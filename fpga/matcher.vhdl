
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
        quality_out     : out std_logic := '0';
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

    type t_match is (EXACT_24, ROUND_16, RESET);
    signal current_match : t_match := RESET;

    function match_assessment (a_in, b_in  : t_sample;
                               prev_match  : t_match) return t_match is
        variable a, b, d : signed (15 downto 0);
    begin
        if a_in = b_in then
            case prev_match is
                when RESET | EXACT_24 =>
                    return EXACT_24;
                when ROUND_16 =>
                    return ROUND_16;
            end case;
        end if;

        a := signed (a_in (23 downto 8));
        b := signed (b_in (23 downto 8));
        d := a - b;
        if d = 0 or d = -1 or d = 1 then
            return ROUND_16;
        else
            return RESET;
        end if;
    end match_assessment;

begin
    mr : match_rom
        port map (
            address_in => std_logic_vector (address),
            data_out => data_match,
            clock => clock);

    left_in <= left_data_in (27 downto 4);
    right_in <= right_data_in (27 downto 4);

    process (clock)
        variable m : t_match := RESET;
    begin
        if clock = '1' and clock'event then
            if left_strobe_in = '1' then
                m := match_assessment (left_in, data_match, current_match);
                if address (address'Right) = '1' then
                    -- Two left samples in a row - desync
                    current_match <= RESET;
                    address <= zero_address;
                elsif address = zero_address then
                    -- First left sample shows the sample rate
                    sample_rate_out <= left_in (23 downto 8);
                    address <= address + 1;
                elsif m /= RESET then
                    -- Matching left sample
                    current_match <= m;
                    address <= address + 1;
                else
                    -- Non-matching left sample
                    current_match <= RESET;
                    address <= zero_address;
                end if;

            elsif right_strobe_in = '1' then
                m := match_assessment (right_in, data_match, current_match);
                if address (address'Right) = '0' then
                    -- Two right samples in a row - desync
                    current_match <= RESET;
                    address <= zero_address;
                elsif m /= RESET then
                    -- Matching right sample
                    current_match <= m;
                    if address = max_address then
                        -- All samples matched, repeat
                        address <= zero_address;
                    else
                        address <= address + 1;
                    end if;
                else
                    -- Non-matching right sample
                    current_match <= RESET;
                    address <= zero_address;
                end if;
            end if;
        end if;
    end process;

    process (clock)
    begin
        if clock = '1' and clock'event then
            case current_match is
                when RESET =>
                    sync_out <= '0';
                    quality_out <= '0';
                when ROUND_16 =>
                    if address = zero_address then
                        sync_out <= '1';
                        quality_out <= '0';
                    end if;
                when EXACT_24 =>
                    if address = zero_address then
                        sync_out <= '1';
                        quality_out <= '1';
                    end if;
            end case;
        end if;
    end process;


end structural;
