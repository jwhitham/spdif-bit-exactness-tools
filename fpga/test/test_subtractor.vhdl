library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity test_subtractor is
end test_subtractor;

use std.textio.all;

architecture test of test_subtractor is

    type t_test is record
        value_width : Natural;
        slice_width : Natural;
    end record;

    type t_test_table is array (Positive range <>) of t_test;

    constant test_table     : t_test_table :=
        ((4, 4), (4, 2), (4, 1), (4, 3), (5, 5), (5, 3), (1, 1), (2, 8));
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

    stest : for part in test_table'Range generate

        constant value_width    : Natural := test_table (part).value_width;
        constant slice_width    : Natural := test_table (part).slice_width;
        constant max_value      : Integer := (2 ** value_width) - 1;

        signal top_value        : std_logic_vector (value_width - 1 downto 0) := (others => '0');
        signal bottom_value     : std_logic_vector (value_width - 1 downto 0) := (others => '0');
        signal start            : std_logic := '0';
        signal reset            : std_logic := '0';
        signal finish           : std_logic := '0';
        signal overflow         : std_logic := '0';
        signal result           : std_logic_vector (value_width - 1 downto 0) := (others => '0');
    begin
        sub : entity subtractor
            generic map (value_width => value_width,
                         slice_width => slice_width)
            port map (
                top_value_in => top_value,
                bottom_value_in => bottom_value,
                start_in => start,
                reset_in => reset,
                finish_out => finish,
                result_out => result,
                overflow_out => overflow,
                clock_in => clock);
            
        process
            variable expect : Integer;
            variable expect_overflow : std_logic;
            variable l : line;
        begin
            done (part) <= '0';
            wait until done (part - 1) = '1';

            write (l, String'("subtractor test "));
            write (l, part);
            writeline (output, l);

            reset <= '1';
            start <= '0';
            top_value <= (others => '0');
            bottom_value <= (others => '0');
            wait for 10 us;

            reset <= '0';
            wait until clock'event and clock = '1';

            outer : for top in 0 to max_value loop
                top_value <= std_logic_vector (to_unsigned (top, value_width));

                for bottom in 0 to max_value loop
                    bottom_value <= std_logic_vector (to_unsigned (bottom, value_width));
                    start <= '1';
                    wait until clock'event and clock = '1';
                    start <= '0';
                    while finish = '0' loop
                        wait until clock'event and clock = '1';
                    end loop;
                    expect := top - bottom;
                    expect_overflow := '0';
                    if expect < 0 then
                        expect := expect + max_value + 1;
                        expect_overflow := '1';
                    end if;
                    if std_logic_vector (to_unsigned (expect, value_width)) /= result
                            or expect_overflow /= overflow then
                        write (l, String'("Subtractor error. "));
                        write (l, top);
                        write (l, String'(" - "));
                        write (l, bottom);
                        write (l, String'(" should be "));
                        write (l, expect);
                        write (l, String'(" got "));
                        write (l, to_integer (unsigned (result)));
                        if expect_overflow /= overflow then
                            write (l, String'(" overflow flag error"));
                        end if;
                        writeline (output, l);
                        assert False;
                        exit outer;
                    end if;
                end loop;
            end loop outer;
            done (part) <= '1';
            wait;
        end process;
    end generate stest;

end test;
