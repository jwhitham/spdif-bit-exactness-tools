library ieee;
use ieee.std_logic_1164.all;
entity filter_unit_microcode_store is port (
        uc_data_out : out std_logic_vector (7 downto 0) := (others => '0');
        uc_addr_in  : in std_logic_vector (8 downto 0) := (others => '0');
        enable_in   : in std_logic := '0';
        clock_in    : in std_logic := '0');
end filter_unit_microcode_store;
architecture structural of filter_unit_microcode_store is
    signal one      : std_logic := '1';
    signal unused   : std_logic_vector(8 downto 0) := (others => '0');

    component SB_RAM512x8 is
        generic (
            INIT_0 : std_logic_vector(255 downto 0);
            INIT_1 : std_logic_vector(255 downto 0);
            INIT_2 : std_logic_vector(255 downto 0);
            INIT_3 : std_logic_vector(255 downto 0);
            INIT_4 : std_logic_vector(255 downto 0);
            INIT_5 : std_logic_vector(255 downto 0);
            INIT_6 : std_logic_vector(255 downto 0);
            INIT_7 : std_logic_vector(255 downto 0);
            INIT_8 : std_logic_vector(255 downto 0);
            INIT_9 : std_logic_vector(255 downto 0);
            INIT_A : std_logic_vector(255 downto 0);
            INIT_B : std_logic_vector(255 downto 0);
            INIT_C : std_logic_vector(255 downto 0);
            INIT_D : std_logic_vector(255 downto 0);
            INIT_E : std_logic_vector(255 downto 0);
            INIT_F : std_logic_vector(255 downto 0));
        port (
            RDATA       : out std_logic_vector (7 downto 0);
            RADDR       : in std_logic_vector (8 downto 0);
            WADDR       : in std_logic_vector (8 downto 0);
            WDATA       : in std_logic_vector (7 downto 0);
            RCLKE       : in std_logic;
            RCLK        : in std_logic;
            RE          : in std_logic;
            WCLKE       : in std_logic;
            WCLK        : in std_logic;
            WE          : in std_logic);
    end component SB_RAM512x8;
signal uc_data_0 : std_logic_vector(7 downto 0) := (others => '0');
begin
ram0 : SB_RAM512x8 generic map (
INIT_0 => X"2323202020202020202020222222222222222222222222222222C2876080C401",
INIT_1 => X"232323232323252525252525252525252525252524C289C36060802220202020",
INIT_2 => X"23272727272727272727272727272726C283C360608024202020202320232323",
INIT_3 => X"2929292929292929292928C284C3606080262323202320202023202320202020",
INIT_4 => X"0B0B0B0B0B0B0B0B0B0B4A832820202020202323202020202020232329292929",
INIT_5 => X"23232320202D2D2D2D2D2D2D2D2D2D2D2D2D2D2DC2866080C4C44C810B0B0B0B",
INIT_6 => X"500F83C4C44E810B0B0B0B0B0B0B0B0B0B0B0B0B0B2D23232023202020232323",
INIT_7 => X"22222222222222222222222222C2876080C48EC7C6C4C153118FC5C1521186C1",
INIT_8 => X"2525252525252524C289C3606080222023202320202320202020202020202222",
INIT_9 => X"272726C283C36060802420232320232320232323232323232325252525252525",
INIT_A => X"C360608026202020232023232023202320202023272727272727272727272727",
INIT_B => X"202023202320202320202020202323292929292929292929292929292928C284",
INIT_C => X"2D2D2D2D2D2D2DC2866080C4C44C810B0B0B0B0B0B0B0B0B0B0B0B0B0B4A8328",
INIT_D => X"0B0B0B0B0B0B0B0B2D2323202320202023232323232320202D2D2D2D2D2D2D2D",
INIT_E => X"11868E531486C7C6C4C153118FC5C1521186C1500F83C4C44E810B0B0B0B0B0B",
INIT_F => X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF185787568815C552")
port map (
RDATA => uc_data_0,
RADDR => uc_addr_in(8 downto 0),
RCLK => clock_in,
RCLKE => one,
RE => enable_in,
WADDR => unused(8 downto 0),
WDATA => unused(7 downto 0),
WCLK => clock_in,
WCLKE => unused(0),
WE => unused(0));
uc_data_out <= uc_data_0;
end structural;
