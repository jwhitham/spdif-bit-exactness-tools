
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library comfilter;
use comfilter.all;
use debug_textio.all;

entity shift_register is
    generic (
        name          : String;
        size          : Natural;
        verbose_debug : Boolean := false);
    port (
        reg_out             : out std_logic := '0';
        negative_out        : out std_logic := '0';
        debug_out           : out std_logic_vector(size - 1 downto 0) := (others => '0');
        shift_right_in      : in std_logic := '0';
        reg_in              : in std_logic := '0';
        clock_in            : in std_logic := '0');
end shift_register;

architecture structural of shift_register is
    signal value : std_logic_vector(size - 1 downto 0) := (others => '0');
begin
    process (clock_in) is
        variable l : line;
        variable new_value : std_logic_vector(size - 1 downto 0) := (others => '0');
    begin
        if clock_in = '1' and clock_in'event then
            -- check for metastable states:
            assert reg_in = '1' or reg_in = '0';
            assert shift_right_in = '1' or shift_right_in = '0';

            if shift_right_in = '1' then
                new_value(size - 1) := reg_in;
                new_value(size - 2 downto 0) := value(size - 1 downto 1);
                value <= new_value;
                if verbose_debug then
                    write (l, name);
                    write (l, String'(" := "));
                    write (l, Integer'(ieee.numeric_std.to_integer(signed(new_value))));
                    writeline (output, l);
                end if;
            end if;
        end if;
    end process;

    debug_out <= value;
    reg_out <= value(0);
    negative_out <= value(size - 1);

end structural;

