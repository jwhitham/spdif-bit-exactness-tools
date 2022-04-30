
library ieee;
use ieee.std_logic_1164.all;

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
    begin
        wait until done = '1';
        wait;
    end process printer;

end structural;

