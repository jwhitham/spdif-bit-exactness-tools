
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity combined_encoder is
    generic (debug : Boolean := false);
    port (
        data_out                : out std_logic := '0';
        sync_out                : out std_logic := '0';
        error_out               : out std_logic := '0';
        data_in                 : in std_logic_vector (31 downto 0);
        left_strobe_in          : in std_logic;
        right_strobe_in         : in std_logic;
        preemph_in              : in std_logic;
        spdif_clock_strobe_in   : in std_logic;
        sync_in                 : in std_logic;
        clock_in                : in std_logic);
end combined_encoder;

architecture structural of combined_encoder is

    -- data output
    constant FIRST_DATA_BIT    : Natural := 4;
    constant LAST_DATA_BIT     : Natural := 30;
    constant SUBCODE_BIT       : Natural := 30;
    constant USER_BIT          : Natural := 29;
    constant VALIDITY_BIT      : Natural := 28;

    -- types
    type t_header is (HEADER_B, HEADER_W, HEADER_M);
    subtype t_bit_counter is unsigned (6 downto 0);
    subtype t_data is std_logic_vector (LAST_DATA_BIT downto FIRST_DATA_BIT);

    -- subcode output
    constant B_INTERVAL     : Natural := 192;
    subtype t_subcode_counter is Natural range 0 to B_INTERVAL - 1;

    -- startup process
    constant READY                  : Natural := 0;
    constant WAIT_FOR_FIRST_PACKET  : Natural := 31;
    subtype t_startup_counter is Natural range READY to WAIT_FOR_FIRST_PACKET;

    -- Registers
    signal parity                   : std_logic := '0';
    signal bit_counter              : t_bit_counter := (others => '0');
    signal transition               : std_logic := '0';
    signal spdif_gen                : std_logic := '1';
    signal subcode_counter          : t_subcode_counter := 0;
    signal startup_counter          : t_startup_counter := WAIT_FOR_FIRST_PACKET;
    signal packet_reject_error      : std_logic := '0';
    signal packet_not_ready_error   : std_logic := '0';
    signal buffer_data              : t_data := (others => '0');
    signal buffer_header            : t_header := HEADER_M;
    signal shift_data               : t_data := (others => '0');
    signal header_type              : t_header := HEADER_M;
    signal packet_enable            : std_logic := '0';

