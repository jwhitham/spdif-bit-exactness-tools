
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_compressor is
end test_compressor;

architecture test of test_compressor is

    component compressor is
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
    end component compressor;

    subtype t_data is std_logic_vector (15 downto 0);

    signal clock            : std_logic := '0';
    signal done             : std_logic := '0';
    signal data_in          : t_data := (others => '0');
    signal left_strobe_in   : std_logic := '0';
    signal right_strobe_in  : std_logic := '0';
    signal data_out         : t_data := (others => '0');
    signal set_amplitude    : t_data := (others => '0');
    signal left_strobe_out  : std_logic := '0';
    signal right_strobe_out : std_logic := '0';
    signal peak_level_out   : std_logic_vector (23 downto 0) := (others => '0');
    signal sync_in          : std_logic := '0';
    signal sync_out         : std_logic := '0';
    signal reveal           : std_logic := '0';
    signal sample_counter   : Natural := 0;
    signal clock_counter    : Natural := 0;
    signal square_wave_divider : Natural := 0;

    constant clock_period   : Time := 10.0 ns;
    constant sample_period  : Time := 20.0 us;
    constant square_wave_period  : Time := 1.0 ms;

begin
    dut : compressor
        port map (
            data_in => data_in,
            left_strobe_in => left_strobe_in,
            right_strobe_in => right_strobe_in,
            data_out => data_out,
            left_strobe_out => left_strobe_out,
            right_strobe_out => right_strobe_out,
            peak_level_out => peak_level_out,
            reveal => reveal,
            sync_in => sync_in,
            sync_out => sync_out,
            clock_in => clock);

    process
    begin
        -- 100MHz clock (one clock every 10 nanoseconds)
        clock_counter <= 0;
        while done /= '1' loop
            clock <= '1';
            clock_counter <= clock_counter + 1;
            wait for (clock_period / 2.0);
            clock <= '0';
            wait for (clock_period / 2.0);
        end loop;
        wait;
    end process;

    process
    begin
        -- Audio data arriving at 50kHz sample rate (one sample per channel every 20 microseconds)
        left_strobe_in <= '0';
        right_strobe_in <= '0';
        sample_counter <= 0;
        wait for clock_period;
        while done /= '1' loop
            left_strobe_in <= '1';
            sample_counter <= sample_counter + 1;
            wait for clock_period;
            left_strobe_in <= '0';
            wait for ((sample_period / 2.0) - clock_period);
            right_strobe_in <= '1';
            wait for clock_period;
            right_strobe_in <= '0';
            wait for ((sample_period / 2.0) - clock_period);
        end loop;
        wait;
    end process;

--    process
--    begin
--        -- Square wave generated, frequency 1kHz (one cycle every millisecond)
--        wait for clock_period;
--        while done /= '1' loop
--            data_in <= std_logic_vector (signed (set_amplitude));
--            wait for (square_wave_period / 2.0);
--            data_in <= std_logic_vector (-1 - signed (set_amplitude));
--            wait for (square_wave_period / 2.0);
--        end loop;
--        wait;
--    end process;
--
--    
    process (clock)
    begin
        -- Square wave generated, frequency 1kHz (one cycle every millisecond)
        if clock'event and clock = '1' then
            if square_wave_divider = 0 then
                if data_in (data_in'Left) = '0' then
                    data_in <= std_logic_vector (-1 - signed (set_amplitude));
                else
                    data_in <= std_logic_vector (signed (set_amplitude));
                end if;
                square_wave_divider <= Natural ((square_wave_period / clock_period) / 2);
            else
                square_wave_divider <= square_wave_divider - 1;
            end if;
        end if;
    end process;

    process
        variable l          : line;
        variable start      : Natural := 0;

        type t_test_table is array (Natural range <>) of Natural;

        constant epsilon    : Natural := 1;
        constant test_table : t_test_table := (16#7fff#, 16#3fff#);
        variable amplitude_in  : Natural := 0;
        constant amplitude_out : Natural := 16#7fff#;
    begin
        done <= '0';

        -- Begin by testing the steady state of the compressor
        for test_index in test_table'Range loop
            write (l, String'("Test steady state amplitude "));
            write (l, test_table (test_index));
            writeline (output, l);

            -- reset stage
            sync_in <= '0';
            amplitude_in := test_table (test_index);
            set_amplitude <= std_logic_vector (to_unsigned (amplitude_in, t_data'Length));
            wait for 1 us;
            wait until data_in'event;

            -- check output
            assert abs (to_integer (signed (data_in))) >= (amplitude_in - epsilon);
            assert abs (to_integer (signed (data_in))) <= (amplitude_in + epsilon);
            write (l, String'("Peak level register value "));
            write (l, to_integer (unsigned (peak_level_out)));
            writeline (output, l);

            -- filling stage: leave reset
            sync_in <= '1';
            start := sample_counter;
            wait until sync_out = '1';
            write (l, String'("Synchronised after "));
            write (l, sample_counter - start);
            write (l, String'(" samples"));
            writeline (output, l);
            write (l, String'("Peak level register value "));
            write (l, to_integer (unsigned (peak_level_out)));
            writeline (output, l);
            
            -- Synchronisation is expected after around 500 samples
            assert (sample_counter - start) >= 500;
            assert (sample_counter - start) <= 510;

            -- Wait for output data
            wait until left_strobe_out'event and left_strobe_out = '1';
            assert abs (to_integer (signed (data_out))) >= (amplitude_out - epsilon);
            assert abs (to_integer (signed (data_out))) <= (amplitude_out + epsilon);

            -- Check period of left output strobe
            start := clock_counter;
            wait until left_strobe_out'event and left_strobe_out = '1';
            assert (clock_counter - start) = (sample_period / clock_period);

            -- Wait for right channel data and check that right strobe
            -- occurs 180 degrees out of phase with the left strobe
            start := clock_counter;
            wait until right_strobe_out'event and right_strobe_out = '1';
            assert (clock_counter - start) = ((sample_period / 2.0) / clock_period);

            -- Check sample values and square wave period
            -- Wait for the negative side of the cycle
            wait until left_strobe_out'event and left_strobe_out = '1'
                    and to_integer (signed (data_out)) < (amplitude_out - epsilon);
            start := sample_counter;
            assert to_integer (signed (data_out)) >= (- amplitude_out - epsilon);
            assert to_integer (signed (data_out)) <= (- amplitude_out + epsilon);

            -- Wait for the positive side of the cycle
            wait until left_strobe_out'event and left_strobe_out = '1'
                    and to_integer (signed (data_out)) > (- amplitude_out + epsilon);
            assert to_integer (signed (data_out)) >= (amplitude_out - epsilon);
            assert to_integer (signed (data_out)) <= (amplitude_out + epsilon);

            -- Wait for the negative side of the cycle again
            wait until left_strobe_out'event and left_strobe_out = '1'
                    and to_integer (signed (data_out)) < (amplitude_out - epsilon);
            assert to_integer (signed (data_out)) >= (- amplitude_out - epsilon);
            assert to_integer (signed (data_out)) <= (- amplitude_out + epsilon);

            -- Check the period
            assert (sample_counter - start) = (square_wave_period / sample_period);
        end loop;
        done <= '1';
        wait;
    end process;


end test;
