
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity fifo is
    port (
        data_in     : in std_logic;
        data_out    : out std_logic := '0';
        empty_out   : out std_logic := '1';
        full_out    : out std_logic := '0';
        half_out    : out std_logic := '0';
        write_error : out std_logic := '0';
        read_error  : out std_logic := '0';
        reset_in    : in std_logic;
        clock_in    : in std_logic;
        write_in    : in std_logic;
        read_in     : in std_logic);
end fifo;

architecture structural of fifo is

    constant addr_size  : Natural := 12;
    constant data_size  : Natural := 16;
    constant mask_size  : Natural := 4;

    subtype t_addr is std_logic_vector (addr_size - 1 downto 0);
    subtype t_data is std_logic_vector (data_size - 1 downto 0);

    signal wdata        : t_data := (others => '0');
    signal rdata        : t_data := (others => '0');
    signal waddr        : t_addr := (others => '0');
    signal raddr        : t_addr := (others => '0');
    signal mask         : t_data := (others => '0');
    signal mask_mux     : std_logic_vector (mask_size - 1 downto 0) := (others => '0');
    signal waddr_next   : t_addr;
    signal raddr_next   : t_addr;
    signal full_sig     : std_logic := '0';
    signal empty_sig    : std_logic := '1';
    signal do_write     : std_logic := '0';
    signal do_read      : std_logic := '0';
    constant one        : std_logic := '1';

    component sb_ram40_4k is
        generic (
            read_mode : Integer;
            write_mode : Integer);
        port (
            rdata       : out std_logic_vector (15 downto 0);
            raddr       : in std_logic_vector (7 downto 0);
            waddr       : in std_logic_vector (7 downto 0);
            mask        : in std_logic_vector (15 downto 0);
            wdata       : in std_logic_vector (15 downto 0);
            rclke       : in std_logic;
            rclk        : in std_logic;
            re          : in std_logic;
            wclke       : in std_logic;
            wclk        : in std_logic;
            we          : in std_logic);
    end component sb_ram40_4k;
begin

    ram : sb_ram40_4k
        generic map (
            read_mode => 0,
            write_mode => 0)
        port map (
            waddr => waddr (addr_size - 1 downto mask_size),
            wdata => wdata,
            mask => mask,
            we => do_write,
            wclke => one,
            wclk => clock_in,
            raddr => raddr (addr_size - 1 downto mask_size),
            rdata => rdata,
            re => do_read,
            rclke => one,
            rclk => clock_in);

    process (waddr)
    begin
        mask <= (others => '0');
        mask (to_integer (unsigned (waddr (mask_size - 1 downto 0)))) <= '1';
    end process;
    data_out <= rdata (to_integer (unsigned (mask_mux)));
    wdata <= (others => data_in);

    waddr_next <= std_logic_vector (unsigned (waddr) + 1);
    raddr_next <= std_logic_vector (unsigned (raddr) + 1);
    empty_sig <= '1' when (raddr = waddr) else '0';
    full_sig <= '1' when (raddr = waddr_next) else '0';
    empty_out <= empty_sig;
    full_out <= full_sig;
    do_write <= write_in and not full_sig;
    do_read <= read_in and not empty_sig;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            -- Control for write address
            write_error <= '0';
            if write_in = '1' then
                if full_sig = '1' then
                    -- Write is not allowed
                    write_error <= '1';
                else
                    -- Write ok, move to next address
                    waddr <= waddr_next;
                end if;
            end if;
            if reset_in = '1' then
                write_error <= '0';
                waddr <= (others => '0');
            end if;
        end if;
    end process;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            -- Control for read address
            read_error <= '0';
            if read_in = '1' then
                if empty_sig = '1' then
                    -- Read is not allowed
                    read_error <= '1';
                else
                    -- Read ok, move to next address
                    raddr <= raddr_next;
                    mask_mux <= raddr (mask_size - 1 downto 0);
                end if;
            end if;
            if reset_in = '1' then
                read_error <= '0';
                raddr <= (others => '0');
                mask_mux <= (others => '0');
            end if;
        end if;
    end process;

    process (clock_in)
        variable inc, dec, half : boolean := false;
    begin
        if clock_in'event and clock_in = '1' then
            -- Control for halfway marker
            inc := write_in = '1' and full_sig = '0';
            dec := read_in = '1' and empty_sig = '0';
            half := std_logic_vector (unsigned (raddr) + to_unsigned (2 ** (addr_size - 1), raddr'Length)) = waddr;

            if inc /= dec then
                -- Adding or removing from the FIFO, but not both
                if inc then
                    -- Adding to FIFO
                    if half then
                        half_out <= '1';
                    end if;
                else
                    -- Removing from FIFO
                    if half then
                        half_out <= '0';
                    end if;
                end if;
            end if;
            if reset_in = '1' then
                half_out <= '0';
            end if;
        end if;
    end process;


end structural;
