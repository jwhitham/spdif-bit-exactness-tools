
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity compressor is
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
    constant fixed_point        : Natural := 1;
    constant top_width          : Natural := audio_bits + peak_bits - fixed_point;
    constant bottom_width       : Natural := peak_bits;
    constant num_channels       : Natural := 2;

    subtype t_data is std_logic_vector (audio_bits - 1 downto 0);
    subtype t_channel is Natural range 0 to num_channels - 1;
    subtype t_bit_per_channel is std_logic_vector (num_channels - 1 downto 0);
    type t_data_per_channel is array (Natural range 0 to num_channels - 1) of t_data;
    subtype t_peak_level is std_logic_vector (peak_bits - 1 downto 0);

    type t_state is (INIT, FILLING, START, FIFO_POP,
                     DIVIDE_AUDIO, WAIT_FOR_AUDIO,
                     DIVIDE_PEAK, WAIT_FOR_PEAK);

    -- Generate control values for the compressor
    -- The peak level is a fixed-point value. The width is peak_bits.
    -- The range of values that can be represented is [0.0, 2.0 ** fixed_point)
    function decibel (db : Real) return Real is
    begin
        return 10.0 ** (db / 10.0);
    end decibel;

    function convert_to_bits (amplitude : Real) return t_peak_level is
    begin
        return t_peak_level (to_unsigned (
            Natural (amplitude * (2.0 ** Real (peak_bits - fixed_point))), peak_bits));
    end convert_to_bits;

    constant sample_rate        : Natural := 44100; -- assumed
    constant peak_divisor       : t_peak_level := convert_to_bits (decibel (1.0 / Real (sample_rate)));
    constant peak_minimum       : t_peak_level := convert_to_bits (decibel (-40.0));
    constant peak_maximum       : t_peak_level := convert_to_bits (1.0);

    constant zero_bits_per_channel : t_bit_per_channel := (others => '0');
    constant one_bits_per_channel : t_bit_per_channel := (others => '1');

    -- Global registers
    signal current_channel      : t_channel := 0;
    signal state                : t_state := INIT;
    signal peak_level           : t_peak_level := (others => '1');

    -- Global signals
    signal strobe_in            : t_bit_per_channel := zero_bits_per_channel;
    signal thresh_reached       : t_bit_per_channel := zero_bits_per_channel;
    signal read_error           : t_bit_per_channel := zero_bits_per_channel;
    signal write_error          : t_bit_per_channel := zero_bits_per_channel;
    signal read_delayed         : t_bit_per_channel := zero_bits_per_channel;
    signal delay_out            : t_data_per_channel := (others => (others => '0'));
    signal reset                : std_logic := '0';
    signal divider_finish       : std_logic := '0';
    signal divider_result       : std_logic_vector (top_width - 1 downto 0) := (others => '0');

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
            bottom_width : Natural);
        port (
            top_value_in    : in std_logic_vector (top_width - 1 downto 0);
            bottom_value_in : in std_logic_vector (bottom_width - 1 downto 0);
            start_in        : in std_logic;
            finish_out      : out std_logic := '0';
            result_out      : out std_logic_vector (top_width - 1 downto 0);
            clock_in        : in std_logic
        );
    end component divider;

