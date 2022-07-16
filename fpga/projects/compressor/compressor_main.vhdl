
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity compressor_main is
    port (
        clock_in        : in std_logic;
        raw_data_in     : in std_logic;
        cmp_data_out    : out std_logic := '0';
        lcols_out       : out std_logic_vector (3 downto 0) := "0000";
        lrows_out       : out std_logic_vector (7 downto 0) := "00000000";
        clock_out       : out std_logic := '0'
    );
end compressor_main;

architecture structural of compressor_main is

    signal preemph                  : std_logic := '0';
    signal sync                     : std_logic_vector (8 downto 1) := (others => '0');
    signal rg_strobe                : std_logic := '0';
    signal raw_packet_data          : std_logic := '0';
    signal raw_packet_shift         : std_logic := '0';
    signal raw_packet_start         : std_logic := '0';
    signal raw_left_strobe          : std_logic := '0';
    signal raw_right_strobe         : std_logic := '0';

    signal cmp_packet_data          : std_logic := '0';
    signal cmp_packet_shift         : std_logic := '0';
    signal cmp_packet_start         : std_logic := '0';
    signal cmp_left_strobe          : std_logic := '0';
    signal cmp_right_strobe         : std_logic := '0';

    subtype t_pulse_length is std_logic_vector (1 downto 0);
    signal raw_pulse_length         : t_pulse_length := "00";
    signal cmp_pulse_length         : t_pulse_length := "00";

    subtype t_leds is std_logic_vector (7 downto 0);
    signal raw_left_meter           : t_leds := (others => '0');
    signal raw_right_meter          : t_leds := (others => '0');
    signal cmp_left_meter           : t_leds := (others => '0');
    signal cmp_right_meter          : t_leds := (others => '0');

    subtype t_data is std_logic_vector (31 downto 0);
    signal raw_data                 : t_data := (others => '0');
    signal cmp_data                 : t_data := (others => '0');

begin
    dec1 : entity input_decoder
        port map (clock_in => clock_in, data_in => raw_data_in,
                  sync_out => sync (1), single_time_out => open,
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
                  left_strobe_out => raw_left_strobe,
                  right_strobe_out => raw_right_strobe);

    rg : entity clock_regenerator
        port map (clock_in => clock_in,
                  pulse_length_in => raw_pulse_length,
                  sync_in => sync (3),
                  sync_out => sync (4),
                  strobe_out => rg_strobe);

    cmp : entity compressor
        port map (clock_in => clock_in,
                  sync_in => sync (4),
                  sync_out => sync (5),
                  data_in => raw_data (27 downto 12),
                  left_strobe_in => raw_left_strobe,
                  right_strobe_in => raw_right_strobe,
                  data_out => cmp_data (27 downto 12),
                  left_strobe_out => cmp_left_strobe,
                  right_strobe_out => cmp_right_strobe);
    cmp_data (31 downto 28) <= (others => '0');
    cmp_data (11 downto 0) <= (others => '0');

    ce : entity channel_encoder
        port map (clock => clock_in,
                  sync_in => sync (5),
                  sync_out => sync (6),
                  data_out => cmp_packet_data,
                  start_out => cmp_packet_start,
                  shift_out => cmp_packet_shift,
                  preemph_in => preemph,
                  data_in => cmp_data,
                  left_strobe_in => cmp_left_strobe,
                  right_strobe_in => cmp_right_strobe);
    preemph <= '0';

    pe : entity packet_encoder
        port map (clock => clock_in,
                  pulse_length_out => cmp_pulse_length,
                  sync_in => sync (6),
                  sync_out => sync (7),
                  data_in => cmp_packet_data,
                  start_in => cmp_packet_start,
                  shift_in => cmp_packet_shift);

    oe : entity output_encoder
        port map (clock_in => clock_in,
                  pulse_length_in => cmp_pulse_length,
                  sync_in => sync (7),
                  sync_out => sync (8),
                  error_out => open,
                  strobe_in => rg_strobe,
                  data_out => cmp_data_out);

    leds : entity led_scan
        port map (clock => clock_in,
                  leds1_in => raw_left_meter,
                  leds2_in => raw_right_meter,
                  leds3_in => cmp_left_meter,
                  leds4_in => cmp_right_meter,
                  lrows_out => lrows_out,
                  lcols_out => lcols_out);

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
                  sync_in => sync (8),
                  data_in => cmp_data (27 downto 19));

    cmp_right : entity vu_meter 
        port map (clock => clock_in,
                  meter_out => cmp_right_meter,
                  strobe_in => cmp_right_strobe,
                  sync_in => sync (8),
                  data_in => cmp_data (27 downto 19));

end structural;

