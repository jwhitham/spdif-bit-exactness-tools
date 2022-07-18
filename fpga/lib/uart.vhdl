

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
        reset_in      : in std_logic;
        serial_in     : in std_logic;
        serial_out    : out std_logic := '0';
        clock_in      : in std_logic);
end uart;

architecture structural of uart is

    signal baud_div_16        : std_logic := '0';

begin
    generate_clock_enable : entity pulse_gen
        generic map (
            clock_frequency => clock_frequency,
            pulse_frequency => baud_rate * 16.0)
        port map (
            pulse_out => baud_div_16,
            clock_in => clock_in);

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
                    if receive_state /= 0 or serial_in_reg = '0' then
                        -- receiving bits
                        receive_state <= receive_state + 1;
                        case receive_state is
                            when 16#008# =>
                                -- start bit: should be 0. If not, discard packet and reset
                                if serial_in_reg /= '0' then
                                    receive_state <= 0;
                                end if;
                            when 16#018# | 16#028# | 16#038# | 16#048#
                                    | 16#058# | 16#068# | 16#078# | 16#088# =>
                                -- data bit: shift into data register
                                data (6 downto 0) <= data (7 downto 1);
                                data (7) <= serial_in_reg;
                            when 16#098# =>
                                -- stop bit: should be 1. If not, discard packet and reset.
                                if serial_in_reg = '1' then
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

                if reset_in = '1' then
                    -- send a break (hold serial out low)
                    serial_out <= '0';
                    send_state <= 0;
                    
                elsif send_state = 0 then
                    if strobe_in = '1' then
                        -- begin sending
                        data <= data_in;
                        send_state <= 1;
                    else
                        -- ready to send
                        ready_out <= '1';
                    end if;
                    serial_out <= '1';
                else
                    if baud_div_16 = '1' then
                        -- send data
                        send_state <= send_state + 1;
                        case send_state is
                            when 16#001# =>
                                -- start bit
                                serial_out <= '0';
                            when 16#011# | 16#021# | 16#031# | 16#041#
                                    | 16#051# | 16#061# | 16#071# | 16#081# =>
                                -- data bit
                                serial_out <= data (0);
                                data (6 downto 0) <= data (7 downto 1);
                            when 16#091# =>
                                -- stop bit
                                serial_out <= '1';
                            when 16#0a0# =>
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
