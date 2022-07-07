
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

entity spdif_meter_top is
    port (
        clk12MHz        : in std_logic;
        raw_data_in     : in std_logic;
        raw_data_out    : out std_logic;
        start_out       : out std_logic := '0';
        clock_out       : out std_logic := '0';
        btn_nw          : in std_logic;
        btn_ne          : in std_logic;
        btn_se          : in std_logic;
        btn_sw          : in std_logic;
        lcol1           : out std_logic := '0';
        lcol2           : out std_logic := '0';
        lcol3           : out std_logic := '0';
        lcol4           : out std_logic := '0';
        led1            : out std_logic := '0';
        led2            : out std_logic := '0';
        led3            : out std_logic := '0';
        led4            : out std_logic := '0';
        led5            : out std_logic := '0';
        led6            : out std_logic := '0';
        led7            : out std_logic := '0';
        led8            : out std_logic := '0' 
    );
end spdif_meter_top;

architecture structural of spdif_meter_top is

    signal lcols       : std_logic_vector (3 downto 0) := "0000";
    signal lrows       : std_logic_vector (7 downto 0) := "00000000";
    signal clock       : std_logic := '0';

begin
    pll : entity spdif_meter_pll
        port map (
              REFERENCECLK => clk12MHz,
              RESET => '1',
              PLLOUTCORE => open,
              PLLOUTGLOBAL => clock);
    fp : entity spdif_meter_main
        port map (
            clock_in => clock,
            raw_data_in => raw_data_in,
            raw_data_out => raw_data_out,
            clock_out => clock_out,
            btn_nw => btn_nw,
            btn_ne => btn_ne,
            btn_se => btn_se,
            btn_sw => btn_sw,
            lcols_out => lcols,
            lrows_out => lrows);

    led1 <= lrows (0);
    led2 <= lrows (1);
    led3 <= lrows (2);
    led4 <= lrows (3);
    led5 <= lrows (4);
    led6 <= lrows (5);
    led7 <= lrows (6);
    led8 <= lrows (7);
    lcol1 <= lcols (0);
    lcol2 <= lcols (1);
    lcol3 <= lcols (2);
    lcol4 <= lcols (3);

end structural;

