library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;
use work.pFunctions.all;

entity RDP_CombineColor is
   port 
   (
      clk1x                   : in  std_logic;
      trigger                 : in  std_logic;
   
      errorCombine_out        : out std_logic := '0';
   
      settings_otherModes     : in  tsettings_otherModes;
      settings_combineMode    : in  tsettings_combineMode;
      settings_primcolor      : in  tsettings_primcolor;
      settings_envcolor       : in  tsettings_envcolor;
     
      pipeInColor             : in  tcolor4_s16;
      texture_color           : in  tcolor3_u8;

      combine_color           : out tcolor3_u8
   );
end entity;

architecture arch of RDP_CombineColor is

   signal mode_sub1        : unsigned(3 downto 0);
   signal mode_sub2        : unsigned(3 downto 0);
   signal mode_mul         : unsigned(4 downto 0);
   signal mode_add         : unsigned(2 downto 0);
   
   signal primcolor        : tcolor3_u8;
   signal envcolor         : tcolor3_u8;
            
   signal color_sub1       : tcolor3_s10 := (others => (others => '0'));
   signal color_sub2       : tcolor3_s10 := (others => (others => '0'));
   signal color_mul        : tcolor3_s10 := (others => (others => '0'));
   signal color_add        : tcolor3_s10 := (others => (others => '0'));
   
   signal combiner_sub     : tcolor3_s10;
   signal combiner_mul     : tcolor3_s20;
   signal combiner_add     : tcolor3_s20;
   signal combiner_cut     : tcolor3_s12;
   
   signal errorCombine     : std_logic;

begin 

   -- todo: switch mode for cycle2
   mode_sub1 <= settings_combineMode.combine_sub_a_R_1;
   mode_sub2 <= settings_combineMode.combine_sub_b_R_1;
   mode_mul  <= settings_combineMode.combine_mul_R_1;
   mode_add  <= settings_combineMode.combine_add_R_1;
   
   primcolor(0) <= settings_primcolor.prim_R;
   primcolor(1) <= settings_primcolor.prim_G;
   primcolor(2) <= settings_primcolor.prim_B;   
   
   envcolor(0) <= settings_envcolor.env_R;
   envcolor(1) <= settings_envcolor.env_G;
   envcolor(2) <= settings_envcolor.env_B;
   
   process (all)
   begin
      
      errorCombine <= '0';
      
      for i in 0 to 2 loop
         
         color_sub1(i) <= (others => '0');
         case (to_integer(mode_sub1)) is
            when 0 => color_sub1(i) <= "00" & signed(combine_color(i));
            when 1 => color_sub1(i) <= "00" & signed(texture_color(i));
            when 2 => errorCombine <= '1'; -- tex2
            when 3 => color_sub1(i) <= "00" & signed(primcolor(i));
            when 4 => color_sub1(i) <= '0' & pipeInColor(i)(8 downto 0);
            when 5 => color_sub1(i) <= "00" & signed(envcolor(i));
            when 6 => color_sub1(i) <= 10x"100";
            when 7 => errorCombine <= '1'; --noise
            when others => null;
         end case;
         
         color_sub2(i) <= (others => '0');
         case (to_integer(mode_sub2)) is
            when 0 => color_sub2(i) <= "00" & signed(combine_color(i));
            when 1 => color_sub2(i) <= "00" & signed(texture_color(i));
            when 2 => errorCombine <= '1'; -- tex2
            when 3 => color_sub2(i) <= "00" & signed(primcolor(i));
            when 4 => color_sub2(i) <= '0' & pipeInColor(i)(8 downto 0);
            when 5 => color_sub2(i) <= "00" & signed(envcolor(i));
            when 6 => errorCombine <= '1'; -- key center
            when 7 => errorCombine <= '1'; -- k4
            when others => null;
         end case;
         
         color_mul(i) <= (others => '0');
         case (to_integer(mode_mul)) is
            when  0 => color_mul(i) <= "00" & signed(combine_color(i));
            when  1 => color_mul(i) <= "00" & signed(texture_color(i));
            when  2 => errorCombine <= '1'; --tex2
            when  3 => color_mul(i) <= "00" & signed(primcolor(i));
            when  4 => color_mul(i) <= '0' & pipeInColor(i)(8 downto 0);
            when  5 => color_mul(i) <= "00" & signed(envcolor(i));
            when  6 => errorCombine <= '1'; -- key scale
            when  7 => errorCombine <= '1'; -- combiner color
            when  8 => errorCombine <= '1'; -- tex1 A
            when  9 => errorCombine <= '1'; -- tex2 A
            when 10 => color_mul(i) <= "00" & signed(settings_primcolor.prim_A);
            when 11 => color_mul(i) <= '0' & pipeInColor(3)(8 downto 0);
            when 12 => color_mul(i) <= "00" & signed(settings_envcolor.env_A);
            when 13 => errorCombine <= '1'; -- lod frac
            when 14 => errorCombine <= '1'; -- primlevel frac
            when 15 => errorCombine <= '1'; -- k5
            when others => null;
         end case;
         
         color_add(i) <= (others => '0');
         case (to_integer(mode_add)) is
            when 0 => color_add(i) <= "00" & signed(combine_color(i));
            when 1 => color_add(i) <= "00" & signed(texture_color(i));
            when 2 => errorCombine <= '1'; --tex2
            when 3 => color_add(i) <= "00" & signed(primcolor(i));
            when 4 => color_add(i) <= '0' & pipeInColor(i)(8 downto 0);
            when 5 => color_add(i) <= "00" & signed(envcolor(i));
            when 6 => color_add(i) <= 10x"100";
            when others => null;
         end case;
   
      end loop;

   end process;
   
   gcalc: for i in 0 to 2 generate
   begin
   
      combiner_sub(i)   <= color_sub1(i) - color_sub2(i);
      combiner_mul(i)   <= combiner_sub(i) * color_mul(i); 
      combiner_add(i)   <= combiner_mul(i) + (color_add(i) & x"80");
      combiner_cut(i)   <= combiner_add(i)(19 downto 8);
   
   end generate;
   

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         --todo: keep unclamped result for cycle 2
         
         if (trigger = '1') then
         
            errorCombine_out <= errorCombine;
         
            for i in 0 to 2 loop
               if (combiner_cut(i)(8 downto 7) = "11") then
                  combine_color(i) <= (others => '0');
               elsif (combiner_cut(i)(8) = '1') then 
                  combine_color(i) <= (others => '1');
               else
                  combine_color(i) <= unsigned(combiner_cut(i)(7 downto 0));
               end if;
            end loop;
            
         end if;
         
      end if;
   end process;

end architecture;





