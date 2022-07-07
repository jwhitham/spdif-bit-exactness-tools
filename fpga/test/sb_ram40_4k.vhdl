
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity sb_ram40_4k is
    generic (
        read_mode : Integer;
        write_mode : Integer);
    port (
        rdata       : out std_logic_vector (15 downto 0) := (others => '0');
        raddr       : in std_logic_vector (7 downto 0);
        waddr       : in std_logic_vector (7 downto 0);
        mask        : in std_logic_vector (15 downto 0);
        wdata       : in std_logic_vector (15 downto 0);
        rclke       : in std_logic;
        rclk        : in std_logic;
        re          : in std_logic;
        wclke       : in std_logic;
        wclk        : in std_logic;
        we          : in std_logic);
end sb_ram40_4k;

architecture behavioural of sb_ram40_4k is
    subtype t_word is std_logic_vector (15 downto 0);
    type t_storage is array (0 to 255) of t_word;

    signal storage : t_storage := (others => (others => '0'));
begin
    process (wclk)
        variable l : line;
    begin
        if wclk'event and wclk = '1' then
            if wclke = '1' and we = '1' then
                for i in 0 to 15 loop
                    if mask (i) = '0' then  -- 0 = write
                        storage (to_integer (unsigned (waddr))) (i) <= wdata (i);
                    end if;
                end loop;
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
