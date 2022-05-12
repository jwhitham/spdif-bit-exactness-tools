
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
    signal sync1           : std_logic := '0';
    signal sync2           : std_logic := '0';
    signal sync3           : std_logic := '0';
    signal single_time     : std_logic_vector (7 downto 0) := (others => '0');
    signal left_data       : std_logic_vector (31 downto 0) := (others => '0');
    signal left_strobe     : std_logic := '0';
    signal right_data      : std_logic_vector (31 downto 0) := (others => '0');
    signal right_strobe    : std_logic := '0';

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

begin
    test_signal_gen : test_signal_generator
        port map (raw_data_out => raw_data, done_out => done, clock_out => clock);

    dec1 : input_decoder
        port map (clock => clock, data_in => raw_data,
                  sync_out => sync1, single_time_out => single_time,
                  pulse_length_out => pulse_length);

    dec2 : packet_decoder
        port map (clock => clock,
                  pulse_length_in => pulse_length,
                  sync_out => sync2,
                  data_out => packet_data,
                  start_out => packet_start,
                  shift_out => packet_shift);

    dec3 : channel_decoder 
        port map (clock => clock,
                  data_in => packet_data,
                  shift_in => packet_shift,
                  start_in => packet_start,
                  sync_out => sync3,
                  left_data_out => left_data,
                  left_strobe_out => left_strobe,
                  right_data_out => right_data,
                  right_strobe_out => right_strobe);

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
            wait until sync1'event;
            if sync1 = '1' then
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
            wait until sync2'event;
            if sync2 = '1' then
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
            wait until sync3'event;
            if sync3 = '1' then
                write (l, String'("channel decoder synchronised"));
                writeline (output, l);
            else
                write (l, String'("channel decoder desynchronised"));
                writeline (output, l);
            end if;
        end loop;
    end process s3p;



    printer : process
        variable l : line;
        variable j : Integer;

        function conv (x : std_logic) return Integer is
        begin
            if x = '1' then
                return 1;
            else
                return 0;
            end if;
        end conv;

        procedure write_hex (x : std_logic_vector (3 downto 0)) is
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
        end write_hex;
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
                j := 28;
                for i in 1 to 6 loop
                    j := j - 4;
                    write_hex (left_data (j + 3 downto j));
                end loop;
                write (l, String'(" "));
                j := 28;
                for i in 1 to 6 loop
                    j := j - 4;
                    write_hex (right_data (j + 3 downto j));
                end loop;
                writeline (output, l);
            end if;
            wait until clock'event and clock = '1';
        end loop;
        wait;
    end process printer;

end structural;

