

library comfilter;
use comfilter.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity subtractor is
    port (
        d_out               : out std_logic := '0';
        x_in, y_in          : in std_logic := '0';
        reset_in            : in std_logic := '0';
        strobe_in           : in std_logic := '0';
        clock_in            : in std_logic := '0');
end subtractor;

architecture structural of subtractor is
    signal b_value : std_logic := '0';
begin
    process (clock_in) is
    begin
        if clock_in = '1' and clock_in'event then
            if strobe_in = '1' then
                -- effectively: b_value := x_in < (y_in + b_in)
                if y_in = '1' and b_value = '1' then
                    b_value <= '1';
                elsif y_in = '1' or b_value = '1' then
                    b_value <= not x_in;
                else
                    b_value <= '0';
                end if;
            end if;

            if reset_in = '1' then
                b_value <= '0';
            end if;
        end if;
    end process;

    d_out <= x_in xor y_in xor b_value;

end structural;

