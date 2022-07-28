-- S/PDIF clock regenerator: produce clock pulses that match the input signal

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The "single pulse time" X is the smallest possible number of clock cycles that the
-- output stays in either the 1 state or the 0 state. This component generates clock
-- pulses with interval X in order to match the input signal. It measures the time
-- for a complete packet to be received by looking for the 3X pulse at the beginning
-- of each packet header.
--
-- X does not have to be an integer number of clock cycles but must be within the
-- permitted range. The maximum value of X is 62 clock cycles (see "overflow_point").
-- The minimum value of X is 2 clock cycles.

entity clock_regenerator is
    port (
        pulse_length_in         : in std_logic_vector (1 downto 0) := "00";
        clock_interval_out      : out std_logic_vector (15 downto 0) := (others => '0');
        sync_in                 : in std_logic;
        sync_out                : out std_logic := '0';
        clock_in                : in std_logic;
        packet_start_strobe_in  : in std_logic := '0';
        spdif_clock_strobe_out  : out std_logic := '0');
end clock_regenerator;

architecture structural of clock_regenerator is

    constant num_packets_log_2           : Integer := 4;    -- average the single-width pulse time across 16 packets
    constant num_clocks_per_packet_log_2 : Integer := 6;    -- S/PDIF packet length is exactly 64 pulses
    constant max_transition_time_log_2   : Integer := 6;    -- max 63 clock cycles for a single-width pulse
    constant fixed_point_bits            : Integer := num_packets_log_2 + num_clocks_per_packet_log_2;
    constant counter_bits                : Integer := fixed_point_bits + max_transition_time_log_2;

    -- Count the number of clock_in cycles required for 2**num_packets_log_2 packets
    -- Use this to make a fixed point clock divider to convert clock_in to spdif_clock_strobe_out
    subtype t_packet_counter is unsigned ((num_packets_log_2 - 1) downto 0);
    subtype t_clock_counter is unsigned ((counter_bits - 1) downto 0);
    constant zero_packets       : t_packet_counter := (others => '0');
    constant zero_clocks        : t_clock_counter := (others => '0');

    signal packet_counter       : t_packet_counter := zero_packets;
    signal clock_counter        : t_clock_counter := (others => '0');
    signal clock_interval       : t_clock_counter := (others => '0');
    signal fixed_point_one_minus_clock_interval : t_clock_counter := (others => '0');

    signal divisor              : t_clock_counter := (others => '0');
    constant fixed_point_one    : t_clock_counter := (fixed_point_bits => '1', others => '0');

    -- This is the true maximum value allowed for clock_counter, in order to ensure
    -- that overflows can be reliably detected when adding to divisor
    constant overflow_point     : t_clock_counter :=
        to_unsigned ((2 ** counter_bits) - 2, counter_bits) - fixed_point_one;

    type t_measurement_state is (START, IN_HEADER_1, IN_HEADER_2, IN_HEADER_3, IN_BODY);
    signal measurement_state    : t_measurement_state := START;
    signal sync_gen             : std_logic := '0';

    subtype t_out_clock_count is Natural range 0 to (2 ** num_clocks_per_packet_log_2) - 1;
    signal out_clock_count      : t_out_clock_count := 0;
    signal packet_start_strobe  : std_logic := '0';

    signal strobe_gen           : std_logic := '0';

    type t_output_state is (RESET, ADD, SUBTRACT);
    signal output_state         : t_output_state := RESET;
begin
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            clock_counter <= clock_counter + 1;
            case measurement_state is
                when START =>
                    -- wait for the start of a new packet
                    clock_counter <= zero_clocks + 1;
                    packet_counter <= zero_packets;
                    clock_interval <= zero_clocks;
                    sync_gen <= '0';
                    if pulse_length_in = "11" then
                        measurement_state <= IN_HEADER_1;
                    end if;
                when IN_HEADER_1 =>
                    -- wait until the body is reached (count 3 pulses of any length)
                    if pulse_length_in /= "00" then
                        measurement_state <= IN_HEADER_2;
                    end if;
                when IN_HEADER_2 =>
                    -- wait until the body is reached (count 2 more pulses of any length)
                    if pulse_length_in /= "00" then
                        measurement_state <= IN_HEADER_3;
                    end if;
                when IN_HEADER_3 =>
                    -- wait until the body is reached (count 1 more pulse of any length)
                    if pulse_length_in /= "00" then
                        measurement_state <= IN_BODY;
                        packet_counter <= packet_counter + 1;
                    end if;
                when IN_BODY =>
                    -- wait until the end of the body (sync pulse)
                    if pulse_length_in = "11" then
                        if packet_counter = zero_packets then
                            -- counting is complete
                            if to_integer (clock_counter (counter_bits - 1 downto fixed_point_bits + 1)) = 0 then
                                -- The total count is less than 2 * fixed_point_one. The input is too fast;
                                -- we cannot generate clock pulses at this rate.
                                measurement_state <= START;
                            else
                                sync_gen <= '1';
                            end if;
                            clock_interval <= clock_counter;
                            clock_counter <= zero_clocks + 1;
                        end if;
                        -- back to the header
                        measurement_state <= IN_HEADER_1;
                    end if;
            end case;
            if sync_in = '0' then
                -- reset on desync
                measurement_state <= START;
            end if;
            if clock_counter = overflow_point then
                -- Counting won't be reliable. In particular, when we add fixed_point_one to divisor,
                -- we won't be able to determine if the result is greater than clock_interval,
                -- because it might have overflowed 2 ** counter_bits. The input is too slow.
                measurement_state <= START;
            end if;
        end if;
    end process;

    sync_out <= sync_gen;
    clock_interval_out <= std_logic_vector (clock_interval (15 downto 0));

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            spdif_clock_strobe_out <= '0';
            fixed_point_one_minus_clock_interval <= fixed_point_one - clock_interval;

            case output_state is
                when RESET =>
                    -- Do nothing while waiting for synchronisation and the start of a packet
                    divisor <= fixed_point_one + fixed_point_one;
                    out_clock_count <= (2 ** num_clocks_per_packet_log_2) - 2;
                    if packet_start_strobe_in = '1' and sync_gen = '1' then
                        -- Output: start the packet with a clock tick
                        spdif_clock_strobe_out <= '1';
                        output_state <= ADD;
                    end if;
                when ADD =>
                    divisor <= divisor + fixed_point_one;
                    if divisor >= clock_interval then
                        output_state <= SUBTRACT;
                    end if;
                when SUBTRACT =>
                    divisor <= divisor + fixed_point_one_minus_clock_interval;
                    spdif_clock_strobe_out <= '1';
                    if out_clock_count = 0 then
                        output_state <= RESET;
                    else
                        out_clock_count <= out_clock_count - 1;
                        output_state <= ADD;
                    end if;
            end case;
        end if;
    end process;

end structural;
