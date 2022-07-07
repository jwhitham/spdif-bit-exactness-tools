
import sys
import typing


PAYLOAD = [
    0xc6, 0x4e, 0x65, 0x5e, 0x25, 0x76, 0x7d, 0x56, 0xf6, 0x69, 0x51, 0xf3,
    0xb6, 0x18, 0x1d, 0x76, 0x4d, 0xc1, 0xdb, 0x5e, 0x40, 0xd9, 0x9e, 0x0d,
    0x50, 0x8a, 0x48, 0xdd, 0xe3, 0xb3, 0x0d, 0x0c, 0x8f, 0xaf, 0xaf, 0xe6,
    0x5e, 0x41, 0x95, 0xb3, 0x66, 0x70, 0x01, 0x40, 0x81, 0x7f, 0x24, 0xda,
    0xf1, 0xeb, 0xf8, 0xc9, 0x5a, 0x20, 0xc9, 0x75, 0xc3, 0xea, 0xd0, 0x96,
    0x1c, 0x8d, 0xe3, 0xb3, 0x8f, 0xb4, 0x08, 0xcf, 0xb5, 0x55, 0xea, 0x6d,
    0x66, 0x3e, 0x48, 0x74, 0xec, 0x54, 0x5b, 0x0f, 0xf4, 0x01, 0x20, 0x3c,
    0x18, 0x52, 0x8c, 0xda, 0x9a, 0x00, 0x9a, 0xa2, 0x38, 0xbb, 0x69, 0x74,
    0xae, 0x80, 0x6a, 0xc5, 0x59, 0x62, 0xd1, 0x80, 0xc9, 0x1e, 0xd2, 0x5d,
    0x69, 0x35, 0x06, 0x4e, 0xae, 0x62, 0xb1, 0xab, 0x35, 0x35, 0xcc, 0x54,
    0x35, 0xb9, 0xff, 0x91, 0xa5, 0x58, 0x62, 0xf8
]

TRUE_MARKER_POSITION = 24
FINAL_PART_POSITION = 32
MARKER_VALUE = 0x654321
REPEAT_SIZE = 40


def generate(index: int) -> typing.Tuple[int, int]:
    assert 0 <= index < REPEAT_SIZE
    if index < TRUE_MARKER_POSITION:
        left = 1 << index
        right = (1 << index) ^ 0xffffff
    elif index == TRUE_MARKER_POSITION:
        left = 0  # sample rate here
        right = MARKER_VALUE
    elif index < FINAL_PART_POSITION:
        # third part of the repeating block: 16 bit data (7 samples)
        j = (index - TRUE_MARKER_POSITION - 1) * 4
        left =  (PAYLOAD[j + 0] << 16) | (PAYLOAD[j + 1] << 8)
        right = (PAYLOAD[j + 2] << 16) | (PAYLOAD[j + 3] << 8)
    else:
        # final part of the repeating block: 24 bit data (8 samples)
        j = (((FINAL_PART_POSITION - TRUE_MARKER_POSITION - 1) * 4) 
                + ((index - FINAL_PART_POSITION) * 6))
        left =  (PAYLOAD[j + 0] << 16) | (PAYLOAD[j + 1] << 8) | (PAYLOAD[j + 2] << 0)
        right = (PAYLOAD[j + 3] << 16) | (PAYLOAD[j + 4] << 8) | (PAYLOAD[j + 5] << 0)

    return (left, right)

def main() -> None:
    with open("app/matcher/match_rom.vhdl", "wt") as fd:
        fd.write("""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity match_rom is
    port (
        address_in       : in std_logic_vector (6 downto 0) := (others => '0');
        data_out         : out std_logic_vector (23 downto 0) := (others => '0');
        clock            : in std_logic
    );
end match_rom;

architecture structural of match_rom is
begin
    process (clock)
    begin
        if clock = '1' and clock'event then
            case address_in is
""")
        for i in range(REPEAT_SIZE):
            (left, right) = generate((i + TRUE_MARKER_POSITION) % REPEAT_SIZE)
            fd.write('when "{:07b}" => data_out <= "{:024b}";\n'.format(i << 1, left))
            fd.write('when "{:07b}" => data_out <= "{:024b}";\n'.format((i << 1) | 1, right))
        fd.write('when others =>   data_out <= "{:024b}";\n'.format(0))
        fd.write("""
            end case;
        end if;
    end process;
end structural;
""")

if __name__ == "__main__":
    main()

