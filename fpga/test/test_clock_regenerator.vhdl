
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_clock_regenerator is
end test_clock_regenerator;

architecture test of test_clock_regenerator is

    constant ZERO   : std_logic_vector (1 downto 0) := "00";
    constant ONE    : std_logic_vector (1 downto 0) := "01";
    constant TWO    : std_logic_vector (1 downto 0) := "10";
    constant THREE  : std_logic_vector (1 downto 0) := "11";

    signal pulse_length_in  : std_logic_vector (1 downto 0) := ZERO;
    signal pulse_length_gen : std_logic_vector (1 downto 0) := ZERO;
    signal pulse_length_old : std_logic_vector (1 downto 0) := ZERO;
    signal clock_interval_out : std_logic_vector (15 downto 0) := (others => '0');
    signal sync_in          : std_logic;
    signal sync_out         : std_logic := '0';
    signal clock            : std_logic;
    signal strobe_out       : std_logic := '0';
    signal data_in          : std_logic := '0';


    type t_test is record
        single_time     : Time;
        min_clocks      : Natural;
        max_clocks      : Natural;
        num_packets     : Natural;
        min_good_count  : Natural;
        max_error       : Time;
    end record;

    type t_test_table is array (Natural range <>) of t_test;

    constant test_table : t_test_table := ((10 us,       10,  10,  200, 11700, 100 ps),
                                           (7999 ns,     7,   8,   200, 11700, 100 ps),
                                           (15570 ns,    15,  16,  200, 11700, 100 ps),
                                           (31415926 ps, 30,  32,  200, 11700, 100 ps),
                                           (12345 ns,    12,  13,  200, 11700, 100 ps));
    signal test_id          : Natural := 0;
    constant num_tests      : Natural := test_table'Length;

    signal interval_time    : Natural := 0;
    signal overall_time     : Natural := 0;
    signal overall_time_at_end : Natural := 0;
    signal good_count       : Natural := 0;
begin

    process
    begin
        -- 1MHz clock (one clock every 1000ns)
        while test_id <= num_tests loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    pulse_length_sync : process (clock)
    begin
        -- The signal generator doesn't use the clock and may generate
        -- pulses at any time. However, the clock regenerator expects input
        -- to be synchronised to the clock. Hence, synchronise the pulse.
        if clock'event and clock = '1' then
            pulse_length_in <= ZERO;
            if pulse_length_gen /= pulse_length_old then
                pulse_length_in <= pulse_length_gen;
                pulse_length_old <= pulse_length_gen;
            end if;
        end if;
    end process pulse_length_sync;

    dut : entity clock_regenerator
        port map (
            pulse_length_in => pulse_length_in,
            clock_interval_out => clock_interval_out,
            sync_in => sync_in,
            sync_out => sync_out,
            clock_in => clock,
            strobe_out => strobe_out);

    signal_generator : process
        variable single_time : Time := 0 us;
        variable l : line;
        variable test : t_test;
    begin
        test_id <= 0;
        sync_in <= '0';
        data_in <= '1';
        wait for 10 us;
        sync_in <= '1';

        for i in test_table'Range loop
            test_id <= i;
            test := test_table (i);
            assert test.single_time > 2 us; -- need to hold pulse_length_gen for 1 us for the clock

            for j in 1 to test.num_packets loop
                -- send two triple pulses
                for k in 1 to 2 loop
                    pulse_length_gen <= THREE;
                    wait for 1 us;
                    pulse_length_gen <= ZERO;
                    wait for (test.single_time * 3) - 1 us;
                end loop;

                -- send the rest of the packet (58 single pulses - this is not valid S/PDIF)
                for k in 1 to 58 loop
                    pulse_length_gen <= ONE;
                    wait for 1 us;
                    pulse_length_gen <= ZERO;
                    wait for test.single_time - 1 us;
                end loop;
            end loop;

            sync_in <= '0';
            wait for 100 us;
            sync_in <= '1';
        end loop;

        sync_in <= '0';
        wait for 20 us;
        test_id <= num_tests + 1;
        wait;
    end process signal_generator;

    -- Measure the clock interval from the generator
    -- Each individual clock pulse should be within the bounds specified in the test table.
    -- Furthermore the overall error in the average time should be less than a specified threshold.
    output_checker : process (clock)
        variable l : line;
        variable average_time, err : Time := 0 us;
        variable test : t_test;
    begin
        if clock'event and clock = '1' then
            if sync_out = '0' then
                if good_count /= 0 then
                    test := test_table (test_id);
                    write (l, String'("generated "));
                    write (l, good_count);
                    write (l, String'(" correct intervals for test "));
                    write (l, test_id);
                    write (l, String'(" average time "));
                    average_time := (overall_time_at_end * 1 us) / good_count;
                    write (l, average_time);
                    err := average_time - test.single_time;
                    write (l, String'(", error "));
                    write (l, err);
                    writeline (output, l);
                    assert good_count >= test.min_good_count;
                    assert abs (err) <= test.max_error;
                    good_count <= 0;
                end if;
                interval_time <= 0;
                overall_time <= 0;

            elsif interval_time = 0 then
                -- await first strobe
                if strobe_out = '1' then
                    interval_time <= 1;
                    overall_time <= 1;
                end if;

            elsif strobe_out = '0' then
                -- await next strobe
                interval_time <= interval_time + 1;
                overall_time <= overall_time + 1;
            else
                -- check time between strobes
                test := test_table (test_id);
                if interval_time < test.min_clocks or interval_time > test.max_clocks then
                    write (l, String'("generated interval "));
                    write (l, interval_time);
                    write (l, String'(" is outside of the permitted range ["));
                    write (l, test.min_clocks);
                    write (l, String'(","));
                    write (l, test.max_clocks);
                    write (l, String'("]"));
                    writeline (output, l);
                    assert False;
                else
                    good_count <= good_count + 1;
                    overall_time_at_end <= overall_time;
                end if;
                overall_time <= overall_time + 1;
                interval_time <= 1;
            end if;
        end if;
    end process output_checker;

end test;
