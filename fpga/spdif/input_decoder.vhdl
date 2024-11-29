-- S/PDIF input decoder: the input is raw data from the optical receiver.

library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use debug_textio.all;

-- The "single pulse time" X is the smallest possible number of clock cycles that the
-- input stays in either the 1 state or the 0 state. The S/PDIF signals use a mixture
-- of pulses of length X, 2X and 3X to transfer data.
-- 
-- In this application we will normally be using X values in the range 7 .. 24. To
-- get the range of X, divide the system clock frequency by the sample rate, and divide
-- again by 128 as there are two packets per sample (stereo) and each is 64 single times.
-- 
-- The system clock frequency is 96MHz, so "ideal" X values are:
-- e.g. 48kHz: single time = 96e6 / (48e3 * 64 * 2) = 15.6 clocks
--   or 32kHz: single time 23.4 clocks
--   or 96kHz: single time 7.8 clocks
--
-- Realistic single times may vary due to clock speed inaccuracies and the
-- decoder is such that no specific X value is expected, provided that X is
-- within the minimum/maximum permitted range. The minimum is 4 (min_transition_time)
-- and the theoretical maximum is 101 (though up to 254 can be measured) because
-- 101 will result in a minimum length for a 3X pulse of 253 clock cycles.

entity input_decoder is
    generic (
        enough_transitions     : Natural := 31;
        debug                  : Boolean := false);
    port (
        data_in          : in std_logic;
        pulse_length_out : out std_logic_vector (1 downto 0) := "00";
        single_time_out  : out std_logic_vector (7 downto 0) := (others => '0');
        sync_out         : out std_logic := '0';
        enable_123_check_in : in std_logic;
        sync_in          : in std_logic;
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
    -- cycles in order to reach the end of the pipeline. Also, very small
    -- measurements are strongly affected by errors and can't be reliably
    -- distinguished.
    constant min_transition_time    : Natural := 4;

    -- The maximum transition time is the length of a THREE pulse
    constant max_transition_time    : Natural := 255;

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
    signal invalid_333              : std_logic := '0';

    -- We can also detect incorrect timings by detecting the invalid 212 sequence
    -- (stage 5)
    type t_previous is array (Natural range 1 to 4) of std_logic_vector (1 downto 0);
    signal previous                 : t_previous := (others => ZERO);
    signal invalid_212              : std_logic := '0';

    -- We can also detect incorrect timings by detecting packets which don't contain
    -- a mixture of ONE and TWO pulses (stage 5)
    constant max_last_seen          : Natural := 63;
    subtype t_last_seen is Natural range 0 to max_last_seen;
    type t_last_seen_array is array (Natural range 1 to 3) of t_last_seen;
    signal last_seen                : t_last_seen_array := (others => 0);
    signal invalid_123              : std_logic := '0';

begin

    measure_transition_time : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            delay0 <= data_in;
            delay1 <= delay0;

            transition_time_strobe <= '0';
            if sync_in = '0' then
                timer <= 1;

            elsif delay0 = delay1 and timer /= max_transition_time then
                -- No transition - measure time
                timer <= timer + 1;

            else
                -- New transition or overflow: Report the time.
                -- If the timer = max_transition_time, this will cause a fast desync, as the
                -- input signal has been lost.
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
                    write (l, String'("input decoder measured "));
                    write (l, transition_time);
                    writeline (output, l);
                end if;

                if min_max_is_valid = '0' then
                    -- Transition sequence appears valid, increase stability
                    valid_transitions <= valid_transitions + 1;
                    if debug then
                        write (l, String'("input decoder increase validity"));
                        writeline (output, l);
                    end if;
                end if;

                if invalid_333 = '1'
                        or invalid_212 = '1'
                        or invalid_123 = '1'
                        or transition_time = max_transition_time 
                        or transition_time < min_transition_time then
                    -- The pulse sequence is not valid
                    -- or the pulse time is too long/short
                    -- -> reset everything
                    min_measured_time <= max_transition_time;
                    max_measured_time <= min_transition_time;
                    valid_transitions <= 0;
                    if debug then
                        write (l, String'("input decoder reset due to"));
                        if invalid_333 = '1' then
                            write (l, String'(" 333"));
                        end if;
                        if invalid_212 = '1' then
                            write (l, String'(" 212"));
                        end if;
                        if invalid_123 = '1' then
                            write (l, String'(" 123"));
                        end if;
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
                            write (l, String'("input decoder new max_measured_time="));
                            write (l, transition_time);
                            writeline (output, l);
                        end if;
                    end if;
                    if min_measured_time > transition_time then
                        -- new minimum does not reset measurements
                        min_measured_time <= transition_time;
                        if debug then
                            write (l, String'("input decoder new min_measured_time="));
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
        -- abs_peak is the absolute maximum value that may be generated in the threshold calculations
        constant abs_peak : Natural := max_transition_time * 2 * 5;
        subtype t_bigger is Natural range 0 to abs_peak;

        variable x1_5, x2_5, x4_0 : t_bigger := 0;
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
            --
            x4_0 := t_bigger (min_measured_time) + t_bigger (max_measured_time);
            x1_5 := (x4_0 * 3) / 8;
            x2_5 := (x4_0 * 5) / 8;

            -- Threshold 2.5X can overflow in initial measurements and pathological cases.
            -- In these cases the threshold will be temporarily invalid and unusable.
            threshold_2_5 <= t_transition_time (x2_5 mod (max_transition_time + 1));
            threshold_1_5 <= t_transition_time (x1_5);
            single_time_out <= std_logic_vector (to_unsigned (0, 8));

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
            write (l, String'("input decoder threshold_calc min_measured_time="));
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

    -- There must be at least one ONE in any sequence containing three THREEs.
    -- Detect this condition by counting threes.
    -- If there was a B packet containing all zeroes, followed by an M header,
    -- then the resulting sequence would be 3113222...2223311 which would trigger
    -- the 333 rule. However, in a stereo signal, B is always followed by W.
    check_threes : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            case pulse_length is
                when ONE =>
                    three_counter <= 0;
                when THREE =>
                    if three_counter /= too_many_threes then
                        three_counter <= three_counter + 1;
                    end if;
                when others =>
                    if valid_transitions = 0 then
                        three_counter <= 0;
                    end if;
            end case;
            invalid_333 <= '0';
            if three_counter = too_many_threes then
                invalid_333 <= '1';
            end if;
        end if;
    end process check_threes;

    -- The sequence 3212 is valid (header) but 1212 and 2212 are not.
    -- Detect this condition by tracking the last 4 pulse lengths.
    check_212 : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if pulse_length /= ZERO then
                for i in 1 to 3 loop
                    previous (i) <= previous (i + 1);
                end loop;
                previous (4) <= pulse_length;
            end if;
            if valid_transitions = 0 then
                previous (4) <= ZERO;
            end if;
            invalid_212 <= '0';
            if (previous (1) = ONE or previous (1) = TWO)
                    and previous (2) = TWO and previous (3) = ONE
                    and previous (4) = TWO then
                invalid_212 <= '1';
            end if;
        end if;
    end process check_212;

    -- Every packet should contain at least one of each pulse length.
    check_123 : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            invalid_123 <= '0';
            for i in 1 to 3 loop
                if valid_transitions = 0 or enable_123_check_in = '0' then
                    -- reset all counters
                    last_seen (i) <= 0;
                elsif last_seen (i) = max_last_seen then
                    -- It has been too long since we saw this type of pulse
                    -- The time for each packet is 64X (where X is the time for ONE)
                    -- and in this time there must be at least one THREE and
                    -- at least one TWO, so we expect the maximum interval between
                    -- any pair of pulses of the same length to be 63
                    invalid_123 <= '1';
                elsif pulse_length /= ZERO then
                    -- Increase counter
                    last_seen (i) <= last_seen (i) + 1;
                end if;
            end loop;

            -- Receiving a specific pulse length resets the counter
            case pulse_length is
                when ONE =>
                    last_seen (1) <= 0;
                when TWO =>
                    last_seen (2) <= 0;
                when THREE =>
                    last_seen (3) <= 0;
                when others =>
                    null;
            end case;
        end if;
    end process check_123;

end structural;
