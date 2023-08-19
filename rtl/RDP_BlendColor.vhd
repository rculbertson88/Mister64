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
     
      blend_ena               : in  std_logic;
      combine_color           : in  tcolor3_u8;
      combine_alpha           : in  unsigned(7 downto 0);
      FB_color                : in  tcolor4_u8;
      blend_shift_a           : in unsigned(2 downto 0);
      blend_shift_b           : in unsigned(2 downto 0);
      
      blender_color           : out tcolor3_u8
   );
end entity;

architecture arch of RDP_BlendColor is

   signal mode_1_R            : unsigned(1 downto 0);
   signal mode_1_A            : unsigned(1 downto 0);
   signal mode_2_R            : unsigned(1 downto 0);
   signal mode_2_A            : unsigned(1 downto 0);
      
   signal color_1_R           : tcolor3_u8;
   signal color_2_R           : tcolor3_u8;
   signal color_1_A           : unsigned(7 downto 0);
   signal color_2_A           : unsigned(7 downto 0);
   
   signal color_1_A_reduced   : unsigned(4 downto 0);
   signal color_2_A_reduced   : unsigned(4 downto 0);
   
   signal blend               : std_logic;
         
   signal blend_mul1          : tcolor3_u13;
   signal blend_mul2          : tcolor3_u14;
   signal blend_add           : tcolor3_u14;

begin 

   -- todo: switch mode for cycle2
   mode_1_R <= settings_otherModes.blend_m1a0;
   mode_1_A <= settings_otherModes.blend_m1b0;
   mode_2_R <= settings_otherModes.blend_m2a0;
   mode_2_A <= settings_otherModes.blend_m2b0;
   
   -- todo: more mux selects
   process (all)
   begin

      -- todo: also disable for step 2
      blend <= blend_ena;
      if (mode_1_A = 0 and mode_2_A = 0 and combine_alpha = 255) then
         blend <= '0';
      end if;
      
      -- todo: for cycletype 1, blend is forced in cycle 1 with a special blending operation?

   
      for i in 0 to 2 loop
         
         color_1_R(i) <= (others => '0');
         case (to_integer(mode_1_R)) is
            when 0 => 
               -- todo: use blender color for step 2
               color_1_R <= combine_color;
            when 1 =>
               color_1_R(0) <= FB_color(0);
               color_1_R(1) <= FB_color(1);
               color_1_R(2) <= FB_color(2);
            when 2 => 
               color_1_R(0) <= settings_blendcolor.blend_R;
               color_1_R(1) <= settings_blendcolor.blend_G;
               color_1_R(2) <= settings_blendcolor.blend_B;
            --when 3 => fog
            when others => null;
         end case;
         
         color_2_R(i) <= (others => '0');
         case (to_integer(mode_2_R)) is
            when 0 => 
               -- todo: use blender color for step 2
               color_2_R <= combine_color;
            when 1 =>
               -- todo: use fb_1 color for step 2...but should be same as it's the same pixel?
               color_2_R(0) <= FB_color(0);
               color_2_R(1) <= FB_color(1);
               color_2_R(2) <= FB_color(2);
            when 2 => 
               color_2_R(0) <= settings_blendcolor.blend_R;
               color_2_R(1) <= settings_blendcolor.blend_G;
               color_2_R(2) <= settings_blendcolor.blend_B;
            --when 3 => fog
            when others => null;
         end case;
   
      end loop;
      
      color_1_A <= (others => '0');
      case (to_integer(mode_1_A)) is
         when 0 => 
            -- todo: use blender color for step 2
            color_1_A <= combine_alpha;
         when 1 =>
            color_1_A <= FB_color(3);
         when 2 => 
            -- todo: should add ditherAlpha and clamp against 0xFF
            color_1_A <= settings_blendcolor.blend_A;
         --when 3 => fog
         when others => null;
      end case;
      
      color_2_A <= (others => '0');
      case (to_integer(mode_2_A)) is
         when 0 => 
            color_2_A <= to_unsigned(16#FF#, 8) - color_1_A;
         when 1 =>
            -- todo: use fb_1 color for step 2...but should be same as it's the same pixel?
            color_2_A <= FB_color(3);
         when 2 => 
            color_2_A <= (others => '1');
         when 3 => 
            color_2_A <= (others => '0');
         when others => null;
      end case;

   end process;
   
   color_1_A_reduced <= shift_right(color_1_A(7 downto 5), to_integer(blend_shift_a)) & "00" when (mode_2_A = 1) else color_1_A(7 downto 3);
   color_2_A_reduced <= shift_right(color_2_A(7 downto 5), to_integer(blend_shift_b)) & "11" when (mode_2_A = 1) else color_2_A(7 downto 3);
   
   gcalc: for i in 0 to 2 generate
   begin
   
      blend_mul1(i)   <= color_1_R(i) * color_1_A_reduced;
      blend_mul2(i)   <= color_2_R(i) * (resize(color_2_A_reduced, 6) + 1);
      blend_add(i)    <= resize(blend_mul1(i), 14) + blend_mul2(i);
      
   end generate;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (trigger = '1') then 
         
            --if (blend_ena = '1') then
            if (blend = '1' and settings_otherModes.forceBlend = '1') then -- hack until special blend mode for AA is implemented
            
               for i in 0 to 2 loop
                  blender_color(i) <= blend_add(i)(12 downto 5);
               end loop;
            
            else
            
               blender_color <= color_1_R;
               
            end if;
         
         end if;
      
         
      end if;
   end process;
   

end architecture;





