
library work;
use work.all;

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
             delay_size_log_2       : Natural := 9;
             subtractor_slice_width : Natural := 8;
             debug                  : Boolean := false);
    port (
        data_in         : in std_logic_vector (15 downto 0);
        left_strobe_in  : in std_logic;
        right_strobe_in : in std_logic;
        data_out        : out std_logic_vector (15 downto 0) := (others => '0');
        peak_level_out  : out std_logic_vector (31 downto 0) := (others => '0');
        left_strobe_out : out std_logic := '0';
        right_strobe_out : out std_logic := '0';
        enable_in       : in std_logic;
        sync_in         : in std_logic;
        sync_out        : out std_logic := '0';
        ready_out       : out std_logic := '0';
        clock_in        : in std_logic
    );
end compressor;

architecture structural of compressor is

    -- audio_bits is the input and output width (two's-complement)
    -- Internally, sign-magnitude is used, and the magnitude is audio_bits - 1 wide.
    constant audio_bits_log_2   : Natural := 4;
    constant audio_bits         : Natural := 2 ** audio_bits_log_2;

    constant peak_bits          : Natural := 24;
    constant fixed_point        : Natural := 1;
    constant peak_audio_high    : Natural := peak_bits - fixed_point - 1;
    constant peak_audio_low     : Natural := peak_audio_high - audio_bits + 2;

    subtype t_fifo_data is std_logic_vector (audio_bits - 1 downto 0);
    subtype t_audio_data is std_logic_vector (audio_bits - 2 downto 0);
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
    --        Store input in FIFO,
    --        Request output from FIFO,
    --      For left channel only:
    --        if peak level division is ready:
    --          peak_level = previous peak level / peak divisor
    --  LOAD_FIFO_INPUT:
    --      abs_compare = absolute input
    --  CLAMP_TO_FIFO_INPUT:
    --      peak_level = max (peak_level, abs_compare)
    --  LOAD_FIFO_OUTPUT:
    --      abs_compare = absolute FIFO output
    --  CLAMP_TO_FIFO_OUTPUT:
    --      peak_level = max (peak_level, abs_compare)
    --  LOAD_MINIMUM:
    --      abs_compare = peak_minimum
    --  CLAMP_TO_MINIMUM:
    --      peak_level = max (peak_level, abs_compare)
    --  LOAD_MAXIMUM:
    --      abs_compare = peak_maximum
    --  CLAMP_TO_MAXIMUM:
    --      peak_level = max (peak_level, abs_compare)
    --  COMPRESS:
    --      signal start of division: input / peak_level
    --      for left channel only:
    --        signal start of division: peak_level / peak_divisor
    --  AWAIT_AUDIO_DIVISION:
    --      Copy divider_finish to appropriate output strobe
    --      Copy divider output to audio output
    --      Flip channel flag
    --      If divider_finish = '1' goto START
    --      
    type t_state is (INIT, FILLING, START,
                     LOAD_FIFO_INPUT,
                     CLAMP_TO_FIFO_INPUT,
                     LOAD_FIFO_OUTPUT,
                     CLAMP_TO_FIFO_OUTPUT,
                     LOAD_MINIMUM,
                     CLAMP_TO_MINIMUM,
                     LOAD_MAXIMUM,
                     CLAMP_TO_MAXIMUM,
                     COMPRESS,
                     AWAIT_AUDIO_DIVISION);

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

    -- This is the maximum value for the peak level
    constant peak_maximum       : t_peak_level := t_peak_level (unsigned (convert_to_bits (1.0)) - 1);

    -- Global registers
    signal left_flag            : std_logic := '1';
    signal minimum_flag         : std_logic := '1';
    signal state                : t_state := INIT;
    signal peak_level           : t_peak_level := (others => '1');
    signal abs_audio_in         : t_audio_data := (others => '0');
    signal peak_divider_done    : std_logic := '0';

    -- Global signals
    signal strobe_in            : std_logic := '0';
    signal thresh_reached       : std_logic := '0';
    signal read_error           : std_logic := '0';
    signal write_error          : std_logic := '0';
    signal fifo_read            : std_logic := '0';
    signal empty_out            : std_logic := '0';
    signal fifo_out             : t_fifo_data := (others => '0');
    signal fifo_in              : t_fifo_data := (others => '0');
    signal reset                : std_logic := '0';
    signal audio_divider_finish : std_logic := '0';
    signal peak_divider_result  : std_logic_vector (peak_bits - 1 downto 0) := (others => '0');
    signal abs_compare          : t_audio_data := (others => '0');
    signal abs_fifo_out         : t_audio_data := (others => '0');

    procedure write_big_number (l : inout line; big_number : std_logic_vector) is
        constant num_bits : Natural := big_number'Length;
        constant nibbles  : Natural := (num_bits + 3) / 4;
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

    -- Incoming data is converted to sign-magnitude form
    sm_in : entity convert_to_sign_magnitude
        generic map (value_width => audio_bits)
        port map (
            value_in => data_in,
            value_out => fifo_in (audio_bits - 2 downto 0),
            value_negative_out => fifo_in (audio_bits - 1));

    -- FIFO is shared by both channels
    delay : entity fifo
        generic map (data_size_log_2 => audio_bits_log_2,
                     addr_size => delay_size_log_2 + 1,
                     threshold_level => delay_threshold_level)
        port map (
            data_in => fifo_in,
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
    abs_fifo_out <= fifo_out (audio_bits - 2 downto 0);
    peak_level_out (peak_bits - 1 downto 0) <= peak_level;

    -- Audio divider
    audio : block
        constant peak_high_bit  : Natural := peak_bits - fixed_point;
        constant top_width      : Natural := peak_high_bit + (audio_bits - 1);
        signal top_value        : std_logic_vector (top_width - 1 downto 0) := (others => '0');
        signal divider_result   : std_logic_vector (top_width - 1 downto 0) := (others => '0');
        signal divider_start    : std_logic := '0';
    begin
        -- Input to divider from FIFO
        top_value (top_width - 1 downto peak_high_bit) <= fifo_out (audio_bits - 2 downto 0);
        top_value (peak_high_bit - 1 downto 0) <= (others => '0');
        divider_start <= '1' when state = COMPRESS else '0';

        div : entity divider
            generic map (top_width => top_width,
                         bottom_width => peak_bits,
                         subtractor_slice_width => subtractor_slice_width)
            port map (
                top_value_in => top_value,
                bottom_value_in => peak_level,
                start_in => divider_start,
                reset_in => reset,
                finish_out => audio_divider_finish,
                result_out => divider_result,
                clock_in => clock_in);

        -- Output from divider
        assert data_out'Length = audio_bits;
        left_strobe_out <= audio_divider_finish and left_flag
                                when (state = AWAIT_AUDIO_DIVISION) else '0';
        right_strobe_out <= audio_divider_finish and not left_flag
                                when (state = AWAIT_AUDIO_DIVISION) else '0';

        sm_out : entity convert_from_sign_magnitude
            generic map (value_width => audio_bits)
            port map (
                value_out => data_out,
                value_in => divider_result (audio_bits - 2 downto 0),
                value_negative_in => fifo_out (audio_bits - 1));

        -- Debug
        process (clock_in)
            variable l : line;
        begin
            if clock_in'event and clock_in = '1' then
                if divider_start = '1' and debug then
                    write (l, String'("begin audio division: "));
                    write_big_number (l, top_value);
                    write (l, String'(" / "));
                    write_big_number (l, peak_level);
                    writeline (output, l);
                end if;
                if audio_divider_finish = '1' and debug then
                    write (l, String'("result of audio division: "));
                    write_big_number (l, divider_result);
                    writeline (output, l);
                end if;
            end if;
        end process;
    end block audio;

    -- Peak divider
    peak : block
        constant top_width      : Natural := (peak_bits * 2) - fixed_point;
        signal top_value        : std_logic_vector (top_width - 1 downto 0) := (others => '0');
        signal bottom_value     : std_logic_vector (peak_bits - 1 downto 0) := peak_divisor;
        signal divider_result   : std_logic_vector (top_width - 1 downto 0) := (others => '0');
        signal divider_start    : std_logic := '0';
        signal divider_finish   : std_logic := '0';
        signal divider_ready    : std_logic := '0';
    begin
        -- Input to divider from peak_level register
        top_value (top_width - 1 downto peak_bits - fixed_point) <= peak_level;
        top_value (peak_bits - fixed_point - 1 downto 0) <= (others => '0');

        -- peak division starts when the left channel enters audio division
        divider_start <= '1' when (state = COMPRESS) and (left_flag = '1') else '0';

        div : entity divider
            generic map (top_width => top_width,
                         bottom_width => peak_bits,
                         subtractor_slice_width => subtractor_slice_width)
            port map (
                top_value_in => top_value,
                bottom_value_in => bottom_value,
                start_in => divider_start,
                reset_in => reset,
                finish_out => divider_finish,
                result_out => divider_result,
                ready_out => divider_ready,
                clock_in => clock_in);

        -- Output from divider
        peak_divider_result <= divider_result (peak_bits - 1 downto 0);

        -- peak_divisor_done indicates that divider_result is valid
        process (clock_in)
            variable l : line;
        begin
            if reset = '1' then
                peak_divider_done <= '0';
            elsif divider_start = '1' then
                if divider_ready = '0' then
                    write (l, String'("Deadline miss! Peak divider is not ready for new data."));
                    writeline (output, l);
                    assert divider_ready = '1';
                else
                    peak_divider_done <= '0';
                end if;
            elsif divider_finish = '1' then
                peak_divider_done <= '1';
            end if;
        end process;

        -- Debug
        process (clock_in)
            variable l : line;
        begin
            if clock_in'event and clock_in = '1' then
                if divider_start = '1' and debug then
                    write (l, String'("begin peak division: "));
                    write_big_number (l, top_value);
                    write (l, String'(" / "));
                    write_big_number (l, bottom_value);
                    writeline (output, l);
                end if;
                if divider_finish = '1' and debug then
                    write (l, String'("result of peak division: "));
                    write_big_number (l, divider_result);
                    writeline (output, l);
                end if;
            end if;
        end process;
    end block peak;

    -- Absolute audio input register (needs to be a register since
    -- the input is only valid when strobe_in = '1')
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if strobe_in = '1' and state = START then
                abs_audio_in <= fifo_in (audio_bits - 2 downto 0);
            end if;
        end if;
    end process;

    -- Comparison input register
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            case state is
                when LOAD_FIFO_INPUT =>
                    abs_compare <= abs_audio_in (audio_bits - 2 downto 0);
                when LOAD_FIFO_OUTPUT =>
                    abs_compare <= abs_fifo_out;
                when LOAD_MINIMUM =>
                    abs_compare <= peak_minimum (peak_audio_high downto peak_audio_low);
                when LOAD_MAXIMUM =>
                    abs_compare <= peak_maximum (peak_audio_high downto peak_audio_low);
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- Peak level register
    process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            case state is
                when INIT | FILLING =>
                    -- Hold at minimum during reset
                    minimum_flag <= '1';
                    peak_level <= (others => '0');
                    peak_level (peak_audio_low - 1 downto 0) <= (others => '1');
                    peak_level (peak_audio_high downto peak_audio_low) <= abs_compare;

                when START =>
                    -- Before processing the left channel, set peak_level to new divider output if available
                    -- Peak decays towards minimum value (maximum amplification)
                    if minimum_flag = '0' and left_flag = '1' and peak_divider_done = '1' then
                        peak_level <= peak_divider_result;
                    end if;

                when CLAMP_TO_FIFO_INPUT | CLAMP_TO_FIFO_OUTPUT | CLAMP_TO_MINIMUM | CLAMP_TO_MAXIMUM =>
                    -- Apply comparison and set
                    if (unsigned (peak_level (peak_audio_high downto peak_audio_low)) <= unsigned (abs_compare)) then
                        -- New 16-bit peak level loaded (reduce amplification)
                        peak_level (peak_audio_high downto peak_audio_low) <= abs_compare;
                        peak_level (peak_audio_low - 1 downto 0) <= (others => '1');
                        if state = CLAMP_TO_MINIMUM then
                            minimum_flag <= '1';
                        else
                            minimum_flag <= '0';
                        end if;
                        if debug then
                            write (l, String'("peak level "));
                            write (l, t_state'Image (state));
                            write (l, String'(": "));
                            write_big_number (l, abs_compare);
                            writeline (output, l);
                        end if;
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- Controller state machine
    controller : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            case state is
                when INIT =>
                    -- Reset state
                    -- (wait for synchronisation and a right input)
                    if sync_in = '1' and right_strobe_in = '1' then
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
                    -- Wait for audio input
                    -- For left channel only, set peak level to new peak level if ready
                    if strobe_in = '1' then
                        state <= LOAD_FIFO_INPUT;
                        if debug then
                            write (l, String'("start with input: "));
                            write_big_number (l, data_in);
                            writeline (output, l);
                        end if;
                    end if;
                    sync_out <= '1';
                when LOAD_FIFO_INPUT =>
                    state <= CLAMP_TO_FIFO_INPUT;
                when CLAMP_TO_FIFO_INPUT =>
                    state <= LOAD_FIFO_OUTPUT;
                when LOAD_FIFO_OUTPUT =>
                    state <= CLAMP_TO_FIFO_OUTPUT;
                when CLAMP_TO_FIFO_OUTPUT =>
                    -- when the compressor is on, this enforces a minimum peak level,
                    -- but when the compressor is off, it forces the peak level to be treated as 1.0.
                    if enable_in = '1' then
                        state <= LOAD_MINIMUM;
                    else
                        state <= LOAD_MAXIMUM;
                    end if;
                when LOAD_MINIMUM =>
                    state <= CLAMP_TO_MINIMUM;
                when CLAMP_TO_MINIMUM =>
                    state <= COMPRESS;
                when LOAD_MAXIMUM =>
                    state <= CLAMP_TO_MAXIMUM;
                when CLAMP_TO_MAXIMUM =>
                    state <= COMPRESS;
                when COMPRESS =>
                    -- start division: absolute FIFO output / peak level
                    -- For left channel only, start division: peak level / peak level divisor
                    state <= AWAIT_AUDIO_DIVISION;
                when AWAIT_AUDIO_DIVISION =>
                    -- When division is complete, flip the channel flag
                    -- Wait for the next audio input
                    if audio_divider_finish = '1' then
                        left_flag <= not left_flag;
                        state <= START;
                    end if;
            end case;

            case state is
                when INIT | FILLING | START =>
                    -- new audio input is expected
                    null;
                when others =>
                    -- new audio input is too early! deadline miss!
                    if strobe_in = '1' then
                        write (l, String'("Deadline miss! New audio data arrived sooner than expected. State is "));
                        write (l, String'(t_state'Image (state)));
                        writeline (output, l);
                        assert strobe_in = '0';
                    end if;
            end case;

            if sync_in = '0' then
                state <= INIT;
            end if;
        end if;
    end process controller;

    ready_out <= '1' when state = INIT or state = FILLING or state = START else '0';

end structural;
