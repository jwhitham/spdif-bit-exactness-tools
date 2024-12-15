
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library comfilter;
use comfilter.all;
use filter_unit_settings.all;
use debug_textio.all;

entity filter_unit is
    generic (print_outputs : Boolean := VERBOSE_DEBUG);
    port (
        clock_in            : in std_logic := '0';
        reset_in            : in std_logic := '0';
        restart_debug_out   : out std_logic := '0';
        input_ready_out     : out std_logic := '0';
        input_strobe_in     : in std_logic := '0';
        input_data_in       : in std_logic_vector
            (FRACTIONAL_BITS + NON_FRACTIONAL_BITS - 1 downto 0) := (others => '0');
        serial_ready_out    : out std_logic := '0';
        serial_data_out     : out std_logic := '0');
end filter_unit;

architecture structural of filter_unit is

    signal zero                 : std_logic := '0';

    signal ADD_A_TO_R           : std_logic := '0';
    signal LOAD_I0_FROM_INPUT   : std_logic := '0';
    signal REPEAT_FOR_ALL_BITS  : std_logic := '0';
    signal RESTART              : std_logic := '0';
    signal SEND_Y_TO_OUTPUT     : std_logic := '0';
    signal SET_X_IN_TO_ABS_O1_REG_OUT : std_logic := '0';
    signal SET_X_IN_TO_REG_OUT  : std_logic := '0';
    signal SET_X_IN_TO_X_AND_CLEAR_Y_BORROW : std_logic := '0';
    signal SHIFT_A_RIGHT        : std_logic := '0';
    signal SHIFT_I0_RIGHT       : std_logic := '0';
    signal SHIFT_I1_RIGHT       : std_logic := '0';
    signal SHIFT_I2_RIGHT       : std_logic := '0';
    signal SHIFT_L_RIGHT        : std_logic := '0';
    signal SHIFT_O1_RIGHT       : std_logic := '0';
    signal SHIFT_O2_RIGHT       : std_logic := '0';
    signal SHIFT_R_RIGHT        : std_logic := '0';
    signal SHIFT_X_RIGHT        : std_logic := '0';
    signal SHIFT_Y_RIGHT        : std_logic := '0';

    constant ASSERT_X_IS_ABS_O1 : std_logic_vector(3 downto 0) := x"1";
    constant ASSERT_A_HIGH_ZERO : std_logic_vector(3 downto 0) := x"2";
    constant ASSERT_A_LOW_ZERO  : std_logic_vector(3 downto 0) := x"3";
    constant ASSERT_R_ZERO      : std_logic_vector(3 downto 0) := x"4";
    constant ASSERT_Y_IS_X_MINUS_L : std_logic_vector(3 downto 0) := x"5";
    constant SEND_O1_TO_OUTPUT  : std_logic_vector(3 downto 0) := x"6";
    constant SEND_L_TO_OUTPUT   : std_logic_vector(3 downto 0) := x"7";

    signal mux_select           : std_logic_vector(3 downto 0) := (others => '0');
    signal mux_strobe           : std_logic := '0';
    signal debug_strobe         : std_logic := '0';
    signal uc_code              : std_logic_vector(7 downto 0) := (others => '0');
    signal uc_valid             : std_logic := '0';

    signal bank_select          : std_logic := '0';
    signal o1_is_negative       : std_logic := '0';
    signal y_is_negative        : std_logic := '0';
    signal reg_out              : std_logic := '0';
    signal r_out                : std_logic := '0';
    signal y_out                : std_logic := '0';
    signal o1_out               : std_logic := '0';
    signal o2_out               : std_logic := '0';
    signal x_out                : std_logic := '0';
    signal l_out                : std_logic := '0';
    signal i0_out               : std_logic := '0';
    signal i1_out               : std_logic := '0';
    signal i2_out               : std_logic := '0';

    signal l_debug_value        : std_logic_vector(ALL_BITS - 1 downto 0) := (others => '0');
    signal y_debug_value        : std_logic_vector(ALL_BITS - 1 downto 0) := (others => '0');
    signal x_debug_value        : std_logic_vector(ALL_BITS - 1 downto 0) := (others => '0');
    signal o1_debug_value       : std_logic_vector(ALL_BITS - 1 downto 0) := (others => '0');
