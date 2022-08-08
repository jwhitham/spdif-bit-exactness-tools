
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

    constant sample_rate    : Natural := 1000;
    constant sample_period  : Time := 1000 ms / sample_rate;
    constant clock_period   : Time := sample_period / 1000;
    constant fpga_freq_mhz  : Natural := 96;

    constant one            : std_logic := '1';
    constant volume_1       : std_logic_vector (10 downto 0) := (10 => '1', others => '0');

    signal data_out         : t_data := (others => '0');
    signal left_strobe_out  : std_logic := '0';
    signal right_strobe_out : std_logic := '0';
    signal sync_in          : std_logic := '0';
    signal sync_out         : std_logic := '0';
    signal ready_out        : std_logic := '0';

    procedure compute_max_sample_rate (left_left_clocks : Natural) is
        constant fpga_clock_period : Real := 1.0 / (Real (fpga_freq_mhz) * 1.0e6); 
        constant min_sample_period : Real := Real (left_left_clocks) * fpga_clock_period;
        constant max_sample_rate   : Real := 1.0 / min_sample_period;
        variable l : line;
    begin
        write (l, String'("Maximum sample rate assuming "));
        write (l, fpga_freq_mhz);
        write (l, String'(" MHz system clock is "));
        write (l, Natural (max_sample_rate));
        write (l, String'(" Hz"));
        writeline (output, l);
    end compute_max_sample_rate;

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
        generic map (delay1_size_log_2 => 4, num_delays => 1)
        port map (
            data_in => data_in,
            left_strobe_in => left_strobe_in,
            right_strobe_in => right_strobe_in,
            enable_in => one,
            data_out => data_out,
            left_strobe_out => left_strobe_out,
            right_strobe_out => right_strobe_out,
            volume_in => volume_1,
            ready_out => ready_out,
            sync_in => sync_in,
            sync_out => sync_out,
            clock_in => clock);

    run_test : process
        variable l                  : line;
        variable ok                 : Boolean := false;
        variable first_in           : Natural := 0;
        variable first_out          : Natural := 0;
        variable ready_time         : Natural := 0;
        variable delta, wcet        : Natural := 0;
        variable previous_ready_out : std_logic := '0';

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
        assert ready_out = '1';
        previous_ready_out := ready_out;

        -- how long between restarting input and receiving output?
        enable_strobes <= '1';
        for channel in 1 to 2 loop
            first_in := 0;
            first_out := 0;
            ready_time := 0;

            for clock_cycle in 1 to (2 * (sample_period / clock_period)) loop
                wait until clock'event and clock = '1';
                if first_in = 0 then
                    if (left_strobe_in or right_strobe_in) = '1' then
                        first_in := clock_cycle;
                    end if;
                else
                    if (left_strobe_out or right_strobe_out) = '1' then
                        if first_out = 0 then
                            first_out := clock_cycle;
                        end if;
                    end if;
                    if ready_out = '1' and previous_ready_out = '0' then
                        if ready_time = 0 then
                            ready_time := clock_cycle;
                        end if;
                    end if;
                    exit when (ready_time /= 0) and (first_out /= 0);
                end if;
                previous_ready_out := ready_out;
            end loop;
            assert ready_time /= 0;
            assert first_out /= 0;
            assert first_in /= 0;
            delta := first_out - first_in;
            write (l, String'("Number of clock cycles required for compression: "));
            write (l, delta);
            writeline (output, l);
            if delta > wcet then
                wcet := delta;
            end if;

            delta := ready_time - first_in;
            write (l, String'("Number of clock cycles required to become ready: "));
            write (l, delta);
            writeline (output, l);
            if delta > wcet then
                wcet := delta;
            end if;
        end loop;

        write (l, String'("Minimum period between left/right samples: "));
        write (l, wcet);
        writeline (output, l);
        write (l, String'("Minimum period between left/left samples: "));
        write (l, wcet * 2);
        writeline (output, l);

        compute_max_sample_rate (wcet * 2);
        done <= '1';
        wait;
    end process run_test;

end test;
