
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_decoder is
    port (
        data_in          : in std_logic;
        pulse_length_out : out std_logic_vector (1 downto 0) := "00";
        single_time_out  : out std_logic_vector (7 downto 0) := (others => '0');
        sync_out         : out std_logic := '0';
        clock            : in std_logic
    );
end input_decoder;

architecture structural of input_decoder is

    subtype t_sync_counter is unsigned (0 to 2);
    subtype t_transition_time is unsigned (0 to 7);

    constant zero_transition_time   : t_transition_time := (others => '0');
    constant max_transition_time    : t_transition_time := (others => '1');
    constant max_single_time        : t_transition_time := max_transition_time srl 2;
    constant zero_sync_counter      : t_sync_counter := (others => '0');
    constant max_sync_counter       : t_sync_counter := (others => '1');

    type t_transition_class is (NONE, SHORT, ONE, TWO, THREE, LONG);

    signal delay0, delay1       : std_logic := '0';
    signal sync_counter         : t_sync_counter := zero_sync_counter;
    signal next_sync_counter    : t_sync_counter := zero_sync_counter;
    signal transition_time      : t_transition_time := zero_transition_time;
    signal transition_class     : t_transition_class := NONE;
    signal timer                : t_transition_time := zero_transition_time + 1;
    signal next_timer           : t_transition_time := zero_transition_time + 2;
    signal threshold            : t_transition_class := NONE;
    signal single_time          : t_transition_time := max_single_time;
    signal double_time          : t_transition_time := max_transition_time;
    signal triple_time          : t_transition_time := max_transition_time;
    signal quad_time            : t_transition_time := max_transition_time;
begin

    -- detect transitions
    process (clock)
    begin
        if clock'event and clock = '1' then
            delay0 <= data_in;
            delay1 <= delay0;
            transition_time <= zero_transition_time;
            transition_class <= NONE;

            if delay0 = delay1 then
                if timer = max_transition_time then
                    threshold <= LONG;
                else
                    timer <= next_timer;
                    if next_timer = single_time then
                        threshold <= ONE;
                    elsif next_timer = double_time then
                        threshold <= TWO;
                    elsif next_timer = triple_time then
                        threshold <= THREE;
                    elsif next_timer = quad_time then
                        threshold <= LONG;
                    end if;
                end if;
            else
                timer <= zero_transition_time + 1;
                threshold <= SHORT;
                transition_class <= threshold;
                transition_time <= timer;
            end if;
        end if;
    end process;

    next_timer <= timer + 1;
    next_sync_counter <= sync_counter + 1;
    single_time_out <= std_logic_vector (single_time);
    sync_out <= '1' when sync_counter = max_sync_counter else '0';

    -- Determine the time for a single transition ("synchronise").
    -- Once synchronised, classify transitions as single, double or triple.
    process (clock)
    begin
        if clock'event and clock = '1' then
            pulse_length_out <= "00";

            double_time <= (single_time sll 1) - (single_time srl 2);  -- multiply by 1.75
            triple_time <= (single_time sll 1) + single_time
                                                - (single_time srl 2); -- multiply by 2.75
            quad_time <= (single_time sll 2) + single_time;            -- multiply by 5

            case transition_class is
                when NONE =>
                    -- No transition, do nothing
                    null;
                when LONG =>
                    -- Invalid transition - start syncing again
                    sync_counter <= zero_sync_counter;
                    single_time <= max_single_time;
                when SHORT =>
                    -- Shorter pulse seen - adjust single_time
                    single_time <= transition_time;
                    if sync_counter = max_sync_counter then
                        pulse_length_out <= "01";
                    end if;
                when ONE =>
                    if sync_counter = max_sync_counter then
                        pulse_length_out <= "01";
                    else
                        sync_counter <= next_sync_counter;
                    end if;
                when TWO =>
                    if sync_counter = max_sync_counter then
                        pulse_length_out <= "10";
                    else
                        sync_counter <= next_sync_counter;
                    end if;
                when THREE =>
                    if sync_counter = max_sync_counter then
                        pulse_length_out <= "11";
                    else
                        sync_counter <= next_sync_counter;
                    end if;
            end case;
        end if;
    end process;

end structural;
