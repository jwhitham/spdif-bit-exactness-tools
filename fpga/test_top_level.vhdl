
library ieee;
use ieee.std_logic_1164.all;

use std.textio.all;

entity test_top_level is
end test_top_level;

architecture structural of test_top_level is

    signal single_pulse    : std_logic := '0';
    signal double_pulse    : std_logic := '0';
    signal triple_pulse    : std_logic := '0';
    signal clock           : std_logic := '0';
    signal done            : std_logic := '0';
    signal data            : std_logic := '0';

    component test_signal_generator is
        port (
            clock       : out std_logic;
            done        : out std_logic;
            data        : out std_logic
        );
    end component test_signal_generator;

    component input_decoder is
        port (
            data_in         : in std_logic;
            single_pulse    : out std_logic;
            double_pulse    : out std_logic;
            triple_pulse    : out std_logic;
            clock           : in std_logic
        );
    end component input_decoder;

begin
    test_signal_gen : test_signal_generator
        port map (data => data, clock => clock);

    input_dec : input_decoder
        port map (clock => clock, data_in => data,
                  single_pulse => single_pulse,
                  double_pulse => double_pulse,
                  triple_pulse => triple_pulse);

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
        while done = '0' loop
            wait until clock'event;
            if clock = '1' then
                write (l, conv (data));
                write (l, string'(" --> "));
                write (l, conv (single_pulse));
                write (l, string'(" "));
                write (l, conv (double_pulse));
                write (l, string'(" "));
                write (l, conv (triple_pulse));
                writeline (output, l);
            end if;
        end loop;
        wait;
    end process printer;

end structural;

