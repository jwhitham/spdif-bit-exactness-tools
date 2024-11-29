
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use debug_textio.all;

entity test_input_decoder is
end test_input_decoder;

architecture test of test_input_decoder is

    constant ZERO   : std_logic_vector (1 downto 0) := "00";
    constant ONE    : std_logic_vector (1 downto 0) := "01";
    constant TWO    : std_logic_vector (1 downto 0) := "10";
    constant THREE  : std_logic_vector (1 downto 0) := "11";

    constant enough_transitions     : Natural := 15;
    constant test_pulse_count       : Natural := 100;

    signal clock            : std_logic := '0';
    signal data_in          : std_logic := '0';
    signal pulse_length_out : std_logic_vector (1 downto 0) := "00";
    signal single_time_out  : std_logic_vector (7 downto 0) := (others => '0');
    signal sync_out         : std_logic := '0';
    signal sync_in          : std_logic := '0';
    signal enable_123_check_in : std_logic := '1';

    type t_test_id is (INIT, DONE, SINGLE_LENGTH, DOUBLE_LENGTH, TRIPLE_LENGTH,
                       TRIANGLE, TOLERANCE, RESYNC_NOW, RESYNC_TOLERANCE,
                       SEND_FASTER, SPEED_UP, SEND_TOO_FAST, SEND_SLOW,
                       BEFORE_LARGE_MAXIMUM, AFTER_LARGE_MAXIMUM);
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
            enough_transitions => enough_transitions,
            debug => false)
        port map (
            data_in => data_in,
            pulse_length_out => pulse_length_out,
            single_time_out => single_time_out,
            enable_123_check_in => enable_123_check_in,
            sync_out => sync_out,
            sync_in => sync_in,
            clock_in => clock);

    signal_generator : process

        variable error_index : Natural := 0;
        type t_error_table is array (Natural range <>) of Integer;
        constant error_table : t_error_table :=
            (2, -34, 87, 78, 94, -54, 82, -91, 69, -24, 98, -69, 16, 73, -72,
             -47, -37, -80, -21, -37, 81, -7, 99, -46, 26, 91, 94, -78, 62, 1,
             -63, -54, -88, 7, -46, -57, -74, 58, 76, 3, -31, 82, 92, -25, 18,
             51, 92, -89, 27, 36, -89, 61, -11, -98, -2, -48, 81, -41, 73, -71,
             87, -62, 55, -52, -60, -76, 90, -11, -65, 59, 24, -4, 46, -10, 61,
             -73, 42, -47, 77, -21, 66, 94, -56, -92, 13, 0, 56, 51, -68, 97,
             -67, -18, 37, -54, -33, -67, -31, 44, 65, -2,
             43, 15, 77, 26, -79, -98, -9, -76, -68, -54, 76, 33, 6, 85, -94,
             26, -1, -94, 26, -4, 49, 96, 49, -28, 75, -15, -37, 29, 12, -24,
             -40, -24, -84, -5, -1, -14, 72, 27, -11, 63, 90, -67, -88, -29,
             10, -48, 58, 11, -14, -37, -71, -21, -44, 19, 95, -4, 87, 54, 1,
             70, -26, -12, -30, 26, -47, 30, 2, 24, -94, -85, 87, 32, -96,
             15, -10, -33, 62, 65, -19, 64, 37, 19, -4, 32, -71, 10, -98, -9,
             -96, 92, -54, 47, 44, 22, -81, -15, -96, -49, -62, 46, 64, 72,
             -17, 98, 79, -95, -34, -7, -8, -66, -20, -34, -27, -55, 75, 86,
             98, -54, -93, 23, -2, 18, 54, -19, -10, -76, 16, -13, -57, 32, 4,
             -48, 34, 13, 46, -70, -47, 55, 63, -20, 1, -83, 84, -62, 97, 6,
             -60, -91, -36, 54, 49, -35, -35, 67, 87, 20, -25, 59, -99, 75,
             -65, -98, -45, 82, 6, -50, -57, -91, 33, 67, 49, -67, 95, -88, 4,
             -34, 30, -52, 9, 29, -50, 2, 59, 28, 44, 60, -31, -65, 13, 94,
             -66, 11, 53, 71, 15, 16, -65, 31, -60, -57, 40, -2, 86, 52, -92,
             -29, 48, -93, 34, -49, -4, 85, 29, -75, 60, 75, 65, 72, 45, 52,
             92, -38, 96, 44, -23, -92, -61, -29, -89, 6, 58, 11, 94, -49, 7,
             -56, -35, -96, 18, 89, -77, -12, 68, 78, -12, -44, -8, 71, -9,
             68, 19, 92, -66, 64, 67, -73, 53, -1, -25, -91, 77, -16, -90,
             -10, 93, 96, -27, -45, 51, 61, -15, -40, 25, -88, 92, -20, 49,
             56, 74, -29, -83, -18, 50, -81, 32, -61, 99, -42, 15, 95, -3,
             7, -53, -11, -6, 13, -29);

        procedure gen_error (err : inout Time) is
        begin
            error_index := (error_index + 1) mod error_table'Length;
            if error_table (error_index) < 0 then
                -- An error of - 5us must be tolerated
                err := (error_table (error_index) rem 6) * 1 us;
            else
                -- An error of + 4us must be tolerated
                err := (error_table (error_index) rem 5) * 1 us;
            end if;
        end gen_error;

        variable err : Time := 0 ms;

    begin
        test_id <= INIT;
        sync_in <= '0';
        data_in <= '1';
        enable_123_check_in <= '0';
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

        -- Now, some longer pulses mixed in
        test_id <= TRIPLE_LENGTH;
        data_in <= not data_in;
        for i in 1 to (test_pulse_count / 2) loop
            data_in <= not data_in;
            if (i mod 10) = 1 then
                wait for 30 us;
            else
                wait for 20 us;
            end if;
            data_in <= not data_in;
            wait for 20 us;
        end loop;

        -- This completes the part of the test where we don't have all three pulse lengths
        -- so we can enable the '123' check.
        enable_123_check_in <= '1';

        -- triangular ONE TWO THREE sequence
        -- Begin with an additional ONE pulse to avoid a 2-1-2 sequence
        test_id <= TRIANGLE;
        data_in <= not data_in;
        wait for 10 us;
        for i in 1 to test_pulse_count loop
            data_in <= not data_in;
            wait for 10 us;
            data_in <= not data_in;
            wait for 20 us;
            data_in <= not data_in;
            wait for 30 us;
        end loop;

        -- test limits of tolerance for all pulses
        test_id <= TOLERANCE;
        for i in 1 to test_pulse_count loop
            data_in <= not data_in;
            gen_error (err);
            wait for err + 10 us;
            data_in <= not data_in;
            gen_error (err);
            wait for err + 20 us;
            data_in <= not data_in;
            gen_error (err);
            wait for err + 30 us;
        end loop;

        -- keeping the errors, force a resync by creating a gap in the signal
        for i in 1 to 10 loop
            wait for 3000 us;
            test_id <= RESYNC_TOLERANCE;
            for j in 1 to test_pulse_count loop
                data_in <= not data_in;
                gen_error (err);
                wait for err + 10 us;
                data_in <= not data_in;
                gen_error (err);
                wait for err + 20 us;
                data_in <= not data_in;
                gen_error (err);
                wait for err + 30 us;
            end loop;
            test_id <= RESYNC_NOW;
            wait for 1 us;
        end loop;

        -- now we make it send faster
        for i in 9 downto 4 loop
            test_id <= SEND_FASTER;
            for j in 1 to test_pulse_count loop
                data_in <= not data_in;
                wait for i * 1 us;
                data_in <= not data_in;
                wait for i * 2 us;
                data_in <= not data_in;
                wait for i * 3 us;
            end loop;
            test_id <= SPEED_UP;
            wait for 1 us;
        end loop;

        -- The next speedup will not work, because the minimum transition time
        -- is 4 clock cycles. (This is the minimum because (a) it is the length of
        -- the pipeline: transition_time needs to be valid when compared to the
        -- thresholds in stage 4, and (b) if the minimum transition time is really short,
        -- you can't get reliable data anyway, because at least a +/- 1 error is
        -- typical for all the measurements and with small numbers, the pulse lengths
        -- become indistinguishable.)
        test_id <= SEND_TOO_FAST;
        for j in 1 to test_pulse_count loop
            data_in <= not data_in;
            wait for 3 * 1 us;
            data_in <= not data_in;
            wait for 3 * 2 us;
            data_in <= not data_in;
            wait for 3 * 3 us;
        end loop;

        -- Now we go to the other extreme - the transmission is almost too slow.
        -- But it is just allowable. The THREE pulse is as long as it can be.
        -- range 152 to 254, so 4X = 406
        -- threshold_1_5 = 1.5X = 152
        -- threshold_2_5 = 2.5X = 253
        test_id <= SEND_SLOW;
        for j in 1 to test_pulse_count loop
            data_in <= not data_in;
            wait for 152 us;        -- longest possible ONE pulse
            data_in <= not data_in;
            wait for 253 us;        -- longest possible TWO pulse
            data_in <= not data_in;
            wait for 254 us;        -- shortest and longest possible THREE pulse
        end loop;

        -- "Large maximum" recovery
        -- Test a failure mode when a very large maximum is captured
        -- due to some input glitch e.g. the cable being connected,
        -- and then everything else just appears to be ONE. The decoder
        -- should resynchronise in this case
        test_id <= BEFORE_LARGE_MAXIMUM;
        wait for 3000 us; -- force a reset, then normal operation for a while
        for j in 1 to test_pulse_count loop
            data_in <= not data_in;
            wait for 30 us;
            data_in <= not data_in;
            wait for 10 us;
            data_in <= not data_in;
            wait for 20 us;
        end loop;
        -- Here we generate a surprisingly large input (but not too large to force a reset)
        data_in <= not data_in;
        wait for 254 us;
        test_id <= AFTER_LARGE_MAXIMUM;
        -- Back to normal - but now everything looks like ONE
        for j in 1 to test_pulse_count loop
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
        variable l              : line;
        variable count1         : Natural := 0;
        variable count2         : Natural := 0;
        variable count3         : Natural := 0;
        variable expected       : Natural := 0;
        variable correct_count  : Natural := 0;
        variable resync_count   : Natural := 0;
        variable lost           : Natural := 0;
        variable previous       : std_logic_vector (1 downto 0) := ZERO;

        constant epsilon        : Natural := 3;
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

        expected := test_pulse_count - enough_transitions;
        write (l, String'("same length test: pulse length 2 count = "));
        write (l, count2);
        write (l, String'(" expected = "));
        write (l, expected);
        writeline (output, l);
        assert count2 > (expected - epsilon);
        assert sync_out = '1';

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
            case pulse_length_out is
                when THREE =>
                    count3 := count3 + 1;
                when TWO =>
                    count2 := count2 + 1;
                when ONE =>
                    assert False;
                when others =>
                    null;
            end case;
        end loop;

        expected := test_pulse_count - enough_transitions;
        write (l, String'("double length test: pulse length 2 count = "));
        write (l, count2);
        write (l, String'(" pulse length 3 count = "));
        write (l, count3);
        write (l, String'(" expected total = "));
        write (l, expected);
        writeline (output, l);
        assert count3 > 0;
        assert count3 < 10;
        assert (count2 + count3) > (expected - epsilon);
        assert sync_out = '1';

        -- In this test we generate a mixture of triple-length and double-length pulses,
        -- but they're all treated as double-length because minimum 20 and maximum 30
        -- has a 2.5 threshold of (20 + 30) * 2.5 / 4 = 31.
        count2 := 0;
        count3 := 0;
        assert test_id = TRIPLE_LENGTH;
        while test_id = TRIPLE_LENGTH loop
            wait until pulse_length_out'event or test_id'event;
            assert pulse_length_out /= ONE;
            assert pulse_length_out /= THREE;
            if pulse_length_out = TWO then
                count2 := count2 + 1;
            end if;
        end loop;
        write (l, String'("triple length test: pulse length 2 count = "));
        write (l, count2);
        writeline (output, l);
        assert count2 = test_pulse_count;


        -- 1, 2, 3 pulses now. As soon as the 10 microsecond pulse is seen, the
        -- decoder has a new minimum transition time. Wait for two pulses of
        -- length one in order to begin.
        for i in 1 to 2 loop
            while test_id = TRIANGLE loop
                wait until pulse_length_out'event or test_id'event;
                assert pulse_length_out /= THREE;
                exit when pulse_length_out = ONE;
            end loop;
        end loop;

        count2 := 0;
        previous := pulse_length_out;
        while test_id = TRIANGLE loop
            wait until pulse_length_out'event or test_id'event;
            case pulse_length_out is
                when ONE =>
                    assert previous = THREE;
                    previous := ONE;
                when TWO =>
                    assert previous = ONE;
                    count2 := count2 + 1;
                    previous := TWO;
                when THREE =>
                    assert previous = TWO;
                    previous := THREE;
                when others =>
                    null;
            end case;
        end loop;
        expected := test_pulse_count;
        write (l, String'("triangle test: pulse length 1, 2, 3 count = "));
        write (l, count2);
        write (l, String'(" expected = "));
        write (l, expected);
        writeline (output, l);
        assert count2 = expected;

        -- The sequence continues but now there is some error in each input time
        -- because we are deliberately adding noise to the signal. Errors are
        -- chosen so that they all fall within the bounds of what should be tolerated.
        count2 := 0;
        assert test_id = TOLERANCE;
        while test_id = TOLERANCE loop
            wait until pulse_length_out'event or test_id'event;
            case pulse_length_out is
                when ONE =>
                    assert previous = THREE;
                    previous := ONE;
                when TWO =>
                    assert previous = ONE;
                    count2 := count2 + 1;
                    previous := TWO;
                when THREE =>
                    assert previous = TWO;
                    previous := THREE;
                when others =>
                    null;
            end case;
        end loop;
        expected := test_pulse_count;
        write (l, String'("tolerance test: pulse length 1, 2, 3 count = "));
        write (l, count2);
        write (l, String'(" expected = "));
        write (l, expected);
        writeline (output, l);
        assert count2 = expected;

        -- Same basic idea but this time we force periodic resyncs as well,
        -- by leaving 3000 us gaps in the signal. The pulse data may not be
        -- correct immediately after resynchronising. How long does it take to
        -- recover?
        correct_count := 0;
        resync_count := 0;
        assert test_id = RESYNC_TOLERANCE;
        while test_id = RESYNC_NOW or test_id = RESYNC_TOLERANCE loop
            if test_id = RESYNC_NOW then
                wait until test_id'event;

                resync_count := resync_count + 1;
                lost := (test_pulse_count * 3) - correct_count;
                write (l, String'("after resync "));
                write (l, resync_count);
                write (l, String'(", lost during recovery: "));
                write (l, lost);
                write (l, String'(", correct: "));
                write (l, correct_count);
                writeline (output, l);
                assert correct_count > test_pulse_count;
                assert lost > 0;

                previous := ZERO;
                correct_count := 0;
            else
                wait until pulse_length_out'event or test_id'event;
                case pulse_length_out is
                    when ONE =>
                        if previous = THREE then
                            correct_count := correct_count + 1;
                        else
                            correct_count := 0;
                        end if;
                        previous := ONE;
                    when TWO =>
                        if previous = ONE then
                            correct_count := correct_count + 1;
                        else
                            correct_count := 0;
                        end if;
                        previous := TWO;
                    when THREE =>
                        if previous = TWO then
                            correct_count := correct_count + 1;
                        else
                            correct_count := 0;
                        end if;
                        previous := THREE;
                    when others =>
                        null;
                end case;
            end if;
        end loop;

        -- Now the transmission becomes faster. There are no gaps in the signal.
        correct_count := 0;
        resync_count := 0;
        assert test_id = SEND_FASTER;
        while test_id = SPEED_UP or test_id = SEND_FASTER loop
            if test_id = SPEED_UP then
                wait until test_id'event;

                resync_count := resync_count + 1;
                lost := (test_pulse_count * 3) - correct_count;
                write (l, String'("after speedup "));
                write (l, resync_count);
                write (l, String'(", lost during recovery: "));
                write (l, lost);
                writeline (output, l);
                assert correct_count > (test_pulse_count * 2);
                assert lost >= 0;
                assert lost < test_pulse_count;

                previous := ZERO;
                correct_count := 0;
            else
                wait until pulse_length_out'event or test_id'event;
                case pulse_length_out is
                    when ONE =>
                        if previous = THREE then
                            correct_count := correct_count + 1;
                        else
                            correct_count := 1;
                        end if;
                        previous := ONE;
                    when TWO =>
                        if previous = ONE then
                            correct_count := correct_count + 1;
                        else
                            correct_count := 1;
                        end if;
                        previous := TWO;
                    when THREE =>
                        if previous = TWO then
                            correct_count := correct_count + 1;
                        else
                            correct_count := 1;
                        end if;
                        previous := THREE;
                    when others =>
                        null;
                end case;
            end if;
        end loop;

        -- The transmission is now too fast. Nothing is received reliably.
        assert test_id = SEND_TOO_FAST;
        while test_id = SEND_TOO_FAST loop
            wait until pulse_length_out'event or test_id'event;
            if pulse_length_out /= ZERO then
                correct_count := correct_count + 1;
            end if;
        end loop;

        -- One pulse was received immediately after the transition.
        write (l, String'("too fast? received only "));
        write (l, correct_count);
        writeline (output, l);
        assert correct_count <= 1;
        assert sync_out = '0';

        -- Send as slowly as possible
        assert test_id = SEND_SLOW;
        correct_count := 0;
        previous := ZERO;
        while test_id = SEND_SLOW loop
            wait until pulse_length_out'event or test_id'event;
            case pulse_length_out is
                when ONE =>
                    if previous = THREE then
                        correct_count := correct_count + 1;
                    else
                        correct_count := 0;
                    end if;
                    previous := ONE;
                when TWO =>
                    if previous = ONE then
                        correct_count := correct_count + 1;
                    else
                        correct_count := 0;
                    end if;
                    previous := TWO;
                when THREE =>
                    if previous = TWO then
                        correct_count := correct_count + 1;
                    else
                        correct_count := 0;
                    end if;
                    previous := THREE;
                when others =>
                    null;
            end case;
        end loop;

        lost := (test_pulse_count * 3) - correct_count;
        write (l, String'("slow: received: "));
        write (l, correct_count);
        write (l, String'(", lost: "));
        write (l, lost);
        writeline (output, l);
        assert correct_count > (test_pulse_count * 2);
        assert lost >= 0;
        assert lost < test_pulse_count;

        -- "Large maximum" recovery
        assert test_id = BEFORE_LARGE_MAXIMUM;
        count1 := 0;
        count2 := 0;
        count3 := 0;

        -- here we wait through a warm-up phase where everything is working normally
        while test_id = BEFORE_LARGE_MAXIMUM loop
            wait until pulse_length_out'event or test_id'event;
        end loop;

        -- now the event has been triggered, we should just see ONE until recovery begins:
        -- many ONEs, almost no TWOs, almost no THREEs.
        -- The number of ONEs is limited to around 64 by max_last_seen.
        assert sync_out = '1';
        assert test_id = AFTER_LARGE_MAXIMUM;
        while test_id = AFTER_LARGE_MAXIMUM and sync_out = '1' loop
            wait until pulse_length_out'event or test_id'event or sync_out'event;
            case pulse_length_out is
                when ONE =>
                    count1 := count1 + 1;
                when TWO =>
                    count2 := count2 + 1;
                when THREE =>
                    count3 := count3 + 1;
                when others =>
                    null;
            end case;
        end loop;
        write (l, String'("failure mode: before recovery: "));
        write (l, count1);
        write (l, String'(" ones "));
        write (l, count2);
        write (l, String'(" twos "));
        write (l, count3);
        write (l, String'(" threes"));
        writeline (output, l);
        assert count1 > 5;
        assert count2 <= 1;
        assert count3 <= 2;
        assert count1 <= (64 + epsilon);

        -- now we wait until the recovery completes
        assert test_id = AFTER_LARGE_MAXIMUM;
        assert sync_out = '0';
        while test_id = AFTER_LARGE_MAXIMUM and sync_out = '1' loop
            wait until pulse_length_out'event or test_id'event or sync_out'event;
        end loop;

        -- recovery completed, normal operation should be restored
        -- Almost equal numbers of ONEs, TWOs, THREEs are obtained.
        count1 := 0;
        count2 := 0;
        count3 := 0;
        assert test_id = AFTER_LARGE_MAXIMUM;
        assert sync_out = '0';
        while test_id = AFTER_LARGE_MAXIMUM loop
            wait until pulse_length_out'event or test_id'event or sync_out'event;
            case pulse_length_out is
                when ONE =>
                    count1 := count1 + 1;
                when TWO =>
                    count2 := count2 + 1;
                when THREE =>
                    count3 := count3 + 1;
                when others =>
                    null;
            end case;
        end loop;
        write (l, String'("failure mode: after recovery: "));
        write (l, count1);
        write (l, String'(" ones "));
        write (l, count2);
        write (l, String'(" twos "));
        write (l, count3);
        write (l, String'(" threes"));
        writeline (output, l);
        assert count1 > (test_pulse_count / 2);
        assert count2 > (test_pulse_count / 2);
        assert count3 > (test_pulse_count / 2);
        assert abs (count3 - count2) < 2;
        assert abs (count2 - count1) < 2;
        assert abs (count3 - count1) < 2;
        assert sync_out = '1';

        assert test_id = DONE;
        wait;
    end process debug;

end test;
