
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

    constant num_packets        : Natural := 200;

    signal pulse_length     : std_logic_vector (1 downto 0) := "00";
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
    end record;

    type t_test_table is array (Natural range <>) of t_test;

    constant test_table : t_test_table := ((10 us, 10, 10),
                                           (7 us, 7, 7),
                                           (15570 ns, 15, 16),
                                           (31415926 ps, 30, 32),
                                           (12345 ns, 12, 13));
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

    id : entity input_decoder 
        generic map (enough_transitions => 3)
        port map (
            data_in => data_in,
            pulse_length_out => pulse_length,
            single_time_out => open,
            sync_out => open,
            sync_in => sync_in,
            clock_in => clock);

    dut : entity clock_regenerator
        port map (
            pulse_length_in => pulse_length,
            clock_interval_out => clock_interval_out,
            sync_in => sync_in,
            sync_out => sync_out,
            clock_in => clock,
            strobe_out => strobe_out);

    signal_generator : process
        variable single_time : Time := 0 us;
        variable l : line;
    begin
        test_id <= 0;
        sync_in <= '0';
        data_in <= '1';
        wait for 10 us;
        sync_in <= '1';

        for i in test_table'Range loop
            test_id <= i;
            single_time := test_table (i).single_time;

            for j in 1 to num_packets loop
                -- send two triple pulses
                data_in <= not data_in;
                wait for single_time * 3;
                data_in <= not data_in;
                wait for single_time * 3;

                -- send the rest of the packet (58 single pulses - this is not valid S/PDIF)
                for k in 1 to 58 loop
                    data_in <= not data_in;
                    wait for single_time;
                end loop;
            end loop;

            wait for 100 us;

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
    output_checker : process (clock)
        variable l : line;
        variable single_time : Time := 0 us;
        variable average_time, err : Real := 0.0;
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
                    average_time := Real (overall_time_at_end) / Real (good_count);
                    write (l, average_time * 1 us);
                    err := average_time - Real (test.single_time / 1 us);
                    write (l, String'(", error "));
                    write (l, err * 1 us);
                    writeline (output, l);
                    assert good_count > 5000;
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

--                  single_time := test_table (test_id);
--                  err := abs (Integer (single_time / 1 us) - Integer (interval_time));
--                  if true or err > 1 then
--                      write (l, String'("interval "));
--                      write (l, interval_time);
--                      write (l, String'(" err "));
--                      write (l, err);
--                      writeline (output, l);
--                      -- assert err <= 1;
--                  end if;
                interval_time <= 1;
            end if;
        end if;
    end process output_checker;

--  -- Check that the second THREE pulse occurs at the expected interval in each test
--  input_checker : process (clock)
--      variable l : line;
--      variable single_time : Time := 0 us;
--      variable err : Integer := 0;
--  begin
--      if clock'event and clock = '1' then
--          interval_time <= interval_time + 1;
--          case pulse_length is
--              when THREE =>
--                  if three_flag = '1' then
--                      if test_id <= num_tests and test_id = previous_test_id and previous_time /= 0 then
--                          single_time := test_table (test_id);
--                          err := abs (Integer ((single_time * 64) / 1 us) -
--                                      Integer (interval_time - previous_time));
--                          if err > 1 then
--                              write (l, String'("interval "));
--                              write (l, interval_time - previous_time);
--                              write (l, String'(" err "));
--                              write (l, err);
--                              writeline (output, l);
--                              assert err <= 1;
--                          end if;
--                      end if;
--                      previous_time <= interval_time;
--                      previous_test_id <= test_id;
--                  end if;
--                  three_flag <= '1';
--              when ZERO =>
--                  null;
--              when others =>
--                  three_flag <= '0';
--          end case;
--      end if;
--  end process input_checker;

end test;
