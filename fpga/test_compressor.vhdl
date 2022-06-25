
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_compressor is
end test_compressor;

architecture test of test_compressor is

    component compressor is
        generic (max_amplification : Real);
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
        generic map (max_amplification => 21.1)
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

    steady_state_test : process
        variable l          : line;
        variable start      : Natural := 0;

        type t_test is record
            amplitude_in    : Integer;
            amplitude_out   : Integer;
            epsilon         : Natural;
        end record;

        type t_test_table is array (Natural range <>) of t_test;

        constant test_table : t_test_table :=
            ((16#0000#, 16#0000#, 0),
             (16#7fff#, 16#7fff#, 1),
             (16#3fff#, 16#7ffe#, 1),
             (16#03ff#, 16#7fe0#, 1),
             (16#01ff#, 16#7fc0#, 1),
             (16#00ff#, 16#7f80#, 1),
             (16#00fe#, 16#7f80#, 1),   -- amplitude does not quite get maximum amplification (21.1dB)
             (16#00fd#, 16#7f50#, 1),   -- amplitude gets maximum amplification
             (16#007f#, 16#3fe8#, 1),
             (16#0001#, 128, 0)         -- minimum non-zero amplitude
            );  
        variable t : t_test;

        constant initial : Integer := 10000;
        constant boost   : Integer := 11000;

        variable loud, reduced : Integer := 0;

        constant delay_length : Natural := 508;
        constant near_maximum : Natural := 16#7ff8#;
    begin
        done <= '0';

        if False then
            write (l, String'("Test changing amplitude"));
            writeline (output, l);

            -- reset stage
            sync_in <= '0';
            set_amplitude_p <= std_logic_vector (to_signed (initial, t_data'Length));
            set_amplitude_n <= std_logic_vector (to_signed (-initial, t_data'Length));
            wait until square_wave_negative'event;
            wait until square_wave_negative'event;
            wait until clock'event and clock = '1' and left_strobe_in = '1';
            assert abs (to_integer (signed (data_in))) = initial;
            wait until clock'event and clock = '1' and left_strobe_in = '1';
            assert abs (to_integer (signed (data_in))) = initial;

            write (l, String'("end reset"));
            writeline (output, l);

            -- filling stage
            sync_in <= '1';
            wait until sync_out = '1';

            write (l, String'("end fill"));
            writeline (output, l);
            -- check amplitude
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            loud := abs (to_integer (signed (data_out)));
            assert loud >= near_maximum;

            -- make input 10% louder
            write (l, String'("louder samples"));
            writeline (output, l);
            set_amplitude_p <= std_logic_vector (to_signed (boost, t_data'Length));
            set_amplitude_n <= std_logic_vector (to_signed (-boost, t_data'Length));
            wait until square_wave_negative'event;

            -- The next sample is the same high amplitude
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            assert abs (to_integer (signed (data_out))) = loud;

            -- The sample after that is 10% quieter: the peak level has changed
            -- but the input samples are still at the initial level
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            reduced := (loud * initial) / boost;
            assert abs (to_integer (signed (data_out))) < loud;
            assert abs (to_integer (signed (data_out))) >= (reduced - 1);
            assert abs (to_integer (signed (data_out))) <= (reduced + 1);

            -- Wait for the delay to empty
            for i in 1 to (delay_length - 3) loop
                wait until clock'event and clock = '1' and left_strobe_out = '1';
                assert abs (to_integer (signed (data_out))) >= (reduced - 1);
                assert abs (to_integer (signed (data_out))) <= (reduced + 1);
            end loop;

            -- Now we expect the amplitude to increase to maximum again
            -- Allow 4 samples for transition
            for i in 1 to 4 loop
                wait until clock'event and clock = '1' and left_strobe_out = '1';
            end loop;
            
            -- Back to the maximum level
            loud := abs (to_integer (signed (data_out)));
            assert loud >= near_maximum;

            -- Drop input 10%
            write (l, String'("quieter samples"));
            writeline (output, l);
            set_amplitude_p <= std_logic_vector (to_signed (initial, t_data'Length));
            set_amplitude_n <= std_logic_vector (to_signed (-initial, t_data'Length));
            wait until square_wave_negative'event;

            -- Wait for the quieter samples to come through the delay;
            -- during this time, the amplitude may gradually increase
            for i in 1 to (delay_length - 2) loop
                wait until clock'event and clock = '1' and left_strobe_out = '1';
                assert abs (to_integer (signed (data_out))) = loud;
                write (l, String'("delay "));
                write (l, i);
                write (l, String'(" peak "));
                write (l, to_integer (unsigned (peak_level_out)));
                write (l, String'(" data out "));
                write (l, to_integer (signed (data_out)));
                writeline (output, l);
            end loop;

            -- Allow 4 samples for transition to quieter samples
            for i in 1 to 4 loop
                write (l, String'("reaching end of delay"));
                writeline (output, l);
                wait until clock'event and clock = '1' and left_strobe_out = '1';
            end loop;
            
            -- Now the samples are quieter again
            assert abs (to_integer (signed (data_out))) < loud;
            assert abs (to_integer (signed (data_out))) >= (reduced - 1);
            assert abs (to_integer (signed (data_out))) <= (reduced + 1);
        end if;

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
                -- negative is very slightly louder
                set_amplitude_n <= x"8000";
            else
                set_amplitude_n <= std_logic_vector (to_signed (- t.amplitude_in, t_data'Length));
            end if;
            wait until square_wave_negative'event;
            wait until clock'event and clock = '1' and left_strobe_in = '1';

            -- check input
            assert abs (to_integer (signed (data_in))) >= (t.amplitude_in - t.epsilon);
            assert abs (to_integer (signed (data_in))) <= (t.amplitude_in + t.epsilon);

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
            assert (sample_counter - start) >= (delay_length - 2);
            assert (sample_counter - start) <= (delay_length + 2);

            -- Wait for output data
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            assert abs (to_integer (signed (data_out))) >= (t.amplitude_out - t.epsilon);
            assert abs (to_integer (signed (data_out))) <= (t.amplitude_out + t.epsilon);
            if not (abs (to_integer (signed (data_out))) >= (t.amplitude_out - t.epsilon)
            and abs (to_integer (signed (data_out))) <= (t.amplitude_out + t.epsilon)) then
                write (l, String'("Unexpected output "));
                write (l, to_integer (signed (data_out)));
                write (l, String'(" should be within "));
                write (l, t.epsilon);
                write (l, String'(" of "));
                write (l, t.amplitude_out);
                writeline (output, l);
            end if;

            if t.amplitude_out = 0 then
                -- Expect 0 steady state to be maintained
                for i in 1 to Natural (8 * square_wave_period / sample_period) loop
                    wait until clock'event and clock = '1' and left_strobe_out = '1';
                    assert data_out = x"0000";
                    wait until clock'event and clock = '1' and right_strobe_out = '1';
                    assert data_out = x"0000";
                end loop;
            else
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
                        and to_integer (signed (data_out)) < (t.amplitude_out - t.epsilon);
                assert to_integer (signed (data_out)) >= (- t.amplitude_out - t.epsilon);
                assert to_integer (signed (data_out)) <= (- t.amplitude_out + t.epsilon);

                -- Wait for the positive side of the cycle
                wait until clock'event and clock = '1' and left_strobe_out = '1'
                        and to_integer (signed (data_out)) > (- t.amplitude_out + t.epsilon);
                assert to_integer (signed (data_out)) >= (t.amplitude_out - t.epsilon);
                assert to_integer (signed (data_out)) <= (t.amplitude_out + t.epsilon);
                start := sample_counter;
                write (l, String'("High value "));
                write (l, to_integer (signed (data_out)));
                writeline (output, l);

                -- Wait for the negative side of the cycle again
                wait until clock'event and clock = '1' and left_strobe_out = '1'
                        and to_integer (signed (data_out)) < (t.amplitude_out - t.epsilon);
                assert to_integer (signed (data_out)) >= (- t.amplitude_out - t.epsilon);
                assert to_integer (signed (data_out)) <= (- t.amplitude_out + t.epsilon);
                write (l, String'("Low value "));
                write (l, to_integer (signed (data_out)));
                writeline (output, l);

                -- Check the period
                assert (sample_counter - start) = ((square_wave_period / sample_period) / 2);
            end if;
        end loop;
        done <= '1';
        wait;
    end process steady_state_test;

end test;
