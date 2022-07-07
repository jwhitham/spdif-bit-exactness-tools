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
        reset_in        : in std_logic;
        finish_out      : out std_logic := '0';
        result_out      : out std_logic_vector (top_width - 1 downto 0);
        clock_in        : in std_logic
    );
end divider;

architecture structural of divider is

    subtype t_wide is unsigned (top_width + bottom_width - 1 downto 0);
    subtype t_steps_to_do is Natural range 0 to top_width - 1; 
    type t_state is (IDLE, INVERT_INPUTS, SHIFT, FINISH_NEGATIVE, FINISH_POSITIVE);

    signal top          : t_wide := (others => '0');
    signal bottom       : t_wide := (others => '0');
    signal subtracted   : t_wide := (others => '0');
    signal result       : std_logic_vector (top_width - 1 downto 0) := (others => '0');
    signal state        : t_state := IDLE;
    signal invert       : std_logic := '0';
    signal steps_to_do  : t_steps_to_do := top_width - 1;

begin
    subtracted <= top - bottom;
    top (top'Left downto top_width) <= (others => '0');
    bottom (bottom'Left) <= '0';
    result_out <= result;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            finish_out <= '0';

            case state is
                when IDLE =>
                    -- Load new inputs
                    top (top_width - 1 downto 0) <= unsigned (top_value_in);
                    bottom (bottom'Left - 1 downto top_width - 1) <= unsigned (bottom_value_in);

                    if is_unsigned then
                        invert <= '0';
                    else
                        invert <= (top_value_in (top_width - 1) xor
                                    bottom_value_in (bottom_width - 1));
                    end if;
                    steps_to_do <= top_width - 1;

                    if start_in = '1' then
                        if is_unsigned then
                            -- input values are always positive
                            state <= SHIFT;
                        else
                            -- input values might not be positive
                            state <= INVERT_INPUTS;
                        end if;
                    end if;
                when INVERT_INPUTS =>
                    -- Get positive values for inputs
                    assert not is_unsigned;
                    if top (top_width - 1) = '1' then
                        top (top_width - 1 downto 0) <=
                            unsigned (0 - signed (top (top_width - 1 downto 0)));
                    end if;
                    if bottom (bottom'Left - 1) = '1' then
                        bottom (bottom'Left - 1 downto top_width - 1) <=
                            unsigned (0 - signed (bottom (bottom'Left - 1 downto top_width - 1)));
                    end if;
                    state <= SHIFT;
                when SHIFT =>
                    -- Perform unsigned division
                    result (result'Left downto 1) <= result (result'Left - 1 downto 0);
                    bottom (bottom'Left - 1 downto 0) <= bottom (bottom'Left downto 1);

                    if subtracted (subtracted'Left) = '0' then
                        -- subtraction did not result in overflow
                        top (top_width - 1 downto 0) <= subtracted (top_width - 1 downto 0);
                        result (0) <= '1';
                    else
                        -- subtraction resulted in overflow
                        result (0) <= '0';
                    end if;
                    if steps_to_do = 0 then
                        -- Finished?
                        if invert = '0' or is_unsigned then
                            state <= FINISH_POSITIVE;
                        else
                            state <= FINISH_NEGATIVE;
                        end if;
                    else
                        steps_to_do <= steps_to_do - 1;
                    end if;
                when FINISH_NEGATIVE =>
                    -- Invert result
                    assert not is_unsigned;
                    assert invert = '1';
                    result <= std_logic_vector (unsigned (0 - signed (result)));
                    finish_out <= '1';
                    state <= IDLE;
                when FINISH_POSITIVE =>
                    -- Result is already positive
                    assert invert = '0';
                    finish_out <= '1';
                    state <= IDLE;
            end case;

            if reset_in = '1' then
                state <= IDLE;
            end if;
        end if;
    end process;

end structural;
