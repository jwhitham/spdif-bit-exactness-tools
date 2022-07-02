
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity compressor is
    generic (max_amplification      : Real := 21.1;         -- dB
             sample_rate            : Natural := 48000;     -- Hz
             decay_rate             : Real := 1.0;          -- dB
             delay_threshold_level  : Real := 0.99;
             delay_size_log_2       : Natural := 9);
    port (
        data_in         : in std_logic_vector (15 downto 0);
        left_strobe_in  : in std_logic;
        right_strobe_in : in std_logic;
        data_out        : out std_logic_vector (15 downto 0) := (others => '0');
        left_strobe_out : out std_logic := '0';
        right_strobe_out : out std_logic := '0';
        peak_level_out  : out std_logic_vector (23 downto 0) := (others => '0');
        reveal          : in std_logic;
        sync_in         : in std_logic;
        sync_out        : out std_logic := '0';
        clock_in        : in std_logic
    );
end compressor;

architecture structural of compressor is


    constant audio_bits_log_2   : Natural := 4;
    constant audio_bits         : Natural := 2 ** audio_bits_log_2;
    constant peak_bits          : Natural := 24;
    constant fixed_point        : Natural := 2;
    constant top_width          : Natural := (peak_bits * 2) - fixed_point;
    constant bottom_width       : Natural := peak_bits;
    constant peak_audio_high    : Natural := peak_bits - fixed_point;
    constant peak_audio_low     : Natural := peak_audio_high - audio_bits + 1;

    subtype t_data is std_logic_vector (audio_bits - 1 downto 0);
    subtype t_peak_level is std_logic_vector (peak_bits - 1 downto 0);

    -- The state machine sequence is:
    --
    --  INIT:
    --      (wait for synchronisation and a left input)
    --      If sync_in = '1' and left input received = '1' goto FILLING
    --  FILLING:
    --      (wait for a nearly-full FIFO with an even number of items)
    --      Wait for audio input:
    --        Store input in FIFO,
    --        If FIFO threshold = '0' or right input received = '0' goto FILLING.
    --  START:
    --      Wait for audio input:
    --        Generate absolute value of input,
    --        Store input in FIFO,
    --        Request output from FIFO,
    --  CLAMP_TO_FIFO_INPUT:
    --      peak_level = max (peak_level, absolute input),
    --      Generate absolute value of FIFO output
    --  CLAMP_TO_FIFO_OUTPUT:
    --      peak_level = max (peak_level, absolute FIFO output),
    --  CLAMP_TO_MINIMUM:
    --      peak_level = max (peak_level, peak_minimum),
    --  COMPRESS:
    --      signal start of division: input / peak_level
    --  AWAIT_AUDIO_DIVISION:
    --      If divider_finish = '0' goto S4
    --      Copy divider_finish to appropriate output strobe
    --      Copy divider output to audio output
    --  RAISE_VOLUME:
    --      signal start of division: peak_level / peak_divisor
    --  AWAIT_PEAK_LEVEL_DIVISION:
    --      If divider_finish = '1' goto START
    --      Copy divider output to peak level
    --      
    type t_state is (INIT, FILLING, START,
                     CLAMP_TO_FIFO_INPUT,
                     CLAMP_TO_FIFO_OUTPUT,
                     CLAMP_TO_MINIMUM,
                     COMPRESS,
                     AWAIT_AUDIO_DIVISION,
                     RAISE_VOLUME,
                     AWAIT_PEAK_LEVEL_DIVISION);

    -- Generate control values for the compressor
    -- The peak level is a fixed-point value. The width is peak_bits.
    -- The range of values that can be represented is [-2.0, 2.0 ** fixed_point)
    -- though only positive numbers are used, and rarely larger than 1.0.
    function decibel (db : Real) return Real is
    begin
        return 10.0 ** (db / 10.0);
    end decibel;

    function convert_to_bits (amplitude : Real) return t_peak_level is
    begin
        return t_peak_level (to_unsigned (
            Natural (amplitude * (2.0 ** Real (peak_bits - fixed_point))), peak_bits));
    end convert_to_bits;

    -- These control how quickly the volume is increased, if the sound suddenly becomes quieter.
    -- decay_rate is (by default) 1 decibel per second, based on the given sample rate.
    constant peak_divisor       : t_peak_level := convert_to_bits (decibel (decay_rate / Real (sample_rate)));

    -- This is the minimum sound level that will be amplified to the maximum level
    constant peak_minimum       : t_peak_level := convert_to_bits (decibel (- max_amplification));

    -- Global registers
    signal left_flag            : std_logic := '1';
    signal minimum_flag         : std_logic := '1';
    signal state                : t_state := INIT;
    signal peak_level           : t_peak_level := (others => '1');
    signal abs_audio_in         : t_data := (others => '0');
    signal abs_fifo_out         : t_data := (others => '0');

    -- Global signals
    signal strobe_in            : std_logic := '0';
    signal thresh_reached       : std_logic := '0';
    signal read_error           : std_logic := '0';
    signal write_error          : std_logic := '0';
    signal fifo_read            : std_logic := '0';
    signal empty_out            : std_logic := '0';
    signal fifo_out             : t_data := (others => '0');
    signal reset                : std_logic := '0';
    signal divider_finish       : std_logic := '0';
    signal divider_result       : std_logic_vector (top_width - 1 downto 0) := (others => '0');
    signal abs_compare          : t_data := (others => '0');

    component fifo is
        generic (addr_size : Natural := 12; data_size_log_2 : Natural := 0; threshold_level : Real := 0.5);
        port (
            data_in     : in std_logic_vector ((2 ** data_size_log_2) - 1 downto 0);
            data_out    : out std_logic_vector ((2 ** data_size_log_2) - 1 downto 0) := (others => '0');
            empty_out   : out std_logic := '1';
            full_out    : out std_logic := '0';
            thresh_out  : out std_logic := '0';
            write_error : out std_logic := '0';
            read_error  : out std_logic := '0';
            reset_in    : in std_logic;
            clock_in    : in std_logic;
            write_in    : in std_logic;
            read_in     : in std_logic);
    end component fifo;

    component divider is
        generic (
            top_width    : Natural;
            bottom_width : Natural;
            is_unsigned  : Boolean);
        port (
            top_value_in    : in std_logic_vector (top_width - 1 downto 0);
            bottom_value_in : in std_logic_vector (bottom_width - 1 downto 0);
            start_in        : in std_logic;
            finish_out      : out std_logic := '0';
            result_out      : out std_logic_vector (top_width - 1 downto 0);
            clock_in        : in std_logic
        );
    end component divider;

    procedure write_big_number (l : inout line; big_number : std_logic_vector) is
        constant num_bits : Natural := big_number'Length;
        constant nibbles  : Natural := num_bits / 4;
        constant pad      : Natural := nibbles * 4;
        variable value    : Natural := 0;
    begin
        for j in pad - 1 downto 0 loop
            if j < num_bits then
                if big_number (j + big_number'Right) = '1' then
                    value := value + 1;
                end if;
            end if;
            if (j mod 4) = 0 then
                case value is
                    when 10 => write (l, String'("a"));
                    when 11 => write (l, String'("b"));
                    when 12 => write (l, String'("c"));
                    when 13 => write (l, String'("d"));
                    when 14 => write (l, String'("e"));
                    when 15 => write (l, String'("f"));
                    when others => write (l, value);
                end case;
                value := 0;
            end if;
            value := value * 2;
        end loop;
    end write_big_number;
begin
    reset <= '1' when state = INIT else '0';
    assert data_in'Length = audio_bits;
    assert peak_bits > audio_bits;

    -- FIFO is shared by both channels
    delay : fifo
        generic map (data_size_log_2 => audio_bits_log_2,
                     addr_size => delay_size_log_2 + 1,
                     threshold_level => delay_threshold_level)
        port map (
            data_in => data_in,
            data_out => fifo_out,
            empty_out => empty_out,
            full_out => open,
            thresh_out => thresh_reached,
            write_error => write_error,
            read_error => read_error,
            reset_in => reset,
            clock_in => clock_in,
            write_in => strobe_in,
            read_in => fifo_read);

    assert read_error = '0';
    assert write_error = '0';
    strobe_in <= left_strobe_in or right_strobe_in;
    fifo_read <= strobe_in when state = START else '0';

    -- Divider: used for output and to decay the peak level register
    division : block
        signal divider_top_mux      : std_logic_vector (top_width - 1 downto 0) := (others => '0');
        signal divider_bottom_mux   : std_logic_vector (bottom_width - 1 downto 0) := (others => '0');
        signal divider_start        : std_logic := '0';
    begin
        -- Divider input multiplexer
        process (peak_level, fifo_out, state)
        begin
            divider_top_mux <= (others => '0');
            divider_bottom_mux <= (others => '0');
            divider_start <= '0';

            case state is
                when RAISE_VOLUME =>
                    -- The input is peak_level / peak_divisor
                    divider_top_mux <= (others => '0');
                    divider_top_mux
                        (peak_bits + peak_bits - 1 - fixed_point downto peak_bits - fixed_point)
                            <= peak_level;
                    divider_bottom_mux <= peak_divisor;
                    divider_start <= '1';
                when COMPRESS =>
                    -- The input is FIFO output / peak_level
                    divider_top_mux
                        (top_width - 1 downto peak_bits - fixed_point)
                            <= (others => fifo_out (audio_bits - 1));
                    divider_top_mux
                        (peak_bits + audio_bits - 1 - fixed_point downto peak_bits - fixed_point)
                            <= fifo_out;
                    divider_bottom_mux <= peak_level;
                    divider_start <= '1';
                when others =>
                    null;
            end case;
        end process;

        process (clock_in)
            variable l : line;
            variable match : std_logic_vector (top_width - 1 downto audio_bits) := (others => '0');

        begin
            if clock_in'event and clock_in = '1' then
                if divider_start = '1' then
                    write (l, String'("begin division: "));
                    write_big_number (l, divider_top_mux);
                    write (l, String'(" / "));
                    write_big_number (l, divider_bottom_mux);
                    writeline (output, l);
                end if;
                if divider_finish = '1' then
                    write (l, String'("result of division: "));
                    write_big_number (l, divider_result);
                    writeline (output, l);
                end if;
                if (divider_finish = '1') and (state = AWAIT_AUDIO_DIVISION) then
                    -- The higher bits of the division result = sign extension
                    match := (others => divider_result (audio_bits - 1));
                    if (divider_result (top_width - 1 downto audio_bits) /= match) or reveal = '1' then
                        write (l, String'("divider result = "));
                        write (l, to_integer (signed (divider_result)));
                        if divider_result (top_width - 1 downto audio_bits) /= match then
                            write (l, String'(" (overflow)"));
                        end if;
                        write (l, String'(" out = "));
                        write (l, to_integer (signed (divider_result (audio_bits - 1 downto 0))));
                        write (l, String'(" "));
                        for j in top_width - 1 downto 0 loop
                            if j = audio_bits - 1 then
                                write (l, String'(" "));
                            end if;
                            if divider_result (j) = '1' then
                                write (l, 1);
                            else
                                write (l, 0);
                            end if;
                        end loop;
                        write (l, String'(" top = "));
                        write (l, to_integer (signed (fifo_out)));
                        write (l, String'(" bottom = "));
                        write (l, to_integer (signed (peak_level)));
                        writeline (output, l);
                    end if;
                    assert (divider_result (top_width - 1 downto audio_bits) = match);
                end if;
            end if;
        end process;

        div : divider
            generic map (top_width => top_width, bottom_width => bottom_width,
                         is_unsigned => False)
            port map (
                top_value_in => divider_top_mux,
                bottom_value_in => divider_bottom_mux,
                start_in => divider_start,
                finish_out => divider_finish,
                result_out => divider_result,
                clock_in => clock_in);

    end block division;

    -- Output from divider
    assert data_out'Length = audio_bits;
    data_out <= divider_result (audio_bits - 1 downto 0);
    left_strobe_out <= divider_finish and left_flag when (state = AWAIT_AUDIO_DIVISION) else '0';
    right_strobe_out <= divider_finish and not left_flag when (state = AWAIT_AUDIO_DIVISION) else '0';

    -- Absolute audio input register
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if strobe_in = '1' and state = START then
                if data_in (data_in'Left) = '0' then
                    abs_audio_in <= std_logic_vector (signed (data_in));
                else
                    abs_audio_in <= std_logic_vector (0 - signed (data_in));
                end if;
            end if;
        end if;
    end process;

    -- Absolute FIFO output register
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if fifo_out (fifo_out'Left) = '0' then
                abs_fifo_out <= std_logic_vector (signed (fifo_out));
            else
                abs_fifo_out <= std_logic_vector (0 - signed (fifo_out));
            end if;
        end if;
    end process;

    -- Peak level comparison multiplexer
    abs_compare <= abs_audio_in when state = CLAMP_TO_FIFO_INPUT
                   else abs_fifo_out when state = CLAMP_TO_FIFO_OUTPUT
                   else peak_minimum (peak_audio_high downto peak_audio_low);

    -- Peak level register
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            case state is
                when INIT | FILLING =>
                    -- Hold at minimum during reset
                    minimum_flag <= '1';
                    peak_level <= (others => '0');
                    peak_level (peak_audio_low - 1 downto 0) <= (others => '1');
                    peak_level (peak_audio_high downto peak_audio_low) <= abs_compare;

                when CLAMP_TO_FIFO_INPUT | CLAMP_TO_FIFO_OUTPUT | CLAMP_TO_MINIMUM =>
                    -- Apply comparison and set
                    if (unsigned (peak_level (peak_audio_high downto peak_audio_low)) <= unsigned (abs_compare)) then
                        -- New 16-bit peak level loaded (reduce amplification)
                        peak_level <= (others => '0');
                        peak_level (peak_audio_low - 1 downto 0) <= (others => '1');
                        peak_level (peak_audio_high downto peak_audio_low) <= abs_compare;
                        if state = CLAMP_TO_MINIMUM then
                            minimum_flag <= '1';
                        else
                            minimum_flag <= '0';
                        end if;
                    end if;
                when AWAIT_AUDIO_DIVISION =>
                    -- Set to new divider output
                    -- Peak decays towards minimum value (maximum amplification)
                    if minimum_flag = '0' and divider_finish = '1' then
                        peak_level <= divider_result (peak_bits - 1 downto 0);
                        peak_level (peak_bits - 1 downto peak_audio_high + 1) <= (others => '0'); -- REMOVE!!
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    peak_level_out <= peak_level;

    -- Controller state machine
    controller : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            case state is
                when INIT =>
                    -- Reset state
                    -- (wait for synchronisation and a left input)
                    if sync_in = '1' and left_strobe_in = '1' then
                        state <= FILLING;
                    end if;
                    sync_out <= '0';
                    left_flag <= '1';
                when FILLING =>
                    -- (wait for a nearly-full FIFO with an even number of items)
                    if thresh_reached = '1' and right_strobe_in = '1' then
                        state <= START;
                    end if;
                when START =>
                    -- (wait for audio input)
                    if strobe_in = '1' then
                        state <= CLAMP_TO_FIFO_INPUT;
                        write (l, String'("start with input: "));
                        write_big_number (l, data_in);
                        writeline (output, l);
                    end if;
                    sync_out <= '1';
                when CLAMP_TO_FIFO_INPUT =>
                    -- peak_level = max (peak_level, absolute input)
                    state <= CLAMP_TO_FIFO_OUTPUT;
                    write (l, String'("FIFO output: "));
                    write_big_number (l, fifo_out);
                    writeline (output, l);
                when CLAMP_TO_FIFO_OUTPUT =>
                    -- peak_level = max (peak_level, absolute FIFO output)
                    write (l, String'("peak level clamped to input: "));
                    write_big_number (l, peak_level);
                    writeline (output, l);
                    state <= CLAMP_TO_MINIMUM;
                when CLAMP_TO_MINIMUM =>
                    -- peak_level = max (peak_level, peak_minimum)
                    write (l, String'("peak level clamped to FIFO output: "));
                    write_big_number (l, peak_level);
                    writeline (output, l);
                    state <= COMPRESS;
                when COMPRESS =>
                    -- start division: absolute FIFO output / peak level
                    write (l, String'("peak level clamped to minimum: "));
                    write_big_number (l, peak_level);
                    writeline (output, l);
                    state <= AWAIT_AUDIO_DIVISION;
                when AWAIT_AUDIO_DIVISION =>
                    if divider_finish = '1' then
                        state <= RAISE_VOLUME;
                    end if;
                when RAISE_VOLUME =>
                    -- start division: peak level / peak_divisor
                    state <= AWAIT_PEAK_LEVEL_DIVISION;
                when AWAIT_PEAK_LEVEL_DIVISION =>
                    -- When division is complete, wait for the next audio input, flip the channel flag
                    if divider_finish = '1' then
                        state <= START;
                        left_flag <= not left_flag;
                    end if;
            end case;

            if sync_in = '0' then
                state <= INIT;
            end if;
        end if;
    end process controller;

end structural;
