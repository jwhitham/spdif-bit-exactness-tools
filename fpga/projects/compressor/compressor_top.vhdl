
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

entity compressor_top is
    port (
        clk12MHz            : in std_logic;

        tx_to_pic           : out std_logic := '0';
        rx_from_pic         : in std_logic;

        rotary_common_p53   : out std_logic := '0'; -- green wire E12
        rotary_024_p54      : in std_logic; -- grey wire D14
        rotary_01_p44       : in std_logic; -- purple wire K14
        rotary_23_p43       : in std_logic; -- blue wire H11

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
end compressor_top;

architecture structural of compressor_top is

    signal lcols            : std_logic_vector (3 downto 0) := "0000";
    signal lrows            : std_logic_vector (7 downto 0) := "00000000";
    signal clock            : std_logic := '0';
    signal rotary_024       : std_logic := '0';
    signal rotary_01        : std_logic := '0';
    signal rotary_23        : std_logic := '0';

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
    fp : entity compressor_main
        port map (
            clock_in => clock,

            tx_to_pic_out => tx_to_pic,
            rx_from_pic_in => rx_from_pic,

            rotary_024_in => rotary_024,
            rotary_01_in => rotary_01,
            rotary_23_in => rotary_23,

            adjust_1a_out => adjust_1a_p52,
            adjust_1b_out => adjust_1b_p50,
            adjust_2a_out => adjust_2a_p47,
            adjust_2b_out => adjust_2b_p45,

            spdif_tx_out => spdif_tx_p55,
            spdif_rx_in => spdif_rx_p42,

            button_a11_in => button_a11,
            button_c11_in => button_c11,
            button_c6_in => button_c6,
            button_a5_in => button_a5,

            lcols_out => lcols,
            lrows_out => lrows);

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

end structural;

