
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spdif_meter_main is
    port (
        clock_in        : in std_logic;
        raw_data_in     : in std_logic;
        raw_data_out    : out std_logic;
        btn_nw          : in std_logic;
        btn_ne          : in std_logic;
        btn_se          : in std_logic;
        btn_sw          : in std_logic;
        lcols_out       : out std_logic_vector (3 downto 0) := "0000";
        lrows_out       : out std_logic_vector (7 downto 0) := "00000000";
        clock_out       : out std_logic := '0'
    );
end spdif_meter_main;

architecture structural of spdif_meter_main is

    constant num_syncs : Natural := 8;

    signal pulse_length    : std_logic_vector (1 downto 0) := "00";
    signal packet_data     : std_logic := '0';
    signal packet_shift    : std_logic := '0';
    signal packet_start    : std_logic := '0';
    signal sync            : std_logic_vector (num_syncs downto 1) := (others => '0');
    signal single_time     : std_logic_vector (7 downto 0) := (others => '0');
    signal sample_rate     : std_logic_vector (15 downto 0) := (others => '0');
    signal matcher_sync    : std_logic_vector (1 downto 0) := "00";
    signal left_strobe     : std_logic := '0';
    signal right_strobe    : std_logic := '0';
    signal rg_strobe       : std_logic := '0';
    signal ce_packet_data  : std_logic := '0';
    signal ce_packet_shift : std_logic := '0';
    signal ce_packet_start : std_logic := '0';
    signal pe_pulse_length : std_logic_vector (1 downto 0) := "00";
    signal preemph         : std_logic := '0';
    signal oe_out          : std_logic := '0';

    subtype t_data is std_logic_vector (31 downto 0);
    signal data            : t_data := (others => '0');
    signal data2           : t_data := (others => '0');

    subtype t_leds is std_logic_vector (7 downto 0);
    signal leds3           : t_leds := (others => '0');
    signal leds4           : t_leds := (others => '0');
    signal left_meter      : t_leds := (others => '0');
    signal right_meter     : t_leds := (others => '0');

    subtype t_sync_counter is unsigned (23 downto 0);
    type t_sync_counters is array (1 to num_syncs) of t_sync_counter;

    signal sync_counter    : t_sync_counters := (others => (others => '0'));
    constant max_counter   : t_sync_counter := (others => '1');

begin
    dec1 : entity input_decoder
        port map (clock_in => clock_in, data_in => raw_data_in,
                  sync_out => sync (1), single_time_out => single_time,
                  pulse_length_out => pulse_length);

    dec2 : entity packet_decoder
        port map (clock => clock_in,
                  pulse_length_in => pulse_length,
                  sync_in => sync (1),
                  sync_out => sync (2),
                  data_out => packet_data,
                  start_out => packet_start,
                  shift_out => packet_shift);

    dec3 : entity channel_decoder 
        port map (clock => clock_in,
                  data_in => packet_data,
                  shift_in => packet_shift,
                  start_in => packet_start,
                  sync_in => sync (2),
                  sync_out => sync (3),
                  data_out => data,
                  left_strobe_out => left_strobe,
                  right_strobe_out => right_strobe);
    m : entity matcher
        port map (data_in => data,
                  left_strobe_in => left_strobe,
                  right_strobe_in => right_strobe,
                  sync_in => sync (3),
                  sync_out => matcher_sync,
                  sample_rate_out => sample_rate,
                  clock => clock_in);

    rg : entity clock_regenerator
        port map (clock_in => clock_in,
                  pulse_length_in => pulse_length,
                  sync_in => sync (3),
                  sync_out => sync (5),
                  strobe_out => rg_strobe);

    ce : entity channel_encoder
        port map (clock => clock_in,
                  sync_in => sync (5),
                  sync_out => sync (6),
                  data_out => ce_packet_data,
                  start_out => ce_packet_start,
                  shift_out => ce_packet_shift,
                  preemph_in => preemph,
                  data_in => data2,
                  left_strobe_in => left_strobe,
                  right_strobe_in => right_strobe);

    -- The SW and SE buttons can divide the volume by 1, 2, 4, or 8.
    process (btn_se, btn_sw, data) is
        variable fade : std_logic_vector (1 downto 0);
    begin
        fade (1) := not btn_sw;
        fade (0) := not btn_se;
        data2 <= data;
        case fade is
            when "01" =>
                data2 (27 downto 27) <= (others => data (27));
                data2 (26 downto 4) <= data (27 downto 5);
            when "10" =>
                data2 (27 downto 26) <= (others => data (27));
                data2 (25 downto 4) <= data (27 downto 6);
            when "11" =>
                data2 (27 downto 25) <= (others => data (27));
                data2 (24 downto 4) <= data (27 downto 7);
            when others =>
                null;
        end case;
    end process;

    -- The NW button enables the pre-emphasis bit
    preemph <= not btn_nw;

    pe : entity packet_encoder
        port map (clock => clock_in,
                  pulse_length_out => pe_pulse_length,
                  sync_in => sync (6),
                  sync_out => sync (7),
                  data_in => ce_packet_data,
                  start_in => ce_packet_start,
                  shift_in => ce_packet_shift);

    oe : entity output_encoder
        port map (clock_in => clock_in,
                  pulse_length_in => pe_pulse_length,
                  sync_in => sync (7),
                  sync_out => sync (8),
                  error_out => open,
                  strobe_in => rg_strobe,
                  data_out => oe_out);

    leds : entity led_scan
        port map (clock => clock_in,
                  leds1_in => left_meter,
                  leds2_in => right_meter,
                  leds3_in => leds3,
                  leds4_in => leds4,
                  lrows_out => lrows_out,
                  lcols_out => lcols_out);

    left : entity vu_meter 
        port map (clock => clock_in,
                  meter_out => left_meter,
                  strobe_in => left_strobe,
                  data_in => data (27 downto 19));

    right : entity vu_meter 
        port map (clock => clock_in,
                  meter_out => right_meter,
                  strobe_in => right_strobe,
                  data_in => data (27 downto 19));

    sync (4) <= '1' when matcher_sync /= "00" else '0';

    sync_leds : for index in 1 to num_syncs generate
        process (clock_in)
        begin
            if clock_in = '1' and clock_in'event then
                leds4 (index - 1) <= '0';
                if sync (index) = '0' then
                    sync_counter (index) <= (others => '0');
                elsif sync_counter (index) /= max_counter then
                    sync_counter (index) <= sync_counter (index) + 1;
                else
                    leds4 (index - 1) <= '1';
                end if;
            end if;
        end process;
    end generate sync_leds;

    process (clock_in)
    begin
        if clock_in = '1' and clock_in'event then
            if matcher_sync /= "00" then
                leds3 (7 downto 4) <= sample_rate (7 downto 4);
                leds3 (3 downto 2) <= "00";
                leds3 (1 downto 0) <= matcher_sync;
            else
                leds3 <= single_time;
            end if;
            -- The NE button enables a direct passthrough.
            if btn_ne = '0' then
                raw_data_out <= raw_data_in;
            else
                raw_data_out <= oe_out;
            end if;
        end if;
    end process;

end structural;

