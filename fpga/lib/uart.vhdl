

library ieee;
use ieee.std_logic_1164.all;

entity uart is
    generic (
        clock_frequency : Real;
        baud_rate       : Real);
    port (
        data_in       : in std_logic_vector (7 downto 0);
        strobe_in     : in std_logic;
        data_out      : out std_logic_vector (7 downto 0) := (others => '0');
        strobe_out    : out std_logic := '0';
        ready_out     : out std_logic := '0';
        serial_in     : in std_logic;
        serial_out    : out std_logic := '0';
        clock_in      : in std_logic);
end uart;

architecture structural of uart is

    constant baud_divisor_max  : Natural :=
            Natural (clock_frequency / (baud_rate * 16.0)) - 1;
    subtype t_baud_divisor is Natural range 0 to baud_divisor_max;

    signal baud_divisor       : t_baud_divisor := 0;
    signal baud_div_16        : std_logic := '0';

begin
    generate_clock_enable : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            baud_div_16 <= '0';
            if baud_divisor = baud_divisor_max then
                baud_divisor <= 0;
                baud_div_16 <= '1';
            else
                baud_divisor <= baud_divisor + 1;
            end if;
        end if;
    end process generate_clock_enable;

    serial_input : block
        signal serial_in_reg : std_logic := '0';
        signal data          : std_logic_vector (7 downto 0) := (others => '0');

        subtype t_receive_state is Natural range 16#000# to 16#0ff#;
        signal receive_state : t_receive_state := 0;
    begin
        data_out <= data;

        process (clock_in)
        begin
            if clock_in'event and clock_in = '1' then
                strobe_out <= '0';
                serial_in_reg <= serial_in;

                if baud_div_16 = '1' then
                    if receive_state /= 0 or serial_in_reg = '1' then
                        -- receiving bits
                        receive_state <= receive_state + 1;
                        case receive_state is
                            when 16#008# =>
                                -- start bit: should be 1. If not, discard packet and reset
                                if serial_in_reg /= '1' then
                                    receive_state <= 0;
                                end if;
                            when 16#018# | 16#028# | 16#038# | 16#048#
                                    | 16#058# | 16#068# | 16#078# | 16#088# =>
                                -- data bit: shift into data register
                                data (7 downto 1) <= data (6 downto 0);
                                data (0) <= serial_in_reg;
                            when 16#098# =>
                                -- stop bit: should be 0. If not, discard packet and reset.
                                if serial_in_reg = '0' then
                                    strobe_out <= '1';
                                end if;
                                receive_state <= 0;
                            when others =>
                                null;
                        end case;
                    end if;
                end if;
            end if;
        end process;
    end block serial_input;

    serial_output : block
        signal data          : std_logic_vector (7 downto 0) := (others => '0');

        subtype t_send_state is Natural range 16#000# to 16#0ff#;
        signal send_state   : t_send_state := 0;
    begin
        process (clock_in)
        begin
            if clock_in'event and clock_in = '1' then

                ready_out <= '0';

                if send_state = 0 then
                    if strobe_in = '1' then
                        -- begin sending
                        data <= data_in;
                        send_state <= 1;
                    else
                        -- ready to send
                        ready_out <= '1';
                    end if;
                    serial_out <= '0';
                else
                    if baud_div_16 = '1' then
                        -- send data
                        send_state <= send_state + 1;
                        case send_state is
                            when 16#001# =>
                                -- start bit
                                serial_out <= '1';
                            when 16#011# | 16#021# | 16#031# | 16#041#
                                    | 16#051# | 16#061# | 16#071# | 16#081# =>
                                -- data bit
                                serial_out <= data (7);
                                data (7 downto 1) <= data (6 downto 0);
                            when 16#091# =>
                                -- stop bit
                                serial_out <= '0';
                            when 16#0a1# =>
                                -- finished
                                send_state <= 0;
                            when others =>
                                null;
                        end case;
                    end if;
                end if;
            end if;
        end process;
    end block serial_output;

end architecture structural;
