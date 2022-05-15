
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matcher is
    port (
        left_data_in    : in std_logic_vector (31 downto 0);
        left_strobe_in  : in std_logic;
        right_data_in   : in std_logic_vector (31 downto 0);
        right_strobe_in : in std_logic;
        sync_out        : out std_logic := '0';
        sample_rate_out : out std_logic_vector (15 downto 0) := (others => '0');
        clock           : in std_logic
    );
end entity matcher;

architecture structural of matcher is

    subtype t_address is unsigned (5 downto 0);
    subtype t_sample is std_logic_vector (23 downto 0);

    constant zero_address : t_address := (others => '0');
    constant max_address  : t_address := to_unsigned (40, 6);

    signal address      : t_address := (others => '0');
    signal left_match   : t_sample := (others => '0');
    signal right_match  : t_sample := (others => '0');
    signal left_in      : t_sample := (others => '0');
    signal right_in     : t_sample := (others => '0');
    signal left_match_flag   : std_logic := '0';

    component match_rom is
        port (
            address_in       : in std_logic_vector (5 downto 0) := (others => '0');
            left_out         : out std_logic_vector (23 downto 0) := (others => '0');
            right_out        : out std_logic_vector (23 downto 0) := (others => '0');
            clock            : in std_logic);
    end component match_rom;

    function reverse (x : t_sample) return t_sample is
        variable y : t_sample := (others => '0');
    begin
        for i in t_sample'Range loop
            y (t_sample'Left - i) := x (i);
        end loop;
        return y;
    end reverse;

begin
    mr : match_rom
        port map (
            address_in => std_logic_vector (address),
            left_out => left_match,
            right_out => right_match,
            clock => clock);

    left_in <= left_data_in (27 downto 4);
    right_in <= right_data_in (27 downto 4);

    process (clock)
    begin
        if clock = '1' and clock'event then
            if left_strobe_in = '1' then
                if address = zero_address then
                    left_match_flag <= '1';
                    sample_rate_out <= left_in (23 downto 8);
                elsif left_match (23 downto 8) = left_in (23 downto 8) then
                    left_match_flag <= '1';
                else
                    left_match_flag <= '0';
                end if;
            end if;
        end if;
    end process;

    process (clock)
    begin
        if clock = '1' and clock'event then
            if right_strobe_in = '1' then
                if right_match (23 downto 8) = right_in (23 downto 8) and left_match_flag = '1' then
                    if address = max_address then
                        address <= zero_address;
                        sync_out <= '1';
                    else
                        address <= address + 1;
                    end if;
                else
                    sync_out <= '0';
                    address <= zero_address;
                end if;
            end if;
        end if;
    end process;

end structural;
