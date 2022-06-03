
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity sb_ram512x8 is
    port (
        waddr       : in std_logic_vector (8 downto 0);
        wdata       : in std_logic_vector (7 downto 0);
        we          : in std_logic;
        wclke       : in std_logic;
        wclk        : in std_logic;
        raddr       : in std_logic_vector (8 downto 0);
        rdata       : out std_logic_vector (7 downto 0);
        re          : in std_logic;
        rclke       : in std_logic;
        rclk        : in std_logic);
end sb_ram512x8;

architecture behavioural of sb_ram512x8 is
    subtype t_byte is std_logic_vector (7 downto 0);
    type t_storage is array (0 to 511) of t_byte;

    signal storage : t_storage := (others => (others => '0'));
begin
    process (wclk)
        variable l : line;
    begin
        if wclk'event and wclk = '1' then
            if wclke = '1' and we = '1' then
                storage (to_integer (unsigned (waddr))) <= wdata;
            end if;
        end if;
    end process;

    process (rclk)
        variable l : line;
    begin
        if rclk'event and rclk = '1' then
            if rclke = '1' and re = '1' then
                rdata <= storage (to_integer (unsigned (raddr)));
            end if;
        end if;
    end process;
end architecture behavioural;
