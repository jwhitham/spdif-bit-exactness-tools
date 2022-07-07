
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_spdif_meter_main is
end test_spdif_meter_main;

architecture structural of test_spdif_meter_main is

    signal clock           : std_logic := '0';
    signal raw_data        : std_logic := '0';
    signal done            : std_logic := '0';
    signal lcols           : std_logic_vector (3 downto 0) := (others => '0');
    signal lrows           : std_logic_vector (7 downto 0) := (others => '0');
    signal one             : std_logic := '1';

begin
    test_signal_gen : entity test_signal_generator
        port map (raw_data_out => raw_data, done_out => done, clock_out => clock);

    t : entity spdif_meter_main
        port map (
            clock_in => clock,
            raw_data_in => raw_data,
            raw_data_out => open,
            btn_nw => one,
            btn_ne => one,
            btn_sw => one,
            btn_se => one,
            clock_out => open,
            lcols_out => lcols,
            lrows_out => lrows);

    printer : process
        variable l : line;

        procedure dump is
        begin
            for i in 0 to 7 loop
                if lrows (i) = '1' then
                    write (l, String'("#"));
                else
                    write (l, String'("."));
                end if;
            end loop;
            writeline (output, l);
        end dump;
    begin
        wait until clock'event and clock = '1';
        while done /= '1' loop
            case lcols is
                when "1110" =>
                    write (l, String'("left:   "));
                    dump;
                when "1101" =>
                    write (l, String'("right:  "));
                    dump;
                when "1011" =>
                    write (l, String'("dtime:  "));
                    dump;
                when "0111" =>
                    write (l, String'("status: "));
                    dump;
                when others =>
                    null;
            end case;
            wait until lcols'event or done = '1';
        end loop;
        wait;
    end process printer;

end structural;

