
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity input_decoder is
    generic (debug : Boolean := false);
    port (
        data_in          : in std_logic;
        pulse_length_out : out std_logic_vector (1 downto 0) := "00";
        single_time_out  : out std_logic_vector (7 downto 0) := (others => '0');
        sync_out         : out std_logic := '0';
        sync_in          : in std_logic := '0';
        clock_in         : in std_logic
    );
end input_decoder;

architecture structural of input_decoder is

    constant ZERO   : std_logic_vector (1 downto 0) := "00";
    constant ONE    : std_logic_vector (1 downto 0) := "01";
    constant TWO    : std_logic_vector (1 downto 0) := "10";
    constant THREE  : std_logic_vector (1 downto 0) := "11";

    -- Detecting transitions
    signal delay0, delay1           : std_logic := '0';

    -- Recording the maximum and minimum transition time
    constant max_transition_time    : Natural := 254;
    subtype t_transition_time is Natural range 0 to max_transition_time + 1;
    subtype t_bigger is Natural range 0 to (((max_transition_time + 2) * 4) - 1);

    signal max_measured_time        : t_transition_time := max_transition_time;
    signal min_measured_time        : t_transition_time := 0;
    signal no_new_minimum           : std_logic := '1';
    signal time_since_transition    : t_transition_time := 0;

    -- Thresholds
    signal threshold_1_5            : t_transition_time := 0;
    signal threshold_2_5            : t_transition_time := 0;
    signal thresholds_calculated    : std_logic := '0';
    signal new_pulse_length         : std_logic_vector (1 downto 0) := ZERO;

    -- Stability counter
    constant enough_transitions     : Natural := 127;
    subtype t_transition_counter is Natural range 0 to enough_transitions;
    signal transitions_since_last_update : t_transition_counter := 0;

    -- Signals
    signal next_time                : t_transition_time := 0;
begin

    next_time <= time_since_transition + 1;

    process (clock_in)
        variable l : line;
        variable x4_0, x2_0, x1_0, x0_5 : t_bigger := 0;
    begin
        if clock_in'event and clock_in = '1' then
            delay0 <= data_in;
            delay1 <= delay0;
            pulse_length_out <= ZERO;

            if sync_in = '0' or (delay0 = delay1 and time_since_transition = max_transition_time) then
                -- Reset: wait for the next transition, start counting again
                min_measured_time <= max_transition_time;
                max_measured_time <= 0;
                transitions_since_last_update <= 0;
                thresholds_calculated <= '0';

            elsif delay0 = delay1 then
                -- No transition
                time_since_transition <= next_time;
                if min_measured_time = time_since_transition then
                    -- Larger minimum value is NOT obtained
                    no_new_minimum <= '1';
                end if;

                if max_measured_time = time_since_transition then
                    -- Larger maximum value obtained, start counting again
                    max_measured_time <= next_time;
                    no_new_minimum <= '1';
                    min_measured_time <= max_transition_time;
                    transitions_since_last_update <= 0;

                    if debug then
                        write (l, String'("AA longer max measured time: "));
                        write (l, next_time);
                        writeline (output, l);
                    end if;

                elsif thresholds_calculated = '1' then
                    -- When we have a stable minimum and maximum, determine the pulse length
                    if time_since_transition = threshold_1_5 then
                        new_pulse_length <= TWO;
                    elsif time_since_transition = threshold_2_5 then
                        new_pulse_length <= THREE;
                    end if;
                end if;
            else
                -- New transition, start timing
                time_since_transition <= 0;
                new_pulse_length <= ONE;
                no_new_minimum <= '0';

                if no_new_minimum = '0' then
                    -- The measured time is a new minimum, start counting again
                    min_measured_time <= time_since_transition;
                    transitions_since_last_update <= 0;
                    if debug then
                        write (l, String'("AA shorter min measured time: "));
                        write (l, time_since_transition);
                        writeline (output, l);
                    end if;

                elsif transitions_since_last_update = enough_transitions then
                    if thresholds_calculated = '1' then
                        -- Valid calculated thresholds give us the pulse length
                        pulse_length_out <= new_pulse_length;
                    else
                        -- We just became stable! Calculate thresholds
                        -- 
                        -- Hypothesis - there is a single pulse time, X clock cycles,
                        -- and a double pulse time 2X and a triple pulse time 3X. These are the
                        -- pulse times that the transmitter intends to generate. X is not an integer,
                        -- as the transmitter's clock frequency is not our clock frequency.
                        --
                        -- There is an error time, E clock cycles, which causes all actual measurements to vary by +/- E.
                        -- This is also not an integer.
                        --
                        -- We can use our measured times to obtain X like this:
                        --            min_measured_time ~ X - E
                        --        and max_measured_time ~ 3X + E
                        --  so 4X ~ min_measured_time + max_measured_time
                        --
                        -- Threshold 1.5X can be used to distinguish between X and 2X pulses.
                        -- Threshold 2.5X can be used to distinguish between 2X and 3X pulses.
                        x4_0 := t_bigger (min_measured_time) + t_bigger (max_measured_time);
                        x2_0 := x4_0 / 2;
                        x1_0 := x2_0 / 2;
                        x0_5 := x1_0 / 2;
                        threshold_1_5 <= t_transition_time (x1_0 + x0_5);
                        threshold_2_5 <= t_transition_time (x2_0 + x0_5);
                        single_time_out <= std_logic_vector (to_unsigned (x1_0, 8));
                        thresholds_calculated <= '1';
                        if debug then
                            write (l, String'("AA thresholds calculated with 4X = "));
                            write (l, x4_0);
                            writeline (output, l);
                        end if;
                    end if;

                else
                    -- We might have a valid max_measured_time, if it is stable
                    transitions_since_last_update <= transitions_since_last_update + 1;
                    thresholds_calculated <= '0';
                    if debug then
                        write (l, String'("AA transitions "));
                        write (l, transitions_since_last_update);
                        write (l, String'(" measured "));
                        write (l, time_since_transition);
                        writeline (output, l);
                    end if;
                end if;
            end if;
        end if;
    end process;

    sync_out <= thresholds_calculated;

end structural;
