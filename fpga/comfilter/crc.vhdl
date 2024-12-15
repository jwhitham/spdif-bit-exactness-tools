library comfilter;
use comfilter.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The generic defaults are the correct settings for CRC-32, matching the zlib.crc32 function,
-- assuming that bits are shifted LSB first.
--
-- For CRC-16 use polynomial = x"8005", bit_width = 16, flip = false.
--
-- Test: crc16("123456789") == 0xbb3d
-- Test: crc32("123456789") == 0xcbf43926
--
entity crc is
    generic (
        bit_width       : Natural := 32;
        polynomial      : Natural := 16#04C11DB7#;
        flip            : Boolean := true);
    port (
        clock_in        : in std_logic := '0';
        reset_in        : in std_logic := '0';
        strobe_in       : in std_logic := '0';
        data_in         : in std_logic := '0';
        crc_out         : out std_logic_vector (bit_width - 1 downto 0) := (others => '0'));
end entity crc;

architecture structural of crc is

    signal invert_bit       : std_logic := '0';
    signal apply_bit        : std_logic := '0';
    signal invert_bits      : std_logic_vector (bit_width - 1 downto 0) := (others => '0');
    signal next_value       : std_logic_vector (bit_width - 1 downto 0) := (others => '0');
    signal value            : std_logic_vector (bit_width - 1 downto 0) := (others => '0');

begin

    invert_bit <= '1' when flip else '0';
    invert_bits <= (others => invert_bit);
    next_value (bit_width - 1 downto 1) <= value (bit_width - 2 downto 0);
    next_value (0) <= '0';
    apply_bit <= value (bit_width - 1) xor data_in;

    process (clock_in) is
        variable p : Natural := 0;
    begin
        if clock_in = '1' and clock_in'event then
            if reset_in = '1' then
                value <= invert_bits;

            elsif strobe_in = '1' then
                p := polynomial;
                for i in 0 to bit_width - 1 loop
                    if ((p mod 2) = 1) then
                        value (i) <= apply_bit xor next_value (i);
                    else
                        value (i) <= next_value (i);
                    end if;
                    p := p / 2;
                end loop;
            end if;
        end if;
    end process;

    process (value, invert_bit) is
    begin
        for i in 0 to bit_width - 1 loop
            crc_out (bit_width - 1 - i) <= value (i) xor invert_bit;
        end loop;
    end process;

end structural;

