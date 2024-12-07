
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use debug_textio.all;

entity test_sign_magnitude is
end test_sign_magnitude;

architecture test of test_sign_magnitude is

    constant tc_width       : Integer := 8;
    constant upper_limit    : Integer := (2 ** (tc_width - 1)) - 1;

    signal c1_neg_in        : std_logic := '0';
    signal c2_neg_out       : std_logic := '0';
    signal c3_neg_out       : std_logic := '0';
    signal c1_in            : std_logic_vector (tc_width - 2 downto 0) := (others => '0');
    signal c1_out           : std_logic_vector (tc_width - 1 downto 0) := (others => '0');
    signal c2_out           : std_logic_vector (tc_width - 2 downto 0) := (others => '0');
    signal c3_in            : std_logic_vector (tc_width - 1 downto 0) := (others => '0');
    signal c3_out           : std_logic_vector (tc_width - 2 downto 0) := (others => '0');

begin

    c1 : entity convert_from_sign_magnitude
        generic map (value_width => tc_width)
        port map (value_in => c1_in,
                  value_negative_in => c1_neg_in,
                  value_out => c1_out);

    c2 : entity convert_to_sign_magnitude
        generic map (value_width => tc_width)
        port map (value_in => c1_out,
                  value_negative_out => c2_neg_out,
                  value_out => c2_out);

    c3 : entity convert_to_sign_magnitude
        generic map (value_width => tc_width)
        port map (value_in => c3_in,
                  value_negative_out => c3_neg_out,
                  value_out => c3_out);

    process
    begin
        for magnitude in 0 to upper_limit loop
            for sign in 0 to 1 loop
                c1_in <= std_logic_vector (to_unsigned (magnitude, tc_width - 1));
                c1_neg_in <= '0';
                if sign /= 0 then
                    c1_neg_in <= '1';
                end if;
                wait for 1 ns;
                if magnitude /= 0 then
                    assert c2_neg_out = c1_neg_in;
                end if;
                assert c2_out = c1_in;
            end loop;
        end loop;

        for value in upper_limit downto (- upper_limit - 1) loop
            c3_in <= std_logic_vector (to_signed (value, tc_width));
            wait for 1 ns;
            if value >= 0 then
                assert c3_neg_out = '0';
                assert c3_out = std_logic_vector (to_unsigned (value, tc_width - 1));
            else
                assert c3_neg_out = '1';
                if value >= (-upper_limit) then
                    assert c3_out = std_logic_vector (to_unsigned (-value, tc_width - 1));
                else
                    -- Special case: -128 (two's complement) becomes -127
                    -- as -128 cannot be encoded in 7-bit sign-magnitude
                    assert c3_out = std_logic_vector (to_unsigned (upper_limit, tc_width - 1));
                end if;
            end if;
        end loop;
        wait;
    end process;


end test;
