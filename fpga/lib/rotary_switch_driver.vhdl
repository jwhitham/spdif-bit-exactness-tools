-- Decode a 6-way double pole rotary switch
-- to obtain a number from 000 to 101.
-- Buttons may also be used to temporarily override the rotary switch.

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
        left_button         : in std_logic;
        right_button        : in std_logic;
        strobe_out          : out std_logic := '0';
        value_out           : out std_logic_vector (2 downto 0) := (others => '0'));
end rotary_switch_driver;

architecture structural of rotary_switch_driver is

    -- Signals must be stable for at least 10ms to be recognised as valid
    constant max_countdown  : Natural := Natural (clock_frequency / 100.0);
    subtype t_countdown is Natural range 0 to max_countdown;
    subtype t_rotary is std_logic_vector (2 downto 0);
    subtype t_button is std_logic_vector (1 downto 0);
    constant min_value      : t_rotary := "000";
    constant max_value      : t_rotary := "101";

    -- Registers
    signal countdown        : t_countdown := max_countdown;
    signal code             : std_logic_vector (2 downto 0) := (others => '0');
    signal updated_buttons  : std_logic := '0';
    signal updated_rotary   : std_logic := '0';
    signal new_button_value : t_button := "00";
    signal new_rotary_value : t_rotary := min_value;
    signal old_button_value : t_button := "00";
    signal old_rotary_value : t_rotary := min_value;
    signal output_value     : t_rotary := min_value;

    -- Signals

begin
    register_inputs : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            code (0) <= rotary_024;
            code (1) <= rotary_01;
            code (2) <= rotary_23;
            new_button_value (1) <= not left_button;   -- buttons are active low
            new_button_value (0) <= not right_button;
        end if;
    end process register_inputs;

    decode_inputs : process (code)
    begin
        if clock_in'event and clock_in = '1' then
            case code is
                when "100" =>  new_rotary_value <= "000"; -- rotary_01 low: rotary_value is 0
                when "101" =>  new_rotary_value <= "001"; --                rotary_value is 1
                when "010" =>  new_rotary_value <= "010"; -- rotary_23 low: rotary_value is 2
                when "011" =>  new_rotary_value <= "011"; --                rotary_value is 3
                when "110" =>  new_rotary_value <= "100"; -- 01 / 23 high:  rotary_value is 4
                when "111" =>  new_rotary_value <= "101"; --                rotary_value is 5
                when others => new_rotary_value <= max_value; -- invalid (both 01 and 23 are low)
            end case;
        end if;
    end process decode_inputs;

    await_stability : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            strobe_out <= '0';
            if new_button_value /= old_button_value then
                countdown <= max_countdown;
                updated_buttons <= '1';
                old_button_value <= new_button_value;

            elsif new_rotary_value /= old_rotary_value then
                countdown <= max_countdown;
                updated_rotary <= '1';
                old_rotary_value <= new_rotary_value;

            elsif countdown /= 0 then
                countdown <= countdown - 1;

            else
                if updated_buttons = '1' then
                    if new_button_value (1) = '1' then
                        -- left button: decrement
                        strobe_out <= '1';
                        if output_value = min_value then
                            output_value <= max_value;
                        else
                            output_value <= std_logic_vector (unsigned (output_value) - 1);
                        end if;
                    elsif new_button_value (0) = '1' then
                        -- right button: increment
                        strobe_out <= '1';
                        if output_value = max_value then
                            output_value <= min_value;
                        else
                            output_value <= std_logic_vector (unsigned (output_value) + 1);
                        end if;
                    end if;
                    updated_buttons <= '0';
                elsif updated_rotary = '1' then
                    -- go direct to new setting
                    strobe_out <= '1';
                    output_value <= new_rotary_value;
                    updated_rotary <= '0';
                end if;
            end if;
        end if;
    end process await_stability;

    value_out <= output_value;

end architecture structural;
