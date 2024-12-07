-- Test case for configurable FIFO

library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use debug_textio.all;

entity test_fifo is
end test_fifo;

architecture structural of test_fifo is

    type t_test_spec is record
            addr_size       : Natural;
            data_size_log_2 : Natural;
            threshold_level : Real;
        end record;
    type t_test_spec_table is array (Natural range <>) of t_test_spec;

    -- Try various combinations of address size and data size
    constant test_spec_table : t_test_spec_table :=
         -- One row and one column
        ((6, 0, 0.5), (6, 1, 0.5), (6, 2, 0.5), (6, 3, 0.5), (6, 4, 0.5), (12, 0, 0.5), (8, 4, 0.5), (4, 0, 0.5),
         -- Different thresholds
         (12, 0, 0.05), (12, 0, 0.15), (12, 0, 0.9), (12, 0, 0.33333),
         -- Two rows one column
         (13, 0, 0.5), (9, 4, 0.5),
         -- Many rows one column
         (16, 0, 0.5), (14, 4, 0.5), 
         -- One row two columns
         (6, 5, 0.5), (8, 5, 0.5),
         -- One row four columns
         (8, 6, 0.5),
         -- Four rows four columns
         (10, 6, 0.5));
    constant num_tests       : Natural := test_spec_table'Length;
    signal done              : std_logic_vector (0 to num_tests) := (others => '0');
    signal clock             : std_logic := '0';

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

    ftest : for spec_index in 0 to num_tests - 1 generate

        constant data_size_log_2 : Natural := test_spec_table (spec_index).data_size_log_2;
        constant data_size       : Natural := 2 ** data_size_log_2;
        constant addr_size       : Natural := test_spec_table (spec_index).addr_size;
        constant full_size       : Natural := 2 ** addr_size;
        constant threshold_level : Real := test_spec_table (spec_index).threshold_level;
        constant thresh_point    : Natural := Natural (Real (full_size) * threshold_level);
        constant inv_thresh_point : Natural := full_size - thresh_point;

        subtype t_data is std_logic_vector (data_size - 1 downto 0);

        signal data_in     : t_data := (others => '0');
        signal data_out    : t_data := (others => '0');
        signal empty       : std_logic := '0';
        signal full        : std_logic := '0';
        signal thresh      : std_logic := '0';
        signal do_write    : std_logic := '0';
        signal do_read     : std_logic := '0';
        signal reset       : std_logic := '0';
        signal write_error : std_logic := '0';
        signal read_error  : std_logic := '0';
    begin

        f : entity fifo
            generic map (addr_size => addr_size,
                         data_size_log_2 => data_size_log_2,
                         threshold_level => threshold_level)
            port map (
                data_in => data_in,
                data_out => data_out,
                empty_out => empty,
                full_out => full,
                thresh_out => thresh,
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
                check_thresh : std_logic := '0') is
            begin
                assert write_error = check_write_error;
                assert read_error = check_read_error;
                assert empty = check_empty;
                assert full = check_full;
                assert thresh = check_thresh;
            end check;
        begin
            -- initial state
            done (spec_index + 1) <= '0';
            do_write <= '0';
            do_read <= '0';
            reset <= '0';
            check (check_empty => '1');
            wait until done (spec_index) = '1';
            write (l, String'("begin test for addr_size = "));
            write (l, addr_size);
            write (l, String'(" data_size = "));
            write (l, data_size);
            write (l, String'(" threshold_level = "));
            write (l, threshold_level);
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

            -- fill to thresh_point
            for i in 1 to thresh_point loop
                data_in <= hash (i);
                do_write <= '1';
                wait for 1 us;
                do_write <= '0';
                check;
                assert data_out = hash (8);
            end loop;
            -- thresh_point flag asserted now
            for i in thresh_point + 1 to full_size - 2 loop
                data_in <= hash (i);
                do_write <= '1';
                wait for 1 us;
                do_write <= '0';
                check (check_thresh => '1');
                assert data_out = hash (8);
            end loop;
            -- full flag asserted after the final write
            data_in <= hash (98);
            do_write <= '1';
            wait for 1 us;
            do_write <= '0';
            check (check_thresh => '1', check_full => '1');
            assert data_out = hash (8);
            -- error if trying to write again
            data_in <= hash (97);
            do_write <= '1';
            wait for 1 us;
            do_write <= '0';
            check (check_thresh => '1', check_full => '1', check_write_error => '1');
            assert data_out = hash (8);

            -- empty to thresh_point
            for i in 1 to inv_thresh_point - 1 loop
                do_read <= '1';
                wait for 1 us;
                do_read <= '0';
                check (check_thresh => '1');
                assert data_out = hash (i);
            end loop;
            -- empty to one left 
            for i in inv_thresh_point to full_size - 2 loop
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
            done (spec_index + 1) <= '1';
            wait;
        end process;
    end generate ftest;


end structural;
