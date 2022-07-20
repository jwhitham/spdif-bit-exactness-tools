
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

entity mode_display is
    port (
        clock_in            : in std_logic;
        pulse_100hz_in      : in std_logic;

        -- mode select
        rot_strobe_in       : in std_logic;
        rot_value_in        : in std_logic_vector (2 downto 0);

        -- shown in all modes
        raw_meter_left_in   : in std_logic_vector (7 downto 0);
        raw_meter_right_in  : in std_logic_vector (7 downto 0);

        -- shown in compressor modes
        cmp_meter_left_in   : in std_logic_vector (7 downto 0);
        cmp_meter_right_in  : in std_logic_vector (7 downto 0);

        -- shown in passthrough modes
        sample_rate_in      : in std_logic_vector (15 downto 0);
        matcher_sync_in     : in std_logic_vector (1 downto 0);
        single_time_in      : in std_logic_vector (7 downto 0);
        sync_in             : in std_logic;

        -- LED outputs
        lcols_out           : out std_logic_vector (3 downto 0) := "0000";
        lrows_out           : out std_logic_vector (7 downto 0) := "00000000");
end mode_display;

architecture structural of mode_display is
    -- Countdown implements a half-second delay
    constant max_countdown  : Natural := 50;
    subtype t_countdown is Natural range 0 to max_countdown;

    type t_display_mode is (DESYNC, COMPRESS_MAX, COMPRESS_2,
                            COMPRESS_1, ATTENUATED_1, ATTENUATED_2,
                            PASSTHROUGH, DOUBLE_VU_METER, SINGLE_VU_METER);
    subtype t_led_line is std_logic_vector (7 downto 0);
    type t_leds is array (Natural range 0 to 3) of t_led_line;

    -- Registers
    signal countdown        : t_countdown := max_countdown;

    -- Signals
    signal display_mode     : t_display_mode := DESYNC;
    signal leds             : t_leds := (others => (others => '0'));

begin

    process (display_mode, raw_meter_left_in, raw_meter_right_in,
             cmp_meter_left_in, cmp_meter_right_in, sample_rate_in,
             matcher_sync_in, single_time_in)
    begin
        leds <= (others => (others => '0'));
        case display_mode is
            when DESYNC =>
                -- Desync "dc"
                leds (0) <= "00010000";
                leds (1) <= "01110111";
                leds (2) <= "01010100";
                leds (3) <= "01110111";
            when COMPRESS_MAX =>
                -- compressed to max level "cx"
                leds (0) <= "00000000";
                leds (1) <= "11100101";
                leds (2) <= "10000010";
                leds (3) <= "11100101";
            when COMPRESS_2 =>
                -- compressed to volume level 2 "c2"
                leds (0) <= "00000000";
                leds (1) <= "11100101";
                leds (2) <= "10000101";
                leds (3) <= "11100101";
            when COMPRESS_1 =>
                -- compressed to volume level 1 "c1"
                leds (0) <= "00000000";
                leds (1) <= "11100010";
                leds (2) <= "10000010";
                leds (3) <= "11100010";
            when ATTENUATED_1 =>
                -- attenuated to volume level 1 "a1"
                leds (0) <= "11100000";
                leds (1) <= "10100010";
                leds (2) <= "11100010";
                leds (3) <= "10100010";
            when ATTENUATED_2 =>
                -- attenuated to volume level 2 "a2"
                leds (0) <= "11100000";
                leds (1) <= "10100101";
                leds (2) <= "11100101";
                leds (3) <= "10100101";
            when PASSTHROUGH =>
                -- passthrough "p"
                leds (0) <= "11100000";
                leds (1) <= "10100000";
                leds (2) <= "11100000";
                leds (3) <= "10000000";
            when DOUBLE_VU_METER =>
                -- Compressed modes
                leds (0) <= raw_meter_left_in;
                leds (1) <= raw_meter_right_in;
                leds (2) <= cmp_meter_left_in;
                leds (3) <= cmp_meter_right_in;
            when SINGLE_VU_METER =>
                -- Passthrough and attenuated modes
                leds (0) <= raw_meter_left_in;
                leds (1) <= raw_meter_right_in;

                if matcher_sync_in /= "00" then
                    leds (3) (7 downto 4) <= sample_rate_in (7 downto 4);
                    leds (3) (3 downto 2) <= "00";
                    leds (3) (1 downto 0) <= matcher_sync_in;
                else
                    leds (3) <= (others => '0');
                end if;
                leds (2) <= single_time_in;
        end case;
    end process;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if sync_in = '0' then
                -- No input
                countdown <= max_countdown;
                display_mode <= DESYNC;

            elsif rot_strobe_in = '1' then
                -- Change mode
                countdown <= max_countdown;
                case rot_value_in is
                    when "000" =>
                        display_mode <= COMPRESS_MAX;
                    when "001" =>
                        display_mode <= COMPRESS_2;
                    when "010" =>
                        display_mode <= COMPRESS_1;
                    when "011" =>
                        display_mode <= ATTENUATED_1;
                    when "100" =>
                        display_mode <= ATTENUATED_2;
                    when others =>
                        display_mode <= PASSTHROUGH;
                end case;

            elsif countdown /= 0 then
                -- Recently changed mode; keep the mode change on the display
                -- for half a second
                if pulse_100hz_in = '1' then
                    countdown <= countdown - 1;
                end if;

            else
                -- Stable - show normal display
                case rot_value_in is
                    when "000" | "001" | "010" =>
                        display_mode <= DOUBLE_VU_METER;
                    when others =>
                        display_mode <= SINGLE_VU_METER;
                end case;
            end if;
        end if;
    end process;

    led_driver : entity led_scan
        port map (clock => clock_in,
                  leds1_in => leds (0),
                  leds2_in => leds (1),
                  leds3_in => leds (2),
                  leds4_in => leds (3),
                  lrows_out => lrows_out,
                  lcols_out => lcols_out);

end structural;

