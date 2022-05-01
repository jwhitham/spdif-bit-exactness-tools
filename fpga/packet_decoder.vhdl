
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity packet_decoder is
    port (
        pulse_length_in : in std_logic_vector (1 downto 0);
        data_out        : out std_logic;
        shift_out       : out std_logic;
        reset_out       : out std_logic;
        clock           : in std_logic
    );
end packet_decoder;

architecture structural of packet_decoder is

    subtype t_pulse_length is std_logic_vector (1 downto 0);
    constant ZERO           : t_pulse_length := "00";
    constant ONE            : t_pulse_length := "01";
    constant TWO            : t_pulse_length := "10";
    constant THREE          : t_pulse_length := "11";

    type t_sync_state is (NORMAL, SKIP, START, DESYNC,
                B_HEADER, B_MID, B_FOOTER,
                M_HEADER, M_MID, M_FOOTER,
                W_HEADER, W_MID, W_FOOTER);
    signal sync_state       : t_sync_state := DESYNC;

begin

    process (clock)
    begin
        if clock'event and clock = '1' then

            reset_out <= '0';
            shift_out <= '0';
            data_out <= '0';

            case sync_state is
                when NORMAL =>
                    case pulse_length_in is
                        when THREE =>
                            -- New packet begins
                            sync_state <= START;
                            reset_out <= '1';
                        when TWO =>
                            -- Ordinary data (0)
                            sync_state <= NORMAL;
                            shift_out <= '1';
                        when ONE =>
                            -- Ordinary data (1)
                            sync_state <= SKIP;
                            shift_out <= '1';
                            data_out <= '1';
                        when others =>
                            null;
                    end case;

                when SKIP =>
                    case pulse_length_in is
                        when THREE =>
                            -- New packet begins
                            sync_state <= START;
                            reset_out <= '1';
                        when TWO =>
                            -- Ordinary data (0)
                            sync_state <= NORMAL;
                            shift_out <= '1';
                        when ONE =>
                            -- Ordinary data (1) skipped
                            sync_state <= NORMAL;
                        when others =>
                            null;
                    end case;

                when START =>
                    case pulse_length_in is
                        when THREE =>
                            sync_state <= M_HEADER; -- 111000 received, 10 remaining, shift 0010
                            shift_out <= '1';
                        when TWO =>
                            sync_state <= W_HEADER; -- 11100 received, 100 remaining, shift 0100
                            shift_out <= '1';
                        when ONE =>
                            sync_state <= B_HEADER; -- 1110 received, 1000 remaining, shift 1000
                            shift_out <= '1';
                            data_out <= '1';
                        when others =>
                            null;
                    end case;

                when M_HEADER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 10
                        when ONE =>
                            sync_state <= M_MID; -- 0 remaining, shift 010
                            shift_out <= '1';
                        when others =>
                            null;
                    end case;

                when M_MID =>
                    sync_state <= M_FOOTER; -- 00 remaining, shift 10
                    data_out <= '1';
                    shift_out <= '1';
                
                when M_FOOTER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 0
                        when ONE =>
                            sync_state <= NORMAL; -- begin M packet, shift 0
                            shift_out <= '1';
                        when others =>
                            null;
                    end case;

                when W_HEADER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 100
                        when ONE =>
                            sync_state <= W_MID; -- 00 remaining, shift 100
                            shift_out <= '1';
                            data_out <= '1';
                        when others =>
                            null;
                    end case;

                when W_MID =>
                    sync_state <= W_FOOTER; -- 00 remaining, shift 00
                    shift_out <= '1';
                
                when W_FOOTER =>
                    case pulse_length_in is
                        when ONE | THREE =>
                            sync_state <= DESYNC; -- expected 00
                        when TWO =>
                            sync_state <= NORMAL; -- begin W packet, shift 0
                            shift_out <= '1';
                        when others =>
                            null;
                    end case;

                when B_HEADER =>
                    case pulse_length_in is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 1000
                        when ONE =>
                            sync_state <= B_MID; -- 000 remaining, shift 000
                            shift_out <= '1';
                        when others =>
                            null;
                    end case;

                when B_MID =>
                    sync_state <= B_FOOTER; -- 000 remaining, shift 00
                    shift_out <= '1';

                when B_FOOTER =>
                    case pulse_length_in is
                        when ONE | TWO =>
                            sync_state <= DESYNC; -- expected 000
                        when THREE =>
                            sync_state <= NORMAL; -- begin B packet, shift 00
                            shift_out <= '1';
                        when others =>
                            null;
                    end case;

                when DESYNC =>
                    case pulse_length_in is
                        when THREE =>
                            sync_state <= START;
                        when others =>
                            null;
                    end case;
            end case;
        end if;
    end process;

end structural;
