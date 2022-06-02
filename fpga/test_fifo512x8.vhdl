
library ieee;
use ieee.std_logic_1164.all;

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
    signal write       : std_logic := '0';
    signal read        : std_logic := '0';
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
            write_in => write,
            read_in => read);

    process
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
        write <= '0';
        read <= '0';
        reset <= '0';
        check (check_empty => '1');

        -- initial state should be stable
        wait for 1 us;
        check (check_empty => '1');

        -- initial state reached by reset
        reset <= '1';
        wait for 1 us;
        check (check_empty => '1');

        -- read when empty (error)
        read <= '1';
        reset <= '0';
        wait for 1 us;
        check (check_empty => '1', check_read_error => '1');

        -- read error disappears
        read <= '0';
        wait for 1 us;
        check (check_empty => '1');

        -- write one
        data_in <= x"55";
        write <= '1';
        wait for 1 us;
        check;

        -- read one
        write <= '0';
        assert data_out = x"55";
        read <= '1';
        wait for 1 us;
        check (check_empty => '1');

        done <= '1';
        wait;
    end process;


end structural;
