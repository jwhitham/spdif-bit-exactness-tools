
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
                     SEND_HEADER,
                     SEND_DATA, DATA_CYCLE_2);

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
    signal buffer_error     : std_logic := '0';
    signal clock_error      : std_logic := '0';
    signal pulse_length_out : std_logic_vector (1 downto 0) := "00";
    signal count            : Natural := 0;

    -- Signals
    signal consume_buffer   : std_logic := '0';

begin

    error_out <= buffer_error or clock_error;

    -- Data input (single entry buffer)
    one_entry_buffer : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            buffer_error <= '0';

            if sync_in = '0' then
                -- Reset
                buffer_full <= '0';
                subcode_counter <= 0;
                sync_out <= '0';

            elsif left_strobe_in = '1' or right_strobe_in = '1' then
                -- New packet arrives - this is the last opportunity to consume the previous buffer entry
                buffer_error <= '0';
                if (buffer_full and not consume_buffer) = '1' then
                    write (l, String'("new packet while buffer full.. count = "));
                    write (l, count);
                    write (l, String'(" bit counter = "));
                    write (l, bit_counter);
                    write (l, String'(" data = "));
                    write (l, to_integer (unsigned (shift_data)));
                    write (l, String'(" state = "));
                    write (l, t_state'Image (state));
                    writeline (output, l);
                    buffer_error <= '1';
                    assert False;
                end if;
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
                        if debug then
                            write (l, String'("new packet: left B"));
                            writeline (output, l);
                        end if;
                    else
                        buffer_header <= THREE & THREE & ONE & ONE;
                        subcode_counter <= subcode_counter + 1;
                        if debug then
                            write (l, String'("new packet: left M"));
                            writeline (output, l);
                        end if;
                    end if;
                else
                    buffer_header <= THREE & TWO & ONE & TWO;
                    if debug then
                        write (l, String'("new packet: right W"));
                        writeline (output, l);
                    end if;
                end if;

                -- There is no transition at the start of the header. The actual
                -- timing for the first pulse is just two S/PDIF strobes, not three,
                -- because the first pulse really begins at the end of the previous packet.
                buffer_header (7 downto 6) <= TWO;

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
                buffer_error <= not buffer_full;
                assert buffer_full = '1';
                buffer_full <= '0';
            end if;
        end if;
    end process one_entry_buffer;

    -- Triggered at the start of a packet
    consume_buffer <= buffer_full when state = AWAIT_NEW_PACKET else '0';

    -- Packet output as S/PDIF
    spdif_generator : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            clock_error <= '0';

            case state is
                when RESET =>
                    -- Reset counters
                    bit_counter <= bit_counter_start;
                    spdif_gen <= '1';
                    count <= 99;
                    state <= AWAIT_NEW_PACKET;

                when AWAIT_NEW_PACKET =>
                    bit_counter <= bit_counter_start;
                    shift_data <= buffer_data;
                    shift_header <= buffer_header;
                    parity <= '0';

                    -- clock pulses at this time will be ignored

                    if consume_buffer = '1' then
                        -- Start sending new packet
                        state <= SEND_HEADER;
                        count <= 1;
                        if debug then
                            write (l, String'("start: "));
                            for i in first_data_bit to last_data_bit loop
                                if buffer_data (i) = '1' then
                                    write (l, String'("1"));
                                else
                                    write (l, String'("0"));
                                end if;
                            end loop;
                            writeline (output, l);
                            write (l, String'("at the beginning of the packet, count is "));
                            write (l, count);
                            writeline (output, l);
                        end if;
                        assert (count = 64) or (count = 99);
                    end if;

                when SEND_HEADER =>
                    if shift_header (7 downto 6) = ZERO then
                        -- finished sending header
                        state <= SEND_DATA;
                        assert spdif_clock_strobe_in = '0';
                        clock_error <= spdif_clock_strobe_in;
                        if debug then
                            write (l, String'("at the end of the header , count is "));
                            write (l, count);
                            writeline (output, l);
                        end if;
                        assert count = 8;

                    elsif spdif_clock_strobe_in = '1' then
                        -- send next header clock pulse
                        case shift_header (7 downto 6) is
                            when THREE =>
                                if debug then
                                    write (l, String'("header hold"));
                                    writeline (output, l);
                                end if;
                                shift_header (7 downto 6) <= TWO;
                            when TWO =>
                                if debug then
                                    write (l, String'("header hold"));
                                    writeline (output, l);
                                end if;
                                shift_header (7 downto 6) <= ONE;
                            when others =>
                                spdif_gen <= not spdif_gen;
                                if debug then
                                    write (l, String'("header flip"));
                                    writeline (output, l);
                                end if;
                                shift_header (7 downto 2) <= shift_header (5 downto 0);
                                shift_header (1 downto 0) <= ZERO;
                        end case;
                        count <= count + 1;
                    end if;

                when SEND_DATA =>
                    if bit_counter = 0 then
                        -- finished sending data
                        state <= AWAIT_NEW_PACKET;
                        assert spdif_clock_strobe_in = '0';
                        clock_error <= spdif_clock_strobe_in;
                        if debug then
                            write (l, String'("at the end of the packet, count is "));
                            write (l, count);
                            writeline (output, l);
                        end if;
                        assert count = 64;

                    elsif spdif_clock_strobe_in = '1' then
                        -- send next data bit
                        state <= DATA_CYCLE_2;

                        if shift_data (first_data_bit) = '1' then
                            -- bit 1: generate two pulses of length 1
                            spdif_gen <= not spdif_gen;
                            if debug then
                                write (l, String'("data 1 bit counter "));
                                write (l, bit_counter);
                                writeline (output, l);
                            end if;
                        else
                            -- bit 0: generate one pulse of length 2
                            if debug then
                                write (l, String'("data 0 bit counter "));
                                write (l, bit_counter);
                                writeline (output, l);
                            end if;
                        end if;

                        -- Shift next bit
                        shift_data (last_data_bit - 1 downto first_data_bit) <=
                                shift_data (last_data_bit downto first_data_bit + 1);
                        shift_data (last_data_bit) <= '0';
                        bit_counter <= bit_counter - 1;

                        -- Track parity
                        parity <= parity xor shift_data (first_data_bit);
                        if bit_counter = 2 then
                            -- Update the parity in the output
                            shift_data (first_data_bit) <= parity xor shift_data (first_data_bit);
                            if debug then
                                write (l, String'("calculate parity: "));
                                if (parity xor shift_data (first_data_bit)) = '1' then
                                    write (l, String'("1"));
                                else
                                    write (l, String'("0"));
                                end if;
                                writeline (output, l);
                            end if;
                        end if;
                        count <= count + 1;
                    end if;

                when DATA_CYCLE_2 =>
                    if spdif_clock_strobe_in = '1' then
                        spdif_gen <= not spdif_gen;
                        state <= SEND_DATA;
                        count <= count + 1;
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
