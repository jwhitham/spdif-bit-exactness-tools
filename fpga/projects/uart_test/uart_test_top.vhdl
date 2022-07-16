
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_test_top is
    port (
        clk12MHz        : in std_logic;
        tx_to_pic       : out std_logic := '0';
        rx_from_pic     : in std_logic;
        lcol1           : out std_logic := '0';
        lcol2           : out std_logic := '0';
        lcol3           : out std_logic := '0';
        lcol4           : out std_logic := '0';
        led1            : out std_logic := '0';
        led2            : out std_logic := '0';
        led3            : out std_logic := '0';
        led4            : out std_logic := '0';
        led5            : out std_logic := '0';
        led6            : out std_logic := '0';
        led7            : out std_logic := '0';
        led8            : out std_logic := '0' );
end uart_test_top;

architecture structural of uart_test_top is

    constant clock_frequency : Real := 96.0e6;

    subtype t_ad is std_logic_vector (11 downto 0);
    type t_ad_array is array (Natural range 1 to 2) of t_ad;

    subtype t_level is std_logic_vector (15 downto 0);
    type t_level_array is array (Natural range 1 to 2) of t_level;

    signal data_from_pic    : std_logic_vector (7 downto 0);
    signal data_to_pic      : std_logic_vector (7 downto 0);
    signal strobe_from_pic  : std_logic;
    signal strobe_to_pic    : std_logic;
    signal clock            : std_logic := '0';
    signal uart_reset       : std_logic := '0';
    signal ad               : t_ad_array := (others => (others => '0'));
    signal level            : t_level_array := (others => (others => '0'));
    signal lcols            : std_logic_vector (3 downto 0) := "0000";
    signal lrows            : std_logic_vector (7 downto 0) := "00000000";

    type t_state is (REPEAT, WAIT_BETWEEN_REQUESTS,
                     SEND_REQUEST_1, WAIT_REPLY_1, WAIT_REPLY_2,
                     SEND_REQUEST_2, WAIT_REPLY_3, WAIT_REPLY_4,
                     TIMEOUT_ERROR, WAIT_RESET_UART);
    signal state            : t_state := REPEAT;

    constant max_countdown  : Natural := Natural (clock_frequency / 100.0);
    subtype t_countdown is Natural range 0 to max_countdown;
    signal countdown        : t_countdown := max_countdown;

begin
    pll : entity compressor_pll
        port map (
              REFERENCECLK => clk12MHz,
              RESET => '1',
              PLLOUTCORE => open,
              PLLOUTGLOBAL => clock);

    -- iceFUN has a PIC with A/D converters, accessed via serial connection at 250kbps
    -- sending \xA1 gave me the input to pin 26 labelled X2
    -- sending \xA2 gave me the input to pin 25 labelled X1
    -- sending \xA3 gave me the input to pin 32 labelled X3
    -- sending \xA4 gave me the input to pin 33 labelled X4
    -- samples arrive around 150 microseconds after being requested though the time is not exact
    -- and varies by 20/30 microseconds in both directions; the delay in these UARTs increases
    -- the time - expect a minimum sample period of about 250 microseconds here.
    -- The least significant byte seemed to be sent first (manual says otherwise).
    -- Values were 10 bit.

    leds : entity led_scan
        port map (clock => clock,
                  leds1_in => level (1) (7 downto 0),
                  leds2_in => level (1) (15 downto 8),
                  leds3_in => level (2) (7 downto 0),
                  leds4_in => level (2) (15 downto 8),
                  lrows_out => lrows,
                  lcols_out => lcols);

    led1 <= lrows (0);
    led2 <= lrows (1);
    led3 <= lrows (2);
    led4 <= lrows (3);
    led5 <= lrows (4);
    led6 <= lrows (5);
    led7 <= lrows (6);
    led8 <= lrows (7);
    lcol1 <= lcols (0);
    lcol2 <= lcols (1);
    lcol3 <= lcols (2);
    lcol4 <= lcols (3);

    convert_ad_to_level : for i in 1 to 2 generate
    begin
        process (clock)
            subtype t_value is Integer range 0 to 15;
            variable value : t_value := 0;
        begin
            if clock'event and clock = '1' then
                if state = REPEAT then
                    level (i) <= (others => '0');
                    value := to_integer (unsigned (ad (i) (9 downto 6)));
                    level (i) (value) <= '1';
                end if;
            end if;
        end process;
    end generate convert_ad_to_level;


    process (clock)
    begin
        if clock'event and clock = '1' then
            strobe_to_pic <= '0';
            uart_reset <= '0';
            case state is
                when REPEAT =>
                    countdown <= max_countdown;
                    state <= WAIT_BETWEEN_REQUESTS;

                when WAIT_BETWEEN_REQUESTS =>
                    if countdown = 0 then
                        state <= SEND_REQUEST_1;
                    else
                        countdown <= countdown - 1;
                    end if;

                when SEND_REQUEST_1 =>
                    data_to_pic <= std_logic_vector (to_unsigned (16#a1#, 8));
                    strobe_to_pic <= '1';
                    countdown <= max_countdown;
                    state <= WAIT_REPLY_1;

                when WAIT_REPLY_1 =>
                    if strobe_from_pic = '1' then
                        state <= WAIT_REPLY_2;
                        ad (1) (7 downto 0) <= data_from_pic;
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    else
                        countdown <= countdown - 1;
                    end if;

                when WAIT_REPLY_2 =>
                    if strobe_from_pic = '1' then
                        state <= SEND_REQUEST_2;
                        ad (1) (9 downto 8) <= data_from_pic (1 downto 0);
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    else
                        countdown <= countdown - 1;
                    end if;

                when SEND_REQUEST_2 =>
                    data_to_pic <= std_logic_vector (to_unsigned (16#a2#, 8));
                    strobe_to_pic <= '1';
                    countdown <= max_countdown;
                    state <= WAIT_REPLY_3;

                when WAIT_REPLY_3 =>
                    if strobe_from_pic = '1' then
                        state <= WAIT_REPLY_4;
                        ad (2) (7 downto 0) <= data_from_pic;
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    else
                        countdown <= countdown - 1;
                    end if;

                when WAIT_REPLY_4 =>
                    if strobe_from_pic = '1' then
                        state <= REPEAT;
                        ad (2) (9 downto 8) <= data_from_pic (1 downto 0);
                    elsif countdown = 0 then
                        state <= TIMEOUT_ERROR;
                    else
                        countdown <= countdown - 1;
                    end if;

                when TIMEOUT_ERROR =>
                    countdown <= max_countdown;
                    state <= WAIT_RESET_UART;

                when WAIT_RESET_UART =>
                    uart_reset <= '1';
                    if countdown = 0 then
                        state <= REPEAT;
                    else
                        countdown <= countdown - 1;
                    end if;

            end case;
        end if;
    end process;

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
            clock_in => clock);
end structural;

