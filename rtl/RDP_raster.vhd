library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;
use work.pFunctions.all;

entity RDP_raster is
   port 
   (
      clk1x                : in  std_logic;
      reset                : in  std_logic;

      settings_poly        : in  tsettings_poly := SETTINGSPOLYINIT;
      settings_scissor     : in  tsettings_scissor := SETTINGSSCISSORINIT;
      settings_otherModes  : in  tsettings_otherModes;
      settings_fillcolor   : in  tsettings_fillcolor;
      settings_blendcolor  : in  tsettings_blendcolor;
      settings_colorImage  : in  tsettings_colorImage;
      poly_start           : in  std_logic;
      loading_mode         : in  std_logic;
      poly_done            : out std_logic := '0';
      
      -- synthesis translate_off
      export_line_done     : out std_logic := '0'; 
      export_line_list     : out rdp_export_type := rdp_export_init; 
      -- synthesis translate_on
      
      writePixel           : out std_logic := '0';
      writePixelX          : out unsigned(11 downto 0) := (others => '0');
      writePixelY          : out unsigned(11 downto 0) := (others => '0');
      writePixelColor      : out unsigned(31 downto 0) := (others => '0')
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
      
   signal sticky_r      : std_logic;  
   signal sticky_l      : std_logic;  
   signal xrsc_sticky   : unsigned(13 downto 0);
   signal xlsc_sticky   : unsigned(13 downto 0);   
   signal xrsc_under    : unsigned(14 downto 0);
   signal xlsc_under    : unsigned(14 downto 0);   
   signal xrsc          : unsigned(14 downto 0);
   signal xlsc          : unsigned(14 downto 0);
   signal curover_r     : std_logic;
   signal curover_l     : std_logic;
   signal curunder_r    : std_logic;
   signal curunder_l    : std_logic;  
   signal xright_cross  : unsigned(13 downto 0);
   signal xleft_cross   : unsigned(13 downto 0);   
   signal curcross      : std_logic;
   signal invaly        : std_logic;
   
   type t_majorminor is array(0 to 3) of unsigned(12 downto 0);
   signal majorx        : t_majorminor := (others => (others => '0'));
   signal minorx        : t_majorminor := (others => (others => '0'));
   signal invalidLine   : std_logic_vector(3 downto 0) := (others => '0');
   
   -- drawing
   type tlineInfo is record
      y       : unsigned(11 downto 0);
      xStart  : unsigned(11 downto 0); 
      xEnd    : unsigned(11 downto 0);
      unscrx  :   signed(12 downto 0);
   end record;
   signal lineInfo      : tlineInfo;
   signal startLine     : std_logic := '0';
   
   type tlineState is 
   (  
      LINEIDLE, 
      DRAWLINE
   ); 
   signal linestate  : tlineState := LINEIDLE;    
   
   signal posY       : unsigned(11 downto 0) := (others => '0');
   signal posX       : unsigned(11 downto 0) := (others => '0');
   signal endX       : unsigned(11 downto 0) := (others => '0');

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
         startLine  <= '0';
         
         if (reset = '1') then
            
            polystate <= POLYIDLE;
            
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
                        allunder       <= '0';
                        allinval       <= '0';
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
                        -- todo: line information for color/texture/z
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
                        if (linestate /= LINEIDLE) then
                           polystate      <= WAITLINE;
                        end if;
                     end if;
                
                  end if;
                  
                  if (unsigned(ycur(1 downto 0)) = 3) then
                     -- todo: increase color/texture/z
                  end if;
            
                  xleft  <= xleft + xleft_inc;
                  xright <= xright + xright_inc;
                  
                  if (ycur + 1 = settings_poly.YM) then
                     secondHalf <= '1';
                     xleft      <= settings_poly.XL(31 downto 1) & '0';
                  end if;
                  
               when WAITLINE =>
                  startLine <= '1';
                  if (linestate = LINEIDLE) then
                     polystate <= EVALLINE;
                  end if;
                  
               when POLYFINISH =>
                  if (linestate = LINEIDLE) then
                     polystate <= POLYIDLE;
                     poly_done <= '1'; 
                  end if;
            
            end case; -- polystate
            
         end if;
      end if;
   end process;
   
   -- drawing
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         writePixel <= '0';
         
         -- synthesis translate_off
         export_line_done  <= '0'; 
         -- synthesis translate_on
         
         if (reset = '1') then
            
            linestate <= LINEIDLE;
            
         else
            
            case (linestate) is
            
               when LINEIDLE =>
                  if (startLine = '1' and allinval = '0' and allover = '0' and allunder = '0') then
                     linestate <= DRAWLINE;
                     posY <= lineInfo.Y;
                     if (settings_poly.lft = '1') then
                        posX <= lineInfo.xStart;
                        endX <= lineInfo.xEnd;
                     else
                        posX <= lineInfo.xEnd;
                        endX <= lineInfo.xStart;
                     end if;
                     -- synthesis translate_off
                     export_line_done        <= '1'; 
                     export_line_list.y      <= resize(lineInfo.y, 16);
                     export_line_list.debug1 <= resize(lineInfo.xStart, 32);
                     export_line_list.debug2 <= resize(lineInfo.xEnd, 32);
                     export_line_list.debug3 <= resize(unsigned(lineInfo.unscrx), 32);
                     -- synthesis translate_on
                  end if;                  
               
               when DRAWLINE =>
                  if (settings_poly.lft = '1') then
                     posX <= posX + 1;
                  else
                     posX <= posX - 1;
                  end if;
                  if (posX = endX) then
                     linestate <= LINEIDLE;
                  end if;
                  
                  writePixel           <= '1';
                  writePixelX          <= posX;
                  writePixelY          <= posY;
                  writePixelColor      <= byteswap32(settings_fillcolor.color);
                 
                  if (settings_colorImage.FB_size = SIZE_16BIT) then
                     if (posX(0) = '0') then
                        writePixelColor(15 downto 0) <= byteswap16(settings_fillcolor.color(31 downto 16));
                     else
                        writePixelColor(15 downto 0) <= byteswap16(settings_fillcolor.color(15 downto 0)); 
                     end if;
                  end if;
                  
                  if (settings_otherModes.cycleType = "00") then -- HACK!
                     writePixelColor(15 downto 0) <= byteswap16(settings_blendcolor.blend_R(7 downto 3) & settings_blendcolor.blend_G(7 downto 3) & settings_blendcolor.blend_B(7 downto 3) & '0');
                  end if;
            
            end case; -- linestate
            
         end if;
      end if;
   end process;
   

end architecture;





