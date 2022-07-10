-- Convert sign-magnitude numbers to two's-complement


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity convert_from_sign_magnitude is
    generic (value_width    : Natural);
    port (
        value_in            : in std_logic_vector (value_width - 2 downto 0);
        value_negative_in   : in std_logic;
        value_out           : out std_logic_vector (value_width - 1 downto 0) := (others => '0')
    );
end convert_from_sign_magnitude;

architecture structural of convert_from_sign_magnitude is
begin
    process (value_in, value_negative_in)
        variable tmp : std_logic_vector (value_width - 1 downto 0) := (others => '0');
    begin
        -- two's complement representation assuming the value is positive:
        tmp (value_width - 2 downto 0) := value_in;
        tmp (value_width - 1) := '0';

        if value_negative_in = '1' then
            -- convert for negative input
            value_out <= std_logic_vector (0 - signed (tmp));
        else
            -- positive input
            value_out <= tmp;
        end if;
    end process;

end structural;
