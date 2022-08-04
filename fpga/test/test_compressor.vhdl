
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_compressor is
end test_compressor;

architecture test of test_compressor is

    subtype t_data is std_logic_vector (15 downto 0);

    signal clock                    : std_logic := '0';
    signal done                     : std_logic := '0';
    signal data_in                  : t_data := (others => '0');
    signal left_strobe_in           : std_logic := '0';
    signal right_strobe_in          : std_logic := '0';
    signal data_out                 : t_data := (others => '0');
    signal set_amplitude_p          : t_data := (others => '0');
    signal set_amplitude_n          : t_data := (others => '0');
    signal left_strobe_out          : std_logic := '0';
    signal right_strobe_out         : std_logic := '0';
    signal sync_in                  : std_logic := '0';
    signal sync_out                 : std_logic := '0';
    signal sample_counter           : Natural := 0;
    signal clock_counter            : Natural := 0;
    signal square_wave_negative     : std_logic := '0';
    signal fifo_error_out           : std_logic := '0';
    signal over_error_out           : std_logic := '0';

    constant one                    : std_logic := '1';
    constant sample_rate            : Natural := 1000;
    constant volume_1       : std_logic_vector (10 downto 0) := (10 => '1', others => '0');

    constant sample_period          : Time := 1000 ms / sample_rate;
    constant clock_period           : Time := sample_period / 1000;
    constant square_wave_period     : Time := sample_period * 10;

    constant delay_size_log_2       : Natural := 5;
    constant delay_threshold_level  : Real := 0.5;
    constant decay_rate             : Real := 0.1;

    constant max_samples_in_delay   : Natural := 
            1 + Natural (Real (2 ** delay_size_log_2) * delay_threshold_level);

