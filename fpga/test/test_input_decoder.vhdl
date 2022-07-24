
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_input_decoder is
end test_input_decoder;

architecture test of test_input_decoder is

    constant max_transition_time    : Natural := 255;
    constant enough_transitions     : Natural := 15;
    constant test_pulse_count       : Natural := 100;

    signal clock            : std_logic := '0';
    signal data_in          : std_logic := '0';
    signal pulse_length_out : std_logic_vector (1 downto 0) := "00";
    signal single_time_out  : std_logic_vector (7 downto 0) := (others => '0');
    signal sync_out         : std_logic := '0';
    signal sync_in          : std_logic := '0';

    type t_test_id is (INIT, DONE, SAME_LENGTH);
    signal test_id          : t_test_id := INIT;

begin

    process
    begin
        -- 1MHz clock (one clock every 1000ns)
        while test_id /= DONE loop
            clock <= '1';
            wait for 500 ns;
            clock <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    dut : entity input_decoder
        generic map (
            max_transition_time => max_transition_time,
            enough_transitions => enough_transitions,
            debug => true)
        port map (
            data_in => data_in,
            pulse_length_out => pulse_length_out,
            single_time_out => single_time_out,
            sync_out => sync_out,
            sync_in => sync_in,
            clock_in => clock);

    signal_generator : process
    begin
        test_id <= INIT;
        sync_in <= '0';
        data_in <= '1';
        wait for 2 us;
        wait until clock'event and clock = '1';
        sync_in <= '1';

        -- In this first test we will generate 100 pulses of the same length
        test_id <= SAME_LENGTH;
        for i in 1 to (test_pulse_count / 2) loop
            data_in <= '1';
            wait for 10 us;
            data_in <= '0';
            wait for 10 us;
        end loop;

        test_id <= DONE;
        wait;
    end process signal_generator;

    debug : process
        variable l          : line;
        variable count      : Natural := 0;
        variable expected   : Natural := 0;
    begin
        wait until test_id = SAME_LENGTH;

        write (l, String'("same length test"));
        writeline (output, l);

        while test_id = SAME_LENGTH loop
            wait until pulse_length_out'event or test_id'event;
            assert pulse_length_out = "00" or pulse_length_out = "10";
            if pulse_length_out = "10" then
                count := count + 1;
            end if;
        end loop;

        expected := test_pulse_count - 1 - enough_transitions;
        write (l, String'("same length test: pulse length 2 count = "));
        write (l, count);
        write (l, String'(" expected = "));
        write (l, expected);
        writeline (output, l);
        assert count = expected;

        assert False;

        wait until test_id = DONE;

        while test_id /= DONE loop
            wait until pulse_length_out'event or test_id'event;
            if test_id'event then
                write (l, t_test_id'Image (test_id));
                writeline (output, l);
            end if;
            if pulse_length_out'event then
                case pulse_length_out is
                    when "01" =>
                        write (l, String'("Pulse length 1"));
                        writeline (output, l);
                    when "10" =>
                        write (l, String'("Pulse length 2"));
                        writeline (output, l);
                    when "11" =>
                        write (l, String'("Pulse length 3"));
                        writeline (output, l);
                    when others =>
                        null;
                end case;
            end if;
        end loop;
        wait;
    end process debug;

end test;
