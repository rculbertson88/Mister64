library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pRDP is

   type tsettings_poly is record
      lft         : std_logic;
      maxLODlevel : unsigned(2 downto 0);
      tile        : unsigned(2 downto 0);
      YL          : signed(14 downto 0);
      YM          : signed(14 downto 0);
      YH          : signed(14 downto 0);
      XL          : signed(31 downto 0);
      DXLDy       : signed(29 downto 0);
      XH          : signed(31 downto 0);
      DXHDy       : signed(29 downto 0);
      XM          : signed(31 downto 0);
      DXMDy       : signed(29 downto 0);
   end record;    

   type tsettings_scissor is record
      ScissorXL     : unsigned(11 downto 0);
      ScissorXH     : unsigned(11 downto 0);
      ScissorYL     : unsigned(11 downto 0);
      ScissorYH     : unsigned(11 downto 0);
      ScissorField  : std_logic;
      ScissorOdd    : std_logic;
   end record;     
   
   type tsettings_otherModes is record
      alphaCompare       : std_logic;
      ditherAlpha        : std_logic;
      zSourceSel         : std_logic;
      AntiAlias          : std_logic;
      zCompare           : std_logic;
      zUpdate            : std_logic;
      imageRead          : std_logic;
      colorOnCvg         : std_logic;
      cvgDest            : unsigned(1 downto 0);
      zMode              : unsigned(1 downto 0);
      cvgTimesAlpha      : std_logic;
      alphaCvgSelect     : std_logic;
      forceBlend         : std_logic;
      blend_m2b1         : unsigned(1 downto 0);
      blend_m2b0         : unsigned(1 downto 0);
      blend_m2a1         : unsigned(1 downto 0);
      blend_m2a0         : unsigned(1 downto 0);
      blend_m1b1         : unsigned(1 downto 0);
      blend_m1b0         : unsigned(1 downto 0);
      blend_m1a1         : unsigned(1 downto 0);
      blend_m1a0         : unsigned(1 downto 0);
      alphaDitherSel     : unsigned(1 downto 0);
      rgbDitherSel       : unsigned(1 downto 0);
      key                : std_logic;
      convertOne         : std_logic;
      biLerp1            : std_logic;
      biLerp0            : std_logic;
      midTexel           : std_logic;
      sampleType         : std_logic;
      tlutType           : std_logic;
      enTlut             : std_logic;
      texLod             : std_logic;
      sharpenTex         : std_logic;
      detailTex          : std_logic;
      perspTex           : std_logic;
      cycleType          : unsigned(1 downto 0);
      atomicPrim         : std_logic;
   end record;    
   
   type tsettings_fillcolor is record
      color     : unsigned(31 downto 0);
   end record;        
   
   type tsettings_blendcolor is record
      blend_A     : unsigned(7 downto 0);
      blend_B     : unsigned(7 downto 0);
      blend_G     : unsigned(7 downto 0);
      blend_R     : unsigned(7 downto 0);
   end record;     
   
   type tsettings_combineMode is record
      combine_add_A_1   : unsigned(2 downto 0);
      combine_sub_b_A_1 : unsigned(2 downto 0);
      combine_add_R_1   : unsigned(2 downto 0);
      combine_add_A_0   : unsigned(2 downto 0);
      combine_sub_b_A_0 : unsigned(2 downto 0);
      combine_add_R_0   : unsigned(2 downto 0);
      combine_mul_A_1   : unsigned(2 downto 0);
      combine_sub_a_A_1 : unsigned(2 downto 0);
      combine_sub_b_R_1 : unsigned(3 downto 0);
      combine_sub_b_R_0 : unsigned(3 downto 0);
      combine_mul_R_1   : unsigned(4 downto 0);
      combine_sub_a_R_1 : unsigned(3 downto 0);
      combine_mul_A_0   : unsigned(2 downto 0);
      combine_sub_a_A_0 : unsigned(2 downto 0);
      combine_mul_R_0   : unsigned(4 downto 0);
      combine_sub_a_R_0 : unsigned(3 downto 0);
   end record;  
   
   type tsettings_colorImage is record
      FB_base      : unsigned(24 downto 0);
      FB_width_m1  : unsigned(13 downto 0);
      FB_size      : unsigned(1 downto 0);
      FB_format    : unsigned(2 downto 0);
   end record; 
   
end package;