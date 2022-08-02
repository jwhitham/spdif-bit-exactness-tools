-- This is a fixed-size delay which stores 255 items of size 16 bits.
--
-- Each input (strobe_in) will be followed by an output after 2 clock cycles
-- provided that the delay is full.
--
-- Inputs are allowed every 2 clock cycles. error_out will be asserted if
-- an input is attempted when the delay is not ready.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity delay1 is
    port (
        data_in     : in std_logic_vector (15 downto 0);
        data_out    : out std_logic_vector (15 downto 0);
        strobe_in   : in std_logic;
        strobe_out  : out std_logic;
        error_out   : out std_logic;
        reset_in    : in std_logic;
        clock_in    : in std_logic);
end delay1;

architecture structural of delay1 is

    constant ram_data_size        : Natural := 16;
    constant ram_addr_size        : Natural := 8;

    subtype t_ram_addr is std_logic_vector (ram_addr_size - 1 downto 0);
    subtype t_ram_data is std_logic_vector (ram_data_size - 1 downto 0);

    type t_state is (READY, READ_DATA, WRITE_OUT);

    constant one            : std_logic := '1';
    constant mask           : t_ram_data := (others => '0');
    constant zero_addr      : t_ram_addr := (others => '0');
    signal addr             : t_ram_addr := (others => '0');
    signal state            : t_state := READY;
    signal refilled         : std_logic := '0';
    signal write_enable     : std_logic := '0';
    signal read_enable      : std_logic := '0';

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
    begin
        if clock_in'event and clock_in = '1' then
            error_out <= '0';
            strobe_out <= '0';
            case state is
                when READY =>
                    if strobe_in = '1' then
                        addr <= std_logic_vector (unsigned (addr) + 1);
                        state <= READ_DATA;
                    end if;
                when READ_DATA =>
                    assert strobe_in = '0';
                    error_out <= strobe_in;
                    if addr = zero_addr then
                        refilled <= '1';
                    end if;
                    state <= WRITE_OUT;
                when WRITE_OUT =>
                    assert strobe_in = '0';
                    error_out <= strobe_in;
                    strobe_out <= refilled;
                    state <= READY;
            end case;
            if reset_in = '1' then
                state <= READY;
                refilled <= '0';
                addr <= zero_addr;
            end if;
        end if;
    end process generate_addr;

    write_enable <= strobe_in when state = READY else '0';
    read_enable <= '1' when state = READ_DATA else '0';

    ram : SB_RAM40_4K
        generic map (
            READ_MODE => 0,
            WRITE_MODE => 0)
        port map (
            WADDR => addr,
            WDATA => data_in,
            MASK => mask,
            WE => write_enable,
            WCLKE => one,
            WCLK => clock_in,
            RADDR => addr,
            RDATA => data_out,
            RE => read_enable,
            RCLKE => one,
            RCLK => clock_in);


end structural;
