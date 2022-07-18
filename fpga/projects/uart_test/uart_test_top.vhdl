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

        rotary_common_p53   : out std_logic := '0'; -- green wire E12
        rotary_024_p54      : inout std_logic; -- grey wire D14
        rotary_01_p44       : inout std_logic; -- purple wire K14
        rotary_23_p43       : inout std_logic; -- blue wire H11

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

    subtype t_ad is std_logic_vector (9 downto 0);
    type t_ad_array is array (Natural range 1 to 2) of t_ad;

    signal clock            : std_logic := '0';
    signal adc_ready        : std_logic := '0';
    signal adc_error        : std_logic := '0';
    signal adc_enable_poll  : std_logic := '0';
    signal pulse_100hz      : std_logic := '0';
    signal rot_strobe       : std_logic := '0';
    signal rot_value        : std_logic_vector (2 downto 0) := (others => '0');

    signal ad               : t_ad_array := (others => (others => '0'));
    signal lcols            : std_logic_vector (3 downto 0) := (others => '0');
    signal lrows            : std_logic_vector (7 downto 0) := (others => '0');

    signal raw_meter_left   : std_logic_vector (7 downto 0) := (others => '0');
    signal raw_meter_right  : std_logic_vector (7 downto 0) := (others => '0');

    signal cmp_meter_left   : std_logic_vector (7 downto 0) := (others => '0');
    signal cmp_meter_right  : std_logic_vector (7 downto 0) := (others => '0');

    signal sample_rate      : std_logic_vector (15 downto 0) := (others => '0');
    signal matcher_sync     : std_logic_vector (1 downto 0) := (others => '0');
    signal single_time      : std_logic_vector (7 downto 0) := (others => '0');
    signal sync             : std_logic;

    component SB_IO is
        generic (PIN_TYPE : std_logic_vector (5 downto 0);
                 PULLUP : std_logic);
        port (
            PACKAGE_PIN : inout std_logic;
            D_IN_0 : out std_logic);
    end component;

begin
    pll : entity compressor_pll
        port map (
              REFERENCECLK => clk12MHz,
              RESET => '1',
              PLLOUTCORE => open,
              PLLOUTGLOBAL => clock);

    led1 <= lrows (7);
    led2 <= lrows (6);
    led3 <= lrows (5);
    led4 <= lrows (4);
    led5 <= lrows (3);
    led6 <= lrows (2);
    led7 <= lrows (1);
    led8 <= lrows (0);
    lcol1 <= lcols (3);
    lcol2 <= lcols (2);
    lcol3 <= lcols (1);
    lcol4 <= lcols (0);

    spdif_tx_p55 <= spdif_rx_p42;

    pulse_100hz_gen : entity pulse_gen
        generic map (
            clock_frequency => clock_frequency,
            pulse_frequency => 100.0)
        port map (
            clock_in => clock,
            pulse_out => pulse_100hz);

    display : entity mode_display
        port map (
            clock_in => clock,
            pulse_100hz_in => pulse_100hz,

            -- mode select
            rot_strobe_in => rot_strobe,
            rot_value_in => rot_value,

            -- shown in all modes
            raw_meter_left_in => raw_meter_left,
            raw_meter_right_in => raw_meter_right,

            -- shown in compressor modes
            cmp_meter_left_in => cmp_meter_left,
            cmp_meter_right_in => cmp_meter_right,

            -- shown in passthrough modes
            sample_rate_in => sample_rate,
            matcher_sync_in => matcher_sync,
            single_time_in => single_time,
            sync_in => sync,

            -- LED outputs
            lcols_out => lcols,
            lrows_out => lrows);

    sync <= '1';
    single_time <= ad (1) (9 downto 2);
    adc_enable_poll <= not button_c11;

    adc : entity icefun_adc_driver
        generic map (clock_frequency => clock_frequency)
        port map (
            clock_in => clock,
            pulse_100hz_in => pulse_100hz,
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

        -- Here is one way to configure input pins with a pullup.
        -- See https://www.latticesemi.com/~/media/LatticeSemi/Documents/
        --     TechnicalBriefs/SBTICETechnologyLibrary201504.pdf page 87..90
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
            port map (
                clock_in => clock,
                pulse_100hz_in => pulse_100hz,
                rotary_024 => rotary_024,
                rotary_01 => rotary_01,
                rotary_23 => rotary_23,
                left_button => button_a11,
                right_button => button_a5,
                strobe_out => rot_strobe,
                value_out => rot_value);
    end block rotary;

end structural;

