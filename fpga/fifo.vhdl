
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This FIFO is configurable and based on SB_RAM40_4K block RAMs.
-- + The maximum number of items in the FIFO is 2**addr_size - 1.
-- + The width of the FIFO (in bits) is 2**data_size_log_2.
-- + The maximum width is 16 bits.
-- + The minimum width is 1 bit.


entity fifo is
    generic (addr_size : Natural := 11; data_size_log_2 : Natural := 1);
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

    -- The RAM data size is always 16 bits (as the block RAMs are 256 by 16)
    constant ram_data_size_log_2  : Natural := 4;
    constant ram_data_size  : Natural := 2 ** ram_data_size_log_2;

    -- Internally the address registers for read and write have this structure:
    --
    --    msb                                    lsb
    --   +------------+---------------+-------------+
    --   | row_select | raddr/waddr   | mask_select |
    --   +------------+---------------+-------------+

    -- mask_select chooses a subset of the data bits
    -- + There may be 0..4 mask_select bits
    constant mask_select_size   : Natural := ram_data_size_log_2 - data_size_log_2;
    subtype t_addr_mask_select is std_logic_vector (mask_select_size - 1 downto 0);

    -- raddr/waddr is passed to each block RAM:
    -- + The width is always 8 bits (as the block RAMs are 256 by 16)
    constant ram_addr_size      : Natural := 8;
    subtype t_addr_ram is std_logic_vector (ram_addr_size - 1 downto 0);

    -- row_select is the block RAM number:
    -- + There may be 0 row_select bits, or any positive number.
    -- + (2**row_select'Length) block RAMs are generated to meet the configured addr_size.
    function calc_row_select_size return Natural is
    begin
        if addr_size <= (mask_select_size + ram_addr_size) then
            -- One block RAM is sufficient
            return 0;
        else
            -- Need multiple block RAMs
            return addr_size - (mask_select_size + ram_addr_size);
        end if;
    end calc_row_select_size;
    constant row_select_size    : Natural := calc_row_select_size;

    -- row_select can be zero, which is tricky for creating a row_select type, because it would have 0 width,
    -- so we assign a 1 bit width for the row select type.
    function calc_row_select_type_size return Natural is
    begin
        if row_select_size = 0 then
            return 1;
        else
            return row_select_size;
        end if;
    end calc_row_select_type_size;
    constant row_select_type_size    : Natural := calc_row_select_type_size;
    subtype t_addr_row_select is std_logic_vector (row_select_type_size - 1 downto 0);

    -- The address register size.
    -- + This could be larger than addr_size
    constant reg_addr_size      : Natural := mask_select_size + ram_addr_size + row_select_size;
    subtype t_reg_addr is std_logic_vector (reg_addr_size - 1 downto 0);

    -- Unused address bits
    -- If only a subset of the address register bits are needed, we ignore higher ones:
    function calc_unused_reg_addr_bits return Natural is
    begin
        if reg_addr_size > addr_size then
            return reg_addr_size - addr_size;
        else
            return 0;
        end if;
    end calc_unused_reg_addr_bits;
    constant unused_reg_addr_bits : Natural := calc_unused_reg_addr_bits;

    -- Number of block RAMs
    constant num_rows       : Natural := 2 ** row_select_size;

    -- Number of data bits
    constant data_size      : Natural := 2 ** data_size_log_2;

    -- Data bus size (set by RAM definition - 16 bits wide)
    subtype t_ram_data is std_logic_vector (ram_data_size - 1 downto 0);
    type t_data_rows is array (0 to num_rows - 1) of t_ram_data;

    -- Block RAM definition
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

    -- Registers
    signal write_addr               : t_reg_addr := (others => '0');
    signal read_addr                : t_reg_addr := (others => '0');
    signal row_mux_reg              : t_addr_row_select := (others => '0');
    signal mask_mux_reg             : t_addr_mask_select := (others => '0');

    -- Global signals and buses
    signal do_read                  : std_logic := '0';
    signal read_data                : t_data_rows := (others => (others => '0'));
    signal write_data               : t_ram_data := (others => '0');
    signal write_mask               : t_ram_data := (others => '0');
    signal used_bits_mask           : t_reg_addr := (others => '0');
    signal write_addr_next          : t_reg_addr := (others => '0');
    signal read_addr_next           : t_reg_addr := (others => '0');
    signal full_sig                 : std_logic := '0';
    signal empty_sig                : std_logic := '1';
    signal read_addr_half           : std_logic := '0';
    signal write_addr_row_select    : t_addr_row_select := (others => '0');
    signal write_addr_ram           : t_addr_ram := (others => '0');
    signal write_addr_mask_select   : t_addr_mask_select := (others => '0');
    signal read_addr_row_select     : t_addr_row_select := (others => '0');
    signal read_addr_ram            : t_addr_ram := (others => '0');
    signal read_addr_mask_select    : t_addr_mask_select := (others => '0');


begin
    -- Block RAMs are generated here
    rows : for row in 0 to num_rows - 1 generate
        signal do_write     : std_logic := '0';
        constant one        : std_logic := '1';
    begin
        do_write <= (write_in and not full_sig) when to_integer (unsigned (write_addr_row_select)) = row else '0';

        ram : SB_RAM40_4K
            generic map (
                READ_MODE => 0,
                WRITE_MODE => 0)
            port map (
                WADDR => write_addr_ram,
                WDATA => write_data,
                MASK => write_mask,
                WE => do_write,
                WCLKE => one,
                WCLK => clock_in,
                RADDR => read_addr_ram,
                RDATA => read_data (row),
                RE => do_read,
                RCLKE => one,
                RCLK => clock_in);
    end generate rows;

    -- Generate write mask bus
    wmb : process (write_addr)
    begin
        write_mask <= (others => '1'); -- 1 = don't write
        for i in 0 to data_size - 1 loop
            write_mask (((to_integer (unsigned (write_addr_mask_select))) * data_size) + i) <= '0';
        end loop;
    end process wmb;

    -- Generate write data bus
    wdb : process (data_in)
    begin
        for i in 0 to ram_data_size - 1 loop
            write_data (i) <= data_in (i mod data_size);
        end loop;
    end process wdb;

    -- Generate multiplexer for data output
    dom : process (data_in)
    begin
        for i in 0 to data_size - 1 loop
            data_out (i) <= read_data
                (to_integer (unsigned (row_mux_reg)))
                ((to_integer (unsigned (mask_mux_reg)) * data_size) + i);
        end loop;
    end process dom;

    -- Generate used bits mask (for when only one block RAM is needed)
    make_used_bits_mask : for i in 0 to reg_addr_size - 1 generate
        used_bits_mask (i) <= '1' when i < addr_size else '0';
    end generate make_used_bits_mask;

    -- Generate bit slices of the address registers
    -- The row select is tricky, because there may be 0 row select bits, in which case the row select
    -- bit slices still have width 1 for ease of use elsewhere.
    bs : process (write_addr, read_addr)
    begin
        if row_select_size /= 0 then
            write_addr_row_select <= write_addr (reg_addr_size - 1 downto ram_addr_size + mask_select_size);
            read_addr_row_select <= read_addr (reg_addr_size - 1 downto ram_addr_size + mask_select_size);
        else
            write_addr_row_select <= "0";
            read_addr_row_select <= "0";
        end if;
    end process bs;

    -- Generate lower bit slices
    write_addr_ram <= write_addr (ram_addr_size + mask_select_size - 1 downto mask_select_size);
    read_addr_ram <= read_addr (ram_addr_size + mask_select_size - 1 downto mask_select_size);

    write_addr_mask_select <= write_addr (mask_select_size - 1 downto 0);
    read_addr_mask_select <= read_addr (mask_select_size - 1 downto 0);

    -- Generate global signals
    do_read <= read_in and not empty_sig;
    write_addr_next <= std_logic_vector (unsigned (write_addr) + 1) and used_bits_mask;
    read_addr_next <= std_logic_vector (unsigned (read_addr) + 1) and used_bits_mask;
    empty_sig <= '1' when (read_addr = write_addr) else '0';
    full_sig <= '1' when (read_addr = write_addr_next) else '0';
    read_addr_half <= '1'
            when (std_logic_vector (unsigned (read_addr) + to_unsigned (2 ** (addr_size - 1), reg_addr_size))
                          and used_bits_mask) = write_addr else '0';

    -- Generate outputs that copy global signals
    empty_out <= empty_sig;
    full_out <= full_sig;

    -- Write address register
    wa : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            write_error <= '0';
            if write_in = '1' then
                if full_sig = '1' then
                    -- Write is not allowed
                    write_error <= '1';
                else
                    -- Write ok, move to next address
                    write_addr <= write_addr_next;
                end if;
            end if;
            if reset_in = '1' then
                write_error <= '0';
                write_addr <= (others => '0');
            end if;
        end if;
    end process wa;

    -- Read address register and multiplexer registers
    ra : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            read_error <= '0';
            if read_in = '1' then
                if empty_sig = '1' then
                    -- Read is not allowed
                    read_error <= '1';
                else
                    -- Read ok, move to next address
                    read_addr <= read_addr_next;
                    -- Previous address used for multiplexing
                    row_mux_reg <= read_addr_row_select;
                    mask_mux_reg <= read_addr_mask_select;
                end if;
            end if;
            if reset_in = '1' then
                read_error <= '0';
                row_mux_reg <= (others => '0');
                mask_mux_reg <= (others => '0');
                read_addr <= (others => '0');
            end if;
        end if;
    end process ra;

    -- Control for halfway marker
    hw : process (clock_in)
        variable inc, dec : boolean := false;
    begin
        if clock_in'event and clock_in = '1' then
            inc := write_in = '1' and full_sig = '0';
            dec := read_in = '1' and empty_sig = '0';

            if inc /= dec then
                -- Adding or removing from the FIFO, but not both
                if inc then
                    -- Adding to FIFO
                    if read_addr_half = '1' then
                        half_out <= '1';
                    end if;
                else
                    -- Removing from FIFO
                    if read_addr_half = '1' then
                        half_out <= '0';
                    end if;
                end if;
            end if;
            if reset_in = '1' then
                half_out <= '0';
            end if;
        end if;
    end process hw;


end structural;
