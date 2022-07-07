
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_fpga_main is
end test_fpga_main;

architecture structural of test_fpga_main is

    signal clock           : std_logic := '0';
    signal raw_data        : std_logic := '0';
    signal done            : std_logic := '0';
    signal lcols           : std_logic_vector (3 downto 0) := (others => '0');
    signal lrows           : std_logic_vector (7 downto 0) := (others => '0');
    signal one             : std_logic := '1';

    component fpga_main is
        port (
            clock_in        : in std_logic;
            clock_out       : out std_logic;
            raw_data_in     : in std_logic;
            raw_data_out    : out std_logic;
            btn_nw          : in std_logic;
            btn_ne          : in std_logic;
            btn_se          : in std_logic;
            btn_sw          : in std_logic;
            lcols_out       : out std_logic_vector (3 downto 0) := "0000";
            lrows_out       : out std_logic_vector (7 downto 0) := "00000000"
        );
    end component fpga_main;

    component test_signal_generator is
        port (
            done_out        : out std_logic;
            clock_out       : out std_logic;
            raw_data_out    : out std_logic
        );
    end component test_signal_generator;

begin
    test_signal_gen : test_signal_generator
        port map (raw_data_out => raw_data, done_out => done, clock_out => clock);

    t : fpga_main
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

