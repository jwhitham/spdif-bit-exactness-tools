
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_top_level is
end test_top_level;

architecture structural of test_top_level is

    signal pulse_length    : std_logic_vector (1 downto 0) := "00";
    signal packet_data     : std_logic := '0';
    signal packet_shift    : std_logic := '0';
    signal packet_start    : std_logic := '0';
    signal packet_channel  : std_logic_vector (1 downto 0) := "00";
    signal clock           : std_logic := '0';
    signal raw_data        : std_logic := '0';
    signal done            : std_logic := '0';
    signal sync            : std_logic_vector (6 downto 1) := (others => '0');
    signal sample_rate     : std_logic_vector (15 downto 0) := (others => '0');
    signal single_time     : std_logic_vector (7 downto 0) := (others => '0');
    signal left_data       : std_logic_vector (31 downto 0) := (others => '0');
    signal left_strobe     : std_logic := '0';
    signal right_data      : std_logic_vector (31 downto 0) := (others => '0');
    signal right_strobe    : std_logic := '0';
    signal r_clock         : std_logic := '0';

    signal uptime          : Integer := 0;
    signal start_of_r_sync : Integer := 0;
    signal count_r_clocks  : Integer := 0;

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
    test_signal_gen : test_signal_generator
        port map (raw_data_out => raw_data, done_out => done, clock_out => clock);

    dec1 : input_decoder
        port map (clock_in => clock, data_in => raw_data,
                  sync_out => sync (1), single_time_out => single_time,
                  pulse_length_out => pulse_length);

    dec2 : packet_decoder
        port map (clock => clock,
                  pulse_length_in => pulse_length,
                  sync_in => sync (1),
                  sync_out => sync (2),
                  data_out => packet_data,
                  start_out => packet_start,
                  shift_out => packet_shift);

    dec3 : channel_decoder 
        port map (clock => clock,
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
                  sync_out => sync (5 downto 4),
                  sample_rate_out => sample_rate,
                  clock => clock);

    rg : regenerator
        port map (clock_in => clock,
                  pulse_length_in => pulse_length,
                  sync_in => sync (3),
                  sync_out => sync (6),
                  clock_out => r_clock);

    t1p : process
        variable l : line;
    begin
        while done /= '1' loop
            wait until single_time'event;
            write (l, String'("input decoder single time = "));
            write (l, to_integer (unsigned (single_time)));
            writeline (output, l);
        end loop;
    end process t1p;

    s1p : process
        variable l : line;
    begin
        while done /= '1' loop
            wait until sync (1)'event;
            if sync (1) = '1' then
                write (l, String'("input decoder synchronised"));
                writeline (output, l);
            else
                write (l, String'("input decoder desynchronised"));
                writeline (output, l);
            end if;
        end loop;
    end process s1p;

    s2p : process
        variable l : line;
    begin
        while done /= '1' loop
            wait until sync (2)'event;
            if sync (2) = '1' then
                write (l, String'("packet decoder synchronised"));
                writeline (output, l);
            else
                write (l, String'("packet decoder desynchronised"));
                writeline (output, l);
            end if;
        end loop;
    end process s2p;

    s3p : process
        variable l : line;
    begin
        while done /= '1' loop
            wait until sync (3)'event;
            if sync (3) = '1' then
                write (l, String'("channel decoder synchronised"));
                writeline (output, l);
            else
                write (l, String'("channel decoder desynchronised"));
                writeline (output, l);
            end if;
        end loop;
    end process s3p;

    s4p : process
        variable l : line;
    begin
        while done /= '1' loop
            wait until sync (5 downto 4)'event;
            if sync (5 downto 4) /= "00" then
                write (l, String'("matcher synchronised: sample rate = "));
                write (l, to_integer (unsigned (sample_rate)) * 100);
                write (l, String'(" sync4 = "));
                write (l, to_integer (unsigned (sync (5 downto 4))));
                writeline (output, l);
            else
                write (l, String'("matcher desynchronised"));
                writeline (output, l);
            end if;
        end loop;
    end process s4p;

    tick_uptime : process
    begin
        while done /= '1' loop
            wait until clock'event or done = '1';
            uptime <= uptime + 1;
        end loop;
        wait;
    end process tick_uptime;

    check_regenerator : process
        variable l : line;
        variable delta : Integer;
    begin
        while done /= '1' loop
            wait until r_clock'event or sync (6)'event or done = '1';
            if sync (6)'event then
                if sync (6) = '0' then
                    if start_of_r_sync /= 0 then
                        delta := uptime - start_of_r_sync;
                        write (l, String'("regenerator desynchronised; "));
                        write (l, count_r_clocks);
                        write (l, String'(" r_clocks in "));
                        write (l, delta);
                        write (l, String'(" clocks"));
                        writeline (output, l);
                    end if;
                    start_of_r_sync <= 0;
                    count_r_clocks <= 0;
                else
                    write (l, String'("regenerator synchronised"));
                    writeline (output, l);
                    start_of_r_sync <= uptime;
                    count_r_clocks <= 0;
                end if;
            elsif sync (6) = '1' and r_clock'event and r_clock = '1' then
                count_r_clocks <= count_r_clocks + 1;
            end if;
        end loop;
        wait;
    end process check_regenerator;

    printer : process
        variable l : line;

        function conv (x : std_logic) return Integer is
        begin
            if x = '1' then
                return 1;
            else
                return 0;
            end if;
        end conv;

        procedure write_hex_nibble (x : std_logic_vector (3 downto 0)) is
        begin
            assert x (0) = '0' or x (0) = '1';
            assert x (1) = '0' or x (1) = '1';
            assert x (2) = '0' or x (2) = '1';
            assert x (3) = '0' or x (3) = '1';
            case to_integer (unsigned (x)) is
                when 10 => write (l, String'("a"));
                when 11 => write (l, String'("b"));
                when 12 => write (l, String'("c"));
                when 13 => write (l, String'("d"));
                when 14 => write (l, String'("e"));
                when 15 => write (l, String'("f"));
                when others => write (l, to_integer (unsigned (x)));
            end case;
        end write_hex_nibble;

        procedure write_hex_sample (x : std_logic_vector (23 downto 0)) is
            variable j : Integer;
        begin
            j := 20;
            for i in 1 to 6 loop
                write_hex_nibble (x (j + 3 downto j));
                j := j - 4;
            end loop;
        end write_hex_sample;
    begin
        wait until clock'event and clock = '1';
        assert raw_data = '0' or raw_data = '1';
        assert done = '0' or done = '1';
        assert pulse_length (0) = '0' or pulse_length (0) = '1';
        assert pulse_length (1) = '0' or pulse_length (1) = '1';
        assert packet_data = '0' or packet_data = '1';
        assert packet_start = '0' or packet_start = '1';
        assert packet_shift = '0' or packet_shift = '1';
        assert left_strobe = '0' or left_strobe = '1';
        assert right_strobe = '0' or right_strobe = '1';
        assert left_data (0) = '0' or left_data (0) = '1';
        assert right_data (0) = '0' or right_data (0) = '1';

        while done /= '1' loop
            if right_strobe = '1' then
                write_hex_sample (left_data (27 downto 4));
                write (l, String'(" "));
                write_hex_sample (right_data (27 downto 4));
                writeline (output, l);
            end if;
            wait until clock'event and clock = '1';
        end loop;
        wait;
    end process printer;

end structural;

