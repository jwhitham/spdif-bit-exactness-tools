
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity test_top_level is
end test_top_level;

architecture structural of test_top_level is

    constant num_sync : Natural := 14;

    signal pulse_length    : std_logic_vector (1 downto 0) := "00";
    signal pe_pulse_length : std_logic_vector (1 downto 0) := "00";
    signal packet_data     : std_logic := '0';
    signal packet_shift    : std_logic := '0';
    signal packet_start    : std_logic := '0';
    signal data            : std_logic_vector (31 downto 0) := (others => '0');
    signal left_strobe     : std_logic := '0';
    signal right_strobe    : std_logic := '0';
    signal left_data       : std_logic_vector (31 downto 0) := (others => '0');

    signal packet_data_2   : std_logic := '0';
    signal packet_shift_2  : std_logic := '0';
    signal packet_start_2  : std_logic := '0';

    signal pulse_length_3  : std_logic_vector (1 downto 0) := "00";
    signal packet_data_3   : std_logic := '0';
    signal packet_shift_3  : std_logic := '0';
    signal packet_start_3  : std_logic := '0';
    signal data_3          : std_logic_vector (31 downto 0) := (others => '0');
    signal left_strobe_3   : std_logic := '0';
    signal right_strobe_3  : std_logic := '0';

    signal clock           : std_logic := '0';
    signal raw_data        : std_logic := '0';
    signal done            : std_logic := '0';
    signal sync            : std_logic_vector (num_sync downto 1) := (others => '0');
    signal sample_rate     : std_logic_vector (15 downto 0) := (others => '0');
    signal single_time     : std_logic_vector (7 downto 0) := (others => '0');
    signal rg_strobe       : std_logic := '0';
    signal oe_data         : std_logic := '0';
    signal oe_error        : std_logic := '0';

    constant zero          : std_logic := '0';
    constant one           : std_logic := '1';

    signal uptime          : Integer := 0;
    signal start_of_r_sync : Integer := 0;
    signal count_r_clocks  : Integer := 0;

