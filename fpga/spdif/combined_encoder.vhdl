
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity combined_encoder is
    port (
        data_out                : out std_logic := '0';
        sync_out                : out std_logic := '0';
        error_out               : out std_logic := '0';
        data_in                 : in std_logic_vector (31 downto 0);
        left_strobe_in          : in std_logic;
        right_strobe_in         : in std_logic;
        preemph_in              : in std_logic;
        packet_start_strobe_out : out std_logic := '0';
        spdif_clock_strobe_in   : in std_logic;
        sync_in                 : in std_logic;
        clock_in                : in std_logic);
end combined_encoder;

architecture structural of combined_encoder is

    -- subcode output
    constant b_interval     : Natural := 192;
    subtype t_subcode_counter is Natural range 0 to b_interval;

    -- data output
    subtype t_bit_counter is Natural range 0 to 31;
    constant first_data_bit    : t_bit_counter := 4;
    constant last_data_bit     : t_bit_counter := 30;
    constant bit_counter_start : t_bit_counter := 2 + last_data_bit - first_data_bit;
    constant subcode_bit       : t_bit_counter := 30;
    constant user_bit          : t_bit_counter := 29;
    constant validity_bit      : t_bit_counter := 28;
    subtype t_data is std_logic_vector (last_data_bit downto first_data_bit);

    -- header output
    subtype t_header is std_logic_vector (7 downto 0);
    subtype t_header_pulse is std_logic_vector (1 downto 0);
    constant THREE             : t_header_pulse := "11";
    constant TWO               : t_header_pulse := "10";
    constant ONE               : t_header_pulse := "01";
    constant ZERO              : t_header_pulse := "00";

    -- state
    type t_state is (RESET, AWAIT_NEW_PACKET,
                     SEND_HEADER, SEND_DATA,
                     SEND_ONE_PULSE, SEND_NO_PULSE);

    -- Registers
    signal parity           : std_logic := '0';
    signal buffer_data      : t_data := (others => '0');
    signal buffer_header    : t_header := (others => '0');
    signal shift_data       : t_data := (others => '0');
    signal shift_header     : t_header := (others => '0');
    signal subcode_counter  : t_subcode_counter := 0;
    signal bit_counter      : t_bit_counter := 0;
    signal state            : t_state := RESET;
    signal spdif_gen        : std_logic := '1';
    signal buffer_full      : std_logic := '0';

    -- Signals
    signal consume_buffer   : std_logic := '0';

