
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
    constant first_data_bit    : Natural := 4;
    constant last_data_bit     : Natural := 30;
    constant subcode_bit       : Natural := 30;
    constant user_bit          : Natural := 29;
    constant validity_bit      : Natural := 28;

    -- types
    type t_header_type is (HEADER_B, HEADER_W, HEADER_M);
    subtype t_bit_counter is Natural range 0 to 127;
    subtype t_per_channel is std_logic_vector (1 downto 0);
    subtype t_data is std_logic_vector (last_data_bit downto first_data_bit);
    type t_per_channel_header is array (Natural range 0 to 1) of t_header_type;
    type t_per_channel_data is array (Natural range 0 to 1) of t_data;

    -- subcode output
    constant b_interval     : Natural := 192;
    subtype t_subcode_counter is Natural range 0 to b_interval;

    -- Registers
    signal parity           : std_logic := '0';
    signal consume_buffer   : t_per_channel := (others => '0');
    signal buffer_full      : t_per_channel := (others => '0');
    signal bit_counter      : t_bit_counter := 0;
    signal transition       : std_logic := '0';
    signal spdif_gen        : std_logic := '1';
    signal subcode_counter  : t_subcode_counter := 0;
    signal buffer_overflow_error : t_per_channel := (others => '0');
    signal buffer_underflow_error : std_logic := '0';
    signal buffer_data      : t_per_channel_data := (others => (others => '0'));
    signal buffer_header    : t_per_channel_header := (others => HEADER_M);
    signal shift_data       : t_data := (others => '0');
    signal header_type      : t_header_type := HEADER_M;
    signal packet_enable    : std_logic := '0';

    -- Signals
    signal strobe_in        : t_per_channel := (others => '0');

begin

    error_out <= buffer_overflow_error (0) or buffer_overflow_error (1) or buffer_underflow_error;

    subcodes_and_Enable : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            if sync_in = '0' then
                -- Reset
                subcode_counter <= 0;
                packet_enable <= '0';

            else
                if left_strobe_in = '1' then
                    packet_enable <= '1';
                end if;
                if right_strobe_in = '1' then
                    if packet_enable = '0' then
                        subcode_counter <= 0;
                    elsif subcode_counter = b_interval then
                        subcode_counter <= 0;
                    else
                        subcode_counter <= subcode_counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process subcodes_and_enable;

    strobe_in (0) <= left_strobe_in;
    strobe_in (1) <= right_strobe_in;

    input_buffer : for channel in 0 to 1 generate
    begin
        -- Data input (single entry buffers)
        one_entry_buffer : process (clock_in)
            variable l : line;
        begin
            if clock_in'event and clock_in = '1' then
                buffer_overflow_error (channel) <= '0';

                if sync_in = '0' then
                    -- Reset
                    buffer_full (channel) <= '0';

                elsif strobe_in (channel) = '1' then
                    -- New packet arrives - this is the last opportunity to consume the previous buffer entry
                    if (buffer_full (channel) and packet_enable and not consume_buffer (channel)) = '1' then
                        write (l, String'("new packet while buffer full.. bit counter = "));
                        write (l, bit_counter);
                        write (l, String'(" data = "));
                        write (l, to_integer (unsigned (shift_data)));
                        writeline (output, l);
                        buffer_overflow_error (channel) <= '1';
                        assert False;
                    end if;
                    buffer_full (channel) <= '1';

                    -- Copy the data into the buffer
                    buffer_data (channel) <= data_in (last_data_bit downto first_data_bit);

                    -- Generate B/M header
                    if channel = 0 then
                        if subcode_counter = 0 then
                            buffer_header (channel) <= HEADER_B;
                        else
                            buffer_header (channel) <= HEADER_M;
                        end if;
                    else
                        buffer_header (channel) <= HEADER_W;
                    end if;

                    -- See https://www.minidisc.org/manuals/an22.pdf for description of subcode bits
                    -- They repeat periodically, beginning with a B packet, which is sent every b_interval.
                    case subcode_counter is
                        when 2 =>
                            buffer_data (channel) (subcode_bit) <= '1'; -- copy
                        when 13 =>
                            buffer_data (channel) (subcode_bit) <= '1'; -- category 0x02 - PCM encoder/decoder
                        when 3 =>
                            buffer_data (channel) (subcode_bit) <= preemph_in; -- DAC instructed to undo 15/50 preemphasis
                        when others =>
                            buffer_data (channel) (subcode_bit) <= '0';
                    end case;
                    buffer_data (channel) (validity_bit) <= '0'; -- can be D/A converted
                    buffer_data (channel) (user_bit) <= '0';

                elsif consume_buffer (channel) = '1' then
                    -- Existing packet is consumed (buffer becomes empty)
                    assert buffer_full (channel) = '1';
                    buffer_full (channel) <= '0';
                end if;
            end if;
        end process one_entry_buffer;
    end generate input_buffer;

    -- Packet output as S/PDIF
    packet_generator : process (clock_in)
        variable l : line;
    begin
        if clock_in'event and clock_in = '1' then
            consume_buffer <= (others => '0');
            buffer_underflow_error <= '0';
            transition <= '0';

            if spdif_clock_strobe_in = '1' then
                bit_counter <= (bit_counter + 1) mod 128;
                case bit_counter mod 64 is
                    when 0 =>
                        -- start of the header
                        -- Header transitions occur in the following patterns
                        -- B: 3113  - transitions on 0,3,4,5,8
                        -- W: 3212  - transitions on 0,3,5,6,8
                        -- M: 3311  - transitions on 0,3,6,7,8
                        if packet_enable = '0' then
                            bit_counter <= 0;
                        else
                            transition <= '1';
                        end if;

                    when 1 =>
                        null;
                    when 2 =>
                        -- Final part of first THREE
                        null;

                    when 3 =>
                        -- Load the shift register and header type now
                        transition <= '1';
                        parity <= '0';
                        if (bit_counter / 64) = 0 then
                            -- Left
                            if buffer_full (0) = '1' then
                                consume_buffer (0) <= '1';
                                shift_data <= buffer_data (0);
                                header_type <= buffer_header (0);
                            else
                                buffer_underflow_error <= '1';
                            end if;
                        else
                            -- Right 
                            if buffer_full (1) = '1' then
                                consume_buffer (1) <= '1';
                                shift_data <= buffer_data (1);
                                header_type <= buffer_header (1);
                            else
                                buffer_underflow_error <= '1';
                            end if;
                        end if;


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
                        if (bit_counter mod 2) = 1 then
                            -- Second part of each bit
                            if shift_data (first_data_bit) = '1' then
                                -- bit 1: generate two pulses of length 1
                                transition <= '1';
                            else
                                -- bit 0: generate one pulse of length 2
                                null;
                            end if;
                            parity <= parity xor shift_data (first_data_bit);
                            shift_data (last_data_bit - 1 downto first_data_bit)
                                    <= shift_data (last_data_bit downto first_data_bit + 1);
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
            if packet_enable = '0' then
                spdif_gen <= '1';
            elsif transition = '1' then
                spdif_gen <= not spdif_gen;
            end if;
        end if;
    end process spdif_generator;

    -- sync out
    sync_out <= packet_enable;

    -- S/PDIF data output
    data_out <= spdif_gen;

end structural;
