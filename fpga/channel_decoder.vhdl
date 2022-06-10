
library ieee;
use ieee.std_logic_1164.all;

entity channel_decoder is
    port (
        data_in         : in std_logic;
        shift_in        : in std_logic;
        start_in        : in std_logic;
        sync_in         : in std_logic;
        data_out        : out std_logic_vector (31 downto 0);
        left_strobe_out : out std_logic;
        right_strobe_out: out std_logic;
        sync_out        : out std_logic;
        clock           : in std_logic
    );
end channel_decoder;

architecture structural of channel_decoder is

    signal parity       : std_logic := '1';
    signal data         : std_logic_vector (31 downto 0) := (others => '0');
    signal left_data    : std_logic_vector (31 downto 0) := (others => '0');
    signal right_data   : std_logic_vector (31 downto 0) := (others => '0');
    signal expect_right : std_logic := '0';
    signal bm_packet    : std_logic := '0';
    signal w_packet     : std_logic := '0';
    signal synced       : std_logic := '0';
begin

    data_out <= data;
    left_strobe_out <= shift_in and synced and start_in and parity and bm_packet and not expect_right;
    right_strobe_out <= shift_in and synced and start_in and parity and w_packet and expect_right;
    sync_out <= synced;
    bm_packet <= '1' when (data (3 downto 0) = "0100" or data (3 downto 0) = "0001") else '0';
    w_packet <= '1' when (data (3 downto 0) = "0010") else '0';

    process (clock)
    begin
        if clock'event and clock = '1' then
            if shift_in = '1' and sync_in = '1' then
                if start_in = '1' then
                    synced <= '0';
                    if parity = '1' then
                        if bm_packet = '1' then
                            -- B or M: left channel
                            expect_right <= '1';
                            synced <= '1';
                        elsif w_packet = '1' then
                            -- W: right channel
                            expect_right <= '0';
                            synced <= '1';
                        end if;
                    end if;
                    parity <= data_in;
                else
                    parity <= parity xor data_in;
                end if;
                data (data'Left) <= data_in;

            elsif sync_in = '0' then
                synced <= '0';
                data (data'Left) <= '0';
                parity <= '0';
            end if;

            if sync_in = '0' or (shift_in = '1' and sync_in = '1') then
                data (data'Left - 1 downto 0) <= data (data'Left downto 1);
            end if;
        end if;
    end process;

end structural;