begin

    error_out <= packet_reject_error or packet_not_ready_error;

    input_buffer : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            packet_reject_error <= '0';
            assert (left_strobe_in and right_strobe_in) = '0';

            if sync_in = '0' or packet_reject_error = '1' or packet_not_ready_error = '1' then
                -- Reset
                subcode_counter <= 0;
                startup_counter <= WAIT_FOR_FIRST_PACKET;

            elsif left_strobe_in = '1' or right_strobe_in = '1' then

                -- New packet arrives: it can only be accepted in certain specific states
                if bit_counter (5 downto 1) = "00000" and startup_counter /= WAIT_FOR_FIRST_PACKET then
                    -- Can't accept new packets at this time because we are about to begin a new one
                    packet_reject_error <= '1';
                    if debug then
                        write (l, String'("combined encoder: reject new packet (about to begin a new one)"));
                        writeline (output, l);
                    end if;
                elsif bit_counter (6) = right_strobe_in and startup_counter /= WAIT_FOR_FIRST_PACKET then
                    -- Can't accept a new "left" packet while we are still transmitting "left" (needs to be "right")
                    -- Can't accept a new "right" packet while we are still transmitting "right" (needs to be "left")
                    packet_reject_error <= '1';
                    if debug then
                        write (l, String'("combined encoder: reject new packet (too early)"));
                        writeline (output, l);
                    end if;
                else
                    -- New packet accepted
                    buffer_data <= data_in (LAST_DATA_BIT downto FIRST_DATA_BIT);

                    -- Generate B/M header and advance subcode counter
                    if right_strobe_in = '0' then
                        if subcode_counter = 0 then
                            buffer_header <= HEADER_B;
                        else
                            buffer_header <= HEADER_M;
                        end if;
                    else
                        buffer_header <= HEADER_W;
                        if subcode_counter = B_INTERVAL - 1 then
                            subcode_counter <= 0;
                        else
                            subcode_counter <= subcode_counter + 1;
                        end if;
                    end if;

                    -- See https://www.minidisc.org/manuals/an22.pdf for description of subcode bits
                    -- They repeat periodically, beginning with a B packet, which is sent every B_INTERVAL.
                    case subcode_counter is
                        when 2 =>
                            buffer_data (SUBCODE_BIT) <= '1'; -- copy
                        when 13 =>
                            buffer_data (SUBCODE_BIT) <= '1'; -- category 0x02 - PCM encoder/decoder
                        when 3 =>
                            buffer_data (SUBCODE_BIT) <= preemph_in; -- DAC instructed to undo 15/50 preemphasis
                        when others =>
                            buffer_data (SUBCODE_BIT) <= '0';
                    end case;
                    buffer_data (VALIDITY_BIT) <= '0'; -- can be D/A converted
                    buffer_data (USER_BIT) <= '0';

                    if startup_counter /= READY then
                        if right_strobe_in = '0' then
                            -- This packet will be transmitted after a delay which ensures that
                            -- (1) a left packet is transmitted first, and (2) new packets arrive
                            -- in the middle of the process for transmitting the previous one, i.e. when
                            -- bit_counter mod 64 = 32.
                            startup_counter <= WAIT_FOR_FIRST_PACKET - 1;
                            if debug then
                                write (l, String'("combined encoder: start countdown"));
                                writeline (output, l);
                                assert startup_counter = WAIT_FOR_FIRST_PACKET;
                            end if;
                        else
                            if debug then
                                write (l, String'("combined encoder: await left packet before starting countdown"));
                                writeline (output, l);
                                assert startup_counter = WAIT_FOR_FIRST_PACKET;
                            end if;
                        end if;
                    end if;
                end if;

            elsif startup_counter /= READY and startup_counter /= WAIT_FOR_FIRST_PACKET then
                -- Startup process is running; wait for the delay to expire
                if spdif_clock_strobe_in = '1' then
                    startup_counter <= startup_counter - 1;
                    if debug then
                        write (l, String'("combined encoder: startup counter = "));
                        write (l, startup_counter);
                        writeline (output, l);
                    end if;
                end if;
            end if;
        end if;
    end process input_buffer;

    -- Packet output as S/PDIF
    packet_generator : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            packet_not_ready_error <= '0';
            transition <= '0';

            if spdif_clock_strobe_in = '1' then
                bit_counter <= bit_counter + to_unsigned (1, 7);
                case to_integer (bit_counter (5 downto 0)) is
                    when 0 =>
                        -- Start of the header: wait for the start signal from the input_buffer process.
                        -- Header transitions occur in the following patterns
                        -- B: 3113  - transitions on 0,3,4,5,8
                        -- W: 3212  - transitions on 0,3,5,6,8
                        -- M: 3311  - transitions on 0,3,6,7,8
                        if startup_counter /= READY then
                            bit_counter <= to_unsigned (0, 7);
                        else
                            transition <= '1';
                        end if;

                    when 1 =>
                        -- Load new data now
                        parity <= '0';
                        if bit_counter (6) = '0' then
                            -- Left
                            if buffer_header = HEADER_B or buffer_header = HEADER_M then
                                -- Left data ready
                                shift_data <= buffer_data;
                                header_type <= buffer_header;
                            else
                                -- Left data not ready! Problem. Stop.
                                packet_not_ready_error <= '1';
                            end if;
                        else
                            -- Right 
                            if buffer_header = HEADER_W then
                                -- Right data ready
                                shift_data <= buffer_data;
                                header_type <= HEADER_W;
                            else
                                -- Right data not ready! Problem. Stop.
                                packet_not_ready_error <= '1';
                            end if;
                        end if;

                    when 2 =>
                        -- Final part of first THREE
                        null;

                    when 3 =>
                        transition <= '1';

                    when 4 =>
                        if header_type = HEADER_B then
                            transition <= '1';
                        end if;

                    when 5 =>
                        if header_type = HEADER_B or header_type = HEADER_W then
                            transition <= '1';
                        end if;

                    when 6 =>
                        if header_type = HEADER_W or header_type = HEADER_M then
                            transition <= '1';
                        end if;

                    when 7 =>
                        if header_type = HEADER_M then
                            transition <= '1';
                        end if;

                    when 63 =>
                        -- first part of parity bit
                        if parity = '1' then
                            -- bit 1: generate two pulses of length 1
                            transition <= '1';
                        else
                            -- bit 0: generate one pulse of length 2
                            null;
                        end if;

                    when others =>
                        -- general case for most data bits
                        if bit_counter (0) = '1' then
                            -- Second part of each bit
                            if shift_data (FIRST_DATA_BIT) = '1' then
                                -- bit 1: generate two pulses of length 1
                                transition <= '1';
                            else
                                -- bit 0: generate one pulse of length 2
                                null;
                            end if;
                            parity <= parity xor shift_data (FIRST_DATA_BIT);
                            shift_data (LAST_DATA_BIT - 1 downto FIRST_DATA_BIT)
                                    <= shift_data (LAST_DATA_BIT downto FIRST_DATA_BIT + 1);
                        else
                            -- First part of each bit
                            transition <= '1';
                        end if;
                end case;
            end if;
        end if;
    end process packet_generator;

    spdif_generator : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if transition = '1' then
                spdif_gen <= not spdif_gen;
            end if;
        end if;
    end process spdif_generator;

    -- sync out
    sync_out <= '1' when startup_counter = READY else '0';

    -- S/PDIF data output
    data_out <= spdif_gen;

end structural;
