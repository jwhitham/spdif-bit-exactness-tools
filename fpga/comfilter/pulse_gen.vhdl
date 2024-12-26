

library ieee;
use ieee.std_logic_1164.all;

entity pulse_gen is
    generic (
        in_frequency  : Real;
        out_frequency : Real);
    port (
        pulse_out       : out std_logic := '0';
        clock_enable_in : in std_logic;
        clock_in        : in std_logic);
end pulse_gen;

architecture structural of pulse_gen is

    constant counter_max  : Natural :=
            Natural (in_frequency / out_frequency) - 1;
    subtype t_counter is Natural range 0 to counter_max;

    signal counter        : t_counter := 0;

begin
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            pulse_out <= '0';
            if clock_enable_in = '1' then
                if counter = counter_max then
                    counter <= 0;
                    pulse_out <= '1';
                else
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;
end architecture structural;
