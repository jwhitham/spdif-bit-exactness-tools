-- This is a configurable delay which stores 2 ** delay_size_log_2 items
-- of size 16 bits. delay_size_log_2 must not be larger than 8.
--
-- Each input (strobe_in) will be followed by an output after 1 clock cycle
-- provided that the delay is full.
--
-- Inputs are allowed every 3 clock cycles. error_out will be asserted if
-- an input is attempted when the delay is not ready.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity delay1 is
    generic (debug : Boolean := false;
             delay_size_log_2 : Natural);
    port (
        data_in     : in std_logic_vector (15 downto 0);
        data_out    : out std_logic_vector (15 downto 0) := (others => '0');
        strobe_in   : in std_logic;
        strobe_out  : out std_logic := '0';
        error_out   : out std_logic := '0';
        reset_in    : in std_logic;
        clock_in    : in std_logic);
end delay1;

architecture structural of delay1 is

    constant ram_data_size        : Natural := 16;
    constant ram_addr_size        : Natural := 8;

    subtype t_ram_addr is std_logic_vector (ram_addr_size - 1 downto 0);
    subtype t_delay_addr is std_logic_vector (delay_size_log_2 downto 0);
    subtype t_ram_data is std_logic_vector (ram_data_size - 1 downto 0);

    type t_state is (READ, WRITE, ADVANCE);

    constant one            : std_logic := '1';
    constant mask           : t_ram_data := (others => '0');
    constant zero_addr      : t_delay_addr := (others => '0');
    signal delay_addr       : t_delay_addr := (others => '0');
    signal ram_addr         : t_ram_addr := (others => '0');
    signal state            : t_state := READ;
    signal write_enable     : std_logic := '0';
    signal read_enable      : std_logic := '0';
    signal data_gen         : t_ram_data := (others => '0');

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

begin

    generate_addr : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            error_out <= '0';
            case state is
                when READ =>
                    error_out <= strobe_in;
                    state <= WRITE;

                when WRITE =>
                    if strobe_in = '1' then
                        if debug then
                            write (l, String'("write value "));
                            write (l, to_integer (unsigned (data_in)));
                            write (l, String'(" to address "));
                            write (l, to_integer (unsigned (delay_addr (delay_addr'Left - 1 downto 0))));
                            writeline (output, l);
                        end if;
                        state <= ADVANCE;
                    end if;

                when ADVANCE =>
                    error_out <= strobe_in;

                    -- address advances
                    delay_addr <= std_logic_vector (unsigned (delay_addr) + 1);

                    -- keep top bit of delay_addr '1' once set (indicates delay is full)
                    if delay_addr (delay_addr'Left) = '1' then
                        delay_addr (delay_addr'Left) <= '1';
                        if debug then
                            write (l, String'("read value "));
                            write (l, to_integer (unsigned (data_gen)));
                            write (l, String'(" from address "));
                            write (l, to_integer (unsigned (delay_addr (delay_addr'Left - 1 downto 0))));
                            writeline (output, l);
                        end if;
                    end if;
                    state <= READ;
            end case;
            if reset_in = '1' then
                state <= READ;
                delay_addr <= (others => '0');
                error_out <= '0';
            end if;
        end if;
    end process generate_addr;

    strobe_out <= delay_addr (delay_addr'Left) when state = ADVANCE else '0';
    write_enable <= '1' when state = WRITE else '0';
    read_enable <= '1' when state = READ else '0';
    data_out <= data_gen;

    process (delay_addr)
    begin
        ram_addr <= (others => '0');
        ram_addr (delay_addr'Left - 1 downto 0) <= delay_addr (delay_addr'Left - 1 downto 0);
    end process;

    ram : SB_RAM40_4K
        generic map (
            READ_MODE => 0,
            WRITE_MODE => 0)
        port map (
            WADDR => ram_addr,
            WDATA => data_in,
            MASK => mask,
            WE => write_enable,
            WCLKE => one,
            WCLK => clock_in,
            RADDR => ram_addr,
            RDATA => data_gen,
            RE => read_enable,
            RCLKE => one,
            RCLK => clock_in);


end structural;
