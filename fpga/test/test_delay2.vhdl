library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_delay2 is
end test_delay2;

architecture test of test_delay2 is

    subtype t_data is std_logic_vector (15 downto 0);

    signal done        : std_logic := '0';
    signal clock_in    : std_logic := '0';
    signal data_in     : t_data := (others => '0');
    signal data_out    : t_data := (others => '0');
    signal strobe_in   : std_logic := '0';
    signal strobe_out  : std_logic := '0';
    signal error_out   : std_logic := '0';
    signal reset_in    : std_logic := '0';
    signal sub_test_number : Natural := 0;
    signal expect_output : std_logic := '0';
    signal bypass_in   : std_logic := '0';


    constant incorrect_value          : Natural := 42;

    constant num_sub_tests            : Natural := 6;
    constant num_values_per_sub_test  : Natural := 100;

    constant delay1_size_log_2        : Natural := 4;
    constant num_delays               : Natural := 4;
    constant num_delays_when_bypassed : Natural := 2;

    constant delay_size               : Natural := (2 ** delay1_size_log_2) * num_delays;
    constant delay_size_when_bypassed : Natural := ((2 ** delay1_size_log_2) * num_delays_when_bypassed) +
                                            (num_delays - num_delays_when_bypassed);

begin
    -- number of test values must be sufficient to get through the delay
    assert delay_size < ((num_values_per_sub_test * 3) / 4);

    -- 1MHz clock (one clock every 1000ns)
    process
    begin
        while done = '0' loop
            clock_in <= '1';
            wait for 500 ns;
            clock_in <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    dut : entity delay
        generic map (
            delay1_size_log_2 => delay1_size_log_2,
            num_delays => num_delays,
            num_delays_when_bypassed => num_delays_when_bypassed)
        port map (
            data_in => data_in,
            data_out => data_out,
            strobe_in => strobe_in,
            strobe_out => strobe_out,
            error_out => error_out,
            bypass_in => bypass_in,
            reset_in => reset_in,
            clock_in => clock_in);

    assert error_out = '0';

    -- Test pattern writes blocks of values to the delay, and then
    -- switches the bypass feature on/off. When the bypass changes,
    -- the delay should forget all of its contents.
    signal_generator : process
        variable value : Natural := 0;
    begin
        reset_in <= '1';
        done <= '0';
        strobe_in <= '0';
        expect_output <= '0';
        bypass_in <= '0';
        data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
        wait for 10 us;
        wait until clock_in = '0';
        reset_in <= '0';
        value := num_values_per_sub_test + 1;

        for sub_test in 1 to num_sub_tests loop
            bypass_in <= not bypass_in;
            wait for 10 us;
            assert value = (sub_test * num_values_per_sub_test) + 1;
            if (sub_test mod 2) = 0 then
                assert bypass_in = '0'; -- even-numbered test - no bypass
            else
                assert bypass_in = '1';
            end if;

            for i in 1 to num_values_per_sub_test loop
                data_in <= std_logic_vector (to_unsigned (value, 16));
                strobe_in <= '1';
                value := value + 1;
                wait for 1 us;
                data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
                strobe_in <= '0';
                wait for 2 us;
            end loop;

            wait for 10 us;
        end loop;
        wait for 10 us;
        done <= '1';
        wait;
    end process signal_generator;

    -- Expecting to receive only certain values from the delay. In bypass
    -- mode, we will see more values, since fewer are trapped in the delay.
    check_data : process
        variable l : line;
        variable sub_test, old_value, new_value, expect_value : Natural := 0;
    begin
        -- Check test data
        expect_value := num_values_per_sub_test + 1;
        while done = '0' loop
            wait until strobe_out'event or done'event or error_out'event;
            if strobe_out = '1' then
                -- Check current value
                new_value := to_integer (unsigned (data_out));
                if new_value /= expect_value then
                    write (l, String'("data output is "));
                    write (l, new_value);
                    write (l, String'(" expected "));
                    write (l, expect_value);
                    write (l, String'(" after "));
                    write (l, old_value);
                    writeline (output, l);
                    assert False;
                end if;
                old_value := new_value;

                -- Determine next expected value
                sub_test := old_value / num_values_per_sub_test;
                expect_value := old_value + 1;

                if (sub_test mod 2) = 0 then
                    -- even-numbered test - no bypass
                    if (old_value mod num_values_per_sub_test) = (num_values_per_sub_test - delay_size) then
                        -- new value is from the next test
                        expect_value := ((sub_test + 1) * num_values_per_sub_test) + 1;
                    end if;
                else
                    -- odd-numbered test - bypass
                    if (old_value mod num_values_per_sub_test) = (num_values_per_sub_test - delay_size_when_bypassed) then
                        -- new value is from the next test
                        expect_value := ((sub_test + 1) * num_values_per_sub_test) + 1;
                    end if;
                end if;
            end if;
        end loop;

        assert expect_value = ((num_sub_tests + 1) * num_values_per_sub_test) + 1;
        write (l, String'("delay operated as expected when toggling bypass"));
        writeline (output, l);
        wait;
    end process check_data;

end test;
