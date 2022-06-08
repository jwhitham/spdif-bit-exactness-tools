
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clock_regenerator is
    port (
        pulse_length_in  : in std_logic_vector (1 downto 0) := "00";
        sync_in          : in std_logic;
        sync_out         : out std_logic := '0';
        clock_in         : in std_logic;
        strobe_out       : out std_logic := '0'
    );
end clock_regenerator;

architecture structural of clock_regenerator is

    constant num_packets_log_2           : Integer := 8;
    constant num_clocks_per_packet_log_2 : Integer := 6;
    constant max_transition_time_log_2   : Integer := 8;
    constant fixed_point_bits            : Integer := num_packets_log_2 + num_clocks_per_packet_log_2;
    constant counter_bits                : Integer := fixed_point_bits + max_transition_time_log_2;

    -- Count the number of clock_in cycles required for 2**num_packets_log_2 packets
    -- Use this to make a fixed point clock divider to convert clock_in to strobe_out
    subtype t_their_packets is unsigned ((num_packets_log_2 - 1) downto 0);
    subtype t_my_clocks is unsigned ((counter_bits - 1) downto 0);
    constant zero_packets       : t_their_packets := (others => '0');
    constant zero_clocks        : t_my_clocks := (others => '0');

    signal their_packets        : t_their_packets := zero_packets;
    signal my_clocks            : t_my_clocks := (others => '0');
    signal my_clocks_done       : t_my_clocks := (others => '0');

    signal divisor              : t_my_clocks := (others => '0');
    constant fixed_point_one    : t_mY_clocks := (fixed_point_bits => '1', others => '0');

    type t_measurement_state is (START, IN_HEADER_1, IN_HEADER_2, IN_HEADER_3, IN_BODY);
    signal measurement_state    : t_measurement_state := START;
    signal sync_gen             : std_logic := '0';

    subtype t_clock_count is unsigned ((num_clocks_per_packet_log_2 - 1) downto 0);
    constant zero_clock_count   : t_clock_count := (others => '0');
    signal clock_count          : t_clock_count := zero_clock_count;
    signal packet_start_strobe  : std_logic := '0';

    signal strobe_gen           : std_logic := '0';
begin
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            my_clocks <= my_clocks + 1;
            packet_start_strobe <= '0';
            case measurement_state is
                when START =>
                    -- wait for the start of a new packet
                    my_clocks <= zero_clocks + 1;
                    their_packets <= zero_packets;
                    my_clocks_done <= zero_clocks;
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
                        their_packets <= their_packets + 1;
                    end if;
                when IN_BODY =>
                    -- wait until the end of the body (sync pulse)
                    if pulse_length_in = "11" then
                        if their_packets = zero_packets then
                            -- counting is complete
                            my_clocks_done <= my_clocks;
                            my_clocks <= zero_clocks + 1;
                            sync_gen <= '1';
                        end if;
                        -- back to the header
                        measurement_state <= IN_HEADER_1;
                        packet_start_strobe <= '1';
                    end if;
            end case;
            if sync_in = '0' then
                -- reset on desync
                measurement_state <= START;
            end if;
        end if;
    end process;

    sync_out <= sync_gen;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            strobe_out <= '0';

            if sync_gen = '0' then
                -- Do nothing while waiting for the measurement stage to synchronise
                divisor <= (others => '0');
                clock_count <= (others => '0');
            elsif packet_start_strobe = '1' then
                -- Output: start the packet with a clock tick
                divisor <= (others => '0');
                clock_count <= (others => '1');
                strobe_out <= '1';
            elsif clock_count /= zero_clock_count then
                -- Output: wait for the right time to send another clock tick
                if divisor < my_clocks_done then
                    divisor <= divisor + fixed_point_one;
                else
                    divisor <= divisor + fixed_point_one - my_clocks_done;
                    strobe_out <= '1';
                    clock_count <= clock_count - 1;
                end if;
            end if;
        end if;
    end process;

end structural;