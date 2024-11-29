library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use debug_textio.all;

entity packet_decoder is
    generic (debug : Boolean := false);
    port (
        pulse_length_in : in std_logic_vector (1 downto 0);
        sync_in         : in std_logic;
        data_out        : out std_logic;
        shift_out       : out std_logic;
        start_out       : out std_logic;
        sync_out        : out std_logic;
        clock           : in std_logic
    );
end packet_decoder;

architecture structural of packet_decoder is

    subtype t_pulse_length is std_logic_vector (1 downto 0);
    constant ZERO           : t_pulse_length := "00";
    constant ONE            : t_pulse_length := "01";
    constant TWO            : t_pulse_length := "10";
    constant THREE          : t_pulse_length := "11";

    type t_sync_state is (NORMAL, SKIP, SYNC, DESYNC,
                B_HEADER, B_MID, B_FOOTER,
                M_HEADER, M_MID, M_FOOTER,
                W_HEADER, W_MID, W_FOOTER);
    signal sync_state       : t_sync_state := DESYNC;

    signal data        : std_logic := '0';
    signal shift       : std_logic := '0';
    signal start       : std_logic := '0';
    signal synced      : std_logic := '0';

begin

    data_out <= data;
    shift_out <= shift;
    start_out <= start;
    sync_out <= synced;

    process (clock)
        variable l : line;
    begin
        if clock'event and clock = '1' then

            data <= '0';
            shift <= '0';
            start <= '0';

            case sync_state is
                when NORMAL =>
                    case pulse_length_in is
                        when THREE =>
                            -- New packet begins
                            sync_state <= SYNC;
                        when TWO =>
                            -- Ordinary data (0)
                            sync_state <= NORMAL;
                            shift <= '1';
                            if debug then
                                write (l, String'("packet decoder: data 0"));
                                writeline (output, l);
                            end if;
                        when ONE =>
                            -- Ordinary data (1)
                            sync_state <= SKIP;
                            shift <= '1';
                            data <= '1';
                            synced <= '1';
                            if debug and synced = '0' then
                                write (l, String'("packet decoder: sync_out = '1'"));
                                writeline (output, l);
                            end if;
                            if debug then
                                write (l, String'("packet decoder: data 1"));
                                writeline (output, l);
                            end if;
                        when others =>
                            null;
                    end case;

                when SKIP =>
                    case pulse_length_in is
                        when THREE =>
                            -- New packet begins
                            sync_state <= SYNC;
                        when TWO =>
                            -- Not valid after 1
                            if debug then
                                write (l, String'("packet decoder: desync in data"));
                                writeline (output, l);
                            end if;
                            sync_state <= DESYNC;
                        when ONE =>
                            -- Ordinary data (1) skipped
                            sync_state <= NORMAL;
                        when others =>
                            null;
                    end case;

                when SYNC =>
                    case pulse_length_in is
                        when THREE =>
                            sync_state <= M_HEADER; -- 111000 received, 10 remaining, shift 0010
                            shift <= '1';
                            start <= '1';
                        when TWO =>
                            sync_state <= W_HEADER; -- 11100 received, 100 remaining, shift 0100
                            shift <= '1';
                            start <= '1';
                        when ONE =>
                            sync_state <= B_HEADER; -- 1110 received, 1000 remaining, shift 1000
                            shift <= '1';
                            data <= '1';
                            start <= '1';
                        when others =>
                            null;
                    end case;

                when M_HEADER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            if debug then
                                write (l, String'("packet decoder: desync M header"));
                                writeline (output, l);
                            end if;
                            sync_state <= DESYNC; -- expected 10
                        when ONE =>
                            sync_state <= M_MID; -- 0 remaining, shift 010
                            shift <= '1';
                        when others =>
                            null;
                    end case;

                when M_MID =>
                    sync_state <= M_FOOTER; -- 00 remaining, shift 10
                    data <= '1';
                    shift <= '1';
                
                when M_FOOTER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            if debug then
                                write (l, String'("packet decoder: desync M footer"));
                                writeline (output, l);
                            end if;
                            sync_state <= DESYNC; -- expected 0
                        when ONE =>
                            sync_state <= NORMAL; -- begin M packet, shift 0
                            shift <= '1';
                            if debug then
                                write (l, String'("packet decoder: M packet"));
                                writeline (output, l);
                            end if;
                        when others =>
                            null;
                    end case;

                when W_HEADER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            if debug then
                                write (l, String'("packet decoder: desync W header"));
                                writeline (output, l);
                            end if;
                            sync_state <= DESYNC; -- expected 100
                        when ONE =>
                            sync_state <= W_MID; -- 00 remaining, shift 100
                            shift <= '1';
                            data <= '1';
                        when others =>
                            null;
                    end case;

                when W_MID =>
                    sync_state <= W_FOOTER; -- 00 remaining, shift 00
                    shift <= '1';
                
                when W_FOOTER =>
                    case pulse_length_in is
                        when ONE | THREE =>
                            if debug then
                                write (l, String'("packet decoder: desync W footer"));
                                writeline (output, l);
                            end if;
                            sync_state <= DESYNC; -- expected 00
                        when TWO =>
                            sync_state <= NORMAL; -- begin W packet, shift 0
                            shift <= '1';
                            if debug then
                                write (l, String'("packet decoder: W packet"));
                                writeline (output, l);
                            end if;
                        when others =>
                            null;
                    end case;

                when B_HEADER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            if debug then
                                write (l, String'("packet decoder: desync B header"));
                                writeline (output, l);
                            end if;
                            sync_state <= DESYNC; -- expected 1000
                        when ONE =>
                            sync_state <= B_MID; -- 000 remaining, shift 000
                            shift <= '1';
                        when others =>
                            null;
                    end case;

                when B_MID =>
                    sync_state <= B_FOOTER; -- 000 remaining, shift 00
                    shift <= '1';

                when B_FOOTER =>
                    case pulse_length_in is
                        when ONE | TWO =>
                            if debug then
                                write (l, String'("packet decoder: desync B footer"));
                                writeline (output, l);
                            end if;
                            sync_state <= DESYNC; -- expected 000
                        when THREE =>
                            sync_state <= NORMAL; -- begin B packet, shift 0
                            shift <= '1';
                            if debug then
                                write (l, String'("packet decoder: B packet"));
                                writeline (output, l);
                            end if;
                        when others =>
                            null;
                    end case;

                when DESYNC =>
                    case pulse_length_in is
                        when THREE =>
                            if debug then
                                write (l, String'("packet decoder: possible resync"));
                                writeline (output, l);
                            end if;
                            sync_state <= SYNC;
                        when others =>
                            null;
                    end case;
                    synced <= '0';
            end case;

            if sync_in = '0' then
                -- held in reset
                sync_state <= NORMAL;
                shift <= '0';
                data <= '0';
                synced <= '0';
            end if;
        end if;
    end process;

end structural;
