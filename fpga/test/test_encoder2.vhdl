
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_encoder2 is
end test_encoder2;

architecture test of test_encoder2 is

    constant num_tests : Natural := 1;

    signal clock_in                 : std_logic := '0';
    signal done                     : std_logic_vector (0 to num_tests) := (others => '0');
    subtype t_pulse_length is std_logic_vector (1 downto 0);
    subtype t_data is std_logic_vector (31 downto 0);

    constant disable                : std_logic := '0';
    constant enable                 : std_logic := '1';

    constant num_sub_tests          : Natural := 1000;
    constant single_time            : Time := 4 us;
    constant packet_time            : Time := single_time * 64;

    constant test_pattern_1         : t_data := (9 => '1', 12 => '1', 17 => '1', others => '0');
    constant test_pattern_2         : t_data := (8 => '1', 12 => '1', 16 => '1', others => '0');


    function generate_test_data (index : Natural; left : Boolean) return t_data is
        variable data : t_data;
    begin
        data := (others => '0');
        data (27 downto 20) := std_logic_vector (to_unsigned (index mod 256, 8));
        data ((index mod 16) + 4) := '1';
        if not left then
            data (((index + 1) mod 16) + 4) := '1';
        end if;
        return data;
    end generate_test_data;

    procedure check_test_data (index : Natural; left : Boolean; data : t_data) is
        constant check : t_data := generate_test_data (index, left);
        variable l : line;
    begin
        if check (27 downto 4) /= data (27 downto 4) then
            write (l, String'("incorrect data: expect "));
            write (l, to_integer (unsigned (check (27 downto 4))));
            write (l, String'(" but got "));
            write (l, to_integer (unsigned (data (27 downto 4))));
            writeline (output, l);
        end if;
        assert check (27 downto 4) = data (27 downto 4);
    end check_test_data;

begin

    -- 1MHz clock (one clock every 1000ns)
    process
    begin
        done (0) <= '1';
        while done (num_tests) = '0' loop
            clock_in <= '1';
            wait for 500 ns;
            clock_in <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    scenario : for test in 1 to 1 generate

        signal middle_data              : std_logic := '0';
        signal start_data               : std_logic := '0';

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

        signal sync_in, sync_out        : std_logic := '0';
        signal packet_sync_in           : std_logic := '0';
        signal channel_sync_in          : std_logic := '0';
        signal timeout                  : std_logic := '0';
        signal oe_error                 : std_logic := '0';
        signal rg_strobe                : std_logic := '0';
        signal encoded_spdif            : std_logic := '0';

    begin

        spdif_pulses : process
        begin
            while done (test) = '0' loop
                rg_strobe <= '1';
                wait for 1 us;
                rg_strobe <= '0';
                wait for single_time - 1 us;
            end loop;
            wait;
        end process spdif_pulses;

        ce : entity combined_encoder
            generic map (debug => true)
            port map (clock_in => clock_in,
                      sync_in => sync_in,
                      sync_out => sync_out,
                      error_out => oe_error,
                      spdif_clock_strobe_in => rg_strobe,
                      data_out => encoded_spdif,
                      preemph_in => disable,
                      data_in => enc_data,
                      left_strobe_in => enc_left_strobe,
                      right_strobe_in => enc_right_strobe);

        -- model of input_decoder hardwired for a specific single time
        input_decoder : process
            variable previous : std_logic;
            variable count    : Natural;
        begin
            previous := '0';
            count := 1;
            packet_sync_in <= '0';
            while done (test) = '0' loop
                wait for single_time - 1 us;
                if previous = encoded_spdif then
                    -- No transition
                    count := count + 1;
                    wait for 1 us;
                    previous := encoded_spdif;
                else
                    -- Transition!
                    if count < 4 then
                        dec_pulse_length <= std_logic_vector (to_unsigned (count, 2));
                    else
                        dec_pulse_length <= "00";
                        packet_sync_in <= '0';
                    end if;
                    wait for 1 us;
                    packet_sync_in <= '1';
                    dec_pulse_length <= "00";
                    previous := encoded_spdif;
                    count := 1;
                end if;
            end loop;
            wait;
        end process input_decoder;

        pd : entity packet_decoder
            port map (clock => clock_in,
                      pulse_length_in => dec_pulse_length,
                      sync_in => packet_sync_in,
                      sync_out => channel_sync_in,
                      data_out => dec_packet_data,
                      start_out => dec_packet_start,
                      shift_out => dec_packet_shift);

        cd : entity channel_decoder 
            port map (clock => clock_in,
                      data_in => dec_packet_data,
                      shift_in => dec_packet_shift,
                      start_in => dec_packet_start,
                      sync_in => packet_sync_in,
                      sync_out => open,
                      data_out => dec_data,
                      subcode_out => open,
                      left_strobe_out => dec_left_strobe,
                      right_strobe_out => dec_right_strobe);

        process
        begin
            done (test) <= '0';
            timeout <= '0';
            wait until done (test - 1) = '1';

            --wait for 10000 us;
            --timeout <= '1';
            wait;
        end process;

        process
            variable l : line;
        begin
            -- Resetting
            done (test) <= '0';
            sync_in <= '0';
            wait until done (test - 1) = '1';

            enc_data <= (others => '0');
            enc_left_strobe <= '0';
            enc_right_strobe <= '0';
            wait for 10 us;
            sync_in <= '1';

            -- Send packets
            for i in 1 to 10 loop
                enc_left_strobe <= '1';
                enc_data <= generate_test_data (i, true);
                wait for 1 us;
                enc_left_strobe <= '0';
                enc_data <= (others => '0');
                wait for (single_time * 64) - 1 us;

                enc_right_strobe <= '1';
                enc_data <= generate_test_data (i, false);
                wait for 1 us;
                enc_right_strobe <= '0';
                enc_data <= (others => '0');
                wait for (single_time * 64) - 1 us;
            end loop;

            wait for 100 us;

            done (test) <= '1';
            sync_in <= '0';
            write (l, String'("STOP"));
            writeline (output, l);
            wait;
        end process;

        process
            variable l : line;
            variable i : Natural;
            variable expect_left : Boolean := true;
        begin
            -- Check output
            wait until done (test - 1) = '1';

            -- Output will skip the first left
            i := 1;
            expect_left := false;
            while done (test) = '0' loop
                -- See what happens; firstly we should see some pulses from the output
                wait until dec_left_strobe'event or dec_right_strobe'event
                        or done'event or oe_error'event or sync_out'event;

                if dec_left_strobe = '1' then
                    assert expect_left;
                    check_test_data (i, true, dec_data);
                    write (l, String'("left ok"));
                    writeline (output, l);
                    expect_left := false;
                end if;
                if dec_right_strobe = '1' then
                    assert not expect_left;
                    check_test_data (i, false, dec_data);
                    write (l, String'("right ok"));
                    writeline (output, l);
                    expect_left := true;
                    i := i + 1;
                end if;
                assert oe_error = '0';
                if sync_out'event then
                    assert sync_out = '1';
                end if;
            end loop;
            assert i = 10;
            wait;
        end process;


    end generate scenario;

end test;
