
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_encoder is
end test_encoder;

architecture test of test_encoder is

    signal clock_in                 : std_logic := '0';
    signal done                     : std_logic := '0';
    signal middle_data              : std_logic := '0';
    signal start_data               : std_logic := '0';

    subtype t_pulse_length is std_logic_vector (1 downto 0);
    subtype t_data is std_logic_vector (31 downto 0);

    signal enc_data                 : t_data := (others => '0');
    signal enc_left_strobe          : std_logic := '0';
    signal enc_right_strobe         : std_logic := '0';

    signal dec_packet_data          : std_logic := '0';
    signal dec_packet_shift         : std_logic := '0';
    signal dec_packet_start         : std_logic := '0';
    signal dec_pulse_length         : t_pulse_length := "00";
    signal dec_data                 : t_data := (others => '0');
    signal dec_left_strobe          : std_logic := '0';
    signal dec_right_strobe         : std_logic := '0';

    signal sync                     : std_logic_vector (7 downto 1) := (others => '0');
    signal oe_error                 : std_logic := '0';
    signal rg_strobe                : std_logic := '0';
    signal enc_packet_start         : std_logic := '0';
    signal encoded_spdif            : std_logic := '0';

    constant disable                : std_logic := '0';
    constant enable                 : std_logic := '1';

    constant num_tests              : Natural := 1000;
    constant single_time            : Time := 4 us;
    constant packet_time            : Time := single_time * 64;



    function generate_test_data (index : Natural; left : Boolean) return t_data is
        variable data : t_data;
    begin
        data := (others => '0');
        data (11 downto 4) := std_logic_vector (to_unsigned (index mod 256, 8));
        data ((index mod 16) + 12) := '1';
        if not left then
            data (((index + 1) mod 16) + 12) := '1';
        end if;
        return data;
    end generate_test_data;

