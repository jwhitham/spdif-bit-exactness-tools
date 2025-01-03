
library work;
use work.all;

library comfilter;
use comfilter.filter_unit_settings.ALL_BITS;
use comfilter.filter_unit_settings.NON_FRACTIONAL_BITS;
use comfilter.filter_unit_settings.FRACTIONAL_BITS;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use mode_definitions.all;

entity compressor_main is
    port (
        clock_in            : in std_logic;

        tx_to_pic_out       : out std_logic := '0';
        rx_from_pic_in      : in std_logic;

        rotary_024_in       : in std_logic;
        rotary_01_in        : in std_logic;
        rotary_23_in        : in std_logic;

        adjust_1a_out       : out std_logic := '0';
        adjust_1b_out       : out std_logic := '0';
        adjust_2a_out       : out std_logic := '0';
        adjust_2b_out       : out std_logic := '0';

        spdif_tx_out        : out std_logic := '0';
        spdif_rx_in         : in std_logic;

        button_a11_in       : in std_logic;
        button_c11_in       : in std_logic;
        button_c6_in        : in std_logic;
        button_a5_in        : in std_logic;

        com_serial_out      : out std_logic := '0';

        -- LED outputs
        lcols_out           : out std_logic_vector (3 downto 0) := "0000";
        lrows_out           : out std_logic_vector (7 downto 0) := "00000000");
end compressor_main;

architecture structural of compressor_main is

    constant clock_frequency        : Real := 96.0e6;

    signal rg_strobe                : std_logic := '0';
    signal encoded_spdif            : std_logic := '0';
    constant enabled                : std_logic := '1';

    -- biphase mark codes, decoded
    subtype t_pulse_length is std_logic_vector (1 downto 0);
    signal raw_pulse_length         : t_pulse_length := "00";
    signal cmp_pulse_length         : t_pulse_length := "00";

    -- serial S/PDIF data
    signal raw_packet_data          : std_logic := '0';
    signal raw_packet_shift         : std_logic := '0';
    signal raw_packet_start         : std_logic := '0';
    signal cmp_packet_data          : std_logic := '0';
    signal cmp_packet_shift         : std_logic := '0';
    signal cmp_packet_start         : std_logic := '0';

    -- parallel audio data
    subtype t_data is std_logic_vector (31 downto 0);
    signal raw_data                 : t_data := (others => '0');
    signal raw_left_strobe          : std_logic := '0';
    signal raw_right_strobe         : std_logic := '0';
    signal cmp_data                 : t_data := (others => '0');
    signal cmp_left_strobe          : std_logic := '0';
    signal cmp_right_strobe         : std_logic := '0';

    -- com receiver
    signal com_data                 : std_logic_vector(15 downto 0) := (others => '0');
    signal com_strobe               : std_logic := '0';
    signal com_adjust_1_set         : std_logic := '0';
    signal com_adjust_2_set         : std_logic := '0';

    -- matcher
    signal matcher_sync             : std_logic_vector (1 downto 0) := "00";
    signal sample_rate              : std_logic_vector (15 downto 0) := (others => '0');

    -- volume controls (potentiometers)
    subtype t_adjust is std_logic_vector (9 downto 0);
    signal adjust_1                 : t_adjust := (others => '0');
    signal adjust_2                 : t_adjust := (others => '0');
    
    -- display and UI
    subtype t_leds is std_logic_vector (7 downto 0);
    signal raw_left_meter           : t_leds := (others => '0');
    signal raw_right_meter          : t_leds := (others => '0');
    signal cmp_left_meter           : t_leds := (others => '0');
    signal cmp_right_meter          : t_leds := (others => '0');
    signal single_time              : t_leds := (others => '0');
    signal preemph                  : std_logic := '0';
    signal sync                     : std_logic_vector (6 downto 0) := (others => '0');
    signal pulse_100hz              : std_logic := '0';
    signal adc_enable_poll          : std_logic := '0';
    signal cmp_enable               : std_logic := '0';
    signal cmp_delay_bypass         : std_logic := '0';
    signal clock_interval           : std_logic_vector (15 downto 0) := (others => '0');
    signal subcode                  : std_logic_vector (31 downto 0) := (others => '0');
    signal peak_level               : std_logic_vector (31 downto 0) := (others => '0');
    signal volume                   : std_logic_vector (10 downto 0) := (others => '0');
    signal oe_error                 : std_logic := '0';
    signal adc_error                : std_logic := '0';
    signal cmp_fifo_error           : std_logic := '0';
    signal cmp_over_error           : std_logic := '0';
    signal reset_error              : std_logic := '0';

    -- user mode
    signal mode_strobe              : std_logic := '0';
    signal mode_select              : mode_definitions.t_mode := mode_definitions.min_value;

    -- reset signal
    signal reset                    : std_logic := '1';

    -- For reset, we have to use an up-counter, because the default value is always 0
    constant max_reset_counter : Natural := 10;
    subtype t_reset_counter is Natural range 0 to max_reset_counter;
    signal reset_counter    : t_reset_counter := max_reset_counter;


