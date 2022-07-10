-- Convert two's-complement numbers to sign-magnitude form
-- If the input number is the minimum value in two's-complement form,
-- e.g. -128 for an 8 bit value, then 1 is added during conversion
-- as the range of possible values is smaller by 1.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity convert_to_sign_magnitude is
    generic (value_width    : Natural);
    port (
        value_in            : in std_logic_vector (value_width - 1 downto 0);
        value_negative_out  : out std_logic := '0';
        value_out           : out std_logic_vector (value_width - 2 downto 0) := (others => '0')
    );
end convert_to_sign_magnitude;

architecture structural of convert_to_sign_magnitude is
begin
    process (value_in)
        variable tmp : std_logic_vector (value_width - 1 downto 0) := (others => '0');
        constant zero : std_logic_vector (value_width - 2 downto 0) := (others => '0');
    begin
        if value_in (value_width - 1) = '1' then
            -- negative input
            value_negative_out <= '1';
            if value_in (value_width - 2 downto 0) = zero then
                -- minimum two's-complement value would overflow the sign-magnitude
                -- representation, so add 1 to the value
                value_out <= (others => '1');
            else
                -- convert from negative input
                tmp := std_logic_vector (0 - signed (value_in));
                value_out <= tmp (value_width - 2 downto 0);
            end if;
        else
            -- positive input
            value_negative_out <= '0';
            value_out <= value_in (value_width - 2 downto 0);
        end if;
    end process;

end structural;
