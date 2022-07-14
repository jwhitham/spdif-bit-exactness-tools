
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_test_top is
    port (
        clk12MHz        : in std_logic;
        tx_to_rpi       : out std_logic := '0';
        rx_from_rpi     : in std_logic;
        tx_to_pic       : out std_logic := '0';
        rx_from_pic     : in std_logic);
end uart_test_top;

architecture structural of uart_test_top is

    signal data_in       : std_logic_vector (7 downto 0);
    signal strobe_in     : std_logic;
    signal data_out      : std_logic_vector (7 downto 0) := (others => '0');
    signal strobe_out    : std_logic := '0';
    signal ready_out     : std_logic := '0';
    signal clock         : std_logic := '0';

begin
    tx_to_pic <= '1';
    data_in <= std_logic_vector (unsigned (data_out) + 1);
    strobe_in <= strobe_out;

    pll : entity compressor_pll
        port map (
              REFERENCECLK => clk12MHz,
              RESET => '1',
              PLLOUTCORE => open,
              PLLOUTGLOBAL => clock);

    pi_uart : entity uart
        generic map (
            clock_frequency => 96.0e6,
            baud_rate => 500.0e3)
        port map (
            data_in => data_in,
            strobe_in => strobe_in,
            data_out => data_out,
            strobe_out => strobe_out,
            ready_out => open,
            serial_in => rx_from_rpi,
            serial_out => tx_to_rpi,
            clock_in => clock);

end structural;

