
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fpga_main is
    port (
        clock_in        : in std_logic;
        raw_data_in     : in std_logic;
        raw_data_out    : out std_logic;
        lcols_out       : out std_logic_vector (3 downto 0) := "0000";
        lrows_out       : out std_logic_vector (7 downto 0) := "00000000";
        clock_out       : out std_logic := '0'
    );
end fpga_main;

architecture structural of fpga_main is

    signal pulse_length    : std_logic_vector (1 downto 0) := "00";
    signal packet_data     : std_logic := '0';
    signal packet_shift    : std_logic := '0';
    signal packet_start    : std_logic := '0';
    signal sync            : std_logic_vector (5 downto 1) := (others => '0');
    signal single_time     : std_logic_vector (7 downto 0) := (others => '0');
    signal sample_rate     : std_logic_vector (15 downto 0) := (others => '0');
    signal matcher_sync    : std_logic_vector (1 downto 0) := "00";
    signal left_strobe     : std_logic := '0';
    signal right_strobe    : std_logic := '0';

    subtype t_data is std_logic_vector (31 downto 0);
    signal left_data       : t_data := (others => '0');
    signal right_data      : t_data := (others => '0');

    subtype t_leds is std_logic_vector (7 downto 0);
    signal leds3           : t_leds := (others => '0');
    signal leds4           : t_leds := (others => '0');
    signal left_meter      : t_leds := (others => '0');
    signal right_meter     : t_leds := (others => '0');

    subtype t_sync_counter is unsigned (23 downto 0);
    type t_sync_counters is array (1 to 5) of t_sync_counter;

    signal sync_counter    : t_sync_counters := (others => (others => '0'));
    constant max_counter   : t_sync_counter := (others => '1');

    component test_signal_generator is
        port (
            done_out        : out std_logic;
            clock_out       : out std_logic;
            raw_data_out    : out std_logic
        );
    end component test_signal_generator;

    component input_decoder is
        port (
            data_in          : in std_logic;
            pulse_length_out : out std_logic_vector (1 downto 0);
            single_time_out  : out std_logic_vector (7 downto 0);
            sync_out         : out std_logic;
            clock_in         : in std_logic
        );
    end component input_decoder;

    component packet_decoder is
        port (
            pulse_length_in : in std_logic_vector (1 downto 0);
            sync_in         : in std_logic;
            data_out        : out std_logic;
            shift_out       : out std_logic;
            start_out       : out std_logic;
            sync_out        : out std_logic;
            clock           : in std_logic
        );
    end component packet_decoder;

    component channel_decoder is
        port (
            data_in         : in std_logic;
            shift_in        : in std_logic;
            start_in        : in std_logic;
            sync_in         : in std_logic;
            left_data_out   : out std_logic_vector (31 downto 0);
            left_strobe_out : out std_logic;
            right_data_out  : out std_logic_vector (31 downto 0);
            right_strobe_out: out std_logic;
            sync_out        : out std_logic;
            clock           : in std_logic
        );
    end component channel_decoder;

    component led_scan is
        port (
            leds1_in        : in std_logic_vector (7 downto 0);
            leds2_in        : in std_logic_vector (7 downto 0);
            leds3_in        : in std_logic_vector (7 downto 0);
            leds4_in        : in std_logic_vector (7 downto 0);
            lcols_out       : out std_logic_vector (3 downto 0) := "0000";
            lrows_out       : out std_logic_vector (7 downto 0) := "00000000";
            clock           : in std_logic);
    end component led_scan;

    component vu_meter
        port (
            data_in         : in std_logic_vector (8 downto 0);
            meter_out       : out std_logic_vector (7 downto 0) := "00000000";
            clock           : in std_logic);
    end component vu_meter;

    component matcher is
        port (
            left_data_in    : in std_logic_vector (31 downto 0);
            left_strobe_in  : in std_logic;
            right_data_in   : in std_logic_vector (31 downto 0);
            right_strobe_in : in std_logic;
            sync_in         : in std_logic;
            sync_out        : out std_logic_vector (1 downto 0) := "00";
            sample_rate_out : out std_logic_vector (15 downto 0) := (others => '0');
            clock           : in std_logic
        );
    end component matcher;

    component regenerator is
        port (
            pulse_length_in  : in std_logic_vector (1 downto 0) := "00";
            sync_in          : in std_logic;
            sync_out         : out std_logic := '0';
            clock_in         : in std_logic;
            clock_out        : out std_logic := '0'
        );
    end component regenerator;
begin
    dec1 : input_decoder
        port map (clock_in => clock_in, data_in => raw_data_in,
                  sync_out => sync (1), single_time_out => single_time,
                  pulse_length_out => pulse_length);

    dec2 : packet_decoder
        port map (clock => clock_in,
                  pulse_length_in => pulse_length,
                  sync_in => sync (1),
                  sync_out => sync (2),
                  data_out => packet_data,
                  start_out => packet_start,
                  shift_out => packet_shift);

    dec3 : channel_decoder 
        port map (clock => clock_in,
                  data_in => packet_data,
                  shift_in => packet_shift,
                  start_in => packet_start,
                  sync_in => sync (2),
                  sync_out => sync (3),
                  left_data_out => left_data,
                  left_strobe_out => left_strobe,
                  right_data_out => right_data,
                  right_strobe_out => right_strobe);
    m : matcher
        port map (left_data_in => left_data,
                  left_strobe_in => left_strobe,
                  right_data_in => right_data,
                  right_strobe_in => right_strobe,
                  sync_in => sync (3),
                  sync_out => matcher_sync,
                  sample_rate_out => sample_rate,
                  clock => clock_in);

    rg : regenerator
        port map (clock_in => clock_in,
                  pulse_length_in => pulse_length,
                  sync_in => sync (3),
                  sync_out => sync (5),
                  clock_out => clock_out);

    leds : led_scan
        port map (clock => clock_in,
                  leds1_in => left_meter,
                  leds2_in => right_meter,
                  leds3_in => leds3,
                  leds4_in => leds4,
                  lrows_out => lrows_out,
                  lcols_out => lcols_out);

    left : vu_meter 
        port map (clock => clock_in,
                  meter_out => left_meter,
                  data_in => left_data (27 downto 19));

    right : vu_meter 
        port map (clock => clock_in,
                  meter_out => right_meter,
                  data_in => right_data (27 downto 19));

    sync (4) <= '1' when matcher_sync /= "00" else '0';

    sync_leds : for index in 1 to 5 generate
        process (clock_in)
        begin
            if clock_in = '1' and clock_in'event then
                leds4 (index) <= '0';
                if sync (index) = '0' then
                    sync_counter (index) <= (others => '0');
                elsif sync_counter (index) /= max_counter then
                    sync_counter (index) <= sync_counter (index) + 1;
                else
                    leds4 (index) <= '1';
                end if;
            end if;
        end process;
    end generate sync_leds;

    leds4 (0) <= '0';
    leds4 (7 downto 6) <= "00";

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
            raw_data_out <= raw_data_in;
        end if;
    end process;

end structural;

