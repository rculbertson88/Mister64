library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_TexTile is
   port 
   (
      clk1x          : in  std_logic;
      trigger        : in  std_logic;
   
      coordIn        : in  signed(15 downto 0);
      tile_max       : in  unsigned(11 downto 0);
      tile_min       : in  unsigned(11 downto 0);
      tile_clamp     : in  std_logic;
      tile_mirror    : in  std_logic;
      tile_mask      : in  unsigned(3 downto 0);
      tile_shift     : in  unsigned(3 downto 0);
      
      index_out      : out unsigned(9 downto 0) := (others => '0');
      index_out1     : out unsigned(9 downto 0) := (others => '0');
      index_out2     : out unsigned(9 downto 0) := (others => '0');
      index_out3     : out unsigned(9 downto 0) := (others => '0');
      index_outN     : out unsigned(9 downto 0) := (others => '0');
      frac_out       : out unsigned(4 downto 0) := (others => '0')
   );
end entity;

architecture arch of RDP_TexTile is

   signal shifted          : signed(15 downto 0);
            
   signal relative         : signed(15 downto 0);
   
   signal clampMax         : unsigned(9 downto 0);
   signal clamp_index      : unsigned(9 downto 0);
   signal clamp_index1     : unsigned(9 downto 0);
   signal clamp_index2     : unsigned(9 downto 0);
   signal clamp_index3     : unsigned(9 downto 0);
   signal frac             : unsigned(4 downto 0);
         
   signal maskShift        : integer range 0 to 10;
   signal maskShifted      : unsigned(15 downto 0);
   signal mask             : unsigned(9 downto 0);
         
   signal wrap_index       : unsigned(10 downto 0);
   signal wrap_index1      : unsigned(10 downto 0);
   signal wrap_index2      : unsigned(10 downto 0);
   signal wrap_index3      : unsigned(10 downto 0);
   signal wrap             : std_logic;
   signal wrap1            : std_logic;
   signal wrap2            : std_logic;
   signal wrap3            : std_logic;
   signal wrapped_index    : unsigned(9 downto 0);
   signal wrapped_index1   : unsigned(9 downto 0);
   signal wrapped_index2   : unsigned(9 downto 0);
   signal wrapped_index3   : unsigned(9 downto 0);

begin 

   shifted <= shift_right(coordIn, to_integer(tile_shift)) when (tile_shift < 11) else
              coordIn sll (16 - to_integer(tile_shift));
   
   relative <= shifted - to_integer(tile_min & "000");
   
   
   -- clamp
   clampMax <= tile_max(11 downto 2) - tile_min(11 downto 2);
      
   process (all)
   begin
   
      clamp_index <= unsigned(relative(14 downto 5));
      frac        <= unsigned(relative(4 downto 0));
   
      if (tile_clamp = '1' or tile_mask = 0) then
         if (to_integer(shifted(15 downto 3)) >= to_integer(tile_max)) then
            clamp_index <= clampMax;
            frac        <= (others => '0');
         elsif (relative < 0) then
            clamp_index <= (others => '0');
            frac        <= (others => '0');
         end if;
      end if;
      
   end process;
   
   clamp_index1 <= clamp_index + 1;
   clamp_index2 <= clamp_index + 2;
   clamp_index3 <= clamp_index + 3;
   
   -- mask
   maskShift   <= 10 when (tile_mask > 10) else to_integer(tile_mask);
   maskShifted <= shift_right(to_unsigned(16#FFFF#, 16), 16 - maskShift);
   mask        <= maskShifted(9 downto 0);
   
   wrap_index    <= '0' & clamp_index;
   wrap_index1   <= '0' & clamp_index1;
   wrap_index2   <= '0' & clamp_index2;
   wrap_index3   <= '0' & clamp_index3;
   
   wrap          <= wrap_index(maskShift);
   wrap1         <= wrap_index1(maskShift);
   wrap2         <= wrap_index2(maskShift);
   wrap3         <= wrap_index3(maskShift);
   
   wrapped_index  <= not clamp_index  when (wrap  = '1') else clamp_index;
   wrapped_index1 <= not clamp_index1 when (wrap1 = '1') else clamp_index1;
   wrapped_index2 <= not clamp_index2 when (wrap2 = '1') else clamp_index2;
   wrapped_index3 <= not clamp_index3 when (wrap3 = '1') else clamp_index3;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then
   
            frac_out   <= frac;
      
            index_out  <= clamp_index;
            index_out1 <= clamp_index1;
            index_out2 <= clamp_index2;
            index_out3 <= clamp_index3;
            
            index_outN <= clamp_index + 1;
            
            if (tile_mask > 0) then
               if (tile_mirror = '1') then
                  index_out  <= wrapped_index  and mask;
                  index_out1 <= wrapped_index1 and mask;
                  index_out2 <= wrapped_index2 and mask;
                  index_out3 <= wrapped_index3 and mask;
                  
                  index_outN <= (wrapped_index + 1) and mask;
                  if (wrap = '1') then
                     index_outN <= (wrapped_index - 1) and mask;
                  end if; 
                  if (wrap = '1' and ((((wrapped_index and mask) - 1) and mask) = mask)) then index_outN <= wrapped_index and mask; end if;
                  if (wrap = '0' and ((wrapped_index and mask)       = mask))            then index_outN <= wrapped_index and mask; end if;           
               else
                  index_out  <= clamp_index  and mask;
                  index_out1 <= clamp_index1 and mask;
                  index_out2 <= clamp_index2 and mask;
                  index_out3 <= clamp_index3 and mask;
                  
                  index_outN <= (clamp_index + 1) and mask;
                  if (clamp_index = mask) then
                     index_outN  <= (others => '0');
                  end if;
               end if;
            end if;
         
         end if;
      
      end if;
   end process;
   
   
   
end architecture;





