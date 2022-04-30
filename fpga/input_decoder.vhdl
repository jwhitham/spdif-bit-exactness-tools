
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

    subtype t_sync_counter is unsigned (0 to 4);
    subtype t_data_counter is unsigned (0 to 5);
    subtype t_pending is Natural range 0 to 3;

    constant zero_data_counter  : t_data_counter := (others => '0');
    constant zero_sync_counter  : t_sync_counter := (others => '0');
    constant max_sync_counter   : t_data_counter := (others => '1');

    -- max allows for *2 and *3
    constant max_data_counter   : t_data_counter :=
        (0 => '0', 1 => '1', others => '0');

    signal delay0, delay1       : std_logic := '0';
    signal skip                 : std_logic := '0';
    signal sync_counter         : t_sync_counter := zero_sync_counter;
    signal data_counter         : t_data_counter := zero_data_counter;
    signal single_pulse_length  : t_data_counter := zero_data_counter;
    signal double_pulse_length  : t_data_counter := zero_data_counter;
    signal triple_pulse_length  : t_data_counter := zero_data_counter;
    signal pending              : t_pending := 0;
begin

    process (clock)
    begin
        if clock'event and clock = '1' then
            single_pulse <= '0';
            double_pulse <= '0';
            triple_pulse <= '0';

            if delay0 = delay1 then
                if data_counter = max_data_counter then
                    -- lost synchronisation - no signal, force resync
                    single_pulse_length <= max_data_counter;
                    sync_counter <= zero_sync_counter;
                    data_counter <= zero_data_counter;
                    pending <= 0;
                else
                    if data_counter = triple_pulse_length then
                        pending <= 3;
                    elsif data_counter = double_pulse_length then
                        pending <= 2;
                    elsif data_counter = single_pulse_length then
                        pending <= 1;
                    end if;
                    data_counter <= data_counter + 1;
                end if;
            else
                -- state transition - synchronise?
                if sync_counter = max_sync_counter then
                    -- synchronised - seen many transitions
                    -- without updating the pulse length
                    case pending is
                        when 1 => 
                            single_pulse <= '1';
                        when 2 => 
                            double_pulse <= '1';
                        when 3 => 
                            triple_pulse <= '1';
                        when others =>
                            -- pulse is too short, resynchronise
                            single_pulse_length <= max_data_counter;
                            sync_counter <= zero_sync_counter;
                    end case;
                else
                    -- transition seen
                    if (data_counter srl 1) = zero_data_counter then
                        -- transition is too soon: resync
                        single_pulse_length <= max_data_counter;
                        sync_counter <= zero_sync_counter;

                    elsif single_pulse_length > data_counter then
                        -- shorter pulse seen: update comparators, resync
                        single_pulse_length <= data_counter;
                        sync_counter <= zero_sync_counter;

                    else
                        -- become more synchronised
                        sync_counter <= sync_counter + 1;
                    end if;
                end if;
                pending <= 0;
                data_counter <= zero_data_counter;
            end if;
            delay0 <= data_in;
            delay1 <= delay0;
        end if;
    end process;

    double_pulse_length <= data_counter + data_counter;
    triple_pulse_length <= data_counter + double_pulse_length;

end structural;
