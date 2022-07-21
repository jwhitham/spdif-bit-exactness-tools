
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

entity mode_display is
    port (
        clock_in            : in std_logic;
        pulse_100hz_in      : in std_logic;

        -- mode select
        mode_strobe_in      : in std_logic;
        mode_select_in      : in mode_definitions.t_mode;

        -- shown in all modes
        raw_meter_left_in   : in std_logic_vector (7 downto 0);
        raw_meter_right_in  : in std_logic_vector (7 downto 0);

        -- shown in compressor modes
        cmp_meter_left_in   : in std_logic_vector (7 downto 0);
        cmp_meter_right_in  : in std_logic_vector (7 downto 0);

        -- shown in debug modes
        sample_rate_in      : in std_logic_vector (15 downto 0);
        matcher_sync_in     : in std_logic_vector (1 downto 0);
        single_time_in      : in std_logic_vector (7 downto 0);
        all_sync_in         : in std_logic_vector (1 to 8);
        clock_interval_in   : in std_logic_vector (15 downto 0);
        subcode_in          : in std_logic_vector (31 downto 0);
        peak_level_in       : in std_logic_vector (31 downto 0);
        adjust_1_in         : in std_logic_vector (9 downto 0);
        adjust_2_in         : in std_logic_vector (9 downto 0);

        -- LED outputs
        lcols_out           : out std_logic_vector (3 downto 0) := "0000";
        lrows_out           : out std_logic_vector (7 downto 0) := "00000000");
end mode_display;

architecture structural of mode_display is
    -- Countdown implements a second delay
    constant max_countdown  : Natural := 100;
    subtype t_countdown is Natural range 0 to max_countdown;

    type t_display_mode is (ANNOUNCE_DBG_SPDIF, ANNOUNCE_DBG_SUBCODES, ANNOUNCE_DBG_COMPRESS,
                            ANNOUNCE_DBG_ADCS, ANNOUNCE_DBG_VERSION,
                            ANNOUNCE_COMPRESS_MAX, ANNOUNCE_COMPRESS_2, ANNOUNCE_PASSTHROUGH, 
                            ANNOUNCE_COMPRESS_1, ANNOUNCE_ATTENUATE_1, ANNOUNCE_ATTENUATE_2,
                            BOOT, DESYNC, DOUBLE_VU_METER, SINGLE_VU_METER,
                            DBG_SPDIF, DBG_SUBCODES, DBG_COMPRESS,
                            DBG_ADCS, DBG_VERSION);
    subtype t_led_line is std_logic_vector (7 downto 0);
    type t_leds is array (Natural range 0 to 3) of t_led_line;

    -- Registers
    signal countdown        : t_countdown := max_countdown;

    -- Signals
    signal display_mode     : t_display_mode := BOOT;
    signal leds             : t_leds := (others => (others => '0'));
    signal version          : std_logic_vector (31 downto 0) := (others => '0');

