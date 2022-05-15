
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

entity matcher is
    port (
        left_data_in    : in std_logic_vector (31 downto 0);
        left_strobe_in  : in std_logic;
        right_data_in   : in std_logic_vector (31 downto 0);
        right_strobe_in : in std_logic;
        sync_out        : out std_logic := '0';
        sample_rate_out : out std_logic_vector (15 downto 0) := (others => '0');
        clock           : in std_logic
    );
end entity matcher;

architecture structural of matcher is

    subtype t_address is unsigned (5 downto 0);
    subtype t_sample is std_logic_vector (23 downto 0);

    constant zero_address : t_address := (others => '0');
    constant max_address  : t_address := to_unsigned (40, 6);

    signal address      : t_address := (others => '0');
    signal left_match   : t_sample := (others => '0');
    signal right_match  : t_sample := (others => '0');
    signal left_in      : t_sample := (others => '0');
    signal right_in     : t_sample := (others => '0');
    signal left_match_flag   : std_logic := '0';

    component match_rom is
        port (
            address_in       : in std_logic_vector (5 downto 0) := (others => '0');
            left_out         : out std_logic_vector (23 downto 0) := (others => '0');
            right_out        : out std_logic_vector (23 downto 0) := (others => '0');
            clock            : in std_logic);
    end component match_rom;

    function reverse (x : t_sample) return t_sample is
        variable y : t_sample := (others => '0');
    begin
        for i in t_sample'Range loop
            y (t_sample'Left - i) := x (i);
        end loop;
        return y;
    end reverse;

begin
    mr : match_rom
        port map (
            address_in => std_logic_vector (address),
            left_out => left_match,
            right_out => right_match,
            clock => clock);

    left_in <= left_data_in (27 downto 4);
    right_in <= right_data_in (27 downto 4);

    process (clock)
        variable l : line;
    begin
        if clock = '1' and clock'event then
            if left_strobe_in = '1' then
                if address = zero_address then
                    left_match_flag <= '1';
                    sample_rate_out <= left_in (23 downto 8);
                    write (l, String'("X LEFT MATCH (zero)"));
                    writeline (output, l);
                elsif left_match (23 downto 8) = left_in (23 downto 8) then
                    left_match_flag <= '1';
                    write (l, String'("X LEFT MATCH (non zero)"));
                    writeline (output, l);
                else
                    left_match_flag <= '0';
                    write (l, String'("X LEFT RESET"));
                    writeline (output, l);
                end if;
            end if;
        end if;
    end process;

    process (clock)
        variable l : line;

        procedure write_hex_nibble (x : std_logic_vector (3 downto 0)) is
        begin
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

        procedure write_hex_sample (x : t_sample) is
            variable j : Integer;
        begin
            j := 20;
            for i in 1 to 6 loop
                write_hex_nibble (x (j + 3 downto j));
                j := j - 4;
            end loop;
        end write_hex_sample;
    begin
        if clock = '1' and clock'event then
            if right_strobe_in = '1' then
                if right_match (23 downto 8) = right_in (23 downto 8) and left_match_flag = '1' then
                    if address = max_address then
                        address <= zero_address;
                        sync_out <= '1';
                        write (l, String'("X RIGHT DONE"));
                        writeline (output, l);
                    else
                        address <= address + 1;
                        write (l, String'("X RIGHT MATCH"));
                        writeline (output, l);
                    end if;
                else
                    write (l, String'("X RIGHT check "));
                    write_hex_sample (right_match);
                    write (l, String'(" "));
                    write_hex_sample (right_in);
                    writeline (output, l);
                    sync_out <= '0';
                    address <= zero_address;
                    write (l, String'("X RIGHT RESET"));
                    writeline (output, l);
                end if;
            end if;
        end if;
    end process;

end structural;
