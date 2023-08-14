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
      
      error_combineAlpha      : out std_logic;
   
      settings_otherModes     : in  tsettings_otherModes;
      settings_combineMode    : in  tsettings_combineMode;
      settings_primcolor      : in  tsettings_primcolor;
      settings_envcolor       : in  tsettings_envcolor;
     
      pipeInColor             : in  tcolor4_s16;
      tex_alpha               : in  unsigned(7 downto 0);
      lod_frac                : in  unsigned(7 downto 0);
      cvgCount                : in  unsigned(3 downto 0);

      combine_alpha           : out unsigned(7 downto 0) := (others => '0')
   );
end entity;

architecture arch of RDP_CombineAlpha is

   signal mode_sub1          : unsigned(2 downto 0);
   signal mode_sub2          : unsigned(2 downto 0);
   signal mode_mul           : unsigned(2 downto 0);
   signal mode_add           : unsigned(2 downto 0);
                             
   signal alpha_sub1         : signed(9 downto 0);
   signal alpha_sub2         : signed(9 downto 0);
   signal alpha_mul          : signed(9 downto 0);
   signal alpha_add          : signed(9 downto 0);
                             
   signal combiner_sub       : signed(9 downto 0);
   signal combiner_mul       : signed(19 downto 0);
   signal combiner_add       : signed(19 downto 0);
   signal combiner_cut       : signed(11 downto 0);
   
   signal combine_alpha_next : signed(9 downto 0) := (others => '0');

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
         when 0 => alpha_sub1 <= combine_alpha_next;
         when 1 => alpha_sub1 <= "00" & signed(tex_alpha);
         --when 2 => tex2
         when 3 => alpha_sub1 <= "00" & signed(settings_primcolor.prim_A);
         when 4 => alpha_sub1 <= '0' & pipeInColor(3)(8 downto 0);
         when 5 => alpha_sub1 <= "00" & signed(settings_envcolor.env_A);
         when 6 => alpha_sub1 <= 10x"100";
         when 7 => alpha_sub1 <= (others => '0');
         when others => null;
      end case;
      
      alpha_sub2 <= (others => '0');
      case (to_integer(mode_sub2)) is
         when 0 => alpha_sub2 <= combine_alpha_next;
         when 1 => alpha_sub2 <= "00" & signed(tex_alpha);
         --when 2 => tex2
         when 3 => alpha_sub2 <= "00" & signed(settings_primcolor.prim_A);
         when 4 => alpha_sub2 <= '0' & pipeInColor(3)(8 downto 0);
         when 5 => alpha_sub2 <= "00" & signed(settings_envcolor.env_A);
         when 6 => alpha_sub2 <= 10x"100";
         when 7 => alpha_sub2 <= (others => '0');
         when others => null;
      end case;
      
      alpha_mul <= (others => '0');
      case (to_integer(mode_mul)) is
         when 0 => alpha_mul <= "00" & signed(lod_frac);
         when 1 => alpha_mul <= "00" & signed(tex_alpha);
         --when 2 => tex2
         when 3 => alpha_mul <= "00" & signed(settings_primcolor.prim_A);
         when 4 => alpha_mul <= '0' & pipeInColor(3)(8 downto 0);
         when 5 => alpha_mul <= "00" & signed(settings_envcolor.env_A);
         --when 6 => prim level Frac
         --when 7 => alpha_sub2 <= (others => '0');
         when others => null;
      end case;
      
      alpha_add <= (others => '0');
      case (to_integer(mode_add)) is
         when 0 => alpha_add <= combine_alpha_next;
         when 1 => alpha_add <= "00" & signed(tex_alpha);
         --when 2 => tex2
         when 3 => alpha_add <= "00" & signed(settings_primcolor.prim_A);
         when 4 => alpha_add <= '0' & pipeInColor(3)(8 downto 0);
         when 5 => alpha_add <= "00" & signed(settings_envcolor.env_A);
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
      variable result : unsigned(7 downto 0);
   begin
      if rising_edge(clk1x) then
      
         error_combineAlpha <= '0';
         
         if (trigger = '1') then
            
            combine_alpha_next <= combiner_cut(9 downto 0);
            
            if (combiner_cut(8 downto 7) = "11") then
               result := (others => '0');
            elsif (combiner_cut(8) = '1') then 
               result := (others => '1');
            else
               result := unsigned(combiner_cut(7 downto 0));
            end if;
            
            combine_alpha <= result;
            
            if (settings_otherModes.cvgTimesAlpha = '1') then
               error_combineAlpha <= '1'; -- todo: update cvg count
            end if;
            
            if (settings_otherModes.alphaCvgSelect = '0') then
               if (settings_otherModes.key = '0') then
                  combine_alpha <= result; -- todo : add dither
               else
                  error_combineAlpha <= '1'; -- todo: key alpha mode
               end if;
            else
               if (settings_otherModes.cvgTimesAlpha = '1') then
                  error_combineAlpha <= '1'; -- todo: alpha from combiner alpha * cvg count
               else 
                  if (cvgCount(3) = '1') then
                     combine_alpha <= x"FF";
                  else
                     combine_alpha <= cvgCount(2 downto 0) & "00000";
                  end if;
               end if;
            end if;
            
         end if;
         
      end if;
   end process;

end architecture;





