
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity input_decoder is
    generic (
        debug            : Boolean := false);
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

    constant enable_packet_decoder  : std_logic := '1';

    -- Measuring the transition time
    constant max_transition_time    : Natural := 255;
    subtype t_transition_time is Natural range 0 to max_transition_time;
    signal transition_time          : t_transition_time := 0;
    signal timer                    : t_transition_time := 0;
    signal transition_time_strobe   : std_logic := '0';
    signal delay0, delay1           : std_logic := '0';

    -- Determining the maximum and minimum
    signal min_measured_time        : t_transition_time := max_transition_time;
    signal max_measured_time        : t_transition_time := 0;

    -- Stability counter
    constant enough_transitions     : Natural := 31;
    subtype t_transition_counter is Natural range 0 to enough_transitions;
    signal valid_transitions : t_transition_counter := 0;
    signal min_max_is_valid         : std_logic := '0';
    signal min_max_was_valid        : std_logic := '0';

    -- Thresholds for distinguishing pulse length
    signal threshold_1_5            : t_transition_time := 0;
    signal threshold_2_5            : t_transition_time := 0;

    -- Pulse length is determined by comparing to thresholds
    signal pulse_length             : std_logic_vector (1 downto 0) := ZERO;

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
            if sync_in = '0' then
                -- Reset
                min_measured_time <= max_transition_time;
                max_measured_time <= 0;
                valid_transitions <= 0;

            elsif transition_time_strobe = '1' then
                -- New transition
                if min_max_is_valid = '0' then
                    -- Transition sequence appears valid, increase stability
                    valid_transitions <= valid_transitions + 1;
                end if;

                if transition_time = max_transition_time then
                    -- invalid time: reset everything
                    min_measured_time <= max_transition_time;
                    max_measured_time <= 0;
                    valid_transitions <= 0;
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
            end if;
        end if;
    end process min_max_transition_time;

    threshold_calc : process (clock_in)
        subtype t_bigger is Natural range 0 to (((max_transition_time + 1) * 2) - 1);
        variable x0_5, x1_0, x2_0, x4_0 : t_bigger := 0;
        variable l : line;
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
            x2_0 := x4_0 / 2;
            x1_0 := x2_0 / 2;
            x0_5 := x1_0 / 2;
            threshold_1_5 <= t_transition_time (x1_0 + x0_5);
            threshold_2_5 <= t_transition_time (x2_0 + x0_5);
            single_time_out <= std_logic_vector (to_unsigned (63, 8));
            min_max_was_valid <= min_max_is_valid;

            if min_max_is_valid = '1' then
                single_time_out <= std_logic_vector (to_unsigned (x1_0 mod 256, 8));
                if debug and min_max_was_valid = '0' then
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
            end if;
        end if;
    end process threshold_calc;

    pulse_transition_time : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            pulse_length_out <= ZERO;
            sync_out <= '0';
            if min_max_is_valid = '1' then
                sync_out <= '1';
                if transition_time_strobe = '1' then
                    if threshold_1_5 >= transition_time then
                        pulse_length_out <= ONE;
                    elsif threshold_2_5 >= transition_time then
                        pulse_length_out <= TWO;
                    else
                        pulse_length_out <= THREE;
                    end if;
                end if;
            end if;
        end if;
    end process pulse_transition_time;

end structural;
