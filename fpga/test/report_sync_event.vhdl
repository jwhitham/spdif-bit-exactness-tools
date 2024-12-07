library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use debug_textio.all;

entity report_sync_event is
    generic (
        index1, index2  : Natural;
        num_sync        : Natural := 14;
        name            : String);
    port (
        sync            : std_logic_vector (num_sync downto 1) := (others => '0');
        done            : std_logic := '0');
end report_sync_event;

architecture test of report_sync_event is
begin
    process
        variable l : line;
    begin
        while done /= '1' loop
            wait until sync (index1 downto index2)'event or done'event;
            write (l, name);
            write (l, String'(" "));
            if to_integer (unsigned (sync (index1 downto index2))) = 0 then
                write (l, String'("de"));
            end if;
            write (l, String'("synchronised"));
            writeline (output, l);
        end loop;
        wait;
    end process;
end architecture test;