begin

    -- Data input (single entry buffer)
    one_entry_buffer : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            if sync_in = '0' then
                -- Reset
                error_out <= '0';
                buffer_full <= '0';
                subcode_counter <= 0;
                sync_out <= '0';

            elsif left_strobe_in = '1' or right_strobe_in = '1' then
                -- New packet arrives - this is the last opportunity to consume the previous buffer entry
                error_out <= buffer_full and not consume_buffer;
                assert (buffer_full and not consume_buffer) = '0';
                buffer_full <= '1';

                -- Copy the data into the buffer
                buffer_data <= data_in (last_data_bit downto first_data_bit);

                -- Generate B/M header
                -- We will output pulses of the following lengths
                -- B: 3113
                -- W: 3212
                -- M: 3311
                if left_strobe_in = '1' then
                    if subcode_counter = 0 or subcode_counter = b_interval then
                        buffer_header <= THREE & ONE & ONE & THREE;
                        subcode_counter <= 1;
                        sync_out <= '1';
                    else
                        buffer_header <= THREE & TWO & ONE & TWO;
                        subcode_counter <= subcode_counter + 1;
                    end if;
                else
                    buffer_header <= THREE & THREE & ONE & ONE;
                end if;

                -- See https://www.minidisc.org/manuals/an22.pdf for description of subcode bits
                -- They repeat periodically, beginning with a B packet, which is sent every b_interval.
                case subcode_counter is
                    when 2 =>
                        buffer_data (subcode_bit) <= '1'; -- copy
                    when 13 =>
                        buffer_data (subcode_bit) <= '1'; -- category 0x02 - PCM encoder/decoder
                    when 3 =>
                        buffer_data (subcode_bit) <= preemph_in; -- DAC instructed to undo 15/50 preemphasis
                    when others =>
                        buffer_data (subcode_bit) <= '0';
                end case;
                buffer_data (validity_bit) <= '0'; -- can be D/A converted
                buffer_data (user_bit) <= '0';

            elsif consume_buffer = '1' then
                -- Existing packet is consumed (buffer becomes empty)
                error_out <= not buffer_full;
                assert buffer_full = '1';
                buffer_full <= '0';
            end if;
        end if;
    end process one_entry_buffer;

    -- Triggered at the start of a packet
    consume_buffer <= buffer_full when state = AWAIT_NEW_PACKET else '0';
    packet_start_strobe_out <= consume_buffer;

    -- Packet output as S/PDIF
    spdif_generator : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            case state is
                when RESET =>
                    -- Reset counters
                    bit_counter <= bit_counter_start;
                    state <= AWAIT_NEW_PACKET;
                    spdif_gen <= '1';

                when AWAIT_NEW_PACKET =>
                    bit_counter <= bit_counter_start;
                    shift_data <= buffer_data;
                    shift_header <= buffer_header;
                    parity <= '0';

                    if consume_buffer = '1' then
                        -- Start sending new packet
                        spdif_gen <= not spdif_gen;
                        state <= SEND_HEADER;
                    end if;

                when SEND_HEADER =>
                    if spdif_clock_strobe_in = '1' then
                        case shift_header (7 downto 6) is
                            when THREE =>
                                -- 2 more clocks with this output
                                shift_header (7 downto 6) <= TWO;
                            when TWO =>
                                -- 1 more clock with this output
                                shift_header (7 downto 6) <= ONE;
                            when others => 
                                -- 0 more clocks with this output (i.e. change)
                                if shift_header (5 downto 4) = ZERO then
                                    -- End of header, send the actual data next
                                    state <= SEND_DATA;
                                end if;
                                shift_header (7 downto 2) <= shift_header (5 downto 0);
                                shift_header (1 downto 0) <= ZERO;
                                spdif_gen <= not spdif_gen;
                        end case;
                    end if;

                when SEND_DATA =>
                    if spdif_clock_strobe_in = '1' then
                        if shift_data (first_data_bit) = '1' then
                            -- bit 1: generate two pulses of length 1
                            spdif_gen <= not spdif_gen;
                            state <= SEND_ONE_PULSE;
                        else
                            -- bit 0: generate one pulse of length 2
                            spdif_gen <= not spdif_gen;
                            state <= SEND_NO_PULSE;
                        end if;

                        -- Next bit
                        shift_data (last_data_bit - 1 downto first_data_bit) <=
                                shift_data (last_data_bit downto first_data_bit + 1);
                        shift_data (last_data_bit) <= '0';
                        bit_counter <= bit_counter - 1;

                        -- Track parity and load it
                        parity <= parity xor shift_data (first_data_bit);
                        if bit_counter = 1 then
                            shift_data (first_data_bit) <= parity xor shift_data (first_data_bit);
                        end if;
                    end if;

                when SEND_ONE_PULSE | SEND_NO_PULSE =>
                    if spdif_clock_strobe_in = '1' then
                        if state = SEND_ONE_PULSE then
                            spdif_gen <= not spdif_gen;
                        end if;
                        if bit_counter = 0 then
                            state <= AWAIT_NEW_PACKET;
                        else
                            state <= SEND_DATA;
                        end if;
                    end if;
            end case;

            if sync_in = '0' then
                state <= RESET;
            end if;
        end if;
    end process;

    -- S/PDIF data output
    data_out <= spdif_gen;

end structural;
