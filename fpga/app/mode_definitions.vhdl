
library work;
use work.all;

library ieee;
use ieee.std_logic_1164.all;

package mode_definitions is
    subtype t_mode is std_logic_vector (3 downto 0);

    constant COMPRESS_MAX : t_mode := "0000";
    constant COMPRESS_2   : t_mode := "0001";
    constant COMPRESS_1   : t_mode := "0010";
    constant ATTENUATE_1  : t_mode := "0011";
    constant ATTENUATE_2  : t_mode := "0100";
    constant PASSTHROUGH  : t_mode := "0101";
    constant DBG_SPDIF    : t_mode := "0110";
    constant DBG_SUBCODES : t_mode := "0111";
    constant DBG_COMPRESS : t_mode := "1000";
    constant DBG_ADCS     : t_mode := "1001";
    constant DBG_VERSION  : t_mode := "1010";

    constant MIN_VALUE    : t_mode := "0000";
    constant MAX_VALUE    : t_mode := "1010";

end mode_definitions;

