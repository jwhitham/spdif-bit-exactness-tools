
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_compressor2 is
end test_compressor2;

architecture test of test_compressor2 is

    subtype t_data is std_logic_vector (15 downto 0);

    signal clock            : std_logic := '0';
    signal done             : std_logic_vector (0 to 3) := (others => '0');
    signal data_in          : t_data := (others => '0');
    signal left_strobe_in   : std_logic := '0';
    signal right_strobe_in  : std_logic := '0';

    constant volume_1       : std_logic_vector (10 downto 0) := (10 => '1', others => '0');

    constant sample_rate            : Natural := 1000;
    constant sample_period          : Time := 1000 ms / sample_rate;
    constant clock_period           : Time := sample_period / 1000;
    constant left_amplitude         : Integer := 20000;
    constant right_amplitude        : Integer := 5000;
    constant near_maximum           : Integer := 16#7ff0#;
    constant true_maximum           : Integer := 16#8000#;

begin

    done (done'Left) <= '1';

    process
    begin
        -- 1MHz clock (one clock every microsecond)
        while done (done'Right) /= '1' loop
            clock <= '1';
            wait for (clock_period / 2.0);
            clock <= '0';
            wait for (clock_period / 2.0);
        end loop;
        wait;
    end process;

    signal_generator : block
        signal sample_phase         : std_logic := '0';
        signal sample_divider       : Natural := 0;
        signal sample_left          : std_logic := '1';
    begin
        process (clock)
        begin
            -- Samples generated, frequency 1kHz (one sample per channel every millisecond)
            -- 500 Hz square wave is generated.
            if clock'event and clock = '1' then
                left_strobe_in <= '0';
                right_strobe_in <= '0';
                data_in <= (others => '0');

                if sample_divider = 0 then
                    if sample_left = '1' then
                        left_strobe_in <= '1';
                        if sample_phase = '1' then
                            data_in <= std_logic_vector (to_signed (-left_amplitude, t_data'Length));
                        else
                            data_in <= std_logic_vector (to_signed (left_amplitude, t_data'Length));
                        end if;
                    else
                        right_strobe_in <= '1';
                        if sample_phase = '1' then
                            data_in <= std_logic_vector (to_signed (-right_amplitude, t_data'Length));
                        else
                            data_in <= std_logic_vector (to_signed (right_amplitude, t_data'Length));
                        end if;
                        sample_phase <= not sample_phase;
                    end if;
                    sample_left <= not sample_left;
                    sample_divider <= Natural ((sample_period / clock_period) / 2) - 1;
                else
                    sample_divider <= sample_divider - 1;
                end if;
            end if;
        end process;
    end block signal_generator;


    stereo_check : for incremental in done'Left + 1 to done'Right generate
        constant delay_size_log_2      : Natural := 5;
        constant test_delay_threshold_level : Real :=
            0.25 + (Real (incremental) / Real (2 ** (delay_size_log_2 + 1)));
        constant one            : std_logic := '1';

        signal data_out         : t_data := (others => '0');
        signal left_strobe_out  : std_logic := '0';
        signal right_strobe_out : std_logic := '0';
        signal sync_in          : std_logic := '0';
        signal sync_out         : std_logic := '0';
    begin
        dut : entity compressor
            generic map (max_amplification => 21.1,
                         sample_rate => sample_rate,
                         decay_rate => 0.1,
                         delay_threshold_level => test_delay_threshold_level,
                         delay_size_log_2 => delay_size_log_2,
                         debug => false)
            port map (
                data_in => data_in,
                left_strobe_in => left_strobe_in,
                right_strobe_in => right_strobe_in,
                enable_in => one,
                data_out => data_out,
                left_strobe_out => left_strobe_out,
                right_strobe_out => right_strobe_out,
                volume_in => volume_1,
                sync_in => sync_in,
                sync_out => sync_out,
                clock_in => clock);

        run_test : process
            variable l           : line;
            variable left, right : Integer := 0;
            variable old_right   : Integer := 0;
        begin
            sync_in <= '0';
            done (incremental) <= '0';
            wait until done (incremental - 1) = '1';

            write (l, String'("Test stereo channels with incremental = "));
            write (l, incremental);
            writeline (output, l);

            -- check input signals
            wait until clock'event and clock = '1' and left_strobe_in = '1';
            assert abs (to_integer (signed (data_in))) = left_amplitude;
            wait until clock'event and clock = '1' and right_strobe_in = '1';
            assert abs (to_integer (signed (data_in))) = right_amplitude;

            -- wait for the other phase before synchronising
            if incremental > (done'Right / 2) then
                wait until clock'event and clock = '1' and left_strobe_in = '1';
                assert abs (to_integer (signed (data_in))) = left_amplitude;
            end if;

            -- await output signals; measure the depth of the delay
            sync_in <= '1';
            for i in 0 to 100 loop
                if sync_out = '1' then
                    write (l, String'("delay depth = "));
                    write (l, i);
                    writeline (output, l);
                    exit;
                end if;
                wait until clock'event and clock = '1' and left_strobe_in = '1';
            end loop;

            for i in 0 to 20 loop
                -- check stereo orientation (left is louder)
                wait until clock'event and clock = '1' and left_strobe_out = '1';
                left := to_integer (signed (data_out));
                assert abs (left) >= near_maximum;
                assert abs (left) <= true_maximum;

                wait until clock'event and clock = '1' and right_strobe_out = '1';
                right := to_integer (signed (data_out));
                assert abs (right) >= ((near_maximum * right_amplitude) / left_amplitude);
                assert abs (right) <= ((true_maximum * right_amplitude) / left_amplitude);

                -- check phase is the same
                if left > 0 then
                    assert right > 0;
                else
                    assert right < 0;
                end if;

                -- check phase is the opposite to last time
                if i > 0 then
                    if right > 0 then
                        assert old_right < 0;
                    else
                        assert old_right > 0;
                    end if;
                end if;

                old_right := right;
            end loop;

            -- check input signals again
            wait until clock'event and clock = '1' and left_strobe_in = '1';
            assert abs (to_integer (signed (data_in))) = left_amplitude;
            wait until clock'event and clock = '1' and right_strobe_in = '1';
            assert abs (to_integer (signed (data_in))) = right_amplitude;

            done (incremental) <= '1';
            wait;
        end process run_test;
    end generate stereo_check;
        


end test;
