
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

    constant ZERO   : std_logic_vector (1 downto 0) := "00";
    constant ONE    : std_logic_vector (1 downto 0) := "01";
    constant TWO    : std_logic_vector (1 downto 0) := "10";
    constant THREE  : std_logic_vector (1 downto 0) := "11";

    constant max_transition_time    : Natural := 255;
    constant enough_transitions     : Natural := 15;
    constant test_pulse_count       : Natural := 100;

    signal clock            : std_logic := '0';
    signal data_in          : std_logic := '0';
    signal pulse_length_out : std_logic_vector (1 downto 0) := "00";
    signal single_time_out  : std_logic_vector (7 downto 0) := (others => '0');
    signal sync_out         : std_logic := '0';
    signal sync_in          : std_logic := '0';

    type t_test_id is (INIT, DONE, SINGLE_LENGTH, DOUBLE_LENGTH, TRIPLE_LENGTH,
                       TRIANGLE);
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
        test_id <= SINGLE_LENGTH;
        for i in 1 to (test_pulse_count / 2) loop
            data_in <= '1';
            wait for 10 us;
            data_in <= '0';
            wait for 10 us;
        end loop;

        -- In this test we will generate 100 pulses of double length
        test_id <= DOUBLE_LENGTH;
        for i in 1 to (test_pulse_count / 2) loop
            data_in <= not data_in;
            wait for 20 us;
            data_in <= not data_in;
            wait for 20 us;
        end loop;

        -- Now, one pulse of length 3
        test_id <= TRIPLE_LENGTH;
        data_in <= not data_in;
        wait for 30 us;
        -- followed by 100 double length pulses
        for i in 1 to (test_pulse_count / 2) loop
            data_in <= not data_in;
            wait for 20 us;
            data_in <= not data_in;
            wait for 20 us;
        end loop;

        -- triangular ONE TWO THREE sequence
        test_id <= TRIANGLE;
        for i in 1 to (test_pulse_count / 2) loop
            data_in <= not data_in;
            wait for 30 us;
            data_in <= not data_in;
            wait for 10 us;
            data_in <= not data_in;
            wait for 20 us;
        end loop;

        test_id <= DONE;
        wait;
    end process signal_generator;

    debug : process
        variable l          : line;
        variable count1     : Natural := 0;
        variable count2     : Natural := 0;
        variable count3     : Natural := 0;
        variable expected   : Natural := 0;
        variable previous   : std_logic_vector (1 downto 0) := ZERO;
    begin
        wait until test_id = SINGLE_LENGTH;

        count2 := 0;
        assert test_id = SINGLE_LENGTH;
        while test_id = SINGLE_LENGTH loop
            wait until pulse_length_out'event or test_id'event;
            assert pulse_length_out = ZERO or pulse_length_out = TWO;
            if pulse_length_out = TWO then
                count2 := count2 + 1;
            end if;
        end loop;

        expected := test_pulse_count - 1 - enough_transitions;
        write (l, String'("same length test: pulse length 2 count = "));
        write (l, count2);
        write (l, String'(" expected = "));
        write (l, expected);
        writeline (output, l);
        assert count2 = expected;

        -- In this test we double the pulse length and this triggers
        -- the "three_counter" reset condition. Before that happens, some
        -- pulses of length THREE are received. The input decoder recalibrates
        -- and the pulse length returns to TWO.
        count2 := 0;
        count3 := 0;
        assert test_id = DOUBLE_LENGTH;
        while test_id = DOUBLE_LENGTH loop
            wait until pulse_length_out'event or test_id'event;
            assert pulse_length_out /= ONE;
            if pulse_length_out = THREE then
                count3 := count3 + 1;
            end if;
            if pulse_length_out = TWO then
                count2 := count2 + 1;
            end if;
        end loop;

        write (l, String'("double length test: pulse length 2 count = "));
        write (l, count2);
        write (l, String'(" pulse length 3 count = "));
        write (l, count3);
        write (l, String'(" expected total = "));
        write (l, expected);
        writeline (output, l);
        assert count3 > 0;
        assert count3 < 10;
        assert (count2 + count3) = expected;

        -- In this test we generate a triple-length pulse and then lots of double-length pulses.
        -- None of this requires any sort of recalibration, everything is captured perfectly.
        count2 := 0;
        count3 := 0;
        assert test_id = TRIPLE_LENGTH;
        while test_id = TRIPLE_LENGTH loop
            wait until pulse_length_out'event or test_id'event;
            assert pulse_length_out /= ONE;
            if pulse_length_out = THREE then
                count3 := count3 + 1;
            end if;
            if pulse_length_out = TWO then
                count2 := count2 + 1;
            end if;
        end loop;
        write (l, String'("triple length test: pulse length 2 count = "));
        write (l, count2);
        write (l, String'(" pulse length 3 count = "));
        write (l, count3);
        writeline (output, l);
        assert count3 = 1;
        assert count2 = test_pulse_count;

        -- 1, 2, 3 pulses now
        assert test_id = TRIANGLE;
        count2 := 0;
        previous := ONE;
        while test_id = TRIANGLE loop
            wait until pulse_length_out'event or test_id'event;
            if pulse_length_out /= ZERO then
                write (l, String'("triangle "));
                write (l, to_integer (unsigned (pulse_length_out)));
                writeline (output, l);
            end if;
            case pulse_length_out is
                when ONE =>
                    assert previous = THREE;
                    previous := ONE;
                when TWO =>
                    assert previous = ONE or previous = TWO;
                    count2 := count2 + 1;
                    previous := TWO;
                when THREE =>
                    assert previous = TWO;
                    previous := THREE;
                when others =>
                    null;
            end case;
        end loop;
        assert count2 = test_pulse_count;

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
