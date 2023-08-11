library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_TexTile is
   port 
   (
      coordIn        : in  signed(15 downto 0);
      tile_max       : in  unsigned(11 downto 0);
      tile_min       : in  unsigned(11 downto 0);
      tile_clamp     : in  std_logic;
      tile_mirror    : in  std_logic;
      tile_mask      : in  unsigned(3 downto 0);
      tile_shift     : in  unsigned(3 downto 0);
      
      index_out      : out unsigned(9 downto 0);
      frac_out       : out unsigned(4 downto 0);
      diff_out       : out signed(1 downto 0)
   );
end entity;

architecture arch of RDP_TexTile is

   signal shifted       : signed(15 downto 0);
         
   signal relative      : signed(15 downto 0);

   signal clampMax      : unsigned(9 downto 0);
   signal clamp_index   : unsigned(9 downto 0);
      
   signal maskShift     : integer range 0 to 10;
   signal maskShifted   : unsigned(15 downto 0);
   signal mask          : unsigned(9 downto 0);
      
   signal wrap_index    : unsigned(10 downto 0);
   signal wrap          : std_logic;
   signal wrapped_index : unsigned(9 downto 0);

begin 

   shifted <= shift_right(coordIn, to_integer(tile_shift)) when (tile_shift < 11) else
              coordIn sll (16 - to_integer(tile_shift));
   
   relative <= shifted - to_integer(tile_min & "000");
   
   
   -- clamp
   clampMax <= tile_max(11 downto 2) - tile_min(11 downto 2);
      
   process (all)
   begin
   
      clamp_index <= unsigned(relative(14 downto 5));
      frac_out    <= unsigned(relative(4 downto 0));
   
      if (tile_clamp = '1' or tile_mask = 0) then
         if (to_integer(shifted(15 downto 3)) >= to_integer(tile_max)) then
            clamp_index <= clampMax;
            frac_out    <= (others => '0');
         elsif (shifted < 0) then
            clamp_index <= (others => '0');
            frac_out    <= (others => '0');
         end if;
      end if;
      
   end process;
   
   -- mask
   maskShift   <= 10 when (tile_mask > 10) else to_integer(tile_mask);
   maskShifted <= shift_right(to_unsigned(16#FFFF#, 16), 16 - maskShift);
   mask        <= maskShifted(9 downto 0);
   
   wrap_index    <= '0' & clamp_index;
   wrap          <= wrap_index(maskShift);
   
   wrapped_index <= not clamp_index when (wrap = '1') else clamp_index;

   process (all)
   begin
   
      index_out <= clamp_index;
      diff_out  <= to_signed(1, 2);
      
      if (tile_mask > 0) then
         if (tile_mirror = '1') then
            index_out <= wrapped_index and mask;
            if (wrap = '1' and (((wrapped_index and mask) - 1) = mask)) then diff_out <= (others => '0'); end if;
            if (wrap = '0' and ((wrapped_index and mask)       = mask)) then diff_out <= (others => '0'); end if;
            if (wrap = '1') then
               diff_out  <= to_signed(-1, 2);
            end if;            
         else
            index_out <= clamp_index and mask;
            if (clamp_index = mask) then
               diff_out  <= to_signed(-1, 2);
            end if;
         end if;
      end if;
      
   end process;
   
   
   
end architecture;





