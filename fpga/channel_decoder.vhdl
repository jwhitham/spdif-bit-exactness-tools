
library ieee;
use ieee.std_logic_1164.all;

entity channel_decoder is
    port (
        data_in         : in std_logic;
        shift_in        : in std_logic;
        start_in        : in std_logic;
        sync_in         : in std_logic;
        left_data_out   : out std_logic_vector (31 downto 0);
        left_strobe_out : out std_logic;
        right_data_out  : out std_logic_vector (31 downto 0);
        right_strobe_out: out std_logic;
        sync_out        : out std_logic;
        clock           : in std_logic
    );
end channel_decoder;

architecture structural of channel_decoder is

    signal parity       : std_logic := '1';
    signal data         : std_logic_vector (31 downto 0) := (others => '0');
    signal left_data    : std_logic_vector (31 downto 0) := (others => '0');
    signal left_strobe  : std_logic := '0';
    signal right_data   : std_logic_vector (31 downto 0) := (others => '0');
    signal right_strobe : std_logic := '0';
    signal expect_right : std_logic := '0';
    signal synced       : std_logic := '0';
begin

    left_data_out <= left_data;
    left_strobe_out <= left_strobe;
    right_data_out <= right_data;
    right_strobe_out <= right_strobe;
    sync_out <= synced;

    process (clock)
    begin
        if clock'event and clock = '1' then
            left_strobe <= '0';
            right_strobe <= '0';

            if shift_in = '1' and sync_in = '1' then
                if start_in = '1' then
                    synced <= '0';
                    if parity = '1' then
                        case data (3 downto 0) is
                            when "0100" | "0001" =>
                                -- B or M: left channel
                                left_data <= data;
                                left_strobe <= '1';
                                expect_right <= '1';
                                synced <= '1';
                            when "0010" =>
                                -- W: additional channel
                                if expect_right = '1' then
                                    right_data <= data;
                                    right_strobe <= '1';
                                end if;
                                expect_right <= '0';
                                synced <= '1';
                            when others =>
                                null;
                        end case;
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
