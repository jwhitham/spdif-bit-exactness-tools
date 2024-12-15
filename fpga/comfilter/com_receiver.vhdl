
library comfilter;
use comfilter.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity com_receiver is
    generic (
        clock_frequency : Real;
        baud_rate       : Real;
        num_data_bits   : Natural);
    port (
        serial_in     : in std_logic := '0';
        reset_in      : in std_logic := '0';
        clock_in      : in std_logic := '0';
        data_out      : out std_logic_vector (num_data_bits - 1 downto 0) := (others => '0');
        strobe_out    : out std_logic := '0');
end com_receiver;

architecture structural of com_receiver is

    constant num_crc_bits        : Natural := 16;
    constant stable_time_in_bits : Natural := 15;

    function compute_counter_bits return Natural is
        variable max_value : Natural := 16 * num_data_bits;
        variable num_bits : Natural := 0;
    begin
        if num_crc_bits > num_data_bits then
            max_value := 16 * num_crc_bits;
        end if;
        if stable_time_in_bits > num_data_bits then
            max_value := 16 * stable_time_in_bits;
        end if;
        while max_value > 0 loop
            num_bits := num_bits + 1;
            max_value := max_value / 2;
        end loop;
        return num_bits;
    end compute_counter_bits;

    constant num_counter_bits   : Natural := compute_counter_bits;

    type t_receive_state is (ZERO_SIGNAL, ONE_SIGNAL, READY,
                    START_BIT, DATA_BIT, CRC_BIT, STOP_BIT);

    signal baud_div_16          : std_logic := '0';
    signal crc_reset_strobe     : std_logic := '0';
    signal crc_strobe           : std_logic := '0';
    signal crc_data             : std_logic_vector (num_crc_bits - 1 downto 0) := (others => '0');
    signal data_strobe          : std_logic := '0';
    signal frame_strobe         : std_logic := '0';
    signal valid_crc            : std_logic := '0';
    signal serial_in_copy       : std_logic := '0';
    signal counter_16_reached   : std_logic := '0';
    signal counter_8_reached    : std_logic := '0';
    signal counter              : unsigned (num_counter_bits - 1 downto 0) := (others => '0');
    signal data_reg             : std_logic_vector (num_data_bits - 1 downto 0) := (others => '0');
    signal receive_state        : t_receive_state := ZERO_SIGNAL;


begin
    generate_clock_enable : entity pulse_gen
        generic map (
            clock_frequency => clock_frequency,
            pulse_frequency => baud_rate * 16.0)
        port map (
            pulse_out => baud_div_16,
            clock_in => clock_in);

    crc16 : entity crc
        generic map (
            bit_width => num_crc_bits,
            polynomial => 16#8005#,
            flip => false)
        port map (
            clock_in => clock_in,
            reset_in => crc_reset_strobe,
            strobe_in => crc_strobe,
            data_in => serial_in_copy,
            crc_out => crc_data);

    process (clock_in) is
    begin
        if clock_in'event and clock_in = '1' then
            if data_strobe = '1' then
                data_reg (num_data_bits - 2 downto 0) <= data_reg (num_data_bits - 1 downto 1);
                data_reg (num_data_bits - 1) <= serial_in_copy;
            end if;
            valid_crc <= '0';
            if crc_data = x"0000" then
                valid_crc <= '1';
            end if;
            counter_8_reached <= '0';
            counter_16_reached <= '0';
            if counter (2 downto 0) = "111" then
                counter_8_reached <= '1';
                counter_16_reached <= counter (3);
            end if;
            if baud_div_16 = '1' then
                serial_in_copy <= serial_in;
            end if;
        end if;
    end process;

    data_out <= data_reg;

    process (clock_in, baud_div_16) is
    begin
        if clock_in'event and clock_in = '1' then
            crc_reset_strobe <= reset_in;
            crc_strobe <= '0';
            data_strobe <= '0';
            strobe_out <= '0';

            if baud_div_16 = '1' then
                counter <= counter + 1;

                case receive_state is
                    when ZERO_SIGNAL =>
                        -- In this state the input signal is not stable so no data is captured
                        if serial_in_copy = '1' then
                            receive_state <= ONE_SIGNAL;
                        end if;
                        counter <= (others => '0');

                    when ONE_SIGNAL =>
                        -- The input must be stable in the '1' state for a while
                        -- in order to enter the READY state
                        if serial_in_copy = '1' then
                            if counter (num_counter_bits - 1 downto 4) = stable_time_in_bits then
                                receive_state <= READY;
                            end if;
                        else
                            receive_state <= ZERO_SIGNAL;
                        end if;

                    when READY =>
                        -- In the READY state we are ready to receive a start bit
                        if serial_in_copy = '0' then
                            receive_state <= START_BIT;
                        end if;
                        counter <= (others => '0');
                        crc_reset_strobe <= '1';

                    when START_BIT =>
                        -- In this state we expect the start bit to be stable
                        if counter_8_reached = '1' then
                            if serial_in_copy = '1' then
                                -- Unstable - returned to 1 in the middle of the bit
                                receive_state <= ZERO_SIGNAL;
                            else
                                receive_state <= DATA_BIT;
                                counter <= (others => '0');
                            end if;
                        end if;

                    when DATA_BIT =>
                        -- Capture data
                        if counter_16_reached = '1'
                          and counter (num_counter_bits - 1 downto 4) = (num_data_bits - 1) then
                            receive_state <= CRC_BIT;
                            counter <= (others => '0');
                        end if;
                        crc_strobe <= counter_16_reached;
                        data_strobe <= counter_16_reached;

                    when CRC_BIT =>
                        -- Capture CRC value
                        if counter_16_reached = '1'
                          and counter (num_counter_bits - 1 downto 4) = (num_crc_bits - 1) then
                            receive_state <= STOP_BIT;
                            counter <= (others => '0');
                        end if;
                        crc_strobe <= counter_16_reached;

                    when STOP_BIT =>
                        -- Accept the frame if the CRC is valid and the stop bit is 1
                        if counter_16_reached = '1' then
                            if serial_in_copy = '1' then
                                receive_state <= READY;
                                strobe_out <= valid_crc;
                            else
                                -- Unstable - stop bit should be 1
                                receive_state <= ZERO_SIGNAL;
                            end if;
                        end if;
                end case;
            end if;
            if reset_in = '1' then
                receive_state <= ZERO_SIGNAL;
            end if;
        end if;
    end process;

end architecture structural;
