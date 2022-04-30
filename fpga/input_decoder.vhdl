
library ieee;
use ieee.std_logic_1164.all;

entity input_decoder is
    port (
        data_in         : in std_logic;
        single_pulse    : out std_logic;
        double_pulse    : out std_logic;
        triple_pulse    : out std_logic;
        clock           : in std_logic
    );
end input_decoder;

architecture structural of input_decoder is

    subtype t_sync_counter is std_logic_vector (4 downto 0);
    signal delay0, delay1       : std_logic := '0';
    signal skip                 : std_logic := '0';
    signal sync_counter         : t_sync_counter := zero_counter;
    signal data_counter         : t_sync_counter := zero_counter;
    constant zero_counter       : t_sync_counter := (others => '0');
    constant max_counter        : t_sync_counter := (others => '1');
    signal single_pulse_length  : t_sync_counter := zero_counter;
    signal double_pulse_length  : t_sync_counter := zero_counter;
    signal triple_pulse_length  : t_sync_counter := zero_counter;
begin

    process (clock)
    begin
        if clock'event and clock = '1' then
            single_pulse <= '0';
            double_pulse <= '0';
            triple_pulse <= '0';

            if delay0 = delay1 then
                if data_counter = max_counter then
                    -- lost synchronisation - no signal
                    sync_counter <= zero_counter;
                    data_counter <= zero_counter;
                    single_pulse_length <= max_counter;
                    double_pulse_length <= max_counter;
                    triple_pulse_length <= max_counter;
                else
                    data_counter <= data_counter + 1;
                end if;
            else
                -- state transition - synchronise?
                if sync_counter = max_counter then
                    -- synchronised - seen many transitions
                    if data_counter > triple_pulse_length then
                        triple_pulse <= '1';
                    elsif data_counter > double_pulse_length then
                        double_pulse <= '1';
                    else
                        single_pulse <= '1';
                    end if;
                else
                    -- transition seen: become more synchronised
                    sync_counter <= sync_counter + 1;
                    if (data_counter srl 1) = zero_counter then
                        -- transition is too soon, force resynchronise
                        sync_counter <= zero_counter;
                    elsif single_pulse_length > data_counter then
                        -- shorter pulse seen, update comparators
                        single_pulse_length <= data_counter;
                        double_pulse_length <= data_counter sll 1;
                        triple_pulse_length <= data_counter + (data_counter sll 1);
                    end if;
                end if;
                data_counter <= zero_counter;
            end if;
            delay0 <= data_in;
            delay1 <= delay0;
        end if;
    end process;

end structural;
