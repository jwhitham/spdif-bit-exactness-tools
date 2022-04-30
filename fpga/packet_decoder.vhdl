
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity packet_decoder is
    port (
        single_pulse    : in std_logic;
        double_pulse    : in std_logic;
        triple_pulse    : in std_logic;
        data_out        : out std_logic_vector (31 downto 0);
        valid_out       : out std_logic;
        clock           : in std_logic
    );
end packet_decoder;

architecture structural of packet_decoder is

    type t_pulse_length is (ZERO, ONE, TWO, THREE);
    signal pulse_length     : t_pulse_length := ZERO;

    type t_sync_state is (NORMAL, SKIP, START, DESYNC,
                B_HEADER, B_FOOTER, M_HEADER, M_FOOTER, W_HEADER, W_FOOTER);
    signal sync_state       : t_sync_state := DESYNC;

    signal data             : std_logic_vector (data_out'Left downto 0) := (others => '0');
begin

    data_out <= data;

    -- Decode the pulse length into an enum
    process (single_pulse, double_pulse, triple_pulse)
    begin
        if triple_pulse = '1' then
            pulse_length <= THREE;

        elsif double_pulse = '1' then
            pulse_length <= TWO;

        elsif single_pulse = '1' then
            pulse_length <= ONE;

        else
            pulse_length <= ZERO;
        end if;
    end process;

    process (clock)
    begin
        if clock'event and clock = '1' then

            valid_out <= '0';
            case sync_state is
                when NORMAL =>
                    case pulse_length is
                        when THREE =>
                            sync_state <= START;
                            valid_out <= '1';
                        when TWO =>
                            -- Ordinary data (0)
                            data (data'Left downto 1) <= data (data'Left - 1 downto 0);
                            data (0) <= '0';
                        when ONE =>
                            -- Ordinary data (1)
                            data (data'Left downto 1) <= data (data'Left - 1 downto 0);
                            data (0) <= '1';
                            sync_state <= SKIP;
                        when ZERO =>
                            null;
                    end case;

                when SKIP =>
                    case pulse_length is
                        when THREE =>
                            sync_state <= START;
                            valid_out <= '1';
                        when TWO =>
                            -- Ordinary data (0)
                            data (data'Left downto 1) <= data (data'Left - 1 downto 0);
                            data (0) <= '0';
                            sync_state <= NORMAL;
                        when ONE =>
                            -- Ordinary data (1) skipped
                            sync_state <= NORMAL;
                        when ZERO =>
                            null;
                    end case;

                when START =>
                    data <= (others => '0');
                    case pulse_length is
                        when THREE =>
                            sync_state <= M_HEADER; -- 111000 received, 10 remaining
                        when TWO =>
                            sync_state <= W_HEADER; -- 11100 received, 100 remaining
                        when ONE =>
                            sync_state <= B_HEADER; -- 1110 received, 1000 remaining
                        when ZERO =>
                            null;
                    end case;

                when M_HEADER =>
                    case pulse_length is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 10
                        when ONE =>
                            sync_state <= M_FOOTER; -- 0 remaining
                        when ZERO =>
                            null;
                    end case;

                when W_HEADER =>
                    case pulse_length is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 100
                        when ONE =>
                            sync_state <= W_FOOTER; -- 00 remaining
                        when ZERO =>
                            null;
                    end case;
                
                when B_HEADER =>
                    case pulse_length is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 1000
                        when ONE =>
                            sync_state <= W_FOOTER; -- 000 remaining
                        when ZERO =>
                            null;
                    end case;

                when M_FOOTER =>
                    case pulse_length is
                        when TWO | THREE =>
                            sync_state <= DESYNC; -- expected 0
                        when ONE =>
                            sync_state <= NORMAL; -- begin M packet
                            data (3 downto 0) <= "0010";
                        when ZERO =>
                            null;
                    end case;

                when W_FOOTER =>
                    case pulse_length is
                        when ONE | THREE =>
                            sync_state <= DESYNC; -- expected 00
                        when TWO =>
                            sync_state <= NORMAL; -- begin W packet
                            data (3 downto 0) <= "0100";
                        when ZERO =>
                            null;
                    end case;

                when B_FOOTER =>
                    case pulse_length is
                        when ONE | TWO =>
                            sync_state <= DESYNC; -- expected 000
                        when THREE =>
                            sync_state <= NORMAL; -- begin B packet
                            data (3 downto 0) <= "1000";
                        when ZERO =>
                            null;
                    end case;

                when DESYNC =>
                    case pulse_length is
                        when ONE | TWO | ZERO =>
                            null;
                        when THREE =>
                            sync_state <= START;
                    end case;
            end case;
        end if;
    end process;

end structural;
