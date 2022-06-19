
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
    signal set_amplitude_p  : t_data := (others => '0');
    signal set_amplitude_n  : t_data := (others => '0');
    signal left_strobe_out  : std_logic := '0';
    signal right_strobe_out : std_logic := '0';
    signal peak_level_out   : std_logic_vector (23 downto 0) := (others => '0');
    signal sync_in          : std_logic := '0';
    signal sync_out         : std_logic := '0';
    signal reveal           : std_logic := '0';
    signal sample_counter   : Natural := 0;
    signal clock_counter    : Natural := 0;
    signal square_wave_divider : Natural := 0;
    signal square_wave_negative : std_logic := '0';

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
                if square_wave_negative = '1' then
                    data_in <= set_amplitude_n;
                else
                    data_in <= set_amplitude_p;
                end if;
                square_wave_negative <= not square_wave_negative;
                square_wave_divider <= Natural ((square_wave_period / clock_period) / 2);
            else
                square_wave_divider <= square_wave_divider - 1;
            end if;
        end if;
    end process;

    process
        variable l          : line;
        variable start      : Natural := 0;

        type t_test is record
            amplitude_in    : Integer;
            epsilon         : Natural;
        end record;

        type t_test_table is array (Natural range <>) of t_test;

        constant test_table : t_test_table :=
            ((16#7fff#, 1),
             (16#3fff#, 5),
             (16#1fff#, 10),
             (16#0fff#, 20),
             (16#07ff#, 40),
             (16#03ff#, 80),
             (16#01ff#, 80));
        variable t : t_test;
        constant amplitude_out : Natural := 16#7fff#;
    begin
        done <= '0';

        -- Begin by testing the steady state of the compressor
        for test_index in test_table'Range loop
            write (l, String'(""));
            writeline (output, l);
            t := test_table (test_index);
            write (l, String'("Test steady state amplitude "));
            write (l, t.amplitude_in);
            writeline (output, l);

            -- reset stage
            sync_in <= '0';
            set_amplitude_p <= std_logic_vector (to_signed (t.amplitude_in, t_data'Length));
            if t.amplitude_in = 16#7fff# then
                set_amplitude_n <= std_logic_vector (to_signed (- 1 - t.amplitude_in, t_data'Length));
            else
                set_amplitude_n <= std_logic_vector (to_signed (- t.amplitude_in, t_data'Length));
            end if;
            wait for 1 us;
            wait until data_in'event;
            write (l, String'("Check "));
            write (l, to_integer (signed (set_amplitude_p)));
            write (l, String'(" "));
            write (l, to_integer (signed (set_amplitude_n)));
            writeline (output, l);

            -- check output
            assert abs (to_integer (signed (data_in))) >= (t.amplitude_in - t.epsilon);
            assert abs (to_integer (signed (data_in))) <= (t.amplitude_in + t.epsilon);
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
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            assert abs (to_integer (signed (data_out))) >= (amplitude_out - t.epsilon);
            assert abs (to_integer (signed (data_out))) <= (amplitude_out + t.epsilon);

            -- Check period of left output strobe
            start := clock_counter;
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            assert (clock_counter - start) = (sample_period / clock_period);

            -- Wait for right channel data and check that right strobe
            -- occurs 180 degrees out of phase with the left strobe
            start := clock_counter;
            wait until clock'event and clock = '1' and right_strobe_out = '1';
            assert (clock_counter - start) = ((sample_period / 2.0) / clock_period);

            -- Check sample values and square wave period
            -- Wait for the negative side of the cycle
            wait until clock'event and clock = '1' and left_strobe_out = '1'
                    and to_integer (signed (data_out)) < (amplitude_out - t.epsilon);
            assert to_integer (signed (data_out)) >= (- amplitude_out - t.epsilon);
            assert to_integer (signed (data_out)) <= (- amplitude_out + t.epsilon);
            write (l, String'("Low value "));
            write (l, to_integer (signed (data_out)));
            writeline (output, l);

            -- Wait for the positive side of the cycle
            wait until clock'event and clock = '1' and left_strobe_out = '1'
                    and to_integer (signed (data_out)) > (- amplitude_out + t.epsilon);
            assert to_integer (signed (data_out)) >= (amplitude_out - t.epsilon);
            assert to_integer (signed (data_out)) <= (amplitude_out + t.epsilon);
            start := sample_counter;
            write (l, String'("High value "));
            write (l, to_integer (signed (data_out)));
            writeline (output, l);

            -- Wait for the negative side of the cycle again
            wait until clock'event and clock = '1' and left_strobe_out = '1'
                    and to_integer (signed (data_out)) < (amplitude_out - t.epsilon);
            assert to_integer (signed (data_out)) >= (- amplitude_out - t.epsilon);
            assert to_integer (signed (data_out)) <= (- amplitude_out + t.epsilon);
            write (l, String'("Low value "));
            write (l, to_integer (signed (data_out)));
            writeline (output, l);

            -- Check the period
            assert (sample_counter - start) = ((square_wave_period / sample_period) / 2);
        end loop;
        done <= '1';
        wait;
    end process;


end test;
