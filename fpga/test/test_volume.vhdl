
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_volume is
end test_volume;

architecture test of test_volume is

    subtype t_data is std_logic_vector (15 downto 0);

    signal clock            : std_logic := '0';
    signal done             : std_logic := '0';
    signal data_in          : t_data := (others => '0');
    signal left_strobe_in   : std_logic := '0';
    signal right_strobe_in  : std_logic := '0';

    constant sample_rate    : Natural := 1000;
    constant sample_period  : Time := 1000 ms / sample_rate;
    constant clock_period   : Time := sample_period / 1000;
    constant fpga_freq_mhz  : Natural := 96;

    constant delay_size_log_2       : Natural := 5;
    constant delay_threshold_level  : Real := 0.5;
    constant decay_rate             : Real := Real (sample_rate);

    constant one            : std_logic := '1';

    signal data_out         : t_data := (others => '0');
    signal left_strobe_out  : std_logic := '0';
    signal right_strobe_out : std_logic := '0';
    signal sync_out         : std_logic := '0';
    signal sync_in          : std_logic := '0';
    signal enable           : std_logic := '0';

    constant input_value      : Integer := 12345;

    constant volume_width     : Natural := 11;
    constant volume_one_value : Real := Real (2 ** (volume_width - 1));
    signal volume             : std_logic_vector (volume_width - 1 downto 0) := (others => '0');

begin

    process
    begin
        -- 1MHz clock (one clock every 1000ns)
        while done /= '1' loop
            clock <= '1';
            wait for (clock_period / 2.0);
            clock <= '0';
            wait for (clock_period / 2.0);
        end loop;
        wait;
    end process;

    signal_generator : block
        signal sample_divider       : Natural := 0;
        signal sample_left          : std_logic := '1';
        signal sample_high          : std_logic := '1';
    begin
        process (clock)
        begin
            if clock'event and clock = '1' then
                left_strobe_in <= '0';
                right_strobe_in <= '0';

                if sample_divider = 0 then
                    if sample_left = '1' then
                        left_strobe_in <= '1';
                    else
                        right_strobe_in <= '1';
                        sample_high <= not sample_high;
                    end if;
                    sample_left <= not sample_left;
                    sample_divider <= Natural ((sample_period / clock_period) / 2) - 1;
                    if sample_high = '1' then
                        data_in <= std_logic_vector (to_signed (input_value, 16));
                    else
                        data_in <= std_logic_vector (to_signed (-input_value, 16));
                    end if;
                else
                    sample_divider <= sample_divider - 1;
                end if;
            end if;
        end process;
    end block signal_generator;

    dut : entity compressor
        generic map (debug => false,
                     sample_rate => sample_rate,
                     decay_rate => decay_rate,
                     delay_threshold_level => delay_threshold_level,
                     delay_size_log_2 => delay_size_log_2)
        port map (
            data_in => data_in,
            left_strobe_in => left_strobe_in,
            right_strobe_in => right_strobe_in,
            enable_in => enable,
            data_out => data_out,
            left_strobe_out => left_strobe_out,
            right_strobe_out => right_strobe_out,
            volume_in => volume,
            ready_out => open,
            sync_in => sync_in,
            sync_out => sync_out,
            clock_in => clock);

    run_test : process
        variable l              : line;
        variable expect         : Integer := 0;
        variable value          : Integer := 0;
        variable new_value      : Integer := 0;
        variable measured_max   : Integer := 0;

    begin
        done <= '0';

        write (l, String'("Test volume control"));
        writeline (output, l);

        -- Initially disable the compressor
        enable <= '0';
        sync_in <= '1';

        -- check data is being generated
        wait until clock'event and clock = '1' and left_strobe_in = '1';
        wait until clock'event and clock = '1' and right_strobe_in = '1';

        -- Try various volume settings with compressor disabled
        for i in 0 to 32 loop
            volume <= std_logic_vector (to_unsigned (Natural ((volume_one_value * Real (i)) / 32.0), volume_width));
            wait until clock'event and clock = '1' and (left_strobe_out or right_strobe_out) = '1';
            assert sync_out = '1';
            assert left_strobe_out /= right_strobe_out;
            expect := Integer ((Real (input_value) * Real (i)) / 32.0);
            value := abs (to_integer (signed (data_out)));
            if abs (value - expect) > 1 then
                write (l, String'("Without compressor: Expect "));
                write (l, expect);
                write (l, String'(" got "));
                write (l, value);
                writeline (output, l);
                assert False;
            end if;
        end loop;

        -- Enable compression, the output level should increase rapidly due to decay_rate being large
        enable <= '1';
        value := 0;
        measured_max := 0;
        for i in 1 to 100 loop
            wait until clock'event and clock = '1' and left_strobe_out = '1';
            new_value := abs (to_integer (signed (data_out)));
            assert new_value >= value;
            if new_value = value then
                -- Output level is stable
                write (l, String'("Compression stabilised after "));
                write (l, i);
                writeline (output, l);
                measured_max := new_value;
                exit;
            end if;
            value := new_value;
        end loop;
        assert measured_max > 0;

        -- Try various volume settings with compressor active
        for i in 0 to 32 loop
            volume <= std_logic_vector (to_unsigned (Natural ((volume_one_value * Real (i)) / 32.0), volume_width));
            wait until clock'event and clock = '1' and (left_strobe_out or right_strobe_out) = '1';
            expect := Integer ((Real (measured_max) * Real (i)) / 32.0);
            value := abs (to_integer (signed (data_out)));
            if abs (value - expect) > 1 then
                write (l, String'("With compressor: Expect "));
                write (l, expect);
                write (l, String'(" got "));
                write (l, value);
                writeline (output, l);
                assert False;
            end if;
        end loop;

        write (l, String'("Volume control works as expected"));
        writeline (output, l);
        done <= '1';
        wait;
    end process run_test;

end test;
