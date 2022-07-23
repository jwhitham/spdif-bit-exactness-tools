
library ieee;
use ieee.std_logic_1164.all;

entity channel_encoder is
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
        clock                   : in std_logic
    );
end channel_encoder;

architecture structural of channel_encoder is

    -- subcode output
    constant b_interval     : Natural := 192;
    subtype t_subcode_counter is Natural range 0 to b_interval;

    -- data output
    subtype t_bit_counter is Natural range 0 to 31;
    constant first_data_bit    : t_bit_counter := 4;
    constant last_data_bit     : t_bit_counter := 31;
    constant bit_counter_start : t_bit_counter := 1 + last_data_bit - first_data_bit;
    constant subcode_bit       : t_bit_counter := 30;
    constant user_bit          : t_bit_counter := 29;
    constant validity_bit      : t_bit_counter := 28;

    -- header output
    subtype t_header is std_logic_vector (7 downto 0);
    subtype t_header_pulse is std_logic_vector (1 downto 0);
    constant THREE             : t_header_pulse := "11";
    constant TWO               : t_header_pulse := "10";
    constant ONE               : t_header_pulse := "01";
    constant ZERO              : t_header_pulse := "00";

    -- state
    type t_state is (AWAIT_DATA, AWAIT_FIRST_CLOCK,
                     SEND_HEADER, SEND_DATA,
                     SEND_ONE_PULSE, SEND_NO_PULSE);

    -- Registers
    signal parity           : std_logic := '0';
    signal data             : std_logic_vector (last_data_bit - 1 downto first_data_bit) := (others => '0');
    signal subcode_counter  : t_subcode_counter := 0;
    signal bit_counter      : t_bit_counter := 0;
    signal header           : t_header := (others => '0');
    signal state            : t_state := RESET;

begin

    -- error when a clock strobe arrives when we're not ready
    error_out <= '1' when state = AWAIT_DATA and spdif_clock_strobe_in = '1' else '0';

    -- Packet starts:
    packet_start_strobe_out <= '1' when state = AWAIT_DATA and (left_strobe_in or right_strobe_in = '1') else '0';

    -- S/PDIF data output
    data_out <= spdif_gen;

    process (clock)
    begin
        if clock_in'event and clock_in = '1' then
            -- New packet
            case state is
                when RESET =>
                    -- Reset counters
                    bit_counter <= bit_counter_start;
                    subcode_counter <= 0;
                    sync_out <= '0';
                    state <= AWAIT_DATA;
                    spdif_gen <= '1';

                when AWAIT_DATA =>
                    -- not ready for clocks
                    assert spdif_clock_strobe_in = '0';

                    if left_strobe_in = '1' or right_strobe_in = '1' then
                        -- Start of a new packet
                        bit_counter <= bit_counter_start;
                        data <= data_in (last_data_bit - 1 downto first_data_bit);

                        -- Generate B/M header
                        -- We will output pulses of the following lengths
                        -- B: 3113
                        -- W: 3212
                        -- M: 3311
                        if left_strobe_in = '1' then
                            if subcode_counter = 0 or subcode_counter = b_interval then
                                header <= THREE & ONE & ONE & THREE;
                                subcode_counter <= 1;
                                sync_out <= '1';
                            else
                                header <= THREE & TWO & ONE & TWO;
                                subcode_counter <= subcode_counter + 1;
                            end if;
                        else
                            header <= THREE & THREE & ONE & ONE;
                        end if;

                        -- See https://www.minidisc.org/manuals/an22.pdf for description of subcode bits
                        -- They repeat periodically, beginning with a B packet, which is sent every b_interval.
                        case subcode_counter is
                            when 2 =>
                                data (subcode_bit) <= '1'; -- copy
                            when 13 =>
                                data (subcode_bit) <= '1'; -- category 0x02 - PCM encoder/decoder
                            when 3 =>
                                data (subcode_bit) <= preemph_in; -- DAC instructed to undo 15/50 preemphasis
                            when others =>
                                data (subcode_bit) <= '0';
                        end case;
                        data (validity_bit) <= '0'; -- can be D/A converted
                        data (user_bit) <= '0';

                        state <= AWAIT_FIRST_CLOCK;
                    end if;

                when AWAIT_FIRST_CLOCK =>
                    if spdif_clock_strobe_in = '1' then
                        spdif_gen <= not spdif_gen;
                        state <= SEND_HEADER;
                    end if;

                when SEND_HEADER =>
                    if spdif_clock_strobe_in = '1' then
                        case header (7 downto 6) is
                            when THREE =>
                                -- 2 more clocks with this output
                                header (7 downto 6) <= TWO;
                            when TWO =>
                                -- 1 more clock with this output
                                header (7 downto 6) <= ONE;
                            when others => 
                                -- 0 more clocks with this output (i.e. change)
                                if header (5 downto 4) = ZERO then
                                    -- End of header, send the actual data next
                                    state <= SEND_DATA;
                                end if;
                                header (7 downto 2) <= header (5 downto 0);
                                header (1 downto 0) <= ZERO;
                                spdif_gen <= not spdif_gen;
                        end case;
                    end if;

                when SEND_DATA =>
                    if spdif_clock_strobe_in = '1' then
                        if data (4) = '1' then
                            -- bit 1: generate two pulses of length 1
                            spdif_gen <= not spdif_gen;
                            state <= SEND_ONE_PULSE;
                        else
                            -- bit 0: generate one pulse of length 2
                            spdif_gen <= not spdif_gen;
                            state <= SEND_NO_PULSE;
                        end if;

                        -- Next bit
                        data (29 downto 4) <= data (30 downto 5);
                        bit_counter <= bit_counter - 1;

                        -- Track parity and load it
                        parity <= parity xor data (4);
                        if bit_counter = 1 then
                            data (4) <= parity xor data (4);
                        end if;
                    end if;

                when SEND_ONE_PULSE | SEND_NO_PULSE =>
                    if spdif_clock_strobe_in = '1' then
                        if state = SEND_ONE_PULSE then
                            spdif_gen <= not spdif_gen;
                        end if;
                        if bit_counter = 0 then
                            state <= AWAIT_DATA;
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

end structural;
