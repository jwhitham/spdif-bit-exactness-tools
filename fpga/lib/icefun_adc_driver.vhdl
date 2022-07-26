
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity icefun_adc_driver is
    generic (clock_frequency : Real);
    port (
        clock_in            : in std_logic;
        reset_in            : in std_logic;
        pulse_100hz_in      : in std_logic;
        tx_to_pic           : out std_logic := '0';
        rx_from_pic         : in std_logic;
        enable_poll_in      : in std_logic;
        ready_out           : out std_logic := '0';
        error_out           : out std_logic := '0';
        adjust_1_out        : out std_logic_vector (9 downto 0) := (others => '0');
        adjust_2_out        : out std_logic_vector (9 downto 0) := (others => '0');
        adjust_1a_p52       : out std_logic := '0';
        adjust_1b_p50       : out std_logic := '0';
        adjust_2a_p47       : out std_logic := '0';
        adjust_2b_p45       : out std_logic := '0');
end icefun_adc_driver;

architecture structural of icefun_adc_driver is

    type t_state is (RESET, WAIT_FIRST_REQUEST,
                     SEND_REQUEST_1, WAIT_REPLY_1, WAIT_REPLY_2,
                     SEND_REQUEST_2, WAIT_REPLY_3, WAIT_REPLY_4,
                     TIMEOUT_ERROR, WAIT_START);

    -- Countdown implements a delay of ~20ms
    -- This is the timeout for receiving data from the PIC and also
    -- the initial delay for the first request.
    constant max_countdown  : Natural := 2;

    subtype t_countdown is Natural range 0 to max_countdown;

    -- Registers
    signal countdown        : t_countdown := max_countdown;
    signal state            : t_state := RESET;
    signal adjust_1_tmp     : std_logic_vector (9 downto 0) := (others => '0');
    signal adjust_2_tmp     : std_logic_vector (9 downto 0) := (others => '0');

    -- Signals
    signal data_from_pic    : std_logic_vector (7 downto 0);
    signal data_to_pic      : std_logic_vector (7 downto 0);
    signal strobe_from_pic  : std_logic;
    signal strobe_to_pic    : std_logic;
    signal measure_enable   : std_logic := '0';

    constant uart_reset     : std_logic := '0';
begin

    -- Each analogue input is connected to the middle of a potentiometer
    -- with both sides (a and b) connected to FPGA pins. This allows
    -- the current through the potentiometer to be turned off
    -- when not in use. b side is always LOW, a is HIGH when used.
    adjust_1a_p52 <= measure_enable;
    adjust_1b_p50 <= '0';
    adjust_2a_p47 <= measure_enable;
    adjust_2b_p45 <= '0';

    -- This state machine controls sending the requests to the PIC.
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if pulse_100hz_in = '1' and countdown /= 0 then
                countdown <= countdown - 1;
            end if;
            case state is
                when RESET =>
                    -- Initial state.
                    countdown <= max_countdown;
                    state <= WAIT_FIRST_REQUEST;

                when WAIT_FIRST_REQUEST =>
                    -- Don't generate the first request immediately. Wait for the timeout to expire.
                    if countdown = 0 then
                        state <= SEND_REQUEST_1;
                    end if;

                when SEND_REQUEST_1 =>
                    -- Send a request for data from ADC 1
                    countdown <= max_countdown;
                    state <= WAIT_REPLY_1;

                when WAIT_REPLY_1 =>
                    -- Wait for a reply from ADC 1
                    if strobe_from_pic = '1' then
                        state <= WAIT_REPLY_2;
                        adjust_1_tmp (7 downto 0) <= data_from_pic;
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    end if;

                when WAIT_REPLY_2 =>
                    -- Wait for part 2 of the reply from ADC 1
                    if strobe_from_pic = '1' then
                        state <= SEND_REQUEST_2;
                        adjust_1_tmp (9 downto 8) <= data_from_pic (1 downto 0);
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    end if;

                when SEND_REQUEST_2 =>
                    -- Send a request for data from ADC 2
                    countdown <= max_countdown;
                    state <= WAIT_REPLY_3;

                when WAIT_REPLY_3 =>
                    -- Wait for a reply from ADC 2
                    if strobe_from_pic = '1' then
                        state <= WAIT_REPLY_4;
                        adjust_2_tmp (7 downto 0) <= data_from_pic;
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    end if;

                when WAIT_REPLY_4 =>
                    -- Wait for part 2 of the reply from ADC 2
                    if strobe_from_pic = '1' then
                        state <= WAIT_START;
                        adjust_2_tmp (9 downto 8) <= data_from_pic (1 downto 0);
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    end if;

                when TIMEOUT_ERROR =>
                    -- Error receiving data from the PIC. Reset the UART (sending a break signal).
                    if countdown = 0 then
                        if enable_poll_in = '1' then
                            state <= RESET;
                        end if;
                    end if;

                when WAIT_START =>
                    -- We have captured data at least once. Now wait for a new request.
                    if countdown = 0 then
                        if enable_poll_in = '1' then
                            state <= SEND_REQUEST_1;
                        end if;
                    end if;
            end case;
            if reset_in = '1' then
                state <= RESET;
            end if;
        end if;
    end process;

    -- Output registers must be updated atomically to avoid glitches where
    -- some bits change before others.
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if state = WAIT_START then
                adjust_1_out <= adjust_1_tmp;
                adjust_2_out <= adjust_2_tmp;
            end if;
        end if;
    end process;

    -- Signals decoded from the state machine
    ready_out <= '1' when state = WAIT_START else '0';
    error_out <= '1' when state = TIMEOUT_ERROR else '0';
    strobe_to_pic <= '1' when state = SEND_REQUEST_1 or state = SEND_REQUEST_2 else '0';
    data_to_pic <= std_logic_vector (to_unsigned (16#a1#, 8)) when state = SEND_REQUEST_1
              else std_logic_vector (to_unsigned (16#a2#, 8));
    measure_enable <= '1' when state = WAIT_REPLY_1 or state = WAIT_REPLY_2
                            or state = SEND_REQUEST_1 or state = SEND_REQUEST_2
                            or state = WAIT_REPLY_3 or state = WAIT_REPLY_4 else '0';

    -- UART connected to PIC
    pic_uart : entity uart
        generic map (
            clock_frequency => clock_frequency,
            baud_rate => 250.0e3)
        port map (
            data_in => data_to_pic,
            strobe_in => strobe_to_pic,
            reset_in => uart_reset,
            data_out => data_from_pic,
            strobe_out => strobe_from_pic,
            ready_out => open,
            serial_in => rx_from_pic,
            serial_out => tx_to_pic,
            clock_in => clock_in);

end architecture structural;
