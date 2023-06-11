library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_command is
   port 
   (
      clk1x                : in  std_logic;
      reset                : in  std_logic;
            
      commandRAMReady      : in  std_logic;
      CommandData          : in  unsigned(63 downto 0);
      commandCntNext       : in  unsigned(4 downto 0) := (others => '0');
            
      commandRAMPtr        : out unsigned(4 downto 0) := (others => '0');
      commandIsIdle        : out std_logic;
      commandWordDone      : out std_logic := '0';
            
      poly_done            : in  std_logic;
      settings_poly        : out tsettings_poly := SETTINGSPOLYINIT;
      poly_start           : out std_logic := '0';
      
      -- synthesis translate_off
      export_command_done  : out std_logic := '0'; 
      -- synthesis translate_on
      
      settings_scissor     : out tsettings_scissor := SETTINGSSCISSORINIT;
      settings_otherModes  : out tsettings_otherModes;
      settings_fillcolor   : out tsettings_fillcolor;
      settings_blendcolor  : out tsettings_blendcolor;
      settings_combineMode : out tsettings_combineMode;
      settings_colorImage  : out tsettings_colorImage := (others => (others => '0'))
   );
end entity;

architecture arch of RDP_command is

   type tState is 
   (  
      IDLE, 
      READCOMMAND,
      EVALCOMMAND,
      EVALTRIANGLE,
      WAITRASTER
   ); 
   signal state  : tState := IDLE;

   -- EVALTRIANGLE
   signal triCnt  : unsigned(2 downto 0);
   signal shade   : std_logic;             
   signal texture : std_logic;             
   signal zbuffer : std_logic;             

