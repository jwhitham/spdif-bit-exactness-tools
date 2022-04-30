
library ieee;
use ieee.std_logic_1164.all;

entity test_top_level is
end test_top_level;

architecture structural of test_top_level is

    signal single_pulse    : std_logic;
    signal double_pulse    : std_logic;
    signal triple_pulse    : std_logic;
    signal clock           : std_logic;
    signal data            : std_logic;

begin
    test_signal_generator : entity test_signal_generator
        port map (clock => clock, data => data);

    input_decoder : entity input_decoder
        port map (clock => clock, data => data,
                  single_pulse => single_pulse,
                  double_pulse => double_pulse,
                  triple_pulse => triple_pulse);

    process
    begin
        clock <= '1';
        wait for 40 ns;
        clock <= '0';
        wait for 40 ns;
    end;

end test_top_level;

