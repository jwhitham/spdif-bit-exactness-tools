
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_measure is
end test_measure;

architecture test of test_measure is

    subtype t_data is std_logic_vector (15 downto 0);

    signal clock            : std_logic := '0';
    signal done             : std_logic := '0';
    signal data_in          : t_data := (others => '0');
    signal left_strobe_in   : std_logic := '0';
    signal right_strobe_in  : std_logic := '0';
    signal enable_strobes   : std_logic := '0';

    constant sample_rate            : Natural := 1000;
    constant sample_period          : Time := 1000 ms / sample_rate;
    constant clock_period           : Time := sample_period / 1000;

    signal data_out         : t_data := (others => '0');
    signal left_strobe_out  : std_logic := '0';
    signal right_strobe_out : std_logic := '0';
    signal sync_in          : std_logic := '0';
    signal sync_out         : std_logic := '0';
begin

    process
    begin
        -- 1MHz clock (one clock every microsecond)
        while done /= '1' loop
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
            if clock'event and clock = '1' then
                left_strobe_in <= '0';
                right_strobe_in <= '0';

                if sample_divider = 0 then
                    if enable_strobes = '1' then
                        if sample_left = '1' then
                            left_strobe_in <= '1';
                        else
                            right_strobe_in <= '1';
                            sample_phase <= not sample_phase;
                        end if;
                        sample_left <= not sample_left;
                        sample_divider <= Natural ((sample_period / clock_period) / 2) - 1;
                    end if;
                else
                    sample_divider <= sample_divider - 1;
                end if;
            end if;
        end process;
    end block signal_generator;

    data_in <= (15 => '1', 14 => '1', others => '0');

    dut : entity compressor
        port map (
            data_in => data_in,
            left_strobe_in => left_strobe_in,
            right_strobe_in => right_strobe_in,
            data_out => data_out,
            left_strobe_out => left_strobe_out,
            right_strobe_out => right_strobe_out,
            sync_in => sync_in,
            sync_out => sync_out,
            clock_in => clock);

    run_test : process
        variable l  : line;
        variable ok : Boolean := false;
        variable first_left_in   : Natural := 0;
        variable first_right_in  : Natural := 0;
        variable first_left_out  : Natural := 0;
        variable first_right_out : Natural := 0;
    begin
        sync_in <= '0';
        enable_strobes <= '1';
        done <= '0';

        write (l, String'("Test timing"));
        writeline (output, l);

        -- ensure strobes are working
        wait until clock'event and clock = '1' and left_strobe_in = '1';
        wait until clock'event and clock = '1' and right_strobe_in = '1';

        -- fill the compressor, await outputs
        sync_in <= '1';
        wait until clock'event and clock = '1' and left_strobe_out = '1';
        wait until clock'event and clock = '1' and right_strobe_out = '1';

        -- stop strobes, wait for the compressor to stop output
        enable_strobes <= '0';
        wait for sample_period * 4;

        -- how long between restarting input and receiving output?
        enable_strobes <= '1';
        for clock_cycle in 1 to (2 * (sample_period / clock_period)) loop
            wait until clock'event and clock = '1';
            if left_strobe_in = '1' then
                if first_left_in = 0 then
                    first_left_in := clock_cycle;
                end if;
            end if;
            if right_strobe_in = '1' then
                if first_right_in = 0 then
                    first_right_in := clock_cycle;
                end if;
            end if;
            if left_strobe_out = '1' then
                if first_left_out = 0 then
                    first_left_out := clock_cycle;
                end if;
            end if;
            if right_strobe_out = '1' then
                if first_right_out = 0 then
                    first_right_out := clock_cycle;
                end if;
            end if;
            exit when (first_left_out /= 0) and (first_right_out /= 0)
                    and (first_left_in /= 0) and (first_right_in /= 0);
        end loop;
        assert (first_left_out /= 0) and (first_right_out /= 0)
                and (first_left_in /= 0) and (first_right_in /= 0);
        
        write (l, String'("Number of clock cycles required for compression (left): "));
        write (l, first_left_out - first_left_in);
        writeline (output, l);
        write (l, String'("Number of clock cycles required for compression (right): "));
        write (l, first_right_out - first_right_in);
        writeline (output, l);
        done <= '1';
        wait;
    end process run_test;

end test;
