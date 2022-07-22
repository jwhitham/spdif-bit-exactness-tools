
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_multiplier is
end test_multiplier;

architecture test of test_multiplier is

    type t_test is record
        a_width       : Natural;
        b_width    : Natural;
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


        constant a_width   : Natural := test_table (part).a_width;
        constant b_width   : Natural := test_table (part).b_width;
        constant r_width   : Natural := a_width + b_width;
        constant a_max     : Natural := (2 ** a_width) - 1;
        constant b_max     : Natural := (2 ** b_width) - 1;

        function convert (value : Natural; size : Natural) return std_logic_vector is
        begin
            assert value <= ((2 ** size) - 1);
            return std_logic_vector (to_unsigned (value, size));
        end convert;

        signal a_value          : std_logic_vector (a_width - 1 downto 0) := (others => '0');
        signal b_value          : std_logic_vector (b_width - 1 downto 0) := (others => '0');
        signal start            : std_logic := '0';
        signal reset            : std_logic := '0';
        signal finish           : std_logic := '0';
        signal result           : std_logic_vector (r_width - 1 downto 0) := (others => '0');

    begin
        d : entity multiplier
            generic map (a_width => a_width,
                         b_width => b_width)
            port map (
                a_value_in => a_value,
                b_value_in => b_value,
                start_in => start,
                reset_in => reset,
                finish_out => finish,
                result_out => result,
                clock_in => clock);

        process
            variable l : line;
            variable expect : Integer;
        begin
            done (part) <= '0';
            wait until done (part - 1) = '1';
            assert finish = '0';
            wait for 1 us;

            write (l, String'("multiplication test "));
            write (l, part);
            writeline (output, l);
            outer : for a in 0 to a_max loop
                for b in 0 to b_max loop
                    a_value <= convert (a, a_width);
                    b_value <= convert (b, b_width);

                    expect := 0;

                    start <= '1';
                    wait for 1 us;

                    a_value <= (others => '0');
                    b_value <= (others => '0');
                    start <= '0';
                    assert finish = '0';
                    while finish = '0' loop
                        wait for 1 us;
                    end loop;

                    expect := a * b;

                    if result /= convert (expect, r_width) then
                        write (l, String'("Multiplication error. Multiplying "));
                        write (l, a);
                        write (l, String'(" by "));
                        write (l, b);
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
