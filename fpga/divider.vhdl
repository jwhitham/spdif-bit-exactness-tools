-- Signed / unsigned divider with configurable width:
--
--   result = top / bottom
--
-- The divider does not report an error in these conditions:
-- (a) If bottom = 0 the result is undefined.
-- (b) If top / bottom does not fit within top_width bits, the result is undefined.
--
-- (b) happens with signed division, when top = minimum and bottom = -1,
-- because the result is -minimum which can't be encoded.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity divider is
    generic (
        top_width    : Natural;
        bottom_width : Natural;
        is_unsigned  : Boolean);
    port (
        top_value_in    : in std_logic_vector (top_width - 1 downto 0);
        bottom_value_in : in std_logic_vector (bottom_width - 1 downto 0);
        start_in        : in std_logic;
        finish_out      : out std_logic := '0';
        result_out      : out std_logic_vector (top_width - 1 downto 0);
        clock_in        : in std_logic
    );
end divider;

architecture structural of divider is

    subtype t_wide is unsigned (top_width + bottom_width - 1 downto 0);
    subtype t_state is Natural range 0 to top_width + 1; 

    constant FINISHED   : t_state := top_width;
    constant IDLE       : t_state := top_width + 1;

    signal top          : t_wide := (others => '0');
    signal bottom       : t_wide := (others => '0');
    signal subtracted   : t_wide := (others => '0');
    signal result       : std_logic_vector (top_width - 1 downto 0) := (others => '0');
    signal state        : t_state := IDLE;
    signal invert       : std_logic := '0';

begin
    subtracted <= top - bottom;
    top (top'Left downto top_width) <= (others => '0');
    bottom (bottom'Left) <= '0';
    result_out <= result;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            finish_out <= '0';

            if start_in = '1' then
                if is_unsigned or top_value_in (top_width - 1) = '0' then
                    -- positive or unsigned
                    top (top_width - 1 downto 0) <= unsigned (top_value_in);
                else
                    -- negative
                    top (top_width - 1 downto 0) <= unsigned (0 - signed (top_value_in));
                end if;

                bottom (top_width - 2 downto 0) <= (others => '0');
                if is_unsigned or bottom_value_in (bottom_width - 1) = '0' then
                    -- positive or unsigned
                    bottom (bottom'Left - 1 downto top_width - 1) <= unsigned (bottom_value_in);
                else
                    -- negative
                    bottom (bottom'Left - 1 downto top_width - 1) <= unsigned (0 - signed (bottom_value_in));
                end if;

                invert <= '0';
                if (not is_unsigned) and
                        (top_value_in (top_width - 1) /= bottom_value_in (bottom_width - 1)) then
                    invert <= '1';
                end if;
                state <= 0;

            elsif state /= IDLE then
                state <= state + 1;
                if state = FINISHED then
                    -- when finished
                    if invert = '1' then
                        result <= std_logic_vector (unsigned (result) + 1);
                    end if;
                    finish_out <= '1';
                else
                    -- when dividing
                    result (result'Left downto 1) <= result (result'Left - 1 downto 0);
                    bottom (bottom'Left - 1 downto 0) <= bottom (bottom'Left downto 1);

                    if subtracted (subtracted'Left) = '0' then
                        -- subtraction did not result in overflow
                        top (top_width - 1 downto 0) <= subtracted (top_width - 1 downto 0);
                        result (0) <= '1' xor invert;
                    else
                        -- subtraction resulted in overflow
                        result (0) <= '0' xor invert;
                    end if;
                end if;
            end if;
        end if;
    end process;

end structural;
