
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity packet_encoder is
    port (
        pulse_length_out : out std_logic_vector (1 downto 0);
        sync_out         : out std_logic;
        data_in          : in std_logic;
        shift_in         : in std_logic;
        start_in         : in std_logic;
        sync_in          : in std_logic;
        clock            : in std_logic
    );
end packet_encoder;

architecture structural of packet_encoder is

    subtype t_pulse_length is std_logic_vector (1 downto 0);
    constant ZERO           : t_pulse_length := "00";
    constant ONE            : t_pulse_length := "01";
    constant TWO            : t_pulse_length := "10";
    constant THREE          : t_pulse_length := "11";

    type t_header_type is (B_HEADER, W_HEADER, M_HEADER);
    signal header_type      : t_header_type := B_HEADER;

    subtype t_bit_count is Natural range 0 to 31;
    signal bit_count        : t_bit_count := 0;
    signal repeat           : std_logic := '0';

begin
    process (clock)
    begin
        if clock'event and clock = '1' then
            pulse_length_out <= ZERO;


            if sync_in = '0' then
                -- Wait for sync
                bit_count <= 0;
                sync_out <= '0';
                repeat <= '0';

            elsif repeat = '1' then
                -- Repeat ONE
                repeat <= '0';
                pulse_length_out <= ONE;
                assert shift_in = '0';
                assert start_in = '0';

            elsif shift_in = '1' then
                bit_count <= t_bit_count (Natural (bit_count + 1) mod 32);
                if start_in = '1' then
                    case bit_count is
                        when 0 =>
                            -- Begin the header.
                            -- We expect to receive one of:
                            -- 1000 (B) 0100 (W) 0010 (M)
                            -- for which we will generate
                            -- B: 3113
                            -- W: 3212
                            -- M: 3311
                            pulse_length_out <= THREE; -- Generated THREE so far
                            sync_out <= '1';
                            if data_in = '1' then
                                header_type <= B_HEADER;
                            else
                                header_type <= W_HEADER; -- or maybe M_HEADER..
                            end if;
                        when others =>
                            -- start bit should not be high
                            bit_count <= 0;
                            sync_out <= '0';
                            assert False;
                    end case;
                else
                    case bit_count is
                        when 0 =>
                            -- Wait for start
                            bit_count <= 0;
                        when 1 =>
                            case header_type is
                                when B_HEADER =>
                                    -- Received 1 expecting to receive 000
                                    if data_in = '1' then
                                        bit_count <= 0;
                                        sync_out <= '0';
                                        assert False;
                                    else
                                        pulse_length_out <= ONE; -- Generated 31
                                    end if;
                                when W_HEADER | M_HEADER =>
                                    -- Received 0 expecting to receive 100 (W) or 010 (M)
                                    if data_in = '1' then
                                        pulse_length_out <= TWO; -- Generated 32
                                        header_type <= W_HEADER;
                                    else
                                        pulse_length_out <= THREE; -- Generated 33
                                        header_type <= M_HEADER;
                                    end if;
                            end case;
                        when 2 =>
                            case header_type is
                                when B_HEADER =>
                                    -- Received 10 expecting to receive 00
                                    if data_in = '1' then
                                        bit_count <= 0;
                                        sync_out <= '0';
                                        assert False;
                                    else
                                        pulse_length_out <= ONE; -- Generated 311
                                    end if;
                                when W_HEADER =>
                                    -- Received 01 expecting to receive 00
                                    if data_in = '1' then
                                        bit_count <= 0;
                                        sync_out <= '0';
                                        assert False;
                                    else
                                        pulse_length_out <= ONE; -- Generated 321
                                    end if;
                                when M_HEADER =>
                                    -- Received 00 expecting to receive 10
                                    if data_in = '1' then
                                        pulse_length_out <= ONE; -- Generated 331
                                    else
                                        bit_count <= 0;
                                        sync_out <= '0';
                                        assert False;
                                    end if;
                            end case;
                        when 3 =>
                            case header_type is
                                when B_HEADER =>
                                    -- Received 100 expecting to receive 0
                                    if data_in = '1' then
                                        bit_count <= 0;
                                        sync_out <= '0';
                                        assert False;
                                    else
                                        pulse_length_out <= THREE; -- Generated 3113
                                    end if;
                                when W_HEADER =>
                                    -- Received 010 expecting to receive 0
                                    if data_in = '1' then
                                        bit_count <= 0;
                                        sync_out <= '0';
                                        assert False;
                                    else
                                        pulse_length_out <= TWO; -- Generated 3212
                                    end if;
                                when M_HEADER =>
                                    -- Received 001 expecting to receive 0
                                    if data_in = '1' then
                                        bit_count <= 0;
                                        sync_out <= '0';
                                        assert False;
                                    else
                                        pulse_length_out <= ONE; -- Generated 3311
                                    end if;
                            end case;
                        when 4 to 31 =>
                            -- Translate incoming bits to pulse lengths
                            if data_in = '1' then
                                -- bit 1: generate ONE ONE
                                pulse_length_out <= ONE;
                                repeat <= '1';
                            else
                                -- bit 0: generate TWO
                                pulse_length_out <= TWO;
                            end if;
                        when others =>
                            bit_count <= 0;
                            sync_out <= '0';
                            assert False;
                    end case;
                end if;
            end if;
        end if;
    end process;


end structural;
