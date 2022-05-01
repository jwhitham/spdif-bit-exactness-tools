
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
    signal packet_reset    : std_logic := '0';
    signal clock           : std_logic := '0';
    signal raw_data        : std_logic := '0';
    signal done            : std_logic := '0';
    signal packet          : std_logic_vector (63 downto 0) := (others => '0');

    component test_signal_generator is
        port (
            clock       : out std_logic;
            done        : out std_logic;
            data        : out std_logic
        );
    end component test_signal_generator;

    component input_decoder is
        port (
            data_in          : in std_logic;
            pulse_length_out : out std_logic_vector (1 downto 0);
            clock            : in std_logic
        );
    end component input_decoder;

    component packet_decoder is
        port (
            pulse_length_in : in std_logic_vector (1 downto 0);
            data_out        : out std_logic;
            shift_out       : out std_logic;
            reset_out       : out std_logic;
            clock           : in std_logic
        );
    end component packet_decoder;

begin
    test_signal_gen : test_signal_generator
        port map (data => raw_data, clock => clock, done => done);

    dec1 : input_decoder
        port map (clock => clock, data_in => raw_data,
                  pulse_length_out => pulse_length);

    dec2 : packet_decoder
        port map (clock => clock,
                  pulse_length_in => pulse_length,
                  data_out => packet_data,
                  shift_out => packet_shift,
                  reset_out => packet_reset);

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
        while done = '0' loop
            if packet_reset = '1' then
                if (packet (35 downto 32) = "0010" or packet (35 downto 32) = "1000")
                        and packet (3 downto 0) = "0100" then

                    -- left channel (B/M packet)
                    j := 28;
                    for i in 1 to 6 loop
                        j := j - 4;
                        write_hex (packet (j + 3 downto j));
                    end loop;
                    write (l, String'(" "));
                    -- right channel (W packet)
                    j := 60;
                    for i in 1 to 6 loop
                        j := j - 4;
                        write_hex (packet (j + 3 downto j));
                    end loop;
                    writeline (output, l);
                end if;
            elsif packet_shift = '1' then
                packet (packet'Left - 1 downto 0) <= packet (packet'Left downto 1);
                packet (packet'Left) <= packet_data;
            end if;
            wait until clock'event and clock = '1';
        end loop;
        wait;
    end process printer;

end structural;

