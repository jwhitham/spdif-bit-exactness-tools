
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

    signal clock            : std_logic := '0';
    signal done             : std_logic := '0';
    signal data_in          : std_logic_vector (15 downto 0) := (others => '0');
    signal left_strobe_in   : std_logic := '0';
    signal right_strobe_in  : std_logic := '0';
    signal data_out         : std_logic_vector (15 downto 0) := (others => '0');
    signal out_1, out_2     : std_logic_vector (15 downto 0) := (others => '0');
    signal left_strobe_out  : std_logic := '0';
    signal right_strobe_out : std_logic := '0';
    signal peak_level_out   : std_logic_vector (23 downto 0) := (others => '0');
    signal sync_in          : std_logic := '0';
    signal sync_out         : std_logic := '0';
    signal reveal           : std_logic := '0';
    signal sample_counter   : Natural := 0;
    signal clock_counter    : Natural := 0;

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

    process
    begin
        -- Square wave generated, frequency 1kHz (one cycle every millisecond)
        wait for clock_period;
        while done /= '1' loop
            data_in <= out_1;
            wait for (square_wave_period / 2.0);
            data_in <= out_2;
            wait for (square_wave_period / 2.0);
        end loop;
        wait;
    end process;

    process
        variable l          : line;
        variable start      : Natural := 0;
        variable counter2   : Natural := 0;
        variable previous   : std_logic_vector (15 downto 0) := (others => '0');
    begin
        done <= '0';
        all_proc : for step in 1 to 1 loop
            -- reset stage
            sync_in <= '0';
            out_1 <= x"7fff";
            out_2 <= x"8000";
            wait for 1 us;
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
            assert abs (signed (data_out)) >= 16#7ffe#;

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
            wait until left_strobe_out'event and left_strobe_out = '1' and signed (data_out) < 16#7ffe#;
            start := sample_counter;
            reveal <= '1';
            assert signed (data_out) <= -16#7ffe#;
            wait until left_strobe_out'event and left_strobe_out = '1' and signed (data_out) > -16#7ffe#;
            assert signed (data_out) >= 16#7ffe#;
            wait until left_strobe_out'event and left_strobe_out = '1' and signed (data_out) < 16#7ffe#;
            assert signed (data_out) <= -16#7ffe#;
            assert (sample_counter - start) = (square_wave_period / sample_period);
            assert peak_level_out = x"800000";

            -- Reset - test again with 0.5 amplitude
            sync_in <= '0';
            out_1 <= x"c000";
            out_2 <= x"3fff";
            wait until sync_out'event and sync_out = '0';
            wait until data_in /= x"7fff" and data_in /= x"8000";
            wait for 1 us;
            -- refill
            sync_in <= '1';
            start := sample_counter;
            wait until sync_out = '1';
            write (l, String'("Synchronised after "));
            write (l, sample_counter - start);
            write (l, String'(" samples"));
            writeline (output, l);
            reveal <= '1';

            wait until left_strobe_out'event and left_strobe_out = '1';
            wait until left_strobe_out'event and left_strobe_out = '1';

            write (l, String'("Data value "));
            write (l, to_integer (signed (data_out)));
            writeline (output, l);
            write (l, String'("Peak level register value "));
            write (l, to_integer (unsigned (peak_level_out)));
            writeline (output, l);


        end loop all_proc;
        done <= '1';
        wait;
    end process;


end test;
