-- Multiplier with configurable width:
--
--   result = a * b
--
-- If the numbers are different sizes, using a smaller size for a_width will
-- reduce the total register size, but increase the total number of clock
-- cycles required for the multiplication (which is always the same regardless
-- of the values).
--

library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

entity multiplier is
    generic (
        a_width             : Natural;
        b_width             : Natural;
        adder_slice_width   : Natural := 8);
    port (
        a_value_in          : in std_logic_vector (a_width - 1 downto 0);
        b_value_in          : in std_logic_vector (b_width - 1 downto 0);
        start_in            : in std_logic;
        reset_in            : in std_logic;
        finish_out          : out std_logic := '0';
        ready_out           : out std_logic := '0';
        result_out          : out std_logic_vector (a_width + b_width - 1 downto 0) := (others => '0');
        clock_in            : in std_logic
    );
end multiplier;

architecture structural of multiplier is

    constant r_width    : Natural := a_width + b_width;
    subtype t_result is std_logic_vector (r_width - 1 downto 0);
    subtype t_b is std_logic_vector (b_width - 1 downto 0);
    subtype t_steps_to_do is Natural range 0 to b_width - 1; 
    type t_state is (IDLE, START_ADD, AWAIT_RESULT);

    -- Registers
    signal a_reg        : t_result := (others => '0');
    signal b_reg        : t_b := (others => '0');
    signal mul_result   : t_result := (others => '0');
    signal state        : t_state := IDLE;
    signal steps_to_do  : t_steps_to_do := b_width - 1;

    -- Signals
    signal add_result   : t_result := (others => '0');
    signal add_start    : std_logic := '0';
    signal add_finish   : std_logic := '0';
    signal add_overflow : std_logic := '0';

begin
    result_out <= mul_result;
    add_start <= '1' when state = START_ADD else '0';
    ready_out <= '1' when state = IDLE else '0';

    add : entity subtractor
        generic map (value_width => r_width,
                     do_addition => true,
                     slice_width => adder_slice_width)
        port map (
            top_value_in => mul_result,
            bottom_value_in => a_reg,
            start_in => add_start,
            reset_in => reset_in,
            finish_out => add_finish,
            result_out => add_result,
            overflow_out => add_overflow,
            clock_in => clock_in);

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            finish_out <= '0';

            case state is
                when IDLE =>
                    -- Load new inputs
                    a_reg (r_width - 1 downto a_width) <= (others => '0');
                    a_reg (a_width - 1 downto 0) <= a_value_in;
                    b_reg <= b_value_in;

                    steps_to_do <= b_width - 1;

                    if start_in = '1' then
                        state <= START_ADD;
                        mul_result <= (others => '0');
                    end if;

                when START_ADD =>
                    -- Begin add
                    state <= AWAIT_RESULT;

                when AWAIT_RESULT =>
                    -- Multiplication
                    if add_finish = '1' then
                        if b_reg (0) = '1' then
                            -- Result of add is incorporated into the result
                            mul_result <= add_result;
                        end if;
                        -- b_reg shifts right (so that a more significant bit will be multiplied next time)
                        b_reg (b_width - 2 downto 0) <= b_reg (b_width - 1 downto 1);
                        b_reg (b_width - 1) <= '0';
                        -- a_reg shifts left (as the next bit is twice as significant)
                        a_reg (r_width - 1 downto 1) <= a_reg (r_width - 2 downto 0);
                        a_reg (0) <= '0';
                        -- Overflow never expected
                        assert add_overflow = '0';

                        if steps_to_do = 0 then
                            -- Finished?
                            finish_out <= '1';
                            state <= IDLE;
                        else
                            -- The next add might be redundant (e.g. b_reg (0) = '0') but
                            -- we do it anyway so that addition always takes the same length of time
                            -- for any particular parameters. Not so efficient, but much easier to check
                            -- that the deadline will always be met.
                            steps_to_do <= steps_to_do - 1;
                            state <= START_ADD;
                        end if;
                    end if;

            end case;

            if reset_in = '1' then
                state <= IDLE;
            end if;
        end if;
    end process;

end structural;