begin
    reset <= '1' when state = INIT else '0';
    strobe_in (0) <= left_strobe_in;
    strobe_in (1) <= right_strobe_in;
    assert data_in'Length = audio_bits;

    -- Delay lines, one per channel
    channel : for channel_num in 0 to num_channels - 1 generate
    begin
        delay : fifo
            generic map (data_size_log_2 => audio_bits_log_2, addr_size => 9, threshold_level => 0.99)
            port map (
                data_in => data_in,
                data_out => delay_out (channel_num),
                empty_out => open,
                full_out => open,
                thresh_out => thresh_reached (channel_num),
                write_error => write_error (channel_num),
                read_error => read_error (channel_num),
                reset_in => reset,
                clock_in => clock_in,
                write_in => strobe_in (channel_num),
                read_in => read_delayed (channel_num));
    end generate channel;

    -- Divider: used for output and to decay the peak level register
    division : block
        signal divider_top_mux      : std_logic_vector (top_width - 1 downto 0) := (others => '0');
        signal divider_bottom_mux   : std_logic_vector (bottom_width - 1 downto 0) := (others => '0');
        signal divider_start        : std_logic := '0';
    begin
        process (read_delayed, peak_level, delay_out, current_channel, state)
        begin
            divider_top_mux <= (others => '0');
            divider_top_mux (top_width - 1 downto top_width - audio_bits) <= delay_out (current_channel);
            divider_bottom_mux <= peak_level;
            divider_start <= '0';

            case state is
                when DIVIDE_AUDIO =>
                    divider_start <= '1';
                when DIVIDE_PEAK =>
                    divider_top_mux (top_width - 1 downto top_width - peak_bits) <= peak_level;
                    divider_bottom_mux <= peak_divisor;
                    divider_start <= '1';
                when others =>
                    null;
            end case;
        end process;

        div : divider
            generic map (top_width => top_width, bottom_width => bottom_width)
            port map (
                top_value_in => divider_top_mux,
                bottom_value_in => divider_bottom_mux,
                start_in => divider_start,
                finish_out => divider_finish,
                result_out => divider_result,
                clock_in => clock_in);

        process (clock_in)
            variable l : line;
            constant zero : std_logic_vector (top_width - 1 downto audio_bits) := (others => '0');
        begin
            if clock_in'event and clock_in = '1' then
                if (divider_finish = '1') and (state = WAIT_FOR_AUDIO) then
                    -- The higher bits of the division result should all be zero - otherwise, it's an overflow
                    if (divider_result (top_width - 1 downto audio_bits) /= zero) or reveal = '1' then
                        write (l, String'("divider result = "));
                        write (l, to_integer (unsigned (divider_result)));
                        write (l, String'(" top = "));
                        write (l, to_integer (unsigned (delay_out (current_channel))));
                        write (l, String'(" bottom = "));
                        write (l, to_integer (unsigned (peak_level)));
                        writeline (output, l);
                    end if;
                    assert (divider_result (top_width - 1 downto audio_bits) = zero);
                end if;
            end if;
        end process;


    end block division;

    -- Output
    assert data_out'Length = audio_bits;
    data_out <= divider_result (audio_bits - 1 downto 0);
    left_strobe_out <= divider_finish when (state = WAIT_FOR_AUDIO) and (current_channel = 0) else '0';
    right_strobe_out <= divider_finish when (state = WAIT_FOR_AUDIO) and (current_channel = 1) else '0';

    -- Peak level register
    peak : block
        constant peak_audio_high    : Natural := peak_bits - fixed_point;
        constant peak_audio_low     : Natural := peak_audio_high - audio_bits + 1;
        constant zero_pad           : std_logic_vector (fixed_point - 1 downto 0) := (others => '0');
        signal set_maximum_peak     : std_logic := '0';
        signal set_minimum_peak     : std_logic := '0';
        signal abs_data_in          : std_logic_vector (audio_bits - 1 downto 0) := (others => '0');
    begin
        process (clock_in)
        begin
            if clock_in'event and clock_in = '1' then
                if reset = '1' or set_minimum_peak = '1' then
                    -- Peak is at the minimum value (maximum amplification)
                    peak_level <= peak_minimum;

                elsif set_maximum_peak = '1' then
                    -- New 16-bit peak level loaded (reduce amplification)
                    peak_level <= (others => '0');
                    peak_level (peak_audio_high downto peak_audio_low) <= abs_data_in;

                elsif (divider_finish = '1') and (state = WAIT_FOR_PEAK) then
                    -- Peak decays towards minimum value (maximum amplification)
                    peak_level <= divider_result (peak_bits - 1 downto 0);
                end if;

                -- store 16-bit absolute value of incoming audio data
                if reset = '1' then
                    abs_data_in <= (others => '0');
                elsif strobe_in /= zero_bits_per_channel then
                    if data_in (data_in'Left) = '0' then
                        abs_data_in <= std_logic_vector (signed (data_in) + 1);
                    else
                        abs_data_in <= std_logic_vector (1 - signed (data_in));
                    end if;
                end if;

                -- Compare to data input (setting new maximum)
                set_maximum_peak <= '0';
                if peak_level (peak_bits - 1 downto peak_audio_low) <= (zero_pad & abs_data_in) then
                    set_maximum_peak <= '1';
                end if;

                -- Compare to minimum
                set_minimum_peak <= '0';
                if peak_level (peak_bits - 1 downto peak_audio_low) <
                        peak_minimum (peak_bits - 1 downto peak_audio_low) then
                    set_minimum_peak <= '1';
                end if;
            end if;
        end process;
    end block peak;

    peak_level_out <= peak_level;

    controller : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            read_delayed <= zero_bits_per_channel;

            case state is
                when INIT =>
                    -- Reset state
                    state <= FILLING;
                    sync_out <= '0';
                    current_channel <= 0;
                when FILLING =>
                    -- Wait for both delay FIFOs to fill
                    if thresh_reached = one_bits_per_channel then
                        state <= START;
                        current_channel <= 0;
                    end if;
                when START =>
                    -- Wait for new data in the current channel
                    -- in order to maintain the FIFO level
                    if strobe_in (current_channel) = '1' then
                        read_delayed (current_channel) <= '1';
                        state <= FIFO_POP;
                    end if;
                when FIFO_POP =>
                    -- Data removed from FIFO
                    state <= DIVIDE_AUDIO;
                when DIVIDE_AUDIO =>
                    -- Division begins
                    state <= WAIT_FOR_AUDIO;
                when WAIT_FOR_AUDIO =>
                    -- Wait for division to finish
                    if divider_finish = '1' then
                        if current_channel /= (num_channels - 1) then
                            current_channel <= current_channel + 1;
                            state <= START;
                        else
                            current_channel <= 0;
                            state <= DIVIDE_PEAK;
                        end if;
                    end if;
                when DIVIDE_PEAK =>
                    -- Division begins
                    state <= WAIT_FOR_PEAK;
                when WAIT_FOR_PEAK =>
                    -- Wait for division to finish
                    if divider_finish = '1' then
                        state <= START;
                        sync_out <= '1';
                    end if;
            end case;

            if sync_in = '0'
                    or read_error /= zero_bits_per_channel
                    or write_error /= zero_bits_per_channel then
                state <= INIT;
            end if;
        end if;
    end process controller;

    assert read_error = zero_bits_per_channel;
    assert write_error = zero_bits_per_channel;

end structural;
