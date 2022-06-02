
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity fifo512x8 is
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
end fifo512x8;

architecture structural of fifo512x8 is

    subtype t_addr is std_logic_vector (8 downto 0);
    signal waddr        : t_addr := (others => '0');
    signal raddr        : t_addr := (others => '0');
    signal waddr_next   : t_addr;
    signal raddr_next   : t_addr;
    signal half_threshold : std_logic;
    signal full         : std_logic;
    signal empty        : std_logic;
    signal write_now    : std_logic;
    constant one : std_logic := '1';

    component sb_ram512x8 is
        port (
            waddr       : in std_logic_vector (8 downto 0);
            wdata       : in std_logic_vector (7 downto 0);
            we          : in std_logic;
            wclke       : in std_logic;
            wclk        : in std_logic;
            raddr       : in std_logic_vector (8 downto 0);
            rdata       : out std_logic_vector (7 downto 0);
            re          : in std_logic;
            rclke       : in std_logic;
            rclk        : in std_logic);
    end component sb_ram512x8;
begin

    ram : sb_ram512x8
        port map (
            waddr => waddr,
            wdata => data_in,
            we => write_now,
            wclke => one,
            wclk => clock_in,
            raddr => raddr,
            rdata => data_out,
            re => one,
            rclke => one,
            rclk => clock_in);

    waddr_next <= std_logic_vector (unsigned (waddr) + 1);
    raddr_next <= std_logic_vector (unsigned (raddr) + 1);
    empty_out <= empty;
    full_out <= full;
    write_now <= write_in and not full;

    empty <= '1' when raddr = waddr else '0';
    full <= '1' when raddr = waddr_next else '0';
    half_threshold <= '1'
        when raddr = std_logic_vector (unsigned (waddr) + 256) else '0';

    process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            -- Track ring buffer addresses
            write_error <= '0';
            if write_in = '1' then
                if full = '1' then
                    write_error <= '1';
                else
                    waddr <= waddr_next;
                end if;
            end if;
            read_error <= '0';
            if read_in = '1' then
                if empty = '1' then
                    read_error <= '1';
                else
                    raddr <= raddr_next;
                end if;
            end if;

            -- Track half-full threshold
            if write_in = '1' and read_in = '0' then
                if half_threshold = '1' then
                    -- moving above half-full
                    half_out <= '1';
                end if;
            elsif write_in = '0' and read_in = '1' then
                if half_threshold = '1' then
                    -- moving below half-full
                    half_out <= '0';
                end if;
            end if;

            if reset_in = '1' then
                raddr <= (others => '0');
                waddr <= (others => '0');
                half_out <= '0';
            end if;
        end if;
    end process;

end structural;