begin
    dut : entity compressor
        generic map (max_amplification => 21.1,
                     sample_rate => sample_rate,
                     decay_rate => decay_rate,
                     delay_threshold_level => delay_threshold_level,
                     delay_size_log_2 => delay_size_log_2,
                     debug => false)
        port map (
            data_in => data_in,
            left_strobe_in => left_strobe_in,
            right_strobe_in => right_strobe_in,
            data_out => data_out,
            enable_in => one,
            volume_in => volume_1,
            left_strobe_out => left_strobe_out,
            right_strobe_out => right_strobe_out,
            fifo_error_out => fifo_error_out,
            over_error_out => over_error_out,
            sync_in => sync_in,
            sync_out => sync_out,
            clock_in => clock);

    assert fifo_error_out = '0';
    assert over_error_out = '0';

    process
    begin
        -- 1MHz clock (one clock every microsecond)
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

    signal_generator : block
        signal square_wave_divider  : Natural := 0;
        signal square_wave_out      : t_data := (others => '0');
        signal sample_divider       : Natural := 0;
        signal sample_left          : std_logic := '1';
    begin
        process (clock)
        begin
            -- Samples generated, frequency 1kHz (one sample per channel every millisecond)
            if clock'event and clock = '1' then
                left_strobe_in <= '0';
                right_strobe_in <= '0';

                if sample_divider = 0 then
                    if sample_left = '1' then
                        left_strobe_in <= '1';
                        sample_counter <= sample_counter + 1;
                    else
                        right_strobe_in <= '1';
                    end if;

                    sample_left <= not sample_left;
                    sample_divider <= Natural ((sample_period / clock_period) / 2) - 1;
                else
                    sample_divider <= sample_divider - 1;
                end if;
            end if;
        end process;

        data_in <= square_wave_out when left_strobe_in = '1'
                   else square_wave_out when right_strobe_in = '1'
                   else (others => '1');

        process (clock)
        begin
            -- Square wave generated, frequency 100Hz (one cycle every 10 milliseconds)
            if clock'event and clock = '1' then
                if square_wave_divider = 0 then
                    if square_wave_negative = '1' then
                        square_wave_out <= set_amplitude_n;
                    else
                        square_wave_out <= set_amplitude_p;
                    end if;
                    square_wave_negative <= not square_wave_negative;
                    square_wave_divider <= Natural ((square_wave_period / clock_period) / 2) - 1;
                else
                    square_wave_divider <= square_wave_divider - 1;
                end if;
            end if;
        end process;
    end block signal_generator;

    all_tests : process
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
             (16#3fff#, 16#7ffe#, 0),
             (16#03ff#, 16#7fe0#, 0),
             (16#01ff#, 16#7fc0#, 0),
             (16#00ff#, 16#7f80#, 0),
             (16#00fe#, 16#7f80#, 1),   -- amplitude does not quite get maximum amplification (21.1dB)
             (16#00fd#, 16#7eff#, 1),   -- amplitude gets maximum amplification
             (16#00fc#, 16#7e7e#, 1),   -- amplitude gets maximum amplification
             (16#00fb#, 16#7dfe#, 1), 
             (16#007f#, 16#3fbf#, 1),
             (16#0001#, 16#0080#, 0)    -- minimum non-zero amplitude
            );  
        variable t : t_test;

        constant initial : Integer := 10000;
        constant boost   : Integer := 11000;
        constant epsilon : Real := 0.001;

        variable loud, reduced : Integer := 0;
        variable reduced_plus_1_db : Integer := 0;
        variable reduced_plus_x_db : Integer := 0;

        constant near_maximum : Natural := 16#7ff8#;
    begin
        done <= '0';

        if true then
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
            assert abs (to_integer (signed (data_out))) = loud;

            -- The next sample is 10% quieter: the peak level has changed
            -- but the input samples are still at the initial level
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            reduced := (loud * initial) / boost;
            assert abs (to_integer (signed (data_out))) < loud;
            assert abs (to_integer (signed (data_out))) >= (reduced - 1);
            assert abs (to_integer (signed (data_out))) <= (reduced + 1);

            -- Wait for the delay to empty
            for i in 1 to max_samples_in_delay - 1 loop
                wait until clock'event and clock = '1' and left_strobe_out = '1';
                assert abs (to_integer (signed (data_out))) >= (reduced - 1);
                assert abs (to_integer (signed (data_out))) <= (reduced + 1);
            end loop;

            -- Now we expect the amplitude to increase to maximum again
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            loud := abs (to_integer (signed (data_out)));
            assert loud >= near_maximum;

            -- Drop input 10%
            write (l, String'("quieter samples"));
            writeline (output, l);
            set_amplitude_p <= std_logic_vector (to_signed (initial, t_data'Length));
            set_amplitude_n <= std_logic_vector (to_signed (-initial, t_data'Length));
            wait until square_wave_negative'event;

            -- Wait for the quieter samples to come through the delay
            for i in 1 to max_samples_in_delay loop
                wait until clock'event and clock = '1' and left_strobe_out = '1';
                assert abs (to_integer (signed (data_out))) = loud;
            end loop;

            wait until clock'event and clock = '1' and left_strobe_out = '1';
            write (l, String'("reaching end of delay: "));
            write (l, to_integer (signed (data_out)));
            write (l, String'(" expect "));
            write (l, reduced);
            writeline (output, l);
            
            -- Now the samples are quieter again; though the volume has grown while
            -- they were in the delay
            assert abs (to_integer (signed (data_out))) < loud;
            assert abs (to_integer (signed (data_out))) > reduced;

            -- Wait for the gradual recovery of the original volume
            -- After one simulated second, the volume should have grown by
            -- approximately decay_rate decibels (within 1% is permitted due to rounding errors).
            for i in 1 to sample_rate - max_samples_in_delay loop
                wait until clock'event and clock = '1' and left_strobe_out = '1';
            end loop;

            assert abs (to_integer (signed (data_out))) < loud;

            reduced_plus_1_db := Integer (Real (reduced) * (10.0 ** (decay_rate / 10.0)));
            -- note: Ensure decay_rate is chosen so that the volume gain over 1 second does not exceed
            -- the maximum amplification
            assert reduced_plus_1_db < (loud - 10);
            assert Real (abs (to_integer (signed (data_out)))) >= Real (reduced_plus_1_db) * (1.0 - epsilon);
            assert Real (abs (to_integer (signed (data_out)))) <= Real (reduced_plus_1_db) * (1.0 + epsilon);

            write (l, String'("getting louder: "));
            write (l, reduced);
            write (l, String'(" -> "));
            write (l, abs (to_integer (signed (data_out))));
            write (l, String'(" expect "));
            write (l, reduced_plus_1_db);
            writeline (output, l);

            -- Expect the peak level to eventually return to the loud level
            for j in 1 to 10 loop
                reduced := abs (to_integer (signed (data_out)));

                for i in 1 to sample_rate loop
                    wait until clock'event and clock = '1' and left_strobe_out = '1';
                end loop;

                reduced_plus_x_db := Integer (Real (reduced) * (10.0 ** (decay_rate / 10.0)));
                if reduced_plus_x_db >= loud then
                    reduced_plus_x_db := loud;
                end if;
                assert Real (abs (to_integer (signed (data_out)))) >= Real (reduced_plus_x_db) * (1.0 - epsilon);
                assert Real (abs (to_integer (signed (data_out)))) <= Real (reduced_plus_x_db) * (1.0 + epsilon);

                write (l, String'("getting louder again: "));
                write (l, reduced);
                write (l, String'(" -> "));
                write (l, abs (to_integer (signed (data_out))));
                write (l, String'(" expect "));
                write (l, reduced_plus_x_db);
                writeline (output, l);

                exit when reduced_plus_x_db >= loud;
            end loop;
            assert reduced_plus_x_db >= loud;
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
            
            -- Synchronisation is expected after filling the delay
            assert (sample_counter - start) >= (max_samples_in_delay - 2);
            assert (sample_counter - start) <= (max_samples_in_delay + 2);

            -- Wait for output data
            wait until clock'event and clock = '1' and left_strobe_out = '1';
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
            assert abs (to_integer (signed (data_out))) >= (t.amplitude_out - t.epsilon);
            assert abs (to_integer (signed (data_out))) <= (t.amplitude_out + t.epsilon);

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
    end process all_tests;

end test;
