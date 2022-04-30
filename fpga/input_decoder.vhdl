
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

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

    subtype t_sync_counter is unsigned (0 to 1);
    subtype t_data_counter is unsigned (0 to 5);
    subtype t_pending is Natural range 0 to 3;

    constant zero_data_counter  : t_data_counter := (others => '0');
    constant zero_sync_counter  : t_sync_counter := (others => '0');
    constant max_sync_counter   : t_sync_counter := (others => '1');

    constant max_pulse_length : t_data_counter := (others => '1');
    constant min_pulse_length : t_data_counter := to_unsigned (2, t_data_counter'Length);

    type t_pulse_length is (SHORT_INVALID, ZERO, ONE, TWO, THREE, LONG_INVALID);

    signal delay0, delay1       : std_logic := '0';
    signal skip                 : std_logic := '0';
    signal sync_counter         : t_sync_counter := zero_sync_counter;
    signal data_counter         : t_data_counter := zero_data_counter;
    signal single_pulse_length  : t_data_counter := max_pulse_length;
    signal pulse_length         : t_pulse_length := SHORT_INVALID;
begin

    process (clock)
        variable l : line;
    begin
        if clock'event and clock = '1' then
            single_pulse <= '0';
            double_pulse <= '0';
            triple_pulse <= '0';
            write (l, String'("sync counter = "));
            write (l, to_integer(sync_counter));
            write (l, String'(" data_counter = "));
            write (l, to_integer(data_counter));
            write (l, String'(" pulse_length = "));
            write (l, t_pulse_length'Image(pulse_length));
            write (l, String'(" single_pulse_length = "));
            write (l, to_integer(single_pulse_length));
            writeline (output, l);

            delay0 <= data_in;
            delay1 <= delay0;

            if delay0 = delay1 then
                -- Stable input. Increment the data counter.
                data_counter <= data_counter + 1;

                if data_counter = max_pulse_length then
                    -- If a pulse is too long, we must resynchronise
                    write (l, String'("Stable input - max pulse length reached"));
                    writeline (output, l);
                    data_counter <= zero_data_counter;

                elsif data_counter = single_pulse_length then
                    -- reached the measured length of a pulse
                    write (l, String'("Stable input - measured pulse length reached"));
                    writeline (output, l);
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

                elsif data_counter = min_pulse_length then
                    -- reached the minimum length of a pulse
                    write (l, String'("Stable input - min pulse length reached"));
                    writeline (output, l);
                    pulse_length <= ZERO;

                end if;
            elsif sync_counter = max_sync_counter then
                -- Transition input when synchronised
                write (l, String'("Transition input when synchronised"));
                writeline (output, l);
                pulse_length <= SHORT_INVALID;
                data_counter <= zero_data_counter;

                case pulse_length is
                    when SHORT_INVALID | LONG_INVALID =>
                        -- Pulse is too short or too long: resynchronise
                        sync_counter <= zero_sync_counter;
                        single_pulse_length <= max_pulse_length;
                        write (l, String'("Pulse is bad when synchronised"));
                        writeline (output, l);
                    when ZERO | ONE =>
                        single_pulse <= '1';
                    when TWO =>
                        double_pulse <= '1';
                    when THREE =>
                        triple_pulse <= '1';
                end case;
            else
                -- Transition input when not synchronised
                write (l, String'("Transition input when not synchronised"));
                writeline (output, l);
                pulse_length <= SHORT_INVALID;
                sync_counter <= sync_counter + 1;
                data_counter <= zero_data_counter;

                case pulse_length is
                    when SHORT_INVALID | LONG_INVALID =>
                        -- Pulse is too short or too long to be usable: resynchronise
                        sync_counter <= zero_sync_counter;
                        single_pulse_length <= max_pulse_length;
                        write (l, String'("Pulse is bad when not synchronised"));
                        writeline (output, l);
                    when ZERO =>
                        -- This pulse is shorter than the shortest one we saw so far
                        single_pulse_length <= data_counter;
                        write (l, String'("Pulse is shorter than previous"));
                        writeline (output, l);
                    when ONE | TWO | THREE =>
                        -- This is a stable measurement
                        null;
                end case;
            end if;
        end if;
    end process;

end structural;
