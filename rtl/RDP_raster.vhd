library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;
use work.pFunctions.all;

entity RDP_raster is
   port 
   (
      clk1x                   : in  std_logic;
      reset                   : in  std_logic;
   
      settings_poly           : in  tsettings_poly := SETTINGSPOLYINIT;
      settings_scissor        : in  tsettings_scissor := SETTINGSSCISSORINIT;
      settings_otherModes     : in  tsettings_otherModes;
      settings_fillcolor      : in  tsettings_fillcolor;
      settings_blendcolor     : in  tsettings_blendcolor;
      settings_colorImage     : in  tsettings_colorImage;
      settings_textureImage   : in  tsettings_textureImage;
      settings_tile           : in  tsettings_tile;
      settings_loadtype       : in  tsettings_loadtype;
      poly_start              : in  std_logic;
      loading_mode            : in  std_logic;
      poly_done               : out std_logic := '0';
      
      TextureReqRAMreq        : out std_logic := '0';
      TextureReqRAMaddr       : out unsigned(25 downto 0) := (others => '0');
      TextureReqRAMPtr        : out unsigned(4 downto 0) := (others => '0');
      TextureReqRAMData       : in  std_logic_vector(63 downto 0);
      TextureReqRAMReady      : in  std_logic;
      
      TextureRamAddr          : out unsigned(8 downto 0) := (others => '0');    
      TextureRam0Data         : out std_logic_vector(15 downto 0) := (others => '0');
      TextureRam1Data         : out std_logic_vector(15 downto 0) := (others => '0');
      TextureRam2Data         : out std_logic_vector(15 downto 0) := (others => '0');
      TextureRam3Data         : out std_logic_vector(15 downto 0) := (others => '0');
      TextureRamWE            : out std_logic_vector(7 downto 0)  := (others => '0');
     
      -- synthesis translate_off
      export_line_done        : out std_logic := '0'; 
      export_line_list        : out rdp_export_type := (others => (others => '0')); 
         
      export_load_done        : out std_logic := '0'; 
      export_loadFetch        : out rdp_export_type := (others => (others => '0')); 
      export_loadData         : out rdp_export_type := (others => (others => '0')); 
      export_loadValue        : out rdp_export_type := (others => (others => '0')); 
      -- synthesis translate_on
      
      writePixel              : out std_logic := '0';
      writePixelAddr          : out unsigned(25 downto 0);
      writePixelX             : out unsigned(11 downto 0) := (others => '0');
      writePixelY             : out unsigned(11 downto 0) := (others => '0');
      writePixelColor         : out unsigned(31 downto 0) := (others => '0');
      fillWrite               : out std_logic := '0';
      fillBE                  : out unsigned(7 downto 0) := (others => '0');
      fillColor               : out unsigned(63 downto 0) := (others => '0')
   );
end entity;

