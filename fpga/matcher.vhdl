
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matcher is
    port (
        data_in         : in std_logic_vector (31 downto 0);
        left_strobe_in  : in std_logic;
        right_strobe_in : in std_logic;
        sync_in         : in std_logic;
        sync_out        : out std_logic_vector (1 downto 0) := "00";
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
    signal audio_in     : t_sample := (others => '0');

    component match_rom is
        port (
            address_in       : in std_logic_vector (6 downto 0) := (others => '0');
            data_out         : out std_logic_vector (23 downto 0) := (others => '0');
            clock            : in std_logic);
    end component match_rom;

    type t_match is (EXACT_24, EXACT_16, ROUND_16, RESET);
    signal current_match : t_match := RESET;

    function match_assessment (a_in, b_in  : t_sample;
                               prev_match  : t_match) return t_match is

        subtype t_sample16 is unsigned (15 downto 0);
        constant zero       : t_sample16 := (others => '0');
        constant one        : t_sample16 := (0 => '1', others => '0');
        constant minus_one  : t_sample16 := (others => '1');
        variable d          : t_sample16 := zero;
    begin
        d := unsigned (a_in (23 downto 8)) - unsigned (b_in (23 downto 8));
        if d = zero then
            if a_in (7 downto 0) = b_in (7 downto 0) then
                case prev_match is
                    when RESET =>
                        return EXACT_24;
                    when others =>
                        return prev_match;
                end case;
            else
                case prev_match is
                    when RESET | EXACT_24 =>
                        return EXACT_16;
                    when others =>
                        return prev_match;
                end case;
            end if;
        elsif d = one or d = minus_one then
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

    audio_in <= data_in (27 downto 4);

    process (clock)
        variable m : t_match := RESET;
    begin
        if clock = '1' and clock'event then
            if left_strobe_in = '1' then
                m := match_assessment (audio_in, data_match, current_match);
                if address (address'Right) = '1' then
                    -- Two left samples in a row - desync
                    current_match <= RESET;
                    address <= zero_address;
                elsif address = zero_address then
                    -- First left sample shows the sample rate
                    sample_rate_out <= audio_in (23 downto 8);
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
                m := match_assessment (audio_in, data_match, current_match);
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

            if sync_in = '0' then
                current_match <= RESET;
                address <= zero_address;
            end if;
        end if;
    end process;

    process (clock)
    begin
        if clock = '1' and clock'event then
            case current_match is
                when RESET =>
                    sync_out <= "00";
                when ROUND_16 =>
                    if address = zero_address then
                        sync_out <= "01";
                    end if;
                when EXACT_16 =>
                    if address = zero_address then
                        sync_out <= "10";
                    end if;
                when EXACT_24 =>
                    if address = zero_address then
                        sync_out <= "11";
                    end if;
            end case;
        end if;
    end process;


end structural;
