
library ieee;
use ieee.std_logic_1164.all;

entity channel_encoder is
    port (
        data_out        : out std_logic;
        shift_out       : out std_logic;
        start_out       : out std_logic;
        sync_out        : out std_logic;
        data_in         : in std_logic_vector (31 downto 0);
        left_strobe_in  : in std_logic;
        right_strobe_in : in std_logic;
        sync_in         : in std_logic;
        clock           : in std_logic
    );
end channel_encoder;

architecture structural of channel_encoder is

    subtype t_counter is Natural range 0 to 31;
    signal parity       : std_logic := '0';
    signal waiting      : std_logic := '0';
    signal data         : std_logic_vector (31 downto 0) := (others => '0');
    signal counter      : t_counter := 0;
begin

    data_out <= data (0);

    process (clock)
    begin
        if clock'event and clock = '1' then
            start_out <= '0';
            shift_out <= '0';
            sync_out <= sync_in;

            if waiting = '1' then
                assert left_strobe_in = '0';
                assert right_strobe_in = '0';
                waiting <= '0';
            elsif sync_in = '1' and (left_strobe_in = '1' or right_strobe_in = '1') then
                assert (data_in (3 downto 0) = "0100") or (data_in (3 downto 0) = "0001") or (data_in (3 downto 0) = "0010");
                counter <= 31;
                data <= data_in;
                parity <= '1';
                start_out <= '1';
                shift_out <= '1';
                waiting <= '1';
            elsif counter /= 0 then
                assert left_strobe_in = '0';
                assert right_strobe_in = '0';
                waiting <= '1';
                counter <= counter - 1;
                data (data'Left - 1 downto 0) <= data (data'Left downto 1);
                data (data'Left) <= '0';
                shift_out <= '1';
                parity <= parity xor data (0);
                if counter = 1 then
                    data (0) <= parity;
                end if;
            end if;
        end if;
    end process;

end structural;
