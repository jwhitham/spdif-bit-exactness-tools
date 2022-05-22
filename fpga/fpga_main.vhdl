
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
        clock_out       : out std_logic := '0';
        sync1_out       : out std_logic := '0';
        sync2_out       : out std_logic := '0';
        sync3_out       : out std_logic := '0';
        sync4_out       : out std_logic := '0'
    );
end fpga_main;

architecture structural of fpga_main is

    signal pulse_length    : std_logic_vector (1 downto 0) := "00";
    signal packet_data     : std_logic := '0';
    signal packet_shift    : std_logic := '0';
    signal packet_start    : std_logic := '0';
    signal sync1           : std_logic := '0';
    signal sync2           : std_logic := '0';
    signal sync3           : std_logic := '0';
    signal sync4           : std_logic_vector (1 downto 0) := "00";
    signal single_time     : std_logic_vector (7 downto 0) := (others => '0');
    signal sample_rate     : std_logic_vector (15 downto 0) := (others => '0');
    signal left_data       : std_logic_vector (31 downto 0) := (others => '0');
    signal left_strobe     : std_logic := '0';
    signal right_data      : std_logic_vector (31 downto 0) := (others => '0');
    signal right_strobe    : std_logic := '0';
    signal leds3           : std_logic_vector (7 downto 0) := (others => '0');
    signal leds4           : std_logic_vector (7 downto 0) := (others => '0');
    signal left_meter      : std_logic_vector (7 downto 0) := (others => '0');
    signal right_meter     : std_logic_vector (7 downto 0) := (others => '0');
    signal sync1_counter   : unsigned (0 to 23) := (others => '0');
    signal sync2_counter   : unsigned (0 to 23) := (others => '0');
    signal sync3_counter   : unsigned (0 to 23) := (others => '0');
    signal sync4_counter   : unsigned (0 to 23) := (others => '0');
    constant max_counter   : unsigned (0 to 23) := (others => '1');

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
            clock_out        : out std_logic;
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
            sync_out        : out std_logic_vector (1 downto 0) := "00";
            sample_rate_out : out std_logic_vector (15 downto 0) := (others => '0');
            clock           : in std_logic
        );
    end component matcher;

begin
    dec1 : input_decoder
        port map (clock_in => clock_in, data_in => raw_data_in,
                  clock_out => clock_out,
                  sync_out => sync1, single_time_out => single_time,
                  pulse_length_out => pulse_length);

    dec2 : packet_decoder
        port map (clock => clock_in,
                  pulse_length_in => pulse_length,
                  sync_in => sync1,
                  sync_out => sync2,
                  data_out => packet_data,
                  start_out => packet_start,
                  shift_out => packet_shift);

    dec3 : channel_decoder 
        port map (clock => clock_in,
                  data_in => packet_data,
                  shift_in => packet_shift,
                  start_in => packet_start,
                  sync_in => sync2,
                  sync_out => sync3,
                  left_data_out => left_data,
                  left_strobe_out => left_strobe,
                  right_data_out => right_data,
                  right_strobe_out => right_strobe);
    m : matcher
        port map (left_data_in => left_data,
                  left_strobe_in => left_strobe,
                  right_data_in => right_data,
                  right_strobe_in => right_strobe,
                  sync_out => sync4,
                  sample_rate_out => sample_rate,
                  clock => clock_in);

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

    sync1_out <= sync1;
    sync2_out <= sync2;
    sync3_out <= sync3;
    sync4_out <= sync4 (1) or sync4 (0);

    process (clock_in)
    begin
        if clock_in = '1' and clock_in'event then
            leds4 <= (others => '0');
            leds3 <= single_time;
            if sync1 = '0' then
                sync1_counter <= (others => '0');
            elsif sync1_counter /= max_counter then
                sync1_counter <= sync1_counter + 1;
            else
                leds4 (1) <= '1';
            end if;
            if sync2 = '0' then
                sync2_counter <= (others => '0');
            elsif sync2_counter /= max_counter then
                sync2_counter <= sync2_counter + 1;
            else
                leds4 (2) <= '1';
            end if;
            if sync3 = '0' then
                sync3_counter <= (others => '0');
            elsif sync3_counter /= max_counter then
                sync3_counter <= sync3_counter + 1;
            else
                leds4 (3) <= '1';
            end if;
            if sync4 = "00" then
                sync4_counter <= (others => '0');
            elsif sync4_counter /= max_counter then
                sync4_counter <= sync4_counter + 1;
            else
                leds4 (4) <= sync4 (0);
                leds4 (5) <= sync4 (1);
                leds3 <= sample_rate (7 downto 0);
            end if;
            raw_data_out <= raw_data_in;
        end if;
    end process;

end structural;

