
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
        preemph_in      : in std_logic;
        cd_source_in    : in std_logic;
        sync_in         : in std_logic;
        clock           : in std_logic
    );
end channel_encoder;

architecture structural of channel_encoder is

    signal parity       : std_logic := '0';
    signal waiting      : std_logic := '0';
    signal data         : std_logic_vector (30 downto 0) := (others => '0');

    constant b_interval     : Natural := 192;

    subtype t_status_counter is Natural range 0 to b_interval;
    signal status_counter   : t_status_counter := 0;

    subtype t_bit_counter is Natural range 0 to 31;
    signal bit_counter      : t_bit_counter := 0;
    constant status_bit     : t_status_counter := 30;
    constant user_bit       : t_status_counter := 29;
    constant validity_bit   : t_status_counter := 28;
begin

    data_out <= data (0);

    process (clock)
    begin
        if clock'event and clock = '1' then
            start_out <= '0';
            shift_out <= '0';

            if sync_in = '0' then
                bit_counter <= 0;
                status_counter <= 0;
                sync_out <= '0';
                waiting <= '0';

            elsif waiting = '1' then
                waiting <= '0';

            elsif left_strobe_in = '1' or right_strobe_in = '1' then
                bit_counter <= 31;
                data <= data_in (30 downto 0);

                -- Generate B/M header
                if left_strobe_in = '1' then
                    if status_counter = 0 or status_counter = b_interval then
                        data (3 downto 0) <= "0001"; -- Output B
                        status_counter <= 1;
                        sync_out <= '1';
                    else
                        data (3 downto 0) <= "0100"; -- Output M
                        status_counter <= status_counter + 1;
                    end if;
                else
                    data (3 downto 0) <= "0010"; -- Output W
                end if;
                -- See https://www.minidisc.org/manuals/an22.pdf for description of channel status bits
                -- They repeat periodically, beginning with a B packet, which is sent every b_interval.
                case status_counter is
                    when 2 =>
                        data (status_bit) <= '1'; -- copy
                    when 8 =>
                        data (status_bit) <= cd_source_in; -- category 0x40 - CD
                    when 13 =>
                        data (status_bit) <= not cd_source_in; -- category 0x02 - PCM encoder/decoder
                    when 3 =>
                        data (status_bit) <= preemph_in;
                    when others =>
                        data (status_bit) <= '0';
                end case;
                data (validity_bit) <= '0'; -- can be D/A converted
                data (user_bit) <= '0';

                parity <= '1';
                start_out <= '1';
                shift_out <= '1';
                waiting <= '1';

            elsif bit_counter /= 0 then
                assert left_strobe_in = '0';
                assert right_strobe_in = '0';
                waiting <= '1';
                bit_counter <= bit_counter - 1;
                data (data'Left - 1 downto 0) <= data (data'Left downto 1);
                data (data'Left) <= '0';
                shift_out <= '1';
                parity <= parity xor data (0);
                if bit_counter = 1 then
                    data (0) <= parity;
                end if;
            end if;
        end if;
    end process;

end structural;
