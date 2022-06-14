
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_divider is
end test_divider;

architecture test of test_divider is

    component divider is
        generic (
            top_width    : Natural;
            bottom_width : Natural);
        port (
            top_value_in    : in std_logic_vector (top_width - 1 downto 0);
            bottom_value_in : in std_logic_vector (bottom_width - 1 downto 0);
            start_in        : in std_logic;
            finish_out      : out std_logic := '0';
            result_out      : out std_logic_vector (top_width - 1 downto 0);
            clock_in        : in std_logic
        );
    end component divider;

    signal clock            : std_logic := '0';
    signal done             : std_logic_vector (0 to 3) := (others => '0');

begin
    process
    begin
        done (0) <= '1';
        wait for 500 ns;
        while done (3) /= '1' loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    dtest : for part in 1 to 3 generate

        function get_top_width (p : Natural) return Natural is
        begin
            case p is
                when 1 =>       return 4;
                when 2 =>       return 8;
                when others =>  return 6;
            end case;
        end get_top_width;

        function get_bottom_width (p : Natural) return Natural is
        begin
            case p is
                when 1 =>       return 8;
                when 2 =>       return 4;
                when others =>  return 6;
            end case;
        end get_bottom_width;

        constant top_width : Natural := get_top_width (part);
        constant bottom_width : Natural := get_bottom_width (part);

        signal top_value        : std_logic_vector (top_width - 1 downto 0);
        signal bottom_value     : std_logic_vector (bottom_width - 1 downto 0);
        signal start            : std_logic := '0';
        signal finish           : std_logic := '0';
        signal result           : std_logic_vector (top_width - 1 downto 0);

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
            variable l : line;
        begin
            done (part) <= '0';
            wait until done (part - 1) = '1';
            assert finish = '0';
            wait for 1 us;

            write (l, String'("division test "));
            write (l, part);
            writeline (output, l);
            outer : for top in 0 to (2 ** top_width) - 1 loop
                for bottom in 1 to (2 ** bottom_width) - 1 loop
                    top_value <= std_logic_vector (to_unsigned (top, top_width));
                    bottom_value <= std_logic_vector (to_unsigned (bottom, bottom_width));
                    start <= '1';
                    wait for 1 us;

                    start <= '0';
                    assert finish = '0';
                    while finish = '0' loop
                        wait for 1 us;
                    end loop;

                    if result /= std_logic_vector (to_unsigned (top / bottom, top_width)) then
                        write (l, String'("Division error. Dividing "));
                        write (l, top);
                        write (l, String'(" by "));
                        write (l, bottom);
                        write (l, String'(" should be "));
                        write (l, top / bottom);
                        write (l, String'(" got "));
                        write (l, to_integer (unsigned (result)));
                        writeline (output, l);
                        assert False;
                        exit outer;
                    end if;
                end loop;
            end loop outer;
            done (part) <= '1';
            wait;
        end process;
    end generate dtest;

end test;
