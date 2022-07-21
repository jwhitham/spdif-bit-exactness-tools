
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;

entity test_disable_compressor is
end test_disable_compressor;

architecture test of test_disable_compressor is

    subtype t_data is std_logic_vector (15 downto 0);

    signal clock            : std_logic := '0';
    signal done             : std_logic := '0';
    signal data_in          : t_data := (others => '0');
    signal left_strobe_in   : std_logic := '0';
    signal right_strobe_in  : std_logic := '0';
    signal enable_strobes   : std_logic := '0';

    constant sample_rate    : Natural := 1000;
    constant sample_period  : Time := 1000 ms / sample_rate;
    constant clock_period   : Time := sample_period / 1000;
    constant fpga_freq_mhz  : Natural := 96;

    constant one            : std_logic := '1';

    signal data_out         : t_data := (others => '0');
    signal left_strobe_out  : std_logic := '0';
    signal right_strobe_out : std_logic := '0';
    signal sync_out         : std_logic := '0';
    signal enable           : std_logic := '0';

    type t_test_numbers is array (Natural range <>) of Integer;
    constant test_numbers : t_test_numbers :=
        (-2483, -12278, 23458, 20125, -20618, -28339, 25736, 23287, -1643, 11680, 
         8841, 29258, -30211, -9006, 22641, 7948, 14077, 13768, 25655, -22529,
         -27210, -6751, 16367, -23749, -710, 24021, 16149, 10960, 2666, 31664,
         -24174, -2382, -14634, 4935, 18132, -23850, 25167, -361, 9294, -17965,
         -18278, -28744, 8372, 23020, 18307, -31098, -32206, -15434, 12334, 3364,
         30261, 7336, -8725, 27218, -26710, 13134, 12396, 25204, 15748, -14823,
         23497, -31531, -23969, -5014, -2279, 8489, -21564, 32429, 28623, -32658,
         -19428, 20230, -25610, -4104, 28284, 13857, 18411, 1997, -1861, -9559,
         12877, -5405, 9234, -25656, 2360, 10720, 16234, -25449, 13990, -25236,
         -29927, 20697, 26956, -5158, 32767, -32767, 0);

begin

    process
    begin
        -- 1MHz clock (one clock every 1000ns)
        while done /= '1' loop
            clock <= '1';
            wait for (clock_period / 2.0);
            clock <= '0';
            wait for (clock_period / 2.0);
        end loop;
        wait;
    end process;

    signal_generator : block
        signal sample_divider       : Natural := 0;
        signal sample_counter       : Natural := 0;
        signal sample_left          : std_logic := '1';
    begin
        process (clock)
        begin
            if clock'event and clock = '1' then
                left_strobe_in <= '0';
                right_strobe_in <= '0';

                if sample_divider = 0 then
                    if sample_left = '1' then
                        left_strobe_in <= '1';
                    else
                        right_strobe_in <= '1';
                    end if;
                    sample_left <= not sample_left;
                    sample_divider <= Natural ((sample_period / clock_period) / 2) - 1;
                    data_in <= std_logic_vector (to_signed (test_numbers (sample_counter), t_data'Length));
                    sample_counter <= (sample_counter + 1) mod test_numbers'Length;
                else
                    sample_divider <= sample_divider - 1;
                end if;
            end if;
        end process;
    end block signal_generator;

    dut : entity compressor
        generic map (debug => false,
                     delay_size_log_2 => 5,
                     delay_threshold_level => 0.5)
        port map (
            data_in => data_in,
            left_strobe_in => left_strobe_in,
            right_strobe_in => right_strobe_in,
            enable_in => enable,
            data_out => data_out,
            left_strobe_out => left_strobe_out,
            right_strobe_out => right_strobe_out,
            ready_out => open,
            sync_in => one,
            sync_out => sync_out,
            clock_in => clock);

    run_test : process
        variable l              : line;
        variable sample_counter : Natural := 0;
        variable value          : Integer := 0;
        variable expect         : Integer := 0;
        variable ok             : Boolean := false;

    begin
        done <= '0';
        enable <= '0';

        write (l, String'("Test for correct data throughput when compression is off"));
        writeline (output, l);

        -- check data is being generated
        wait until clock'event and clock = '1' and left_strobe_in = '1';
        wait until clock'event and clock = '1' and right_strobe_in = '1';

        -- The first sample on each channel is lost by the compressor.
        sample_counter := 2;

        -- wait for data from the output
        for i in 1 to (test_numbers'Length * 3) loop
            wait until clock'event and clock = '1' and (left_strobe_out or right_strobe_out) = '1';
            assert sync_out = '1';
            assert left_strobe_out /= right_strobe_out;
            value := to_integer (signed (data_out));
            expect := test_numbers (sample_counter);
            sample_counter := (sample_counter + 1) mod test_numbers'Length;
            if value /= expect then
                write (l, String'("Test "));
                write (l, i);
                write (l, String'(" expected "));
                write (l, expect);
                write (l, String'(" actually "));
                write (l, value);
                writeline (output, l);
                assert False;
                exit;
            end if;
        end loop;

        -- Turn on compression and we quickly lose accuracy - but
        -- hopefully not very much at first (if we did suddenly lose a lot of accuracy,
        -- that would point to a glitch, e.g. because the peak level is 1.0, but the
        -- maximum audio level is really 32767.0 / 32768.0, and the abs_compare comparison does not
        -- consider that the value might be 1.0).

        enable <= '1';
        write (l, String'("Enable compression!"));
        writeline (output, l);

        for i in 1 to 80 loop
            wait until clock'event and clock = '1' and (left_strobe_out or right_strobe_out) = '1';
            value := to_integer (signed (data_out));
            expect := test_numbers (sample_counter);
            sample_counter := (sample_counter + 1) mod test_numbers'Length;
            if value /= expect then
                ok := True;
                if abs (value - expect) > 5 then
                    write (l, String'("Lost more accuracy than expected at "));
                    write (l, i);
                    write (l, String'(" as expected: got "));
                    write (l, value);
                    write (l, String'(" lossless value is "));
                    write (l, expect);
                    writeline (output, l);
                    assert False;
                    exit;
                end if;
            end if;
        end loop;

        assert ok;

        done <= '1';
        wait;
    end process run_test;

end test;
