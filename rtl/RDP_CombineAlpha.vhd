library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;
use work.pFunctions.all;

entity RDP_CombineAlpha is
   port 
   (
      clk1x                   : in  std_logic;
      trigger                 : in  std_logic;
   
      settings_otherModes     : in  tsettings_otherModes;
      settings_combineMode    : in  tsettings_combineMode;
     
      pipeInColor             : in  tcolor4_s16;
      tex_alpha               : in  unsigned(7 downto 0);
      lod_frac                : in  unsigned(7 downto 0);

      combine_alpha           : out unsigned(7 downto 0) := (others => '0')
   );
end entity;

architecture arch of RDP_CombineAlpha is

   signal mode_sub1        : unsigned(2 downto 0);
   signal mode_sub2        : unsigned(2 downto 0);
   signal mode_mul         : unsigned(2 downto 0);
   signal mode_add         : unsigned(2 downto 0);
            
   signal alpha_sub1       : signed(9 downto 0);
   signal alpha_sub2       : signed(9 downto 0);
   signal alpha_mul        : signed(9 downto 0);
   signal alpha_add        : signed(9 downto 0);
   
   signal combiner_sub     : signed(9 downto 0);
   signal combiner_mul     : signed(19 downto 0);
   signal combiner_add     : signed(19 downto 0);
   signal combiner_cut     : signed(11 downto 0);

begin 

   -- todo: switch mode for cycle2
   mode_sub1 <= settings_combineMode.combine_sub_a_A_1;
   mode_sub2 <= settings_combineMode.combine_sub_b_A_1;
   mode_mul  <= settings_combineMode.combine_mul_A_1;
   mode_add  <= settings_combineMode.combine_add_A_1;
   
   process (all)
   begin
      
      alpha_sub1 <= (others => '0');
      case (to_integer(mode_sub1)) is
         when 0 => alpha_sub1 <= "00" & signed(combine_alpha);
         when 1 => alpha_sub1 <= "00" & signed(tex_alpha);
         --when 2 => tex2
         --when 3 => prim
         when 4 => alpha_sub1 <= '0' & pipeInColor(3)(8 downto 0);
         --when 5 => env
         when 6 => alpha_sub1 <= 10x"100";
         when 7 => alpha_sub1 <= (others => '0');
         when others => null;
      end case;
      
      alpha_sub2 <= (others => '0');
      case (to_integer(mode_sub2)) is
         when 0 => alpha_sub2 <= "00" & signed(combine_alpha);
         when 1 => alpha_sub2 <= "00" & signed(tex_alpha);
         --when 2 => tex2
         --when 3 => prim
         when 4 => alpha_sub2 <= '0' & pipeInColor(3)(8 downto 0);
         --when 5 => env
         when 6 => alpha_sub2 <= 10x"100";
         when 7 => alpha_sub2 <= (others => '0');
         when others => null;
      end case;
      
      alpha_mul <= (others => '0');
      case (to_integer(mode_mul)) is
         when 0 => alpha_mul <= "00" & signed(lod_frac);
         when 1 => alpha_mul <= "00" & signed(tex_alpha);
         --when 2 => tex2
         --when 3 => prim
         when 4 => alpha_mul <= '0' & pipeInColor(3)(8 downto 0);
         --when 5 => env
         --when 6 => prim level Frac
         --when 7 => alpha_sub2 <= (others => '0');
         when others => null;
      end case;
      
      alpha_add <= (others => '0');
      case (to_integer(mode_add)) is
         when 0 => alpha_add <= "00" & signed(combine_alpha);
         when 1 => alpha_add <= "00" & signed(tex_alpha);
         --when 2 => tex2
         --when 3 => prim
         when 4 => alpha_add <= '0' & pipeInColor(3)(8 downto 0);
         --when 5 => env
         when 6 => alpha_add <= 10x"100";
         when 7 => alpha_add <= (others => '0');
         when others => null;
      end case;

   end process;
   
   combiner_sub <= alpha_sub1 - alpha_sub2;
   combiner_mul <= combiner_sub * alpha_mul; 
   combiner_add <= combiner_mul + (alpha_add & x"80");
   combiner_cut <= combiner_add(19 downto 8);

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         --todo: keep unclamped result for cycle 2
         
         if (trigger = '1') then
         
            if (combiner_cut(8 downto 7) = "11") then
               combine_alpha <= (others => '0');
            elsif (combiner_cut(8) = '1') then 
               combine_alpha <= (others => '1');
            else
               combine_alpha <= unsigned(combiner_cut(7 downto 0));
            end if;
            
         end if;
         
      end if;
   end process;
   
   
   -- todo : CVG handling

end architecture;





