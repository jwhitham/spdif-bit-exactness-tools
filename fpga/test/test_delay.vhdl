library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_delay is
end test_delay;

architecture test of test_delay is
    subtype t_data is std_logic_vector (15 downto 0);
    constant num_tests : Natural := 3;

    signal done        : std_logic_vector (0 to num_tests) := (others => '0');
    signal clock_in    : std_logic := '0';
begin
    -- 1MHz clock (one clock every 1000ns)
    process
    begin
        done (0) <= '1';
        while done (num_tests) = '0' loop
            clock_in <= '1';
            wait for 500 ns;
            clock_in <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    test_size : for test_number in 1 to num_tests generate
        constant delay_size_log_2 : Natural := 6 + ((test_number - 1) * 2);
        constant delay_size : Natural := 2 ** delay_size_log_2;
        constant num_sub_tests : Natural := 5;

        signal data_in     : t_data := (others => '0');
        signal data_out    : t_data := (others => '0');
        signal strobe_in   : std_logic := '0';
        signal strobe_out  : std_logic := '0';
        signal error_out   : std_logic := '0';
        signal reset_in    : std_logic := '0';
        signal sub_test_number : Natural := 0;
        signal expect_output : std_logic := '0';

        constant first_value : Natural := 2000;
        constant last_value : Natural := 4000;
        constant incorrect_value : Natural := 31337;
        constant too_fast_test : Natural := 4;

        function generate_offset (test, sub_test : Natural) return Natural is
        begin
            return (test * 10) + sub_test;
        end generate_offset;

    begin
        assert last_value > (first_value + delay_size);

        dut : entity delay
            generic map (delay_size_log_2 => delay_size_log_2)
            port map (
                data_in => data_in,
                data_out => data_out,
                strobe_in => strobe_in,
                strobe_out => strobe_out,
                error_out => error_out,
                reset_in => reset_in,
                clock_in => clock_in);

        signal_generator : process
            variable l : line;
            variable offset : Natural := 0;
        begin
            reset_in <= '1';
            done (test_number) <= '0';
            wait until done (test_number - 1) = '1';

            for sub_test in 1 to num_sub_tests loop
                reset_in <= '1';
                strobe_in <= '0';
                expect_output <= '0';
                data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
                sub_test_number <= sub_test;
                wait for 10 us;

                write (l, String'("test delay - test number "));
                write (l, test_number);
                write (l, String'("."));
                write (l, sub_test_number);
                writeline (output, l);

                wait until clock_in = '0';
                wait for 10 us;
                reset_in <= '0';
                wait for 10 us;
                offset := generate_offset (test_number, sub_test_number);

                -- Fill with test data
                for i in first_value to last_value loop
                    if i = (first_value + delay_size) then
                        expect_output <= '1';
                    end if;
                    data_in <= std_logic_vector (to_unsigned (i + offset, 16));
                    strobe_in <= '1';
                    wait for 1 us;
                    data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
                    strobe_in <= '0';
                    case sub_test is
                        when 1 => wait for 10 us;
                        when 2 => wait for 2 us;
                        when 3 => wait for 3 us;
                        when too_fast_test => wait for 1 us; -- not enough!
                        when others => wait for (9 - (i mod 8)) * 1 us;
                    end case;
                end loop;

                wait for 10 us;
            end loop;
            sub_test_number <= num_sub_tests + 1;
            wait for 1 us;
            done (test_number) <= '1';
            wait;
        end process signal_generator;

        check_data : process
            variable l : line;
            variable sub_test, i, offset, final_value : Natural := 0;
            variable error_flag : Boolean := false;
        begin
            -- Check test data
            while done (test_number) = '0' loop
                wait until strobe_out'event or done (test_number)'event
                        or error_out'event or sub_test_number'event;
                if sub_test_number'event then
                    if sub_test > 0 then
                        if sub_test /= too_fast_test then
                            final_value := (last_value - delay_size + 1 + offset);
                            if final_value /= i then
                                write (l, String'("final value is "));
                                write (l, i);
                                write (l, String'(" expected "));
                                write (l, final_value);
                                writeline (output, l);
                                assert False;
                            end if;
                        else
                            assert error_flag;
                        end if;
                        write (l, String'("test ok"));
                        writeline (output, l);
                    end if;
                    sub_test := sub_test_number;
                    error_flag := false;
                    offset := generate_offset (test_number, sub_test_number);
                    i := first_value + offset;
                end if;
                if strobe_out'event and strobe_out = '1'
                        and sub_test /= too_fast_test then
                    assert expect_output = '1';
                    if data_out /= std_logic_vector (to_unsigned (i, 16)) then
                        write (l, String'("output from delay is "));
                        write (l, to_integer (unsigned (data_out)));
                        write (l, String'(" expected "));
                        write (l, i);
                        writeline (output, l);
                        assert False;
                    end if;
                    assert data_out = std_logic_vector (to_unsigned (i, 16));
                    wait for 1001 ns;
                    assert strobe_out = '0';
                    assert data_out = std_logic_vector (to_unsigned (i, 16));
                    i := i + 1;
                end if;
                if error_out = '1' then
                    assert sub_test_number = too_fast_test;
                    error_flag := true;
                end if;
            end loop;

            assert sub_test = num_sub_tests + 1;
            write (l, String'("delay operated as expected: size "));
            write (l, delay_size);
            writeline (output, l);
            wait;
        end process check_data;
    end generate test_size;

end test;
