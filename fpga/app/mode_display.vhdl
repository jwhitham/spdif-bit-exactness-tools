
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

use mode_definitions.all;

entity mode_display is
    port (
        clock_in            : in std_logic;
        pulse_100hz_in      : in std_logic;
        reset_in            : in std_logic;

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
        all_sync_in         : in std_logic_vector (8 downto 0);
        clock_interval_in   : in std_logic_vector (15 downto 0);
        subcode_in          : in std_logic_vector (31 downto 0);
        peak_level_in       : in std_logic_vector (31 downto 0);
        adjust_1_in         : in std_logic_vector (9 downto 0);
        adjust_2_in         : in std_logic_vector (9 downto 0);
        oe_error_in         : in std_logic;
        adc_error_in        : in std_logic;
        cmp_fifo_error_in   : in std_logic;
        cmp_over_error_in   : in std_logic;
        reset_error_in      : in std_logic;

        -- LED outputs
        lcols_out           : out std_logic_vector (3 downto 0) := "0000";
        lrows_out           : out std_logic_vector (7 downto 0) := "00000000");
end mode_display;

architecture structural of mode_display is

    -- Countdown implements the delay for messages on the "screen"
    constant max_countdown  : Natural := 100;
    subtype t_countdown is Natural range 0 to max_countdown;

    -- Here's what's shown on the screen
    type t_display_mode is (ANNOUNCE_DBG_SPDIF, ANNOUNCE_DBG_SUBCODES, ANNOUNCE_DBG_COMPRESS,
                            ANNOUNCE_DBG_ADCS, ANNOUNCE_DBG_VERSION,
                            ANNOUNCE_COMPRESS_MAX, ANNOUNCE_COMPRESS_2, ANNOUNCE_PASSTHROUGH, 
                            ANNOUNCE_COMPRESS_1, ANNOUNCE_ATTENUATE_1, ANNOUNCE_ATTENUATE_2,
                            BOOT, DESYNC, DOUBLE_VU_METER, SINGLE_VU_METER,
                            SHOW_DBG_SPDIF, SHOW_DBG_SUBCODES, SHOW_DBG_COMPRESS,
                            SHOW_DBG_ADCS, SHOW_DBG_VERSION);

    -- LED output
    subtype t_led_line is std_logic_vector (7 downto 0);
    type t_leds is array (Natural range 0 to 3) of t_led_line;

    -- Desync message countdown 
    constant max_desync_messages : Natural := 100;
    subtype t_desync_messages is Natural range 0 to max_desync_messages;

    -- Registers
    signal countdown        : t_countdown := max_countdown;
    signal desync_messages  : t_desync_messages := max_desync_messages;
    signal oe_error_latch   : std_logic := '0';
    signal adc_error_latch  : std_logic := '0';
    signal cmp_fifo_error_latch : std_logic := '0';
    signal cmp_over_error_latch : std_logic := '0';
    signal desync_error_latch : std_logic := '0';

    -- Signals
    signal display_mode     : t_display_mode := BOOT;
    signal leds             : t_leds := (others => (others => '0'));
    signal version          : std_logic_vector (31 downto 0) := (others => '0');
    signal desync_flag      : std_logic := '0';

