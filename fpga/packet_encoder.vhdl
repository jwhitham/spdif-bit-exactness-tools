
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

    type t_packet_state is (READY,
                            B_HEADER, B_HEADER_2, B_HEADER_3,
                            MW_HEADER,
                            M_HEADER, M_HEADER_2,
                            W_HEADER, W_HEADER_2,
                            PACKET_BODY,
                            DESYNC);
    signal packet_state : t_packet_state := READY;

    subtype t_bit_count is unsigned (4 downto 0);
    signal bit_count    : t_bit_count := (others => '0');

    signal repeat       : std_logic := '0';


begin
    process (clock)
    begin
        if clock'event and clock = '1' then
            pulse_length_out <= ZERO;

            if repeat = '1' then
                repeat <= '0';
                pulse_length_out <= ONE;
            end if;
            if shift_in = '1' then
                case packet_state is
                    when READY =>
                        -- Await start of packet
                        -- There are 28 bits in each packet excluding the 4 special header bits
                        bit_count <= to_unsigned (28, 5);
                        if start_in = '1' and sync_in = '1' then
                            -- Begin the header.
                            -- We expect to receive one of:
                            -- 1000 (B) 0100 (W) 0010 (M)
                            -- for which we will generate
                            -- B: THREE ONE ONE THREE
                            -- W: THREE TWO ONE TWO
                            -- M: THREE THREE ONE ONE
                            pulse_length_out <= THREE; -- Generated THREE so far
                            sync_out <= '1';
                            if data_in = '1' then
                                packet_state <= B_HEADER;
                            else
                                packet_state <= MW_HEADER;
                            end if;
                        end if;
                    when B_HEADER =>
                        -- Expecting to receive 000
                        if data_in = '1' then
                            packet_state <= DESYNC;
                        else
                            pulse_length_out <= ONE; -- Generated THREE ONE so far
                            packet_state <= B_HEADER_2;
                        end if;
                    when B_HEADER_2 =>
                        -- Expecting to receive 00
                        if data_in = '1' then
                            packet_state <= DESYNC;
                        else
                            pulse_length_out <= ONE; -- Generated THREE ONE ONE
                            packet_state <= B_HEADER_3;
                        end if;
                    when B_HEADER_3 =>
                        -- Expecting to receive 0
                        if data_in = '1' then
                            packet_state <= DESYNC;
                        else
                            pulse_length_out <= THREE; -- Generated THREE ONE ONE THREE (B)
                            packet_state <= PACKET_BODY;
                        end if;
                    when MW_HEADER =>
                        -- Expecting to receive 100 (W) or 010 (M)
                        if data_in = '1' then
                            pulse_length_out <= TWO; -- Generated THREE TWO so far
                            packet_state <= W_HEADER;
                        else
                            pulse_length_out <= THREE; -- Generated THREE THREE so far
                            packet_state <= M_HEADER;
                        end if;
                    when W_HEADER =>
                        -- Expecting to receive 00
                        if data_in = '1' then
                            packet_state <= DESYNC;
                        else
                            pulse_length_out <= ONE; -- Generated THREE TWO ONE so far
                            packet_state <= W_HEADER_2;
                        end if;
                    when W_HEADER_2 =>
                        -- Expecting to receive 0
                        if data_in = '1' then
                            packet_state <= DESYNC;
                        else
                            pulse_length_out <= TWO; -- Generated THREE TWO ONE TWO (W)
                            packet_state <= PACKET_BODY;
                        end if;
                    when M_HEADER =>
                        -- Expecting to receive 10
                        if data_in = '1' then
                            pulse_length_out <= ONE; -- Generated THREE THREE ONE
                            packet_state <= M_HEADER_2;
                        else
                            packet_state <= DESYNC;
                        end if;
                    when M_HEADER_2 =>
                        -- Expecting to receive 0
                        if data_in = '1' then
                            packet_state <= DESYNC;
                        else
                            pulse_length_out <= ONE; -- Generated THREE THREE ONE ONE (M)
                            packet_state <= PACKET_BODY;
                        end if;
                    when PACKET_BODY =>
                        -- Translate incoming bits to pulse lengths
                        if data_in = '1' then
                            -- bit 1: generate ONE ONE
                            pulse_length_out <= ONE;
                            repeat <= '1';
                        else
                            -- bit 0: generate TWO
                            pulse_length_out <= TWO;
                        end if;

                        if bit_count = 0 then
                            packet_state <= READY;
                        else
                            bit_count <= bit_count - 1;
                        end if;
                    when DESYNC =>
                        sync_out <= '0';
                end case;
            end if;

            if sync_in = '0' then
                -- sits in READY state until sync'ed
                packet_state <= READY;
                sync_out <= '0';
            elsif start_in = '1' and (packet_state /= READY or shift_in /= '1') then
                -- Detect invalid start
                packet_state <= DESYNC;
                sync_out <= '0';
            end if;
        end if;
    end process;


end structural;
