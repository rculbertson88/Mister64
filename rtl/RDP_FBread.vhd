library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;
use work.pFunctions.all;

entity RDP_FBread is
   port 
   (
      clk1x                   : in  std_logic;
      trigger                 : in  std_logic;
   
      settings_otherModes     : in  tsettings_otherModes;
      settings_colorImage     : in  tsettings_colorImage;
      
      xIndex                  : in  unsigned(11 downto 0);
      yOdd                    : in  std_logic;
      
      FBAddr                  : out unsigned(10 downto 0);
      FBData                  : in  unsigned(31 downto 0);
     
      FBcolor                 : out  tcolor4_u8;
      cvgFB                   : out unsigned(2 downto 0)
   );
end entity;

architecture arch of RDP_FBread is

   signal muxselect : std_logic := '0';
   signal Fbdata16  : unsigned(15 downto 0);

begin 
   
   -- todo: must increase line size if games really use more than 2048 pixels in 16bit mode or 1024 pixels in 32 bit mode
   FBAddr <= yOdd & xIndex(10 downto 1) when (settings_colorImage.FB_size = SIZE_16BIT) else
             yOdd & xIndex(9 downto 0);
             
   Fbdata16 <= FBData(31 downto 16) when (muxselect = '1') else FBData(15 downto 0);

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         
         muxselect <= xIndex(0);
         
         case (settings_colorImage.FB_size) is
            when SIZE_16BIT =>
               FBcolor(0) <= Fbdata16(15 downto 11) & "000";
               FBcolor(1) <= Fbdata16(10 downto 6) & "000";
               FBcolor(2) <= Fbdata16(5 downto 1) & "000";
               FBcolor(3) <= x"E0"; -- todo: use data from old_cvg
               cvgFB      <= (others => '1');
               
            when SIZE_32BIT =>
               FBcolor(0) <= Fbdata(31 downto 24);
               FBcolor(1) <= Fbdata(23 downto 16);
               FBcolor(2) <= Fbdata(15 downto 8);
               FBcolor(3) <= x"E0"; -- todo: unclear
            
            when others => null;
         end case;
         
      end if;
   end process;
      
      


end architecture;





