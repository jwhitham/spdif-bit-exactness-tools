
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity fifo is
    generic (test_addr_size : Natural := 11; data_size_log_2 : Natural := 1);
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
end fifo;

architecture structural of fifo is

    -- FIFO contains 2**test_addr_size items
    -- true_addr_size is the upper limit on test_addr_size
    constant true_addr_size : Natural := 12 - data_size_log_2;
    constant true_data_size : Natural := 16;
    constant data_size      : Natural := 2 ** data_size_log_2;
    constant mask_size      : Natural := 4 - data_size_log_2;

    subtype t_addr is std_logic_vector (true_addr_size - 1 downto 0);
    subtype t_data is std_logic_vector (true_data_size - 1 downto 0);

    signal wdata        : t_data := (others => '0');
    signal rdata        : t_data := (others => '0');
    signal waddr        : t_addr := (others => '0');
    signal raddr        : t_addr := (others => '0');
    signal mask         : t_data := (others => '0');
    signal mask_mux     : std_logic_vector (mask_size - 1 downto 0) := (others => '0');
    signal test_mask    : t_addr := (others => '1');
    signal waddr_next   : t_addr;
    signal raddr_next   : t_addr;
    signal full_sig     : std_logic := '0';
    signal empty_sig    : std_logic := '1';
    signal do_write     : std_logic := '0';
    signal do_read      : std_logic := '0';
    constant one        : std_logic := '1';

    component SB_RAM40_4K is
        generic (
            READ_MODE : Integer;
            WRITE_MODE : Integer);
        port (
            RDATA       : out std_logic_vector (15 downto 0);
            RADDR       : in std_logic_vector (7 downto 0);
            WADDR       : in std_logic_vector (7 downto 0);
            MASK        : in std_logic_vector (15 downto 0);
            WDATA       : in std_logic_vector (15 downto 0);
            RCLKE       : in std_logic;
            RCLK        : in std_logic;
            RE          : in std_logic;
            WCLKE       : in std_logic;
            WCLK        : in std_logic;
            WE          : in std_logic);
    end component SB_RAM40_4K;
begin

    ram : SB_RAM40_4K
        generic map (
            READ_MODE => 0,
            WRITE_MODE => 0)
        port map (
            WADDR => waddr (true_addr_size - 1 downto mask_size),
            WDATA => wdata,
            MASK => mask,
            WE => do_write,
            WCLKE => one,
            WCLK => clock_in,
            RADDR => raddr (true_addr_size - 1 downto mask_size),
            RDATA => rdata,
            RE => do_read,
            RCLKE => one,
            RCLK => clock_in);

    make_test_mask : for i in 0 to true_addr_size - 1 generate
        test_mask (i) <= '1' when i < test_addr_size else '0';
    end generate make_test_mask;

    process (waddr, data_in, rdata, mask_mux)
    begin
        -- Write enable:
        mask <= (others => '1'); -- 1 = don't write
        for i in 0 to data_size - 1 loop
            mask ((to_integer (unsigned (waddr (mask_size - 1 downto 0))) * data_size) + i) <= '0';
        end loop;

        -- Input to FIFO:
        for i in 0 to true_data_size - 1 loop
            wdata (i) <= data_in (i mod data_size);
        end loop;

        -- Output from FIFO:
        for i in 0 to data_size - 1 loop
            data_out (i) <= rdata ((to_integer (unsigned (mask_mux)) * data_size) + i);
        end loop;
    end process;

    waddr_next <= std_logic_vector (unsigned (waddr) + 1) and test_mask;
    raddr_next <= std_logic_vector (unsigned (raddr) + 1) and test_mask;
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
            half := (std_logic_vector
                (unsigned (raddr) + to_unsigned (2 ** (test_addr_size - 1), raddr'Length))
                    and test_mask) = waddr;

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
