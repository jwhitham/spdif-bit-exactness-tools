library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_delay1 is
end test_delay1;

architecture test of test_delay1 is
    subtype t_data is std_logic_vector (15 downto 0);

    signal data_in     : t_data := (others => '0');
    signal data_in_copy: t_data := (others => '0');
    signal data_out    : t_data := (others => '0');
    signal strobe_in   : std_logic := '0';
    signal strobe_out  : std_logic := '0';
    signal error_out   : std_logic := '0';
    signal reset_in    : std_logic := '0';
    signal clock_in    : std_logic := '0';
    signal done        : std_logic := '0';
    signal expect_output : std_logic := '0';

    constant first_value : Natural := 2000;
    constant last_value : Natural := 3000;
    constant incorrect_value : Natural := 31337;
    constant delay_size : Natural := 256;

begin
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

    -- Delay (255 items)
    dut : entity delay1
        port map (
            data_in => data_in,
            data_out => data_out,
            strobe_in => strobe_in,
            strobe_out => strobe_out,
            error_out => error_out,
            reset_in => reset_in,
            clock_in => clock_in);

    assert error_out = '0';

    signal_generator : process
        variable l : line;
    begin
        reset_in <= '1';
        done <= '0';
        strobe_in <= '0';
        expect_output <= '0';
        data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
        wait until clock_in = '0';
        wait for 10 us;
        reset_in <= '0';
        wait for 10 us;

        write (l, String'("test delay"));
        writeline (output, l);

        -- Fill with test data
        for i in first_value to last_value loop
            if i = (first_value + delay_size) then
                expect_output <= '1';
            end if;
            data_in <= std_logic_vector (to_unsigned (i, 16));
            data_in_copy <= std_logic_vector (to_unsigned (i, 16));
            strobe_in <= '1';
            wait for 1 us;
            data_in <= std_logic_vector (to_unsigned (incorrect_value, 16));
            strobe_in <= '0';
            wait for 2 us;
        end loop;

        wait for 100 us;
        done <= '1';
        wait;
    end process signal_generator;

    check_data : process
        variable l : line;
        variable i : Natural := first_value;
    begin
        -- Check test data
        while done = '0' loop
            wait until strobe_out'event or done'event;
            if strobe_out'event and strobe_out = '1' then
                assert expect_output = '1';
                if data_out /= std_logic_vector (to_unsigned (i, 16)) then
                    write (l, String'("output from delay is "));
                    write (l, to_integer (unsigned (data_out)));
                    write (l, String'(" expected "));
                    write (l, i);
                    writeline (output, l);
                    assert False;
                end if;
                if (unsigned (data_out) + to_unsigned (delay_size, 16)) /= unsigned (data_in_copy) then
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
        end loop;
        assert i = (last_value - delay_size + 1);

        write (l, String'("delay operated as expected"));
        writeline (output, l);
        wait;
    end process check_data;

end test;
