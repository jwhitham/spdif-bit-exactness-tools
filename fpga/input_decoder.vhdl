
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_decoder is
    port (
        data_in         : in std_logic;
        single_pulse    : out std_logic;
        double_pulse    : out std_logic;
        triple_pulse    : out std_logic;
        clock           : in std_logic
    );
end input_decoder;

architecture structural of input_decoder is

    subtype t_sync_counter is unsigned (0 to 2);
    subtype t_data_counter is unsigned (0 to 3);

    constant zero_data_counter  : t_data_counter := (others => '0');
    constant zero_sync_counter  : t_sync_counter := (others => '0');
    constant max_sync_counter   : t_sync_counter := (others => '1');

    constant max_pulse_length : t_data_counter := (others => '1');
    constant min_pulse_length : t_data_counter := to_unsigned (3, t_data_counter'Length);

    type t_pulse_length is (SHORT_INVALID, ZERO, ONE, TWO, THREE, LONG_INVALID);

    signal delay0, delay1       : std_logic := '0';
    signal skip                 : std_logic := '0';
    signal sync_counter         : t_sync_counter := zero_sync_counter;
    signal data_counter         : t_data_counter := zero_data_counter;
    signal next_data_counter    : t_data_counter := zero_data_counter;
    signal single_pulse_length  : t_data_counter := max_pulse_length;
    signal pulse_length         : t_pulse_length := SHORT_INVALID;
begin

    next_data_counter <= data_counter + 1;

    process (clock)
    begin
        if clock'event and clock = '1' then
            single_pulse <= '0';
            double_pulse <= '0';
            triple_pulse <= '0';

            delay0 <= data_in;
            delay1 <= delay0;

            if delay0 = delay1 then
                -- Stable input. Increment the data counter.
                data_counter <= next_data_counter;

                if next_data_counter = max_pulse_length then
                    -- If a pulse is too long, we must resynchronise
                    pulse_length <= LONG_INVALID;
                    data_counter <= zero_data_counter;

                elsif next_data_counter = single_pulse_length then
                    -- reached the measured length of a pulse
                    case pulse_length is
                        when ZERO | SHORT_INVALID =>
                            pulse_length <= ONE;
                        when ONE =>
                            pulse_length <= TWO;
                        when TWO =>
                            pulse_length <= THREE;
                        when THREE | LONG_INVALID =>
                            pulse_length <= LONG_INVALID;
                    end case;
                    data_counter <= zero_data_counter;

                elsif next_data_counter = min_pulse_length then
                    -- reached the minimum length of a pulse
                    case pulse_length is
                        when SHORT_INVALID =>
                            pulse_length <= ZERO;
                        when ZERO | ONE | TWO | THREE | LONG_INVALID =>
                            null;
                    end case;
                end if;
            elsif sync_counter = max_sync_counter then
                -- Transition input when synchronised
                pulse_length <= SHORT_INVALID;
                data_counter <= zero_data_counter;

                case pulse_length is
                    when SHORT_INVALID | LONG_INVALID =>
                        -- Pulse is too short or too long: resynchronise
                        sync_counter <= zero_sync_counter;
                        single_pulse_length <= max_pulse_length;
                    when ZERO =>
                        -- This pulse may be shorter than the shortest one we saw so far
                        single_pulse_length <= next_data_counter;
                        single_pulse <= '1';
                    when ONE =>
                        single_pulse <= '1';
                    when TWO =>
                        double_pulse <= '1';
                    when THREE =>
                        triple_pulse <= '1';
                end case;
            else
                -- Transition input when not synchronised
                pulse_length <= SHORT_INVALID;
                sync_counter <= sync_counter + 1;
                data_counter <= zero_data_counter;

                case pulse_length is
                    when SHORT_INVALID | LONG_INVALID =>
                        -- Pulse is too short or too long to be usable: resynchronise
                        sync_counter <= zero_sync_counter;
                        single_pulse_length <= max_pulse_length;
                    when ZERO =>
                        -- This pulse may be shorter than the shortest one we saw so far
                        single_pulse_length <= next_data_counter;
                    when ONE | TWO | THREE =>
                        -- This is a stable measurement
                        null;
                end case;
            end if;
        end if;
    end process;

end structural;
