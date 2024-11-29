
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use debug_textio.all;

entity test_divider is
end test_divider;

architecture test of test_divider is

    type t_test is record
        top_width       : Natural;
        bottom_width    : Natural;
    end record;

    type t_test_table is array (Positive range <>) of t_test;

    constant test_table     : t_test_table :=
        ((4, 8), (8, 4), (6, 6), (4, 4), (4, 1), (1, 4));
    constant num_tests      : Natural := test_table'Length;
    signal clock            : std_logic := '0';
    signal done             : std_logic_vector (0 to num_tests) := (others => '0');


begin
    process
    begin
        done (0) <= '1';
        wait for 500 ns;
        while done (num_tests) /= '1' loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    dtest : for part in test_table'Range generate


        constant top_width      : Natural := test_table (part).top_width;
        constant bottom_width   : Natural := test_table (part).bottom_width;
        constant top_start      : Natural := 0;
        constant top_finish     : Natural := (2 ** top_width) - 1;
        constant bottom_start   : Natural := 0;
        constant bottom_finish  : Natural := (2 ** bottom_width) - 1;

        function convert (value : Natural; size : Natural) return std_logic_vector is
        begin
            assert value <= ((2 ** size) - 1);
            return std_logic_vector (to_unsigned (value, size));
        end convert;

        signal top_value        : std_logic_vector (top_width - 1 downto 0) := (others => '0');
        signal bottom_value     : std_logic_vector (bottom_width - 1 downto 0) := (others => '0');
        signal start            : std_logic := '0';
        signal reset            : std_logic := '0';
        signal finish           : std_logic := '0';
        signal result           : std_logic_vector (top_width - 1 downto 0) := (others => '0');

    begin
        d : entity divider
            generic map (top_width => top_width,
                         bottom_width => bottom_width)
            port map (
                top_value_in => top_value,
                bottom_value_in => bottom_value,
                start_in => start,
                reset_in => reset,
                finish_out => finish,
                result_out => result,
                clock_in => clock);

        process
            variable l : line;
            variable expect : Integer;
            variable undefined : Boolean;
        begin
            done (part) <= '0';
            wait until done (part - 1) = '1';
            assert finish = '0';
            wait for 1 us;

            write (l, String'("division test "));
            write (l, part);
            writeline (output, l);
            outer : for top in top_start to top_finish loop
                for bottom in bottom_start to bottom_finish loop
                    top_value <= convert (top, top_width);
                    bottom_value <= convert (bottom, bottom_width);

                    expect := 0;
                    undefined := true;

                    -- Though the result of division by zero is undefined, the
                    -- divider should still finish.
                    start <= '1';
                    wait for 1 us;

                    top_value <= (others => '0');
                    bottom_value <= (others => '0');
                    start <= '0';
                    assert finish = '0';
                    while finish = '0' loop
                        wait for 1 us;
                    end loop;

                    if bottom /= 0 then
                        expect := top / bottom;
                        undefined := false;
                    end if;

                    if (not undefined) and result /= convert (expect, top_width) then
                        write (l, String'("Division error. Dividing "));
                        write (l, top);
                        write (l, String'(" by "));
                        write (l, bottom);
                        write (l, String'(" should be "));
                        write (l, expect);
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