begin
    zero <= '0';

    -- Control store and decoder
    cl_decoder : entity filter_unit_control_line_decoder
        port map (
                ADD_A_TO_R => ADD_A_TO_R,
                LOAD_I0_FROM_INPUT => LOAD_I0_FROM_INPUT,
                REPEAT_FOR_ALL_BITS => REPEAT_FOR_ALL_BITS,
                RESTART => RESTART,
                SEND_Y_TO_OUTPUT => SEND_Y_TO_OUTPUT,
                SET_X_IN_TO_ABS_O1_REG_OUT => SET_X_IN_TO_ABS_O1_REG_OUT,
                SET_X_IN_TO_REG_OUT => SET_X_IN_TO_REG_OUT,
                SET_X_IN_TO_X_AND_CLEAR_Y_BORROW => SET_X_IN_TO_X_AND_CLEAR_Y_BORROW,
                SHIFT_A_RIGHT => SHIFT_A_RIGHT,
                SHIFT_I0_RIGHT => SHIFT_I0_RIGHT,
                SHIFT_I1_RIGHT => SHIFT_I1_RIGHT,
                SHIFT_I2_RIGHT => SHIFT_I2_RIGHT,
                SHIFT_L_RIGHT => SHIFT_L_RIGHT,
                SHIFT_O1_RIGHT => SHIFT_O1_RIGHT,
                SHIFT_O2_RIGHT => SHIFT_O2_RIGHT,
                SHIFT_R_RIGHT => SHIFT_R_RIGHT,
                SHIFT_X_RIGHT => SHIFT_X_RIGHT,
                SHIFT_Y_RIGHT => SHIFT_Y_RIGHT,
                mux_select => mux_select,
                mux_strobe => mux_strobe,
                debug_strobe => debug_strobe,
                enable_in => uc_valid,
                code_in => uc_code);
  
    -- Microcode unit
    uc : block
        signal uc_addr      : unsigned(UC_ADDR_BITS - 1 downto 0) := (others => '1');
        signal uc_addr_next : unsigned(UC_ADDR_BITS - 1 downto 0) := (others => '0');
        signal bit_counter  : Natural range 0 to ALL_BITS - 1 := 0;
        signal more_bits    : std_logic := '0';
        signal uc_enable    : std_logic := '0';
    begin
        store : entity filter_unit_microcode_store 
            port map (
                    uc_data_out => uc_code,
                    uc_addr_in => std_logic_vector(uc_addr),
                    enable_in => uc_enable,
                    clock_in => clock_in);

        more_bits <= '1' when bit_counter /= 0 else '0';
        uc_enable <= '1' when RESTART = '1'
            else '1' when reset_in = '1'
            else '0' when (LOAD_I0_FROM_INPUT and not input_strobe_in) = '1'
            else '0' when (REPEAT_FOR_ALL_BITS = '1' and more_bits = '1')
            else '1';
        uc_addr_next <= uc_addr + 1;

        process (clock_in) is
            variable l : line;
        begin
            if clock_in = '1' and clock_in'event then
                if VERBOSE_DEBUG then
                    write (l, String'("uc_code = "));
                    write (l, Integer'(ieee.numeric_std.to_integer(unsigned(uc_code))));
                    writeline (output, l);
                end if;
                bit_counter <= ALL_BITS - 1;
                uc_valid <= '1';
                if reset_in = '1' or RESTART = '1' then
                    uc_addr <= (others => '0');
                    uc_valid <= '0'; -- Next uc_code won't be valid due to control flow
                    if VERBOSE_DEBUG then
                        write (l, String'("uc_addr -- reset"));
                        writeline (output, l);
                    end if;
                elsif uc_enable = '1' then
                    uc_addr <= uc_addr_next;
                    if VERBOSE_DEBUG then
                        write (l, String'("uc_addr := "));
                        write (l, Integer'(ieee.numeric_std.to_integer(uc_addr_next)));
                        writeline (output, l);
                    end if;
                end if;
                if REPEAT_FOR_ALL_BITS = '1' and more_bits = '1' then
                    bit_counter <= bit_counter - 1;
                end if;
                if uc_valid = '0' then
                    if VERBOSE_DEBUG then
                        write (l, String'("not executed"));
                        writeline (output, l);
                    end if;
                else
                    if uc_code = x"ff" then
                        write (l, String'("illegal instruction"));
                        writeline (output, l);
                        assert False;
                    end if;
                end if;
            end if;
        end process;
    end block uc;

    -- X register (special input via negation unit or passthrough)
    x_register : block
        type x_select_enum is (PASSTHROUGH_REG_OUT, PASSTHROUGH_X, NEGATE_REG_OUT);
        signal x_select                     : x_select_enum := PASSTHROUGH_REG_OUT;
        signal x_in_negate_reg_out, x_mux   : std_logic := '0';
        signal negated                      : std_logic := '0';
    begin
        x_subtractor : entity subtractor
            port map (
                    x_in => zero,
                    y_in => reg_out,
                    reset_in => SET_X_IN_TO_ABS_O1_REG_OUT,
                    strobe_in => SHIFT_X_RIGHT,
                    d_out => negated,
                    clock_in => clock_in);

        x_mux <= reg_out when x_select = PASSTHROUGH_REG_OUT
            else x_out when x_select = PASSTHROUGH_X
            else negated;

        sr : entity shift_register
            generic map (
                    name => "X",
                    size => ALL_BITS,
                    verbose_debug => VERBOSE_DEBUG)
            port map (
                    reg_out => x_out,
                    shift_right_in => SHIFT_X_RIGHT,
                    reg_in => x_mux,
                    debug_out => x_debug_value,
                    negative_out => open,
                    clock_in => clock_in);

        process (clock_in) is
        begin
            if clock_in = '1' and clock_in'event then
                if SET_X_IN_TO_REG_OUT = '1' then
                    x_select <= PASSTHROUGH_REG_OUT;
                elsif SET_X_IN_TO_ABS_O1_REG_OUT = '1' then
                    if o1_is_negative = '1' then
                        x_select <= NEGATE_REG_OUT;
                    else
                        x_select <= PASSTHROUGH_REG_OUT;
                    end if;
                elsif SET_X_IN_TO_X_AND_CLEAR_Y_BORROW = '1' then
                    x_select <= PASSTHROUGH_X;
                end if;
            end if;
        end process;
    end block x_register;

    -- Y register (special input via subtractor)
    y_register : block
        signal y_in : std_logic := '0';
    begin
        y_subtractor : entity subtractor
            port map (
                    x_in => x_out,
                    y_in => reg_out,
                    reset_in => SET_X_IN_TO_X_AND_CLEAR_Y_BORROW,
                    strobe_in => SHIFT_Y_RIGHT,
                    d_out => y_in,
                    clock_in => clock_in);
        sr : entity shift_register
            generic map (
                    name => "Y",
                    size => ALL_BITS,
                    verbose_debug => VERBOSE_DEBUG)
            port map (
                    reg_out => y_out,
                    shift_right_in => SHIFT_Y_RIGHT,
                    reg_in => y_in,
                    debug_out => y_debug_value,
                    negative_out => y_is_negative,
                    clock_in => clock_in);
    end block y_register;

    -- I0 register (parallel input)
    i0_register : block
        signal i0_value : std_logic_vector(ALL_BITS - 1 downto 0) := (others => '0');
    begin
        process (clock_in) is
            variable l : line;
            variable new_i0_value : std_logic_vector(ALL_BITS - 1 downto 0) := (others => '0');
            variable print_i0 : Boolean := false;
        begin
            if clock_in = '1' and clock_in'event then
                print_i0 := false;
                if LOAD_I0_FROM_INPUT = '1' then
                    new_i0_value := input_data_in;
                    i0_value <= new_i0_value;
                    print_i0 := VERBOSE_DEBUG;
                elsif SHIFT_I0_RIGHT = '1' then
                    new_i0_value(ALL_BITS - 1) := reg_out;
                    new_i0_value(ALL_BITS - 2 downto 0) := i0_value(ALL_BITS - 1 downto 1);
                    i0_value <= new_i0_value;
                    print_i0 := VERBOSE_DEBUG;
                end if;
                if print_i0 then
                    write (l, String'("I0 := "));
                    write (l, Integer'(ieee.numeric_std.to_integer(signed(new_i0_value))));
                    writeline (output, l);
                end if;
            end if;
        end process;
        i0_out <= i0_value(0);
    end block i0_register;

    -- Other registers
    i1_register : entity shift_register
        generic map (
                name => "I1",
                size => ALL_BITS,
                verbose_debug => VERBOSE_DEBUG)
        port map (
                reg_out => i1_out,
                shift_right_in => SHIFT_I1_RIGHT,
                reg_in => reg_out,
                negative_out => open,
                clock_in => clock_in);
    i2_register : entity shift_register
        generic map (
                name => "I2",
                size => ALL_BITS,
                verbose_debug => VERBOSE_DEBUG)
        port map (
                reg_out => i2_out,
                shift_right_in => SHIFT_I2_RIGHT,
                reg_in => reg_out,
                negative_out => open,
                clock_in => clock_in);
    o1_register : entity banked_shift_register
        generic map (
                name => "O1",
                size => ALL_BITS,
                verbose_debug => VERBOSE_DEBUG)
        port map (
                reg_out => o1_out,
                shift_right_in => SHIFT_O1_RIGHT,
                reg_in => reg_out,
                bank_select_in => bank_select,
                debug_out => o1_debug_value,
                negative_out => o1_is_negative,
                clock_in => clock_in);
    o2_register : entity banked_shift_register
        generic map (
                name => "O2",
                size => ALL_BITS,
                verbose_debug => VERBOSE_DEBUG)
        port map (
                reg_out => o2_out,
                shift_right_in => SHIFT_O2_RIGHT,
                reg_in => reg_out,
                bank_select_in => bank_select,
                negative_out => open,
                clock_in => clock_in);
    l_register : entity banked_shift_register
        generic map (
                name => "L",
                size => ALL_BITS,
                verbose_debug => VERBOSE_DEBUG)
        port map (
                reg_out => l_out,
                shift_right_in => SHIFT_L_RIGHT,
                reg_in => reg_out,
                bank_select_in => bank_select,
                debug_out => l_debug_value,
                negative_out => open,
                clock_in => clock_in);

    -- Adder and A, R registers
    ar_registers : block
        signal a_value : signed(A_BITS - 1 downto 0) := (others => '0');
        signal r_value : signed(A_BITS - 1 downto 0) := (others => '0');
    begin
        process (clock_in) is
            variable l : line;
            variable new_a_value : signed(A_BITS - 1 downto 0) := (others => '0');
            variable new_r_value : signed(A_BITS - 1 downto 0) := (others => '0');
            variable print_r     : Boolean := false;
        begin
            if clock_in = '1' and clock_in'event then
                print_r := false;
                if SHIFT_A_RIGHT = '1' then
                    new_a_value(A_BITS - 1) := reg_out;
                    new_a_value(A_BITS - 2 downto 0) := a_value(A_BITS - 1 downto 1);
                    a_value <= new_a_value;
                    if VERBOSE_DEBUG then
                        write (l, String'("A := "));
                        write (l, Integer'(ieee.numeric_std.to_integer(new_a_value)));
                        writeline (output, l);
                    end if;
                end if;
                if ADD_A_TO_R = '1' then
                    new_r_value := r_value + a_value;
                    r_value <= new_r_value;
                    print_r := VERBOSE_DEBUG;
                elsif SHIFT_R_RIGHT = '1' then
                    new_r_value(A_BITS - 1) := '0';
                    new_r_value(A_BITS - 2 downto 0) := r_value(A_BITS - 1 downto 1);
                    r_value <= new_r_value;
                    print_r := VERBOSE_DEBUG;
                end if;
                if print_r then
                    write (l, String'("R := "));
                    write (l, Integer'(ieee.numeric_std.to_integer(new_r_value)));
                    writeline (output, l);
                end if;
                if debug_strobe = '1' then
                    case mux_select is
                        when ASSERT_A_HIGH_ZERO =>
                            assert ieee.numeric_std.to_integer(signed(a_value(A_BITS - 1 downto ALL_BITS))) = 0;
                        when ASSERT_A_LOW_ZERO =>
                            assert ieee.numeric_std.to_integer(signed(a_value(ALL_BITS - 1 downto 0))) = 0;
                        when ASSERT_R_ZERO =>
                            assert ieee.numeric_std.to_integer(signed(r_value)) = 0;
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end process;
        r_out <= r_value(0);
    end block ar_registers;

    -- Register multiplexer
    mux : block
        signal reg_mux      : std_logic_vector(15 downto 0) := (others => '0');
        signal mux_register : Natural range 0 to 15 := 0;
    begin
        reg_mux(0) <= '0'; -- ZERO = 0
        reg_mux(1) <= r_out; -- R = 1
        reg_mux(2) <= y_out; -- Y = 2
        reg_mux(3) <= o1_out; -- O1 = 3
        reg_mux(4) <= o2_out; -- O2 = 4
        reg_mux(5) <= x_out; -- X = 5
        reg_mux(6) <= l_out; -- L = 6
        reg_mux(7) <= i0_out; -- I0 = 7
        reg_mux(8) <= i1_out; -- I1 = 8
        reg_mux(9) <= i2_out; -- I2 = 9
        reg_mux(15 downto 10) <= (others => '1'); -- ONE = 10
        reg_out <= reg_mux(mux_register);

        process (clock_in) is
            variable l : line;
        begin
            if clock_in = '1' and clock_in'event then
                if mux_strobe = '1' then
                    mux_register <= ieee.numeric_std.to_integer(unsigned(mux_select));
                    case ieee.numeric_std.to_integer(unsigned(mux_select)) is
                        when 14 =>
                            -- bank switch
                            bank_select <= not bank_select;
                        when 15 =>
                            -- L or X
                            if y_is_negative = '1' then
                                mux_register <= 6; -- L when negative
                            else
                                mux_register <= 5; -- X when not negative
                            end if;
                        when others =>
                            null;
                    end case;
                    if VERBOSE_DEBUG then
                        write (l, String'("mux select = "));
                        write (l, ieee.numeric_std.to_integer(unsigned(mux_select)));
                        writeline (output, l);
                    end if;
                end if;
            end if;
        end process;
    end block mux;

    debug : block
    begin
        process (clock_in) is
            variable l : line;
            variable x_minus_l : signed(ALL_BITS - 1 downto 0) := (others => '0');
        begin
            if clock_in = '1' and clock_in'event then
                if debug_strobe = '1' and (VERBOSE_DEBUG or print_outputs) then
                    case mux_select is
                        when ASSERT_X_IS_ABS_O1 =>
                            assert ieee.numeric_std.to_integer(signed(x_debug_value)) =
                                abs(ieee.numeric_std.to_integer(signed(o1_debug_value)));
                        when ASSERT_Y_IS_X_MINUS_L =>
                            x_minus_l := signed(x_debug_value) - signed(l_debug_value);
                            assert signed(y_debug_value) = x_minus_l;
                        when SEND_O1_TO_OUTPUT =>
                            write (l, String'("Debug out O1 = "));
                            write (l, Integer'(ieee.numeric_std.to_integer(signed(o1_debug_value))));
                            writeline (output, l);
                        when SEND_L_TO_OUTPUT =>
                            write (l, String'("Debug out L = "));
                            write (l, Integer'(ieee.numeric_std.to_integer(signed(l_debug_value))));
                            writeline (output, l);
                        when others =>
                            null;
                    end case;
                end if;
                if SEND_Y_TO_OUTPUT = '1' and (VERBOSE_DEBUG or print_outputs) then
                    write (l, String'("Debug out Y = "));
                    write (l, Integer'(ieee.numeric_std.to_integer(signed(y_debug_value))));
                    writeline (output, l);
                end if;
            end if;
        end process;
    end block debug;


    -- Output
    serial_data_out <= y_is_negative;
    serial_ready_out <= SEND_Y_TO_OUTPUT;
    input_ready_out <= LOAD_I0_FROM_INPUT;
    restart_debug_out <= RESTART;
end structural;

