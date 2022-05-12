
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
    signal sync1_counter   : unsigned (0 to 23) := (others => '0');
    signal sync2_counter   : unsigned (0 to 23) := (others => '0');
    signal sync3_counter   : unsigned (0 to 23) := (others => '0');
    signal test_counter    : unsigned (0 to 23) := (others => '0');
    constant max_counter   : unsigned (0 to 23) := (others => '1');
    signal test_flip       : std_logic := '0';

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

    component vu_meter
        port (
            data_in         : in std_logic_vector (8 downto 0);
            meter_out       : out std_logic_vector (7 downto 0) := "00000000";
            clock           : in std_logic);
    end component vu_meter;

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

    process (clock_in)
    begin
        if clock_in = '1' and clock_in'event then
            leds4 <= (others => '0');
            if sync1 = '0' then
                sync1_counter <= 0;
            elsif sync1_counter /= max_counter then
                sync1_counter <= sync1_counter + 1;
            else
                leds4 (1) <= '1';
            end if;
            if sync2 = '0' then
                sync2_counter <= 0;
            elsif sync2_counter /= max_counter then
                sync2_counter <= sync2_counter + 1;
            else
                leds4 (2) <= '1';
            end if;
            if sync3 = '0' then
                sync3_counter <= 0;
            elsif sync3_counter /= max_counter then
                sync3_counter <= sync3_counter + 1;
            else
                leds4 (3) <= '1';
            end if;
            if test_counter /= max_counter then
                test_counter <= test_counter + 1;
            else
                test_counter <= 0;
                test_flip <= not test_flip;
            end if;
            leds4 (4) <= test_flip;
            leds4 (0) <= test_flip;
            raw_data_out <= raw_data_in;
        end if;
    end process;

end structural;

