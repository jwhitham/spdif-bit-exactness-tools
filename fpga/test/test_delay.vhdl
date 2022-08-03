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
    constant num_sizes : Natural := 3;

    signal done        : std_logic_vector (0 to num_sizes) := (others => '0');
    signal clock_in    : std_logic := '0';
begin
    -- 1MHz clock (one clock every 1000ns)
    process
    begin
        done (0) <= '1';
        while done (num_sizes) = '0' loop
            clock_in <= '1';
            wait for 500 ns;
            clock_in <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    size : for num_delays in 1 to num_sizes generate
        constant delay_size : Natural := 256 * num_delays;
        constant num_tests : Natural := 5;

        signal data_in     : t_data := (others => '0');
        signal data_in_copy: t_data := (others => '0');
        signal data_out    : t_data := (others => '0');
        signal strobe_in   : std_logic := '0';
        signal strobe_out  : std_logic := '0';
        signal error_out   : std_logic := '0';
        signal reset_in    : std_logic := '0';
        signal test_number : Natural := 0;
        signal expect_output : std_logic := '0';

        constant first_value : Natural := 2000;
        constant last_value : Natural := 3000;
        constant incorrect_value : Natural := 31337;
        constant too_fast_test : Natural := 4;

    begin
        dut : entity delay
            generic map (num_delays => num_delays)
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
            done (num_delays) <= '0';
            wait until done (num_delays - 1) = '1';

            for test in 1 to num_tests loop
                reset_in <= '1';
                strobe_in <= '0';
                expect_output <= '0';
                data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
                test_number <= test;
                offset := test - 1;
                wait for 1 us;

                write (l, String'("test delay - test number "));
                write (l, num_delays);
                write (l, String'("."));
                write (l, test);
                writeline (output, l);

                wait until clock_in = '0';
                wait for 10 us;
                reset_in <= '0';
                wait for 10 us;

                -- Fill with test data
                for i in first_value to last_value loop
                    if i = (first_value + delay_size) then
                        expect_output <= '1';
                    end if;
                    data_in <= std_logic_vector (to_unsigned (i + offset, 16));
                    data_in_copy <= std_logic_vector (to_unsigned (i + offset, 16));
                    strobe_in <= '1';
                    wait for 1 us;
                    data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
                    strobe_in <= '0';
                    case test is
                        when 1 => wait for 10 us;
                        when 2 => wait for 2 us;
                        when 3 => wait for 3 us;
                        when too_fast_test => wait for 1 us; -- not enough!
                        when others => wait for (9 - (i mod 8)) * 1 us;
                    end case;
                end loop;

                wait for 1 us;
            end loop;
            test_number <= num_tests + 1;
            wait for 1 us;
            done (num_delays) <= '1';
            wait;
        end process signal_generator;

        check_data : process
            variable l : line;
            variable test, i, offset : Natural := 0;
            variable error_flag : Boolean := false;
        begin
            -- Check test data
            while done (num_delays) = '0' loop
                wait until strobe_out'event or done (num_delays)'event
                        or error_out'event or test_number'event;
                if test_number'event then
                    if test > 0 then
                        if test /= too_fast_test then
                            assert i = (last_value - delay_size + 1 + offset);
                        else
                            assert error_flag;
                        end if;
                        write (l, String'("test ok"));
                        writeline (output, l);
                    end if;
                    test := test_number;
                    error_flag := false;
                    offset := test - 1;
                    i := first_value + offset;
                end if;
                if strobe_out'event and strobe_out = '1'
                        and test /= too_fast_test then
                    assert expect_output = '1';
                    if data_out /= std_logic_vector (to_unsigned (i, 16)) then
                        write (l, String'("output from delay is "));
                        write (l, to_integer (unsigned (data_out)));
                        write (l, String'(" expected "));
                        write (l, i);
                        writeline (output, l);
                        assert False;
                    end if;
                    if (unsigned (data_out) + to_unsigned (delay_size, 16))
                                /= unsigned (data_in_copy) then
                        write (l, String'("output from delay "));
                        write (l, to_integer (unsigned (data_out)));
                        write (l, String'(" is not "));
                        write (l, delay_size);
                        write (l, String'(" behind the input "));
                        write (l, to_integer (unsigned (data_in_copy)));
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
                    assert test_number = too_fast_test;
                    error_flag := true;
                end if;
            end loop;

            assert test = num_tests + 1;
            write (l, String'("delay operated as expected: size "));
            write (l, delay_size);
            writeline (output, l);
            wait;
        end process check_data;
    end generate size;

end test;
