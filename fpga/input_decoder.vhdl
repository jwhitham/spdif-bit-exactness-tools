
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

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

    subtype t_sync_counter is unsigned (0 to 2);
    subtype t_transition_time is unsigned (0 to 3);

    constant zero_transition_time   : t_transition_time := (others => '0');
    constant max_transition_time    : t_transition_time := (others => '1');
    constant max_single_time        : t_transition_time := max_transition_time srl 2;
    constant zero_sync_counter      : t_sync_counter := (others => '0');
    constant max_sync_counter       : t_sync_counter := (others => '1');

    signal delay0               : std_logic := '0';
    signal sync_counter         : t_sync_counter := zero_sync_counter;
    signal transition_time      : t_transition_time := zero_transition_time;
    signal transition_counter   : t_transition_time := zero_transition_time;
    signal single_time          : t_transition_time := max_single_time;
    signal double_time          : t_transition_time := max_transition_time;
    signal triple_time          : t_transition_time := max_transition_time;
    signal quad_time            : t_transition_time := max_transition_time;
begin

    -- detect transitions
    process (clock)
        variable l : line;
    begin
        if clock'event and clock = '1' then
            delay0 <= data_in;
            transition_time <= zero_transition_time;

            if delay0 = data_in then
                if transition_counter /= max_transition_time then
                    transition_counter <= transition_counter + 1;
                end if;
            else
                transition_counter <= zero_transition_time + 1;
                transition_time <= transition_counter;
            end if;
        end if;
    end process;

    double_time <= single_time + single_time;
    triple_time <= double_time + single_time;
    quad_time <= double_time + double_time;

    -- Determine the time for a single transition ("synchronise").
    -- Once synchronised, classify transitions as single, double or triple.
    process (clock)
    begin
        if clock'event and clock = '1' then
            single_pulse <= '0';
            double_pulse <= '0';
            triple_pulse <= '0';

            if transition_time = zero_transition_time then
                -- No transition, do nothing
                null;
            elsif transition_time >= quad_time then
                -- Invalid transition - start syncing again
                sync_counter <= zero_sync_counter;
                single_time <= max_single_time;
            else
                -- Normal transition
                if sync_counter = max_sync_counter then
                    -- Synced: generate pulse
                    if transition_time >= triple_time then
                        triple_pulse <= '1';
                    elsif transition_time >= double_time then
                        double_pulse <= '1';
                    else
                        single_pulse <= '1';
                    end if;
                else
                    -- Not synced: capture shortest pulse
                    if transition_time < single_time then
                        single_time <= transition_time;
                    end if;
                    sync_counter <= sync_counter + 1;
                end if;
            end if;
        end if;
    end process;

end structural;
