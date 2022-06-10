
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_fifo is
end test_fifo;

architecture structural of test_fifo is

    component fifo is
        generic (test_addr_size : Natural := 12; data_size_log_2 : Natural := 1);
        port (
            data_in     : in std_logic_vector ((2 ** data_size_log_2) - 1 downto 0);
            data_out    : out std_logic_vector ((2 ** data_size_log_2) - 1 downto 0) := (others => '0');
            empty_out   : out std_logic := '1';
            full_out    : out std_logic := '0';
            half_out    : out std_logic := '0';
            write_error : out std_logic := '0';
            read_error  : out std_logic := '0';
            reset_in    : in std_logic;
            clock_in    : in std_logic;
            write_in    : in std_logic;
            read_in     : in std_logic);
    end component fifo;

    signal done        : std_logic_vector (0 to 6) := (others => '0');
    signal clock       : std_logic := '0';
begin


    process
    begin
        done (0) <= '1';
        wait for 500 ns;
        while done (6) /= '1' loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    ftest : for test_size in 1 to 6 generate

        constant data_size_log_2 : Natural := ((test_size - 1) / 2); -- 0 or 1 or 2
        constant data_size       : Natural := 2 ** data_size_log_2;  -- 1 or 2 or 4
        constant addr_size       : Natural := (6 * (((test_size - 1) mod 2) + 1)) - data_size_log_2;
                -- 6, 12, 5, 11, 4, 10
        constant full_size       : Natural := 2 ** addr_size;
        constant halfway         : Natural := full_size / 2;

        subtype t_data is std_logic_vector (data_size - 1 downto 0);

        signal data_in     : t_data := (others => '0');
        signal data_out    : t_data := (others => '0');
        signal empty       : std_logic := '0';
        signal full        : std_logic := '0';
        signal half        : std_logic := '0';
        signal do_write    : std_logic := '0';
        signal do_read     : std_logic := '0';
        signal reset       : std_logic := '0';
        signal write_error : std_logic := '0';
        signal read_error  : std_logic := '0';
    begin

        f : fifo
            generic map (test_addr_size => addr_size, data_size_log_2 => data_size_log_2)
            port map (
                data_in => data_in,
                data_out => data_out,
                empty_out => empty,
                full_out => full,
                half_out => half,
                write_error => write_error,
                read_error => read_error,
                reset_in => reset,
                clock_in => clock,
                write_in => do_write,
                read_in => do_read);

        process
            variable l : line;

            function hash (x : Integer) return t_data is
                constant table : std_logic_vector (127 downto 0) :=
                    x"aaeb0f31668a6fe22515e558c7e2fb06";
                variable r : t_data := (others => '0');
            begin
                for i in 0 to data_size - 1 loop
                    r (i) := table (((x * data_size) + i) mod 127);
                end loop;
                return r;
            end hash;

            procedure check
               (check_write_error : std_logic := '0';
                check_read_error : std_logic := '0';
                check_empty : std_logic := '0';
                check_full : std_logic := '0';
                check_half : std_logic := '0') is
            begin
                assert write_error = check_write_error;
                assert read_error = check_read_error;
                assert empty = check_empty;
                assert full = check_full;
                assert half = check_half;
            end check;
        begin
            -- initial state
            done (test_size) <= '0';
            do_write <= '0';
            do_read <= '0';
            reset <= '0';
            check (check_empty => '1');
            wait until done (test_size - 1) = '1';
            write (l, String'("begin test for addr_size = "));
            write (l, addr_size);
            write (l, String'(" data_size = "));
            write (l, data_size);
            writeline (output, l);

            -- initial state should be stable
            wait for 1 us;
            check (check_empty => '1');
            wait for 1 us;
            check (check_empty => '1');

            -- initial state reached by reset
            reset <= '1';
            wait for 1 us;
            check (check_empty => '1');
            reset <= '0';

            -- read when empty (error)
            do_read <= '1';
            wait for 1 us;
            check (check_empty => '1', check_read_error => '1');
            do_read <= '0';

            -- read error disappears
            wait for 1 us;
            check (check_empty => '1');

            -- write one
            data_in <= hash (99);
            do_write <= '1';
            wait for 1 us;
            check;
            do_write <= '0';
            wait for 10 us;

            -- read one
            do_read <= '1';
            wait for 1 us;
            do_read <= '0';
            check (check_empty => '1');
            assert data_out = hash (99);

            -- read when empty: error, but the output holds
            do_read <= '1';
            wait for 1 us;
            check (check_empty => '1', check_read_error => '1');
            do_read <= '0';
            assert data_out = hash (99);

            -- output is held in place
            wait for 1 us;
            check (check_empty => '1');
            assert data_out = hash (99);

            -- check throughput, with up to 3 items in the FIFO
            for i in 1 to 3 loop
                data_in <= hash (i);
                do_write <= '1';
                wait for 1 us;
                do_write <= '0';
                check;
            end loop;
            for i in 4 to 8 loop
                data_in <= hash (i);
                do_read <= '1';
                do_write <= '1';
                wait for 1 us;
                do_read <= '0';
                do_write <= '0';
                assert data_out = hash (i - 3);
                check;
            end loop;
            for i in 9 to 11 loop
                check;
                data_in <= hash (i);
                do_read <= '1';
                wait for 1 us;
                do_read <= '0';
                assert data_out = hash (i - 3);
            end loop;
            check (check_empty => '1');

            -- fill to halfway
            for i in 1 to halfway loop
                data_in <= hash (i);
                do_write <= '1';
                wait for 1 us;
                do_write <= '0';
                check;
                assert data_out = hash (8);
            end loop;
            -- halfway flag asserted after the 50% write
            for i in halfway + 1 to full_size - 2 loop
                data_in <= hash (i);
                do_write <= '1';
                wait for 1 us;
                do_write <= '0';
                check (check_half => '1');
                assert data_out = hash (8);
            end loop;
            -- full flag asserted after the final write
            data_in <= hash (98);
            do_write <= '1';
            wait for 1 us;
            do_write <= '0';
            check (check_half => '1', check_full => '1');
            assert data_out = hash (8);
            -- error if trying to write again
            data_in <= hash (97);
            do_write <= '1';
            wait for 1 us;
            do_write <= '0';
            check (check_half => '1', check_full => '1', check_write_error => '1');
            assert data_out = hash (8);

            -- empty to halfway
            for i in 1 to halfway - 1 loop
                do_read <= '1';
                wait for 1 us;
                do_read <= '0';
                check (check_half => '1');
                assert data_out = hash (i);
            end loop;
            -- empty to one left 
            for i in halfway to full_size - 2 loop
                do_read <= '1';
                wait for 1 us;
                do_read <= '0';
                check;
                assert data_out = hash (i);
            end loop;
            -- empty flag asserted after the final read
            do_read <= '1';
            wait for 1 us;
            do_read <= '0';
            check (check_empty => '1');
            assert data_out = hash (98);
            -- error if trying to read again
            do_read <= '1';
            wait for 1 us;
            do_read <= '0';
            check (check_empty => '1', check_read_error => '1');
            assert data_out = hash (98);

            write (l, String'("end test for addr_size = "));
            write (l, addr_size);
            writeline (output, l);
            done (test_size) <= '1';
            wait;
        end process;
    end generate ftest;


end structural;