begin
    test_signal_gen : entity test_signal_generator
        port map (raw_data_out => raw_data, done_out => done, clock_out => clock);

    dec1 : entity input_decoder
        port map (clock_in => clock, data_in => raw_data,
                  sync_in => one,
                  sync_out => sync (1), single_time_out => single_time,
                  pulse_length_out => pulse_length);

    dec2 : entity packet_decoder
        port map (clock => clock,
                  pulse_length_in => pulse_length,
                  sync_in => sync (1),
                  sync_out => sync (2),
                  data_out => packet_data,
                  start_out => packet_start,
                  shift_out => packet_shift);

    dec3 : entity channel_decoder 
        port map (clock => clock,
                  data_in => packet_data,
                  shift_in => packet_shift,
                  start_in => packet_start,
                  sync_in => sync (2),
                  sync_out => sync (3),
                  data_out => data,
                  left_strobe_out => left_strobe,
                  right_strobe_out => right_strobe);

    m : entity matcher
        port map (data_in => data,
                  left_strobe_in => left_strobe,
                  right_strobe_in => right_strobe,
                  sync_in => sync (3),
                  sync_out => sync (5 downto 4),
                  sample_rate_out => sample_rate,
                  clock => clock);

    rg : entity clock_regenerator
        port map (clock_in => clock,
                  pulse_length_in => pulse_length,
                  sync_in => sync (3),
                  sync_out => sync (6),
                  strobe_out => rg_strobe);

    ce : entity channel_encoder
        port map (clock => clock,
                  sync_in => sync (6),
                  sync_out => sync (7),
                  data_out => packet_data_2,
                  start_out => packet_start_2,
                  shift_out => packet_shift_2,
                  preemph_in => zero,
                  left_strobe_in => left_strobe,
                  right_strobe_in => right_strobe,
                  data_in => data);

    pe : entity packet_encoder
        port map (clock => clock,
                  pulse_length_out => pe_pulse_length,
                  sync_in => sync (7),
                  sync_out => sync (8),
                  data_in => packet_data_2,
                  start_in => packet_start_2,
                  shift_in => packet_shift_2);

    oe : entity output_encoder
        generic map (addr_size => 7, threshold_level => 0.5)
        port map (clock_in => clock,
                  pulse_length_in => pe_pulse_length,
                  sync_in => sync (8),
                  sync_out => sync (9),
                  error_out => oe_error,
                  strobe_in => rg_strobe,
                  data_out => oe_data);

    assert oe_error = '0';

    dec4 : entity input_decoder
        port map (clock_in => clock, data_in => oe_data,
                  sync_in => one,
                  sync_out => sync (10), single_time_out => open,
                  pulse_length_out => pulse_length_3);

    dec5 : entity packet_decoder
        port map (clock => clock,
                  pulse_length_in => pulse_length_3,
                  sync_in => sync (10),
                  sync_out => sync (11),
                  data_out => packet_data_3,
                  start_out => packet_start_3,
                  shift_out => packet_shift_3);

    dec6 : entity channel_decoder 
        port map (clock => clock,
                  data_in => packet_data_3,
                  shift_in => packet_shift_3,
                  start_in => packet_start_3,
                  sync_in => sync (11),
                  sync_out => sync (12),
                  data_out => data_3,
                  left_strobe_out => left_strobe_3,
                  right_strobe_out => right_strobe_3);

    m2 : entity matcher
        port map (data_in => data_3,
                  left_strobe_in => left_strobe_3,
                  right_strobe_in => right_strobe_3,
                  sync_in => sync (12),
                  sync_out => sync (14 downto 13),
                  sample_rate_out => open,
                  clock => clock);


    t1p : process
        variable l : line;
    begin
        while done /= '1' loop
            wait until single_time'event;
            write (l, String'("input decoder single time = "));
            write (l, to_integer (unsigned (single_time)));
            writeline (output, l);
        end loop;
    end process t1p;

    sync_events : block
        procedure report_sync_event (index1, index2 : Integer; name: String) is
            variable l : line;
        begin
            while done /= '1' loop
                wait until sync (index1 downto index2)'event;
                write (l, name);
                write (l, String'(" "));
                if to_integer (unsigned (sync (index1 downto index2))) = 0 then
                    write (l, String'("de"));
                end if;
                write (l, String'("synchronised"));
                writeline (output, l);
            end loop;
            wait;
        end report_sync_event;
    begin
        process begin
            report_sync_event (1, 1, "input decoder");
        end process;
        process begin
            report_sync_event (2, 2, "packet decoder");
        end process;
        process begin
            report_sync_event (3, 3, "channel decoder");
        end process;
        process begin
            report_sync_event (5, 4, "matcher");
        end process;
        process begin
            report_sync_event (6, 6, "clock regenerator");
        end process;
        process begin
            report_sync_event (7, 7, "channel encoder");
        end process;
        process begin
            report_sync_event (8, 8, "packet encoder");
        end process;
        process begin
            report_sync_event (9, 9, "output encoder");
        end process;
        process begin
            report_sync_event (10, 10, "second input decoder");
        end process;
        process begin
            report_sync_event (11, 11, "second packet decoder");
        end process;
        process begin
            report_sync_event (12, 12, "second channel decoder");
        end process;
        process begin
            report_sync_event (14, 13, "second matcher");
        end process;
    end block sync_events;

    print_sample_rate : process
        variable l : line;
    begin
        while done /= '1' loop
            wait until sync (5 downto 4)'event;
            if sync (5 downto 4) /= "00" then
                write (l, String'("matcher sample rate = "));
                write (l, to_integer (unsigned (sample_rate)) * 100);
                write (l, String'(" sync4 = "));
                write (l, to_integer (unsigned (sync (5 downto 4))));
                writeline (output, l);
            end if;
        end loop;
        wait;
    end process print_sample_rate;

    tick_uptime : process
    begin
        while done /= '1' loop
            wait until clock'event or done = '1';
            uptime <= uptime + 1;
        end loop;
        wait;
    end process tick_uptime;

    check_regenerator : process
        variable l : line;
        variable delta : Integer;
    begin
        while done /= '1' loop
            wait until rg_strobe'event or sync (6)'event or done = '1';
            if sync (6)'event then
                if sync (6) = '0' then
                    if start_of_r_sync /= 0 then
                        delta := uptime - start_of_r_sync;
                        write (l, String'("regenerator r_clocks = "));
                        write (l, count_r_clocks);
                        write (l, String'(" clocks = "));
                        write (l, delta);
                        writeline (output, l);
                    end if;
                    start_of_r_sync <= 0;
                    count_r_clocks <= 0;
                else
                    start_of_r_sync <= uptime;
                    count_r_clocks <= 0;
                end if;
            elsif sync (6) = '1' and rg_strobe'event and rg_strobe = '1' then
                count_r_clocks <= count_r_clocks + 1;
            end if;
        end loop;
        wait;
    end process check_regenerator;

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

        procedure write_hex_nibble (x : std_logic_vector (3 downto 0)) is
        begin
            assert x (0) = '0' or x (0) = '1';
            assert x (1) = '0' or x (1) = '1';
            assert x (2) = '0' or x (2) = '1';
            assert x (3) = '0' or x (3) = '1';
            case to_integer (unsigned (x)) is
                when 10 => write (l, String'("a"));
                when 11 => write (l, String'("b"));
                when 12 => write (l, String'("c"));
                when 13 => write (l, String'("d"));
                when 14 => write (l, String'("e"));
                when 15 => write (l, String'("f"));
                when others => write (l, to_integer (unsigned (x)));
            end case;
        end write_hex_nibble;

        procedure write_hex_sample (x : std_logic_vector (23 downto 0)) is
            variable j : Integer;
        begin
            j := 20;
            for i in 1 to 6 loop
                write_hex_nibble (x (j + 3 downto j));
                j := j - 4;
            end loop;
        end write_hex_sample;
    begin
        wait until clock'event and clock = '1';
        assert raw_data = '0' or raw_data = '1';
        assert done = '0' or done = '1';
        assert pulse_length (0) = '0' or pulse_length (0) = '1';
        assert pulse_length (1) = '0' or pulse_length (1) = '1';
        assert packet_data = '0' or packet_data = '1';
        assert packet_start = '0' or packet_start = '1';
        assert packet_shift = '0' or packet_shift = '1';
        assert left_strobe = '0' or left_strobe = '1';
        assert right_strobe = '0' or right_strobe = '1';
        assert data (0) = '0' or data (0) = '1';

        while done /= '1' loop
            if left_strobe = '1' then
                left_data <= data;
            end if;
            if right_strobe = '1' then
                write_hex_sample (left_data (27 downto 4));
                write (l, String'(" "));
                write_hex_sample (data (27 downto 4));
                writeline (output, l);
            end if;
            wait until clock'event and clock = '1';
        end loop;
        wait;
    end process printer;

end structural;

