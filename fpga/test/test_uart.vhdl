
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity test_uart is
end test_uart;

architecture structural of test_uart is

    signal data_in       : std_logic_vector (7 downto 0) := (others => '0');
    signal strobe_in     : std_logic := '0';
    signal data_out      : std_logic_vector (7 downto 0) := (others => '0');
    signal strobe_out    : std_logic := '0';
    signal ready_out     : std_logic := '0';
    signal serial_in     : std_logic := '0';
    signal serial_out    : std_logic := '0';
    signal clock         : std_logic := '0';
    signal done          : std_logic := '0';

begin

    dut : entity uart
        generic map (
            clock_frequency => 1.0e6,
            baud_rate => 1200.0)
        port map (
            data_in => data_in,
            strobe_in => strobe_in,
            data_out => data_out,
            strobe_out => strobe_out,
            ready_out => ready_out,
            serial_in => serial_in,
            serial_out => serial_out,
            clock_in => clock);

    serial_in <= serial_out;

    process
    begin
        -- 1MHz clock (one clock every microsecond)
        while done /= '1' loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    process
    begin
        wait until clock'event and clock = '1';
        -- send bytes 1 to 255
        for i in 1 to 255 loop
            wait until clock'event and clock = '0';
            data_in <= std_logic_vector (to_unsigned (i, 8));
            assert ready_out = '1';
            strobe_in <= '1';
            wait until clock'event and clock = '1';
            wait until clock'event and clock = '0';
            assert ready_out = '0';
            strobe_in <= '0';
            wait until ready_out'event and ready_out = '1';
        end loop;
        wait;
    end process;

    process
    begin
        done <= '0';
        wait until clock'event and clock = '1';
        -- receive bytes 1 to 255
        for i in 1 to 255 loop
            wait until strobe_out'event and strobe_out = '1';
            assert data_out = std_logic_vector (to_unsigned (i, 8));
            wait until strobe_out'event and strobe_out = '0';
        end loop;
        done <= '1';
        wait;
    end process;


end architecture structural;
