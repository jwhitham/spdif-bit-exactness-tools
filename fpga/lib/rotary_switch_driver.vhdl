-- Decode a 6-way double pole rotary switch
-- to obtain a number from 000 to 101.
-- If the input doesn't make sense, output is 111.

library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rotary_switch_driver is
    generic (clock_frequency : Real);
    port (
        clock_in            : in std_logic;
        rotary_024          : in std_logic;
        rotary_01           : in std_logic;
        rotary_23           : in std_logic;
        strobe_out          : out std_logic := '0';
        mode_out            : out std_logic_vector (2 downto 0) := (others => '0'));
end rotary_switch_driver;

architecture structural of rotary_switch_driver is

    -- Signals must be stable for at least 10ms to be recognised as valid
    constant max_countdown  : Natural := Natural (clock_frequency / 100.0);
    subtype t_countdown is Natural range 0 to max_countdown;

    -- Registers
    signal countdown        : t_countdown := max_countdown;
    signal code             : std_logic_vector (2 downto 0) := (others => '0');
    signal choice           : std_logic_vector (2 downto 0) := (others => '0');
    signal old_choice       : std_logic_vector (2 downto 0) := (others => '0');
    signal updated          : std_logic := '1';

begin
    register_inputs : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            code (0) <= rotary_024;
            code (1) <= rotary_01;
            code (2) <= rotary_23;
        end if;
    end process register_inputs;

    decode_inputs : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            case code is
                when "100" => choice <= "000"; -- rotary_01 low: choice is 0
                when "101" => choice <= "001"; --                choice is 1
                when "010" => choice <= "010"; -- rotary_23 low: choice is 2
                when "011" => choice <= "011"; --                choice is 3
                when "110" => choice <= "100"; -- 01 / 23 high:  choice is 4
                when "111" => choice <= "101"; --                choice is 5
                when others => choice <= "111"; -- invalid (both 01 and 23 are low)
            end case;
        end if;
    end process decode_inputs;

    await_stability : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            old_choice <= choice;
            strobe_out <= '0';
            if choice /= old_choice then
                countdown <= max_countdown;
                updated <= '1';
            elsif countdown = 0 then
                strobe_out <= updated;
                mode_out <= choice;
                updated <= '0';
            else
                countdown <= countdown - 1;
            end if;
        end if;
    end process await_stability;

end architecture structural;