begin 

   commandIsIdle <= '1' when (state = IDLE) else '0';

   -- synthesis translate_off
   export_command_done <=  '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"08" and commandCntNext - commandRAMPtr >= 3) else 
                           '1' when (state = EVALCOMMAND and (CommandData(61 downto 56) < 6x"08" or CommandData(61 downto 56) > 6x"08")) else 
                           '0';
   -- synthesis translate_on

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         commandWordDone <= '0';
         poly_start      <= '0';
      
         if (reset = '1') then
            
            state <= IDLE;
            
         else
            
            case (state) is
            
               when IDLE =>
                  if (commandRAMReady = '1') then
                     state         <= READCOMMAND;
                     commandRAMPtr <= (others => '0');
                  end if;                  
               
               when READCOMMAND =>
                  state          <= EVALCOMMAND;
                  commandRAMPtr  <= commandRAMPtr + 1;
                  
               when EVALCOMMAND =>
                  commandRAMPtr   <= commandRAMPtr + 1;
                  if (commandRAMPtr = commandCntNext) then
                     state <= IDLE;
                  end if;

                  case (CommandData(61 downto 56)) is
                  
                     when 6x"00" => -- NOP
                        commandWordDone <= '1';                         
                        
                     -- triangle commands
                     when 6x"08" =>
                        shade <= '0'; texture <= '0'; zbuffer <= '0'; 
                        if (commandCntNext - commandRAMPtr >= 3) then
                           commandWordDone <= '1';
                           state           <= EVALTRIANGLE;                           
                        else
                           state           <= IDLE;
                        end if;
                        triCnt                    <= (others => '0');
                        settings_poly.lft         <= CommandData(55);
                        settings_poly.maxLODlevel <= CommandData(53 downto 51);
                        settings_poly.tile        <= CommandData(50 downto 48);
                        settings_poly.YL          <= signed(CommandData(46 downto 32));
                        settings_poly.YM          <= signed(CommandData(30 downto 16));
                        settings_poly.YH          <= signed(CommandData(14 downto  0));
                        
                     when 6x"27" => -- sync pipe
                        commandWordDone <= '1';
                        -- todo
                  
                     when 6x"2D" => -- set scissor
                        commandWordDone <= '1';
                        settings_scissor.ScissorXL    <= CommandData(23 downto 12);
                        settings_scissor.ScissorXH    <= CommandData(55 downto 44);
                        settings_scissor.ScissorYL    <= CommandData(11 downto  0);
                        settings_scissor.ScissorYH    <= CommandData(43 downto 32);
                        settings_scissor.ScissorField <= CommandData(25);
                        settings_scissor.ScissorOdd   <= CommandData(24);
                  
                     when 6x"2F" => -- set other modes
                        commandWordDone <= '1';
                        settings_otherModes.alphaCompare    <= CommandData(0);
                        settings_otherModes.ditherAlpha     <= CommandData(1);
                        settings_otherModes.zSourceSel      <= CommandData(2);
                        settings_otherModes.AntiAlias       <= CommandData(3);
                        settings_otherModes.zCompare        <= CommandData(4);
                        settings_otherModes.zUpdate         <= CommandData(5);
                        settings_otherModes.imageRead       <= CommandData(6);
                        settings_otherModes.colorOnCvg      <= CommandData(7);
                        settings_otherModes.cvgDest         <= CommandData(9 downto 8);
                        settings_otherModes.zMode           <= CommandData(11 downto 10);
                        settings_otherModes.cvgTimesAlpha   <= CommandData(12);
                        settings_otherModes.alphaCvgSelect  <= CommandData(13);
                        settings_otherModes.forceBlend      <= CommandData(14);
                        settings_otherModes.blend_m2b1      <= CommandData(17 downto 16);
                        settings_otherModes.blend_m2b0      <= CommandData(19 downto 18);
                        settings_otherModes.blend_m2a1      <= CommandData(21 downto 20);
                        settings_otherModes.blend_m2a0      <= CommandData(23 downto 22);
                        settings_otherModes.blend_m1b1      <= CommandData(25 downto 24);
                        settings_otherModes.blend_m1b0      <= CommandData(27 downto 26);
                        settings_otherModes.blend_m1a1      <= CommandData(29 downto 28);
                        settings_otherModes.blend_m1a0      <= CommandData(31 downto 30);
                        settings_otherModes.alphaDitherSel  <= CommandData(37 downto 36);
                        settings_otherModes.rgbDitherSel    <= CommandData(39 downto 38);
                        settings_otherModes.key             <= CommandData(40);
                        settings_otherModes.convertOne      <= CommandData(41);
                        settings_otherModes.biLerp1         <= CommandData(42);
                        settings_otherModes.biLerp0         <= CommandData(43);
                        settings_otherModes.midTexel        <= CommandData(44);
                        settings_otherModes.sampleType      <= CommandData(45);
                        settings_otherModes.tlutType        <= CommandData(46);
                        settings_otherModes.enTlut          <= CommandData(47);
                        settings_otherModes.texLod          <= CommandData(48);
                        settings_otherModes.sharpenTex      <= CommandData(49);
                        settings_otherModes.detailTex       <= CommandData(50);
                        settings_otherModes.perspTex        <= CommandData(51);
                        settings_otherModes.cycleType       <= CommandData(53 downto 52);
                        settings_otherModes.atomicPrim      <= CommandData(55);
                     
                     when 6x"36" => -- fill rectangle
                        commandWordDone        <= '1';
                        poly_start             <= '1';
                        commandRAMPtr          <= commandRAMPtr;
                        state                  <= WAITRASTER;
                        settings_poly.lft      <= '1';
                        settings_poly.YL       <= "000" & signed(CommandData(43 downto 32));
                        settings_poly.YM       <= "000" & signed(CommandData(43 downto 32));
                        settings_poly.YH       <= "000" & signed(CommandData(11 downto  0));     
                        settings_poly.XL       <= 6x"0" & signed(CommandData(23 downto 12)) & 14x"0";
                        settings_poly.XH       <= 6x"0" & signed(CommandData(23 downto 12)) & 14x"0";
                        settings_poly.XM       <= 6x"0" & signed(CommandData(55 downto 44)) & 14x"0";
                        settings_poly.DXLDy    <= (others => '0');
                        settings_poly.DXHDy    <= (others => '0');
                        settings_poly.DXMDy    <= (others => '0');
                        if (settings_otherModes.cycleType >= 2) then
                           settings_poly.YL(1 downto 0) <= "11";
                           settings_poly.YM(1 downto 0) <= "11";
                        end if;
                        
                     when 6x"37" => -- set fill color
                        commandWordDone <= '1';
                        settings_fillcolor.color    <= CommandData(31 downto 0);                      
                        
                     when 6x"39" => -- set blend color
                        commandWordDone <= '1';
                        settings_blendcolor.blend_A  <= CommandData( 7 downto  0);                           
                        settings_blendcolor.blend_B  <= CommandData(15 downto  8);                           
                        settings_blendcolor.blend_G  <= CommandData(23 downto 16);                           
                        settings_blendcolor.blend_R  <= CommandData(31 downto 24);                           
                        
                     when 6x"3C" => -- set combine mode
                        commandWordDone <= '1';
                        settings_combineMode.combine_add_A_1      <= CommandData( 2 downto  0);                     
                        settings_combineMode.combine_sub_b_A_1    <= CommandData( 5 downto  3);                     
                        settings_combineMode.combine_add_R_1      <= CommandData( 8 downto  6);                     
                        settings_combineMode.combine_add_A_0      <= CommandData(11 downto  9);                     
                        settings_combineMode.combine_sub_b_A_0    <= CommandData(14 downto 12);                     
                        settings_combineMode.combine_add_R_0      <= CommandData(17 downto 15);                     
                        settings_combineMode.combine_mul_A_1      <= CommandData(20 downto 18);                     
                        settings_combineMode.combine_sub_a_A_1    <= CommandData(23 downto 21);                     
                        settings_combineMode.combine_sub_b_R_1    <= CommandData(27 downto 24);                     
                        settings_combineMode.combine_sub_b_R_0    <= CommandData(31 downto 28);                     
                        settings_combineMode.combine_mul_R_1      <= CommandData(36 downto 32);                     
                        settings_combineMode.combine_sub_a_R_1    <= CommandData(40 downto 37);                     
                        settings_combineMode.combine_mul_A_0      <= CommandData(43 downto 41);                     
                        settings_combineMode.combine_sub_a_A_0    <= CommandData(46 downto 44);                     
                        settings_combineMode.combine_mul_R_0      <= CommandData(51 downto 47);                     
                        settings_combineMode.combine_sub_a_R_0    <= CommandData(55 downto 52);                     
                        
                     when 6x"3F" => -- set color image
                        commandWordDone <= '1';
                        settings_colorImage.FB_base      <= CommandData(24 downto 0);
                        settings_colorImage.FB_width_m1  <= CommandData(45 downto 32);
                        settings_colorImage.FB_size      <= CommandData(52 downto 51);
                        settings_colorImage.FB_format    <= CommandData(55 downto 53);
                     
                     when others => 
                        commandWordDone <= '1';
                        -- synthesis translate_off
                        report to_hstring(CommandData(61 downto 56));
                        -- synthesis translate_on
                        report "Unknown RDP command" severity warning; 
                  
                  end case; -- command
            
               when EVALTRIANGLE =>
                  commandRAMPtr   <= commandRAMPtr + 1;
                  commandWordDone <= '1';
                  triCnt <= triCnt + 1;
                  case (to_integer(triCnt)) is
                     when 0 =>
                        settings_poly.XL       <= signed(CommandData(63 downto 32));
                        settings_poly.DXLDy    <= signed(CommandData(29 downto  0));
                     when 1 =>
                        settings_poly.XH       <= signed(CommandData(63 downto 32));
                        settings_poly.DXHDy    <= signed(CommandData(29 downto  0));
                     when 2 =>
                        settings_poly.XM       <= signed(CommandData(63 downto 32));
                        settings_poly.DXMDy    <= signed(CommandData(29 downto  0));
                        state                  <= WAITRASTER;
                        commandRAMPtr          <= commandRAMPtr;
                        poly_start             <= '1';
                        
                     when others => null;
                  end case;
                  
               when WAITRASTER =>
                  if (poly_done = '1') then
                     if (commandRAMPtr = commandCntNext) then
                        state <= IDLE;
                     else
                        state         <= EVALCOMMAND;
                        commandRAMPtr <= commandRAMPtr + 1;
                     end if;
                  end if;
            
            end case; -- state
            
         end if;
      end if;
   end process;

end architecture;





