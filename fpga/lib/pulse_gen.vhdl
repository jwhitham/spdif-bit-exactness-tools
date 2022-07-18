

library ieee;
use ieee.std_logic_1164.all;

entity pulse_gen is
    generic (
        clock_frequency : Real;
        pulse_frequency : Real);
    port (
        pulse_out     : out std_logic := '0';
        clock_in      : in std_logic);
end pulse_gen;

architecture structural of pulse_gen is

    constant countdown_max  : Natural :=
            Natural (clock_frequency / pulse_frequency) - 1;
    subtype t_countdown is Natural range 0 to countdown_max;

    signal countdown        : t_countdown := countdown_max;

begin
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            pulse_out <= '0';
            if countdown = 0 then
                countdown <= countdown_max;
                pulse_out <= '1';
            else
                countdown <= countdown - 1;
            end if;
        end if;
    end process;
end architecture structural;