architecture arch of RDP_raster is

   type tpolyState is 
   (  
      POLYIDLE, 
      EVALLINE,
      WAITLINE,
      POLYFINISH
   ); 
   signal polystate  : tpolyState := POLYIDLE;    

   signal xleft_inc     : signed(27 downto 0) := (others => '0');
   signal xright_inc    : signed(27 downto 0);
   signal xright        : signed(31 downto 0) := (others => '0');
   signal xleft         : signed(31 downto 0) := (others => '0');
   signal do_offset     : std_logic;
   signal ycur          : signed(14 downto 0) := (others => '0');
   signal ldflag        : unsigned(1 downto 0) := (others => '0');
   signal yLLimitMux    : signed(14 downto 0);
   signal yHLimitMux    : signed(14 downto 0);
   signal ylfar         : signed(14 downto 0) := (others => '0');
   signal yllimit       : signed(14 downto 0) := (others => '0');
   signal yhlimit       : signed(14 downto 0) := (others => '0');
   signal yhclose       : signed(14 downto 0);
   signal clipxlshift   : unsigned(12 downto 0);
   signal clipxhshift   : unsigned(12 downto 0);
      
   signal secondHalf    : std_logic := '0';
   signal allover       : std_logic := '0';
   signal allunder      : std_logic := '0';
   signal allinval      : std_logic := '0';
   signal unscrx        : signed(12 downto 0) := (others => '0');
   signal maxxmx        : unsigned(11 downto 0) := (others => '0');
   signal minxmx        : unsigned(11 downto 0) := (others => '0');
      
   type t_majorminor is array(0 to 3) of unsigned(12 downto 0);
   signal majorx        : t_majorminor := (others => (others => '0'));
   signal minorx        : t_majorminor := (others => (others => '0'));
   signal invalidLine   : std_logic_vector(3 downto 0) := (others => '0');
   
   -- comb calculation
   signal sticky_r      : std_logic := '0';  
   signal sticky_l      : std_logic := '0';  
   signal xrsc_sticky   : unsigned(13 downto 0) := (others => '0');
   signal xlsc_sticky   : unsigned(13 downto 0) := (others => '0');   
   signal xrsc_under    : unsigned(14 downto 0) := (others => '0');
   signal xlsc_under    : unsigned(14 downto 0) := (others => '0');   
   signal xrsc          : unsigned(14 downto 0) := (others => '0');
   signal xlsc          : unsigned(14 downto 0) := (others => '0');
   signal curover_r     : std_logic := '0';
   signal curover_l     : std_logic := '0';
   signal curunder_r    : std_logic := '0';
   signal curunder_l    : std_logic := '0';  
   signal xright_cross  : unsigned(13 downto 0) := (others => '0');
   signal xleft_cross   : unsigned(13 downto 0) := (others => '0');   
   signal curcross      : std_logic := '0';
   signal invaly        : std_logic := '0';
   
   -- poly accu
   signal poly_Color_R     : signed(31 downto 0) := (others => '0');
   signal poly_Color_G     : signed(31 downto 0) := (others => '0');
   signal poly_Color_B     : signed(31 downto 0) := (others => '0');
   signal poly_Color_A     : signed(31 downto 0) := (others => '0');
   signal poly_Texture_S   : signed(31 downto 0) := (others => '0');
   signal poly_Texture_T   : signed(31 downto 0) := (others => '0');
   signal poly_Texture_W   : signed(31 downto 0) := (others => '0');
   signal poly_Z           : signed(31 downto 0) := (others => '0');   
   
   type tlineInfo is record
      y           : unsigned(11 downto 0);
      xStart      : unsigned(11 downto 0); 
      xEnd        : unsigned(11 downto 0);
      unscrx      : signed(12 downto 0);
      Color_R     : signed(31 downto 0);
      Color_G     : signed(31 downto 0);
      Color_B     : signed(31 downto 0);
      Color_A     : signed(31 downto 0);
      Texture_S   : signed(31 downto 0);
      Texture_T   : signed(31 downto 0);
      Texture_W   : signed(31 downto 0);
      Z           : signed(31 downto 0);
   end record;
   signal lineInfo      : tlineInfo;
   signal startLine     : std_logic := '0';
   
   -- line drawing
   type tlineState is 
   (  
      LINEIDLE, 
      DRAWLINE,
      FILLLINE
   ); 
   signal linestate  : tlineState := LINEIDLE;    
   
   signal drawLineDone     : std_logic;
   signal line_posY        : unsigned(11 downto 0) := (others => '0');
   signal line_posX        : unsigned(11 downto 0) := (others => '0');
   signal line_endX        : unsigned(11 downto 0) := (others => '0');
   
   -- comb calculation
   signal calcPixelAddr    : unsigned(25 downto 0);
   
   -- line loading
   type tloadState is 
   (  
      LOADIDLE,
      LOADRAM,      
      LOADLINE
   ); 
   signal loadState  : tloadState := LOADIDLE;  
   
   signal loadLineDone        : std_logic;
   signal load_posX           : unsigned(11 downto 0) := (others => '0');
   signal load_endX           : unsigned(11 downto 0) := (others => '0');
   signal loadTexture_S       : signed(31 downto 0);
   signal loadTexture_T       : signed(31 downto 0);
   signal load_memAddr        : unsigned(25 downto 0) := (others => '0');
   
   signal TextureReqRAM_index : unsigned(4 downto 0) := (others => '0');

   -- comb calculation
   signal spanAdvance         : integer range 0 to 8;
   signal memAdvance          : integer range 0 to 8;
   signal load_S_sub          : signed(15 downto 0);
   signal load_T_sub          : signed(15 downto 0);   
   signal load_S_corrected    : signed(12 downto 0);
   signal load_T_corrected    : signed(12 downto 0);   
   signal load_S_shifted      : unsigned(10 downto 0);
   signal load_bit3flipped    : std_logic;
   signal load_hibit          : std_logic;
   signal load_linesize       : unsigned(21 downto 0);
   signal load_tbase_mul      : unsigned(21 downto 0);
   signal load_tbase          : unsigned(8 downto 0);
   signal load_tmemAddr0      : unsigned(10 downto 0);
   signal load_tmemAddr1      : unsigned(10 downto 0);
   signal load_tmemAddr2      : unsigned(10 downto 0);
   signal load_tmemAddr3      : unsigned(10 downto 0);
   signal load_Ram0Addr       : unsigned(10 downto 0) := (others => '0');
   signal load_Ram1Addr       : unsigned(10 downto 0) := (others => '0');
   signal load_Ram2Addr       : unsigned(10 downto 0) := (others => '0');
   signal load_Ram3Addr       : unsigned(10 downto 0) := (others => '0');      
   signal load_Ram0Data       : std_logic_vector(15 downto 0) := (others => '0');
   signal load_Ram1Data       : std_logic_vector(15 downto 0) := (others => '0');
   signal load_Ram2Data       : std_logic_vector(15 downto 0) := (others => '0');
   signal load_Ram3Data       : std_logic_vector(15 downto 0) := (others => '0');
   
   -- export only
   -- synthesis translate_off
   signal load_posY           : unsigned(11 downto 0) := (others => '0');
   -- synthesis translate_on

