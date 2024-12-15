

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

    constant counter_max  : Natural :=
            Natural (clock_frequency / pulse_frequency) - 1;
    subtype t_counter is Natural range 0 to counter_max;

    signal counter        : t_counter := 0;

begin
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            pulse_out <= '0';
            if counter = counter_max then
                counter <= 0;
                pulse_out <= '1';
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;
end architecture structural;
