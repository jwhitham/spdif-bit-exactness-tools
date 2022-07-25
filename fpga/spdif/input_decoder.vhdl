
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity input_decoder is
    generic (
        max_transition_time    : Natural := 255;
        enough_transitions     : Natural := 31;
        debug                  : Boolean := false);
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

    -- Outputs
    constant ZERO   : std_logic_vector (1 downto 0) := "00";
    constant ONE    : std_logic_vector (1 downto 0) := "01";
    constant TWO    : std_logic_vector (1 downto 0) := "10";
    constant THREE  : std_logic_vector (1 downto 0) := "11";

    -- Need to hold the transition time for at least this number of clock
    -- cycles in order to reach the end of the pipeline.
    constant min_transition_time    : Natural := 4;

    -- Measuring the transition time (stage 1)
    subtype t_transition_time is Natural range 0 to max_transition_time;
    signal transition_time          : t_transition_time := 0;
    signal timer                    : t_transition_time := 0;
    signal transition_time_strobe   : std_logic := '0';
    signal delay0, delay1           : std_logic := '0';

    -- Determining the maximum and minimum; stability counter (stage 2)
    signal min_measured_time        : t_transition_time := max_transition_time;
    signal max_measured_time        : t_transition_time := min_transition_time;
    signal min_max_strobe           : std_logic := '0';
    signal min_max_is_valid         : std_logic := '0';
    subtype t_transition_counter is Natural range 0 to enough_transitions;
    signal valid_transitions        : t_transition_counter := 0;

    -- Thresholds for distinguishing pulse length (stage 3)
    signal threshold_1_5            : t_transition_time := 0;
    signal threshold_2_5            : t_transition_time := 0;
    signal threshold_strobe         : std_logic := '0';

    -- Pulse length is determined by comparing to thresholds (stage 4)
    signal pulse_length             : std_logic_vector (1 downto 0) := ZERO;

    -- We can detect incorrect timings by looking at the number of
    -- sequential THREE pulses (stage 5)
    constant too_many_threes        : Natural := 3;
    subtype t_three_counter is Natural range 0 to too_many_threes;
    signal three_counter            : t_three_counter := 0;

begin

    measure_transition_time : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            delay0 <= data_in;
            delay1 <= delay0;

            transition_time_strobe <= '0';
            if sync_in = '0' then
                timer <= 0;
                transition_time <= 0;

            elsif delay0 = delay1 then
                -- No transition - measure time
                if timer /= max_transition_time then
                    timer <= timer + 1;
                end if;

            else
                -- New transition - report time
                transition_time <= timer;
                transition_time_strobe <= '1';
                timer <= 1;
            end if;
        end if;
    end process measure_transition_time;

    min_max_is_valid <= '1' when valid_transitions = enough_transitions else '0';

    -- Determine the maximum and minimum transition time, by measurement
    min_max_transition_time : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            min_max_strobe <= '0';

            if sync_in = '0' then
                -- Reset
                min_measured_time <= max_transition_time;
                max_measured_time <= min_transition_time;
                valid_transitions <= 0;

            elsif transition_time_strobe = '1' then
                -- New transition
                if debug then
                    write (l, String'("AA measured "));
                    write (l, transition_time);
                    writeline (output, l);
                end if;

                if min_max_is_valid = '0' then
                    -- Transition sequence appears valid, increase stability
                    valid_transitions <= valid_transitions + 1;
                    if debug then
                        write (l, String'("AA increase validity"));
                        writeline (output, l);
                    end if;
                end if;

                if three_counter = too_many_threes
                        or transition_time = max_transition_time 
                        or transition_time < min_transition_time then
                    -- Too many transitions of length THREE have been measured;
                    -- this shows that the measurements are wrong.
                    -- OR. The pulse time is too long or too short
                    -- -> reset everything
                    min_measured_time <= max_transition_time;
                    max_measured_time <= min_transition_time;
                    valid_transitions <= 0;
                    if debug then
                        write (l, String'("AA reset due to three_counter="));
                        write (l, three_counter);
                        write (l, String'(" transition_time="));
                        write (l, transition_time);
                        writeline (output, l);
                    end if;
                else
                    -- capture minimum and maximum
                    if max_measured_time < transition_time then
                        -- new maximum does not reset measurements
                        max_measured_time <= transition_time;
                        if debug then
                            write (l, String'("AA new max_measured_time="));
                            write (l, transition_time);
                            writeline (output, l);
                        end if;
                    end if;
                    if min_measured_time > transition_time then
                        -- new minimum resets measurements
                        min_measured_time <= transition_time;
                        valid_transitions <= 0;
                        if debug then
                            write (l, String'("AA new min_measured_time="));
                            write (l, transition_time);
                            writeline (output, l);
                        end if;
                    end if;
                end if;

                -- signal readiness to the next stage
                min_max_strobe <= '1';
            end if;
        end if;
    end process min_max_transition_time;

    threshold_calc : process (clock_in)
        constant peak : Natural := max_transition_time * 2 * 5;
        subtype t_bigger is Natural range 0 to peak;
        variable x4_0 : t_bigger := 0;
    begin
        if clock_in'event and clock_in = '1' then
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
            threshold_1_5 <= t_transition_time ((x4_0 * 3) / 8);
            threshold_2_5 <= t_transition_time ((x4_0 * 5) / 8);
            single_time_out <= std_logic_vector (to_unsigned (63, 8));

            if min_max_is_valid = '1' then
                single_time_out <= std_logic_vector (to_unsigned ((x4_0 / 4) mod 256, 8));
            end if;

            -- signal readiness to the next stage
            threshold_strobe <= min_max_strobe;
        end if;
    end process threshold_calc;

    debug_thresholds : process (threshold_1_5, threshold_2_5, min_measured_time, max_measured_time)
        variable l : line;
    begin
        if debug then
            write (l, String'("AA threshold_calc min_measured_time="));
            write (l, min_measured_time);
            write (l, String'(" max_measured_time="));
            write (l, max_measured_time);
            write (l, String'(" threshold_1_5="));
            write (l, threshold_1_5);
            write (l, String'(" threshold_2_5="));
            write (l, threshold_2_5);
            writeline (output, l);
        end if;
    end process debug_thresholds;

    pulse_transition_time : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            pulse_length <= ZERO;
            if threshold_strobe = '1' then
                if threshold_1_5 >= transition_time then
                    pulse_length <= ONE;
                elsif threshold_2_5 >= transition_time then
                    pulse_length <= TWO;
                else
                    pulse_length <= THREE;
                end if;
            end if;
        end if;
    end process pulse_transition_time;

    pulse_length_out <= pulse_length when min_max_is_valid = '1' else ZERO;
    sync_out <= min_max_is_valid;

    check_threes : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            case pulse_length is
                when ONE =>
                    three_counter <= 0;
                when THREE =>
                    -- There must be at least one ONE in any sequence containing three THREEs
                    if three_counter /= too_many_threes then
                        three_counter <= three_counter + 1;
                    end if;
                when others =>
                    if sync_in = '0' then
                        three_counter <= 0;
                    end if;
            end case;
        end if;
    end process check_threes;

end structural;
