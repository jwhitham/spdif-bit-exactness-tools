-- C:\Users\jackd\Documents\Software projects\spdif\fpga\projects\compressor\compressor_Implmnt\sbt\outputs\bitmap\compressor_top_bitmap.bin
-- C:\Users\jackd\Documents\Software projects\spdif\fpga\projects\uart_test\uart_test_Implmnt\sbt\outputs\bitmap\uart_test_top_bitmap.bin

library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_test_top is
    port (
        clk12MHz            : in std_logic;

        tx_to_pic           : out std_logic := '0';
        rx_from_pic         : in std_logic;

        rotary_common_p53   : out std_logic := '0';
        rotary_024_p54      : in std_logic;
        rotary_01_p44       : in std_logic;
        rotary_23_p43       : in std_logic;

        adjust_1a_p52       : out std_logic := '0';
        adjust_1b_p50       : out std_logic := '0';
        adjust_2a_p47       : out std_logic := '0';
        adjust_2b_p45       : out std_logic := '0';

        spdif_tx_p55        : out std_logic := '0';
        spdif_rx_p42        : in std_logic;

        button_a11          : in std_logic;
        button_c11          : in std_logic;
        button_c6           : in std_logic;
        button_a5           : in std_logic;

        lcol1               : out std_logic := '0';
        lcol2               : out std_logic := '0';
        lcol3               : out std_logic := '0';
        lcol4               : out std_logic := '0';
        led1                : out std_logic := '0';
        led2                : out std_logic := '0';
        led3                : out std_logic := '0';
        led4                : out std_logic := '0';
        led5                : out std_logic := '0';
        led6                : out std_logic := '0';
        led7                : out std_logic := '0';
        led8                : out std_logic := '0');
end uart_test_top;

architecture structural of uart_test_top is

    constant clock_frequency : Real := 96.0e6;

    subtype t_ad is std_logic_vector (11 downto 0);
    type t_ad_array is array (Natural range 1 to 2) of t_ad;

    subtype t_level is std_logic_vector (7 downto 0);
    type t_level_array is array (Natural range 1 to 4) of t_level;

    signal clock            : std_logic := '0';
    signal adc_ready        : std_logic := '0';
    signal adc_error        : std_logic := '0';
    signal adc_enable_poll  : std_logic := '0';
    signal rot_mode         : std_logic_vector (2 downto 0) := (others => '0');

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

    component SB_IO is
        generic (pin_type : std_logic_vector (5 downto 0);
                 pullup : std_logic);
        port (
            package_pin : inout std_logic;
            d_in_0 : out std_logic);
    end component;

begin
    pll : entity compressor_pll
        port map (
              REFERENCECLK => clk12MHz,
              RESET => '1',
              PLLOUTCORE => open,
              PLLOUTGLOBAL => clock);

    spdif_tx_p55 <= spdif_rx_p42;

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
                  leds1_in => level (1),
                  leds2_in => level (2),
                  leds3_in => level (3),
                  leds4_in => level (4),
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
                if adc_ready = '1' then
                    level (i) <= (others => '0');
                    value := to_integer (unsigned (ad (i) (9 downto 7)));
                    level (i) (value) <= '1';
                end if;
            end if;
        end process;
    end generate convert_ad_to_level;

    level (4) (7) <= '1';
    level (4) (6) <= '1';
    level (4) (0) <= adc_ready;
    level (4) (1) <= adc_error;

    level (3) (0) <= rot_mode (0);
    level (3) (1) <= rot_mode (1);
    level (3) (2) <= rot_mode (2);

    level (3) (4) <= rot_mode (0);
    level (3) (5) <= rot_mode (1);
    level (3) (6) <= rot_mode (2);

    adc_enable_poll <= not button_c11;

    adc : entity icefun_adc_driver
        generic map (clock_frequency => clock_frequency)
        port map (
            clock_in => clock,
            tx_to_pic => tx_to_pic,
            rx_from_pic => rx_from_pic,
            enable_poll_in => adc_enable_poll,
            ready_out => adc_ready,
            error_out => adc_error,
            adjust_1_out => ad (1),
            adjust_2_out => ad (2),
            adjust_1a_p52 => adjust_1a_p52,
            adjust_1b_p50 => adjust_1b_p50,
            adjust_2a_p47 => adjust_2a_p47,
            adjust_2b_p45 => adjust_2b_p45);

    rotary : block
        -- Signals
        signal rotary_024       : std_logic := '0';
        signal rotary_01        : std_logic := '0';
        signal rotary_23        : std_logic := '0';

    begin
        -- Rotary switch has a common output from the FPGA
        -- which is always LOW. And three inputs with pullups.
        rotary_common_p53 <= '0';

        -- See https://www.latticesemi.com/~/media/LatticeSemi/Documents/TechnicalBriefs/SBTICETechnologyLibrary201504.pdf page 87..90
        -- pin_type = "000001": simple PIN_INPUT
        rotary_024_buffer : SB_IO
            generic map (pin_type => "000001", pullup => '1')
            port map (
                package_pin => rotary_024_p54,
                d_in_0 => rotary_024);

        rotary_01_buffer : SB_IO
            generic map (pin_type => "000001", pullup => '1')
            port map (
                package_pin => rotary_01_p44,
                d_in_0 => rotary_01);

        rotary_23_buffer : SB_IO
            generic map (pin_type => "000001", pullup => '1')
            port map (
                package_pin => rotary_23_p43,
                d_in_0 => rotary_23);

        rot : entity rotary_switch_driver
            generic map (clock_frequency => clock_frequency)
            port map (
                clock_in => clock,
                rotary_024 => rotary_024,
                rotary_01 => rotary_01,
                rotary_23 => rotary_23,
                strobe_out => open,
                mode_out => rot_mode);
        end block rotary;

end structural;

