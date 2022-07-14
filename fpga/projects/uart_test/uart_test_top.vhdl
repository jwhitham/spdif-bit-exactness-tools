
library ieee;
use ieee.std_logic_1164.all;

entity uart_test_top is
    port (
        clk12MHz        : in std_logic;
        tx_to_rpi       : out std_logic := '0';
        rx_from_rpi     : in std_logic;
        tx_to_pic       : out std_logic := '0';
        rx_from_pic     : in std_logic);
end uart_test_top;

architecture structural of uart_test_top is

begin
    process (clk12MHz)
    begin
        if clk12MHz = '1' and clk12MHz'event then
            tx_to_pic <= rx_from_rpi;
            tx_to_rpi <= rx_from_pic;
        end if;
    end process;

end structural;

