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
    signal data_out    : t_data := (others => '0');
    signal strobe_in   : std_logic := '0';
    signal strobe_out  : std_logic := '0';
    signal error_out   : std_logic := '0';
    signal reset_in    : std_logic := '0';
    signal clock_in    : std_logic := '0';
    signal done        : std_logic := '0';
    signal expect_output : std_logic := '0';

    constant first_value : Natural := 1234;
    constant last_value : Natural := 2234;
    constant delay_size : Natural := 255;

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

    -- assert error_out = '0';

    signal_generator : process
    begin
        reset_in <= '1';
        done <= '0';
        strobe_in <= '0';
        expect_output <= '0';
        wait for 10 us;
        reset_in <= '0';
        wait for 10 us;
        wait until clock_in'event and clock_in = '1';

        -- Fill with test data
        for i in first_value to last_value loop
            if i = (first_value + delay_size) then
                expect_output <= '1';
            end if;
            data_in <= std_logic_vector (to_unsigned (i, 16));
            strobe_in <= '1';
            wait until clock_in'event and clock_in = '1';
            data_in <= std_logic_vector (to_unsigned (i + 1000, 16));
            strobe_in <= '0';
            wait until clock_in'event and clock_in = '1';
            data_in <= std_logic_vector (to_unsigned (0, 16));
            wait until clock_in'event and clock_in = '1';
            wait until clock_in'event and clock_in = '1';
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
        loop
            wait until strobe_out'event or done'event;
            assert done = '0';
            if strobe_out'event and strobe_out = '1' then
                assert expect_output = '1';
                if data_out /= std_logic_vector (to_unsigned (i, 16)) then
                    write (l, String'("output from delay is "));
                    write (l, to_integer (unsigned (data_out)));
                    write (l, String'(" expected "));
                    write (l, i);
                    writeline (output, l);
                end if;
                assert data_out = std_logic_vector (to_unsigned (i, 16));
                wait until clock_in'event and clock_in = '1';
                assert strobe_out = '0';
                assert data_out = std_logic_vector (to_unsigned (i, 16));
                i := i + 1;
            end if;
            exit when i >= (last_value - delay_size);
        end loop;

        wait until strobe_out'event or done'event;
        assert done = '1';
        assert strobe_out = '0';
        wait;
    end process check_data;

end test;
