
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
    signal packet          : std_logic_vector (31 downto 0) := (others => '0');

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

        function conv (x : std_logic) return Integer is
        begin
            if x = '1' then
                return 1;
            else
                return 0;
            end if;
        end conv;
    begin
        wait until clock'event and clock = '1';
        while done = '0' loop
            if packet_reset = '1' then
                for i in packet'Left downto 0 loop
                    write (l, conv (packet (i)));
                end loop;
                writeline (output, l);
                packet <= (others => '0');
            elsif packet_shift = '1' then
                packet (packet'Left downto 1) <= packet (packet'Left - 1 downto 0);
                packet (0) <= packet_data;
            end if;
            wait until clock'event and clock = '1';
        end loop;
        wait;
    end process printer;

end structural;

