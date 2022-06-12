
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_divider is
end test_divider;

architecture test of test_divider is

    component divider is
        generic (
            top_width : Natural := 16;
            bottom_width : Natural := 16);
        port (
            top_value_in    : in std_logic_vector (top_width - 1 downto 0);
            bottom_value_in : in std_logic_vector (bottom_width - 1 downto 0);
            start_in        : in std_logic;
            finish_out      : out std_logic := '0';
            result_out      : out std_logic_vector (top_width - 1 downto 0);
            clock_in        : in std_logic
        );
    end component divider;

    constant top_width : Natural := 16;
    constant bottom_width : Natural := 8;

    signal top_value        : std_logic_vector (top_width - 1 downto 0);
    signal bottom_value     : std_logic_vector (bottom_width - 1 downto 0);
    signal start            : std_logic := '0';
    signal finish           : std_logic := '0';
    signal result           : std_logic_vector (top_width - 1 downto 0);
    signal clock            : std_logic := '0';
    signal done             : std_logic := '0';

begin
    d : divider
        generic map (top_width => top_width, bottom_width => bottom_width)
        port map (
            top_value_in => top_value,
            bottom_value_in => bottom_value,
            start_in => start,
            finish_out => finish,
            result_out => result,
            clock_in => clock);

    process
    begin
        wait for 500 ns;
        while done /= '1' loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    process
    begin
        wait for 1 us;
        top_value <= std_logic_vector (to_unsigned (1337, top_width));
        bottom_value <= std_logic_vector (to_unsigned (3, bottom_width));
        assert finish = '0';
        start <= '1';

        wait for 1 us;
        start <= '0';
        assert finish = '0';
        while finish = '0' loop
            wait for 1 us;
        end loop;
        assert result = std_logic_vector (to_unsigned (445, top_width));
        wait for 1 us;
        assert finish = '0';
        done <= '1';
        wait;
    end process;
        

end test;
