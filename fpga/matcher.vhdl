
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

    subtype t_address is unsigned (6 downto 0);
    subtype t_sample is std_logic_vector (23 downto 0);

    constant zero_address : t_address := (others => '0');
    constant max_address  : t_address := to_unsigned (79, 7);

    signal address      : t_address := (others => '0');
    signal data_match   : t_sample := (others => '0');
    signal left_in      : t_sample := (others => '0');
    signal right_in     : t_sample := (others => '0');

    component match_rom is
        port (
            address_in       : in std_logic_vector (6 downto 0) := (others => '0');
            data_out         : out std_logic_vector (23 downto 0) := (others => '0');
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
            data_out => data_match,
            clock => clock);

    left_in <= left_data_in (27 downto 4);
    right_in <= right_data_in (27 downto 4);

    process (clock)
    begin
        if clock = '1' and clock'event then
            if left_strobe_in = '1' then
                if address (address'Right) = '1' then
                    -- Two left samples in a row - desync
                    sync_out <= '0';
                    address <= zero_address;
                elsif address = zero_address then
                    -- First left sample shows the sample rate
                    sample_rate_out <= left_in (23 downto 8);
                    address <= address + 1;
                elsif data_match = left_in then
                    -- Matching left sample
                    address <= address + 1;
                else
                    -- Non-matching left sample
                    sync_out <= '0';
                end if;

            elsif right_strobe_in = '1' then
                if address (address'Right) = '0' then
                    -- Two right samples in a row - desync
                    sync_out <= '0';
                    address <= zero_address;
                elsif data_match = right_in then
                    -- Matching right sample
                    if address = max_address then
                        -- All samples matched, repeat
                        address <= zero_address;
                        sync_out <= '1';
                    else
                        address <= address + 1;
                    end if;
                else
                    -- Non-matching right sample
                    sync_out <= '0';
                    address <= zero_address;
                end if;
            end if;
        end if;
    end process;

end structural;