begin

    -- 1MHz clock (one clock every 1000ns)
    process
    begin
        while done = '0' loop
            clock_in <= '1';
            wait for 500 ns;
            clock_in <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    -- S/PDIF pulses (setting the single time, X, as 4 microseconds)
    spdif_pulses : process
    begin
        while done = '0' loop
            rg_strobe <= '0';
            wait for single_time - 1 us;
            rg_strobe <= '1';
            wait for 1 us;
        end loop;
        wait;
    end process spdif_pulses;

    sync (3) <= sync (2);
    sync (4) <= sync (2);

    ce : entity combined_encoder
        port map (clock_in => clock_in,
                  sync_in => sync (1),
                  sync_out => sync (2),
                  error_out => oe_error,
                  packet_start_strobe_out => enc_packet_start,
                  spdif_clock_strobe_in => rg_strobe,
                  data_out => encoded_spdif,
                  preemph_in => disable,
                  data_in => enc_data,
                  left_strobe_in => enc_left_strobe,
                  right_strobe_in => enc_right_strobe);

    id : entity input_decoder
        port map (data_in => encoded_spdif,
                  pulse_length_out => dec_pulse_length,
                  single_time_out => open,
                  enable_123_check_in => enable,
                  sync_in => sync (1),
                  sync_out => sync (5),
                  clock_in => clock_in);

    pd : entity packet_decoder
        port map (clock => clock_in,
                  pulse_length_in => dec_pulse_length,
                  sync_in => sync (5),
                  sync_out => sync (6),
                  data_out => dec_packet_data,
                  start_out => dec_packet_start,
                  shift_out => dec_packet_shift);

    cd : entity channel_decoder 
        port map (clock => clock_in,
                  data_in => dec_packet_data,
                  shift_in => dec_packet_shift,
                  start_in => dec_packet_start,
                  sync_in => sync (6),
                  sync_out => sync (7),
                  data_out => dec_data,
                  subcode_out => open,
                  left_strobe_out => dec_left_strobe,
                  right_strobe_out => dec_right_strobe);

    sync_check : process
        variable l : line;
    begin
        while done = '0' loop
            wait until sync'event or done'event;
            if start_data = '1' then
                assert sync (7) = '1';
                assert sync (6) = '1';
                assert sync (5) = '1';
                assert sync (2) = '1';
            end if;
        end loop;
        wait;
    end process sync_check;

    activity_counters : process
        variable dec_pulse_count : Natural := 0;
        variable dec_packet_count : Natural := 0;
        variable enc_packet_count : Natural := 0;
        variable l : line;
    begin
        while done = '0' loop
            wait until dec_pulse_length'event or dec_packet_start'event
                        or enc_packet_start'Event or done'event;
            if middle_data = '1' then
                if dec_pulse_length'event and dec_pulse_length /= "00" then
                    dec_pulse_count := dec_pulse_count + 1;
                end if;
                if dec_packet_start'event and dec_packet_start = '1' then
                    dec_packet_count := dec_packet_count + 1;
                end if;
                if enc_packet_start'event and enc_packet_start = '1' then
                    enc_packet_count := enc_packet_count + 1;
                end if;
            end if;
        end loop;
        write (l, String'("enc_packet_count = "));
        write (l, enc_packet_count);
        writeline (output, l);
        write (l, String'("dec_pulse_count = "));
        write (l, dec_pulse_count);
        writeline (output, l);
        write (l, String'("dec_packet_count = "));
        write (l, dec_packet_count);
        writeline (output, l);
        wait;
    end process activity_counters;
            

    signal_generator : process
    begin
        -- Resetting
        done <= '0';
        middle_data <= '0';
        start_data <= '0';
        sync (1) <= '0';
        enc_data <= (others => '0');
        enc_left_strobe <= '0';
        enc_right_strobe <= '0';
        wait for 10 us;
        sync (1) <= '1';
        wait for 10 us;

        -- Send zeroes before tests begin
        for i in 0 to 9 loop
            enc_left_strobe <= '1';
            wait for 1 us;
            enc_left_strobe <= '0';
            wait for packet_time - 1 us;

            enc_right_strobe <= '1';
            wait for 1 us;
            enc_right_strobe <= '0';
            wait for packet_time - 1 us;
        end loop;

        -- Every part of the pipeline should be synchronised from this point
        start_data <= '1';

        -- Send test data
        for i in 0 to num_tests - 1 loop
            -- Send left data
            enc_data <= generate_test_data (i * 2, true);
            enc_left_strobe <= '1';
            wait for 1 us;
            enc_left_strobe <= '0';
            wait for packet_time - 1 us;

            -- Send right data
            enc_data <= (others => '0');
            enc_data <= generate_test_data ((i * 2) + 1, false);
            enc_right_strobe <= '1';
            wait for 1 us;
            enc_right_strobe <= '0';
            wait for packet_time - 1 us;

            -- During steady state transmission, capture some data from within the pipeline
            if i = (num_tests / 4) then
                middle_data <= '1';
            end if;
            if i = ((3 * num_tests) / 4) then
                middle_data <= '0';
            end if;
        end loop;

        -- Send zeroes after tests
        for i in 0 to 99 loop
            enc_data <= (others => '0');
            enc_left_strobe <= '1';
            wait for 1 us;
            enc_left_strobe <= '0';
            wait for packet_time - 1 us;

            enc_right_strobe <= '1';
            wait for 1 us;
            enc_right_strobe <= '0';
            wait for packet_time - 1 us;
        end loop;

        start_data <= '0';
        done <= '1';
        wait;
    end process signal_generator;

    assert oe_error = '0';

    output_checker : process
        variable l : line;
        variable expect_data_valid : Boolean := true;
        variable expect_data       : t_data := (others => '0');
        variable test_number       : Natural := 0;
    begin
        while done = '0' loop
            wait until dec_left_strobe'event or dec_right_strobe'event or done'event;
            if dec_left_strobe = '1' then
                assert dec_right_strobe = '0';
                expect_data := generate_test_data (test_number, true);
                expect_data_valid := true;
            elsif dec_right_strobe = '1' then
                assert dec_left_strobe = '0';
                expect_data := generate_test_data (test_number, false);
                expect_data_valid := true;
            else
                expect_data_valid := false;
            end if;

            if expect_data_valid then
                if to_integer (unsigned (dec_data (27 downto 4))) = 0 then
                    -- ignore this packet (startup/finish)
                    null;
                else
                    -- unimportant non-audio parts of the data are ignored:
                    expect_data (31 downto 28) := dec_data (31 downto 28);
                    expect_data (3 downto 0) := dec_data (3 downto 0);

                    -- check for match
                    if dec_data /= expect_data then
                        write (l, String'("test "));
                        write (l, test_number);
                        write (l, String'(" received "));
                        if dec_left_strobe = '1' then
                            write (l, String'("left"));
                        else
                            write (l, String'("right"));
                        end if;
                        write (l, String'(" data "));
                        write (l, to_integer (unsigned (dec_data (27 downto 4))));
                        write (l, String'(" expected "));
                        write (l, to_integer (unsigned (expect_data (27 downto 4))));
                        writeline (output, l);
                    end if;
                    assert dec_data = expect_data;
                    test_number := test_number + 1;
                end if;
            end if;
        end loop;

        for i in 1 to 7 loop
            assert sync (i) = '1';
        end loop;

        write (l, String'("completed "));
        write (l, test_number);
        write (l, String'(" tests"));
        writeline (output, l);
        assert test_number = (num_tests * 2);
        wait;
    end process output_checker;

end test;
