
library ieee;
use ieee.std_logic_1164.all;

use std.textio.all;

entity output_encoder is
    generic (addr_size : Natural := 11);
    port (
        pulse_length_in : in std_logic_vector (1 downto 0);
        sync_in         : in std_logic;
        data_out        : out std_logic := '0';
        error_out       : out std_logic := '0';
        sync_out        : out std_logic := '0';
        strobe_in       : in std_logic;
        clock_in        : in std_logic
    );
end output_encoder;

architecture structural of output_encoder is

    subtype t_pulse_length is std_logic_vector (1 downto 0);
    constant ZERO           : t_pulse_length := "00";
    constant ONE            : t_pulse_length := "01";
    constant TWO            : t_pulse_length := "10";
    constant THREE          : t_pulse_length := "11";

    type t_encode_state is (READY, HOLD_ONE, HOLD_TWO);
    signal encode_state       : t_encode_state := READY;

    type t_output_state is (RESET, FILLING, ACTIVE);
    signal output_state       : t_output_state := RESET;

    signal pulse_length     : t_pulse_length := ZERO;
    signal fifo_write       : std_logic := '0';
    signal fifo_read        : std_logic := '0';
    signal fifo_reset       : std_logic := '0';
    signal fifo_half_full   : std_logic := '0';
    signal fifo_read_error  : std_logic := '0';
    signal fifo_write_error : std_logic := '0';
    signal data_gen         : std_logic := '0';

    component fifo is
        generic (addr_size : Natural; data_size_log_2 : Natural);
        port (
            data_in     : in std_logic_vector ((2 ** data_size_log_2) - 1 downto 0);
            data_out    : out std_logic_vector ((2 ** data_size_log_2) - 1 downto 0) := (others => '0');
            empty_out   : out std_logic := '1';
            full_out    : out std_logic := '0';
            half_out    : out std_logic := '0';
            write_error : out std_logic := '0';
            read_error  : out std_logic := '0';
            reset_in    : in std_logic;
            clock_in    : in std_logic;
            write_in    : in std_logic;
            read_in     : in std_logic);
    end component fifo;


begin
    f : fifo
        generic map (addr_size => addr_size, data_size_log_2 => 1)
        port map (
            data_in => pulse_length_in,
            data_out => pulse_length,
            empty_out => open,
            full_out => open,
            half_out => fifo_half_full,
            write_error => fifo_write_error,
            read_error => fifo_read_error,
            reset_in => fifo_reset,
            clock_in => clock_in,
            write_in => fifo_write,
            read_in => fifo_read);

    assert fifo_write_error = '0';
    assert fifo_read_error = '0';
    error_out <= fifo_write_error or fifo_read_error;
    sync_out <= '1' when output_state = ACTIVE else '0';
    fifo_reset <= '1' when output_state = RESET else '0';
    fifo_write <= '1' when (pulse_length_in /= "00") and (output_state /= RESET) else '0';

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            case output_state is
                when RESET =>
                    -- Initial state - fill to halfway
                    output_state <= FILLING;
                when FILLING | ACTIVE =>
                    -- When half-way point is reached, output encoder becomes active
                    if fifo_half_full = '1' then
                        output_state <= ACTIVE;
                    end if;
                    -- Any error forces a reset and refill
                    if fifo_read_error = '1' or fifo_write_error = '1' then
                        output_state <= RESET;
                    end if;
            end case;

            if sync_in = '0' then
                -- Wait for clock_regenerator sync before allowing anything into the FIFO
                output_state <= RESET;
            end if;
        end if;
    end process;

    fifo_read <= '1' when output_state = ACTIVE and strobe_in = '1' and encode_state = READY else '0';
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            if output_state = ACTIVE and strobe_in = '1' then
                case encode_state is
                    when READY =>
                        case pulse_length is
                            when THREE =>
                                encode_state <= HOLD_TWO;
                                data_gen <= not data_gen;
                            when TWO =>
                                encode_state <= HOLD_ONE;
                                data_gen <= not data_gen;
                            when ONE =>
                                data_gen <= not data_gen;
                            when others =>
                                null;
                        end case;

                    when HOLD_TWO =>
                        encode_state <= HOLD_ONE;

                    when HOLD_ONE =>
                        encode_state <= READY;
                end case;
            end if;
        end if;
    end process;

    data_out <= data_gen;



end structural;
