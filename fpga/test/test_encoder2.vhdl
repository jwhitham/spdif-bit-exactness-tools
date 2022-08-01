
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

    signal clock_in                 : std_logic := '0';
    signal done                     : std_logic := '0';

    subtype t_pulse_length is std_logic_vector (1 downto 0);
    subtype t_data is std_logic_vector (31 downto 0);

    constant disable                : std_logic := '0';
    constant enable                 : std_logic := '1';

    constant num_sub_tests          : Natural := 1000;
    constant single_time            : Time := 4 us;
    constant packet_time            : Time := single_time * 64;

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
    signal oe_error                 : std_logic := '0';
    signal rg_strobe                : std_logic := '0';
    signal encoded_spdif            : std_logic := '0';

    type t_stage is (UNDEFINED,
                     RIGHT_ONLY,
                     LEFT_ONLY,
                     BREAK,
                     TOO_SOON,
                     TOO_SOON_MARGINAL,
                     NOT_TOO_SOON_MARGINAL,
                     TOO_LONG,
                     TOO_LONG_MARGINAL,
                     NOT_TOO_LONG_MARGINAL,
                     NORMAL);
    signal stage                    : t_stage := UNDEFINED;

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
        while done = '0' loop
            clock_in <= '1';
            wait for 500 ns;
            clock_in <= '0';
            wait for 500 ns;
        end loop;
        wait;
    end process;

    spdif_pulses : process
    begin
        while done = '0' loop
            rg_strobe <= '1';
            wait for 1 us;
            rg_strobe <= '0';
            wait for single_time - 1 us;
        end loop;
        wait;
    end process spdif_pulses;

    ce : entity combined_encoder
        -- generic map (debug => true)
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
        while done = '0' loop
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
        variable l : line;

        procedure do_break is
        begin
            enc_data <= (others => '0');
            enc_left_strobe <= '0';
            enc_right_strobe <= '0';
            sync_in <= '0';
            wait for 10 us;
            sync_in <= '1';
            for i in 1 to 100 loop
                enc_left_strobe <= '1';
                wait for 1 us;
                enc_left_strobe <= '0';
                wait for (single_time * 64) - 1 us;

                enc_right_strobe <= '1';
                wait for 1 us;
                enc_right_strobe <= '0';
                wait for (single_time * 64) - 1 us;
            end loop;
        end do_break;
    begin
        -- Resetting
        done <= '0';
        sync_in <= '0';
        stage <= UNDEFINED;

        enc_data <= (others => '0');
        enc_left_strobe <= '0';
        enc_right_strobe <= '0';
        sync_in <= '0';
        wait for 10 us;
        sync_in <= '1';

        -- Send bad packets in various ways, causing various error behaviours
        stage <= RIGHT_ONLY;
        for i in 1 to 10 loop
            enc_right_strobe <= '1';
            enc_data <= generate_test_data (100 + i, false);
            wait for 1 us;
            enc_right_strobe <= '0';
            wait for (single_time * 64) - 1 us;
        end loop;

        stage <= LEFT_ONLY;
        for i in 1 to 10 loop
            enc_left_strobe <= '1';
            enc_data <= generate_test_data (100 + i, true);
            wait for 1 us;
            enc_left_strobe <= '0';
            wait for (single_time * 64) - 1 us;
        end loop;

        -- check for normal recovery after an error
        stage <= NORMAL;
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

        stage <= BREAK;
        do_break;

        stage <= TOO_SOON;
        enc_left_strobe <= '1';
        enc_data <= generate_test_data (70, true);
        wait for 1 us;
        enc_left_strobe <= '0';
        enc_right_strobe <= '1';
        wait for 1 us;
        enc_right_strobe <= '0';
        wait for 1 us;

        stage <= BREAK;
        do_break;

        stage <= TOO_SOON_MARGINAL;
        enc_left_strobe <= '1';
        enc_data <= generate_test_data (71, true);
        wait for 1 us;
        enc_left_strobe <= '0';
        wait for (single_time * 31) - 1 us;     -- 31 is just too soon (by 1 single time)
        enc_right_strobe <= '1';
        wait for 1 us;
        enc_right_strobe <= '0';
        wait for 1 us;

        stage <= BREAK;
        do_break;

        stage <= NOT_TOO_SOON_MARGINAL;
        enc_left_strobe <= '1';
        enc_data <= generate_test_data (72, true);
        wait for 1 us;
        enc_left_strobe <= '0';
        wait for (single_time * 32) - 1 us;     -- 32 is acceptable
        enc_right_strobe <= '1';
        wait for 1 us;
        enc_right_strobe <= '0';
        wait for 1 us;

        stage <= BREAK;
        do_break;

        stage <= TOO_LONG;
        enc_left_strobe <= '1';
        enc_data <= generate_test_data (73, true);
        wait for 1 us;
        enc_left_strobe <= '0';
        wait for (single_time * 200) - 1 us;
        enc_right_strobe <= '1';
        wait for 1 us;
        enc_right_strobe <= '0';
        wait for 1 us;

        stage <= BREAK;
        do_break;

        stage <= TOO_LONG_MARGINAL;
        enc_left_strobe <= '1';
        enc_data <= generate_test_data (74, true);
        wait for 1 us;
        enc_left_strobe <= '0';
        wait for (single_time * 94) - 1 us;  -- 94 is not acceptable (just too long)
        enc_right_strobe <= '1';
        wait for 1 us;
        enc_right_strobe <= '0';
        wait for 1 us;

        stage <= BREAK;
        do_break;

        stage <= NOT_TOO_LONG_MARGINAL;
        enc_left_strobe <= '1';
        enc_data <= generate_test_data (75, true);
        wait for 1 us;
        enc_left_strobe <= '0';
        wait for (single_time * 93) - 1 us; -- 93 is acceptable
        enc_right_strobe <= '1';
        wait for 1 us;
        enc_right_strobe <= '0';
        wait for 1 us;

        stage <= UNDEFINED;
        done <= '1';
        sync_in <= '0';
        wait;
    end process;

    process
        type t_error_coverage is array (t_stage) of Boolean;
        variable l                               : line;
        variable normal_output_index             : Natural := 1;
        variable expect_left                     : Boolean := true;
        variable error_coverage                  : t_error_coverage := (others => false);
        variable sync_falling_edge               : t_error_coverage := (others => false);
    begin
        -- in NORMAL mode we expect to see the right channel first, with value 1
        normal_output_index := 1;
        expect_left := false;
        while done = '0' loop
            -- Each stage has a particular expectation
            wait until dec_left_strobe'event or dec_right_strobe'event
                    or done'event or oe_error'event or sync_out'event or stage'event;

            if stage'event then
                write (l, String'("stage "));
                write (l, t_stage'Image (stage));
                writeline (output, l);
            end if;
            -- Some stages should flag an error and the sync output will go to zero
            if oe_error = '1' then
                error_coverage (stage) := true;
            end if;
            if sync_out'event and sync_out = '0' then
                sync_falling_edge (stage) := true;
            end if;
            case stage is
                when RIGHT_ONLY =>
                    -- Nothing happens - first output must be left
                    assert oe_error = '0';
                    assert dec_left_strobe = '0';
                    assert dec_right_strobe = '0';
                    assert sync_out = '0';

                when LEFT_ONLY =>
                    -- We get an error before anything else happens
                    assert dec_left_strobe = '0';
                    assert dec_right_strobe = '0';

                when TOO_SOON | TOO_SOON_MARGINAL =>
                    -- Left then right in quick succession - error triggered
                    assert dec_left_strobe = '0';
                    assert dec_right_strobe = '0';

                when TOO_LONG | TOO_LONG_MARGINAL =>
                    -- Left then right with a long delay - error triggered
                    null;

                when NOT_TOO_SOON_MARGINAL | NOT_TOO_LONG_MARGINAL =>
                    -- Just acceptable
                    assert oe_error = '0';

                when NORMAL =>
                    -- The encoder recovers from the error
                    if dec_left_strobe = '1' then
                        assert expect_left;
                        check_test_data (normal_output_index, true, dec_data);
                        expect_left := false;
                    end if;
                    if dec_right_strobe = '1' then
                        assert not expect_left;
                        check_test_data (normal_output_index, false, dec_data);
                        expect_left := true;
                        normal_output_index := normal_output_index + 1;
                    end if;
                    if sync_out'event then
                        assert sync_out = '1';
                    end if;

                when UNDEFINED | BREAK =>
                    -- The break state is used to reset the encoder
                    null;
            end case;
        end loop;
        assert normal_output_index = 10;
        for i in t_error_coverage'Range loop
            case i is
                when RIGHT_ONLY | NORMAL
                        | NOT_TOO_SOON_MARGINAL | NOT_TOO_LONG_MARGINAL =>
                    -- No error is expected
                    assert not error_coverage (i);
                    assert not sync_falling_edge (i);
                when BREAK | UNDEFINED =>
                    null;
                when others =>
                    write (l, String'("Error coverage ("));
                    write (l, t_stage'Image (i));
                    write (l, String'(") = "));
                    write (l, error_coverage (i));
                    writeline (output, l);
                    assert error_coverage (i);
                    assert sync_falling_edge (i);
            end case;
        end loop;
        wait;
    end process;

end test;
