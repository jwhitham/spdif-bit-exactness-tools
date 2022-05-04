
library ieee;
use ieee.std_logic_1164.all;

entity fpga_main is
    port (
        clock_in        : in std_logic;
        raw_data_in     : in std_logic;
        lcols_out       : out std_logic_vector (3 downto 0) := "0000";
        lrows_out       : out std_logic_vector (7 downto 0) := "00000000";
        sync1_out       : out std_logic := '0';
        sync2_out       : out std_logic := '0';
        sync3_out       : out std_logic := '0'
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
    signal double_time     : std_logic_vector (7 downto 0) := (others => '0');
    signal left_data       : std_logic_vector (31 downto 0) := (others => '0');
    signal left_strobe     : std_logic := '0';
    signal right_data      : std_logic_vector (31 downto 0) := (others => '0');
    signal right_strobe    : std_logic := '0';
    signal leds4           : std_logic_vector (7 downto 0) := (others => '0');
    signal left_meter      : std_logic_vector (7 downto 0) := (others => '0');
    signal right_meter     : std_logic_vector (7 downto 0) := (others => '0');

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
            double_time_out  : out std_logic_vector (7 downto 0);
            sync_out         : out std_logic;
            clock            : in std_logic
        );
    end component input_decoder;

    component packet_decoder is
        port (
            pulse_length_in : in std_logic_vector (1 downto 0);
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

begin
    dec1 : input_decoder
        port map (clock => clock_in, data_in => raw_data_in,
                  sync_out => sync1, double_time_out => double_time,
                  pulse_length_out => pulse_length);

    dec2 : packet_decoder
        port map (clock => clock_in,
                  pulse_length_in => pulse_length,
                  sync_out => sync2,
                  data_out => packet_data,
                  start_out => packet_start,
                  shift_out => packet_shift);

    dec3 : channel_decoder 
        port map (clock => clock_in,
                  data_in => packet_data,
                  shift_in => packet_shift,
                  start_in => packet_start,
                  sync_out => sync3,
                  left_data_out => left_data,
                  left_strobe_out => left_strobe,
                  right_data_out => right_data,
                  right_strobe_out => right_strobe);

    leds : led_scan
        port map (clock => clock_in,
                  leds1_in => left_meter,
                  leds2_in => right_meter,
                  leds3_in => double_time,
                  leds4_in => leds4,
                  lrows_out => lrows_out,
                  lcols_out => lcols_out);

    sync1_out <= sync1;
    sync2_out <= sync2;
    sync3_out <= sync3;

    leds4 (0) <= sync1;
    leds4 (1) <= sync2;
    leds4 (2) <= sync3;
    leds4 (3) <= left_strobe;
    leds4 (4) <= right_strobe;
    leds4 (5) <= '0';
    leds4 (6) <= pulse_length (0);
    leds4 (7) <= pulse_length (1);

    left_meter <= left_data (26 downto 19)
                    when left_data (27) = '0' else (not left_data (26 downto 19));
    right_meter <= right_data (26 downto 19)
                    when right_data (27) = '0' else (not right_data (26 downto 19));

end structural;

