
library ieee;
use ieee.std_logic_1164.all;

entity filter_unit_control_line_decoder is port (
ADD_A_TO_R : out std_logic := '0';
LOAD_I0_FROM_INPUT : out std_logic := '0';
REPEAT_FOR_ALL_BITS : out std_logic := '0';
RESTART : out std_logic := '0';
SEND_Y_TO_OUTPUT : out std_logic := '0';
SET_X_IN_TO_ABS_O1_REG_OUT : out std_logic := '0';
SET_X_IN_TO_REG_OUT : out std_logic := '0';
SET_X_IN_TO_X_AND_CLEAR_Y_BORROW : out std_logic := '0';
SHIFT_A_RIGHT : out std_logic := '0';
SHIFT_I0_RIGHT : out std_logic := '0';
SHIFT_I1_RIGHT : out std_logic := '0';
SHIFT_I2_RIGHT : out std_logic := '0';
SHIFT_L_RIGHT : out std_logic := '0';
SHIFT_O1_RIGHT : out std_logic := '0';
SHIFT_O2_RIGHT : out std_logic := '0';
SHIFT_R_RIGHT : out std_logic := '0';
SHIFT_X_RIGHT : out std_logic := '0';
SHIFT_Y_RIGHT : out std_logic := '0';

mux_select          : out std_logic_vector(3 downto 0);
mux_strobe          : out std_logic;
debug_strobe        : out std_logic;
enable_in           : in std_logic;
code_in             : in std_logic_vector(7 downto 0));
end filter_unit_control_line_decoder;
architecture structural of filter_unit_control_line_decoder is
    signal control_line_enable : std_logic;
begin
    control_line_enable <= enable_in and not code_in(7);
    mux_strobe <= enable_in and code_in(7) and not code_in(6);
    debug_strobe <= enable_in and code_in(7) and code_in(6);
    mux_select <= code_in(3 downto 0);
    REPEAT_FOR_ALL_BITS <= code_in(6) and control_line_enable;
    SHIFT_A_RIGHT <= code_in(5) and control_line_enable;

process (code_in, control_line_enable) is begin
ADD_A_TO_R <= '0';
LOAD_I0_FROM_INPUT <= '0';
RESTART <= '0';
SEND_Y_TO_OUTPUT <= '0';
SET_X_IN_TO_ABS_O1_REG_OUT <= '0';
SET_X_IN_TO_REG_OUT <= '0';
SET_X_IN_TO_X_AND_CLEAR_Y_BORROW <= '0';
SHIFT_I0_RIGHT <= '0';
SHIFT_I1_RIGHT <= '0';
SHIFT_I2_RIGHT <= '0';
SHIFT_L_RIGHT <= '0';
SHIFT_O1_RIGHT <= '0';
SHIFT_O2_RIGHT <= '0';
SHIFT_R_RIGHT <= '0';
SHIFT_X_RIGHT <= '0';
SHIFT_Y_RIGHT <= '0';
case code_in (4 downto 0) is
when "00000" =>
  null;
when "00001" =>
  LOAD_I0_FROM_INPUT <= control_line_enable;
when "00010" =>
  SHIFT_I0_RIGHT <= control_line_enable;
when "00011" =>
  ADD_A_TO_R <= control_line_enable;
when "00100" =>
  SHIFT_I2_RIGHT <= control_line_enable;
when "00101" =>
  ADD_A_TO_R <= control_line_enable;
  SHIFT_I2_RIGHT <= control_line_enable;
when "00110" =>
  SHIFT_O1_RIGHT <= control_line_enable;
when "00111" =>
  ADD_A_TO_R <= control_line_enable;
  SHIFT_O1_RIGHT <= control_line_enable;
when "01000" =>
  SHIFT_O2_RIGHT <= control_line_enable;
when "01001" =>
  ADD_A_TO_R <= control_line_enable;
  SHIFT_O2_RIGHT <= control_line_enable;
when "01010" =>
  SHIFT_O1_RIGHT <= control_line_enable;
  SHIFT_O2_RIGHT <= control_line_enable;
when "01011" =>
  SHIFT_R_RIGHT <= control_line_enable;
when "01100" =>
  SHIFT_O1_RIGHT <= control_line_enable;
  SHIFT_R_RIGHT <= control_line_enable;
when "01101" =>
  SHIFT_L_RIGHT <= control_line_enable;
when "01110" =>
  SHIFT_L_RIGHT <= control_line_enable;
  SHIFT_R_RIGHT <= control_line_enable;
when "01111" =>
  SET_X_IN_TO_ABS_O1_REG_OUT <= control_line_enable;
when "10000" =>
  SHIFT_O1_RIGHT <= control_line_enable;
  SHIFT_X_RIGHT <= control_line_enable;
when "10001" =>
  SET_X_IN_TO_X_AND_CLEAR_Y_BORROW <= control_line_enable;
when "10010" =>
  SHIFT_L_RIGHT <= control_line_enable;
  SHIFT_X_RIGHT <= control_line_enable;
  SHIFT_Y_RIGHT <= control_line_enable;
when "10011" =>
  SHIFT_L_RIGHT <= control_line_enable;
  SHIFT_X_RIGHT <= control_line_enable;
when "10100" =>
  SET_X_IN_TO_REG_OUT <= control_line_enable;
when "10101" =>
  SEND_Y_TO_OUTPUT <= control_line_enable;
when "10110" =>
  SHIFT_I1_RIGHT <= control_line_enable;
  SHIFT_I2_RIGHT <= control_line_enable;
when "10111" =>
  SHIFT_I0_RIGHT <= control_line_enable;
  SHIFT_I1_RIGHT <= control_line_enable;
when "11000" =>
  RESTART <= control_line_enable;
when others => RESTART <= control_line_enable;
end case;
end process;
end structural;