begin 

   xright_inc     <= settings_poly.DXHDy(29 downto 3) & '0';
   xleft_inc      <= settings_poly.DXMDy(29 downto 3) & '0' when (secondhalf = '0') else settings_poly.DXLDy(29 downto 3) & '0';
      
   do_offset      <= settings_poly.DXHDy(29) xor settings_poly.lft;
   
   yLLimitMux     <= settings_poly.YL(14 downto 0)           when (loading_mode = '1' or settings_poly.YL(13) = '1') else
                  "000" & signed(settings_scissor.ScissorYL) when (settings_poly.YL(12) = '1') else
                  settings_poly.YL(14 downto 0)              when (unsigned(settings_poly.YL(11 downto 0)) < settings_scissor.ScissorYL) else
                  "000" & signed(settings_scissor.ScissorYL);   
                  
   yHLimitMux     <= settings_poly.YH(14 downto 0)           when (loading_mode = '1' or settings_poly.YH(13) = '1') else
                  "000" & signed(settings_scissor.ScissorYH) when (settings_poly.YH(12) = '1') else
                  settings_poly.YH(14 downto 0)              when (settings_poly.YH >= to_integer(settings_scissor.ScissorYH)) else
                  "000" & signed(settings_scissor.ScissorYH);
   
   yhclose        <= yHLimitMux(14 downto 2) & "00";
   
   clipxlshift    <= settings_scissor.ScissorXL & '0';
   clipxhshift    <= settings_scissor.ScissorXH & '0';
   
   sticky_r       <= '1' when (xright(13 downto 1) > 0) else '0';
   sticky_l       <= '1' when (xleft(13 downto 1) > 0) else '0';
   
   xrsc_sticky    <= unsigned(xright(26 downto 14)) & sticky_r;
   xlsc_sticky    <= unsigned(xleft(26 downto 14))  & sticky_l;
   
   curunder_r     <= '1' when (xright(27) = '1' or (xrsc_sticky < clipxhshift and xright(26) = '0')) else '0';
   curunder_l     <= '1' when (xleft(27)  = '1' or (xlsc_sticky < clipxhshift and xleft(26)  = '0')) else '0';
   
   xrsc_under     <= "00" & clipxhshift when (curunder_r = '1') else unsigned(xright(27 downto 14)) & sticky_r;
   xlsc_under     <= "00" & clipxhshift when (curunder_l = '1') else unsigned(xleft(27 downto 14))  & sticky_l;
   
   curover_r      <= '1' when (xrsc_under(13) = '1' or xrsc_under > clipxlshift) else '0';
   curover_l      <= '1' when (xlsc_under(13) = '1' or xlsc_under > clipxlshift) else '0';
   
   xrsc           <= "00" & clipxlshift when (curover_r = '1') else xrsc_under(14 downto 0);
   xlsc           <= "00" & clipxlshift when (curover_l = '1') else xlsc_under(14 downto 0);
   
   xright_cross   <= not xright(27) & unsigned(xright(26 downto 14));
   xleft_cross    <= not xleft(27)  & unsigned(xleft(26 downto 14));
   
   curcross       <= '1' when (settings_poly.lft = '1' and xleft_cross < xright_cross) else
                     '1' when (settings_poly.lft = '0' and xright_cross < xleft_cross) else
                     '0';
   
   invaly         <= '1' when (ycur < yhlimit) else
                     '1' when (ycur >= yllimit) else
                     '1' when curcross = '1' else
                     '0';
   
   process (clk1x)
      variable unscrx_new : signed(12 downto 0) := (others => '0');
      variable maxxmx_new : unsigned(11 downto 0) := (others => '0');
      variable minxmx_new : unsigned(11 downto 0) := (others => '0');
   begin
      if rising_edge(clk1x) then
      
         unscrx_new := unscrx;
         maxxmx_new := maxxmx;
         minxmx_new := minxmx;
      
         poly_done  <= '0';

         if (reset = '1') then
            
            polystate <= POLYIDLE;
            startLine <= '0';
            
         else
            
            case (polystate) is
            
               when POLYIDLE =>
                  if (poly_start = '1') then
                     polystate <= EVALLINE;
                     --todos:
                     -- dzpix
                     -- normalize_dzpix
                     -- if (do_offset) .. if (otherModes_cycleType != 2)
                     xright         <= settings_poly.XH(31 downto 1) & '0';
                     if (settings_poly.YH(14 downto 2) & "00" = settings_poly.YM) then
                        secondHalf <= '1';
                        xleft      <= settings_poly.XL(31 downto 1) & '0';
                     else
                        secondHalf  <= '0';
                        xleft       <= settings_poly.XM(31 downto 1) & '0';
                     end if;
                     ycur           <= settings_poly.YH(14 downto 2) & "00";
                     ldflag         <= (others => not do_offset);
                     yllimit        <= yLLimitMux;
                     if (settings_poly.YL(14 downto 2) > yLLimitMux(14 downto 2)) then
                        ylfar       <= (yLLimitMux(14 downto 2) + 1) & "11";
                     else
                        ylfar       <= yLLimitMux(14 downto 2) & "11";
                     end if;
                     yhlimit        <= yHLimitMux;
                     allover        <= '1';
                     allunder       <= '1';
                     allinval       <= '1';
                     maxxmx         <= (others => '0');
                     minxmx         <= (others => '0');
                     
                     poly_Color_R   <= settings_poly.shade_Color_R;
                     poly_Color_G   <= settings_poly.shade_Color_G;
                     poly_Color_B   <= settings_poly.shade_Color_B;
                     poly_Color_A   <= settings_poly.shade_Color_A;
                     poly_Texture_S <= settings_poly.tex_Texture_S;
                     poly_Texture_S <= settings_poly.tex_Texture_T;
                     poly_Texture_W <= settings_poly.tex_Texture_W;
                     poly_Z         <= settings_poly.zBuffer_Z;
                  end if;                  
               
               when EVALLINE =>
                  ycur <= ycur + 1;
                  if (ycur >= ylfar) then
                     polystate <= POLYFINISH;
                  end if;
                  
                  if ((loading_mode = '1' and ycur(14 downto 12) = "000") or (loading_mode = '0' and ycur >= yhclose)) then

                     if (ycur(1 downto 0) = 0) then
                        maxxmx_new     := (others => '0');
                        minxmx_new     := (others => '1');
                        allover        <= '1';
                        allunder       <= '1';
                        allinval       <= '1';
                     end if;
                
                     if (loading_mode = '1') then
                        allover        <= '0';
                        allunder       <= '0';
                     else
                        majorx(to_integer(unsigned(ycur(1 downto 0)))) <= xrsc(12 downto 0);
                        minorx(to_integer(unsigned(ycur(1 downto 0)))) <= xlsc(12 downto 0);   
                        if (curover_r  = '0' or curover_l  = '0') then allover  <= '0'; end if;
                        if (curunder_r = '0' or curunder_l = '0') then allunder <= '0'; end if;
                     end if;
                     
                     invalidLine(to_integer(unsigned(ycur(1 downto 0)))) <= invaly;
                     if (invaly = '0') then allinval <= '0'; end if;
                     
                     if (invaly = '0') then
                        if (settings_poly.lft = '1') then
                           if (xlsc(14 downto 3) > maxxmx_new) then maxxmx_new := xlsc(14 downto 3); end if;
                           if (xrsc(14 downto 3) < minxmx_new) then minxmx_new := xrsc(14 downto 3); end if;
                        else
                           if (xlsc(14 downto 3) < minxmx_new) then minxmx_new := xlsc(14 downto 3); end if;
                           if (xrsc(14 downto 3) > maxxmx_new) then maxxmx_new := xrsc(14 downto 3); end if;
                        end if;
                     end if;
                
                     if (unsigned(ycur(1 downto 0)) = ldflag) then
                        unscrx_new := xright(28 downto 16);
                        -- todo: fractional line information for color/texture/z
                        lineInfo.Color_R   <= poly_Color_R;  
                        lineInfo.Color_G   <= poly_Color_G;  
                        lineInfo.Color_B   <= poly_Color_B;  
                        lineInfo.Color_A   <= poly_Color_A;  
                        lineInfo.Texture_S <= poly_Texture_S;
                        lineInfo.Texture_T <= poly_Texture_T;
                        lineInfo.Texture_W <= poly_Texture_W;
                        lineInfo.Z         <= poly_Z;       
                     end if;
                     
                     unscrx <= unscrx_new;
                     maxxmx <= maxxmx_new;
                     minxmx <= minxmx_new;
                     
                     if (unsigned(ycur(1 downto 0)) = 3) then
                        startLine         <= '1';
                        lineInfo.y        <= unsigned(ycur(13 downto 2)); 
                        lineInfo.xStart   <= minxmx_new;
                        lineInfo.xEnd     <= maxxmx_new;
                        lineInfo.unscrx   <= unscrx_new;
                        if (startLine = '1') then
                           polystate      <= WAITLINE;
                        end if;
                     end if;
                
                  end if;
                  
                  if (unsigned(ycur(1 downto 0)) = 3) then
                     poly_Color_R   <= poly_Color_R   + settings_poly.shade_DrDe;
                     poly_Color_G   <= poly_Color_G   + settings_poly.shade_DgDe;
                     poly_Color_B   <= poly_Color_B   + settings_poly.shade_DbDe;
                     poly_Color_A   <= poly_Color_A   + settings_poly.shade_DaDe;
                     poly_Texture_S <= poly_Texture_S + settings_poly.tex_DsDe;
                     poly_Texture_T <= poly_Texture_T + settings_poly.tex_DtDe;
                     poly_Texture_W <= poly_Texture_W + settings_poly.tex_DwDe;
                     poly_Z         <= poly_Z         + settings_poly.zBuffer_DzDe;
                  end if;
            
                  xleft  <= xleft + xleft_inc;
                  xright <= xright + xright_inc;
                  
                  if (ycur + 1 = settings_poly.YM) then
                     secondHalf <= '1';
                     xleft      <= settings_poly.XL(31 downto 1) & '0';
                  end if;
                  
               when WAITLINE =>
                  if (startLine = '0') then
                     polystate <= EVALLINE;
                     startLine <= '1';
                  end if;
                  
               when POLYFINISH =>
                  if (startLine = '0' and linestate = LINEIDLE and loadstate = LOADIDLE) then
                     polystate <= POLYIDLE;
                     poly_done <= '1'; 
                  end if;
            
            end case; -- polystate
            
            if (drawLineDone = '1' or loadLineDone = '1') then
               startLine <= '0';
            end if;
            
            if (startLine = '1' and (allinval = '1' or allover = '1' or allunder = '1')) then
               startLine <= '0';
            end if;
            
         end if;
      end if;
   end process;
   
   -- drawing
   drawLineDone <= '1' when (linestate = DRAWLINE and line_posX = line_endX) else 
                   '1' when (linestate = FILLLINE and line_posX > line_endX) else 
                   '0';
   
   calcPixelAddr <= resize(settings_colorImage.FB_base + ((line_posY * (settings_colorImage.FB_width_m1 + 1)) + line_posX) * 2, 26) when (settings_colorImage.FB_size = SIZE_16BIT) else
                    resize(settings_colorImage.FB_base + ((line_posY * (settings_colorImage.FB_width_m1 + 1)) + line_posX) * 4, 26);
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         writePixel <= '0';
         fillWrite  <= '0';
         
         if (reset = '1') then
            
            linestate <= LINEIDLE;
            
         else
            
            case (linestate) is
            
               when LINEIDLE =>
                  if (startLine = '1' and allinval = '0' and allover = '0' and allunder = '0') then
                     if (loading_mode = '0') then
                        if (settings_otherModes.cycleType = "11") then
                           linestate <= FILLLINE;
                        else
                           linestate <= DRAWLINE;
                        end if;
                     end if;
                     line_posY <= lineInfo.Y;
                     if (settings_poly.lft = '1' or settings_otherModes.cycleType = "11") then
                        line_posX <= lineInfo.xStart;
                        line_endX <= lineInfo.xEnd;
                     else
                        line_posX <= lineInfo.xEnd;
                        line_endX <= lineInfo.xStart;
                     end if;
                  end if;                  
               
               when DRAWLINE =>
                  if (settings_poly.lft = '1') then
                     line_posX <= line_posX + 1;
                  else
                     line_posX <= line_posX - 1;
                  end if;
                  if (drawLineDone = '1') then
                     linestate <= LINEIDLE;
                  end if;
                  
                  -- hack!
                  writePixelAddr                <= calcPixelAddr;
                  writePixelX                   <= line_posX;
                  writePixelY                   <= line_posY;
                  writePixel                    <= '1';
                  writePixelColor(31 downto 16) <= (others => '0');
                  writePixelColor(15 downto 0)  <= byteswap16(settings_blendcolor.blend_R(7 downto 3) & settings_blendcolor.blend_G(7 downto 3) & settings_blendcolor.blend_B(7 downto 3) & '0');
                  
               when FILLLINE =>
                  writePixelAddr <= calcPixelAddr;
                  writePixelX    <= line_posX;
                  writePixelY    <= line_posY;
                  
                  fillWrite      <= '1';
                  fillColor      <= byteswap32(settings_fillcolor.color) & byteswap32(settings_fillcolor.color);
                  fillBE         <= (others => '1');
                  
                  case (settings_colorImage.FB_size) is
                     when SIZE_8BIT  => 
                        line_posX <= line_posX + 8 - calcPixelAddr(2 downto 0);
                        case (to_integer(line_endX - line_posX)) is
                           when 0 => fillBE(7 downto 1) <= (others => '0');
                           when 1 => fillBE(7 downto 2) <= (others => '0');
                           when 2 => fillBE(7 downto 3) <= (others => '0');
                           when 3 => fillBE(7 downto 4) <= (others => '0');
                           when 4 => fillBE(7 downto 5) <= (others => '0');
                           when 5 => fillBE(7 downto 6) <= (others => '0');
                           when 6 => fillBE(7 downto 7) <= (others => '0');
                           when others => null;
                        end case;
                        
                     when SIZE_16BIT => 
                        line_posX <= line_posX + 4 - calcPixelAddr(2 downto 1);
                        case (to_integer(line_endX - line_posX)) is
                           when 0 => fillBE(7 downto 2) <= (others => '0');
                           when 1 => fillBE(7 downto 4) <= (others => '0');
                           when 2 => fillBE(7 downto 6) <= (others => '0');
                           when others => null;
                        end case;
                        
                     when SIZE_32BIT => 
                        line_posX <= line_posX + 2 - ('0' & calcPixelAddr(2));
                        if (line_endX = line_posX) then
                           fillBE(7 downto 4) <= (others => '0');
                        end if;
                        
                     when others => report "4 Bit Fill mode, RDP will crash" severity failure; 
                  end case;
                  
                  if (drawLineDone = '1') then
                     linestate <= LINEIDLE;
                     fillWrite <= '0';
                  end if;

            end case; -- linestate
            
         end if;
      end if;
   end process;
   
   -- loading
   loadLineDone <= '1' when (loadstate = LOADLINE and load_posX = load_endX) else '0';
   
   spanAdvance <= 4 when (settings_textureImage.tex_size = SIZE_16BIT and settings_loadtype /= LOADTYPE_TLUT) else
                  1 when (settings_textureImage.tex_size = SIZE_16BIT and settings_loadtype = LOADTYPE_TLUT) else
                  2 when (settings_textureImage.tex_size = SIZE_32BIT) else
                  8;
   
   memAdvance  <= 2 when (settings_textureImage.tex_size = SIZE_16BIT and settings_loadtype = LOADTYPE_TLUT) else
                  8;
                  
   load_S_sub  <= loadTexture_S(31 downto 16) - ('0' & signed(settings_tile.Tile_sl) & "000");  
   load_T_sub  <= loadTexture_T(31 downto 16) - ('0' & signed(settings_tile.Tile_tl) & "000");    

   load_S_corrected <= resize(load_S_sub(15 downto 5), 13) when (settings_loadtype = LOADTYPE_TILE) else load_S_sub(15 downto 3);     
   load_T_corrected <= resize(load_T_sub(15 downto 5), 13) when (settings_loadtype = LOADTYPE_TILE) else load_T_sub(15 downto 3);     
   
   load_S_shifted <= unsigned(load_S_corrected(11 downto 1)) when (settings_tile.Tile_size = SIZE_8BIT or settings_tile.Tile_format = FORMAT_YUV) else
                     unsigned(load_S_corrected(10 downto 0)) when (settings_tile.Tile_size = SIZE_16BIT or settings_tile.Tile_size = SIZE_32BIT) else
                     unsigned(load_S_corrected(12 downto 2));
   
   load_bit3flipped <= load_S_shifted(1) xor load_T_corrected(0);
   
   load_linesize <= lineInfo.Y * (settings_textureImage.tex_width_m1 + 1);
   
   load_tbase_mul <= settings_tile.Tile_line * unsigned(load_T_corrected);
   load_tbase     <= load_tbase_mul(8 downto 0) + settings_tile.Tile_TmemAddr;
   
   -- todo: sorting required?
   load_tmemAddr0 <= (load_tbase & "00") + (load_s_shifted(10 downto 2) & "0" & load_s_shifted(0));
   load_tmemAddr1 <= load_tmemAddr0 + 1;
   load_tmemAddr2 <= load_tmemAddr0 + 2;
   load_tmemAddr3 <= load_tmemAddr0 + 3;
   
   load_hibit       <= load_tmemAddr0(10);
   
   TextureReqRAMaddr <= load_MemAddr;
   TextureReqRAMPtr  <= TextureReqRAM_index when (loadstate = LOADRAM) else (TextureReqRAM_index + 1);
   
   load_Ram0Addr <= load_tmemAddr0(10 downto 1) & '1';
   load_Ram1Addr <= load_tmemAddr0(10 downto 1) & '0';
   load_Ram2Addr <= load_tmemAddr0(10 downto 1) & '1';
   load_Ram3Addr <= load_tmemAddr0(10 downto 1) & '0';
   
   load_Ram0Data <= TextureReqRAMData(63 downto 48) when (load_T_corrected(0) = '0') else TextureReqRAMData(31 downto 16);
   load_Ram1Data <= TextureReqRAMData(47 downto 32) when (load_T_corrected(0) = '0') else TextureReqRAMData(15 downto  0);
   load_Ram2Data <= TextureReqRAMData(31 downto 16) when (load_T_corrected(0) = '0') else TextureReqRAMData(63 downto 48);
   load_Ram3Data <= TextureReqRAMData(15 downto  0) when (load_T_corrected(0) = '0') else TextureReqRAMData(47 downto 32);
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         -- synthesis translate_off
         export_load_done  <= '0'; 
         -- synthesis translate_on
      
         TextureReqRAMreq <= '0';
         TextureRamWE     <= (others => '0');
      
         if (reset = '1') then
            
            loadstate <= LOADIDLE;
            
         else
            
            case (loadstate) is
            
               when LOADIDLE =>
                  if (startLine = '1' and allinval = '0' and allover = '0' and allunder = '0') then
                     if (loading_mode = '1') then
                        TextureReqRAMreq <= '1';
                        loadstate        <= LOADRAM;
                     end if;
                     -- synthesis translate_off
                     load_posY      <= lineInfo.Y;
                     -- synthesis translate_on
                     load_posX      <= lineInfo.xStart;
                     load_endX      <= lineInfo.xEnd;
                     loadTexture_S  <= lineInfo.Texture_S;
                     loadTexture_T  <= lineInfo.Texture_T;
                     case (settings_textureImage.tex_size) is
                        when SIZE_16BIT => load_MemAddr <= resize(settings_textureImage.tex_base + ((load_linesize + lineInfo.xStart) * 2), 26);
                        when SIZE_32BIT => load_MemAddr <= resize(settings_textureImage.tex_base + ((load_linesize + lineInfo.xStart) * 4), 26);
                        when others     => load_MemAddr <= resize(settings_textureImage.tex_base + ((load_linesize + lineInfo.xStart) * 1), 26);
                     end case;
                     
                  end if;  
                    
               when LOADRAM =>
                  TextureReqRAM_index <= (others => '0'); -- todo: needs additional read and muxing for unaligned addresses
                  if (TextureReqRAMReady = '1') then
                     loadstate <= LOADLINE;
                  end if;
               
               when LOADLINE =>
                  load_posX    <= load_posX + spanAdvance;
                  load_MemAddr <= load_MemAddr + memAdvance;
                  
                  TextureReqRAM_index <= TextureReqRAM_index + 1;
                  
                  if (TextureReqRAM_index /= 31) then
                     load_MemAddr <= load_MemAddr + memAdvance;
                  end if;
                 
                  if (loadLineDone = '1') then
                     loadstate <= LOADIDLE;
                  elsif (TextureReqRAM_index = 31) then
                     loadstate        <= LOADRAM;
                     TextureReqRAMreq <= '1';
                  end if;
                  
                  loadTexture_S <= loadTexture_S + (settings_poly.tex_DsDx(31 downto 5) & "00000");
                  loadTexture_T <= loadTexture_T + (settings_poly.tex_DtDx(31 downto 5) & "00000");
                  
                  TextureRamAddr  <= load_Ram0Addr(10 downto 2);
                  TextureRam0Data <= load_Ram0Data;
                  TextureRam1Data <= load_Ram1Data;
                  TextureRam2Data <= load_Ram2Data;
                  TextureRam3Data <= load_Ram3Data;
                  
                  if (settings_tile.Tile_format = FORMAT_YUV) then
                     report "texture loading in YUV format" severity failure;  -- todo: implement
                  elsif (settings_tile.Tile_format = FORMAT_RGBA and settings_textureImage.tex_size = SIZE_32BIT) then
                     if (load_bit3flipped = '1') then
                        TextureRamWE(0) <= '0';
                        TextureRamWE(1) <= '0';
                        TextureRamWE(2) <= '1';
                        TextureRamWE(3) <= '1';
                        TextureRamWE(4) <= '0';
                        TextureRamWE(5) <= '0';
                        TextureRamWE(6) <= '1';
                        TextureRamWE(7) <= '1';
                     else
                        TextureRamWE(0) <= '1';
                        TextureRamWE(1) <= '1';
                        TextureRamWE(2) <= '0';
                        TextureRamWE(3) <= '0';
                        TextureRamWE(4) <= '1';
                        TextureRamWE(5) <= '1';
                        TextureRamWE(6) <= '0';
                        TextureRamWE(7) <= '0';
                     end if;
                  else
                     TextureRamWE(0) <= not load_Ram0Addr(10);
                     TextureRamWE(1) <= not load_Ram0Addr(10);
                     TextureRamWE(2) <= not load_Ram0Addr(10);
                     TextureRamWE(3) <= not load_Ram0Addr(10);
                     TextureRamWE(4) <= load_Ram0Addr(10);
                     TextureRamWE(5) <= load_Ram0Addr(10);
                     TextureRamWE(6) <= load_Ram0Addr(10);
                     TextureRamWE(7) <= load_Ram0Addr(10);
                  end if;

                  -- synthesis translate_off
                  export_load_done        <= '1'; 
                  export_loadFetch.addr   <= resize(load_MemAddr, 32);
                  export_loadFetch.data   <= (others => '0');
                  export_loadFetch.x      <= resize(load_posX, 16);
                  export_loadFetch.y      <= resize(load_posY, 16);
                  export_loadFetch.debug1 <= (others => '0');
                  export_loadFetch.debug2 <= 19x"0" & unsigned(load_S_corrected);
                  export_loadFetch.debug3 <= 19x"0" & unsigned(load_T_corrected);
                  
                  export_loadData.addr   <= resize(load_tmemAddr0, 32);
                  export_loadData.data   <= unsigned(TextureReqRAMData);
                  export_loadData.x      <= 15x"0" & load_bit3flipped;
                  export_loadData.y      <= 15x"0" & load_hibit;
                  export_loadData.debug1 <= resize(load_tmemAddr1, 32);
                  export_loadData.debug2 <= resize(load_tmemAddr2, 32);
                  export_loadData.debug3 <= resize(load_tmemAddr3, 32);
                  
                  export_loadValue.addr   <= 21x"0" & load_Ram0Addr;
                  export_loadValue.data   <= 48x"0" & unsigned(load_Ram0Data);
                  export_loadValue.x      <= (others => '0');
                  export_loadValue.y      <= (others => '0');
                  export_loadValue.debug1 <= 16x"0" & unsigned(load_Ram1Data);
                  export_loadValue.debug2 <= 16x"0" & unsigned(load_Ram2Data);
                  export_loadValue.debug3 <= 16x"0" & unsigned(load_Ram3Data);
                  -- synthesis translate_on
            
            end case; -- loadstate
            
         end if;
      end if;
   end process;
   
   
   -------- line export
   
   -- synthesis translate_off
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         export_line_done  <= '0'; 
         
         if (linestate = LINEIDLE and loadstate = LOADIDLE) then
            if (startLine = '1' and allinval = '0' and allover = '0' and allunder = '0') then
               export_line_done        <= '1'; 
               export_line_list.y      <= resize(lineInfo.y, 16);
               export_line_list.debug1 <= resize(lineInfo.xStart, 32);
               export_line_list.debug2 <= resize(lineInfo.xEnd, 32);
               export_line_list.debug3 <= resize(unsigned(lineInfo.unscrx), 32);
            end if;
         end if;
         
      end if;
    end process;  
   -- synthesis translate_on
   

end architecture;





