library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;
use work.pFunctions.all;

entity RDP_BlendColor is
   port 
   (
      clk1x                   : in  std_logic;
      trigger                 : in  std_logic;

      settings_otherModes     : in  tsettings_otherModes;
      settings_blendcolor     : in  tsettings_blendcolor;
     
      combine_color           : in  tcolor3_u8;
      
      blender_color           : out tcolor3_u8
   );
end entity;

architecture arch of RDP_BlendColor is

   signal mode_1_R        : unsigned(1 downto 0);
   signal mode_1_A        : unsigned(1 downto 0);
   signal mode_2_R        : unsigned(1 downto 0);
   signal mode_2_A        : unsigned(1 downto 0);

   signal color_1_R       : tcolor3_u8;

begin 

   -- todo: switch mode for cycle2
   mode_1_R <= settings_otherModes.blend_m1a0;
   mode_1_A <= settings_otherModes.blend_m1b0;
   mode_2_R <= settings_otherModes.blend_m2a0;
   mode_2_A <= settings_otherModes.blend_m2b0;
   
   -- todo: more mux selects
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then 
      
            for i in 0 to 2 loop
               
               color_1_R(i) <= (others => '0');
               case (to_integer(mode_1_R)) is
                  when 0 => 
                     -- todo: use blender color for step 2
                     color_1_R <= combine_color;
                  --when 1 => memory
                  when 2 => 
                     color_1_R(0) <= settings_blendcolor.blend_R;
                     color_1_R(1) <= settings_blendcolor.blend_G;
                     color_1_R(2) <= settings_blendcolor.blend_B;
                  --when 3 => fog
                  when others => null;
               end case;
   
            end loop;
         
         end if;
         
      end if;
   end process;
   
   -- no blend hack
   blender_color <= color_1_R;

end architecture;