begin
    sync (0) <= not reset;

    dec1 : entity input_decoder
        port map (clock_in => clock_in,
                  data_in => spdif_rx_in,
                  sync_in => sync (0),
                  sync_out => sync (1),
                  enable_123_check_in => enabled,
                  single_time_out => single_time,
                  pulse_length_out => raw_pulse_length);

    dec2 : entity packet_decoder
        port map (clock => clock_in,
                  pulse_length_in => raw_pulse_length,
                  sync_in => sync (1),
                  sync_out => sync (2),
                  data_out => raw_packet_data,
                  start_out => raw_packet_start,
                  shift_out => raw_packet_shift);

    dec3 : entity channel_decoder 
        port map (clock => clock_in,
                  data_in => raw_packet_data,
                  shift_in => raw_packet_shift,
                  start_in => raw_packet_start,
                  sync_in => sync (2),
                  sync_out => sync (3),
                  data_out => raw_data,
                  subcode_out => subcode,
                  left_strobe_out => raw_left_strobe,
                  right_strobe_out => raw_right_strobe);

    rg : entity clock_regenerator
        port map (clock_in => clock_in,
                  pulse_length_in => raw_pulse_length,
                  clock_interval_out => clock_interval,
                  sync_in => sync (3),
                  sync_out => sync (4),
                  spdif_clock_strobe_out => rg_strobe);

    cmp : entity compressor
        port map (clock_in => clock_in,
                  sync_in => sync (4),
                  sync_out => sync (5),
                  peak_level_out => peak_level,
                  volume_in => volume,
                  ready_out => open,
                  fifo_error_out => cmp_fifo_error,
                  over_error_out => cmp_over_error,
                  compressor_enable_in => cmp_enable,
                  delay_bypass_in => cmp_delay_bypass,
                  data_in => raw_data (27 downto 12),
                  left_strobe_in => raw_left_strobe,
                  right_strobe_in => raw_right_strobe,
                  data_out => cmp_data (27 downto 12),
                  left_strobe_out => cmp_left_strobe,
                  right_strobe_out => cmp_right_strobe);

    cmp_data (31 downto 28) <= (others => '0');
    cmp_data (11 downto 0) <= (others => '0');

    process (adjust_1, adjust_2, mode_select)
    begin
        -- Compressor is disabled in certain modes
        cmp_enable <= '1';
        case mode_select is
            when PASSTHROUGH | ATTENUATE_2 | DBG_VERSION =>
                cmp_enable <= '0';
            when others =>
                null;
        end case;

        -- Delay can be disabled in certain modes
        cmp_delay_bypass <= '0';
        case mode_select is
            when PASSTHROUGH | COMPRESS_VIDEO | ATTENUATE_2 | DBG_VERSION =>
                cmp_delay_bypass <= '1';
            when others =>
                null;
        end case;

        -- Volume is not 1.0 in certain modes
        volume <= (others => '0');
        case mode_select is
            when COMPRESS_1 =>
                -- volume from adjuster 1, range is [0.0, 1.0)
                volume (volume'Left - 1 downto 0) <= adjust_1;
            when ATTENUATE_2 | COMPRESS_2 | COMPRESS_VIDEO =>
                -- volume from adjuster 2, range is [0.0, 1.0)
                volume (volume'Left - 1 downto 0) <= adjust_2;
            when others =>
                -- volume is 1.0
                volume (volume'Left) <= '1';
        end case;
    end process;

    ce : entity combined_encoder
        port map (clock_in => clock_in,
                  sync_in => sync (5),
                  sync_out => sync (6),
                  preemph_in => preemph,
                  left_strobe_in => cmp_left_strobe,
                  right_strobe_in => cmp_right_strobe,
                  error_out => oe_error,
                  spdif_clock_strobe_in => rg_strobe,
                  data_out => encoded_spdif,
                  data_in => cmp_data);

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if mode_select = mode_definitions.PASSTHROUGH then
                -- passthrough mode
                spdif_tx_out <= not spdif_rx_in;
            else
                -- via encoder
                spdif_tx_out <= encoded_spdif;
            end if;
        end if;
    end process;

    -- COM filter
    ifu : entity comfilter.comfilter_main
        port map (clock_in => clock_in,
                reset_in => reset,
                audio_strobe_in => raw_left_strobe,
                audio_data_in => raw_data (27 downto 12),
                debug_serial_out => com_serial_out,
                strobe_out => com_strobe,
                data_out => com_data);

    com_adjust_1_set <= com_strobe when (com_data (15 downto 14) = "10") else '0';
    com_adjust_2_set <= com_strobe when (com_data (15 downto 14) = "11") else '0';

    m : entity matcher
        port map (data_in => raw_data,
                  left_strobe_in => raw_left_strobe,
                  right_strobe_in => raw_right_strobe,
                  sync_in => sync (3),
                  sync_out => matcher_sync,
                  sample_rate_out => sample_rate,
                  clock => clock_in);

    raw_left : entity vu_meter 
        port map (clock => clock_in,
                  meter_out => raw_left_meter,
                  strobe_in => raw_left_strobe,
                  sync_in => sync (3),
                  data_in => raw_data (27 downto 19));

    raw_right : entity vu_meter 
        port map (clock => clock_in,
                  meter_out => raw_right_meter,
                  strobe_in => raw_right_strobe,
                  sync_in => sync (3),
                  data_in => raw_data (27 downto 19));

    cmp_left : entity vu_meter 
        port map (clock => clock_in,
                  meter_out => cmp_left_meter,
                  strobe_in => cmp_left_strobe,
                  sync_in => sync (6),
                  data_in => cmp_data (27 downto 19));

    cmp_right : entity vu_meter 
        port map (clock => clock_in,
                  meter_out => cmp_right_meter,
                  strobe_in => cmp_right_strobe,
                  sync_in => sync (6),
                  data_in => cmp_data (27 downto 19));

    display : entity mode_display
        port map (clock_in => clock_in,
                  pulse_100hz_in => pulse_100hz,
                  reset_in => reset,

                  -- mode select
                  mode_strobe_in => mode_strobe,
                  mode_select_in => mode_select,
  
                  -- shown in all modes
                  raw_meter_left_in => raw_left_meter,
                  raw_meter_right_in => raw_right_meter,

                  -- shown in compressor modes
                  cmp_meter_left_in => cmp_left_meter,
                  cmp_meter_right_in => cmp_right_meter,

                  -- shown in debug modes
                  sample_rate_in => sample_rate,
                  matcher_sync_in => matcher_sync,
                  single_time_in => single_time,
                  all_sync_in => sync,
                  clock_interval_in => clock_interval,
                  subcode_in => subcode,
                  peak_level_in => peak_level,
                  adjust_1_in => adjust_1,
                  adjust_2_in => adjust_2,
                  oe_error_in => oe_error,
                  adc_error_in => adc_error,
                  cmp_fifo_error_in => cmp_fifo_error,
                  cmp_over_error_in => cmp_over_error,
                  reset_error_in => reset_error,

                  -- LED outputs
                  lcols_out => lcols_out,
                  lrows_out => lrows_out);

    adc : entity adc_driver
        generic map (clock_frequency => clock_frequency)
        port map (clock_in => clock_in,
                  reset_in => reset,
                  pulse_100hz_in => pulse_100hz,
                  tx_to_pic => tx_to_pic_out,
                  rx_from_pic => rx_from_pic_in,
                  enable_poll_in => adc_enable_poll,
                  error_out => adc_error,
                  adjust_1_out => adjust_1,
                  adjust_2_out => adjust_2,
                  com_adjust_value_in => com_data (9 downto 0),
                  com_adjust_1_set_in => com_adjust_1_set,
                  com_adjust_2_set_in => com_adjust_2_set,
                  adjust_1a_p52 => adjust_1a_out,
                  adjust_1b_p50 => adjust_1b_out,
                  adjust_2a_p47 => adjust_2a_out,
                  adjust_2b_p45 => adjust_2b_out);

    com_rot : block
        signal com_button_command       : std_logic := '0';
        signal com_preemph_set          : std_logic := '0';
        signal com_mode_set             : std_logic := '0';
        signal com_mode_clear           : std_logic := '0';
        signal com_reset_error_button   : std_logic := '0';

        subtype t_com_auto_reset_counter is unsigned (6 downto 0);
        signal com_auto_reset_counter   : t_com_auto_reset_counter := (others => '1');
        constant com_auto_reset_end     : t_com_auto_reset_counter := (others => '0');
        constant com_auto_reset_trigger : t_com_auto_reset_counter := (0 => '1', others => '0');
    begin
        com_button_command <= com_strobe when (com_data (15 downto 14) = "01") else '0';
        com_preemph_set <= com_button_command and com_data (7);
        com_mode_set <= com_button_command and com_data (2);
        com_reset_error_button <= com_button_command and com_data (0);

        adc_enable_poll <= (not button_c11_in) or com_mode_clear;
        reset_error <= (not button_c6_in) or com_reset_error_button;

        -- The pre-emphasis register can be set via com
        preemph_register : process (clock_in)
        begin
            if clock_in'event and clock_in = '1' then
                if com_mode_clear = '1' then
                    preemph <= '0';
                elsif com_preemph_set = '1' then
                    preemph <= com_data (6);
                end if;
            end if;
        end process preemph_register;

        -- Any special settings provided via com are lost if desynced for more than 1270 ms,
        -- or if bit 1 is asserted, or on system reset
        com_reset : process (clock_in)
        begin
            if clock_in'event and clock_in = '1' then
                com_mode_clear <= (com_button_command and com_data (1)) or reset;
                if reset = '1' or sync (6) = '1' then
                    com_auto_reset_counter <= (others => '1');
                elsif pulse_100hz = '1' then
                    if com_auto_reset_counter = com_auto_reset_trigger then
                        com_mode_clear <= '1';
                    end if;
                    if com_auto_reset_counter /= com_auto_reset_end then
                        com_auto_reset_counter <= com_auto_reset_counter - 1;
                    end if;
                end if;
            end if;
        end process com_reset;

        rot : entity rotary_switch
            port map (clock_in => clock_in,
                      reset_in => reset,
                      pulse_100hz_in => pulse_100hz,
                      rotary_024 => rotary_024_in,
                      rotary_01 => rotary_01_in,
                      rotary_23 => rotary_23_in,
                      left_button => button_a11_in,
                      right_button => button_a5_in,
                      strobe_out => mode_strobe,
                      value_out => mode_select,
                      com_mode_value_in => com_data (6 downto 3),
                      com_mode_set_in => com_mode_set,
                      com_mode_clear_in => com_mode_clear);
    end block com_rot;

    -- 100 Hz pulse generator drives various UI tasks and timers
    pulse_100hz_gen : entity pulse_gen
        generic map (clock_frequency => clock_frequency,
                     pulse_frequency => 100.0)
        port map (clock_in => clock_in,
                  pulse_out => pulse_100hz);

    -- reset generator
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if reset_counter /= max_reset_counter and pulse_100hz = '1' then
                reset_counter <= reset_counter + 1;
            end if;
            reset <= '1';
            if reset_counter = max_reset_counter then
                reset <= '0';
            end if;
        end if;
    end process;

end structural;

