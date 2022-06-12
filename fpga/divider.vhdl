
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity divider is
    generic (
        top_width : Natural := 16;
        bottom_width : Natural := 16);
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

    subtype t_wide is unsigned (top_width + bottom_width - 2 downto 0);
    subtype t_state is Natural range 0 to top_width + 1; 

    constant FINISHED   : t_state := top_width;
    constant IDLE       : t_state := top_width + 1;

    signal top          : t_wide := (others => '0');
    signal bottom       : t_wide := (others => '0');
    signal subtracted   : t_wide := (others => '0');
    signal result       : std_logic_vector (top_width - 1 downto 0) := (others => '0');
    signal state        : t_state := IDLE;

begin
    subtracted <= top - bottom;
    top (top'Left downto top_width) <= (others => '0');
    result_out <= result;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            finish_out <= '0';

            if start_in = '1' then
                top (top_width - 1 downto 0) <= unsigned (top_value_in);
                bottom <= (others => '0');
                bottom (t_wide'Left downto top_width - 1) <= unsigned (bottom_value_in);
                state <= 0;

            elsif state /= IDLE then
                state <= state + 1;
                if state = FINISHED then
                    -- when finished
                    finish_out <= '1';
                else
                    -- when dividing
                    result (result'Left downto 1) <= result (result'Left - 1 downto 0);
                    bottom (t_wide'Left - 1 downto 0) <= bottom (t_wide'Left downto 1);
                    bottom (t_wide'Left) <= '0';

                    if subtracted (subtracted'Left) = '0' then
                        -- subtraction did not result in overflow
                        top (top_width - 1 downto 0) <= subtracted (top_width - 1 downto 0);
                        result (0) <= '1';
                    else
                        -- subtraction resulted in overflow
                        result (0) <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

end structural;
