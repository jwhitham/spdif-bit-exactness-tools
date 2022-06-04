
library ieee;
use ieee.std_logic_1164.all;

entity output_encoder is
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

    signal fifo_data_in     : std_logic := '0';
    signal fifo_write       : std_logic := '0';
    signal fifo_read        : std_logic := '0';
    signal fifo_reset       : std_logic := '0';
    signal fifo_half_full   : std_logic := '0';
    signal fifo_data_out    : std_logic := '0';
    signal fifo_read_error  : std_logic := '0';
    signal fifo_write_error : std_logic := '0';

    component fifo is
        generic (test_addr_size : Natural := 12);
        port (
            data_in     : in std_logic;
            data_out    : out std_logic := '0';
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
    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then

            fifo_write <= '0';
            case encode_state is
                when READY =>
                    case pulse_length_in is
                        when THREE =>
                            encode_state <= HOLD_TWO;
                            fifo_data_in <= not fifo_data_in;
                            fifo_write <= '1';
                        when TWO =>
                            encode_state <= HOLD_ONE;
                            fifo_data_in <= not fifo_data_in;
                            fifo_write <= '1';
                        when ONE =>
                            fifo_data_in <= not fifo_data_in;
                            fifo_write <= '1';
                        when others =>
                            null;
                    end case;

                when HOLD_TWO =>
                    encode_state <= HOLD_ONE;
                    fifo_write <= '1';

                when HOLD_ONE =>
                    encode_state <= READY;
                    fifo_write <= '1';
            end case;

            if sync_in = '0' then
                -- held in reset
                encode_state <= READY;
                fifo_write <= '0';
                fifo_data_in <= '0';
            end if;
        end if;
    end process;

    fifo_reset <= '1' when output_state = RESET else '0';
    data_out <= fifo_data_out;
    fifo_read <= strobe_in when output_state = ACTIVE else '0';
    sync_out <= '1' when output_state = ACTIVE else '0';
    error_out <= fifo_read_error or fifo_write_error;

    f : fifo
        generic map (test_addr_size => 4)
        port map (
            data_in => fifo_data_in,
            data_out => fifo_data_out,
            empty_out => open,
            full_out => open,
            half_out => fifo_half_full,
            write_error => fifo_read_error,
            read_error => fifo_write_error,
            reset_in => fifo_reset,
            clock_in => clock_in,
            write_in => fifo_write,
            read_in => fifo_read);

    process (clock_in)
    begin
        if clock_in'event and clock_in = '1' then
            case output_state is
                when RESET =>
                    output_state <= FILLING;
                when FILLING =>
                    if fifo_half_full = '1' then
                        output_state <= ACTIVE;
                    end if;
                when ACTIVE =>
                    null;
            end case;

            if sync_in = '0' then
                -- Wait for clock_regenerator sync before allowing anything into the FIFO
                output_state <= RESET;
            end if;
        end if;
    end process;


end structural;