begin

    desync_flag <= not all_sync_in (all_sync_in'Left);

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            leds <= (others => (others => '0'));
            case display_mode is
                when SHOW_DBG_VERSION | BOOT =>
                    -- Bootup
                    leds (0) <= version (31 downto 24);
                    leds (1) <= version (23 downto 16);
                    leds (2) <= version (15 downto 8);
                    leds (3) <= version (7 downto 0);
                when DESYNC =>
                    -- Desync "dc"
                    leds (0) <= "00010000";
                    leds (1) <= "01110111";
                    leds (2) <= "01010100";
                    leds (3) <= "01110111";
                when ANNOUNCE_COMPRESS_MAX =>
                    -- compressed to max level "cx"
                    leds (0) <= "11100000";
                    leds (1) <= "10000101";
                    leds (2) <= "10000010";
                    leds (3) <= "11100101";
                when ANNOUNCE_COMPRESS_2 =>
                    -- compressed to volume level 2 "c2"
                    leds (0) <= "11100000";
                    leds (1) <= "10000101";
                    leds (2) <= "10000101";
                    leds (3) <= "11100101";
                when ANNOUNCE_COMPRESS_1 =>
                    -- compressed to volume level 1 "c1"
                    leds (0) <= "11100000";
                    leds (1) <= "10000010";
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
                    leds (0) <= "00100000";
                    leds (1) <= "11100000";
                    leds (2) <= "10100010";
                    leds (3) <= "11100000";
                when SHOW_DBG_SPDIF =>
                    -- S/PDIF signal information
                    leds (0) <= single_time_in;
                    leds (1) <= clock_interval_in (15 downto 8);
                    leds (2) <= clock_interval_in (7 downto 0);
                    leds (3) <= all_sync_in (8 downto 1);
                when ANNOUNCE_DBG_SUBCODES =>
                    -- debug mode 2
                    leds (0) <= "00100000";
                    leds (1) <= "11100100";
                    leds (2) <= "10100000";
                    leds (3) <= "11100001";
                when SHOW_DBG_SUBCODES =>
                    -- Subcodes information
                    leds (0) <= subcode_in (31 downto 24);
                    leds (1) <= subcode_in (23 downto 16);
                    leds (2) <= subcode_in (15 downto 8);
                    leds (3) <= subcode_in (7 downto 0);
                when ANNOUNCE_DBG_COMPRESS =>
                    -- debug mode 3
                    leds (0) <= "00100000";
                    leds (1) <= "11100100";
                    leds (2) <= "10100010";
                    leds (3) <= "11100001";
                when SHOW_DBG_COMPRESS =>
                    -- Compressor information
                    leds (0) <= peak_level_in (31 downto 24);
                    leds (1) <= peak_level_in (23 downto 16);
                    leds (2) <= peak_level_in (15 downto 8);
                    leds (3) <= peak_level_in (7 downto 0);
                when ANNOUNCE_DBG_ADCS =>
                    -- debug mode 4
                    leds (0) <= "00100000";
                    leds (1) <= "11100101";
                    leds (2) <= "10100000";
                    leds (3) <= "11100101";
                when SHOW_DBG_ADCS =>
                    -- ADC information and error latches
                    leds (0) (1 downto 0) <= adjust_1_in (9 downto 8);
                    leds (0) (7) <= oe_error_latch;      -- output encoder FIFO error
                    leds (0) (6) <= adc_error_latch;     -- ADC capture error (timeout reading from PIC)
                    leds (0) (5) <= cmp_fifo_error_latch; -- compressor FIFO error
                    leds (0) (4) <= cmp_over_error_latch; -- compressor overflow error
                    leds (0) (3) <= desync_error_latch;  -- desync at some point
                    leds (0) (2) <= reset_error_in;      -- reset button is pressed
                    leds (1) <= adjust_1_in (7 downto 0);
                    leds (2) (1 downto 0) <= adjust_2_in (9 downto 8);
                    leds (3) <= adjust_2_in (7 downto 0);
                when ANNOUNCE_DBG_VERSION =>
                    -- debug mode 5
                    leds (0) <= "00100000";
                    leds (1) <= "11100101";
                    leds (2) <= "10100010";
                    leds (3) <= "11100101";
            end case;
        end if;
    end process;

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if reset_in = '1' then
                -- Hold in reset
                countdown <= max_countdown;
                desync_messages <= max_desync_messages;
                display_mode <= BOOT;

            elsif mode_strobe_in = '1' then
                -- Change mode; announce the new mode
                countdown <= max_countdown;
                desync_messages <= max_desync_messages;
                case mode_select_in is
                    when COMPRESS_MAX =>
                        display_mode <= ANNOUNCE_COMPRESS_MAX;
                    when COMPRESS_2 =>
                        display_mode <= ANNOUNCE_COMPRESS_2;
                    when COMPRESS_1 =>
                        display_mode <= ANNOUNCE_COMPRESS_1;
                    when ATTENUATE_1 =>
                        display_mode <= ANNOUNCE_ATTENUATE_1;
                    when ATTENUATE_2 =>
                        display_mode <= ANNOUNCE_ATTENUATE_2;
                    when PASSTHROUGH =>
                        display_mode <= ANNOUNCE_PASSTHROUGH;
                    when DBG_SPDIF =>
                        display_mode <= ANNOUNCE_DBG_SPDIF;
                    when DBG_SUBCODES =>
                        display_mode <= ANNOUNCE_DBG_SUBCODES;
                    when DBG_COMPRESS =>
                        display_mode <= ANNOUNCE_DBG_COMPRESS;
                    when DBG_ADCS =>
                        display_mode <= ANNOUNCE_DBG_ADCS;
                    when DBG_VERSION =>
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

            elsif desync_flag = '1' and display_mode /= DESYNC and desync_messages /= 0 then
                -- Show desync display
                countdown <= max_countdown;
                display_mode <= DESYNC;
                desync_messages <= desync_messages - 1;

            else
                -- Stable - show normal display
                case mode_select_in is
                    when COMPRESS_MAX | COMPRESS_2 | COMPRESS_1 =>
                        display_mode <= DOUBLE_VU_METER;
                    when DBG_SPDIF =>
                        display_mode <= SHOW_DBG_SPDIF;
                    when DBG_SUBCODES =>
                        display_mode <= SHOW_DBG_SUBCODES;
                    when DBG_COMPRESS =>
                        display_mode <= SHOW_DBG_COMPRESS;
                    when DBG_ADCS =>
                        display_mode <= SHOW_DBG_ADCS;
                    when DBG_VERSION =>
                        display_mode <= SHOW_DBG_VERSION;
                    when others =>
                        display_mode <= SINGLE_VU_METER;
                end case;
            end if;
        end if;
    end process;

    error_latches : process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if reset_in = '1' or reset_error_in = '1' then
                oe_error_latch <= '0';
                adc_error_latch <= '0';
                cmp_fifo_error_latch <= '0';
                cmp_over_error_latch <= '0';
                desync_error_latch <= '0';
            else
                oe_error_latch <= oe_error_latch or oe_error_in;
                adc_error_latch <= adc_error_latch or adc_error_in;
                cmp_over_error_latch <= cmp_over_error_latch or cmp_over_error_in;
                cmp_fifo_error_latch <= cmp_fifo_error_latch or cmp_fifo_error_in;
                desync_error_latch <= desync_flag or desync_error_latch;
            end if;
        end if;
    end process error_latches;

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