begin

    process (display_mode, raw_meter_left_in, raw_meter_right_in,
             cmp_meter_left_in, cmp_meter_right_in, sample_rate_in,
             matcher_sync_in, single_time_in)
    begin
        leds <= (others => (others => '0'));
        case display_mode is
            when DBG_VERSION | ANNOUNCE_DBG_VERSION | BOOT =>
                -- Bootup
                leds (0) <= version (31 downto 24);
                leds (1) <= version (23 downto 16);
                leds (1) <= version (15 downto 8);
                leds (1) <= version (7 downto 0);
            when DESYNC =>
                -- Desync "dc"
                leds (0) <= "00010000";
                leds (1) <= "01110111";
                leds (2) <= "01010100";
                leds (3) <= "01110111";
            when ANNOUNCE_COMPRESS_MAX =>
                -- compressed to max level "cx"
                leds (0) <= "00000000";
                leds (1) <= "11100101";
                leds (2) <= "10000010";
                leds (3) <= "11100101";
            when ANNOUNCE_COMPRESS_2 =>
                -- compressed to volume level 2 "c2"
                leds (0) <= "00000000";
                leds (1) <= "11100101";
                leds (2) <= "10000101";
                leds (3) <= "11100101";
            when ANNOUNCE_COMPRESS_1 =>
                -- compressed to volume level 1 "c1"
                leds (0) <= "00000000";
                leds (1) <= "11100010";
                leds (2) <= "10000010";
                leds (3) <= "11100010";
            when ANNOUNCE_ATTENUATE_1 =>
                -- attenuated to volume level 1 "a1"
                leds (0) <= "11100000";
                leds (1) <= "10100010";
                leds (2) <= "11100010";
                leds (3) <= "10100010";
            when ANNOUNCE_ATTENUATE_2 =>
                -- attenuated to volume level 2 "a2"
                leds (0) <= "11100000";
                leds (1) <= "10100101";
                leds (2) <= "11100101";
                leds (3) <= "10100101";
            when ANNOUNCE_PASSTHROUGH =>
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
            when ANNOUNCE_DBG_SPDIF =>
                -- debug mode 1
                leds (0) <= "10000000";
                leds (1) <= "10000000";
                leds (2) <= "10000000";
                leds (3) <= "10000000";
            when DBG_SPDIF =>
                -- S/PDIF signal information
                leds (0) <= single_time_in;
                leds (1) <= clock_interval_in (15 downto 8);
                leds (2) <= clock_interval_in (7 downto 0);
                leds (3) <= all_sync_in;
            when ANNOUNCE_DBG_SUBCODES =>
                -- debug mode 2
                leds (0) <= "10100000";
                leds (1) <= "10100000";
                leds (2) <= "10100000";
                leds (3) <= "10100000";
            when DBG_SUBCODES =>
                -- Subcodes information
                leds (0) <= subcode_in (31 downto 24);
                leds (1) <= subcode_in (23 downto 16);
                leds (2) <= subcode_in (15 downto 8);
                leds (3) <= subcode_in (7 downto 0);
            when ANNOUNCE_DBG_COMPRESS =>
                -- debug mode 3
                leds (0) <= "10101000";
                leds (1) <= "10101000";
                leds (2) <= "10101000";
                leds (3) <= "10101000";
            when DBG_COMPRESS =>
                -- Compressor information
                leds (0) <= peak_level_in (31 downto 24);
                leds (1) <= peak_level_in (23 downto 16);
                leds (2) <= peak_level_in (15 downto 8);
                leds (3) <= peak_level_in (7 downto 0);
            when ANNOUNCE_DBG_ADCS =>
                -- debug mode 4
                leds (0) <= "10101010";
                leds (1) <= "10101010";
                leds (2) <= "10101010";
                leds (3) <= "10101010";
            when DBG_ADCS =>
                -- ADC information
                leds (0) (1 downto 0) <= adjust_1_in (9 downto 8);
                leds (1) <= adjust_1_in (7 downto 0);
                leds (2) (1 downto 0) <= adjust_2_in (9 downto 8);
                leds (3) <= adjust_2_in (7 downto 0);
        end case;
    end process;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if mode_strobe_in = '1' then
                -- Change mode
                countdown <= max_countdown;
                case mode_select_in is
                    when mode_definitions.COMPRESS_MAX =>
                        display_mode <= ANNOUNCE_COMPRESS_MAX;
                    when mode_definitions.COMPRESS_2 =>
                        display_mode <= ANNOUNCE_COMPRESS_2;
                    when mode_definitions.COMPRESS_1 =>
                        display_mode <= ANNOUNCE_COMPRESS_1;
                    when mode_definitions.ATTENUATE_1 =>
                        display_mode <= ANNOUNCE_ATTENUATE_1;
                    when mode_definitions.ATTENUATE_2 =>
                        display_mode <= ANNOUNCE_ATTENUATE_2;
                    when mode_definitions.PASSTHROUGH =>
                        display_mode <= ANNOUNCE_PASSTHROUGH;
                    when mode_definitions.DBG_SPDIF =>
                        display_mode <= ANNOUNCE_DBG_SPDIF;
                    when mode_definitions.DBG_SUBCODES =>
                        display_mode <= ANNOUNCE_DBG_SUBCODES;
                    when mode_definitions.DBG_COMPRESS =>
                        display_mode <= ANNOUNCE_DBG_COMPRESS;
                    when mode_definitions.DBG_ADCS =>
                        display_mode <= ANNOUNCE_DBG_ADCS;
                    when mode_definitions.DBG_VERSION =>
                        display_mode <= ANNOUNCE_DBG_VERSION;
                    when others =>
                        display_mode <= ANNOUNCE_PASSTHROUGH;
                end case;

            elsif countdown /= 0 then
                -- Recently changed mode; keep the mode change on the display
                -- for half a second
                if pulse_100hz_in = '1' then
                    countdown <= countdown - 1;
                end if;

            elsif all_sync_in (8) = '0' then
                -- No input
                countdown <= max_countdown;
                display_mode <= DESYNC;

            else
                -- Stable - show normal display
                case mode_select_in is
                    when mode_definitions.COMPRESS_MAX
                            | mode_definitions.COMPRESS_2
                            | mode_definitions.COMPRESS_1 =>
                        display_mode <= DOUBLE_VU_METER;
                    when mode_definitions.DBG_SPDIF =>
                        display_mode <= DBG_SPDIF;
                    when mode_definitions.DBG_SUBCODES =>
                        display_mode <= DBG_SUBCODES;
                    when mode_definitions.DBG_COMPRESS =>
                        display_mode <= DBG_COMPRESS;
                    when mode_definitions.DBG_ADCS =>
                        display_mode <= DBG_ADCS;
                    when mode_definitions.DBG_VERSION =>
                        display_mode <= DBG_VERSION;
                    when others =>
                        display_mode <= SINGLE_VU_METER;
                end case;
            end if;
        end if;
    end process;

    vr : entity version_rom
        port map (data_out => version);

    led_driver : entity led_scan
        port map (clock => clock_in,
                  leds1_in => leds (0),
                  leds2_in => leds (1),
                  leds3_in => leds (2),
                  leds4_in => leds (3),
                  lrows_out => lrows_out,
                  lcols_out => lcols_out);

end structural;

