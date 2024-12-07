library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

use debug_textio.all;

entity channel_decoder is
    generic (debug      : Boolean := false);
    port (
        data_in         : in std_logic;
        shift_in        : in std_logic;
        start_in        : in std_logic;
        sync_in         : in std_logic;
        data_out        : out std_logic_vector (31 downto 0);
        subcode_out     : out std_logic_vector (31 downto 0);
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
    signal b_packet     : std_logic := '0';
    signal m_packet     : std_logic := '0';
    signal w_packet     : std_logic := '0';
    signal synced       : std_logic := '0';
    signal left_strobe  : std_logic := '0';
    signal right_strobe : std_logic := '0';
    signal subcode      : std_logic_vector (31 downto 0) := (others => '0');

    subtype t_subcode_counter is Natural range 0 to subcode'Length - 1;
    signal subcode_counter  : t_subcode_counter := 0;

    constant subcode_bit    : Natural := 30;

begin

    data_out <= data;
    left_strobe_out <= left_strobe;
    right_strobe_out <= right_strobe;
    left_strobe <= shift_in and synced and start_in and parity and bm_packet and not expect_right;
    right_strobe <= shift_in and synced and start_in and parity and w_packet and expect_right;
    sync_out <= synced;
    b_packet <= '1' when data (3 downto 0) = "0001" else '0';
    m_packet <= '1' when data (3 downto 0) = "0100" else '0';
    bm_packet <= b_packet or m_packet;
    w_packet <= '1' when (data (3 downto 0) = "0010") else '0';

    data_register : process (clock)
        variable l : line;
    begin
        if clock'event and clock = '1' then
            if shift_in = '1' and sync_in = '1' then
                if debug then
                    write (l, String'("channel decoder: shift in:"));
                    if start_in = '1' then
                        write (l, String'(" start"));
                    end if;
                    if data_in = '1' then
                        write (l, String'(" data"));
                    end if;
                    writeline (output, l);
                end if;

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
                        elsif debug then
                            write (l, String'("channel decoder: header error"));
                            writeline (output, l);
                        end if;
                    elsif debug then
                        write (l, String'("channel decoder: parity error"));
                        writeline (output, l);
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
    end process data_register;

    subcode_register : process (clock)
    begin
        if clock'event and clock = '1' then
            if sync_in = '0' then
                subcode_counter <= subcode'Length - 1;
                subcode_out <= (others => '0');

            elsif left_strobe = '1' then
                if b_packet = '1' then
                    -- beginning of new subcode data
                    subcode_counter <= subcode'Length - 1;
                    subcode (0) <= data (subcode_bit);
                    subcode_out <= subcode;
                elsif subcode_counter /= 0 then
                    -- additional subcode bit shifted in
                    subcode_counter <= subcode_counter - 1;
                    subcode (0) <= data (subcode_bit);
                    subcode (subcode'Left downto 1) <= subcode (subcode'Left - 1 downto 0);
                end if;
            end if;
        end if;
    end process subcode_register;

end structural;
