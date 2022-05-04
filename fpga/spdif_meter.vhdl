
library ieee;
use ieee.std_logic_1164.all;

entity spdif_meter is
    port (
        clk12MHz        : in std_logic;
        raw_data_in     : in std_logic;
        sync1_out       : out std_logic := '0';
        sync2_out       : out std_logic := '0';
        sync3_out       : out std_logic := '0';
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
end spdif_meter;

architecture structural of spdif_meter is

    signal lcols       : std_logic_vector (3 downto 0) := "0000";
    signal lrows       : std_logic_vector (7 downto 0) := "00000000";
    signal clock       : std_logic := '0';
    signal zero        : std_logic := '0';

    component fpga_main is
        port (
            clock_in        : in std_logic;
            raw_data_in     : in std_logic;
            lcols_out       : out std_logic_vector (3 downto 0) := "0000";
            lrows_out       : out std_logic_vector (7 downto 0) := "00000000";
            sync1_out       : out std_logic := '0';
            sync2_out       : out std_logic := '0';
            sync3_out       : out std_logic := '0'
        );
    end component fpga_main;

    component spdif_meter_pll is
        port(
              REFERENCECLK: in std_logic;
              RESET: in std_logic;
              PLLOUTCORE: out std_logic;
              PLLOUTGLOBAL: out std_logic
            );
    end component spdif_meter_pll;

begin
    pll : spdif_meter_pll
        port map (
              REFERENCECLK => clk12MHz,
              RESET => zero,
              PLLOUTCORE => open,
              PLLOUTGLOBAL => clock);
    fp : fpga_main
        port map (
            clock_in => clock,
            raw_data_in => raw_data_in,
            lcols_out => lcols,
            lrows_out => lrows,
            sync1_out => sync1_out,
            sync2_out => sync2_out,
            sync3_out => sync3_out);

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

