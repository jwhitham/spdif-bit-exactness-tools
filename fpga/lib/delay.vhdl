-- This is a configurable delay which stores 2 ** delay_size_log_2 items
-- of size 16 bits.
--
-- Each input (strobe_in) will be followed by an output after 1 clock cycle
-- provided that the delay is full.
--
-- Inputs are allowed every 3 clock cycles. error_out will be asserted if
-- an input is attempted when the delay is not ready.

library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity delay is
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
end delay;

architecture structural of delay is

    function get_sub_delay_size_log_2 return Natural is
    begin
        if delay_size_log_2 <= 8 then
            return delay_size_log_2;
        else
            return 8;
        end if;
    end get_sub_delay_size_log_2;

    function get_num_delays return Natural is
    begin
        if delay_size_log_2 > 8 then
            return 2 ** (delay_size_log_2 - 8);
        else
            return 1;
        end if;
    end get_num_delays;

    constant sub_delay_size_log_2 : Natural := get_sub_delay_size_log_2;
    constant num_delays           : Natural := get_num_delays;
    constant ram_data_size        : Natural := 16;

    subtype t_ram_data is std_logic_vector (ram_data_size - 1 downto 0);
    type t_bus is record
        data    : t_ram_data;
        strobe  : std_logic;
        err     : std_logic;
        reset   : std_logic;
    end record;
        
    type t_buses is array (Natural range 0 to num_delays) of t_bus;
    constant zero       : t_ram_data := (others => '0');
    constant off        : t_bus := (zero, '0', '0', '0');
    signal buses        : t_buses := (others => off);

begin
    buses (0).data <= data_in;
    buses (0).strobe <= strobe_in;
    buses (0).err <= '0';
    buses (num_delays).reset <= reset_in;
    data_out <= buses (num_delays).data;
    strobe_out <= buses (num_delays).strobe;
    error_out <= buses (num_delays).err;

    g : for i in 1 to num_delays generate
        signal err : std_logic := '0';
    begin
        d : entity delay1
            generic map (debug => debug, delay_size_log_2 => sub_delay_size_log_2)
            port map (
                data_in => buses (i - 1).data,
                strobe_in => buses (i - 1).strobe,
                data_out => buses (i).data,
                strobe_out => buses (i).strobe,
                error_out => err,
                reset_in => buses (i).reset,
                clock_in => clock_in);

        process (clock_in)
        begin
            if clock_in'event and clock_in = '1' then
                buses (i - 1).reset <= buses (i).reset;
                buses (i).err <= buses (i - 1).err or err;
            end if;
        end process;
    end generate g;

end structural;
