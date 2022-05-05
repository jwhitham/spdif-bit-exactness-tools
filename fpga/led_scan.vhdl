
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_scan is
    port (
        leds1_in        : in std_logic_vector (7 downto 0);
        leds2_in        : in std_logic_vector (7 downto 0);
        leds3_in        : in std_logic_vector (7 downto 0);
        leds4_in        : in std_logic_vector (7 downto 0);
        lcols_out       : out std_logic_vector (3 downto 0) := "0000";
        lrows_out       : out std_logic_vector (7 downto 0) := "00000000";
        clock           : in std_logic);
end entity led_scan;

architecture structural of led_scan is

    signal counter : unsigned (0 to 12) := (others => '0');
begin
    process (clock)
    begin
        if clock = '1' and clock'event then
            -- multiplex rows
            case counter (counter'Left to counter'Left + 1) is
                when "00" =>
                    lrows_out <= not leds1_in;
                    lcols_out <= "1110";
                when "01" =>
                    lrows_out <= not leds2_in;
                    lcols_out <= "1101";
                when "10" =>
                    lrows_out <= not leds3_in;
                    lcols_out <= "1011";
                when others =>
                    lrows_out <= not leds4_in;
                    lcols_out <= "0111";
            end case;

            -- hide row transitions - go dark for 1/8th of the time
            case counter (counter'Left + 2 to counter'Left + 5) is
                when "0000" | "1111" =>
                    lcols_out <= "1111";
                when others =>
                    null;
            end case;

            counter <= counter + 1;
        end if;
    end process;
end structural;

