
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

    signal data_from_pic    : std_logic_vector (7 downto 0);
    signal data_to_pic      : std_logic_vector (7 downto 0);
    signal strobe_from_pic  : std_logic;
    signal strobe_to_pic    : std_logic;
    signal clock            : std_logic := '0';

begin
    pll : entity compressor_pll
        port map (
              REFERENCECLK => clk12MHz,
              RESET => '1',
              PLLOUTCORE => open,
              PLLOUTGLOBAL => clock);

    -- iceFUN has a PIC with A/D converters, accessed via serial connection at 250kbps
    -- sending \xA1 gave me the input to pin 26 labelled X2
    -- sending \xA2 gave me the input to pin 25 labelled X1
    -- sending \xA3 gave me the input to pin 32 labelled X3
    -- sending \xA4 gave me the input to pin 33 labelled X4
    -- samples arrive around 150 microseconds after being requested though the time is not exact
    -- and varies by 20/30 microseconds in both directions; the delay in these UARTs increases
    -- the time - expect a minimum sample period of about 250 microseconds here.
    -- The least significant byte seemed to be sent first (manual says otherwise).
    -- Values were 10 bit.

    pi_uart : entity uart
        generic map (
            clock_frequency => 96.0e6,
            baud_rate => 500.0e3)
        port map (
            data_in => data_from_pic,
            strobe_in => strobe_from_pic,
            data_out => data_to_pic,
            strobe_out => strobe_to_pic,
            ready_out => open,
            serial_in => rx_from_rpi,
            serial_out => tx_to_rpi,
            clock_in => clock);

    pic_uart : entity uart
        generic map (
            clock_frequency => 96.0e6,
            baud_rate => 250.0e3)
        port map (
            data_in => data_to_pic,
            strobe_in => strobe_to_pic,
            data_out => data_from_pic,
            strobe_out => strobe_from_pic,
            ready_out => open,
            serial_in => rx_from_pic,
            serial_out => tx_to_pic,
            clock_in => clock);
end structural;

