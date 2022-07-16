-- subtractor with configurable width; the subtraction is carried out in
-- multiple steps (slice_width bits are subtracted in each clock cycle).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity subtractor is
    generic (value_width    : Natural;
             slice_width    : Natural := 8;
             do_addition    : Boolean := false);
    port (
        top_value_in        : in std_logic_vector (value_width - 1 downto 0);
        bottom_value_in     : in std_logic_vector (value_width - 1 downto 0);
        start_in            : in std_logic;
        reset_in            : in std_logic;
        finish_out          : out std_logic := '0';
        overflow_out        : out std_logic := '0';
        result_out          : out std_logic_vector (value_width - 1 downto 0) := (others => '0');
        clock_in            : in std_logic
    );
end subtractor;

architecture structural of subtractor is

    constant number_of_slices : Natural := (value_width + slice_width - 1) / slice_width;
    constant expanded_width   : Natural := slice_width * number_of_slices;
    constant unused_bits      : Natural := expanded_width - value_width;

    subtype t_expanded_value is unsigned (expanded_width - 1 downto 0);
    subtype t_slice is unsigned (slice_width + 1 downto 0);

    subtype t_steps_to_do is Natural range 0 to number_of_slices - 1; 
    type t_state is (IDLE, SUBTRACT);

    signal top          : t_expanded_value := (others => '0');
    signal bottom       : t_expanded_value := (others => '0');
    signal result       : t_expanded_value := (others => '0');
    signal top_slice    : t_slice := (others => '0');
    signal bottom_slice : t_slice := (others => '0');
    signal result_slice : t_slice := (others => '0');
    signal state        : t_state := IDLE;
    signal steps_to_do  : t_steps_to_do := number_of_slices - 1;
    signal borrow       : std_logic := '0';

begin
    assert expanded_width >= value_width;
    assert slice_width <= expanded_width;

    result_out <= std_logic_vector (result (value_width - 1 downto 0));
    overflow_out <= borrow;

    top_slice (slice_width + 1) <= '0';
    top_slice (slice_width downto 1) <= top (slice_width - 1 downto 0);
    top_slice (0) <= '1' when do_addition else '0';

    bottom_slice (slice_width + 1) <= '0';
    bottom_slice (slice_width downto 1) <= bottom (slice_width - 1 downto 0);
    bottom_slice (0) <= borrow;

    result_slice <= top_slice + bottom_slice when do_addition else top_slice - bottom_slice;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            finish_out <= '0';

            case state is
                when IDLE =>
                    -- Load new inputs
                    top <= (others => '0');
                    top (value_width - 1 downto 0) <= unsigned (top_value_in);
                    bottom <= (others => '0');
                    bottom (value_width - 1 downto 0) <= unsigned (bottom_value_in);

                    steps_to_do <= number_of_slices - 1;

                    if start_in = '1' then
                        state <= SUBTRACT;
                        borrow <= '0';
                    end if;
                when SUBTRACT =>
                    -- Shift inputs right
                    top (expanded_width - slice_width - 1 downto 0) <=
                            top (expanded_width - 1 downto slice_width);
                    bottom (expanded_width - slice_width - 1 downto 0) <=
                            bottom (expanded_width - 1 downto slice_width);

                    -- Shift output right
                    result (expanded_width - slice_width - 1 downto 0) <=
                            result (expanded_width - 1 downto slice_width);

                    -- Subtract one slice
                    result (expanded_width - 1 downto expanded_width - slice_width) <=
                            result_slice (slice_width downto 1);
                    borrow <= result_slice (slice_width + 1);

                    if steps_to_do = 0 then
                        -- Finished?
                        finish_out <= '1';
                        state <= IDLE;
                        if do_addition and unused_bits /= 0 then
                            -- Use correct bit for overflow output; we can't just use
                            -- slice_width + 1 as with subtraction, since addition overflow
                            -- only affects one bit.
                            borrow <= result_slice (slice_width + 1 - unused_bits);
                        end if;
                    else
                        steps_to_do <= steps_to_do - 1;
                        state <= SUBTRACT;
                    end if;
            end case;

            if reset_in = '1' then
                state <= IDLE;
            end if;
        end if;
    end process;

end structural;
