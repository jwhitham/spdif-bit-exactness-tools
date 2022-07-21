
import subprocess


def main() -> None:
    bits = 0xaaaaaaaa
    p = subprocess.Popen(["git", "rev-parse", "HEAD"], stdout=subprocess.PIPE, text=True)
    (git_hash, _) = p.communicate()
    git_hash = git_hash.strip()
    if (p.wait() == 0) and len(git_hash) != 0:
        bits = int(git_hash[:8], 16)
                     
    with open("app/generated/version_rom.vhdl", "wt") as fd:
        fd.write("""
library ieee;
use ieee.std_logic_1164.all;

entity version_rom is
    port (data_out : out std_logic_vector (31 downto 0) := (others => '0'));
end version_rom;

architecture structural of version_rom is
begin
    -- full: {}
    -- hex:  {:08x}
    -- bits:
data_out <= "{:032b}";
end architecture structural;
""".format(git_hash, bits, bits))

if __name__ == "__main__":
    main()

