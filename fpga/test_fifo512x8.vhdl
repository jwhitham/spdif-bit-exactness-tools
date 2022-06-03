
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_fifo512x8 is
end test_fifo512x8;

architecture structural of test_fifo512x8 is

    component fifo512x8 is
        port (
            data_in     : in std_logic_vector (7 downto 0);
            data_out    : out std_logic_vector (7 downto 0) := "00000000";
            empty_out   : out std_logic := '1';
            full_out    : out std_logic := '0';
            half_out    : out std_logic := '0';
            write_error : out std_logic := '0';
            read_error  : out std_logic := '0';
            reset_in    : in std_logic;
            clock_in    : in std_logic;
            write_in    : in std_logic;
            read_in     : in std_logic);
    end component fifo512x8;

    signal data_in     : std_logic_vector (7 downto 0) := "00000000";
    signal data_out    : std_logic_vector (7 downto 0) := "00000000";
    signal empty       : std_logic := '0';
    signal full        : std_logic := '0';
    signal half        : std_logic := '0';
    signal clock       : std_logic := '0';
    signal do_write    : std_logic := '0';
    signal do_read     : std_logic := '0';
    signal reset       : std_logic := '0';
    signal done        : std_logic := '0';
    signal write_error : std_logic := '0';
    signal read_error  : std_logic := '0';
begin

    fifo : fifo512x8
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
    begin
        while done /= '1' loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    process
        variable l : line;
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
        done <= '0';
        do_write <= '0';
        do_read <= '0';
        reset <= '0';
        check (check_empty => '1');

        -- initial state should be stable
        wait for 500 ns;
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
        data_in <= x"55";
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
        assert data_out = x"55";

        -- read when empty: error, but the output holds
        do_read <= '1';
        wait for 1 us;
        check (check_empty => '1', check_read_error => '1');
        do_read <= '0';
        assert data_out = x"55";

        -- output is held in place
        wait for 1 us;
        check (check_empty => '1');
        assert data_out = x"55";

        -- check throughput, with up to 3 items in the FIFO
        for i in 1 to 3 loop
            data_in <= std_logic_vector (to_unsigned (i, 8));
            do_write <= '1';
            wait for 1 us;
            do_write <= '0';
            check;
        end loop;
        for i in 4 to 8 loop
            data_in <= std_logic_vector (to_unsigned (i, 8));
            do_read <= '1';
            do_write <= '1';
            wait for 1 us;
            do_read <= '0';
            do_write <= '0';
            assert data_out = std_logic_vector (to_unsigned (i - 3, 8));
            check;
        end loop;
        for i in 9 to 11 loop
            check;
            data_in <= std_logic_vector (to_unsigned (i, 8));
            do_read <= '1';
            wait for 1 us;
            do_read <= '0';
            assert data_out = std_logic_vector (to_unsigned (i - 3, 8));
        end loop;
        check (check_empty => '1');

        -- fill to halfway
        for i in 1 to 256 loop
            data_in <= std_logic_vector (to_unsigned (i mod 256, 8));
            do_write <= '1';
            wait for 1 us;
            do_write <= '0';
            check;
            assert data_out = std_logic_vector (to_unsigned (8, 8));
        end loop;
        -- halfway flag asserted after the 257th write
        for i in 257 to 510 loop
            data_in <= std_logic_vector (to_unsigned (i mod 256, 8));
            do_write <= '1';
            wait for 1 us;
            do_write <= '0';
            check (check_half => '1');
            assert data_out = std_logic_vector (to_unsigned (8, 8));
        end loop;
        -- full flag asserted after the 511th write
        data_in <= x"55";
        do_write <= '1';
        wait for 1 us;
        do_write <= '0';
        check (check_half => '1', check_full => '1');
        assert data_out = std_logic_vector (to_unsigned (8, 8));
        -- error if trying to write again
        data_in <= x"ee";
        do_write <= '1';
        wait for 1 us;
        do_write <= '0';
        check (check_half => '1', check_full => '1', check_write_error => '1');
        assert data_out = std_logic_vector (to_unsigned (8, 8));

        -- empty to halfway
        for i in 1 to 255 loop
            do_read <= '1';
            wait for 1 us;
            do_read <= '0';
            check (check_half => '1');
            assert data_out = std_logic_vector (to_unsigned (i mod 256, 8));
        end loop;
        -- empty to one left 
        for i in 256 to 510 loop
            do_read <= '1';
            wait for 1 us;
            do_read <= '0';
            check;
            assert data_out = std_logic_vector (to_unsigned (i mod 256, 8));
        end loop;
        -- empty flag asserted after the 511th read
        do_read <= '1';
        wait for 1 us;
        do_read <= '0';
        check (check_empty => '1');
        assert data_out = x"55";
        -- error if trying to read again
        do_read <= '1';
        wait for 1 us;
        do_read <= '0';
        check (check_empty => '1', check_read_error => '1');
        assert data_out = x"55";


        done <= '1';
        wait;
    end process;


end structural;
