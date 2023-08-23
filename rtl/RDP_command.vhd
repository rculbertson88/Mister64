library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pRDP.all;

entity RDP_command is
   port 
   (
      clk1x                   : in  std_logic;
      reset                   : in  std_logic;
         
      error                   : out std_logic := '0';
               
      commandRAMReady         : in  std_logic;
      CommandData             : in  unsigned(63 downto 0);
      commandCntNext          : in  unsigned(4 downto 0) := (others => '0');
               
      commandRAMPtr_out       : out unsigned(4 downto 0) := (others => '0');
      commandIsIdle           : out std_logic;
      commandWordDone         : out std_logic := '0';
      commandAbort            : out std_logic := '0';
               
      poly_done               : in  std_logic;
      settings_poly           : out tsettings_poly := SETTINGSPOLYINIT;
      poly_start              : out std_logic := '0';
      poly_loading_mode       : out std_logic := '0';
      sync_full               : out std_logic := '0';  
      
      -- synthesis translate_off
      export_command_done     : out std_logic := '0'; 
      -- synthesis translate_on
      
      settings_scissor        : out tsettings_scissor := SETTINGSSCISSORINIT;
      settings_Z              : out tsettings_Z := (others => (others => '0'));
      settings_otherModes     : out tsettings_otherModes := SETTINGSOTHERMODESINIT;
      settings_fillcolor      : out tsettings_fillcolor := (others => (others => '0'));
      settings_fogcolor       : out tsettings_fogcolor := (others => (others => '0'));
      settings_blendcolor     : out tsettings_blendcolor := (others => (others => '0'));
      settings_primcolor      : out tsettings_primcolor := (others => (others => '0'));
      settings_envcolor       : out tsettings_envcolor := (others => (others => '0'));
      settings_combineMode    : out tsettings_combineMode := (others => (others => '0'));
      settings_textureImage   : out tsettings_textureImage := (others => (others => '0'));
      settings_Z_base         : out unsigned(24 downto 0) := (others => '0');
      settings_colorImage     : out tsettings_colorImage := (others => (others => '0'));
      settings_tile           : out tsettings_tile;
      settings_loadtype       : out tsettings_loadtype
   );
end entity;

architecture arch of RDP_command is

   type tState is 
   (  
      IDLE, 
      READCOMMAND,
      EVALCOMMAND,
      EVALTEXRECTANGLE,
      EVALTEXRECTANGLEFLIP,
      EVALTRIANGLE,
      EVALSHADE,
      EVALTEXTURE,
      EVALZBUFFER,
      WAITRASTER
   ); 
   signal state  : tState := IDLE;
   
   signal commandRAMPtr    : unsigned(4 downto 0) := (others => '0');
   signal commandAvailable : integer range -31 to 31;

   -- EVALTRIANGLE
   signal triCnt  : unsigned(2 downto 0);
   signal shade   : std_logic;             
   signal texture : std_logic;             
   signal zbuffer : std_logic;     

   -- tile settings
   signal tile_RdAddr : std_logic_vector(2 downto 0) := (others => '0');
   
   signal tileSettings_WrAddr : std_logic_vector(2 downto 0) := (others => '0');
   signal tileSettings_WrData : std_logic_vector(46 downto 0) := (others => '0');
   signal tileSettings_we     : std_logic := '0';
   signal tileSettings_RdData : std_logic_vector(46 downto 0) := (others => '0');  

   -- tile size
   signal tileSize_WrAddr     : std_logic_vector(2 downto 0) := (others => '0');
   signal tileSize_WrData     : std_logic_vector(47 downto 0) := (others => '0');
   signal tileSize_we         : std_logic := '0';
   signal tileSize_RdData     : std_logic_vector(47 downto 0) := (others => '0');

begin 

   commandIsIdle <= '1' when (state = IDLE) else '0';

   commandRAMPtr_out <= commandRAMPtr;

   commandAvailable <= to_integer(commandCntNext) - to_integer(commandRAMPtr);

   -- synthesis translate_off
   export_command_done <=  '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"08" and commandAvailable >=  3) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"09" and commandAvailable >=  5) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"0A" and commandAvailable >= 11) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"0B" and commandAvailable >= 13) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"0C" and commandAvailable >= 11) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"0D" and commandAvailable >= 13) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"0E" and commandAvailable >= 19) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"0F" and commandAvailable >= 21) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"24" and commandAvailable >= 1) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) = 6x"25" and commandAvailable >= 1) else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) < 6x"08") else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) > 6x"0F" and CommandData(61 downto 56) < 6x"24") else 
                           '1' when (state = EVALCOMMAND and CommandData(61 downto 56) > 6x"25") else 
                           '0';
   -- synthesis translate_on
   
   itileSettings : entity mem.RamMLAB
	GENERIC MAP 
   (
      width      => 47, -- 56 - 1 - 8 = 47
      widthad    => 3
	)
	PORT MAP (
      inclock    => clk1x,
      wren       => tileSettings_we,
      data       => tileSettings_WrData,
      wraddress  => tileSettings_WrAddr,
      rdaddress  => tile_RdAddr,
      q          => tileSettings_RdData
	);
   
   itileSize : entity mem.RamMLAB
	GENERIC MAP 
   (
      width      => 48, -- 56 - 8 = 48
      widthad    => 3
	)
	PORT MAP (
      inclock    => clk1x,
      wren       => tileSize_we,
      data       => tileSize_WrData,
      wraddress  => tileSize_WrAddr,
      rdaddress  => tile_RdAddr,
      q          => tileSize_RdData
	);
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         error           <= '0';
         commandWordDone <= '0';
         commandAbort    <= '0';
         poly_start      <= '0';
         sync_full       <= '0';
         tileSettings_we <= '0';
         tileSize_we     <= '0';
         
         settings_tile.Tile_sl <= unsigned(tileSize_RdData(47 downto 36));
         settings_tile.Tile_tl <= unsigned(tileSize_RdData(35 downto 24));
         settings_tile.Tile_sh <= unsigned(tileSize_RdData(23 downto 12));
         settings_tile.Tile_th <= unsigned(tileSize_RdData(11 downto  0));
      
         settings_tile.Tile_format   <= unsigned(tileSettings_RdData(46 downto 44));
         settings_tile.Tile_size     <= unsigned(tileSettings_RdData(43 downto 42));
         settings_tile.Tile_line     <= unsigned(tileSettings_RdData(41 downto 33));
         settings_tile.Tile_TmemAddr <= unsigned(tileSettings_RdData(32 downto 24));
         settings_tile.Tile_palette  <= unsigned(tileSettings_RdData(23 downto 20));
         settings_tile.Tile_clampT   <= tileSettings_RdData(19);
         settings_tile.Tile_mirrorT  <= tileSettings_RdData(18);
         settings_tile.Tile_maskT    <= unsigned(tileSettings_RdData(17 downto 14));
         settings_tile.Tile_shiftT   <= unsigned(tileSettings_RdData(13 downto 10));
         settings_tile.Tile_clampS   <= tileSettings_RdData(9);
         settings_tile.Tile_mirrorS  <= tileSettings_RdData(8);
         settings_tile.Tile_maskS    <= unsigned(tileSettings_RdData( 7 downto  4));
         settings_tile.Tile_shiftS   <= unsigned(tileSettings_RdData( 3 downto  0));
      
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
                  
                  settings_poly  <= SETTINGSPOLYINIT;

                  case (CommandData(61 downto 56)) is
                  
                     when 6x"00" => -- NOP
                        commandWordDone <= '1';                         
                        
                     -- triangle commands
                     when 6x"08" | 6x"09" | 6x"0A" | 6x"0B" | 6x"0C" | 6x"0D" | 6x"0E" | 6x"0F" =>
                        shade          <= CommandData(58); 
                        texture        <= CommandData(57); 
                        zbuffer        <= CommandData(56); 
                        tile_RdAddr    <= std_logic_vector(CommandData(50 downto 48));
                        state          <= IDLE;
                        if (commandRAMPtr = 1) then
                           commandAbort   <= '1';
                        end if;
                        if (CommandData(61 downto 56) = 6x"08" and commandAvailable >=  3) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        if (CommandData(61 downto 56) = 6x"09" and commandAvailable >=  5) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        if (CommandData(61 downto 56) = 6x"0A" and commandAvailable >= 11) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        if (CommandData(61 downto 56) = 6x"0B" and commandAvailable >= 13) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        if (CommandData(61 downto 56) = 6x"0C" and commandAvailable >= 11) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        if (CommandData(61 downto 56) = 6x"0D" and commandAvailable >= 13) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        if (CommandData(61 downto 56) = 6x"0E" and commandAvailable >= 19) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        if (CommandData(61 downto 56) = 6x"0F" and commandAvailable >= 21) then commandWordDone <= '1'; state <= EVALTRIANGLE; commandAbort <= '0'; end if;
                        triCnt                    <= (others => '0');
                        settings_poly.lft         <= CommandData(55);
                        settings_poly.maxLODlevel <= CommandData(53 downto 51);
                        settings_poly.tile        <= CommandData(50 downto 48);
                        settings_poly.YL          <= signed(CommandData(46 downto 32));
                        settings_poly.YM          <= signed(CommandData(30 downto 16));
                        settings_poly.YH          <= signed(CommandData(14 downto  0));
                        
                     when 6x"24" | 6x"25" => -- texture rectangle
                        if (commandAvailable >= 1) then
                           commandWordDone <= '1';
                           state           <= EVALTEXRECTANGLE;  
                           if (CommandData(56) = '1') then
                              state        <= EVALTEXRECTANGLEFLIP; 
                           end if;
                        else
                           state           <= IDLE;
                           if (commandRAMPtr = 1) then
                              commandAbort   <= '1';
                           end if;
                        end if;
                     
                        tile_RdAddr            <= std_logic_vector(CommandData(26 downto 24));
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
                        
                     when 6x"26" => -- sync load
                        commandWordDone <= '1';
                        -- todo   
                        
                     when 6x"27" => -- sync pipe
                        commandWordDone <= '1';
                        -- todo                       
                        
                     when 6x"28" => -- sync tile
                        commandWordDone <= '1';
                        -- todo                     
                        
                     when 6x"29" => -- sync full
                        commandWordDone <= '1';
                        sync_full       <= '1';
                        -- todo
                  
                     when 6x"2D" => -- set scissor
                        commandWordDone <= '1';
                        settings_scissor.ScissorXL    <= CommandData(23 downto 12);
                        settings_scissor.ScissorXH    <= CommandData(55 downto 44);
                        settings_scissor.ScissorYL    <= CommandData(11 downto  0);
                        settings_scissor.ScissorYH    <= CommandData(43 downto 32);
                        settings_scissor.ScissorField <= CommandData(25);
                        settings_scissor.ScissorOdd   <= CommandData(24);
                        
                     when 6x"2E" => -- set primitive depth
                        commandWordDone <= '1';
                        settings_Z.Delta_Z        <= CommandData(15 downto 0);
                        settings_Z.Primitive_Z    <= CommandData(30 downto 16);
                  
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
                     
                     when 6x"30" | 6x"34" => -- load tlut and load tile
                        commandWordDone        <= '1';  
                        poly_start             <= '1';
                        poly_loading_mode      <= '1';
                        state                  <= WAITRASTER;   
                        commandRAMPtr          <= commandRAMPtr;                        
                        tile_RdAddr            <= std_logic_vector(CommandData(26 downto 24));
                        tileSize_WrAddr        <= std_logic_vector(CommandData(26 downto 24));
                        tileSize_WrData        <= std_logic_vector(CommandData(55 downto 32)) & std_logic_vector(CommandData(23 downto 0));
                        tileSize_we            <= '1'; 
                        if (CommandData(61 downto 56) = 6x"30") then
                           settings_loadtype   <= LOADTYPE_TLUT;
                        else                   
                           settings_loadtype   <= LOADTYPE_TILE;
                        end if;
                        settings_poly.lft             <= '1';
                        settings_poly.YL              <= "000" & signed(CommandData(11 downto 2)) & "11";
                        settings_poly.YM              <= "000" & signed(CommandData(11 downto 2)) & "11";
                        settings_poly.YH              <= "000" & signed(CommandData(43 downto 32));
                        settings_poly.XL              <= 6x"0" & signed(CommandData(23 downto 14)) & 16x"0";
                        settings_poly.XH              <= 6x"0" & signed(CommandData(55 downto 46)) & 16x"0";
                        settings_poly.XM              <= 6x"0" & signed(CommandData(23 downto 14)) & 16x"0";
                        settings_poly.DXLDy           <= (others => '0');
                        settings_poly.DXHDy           <= (others => '0');
                        settings_poly.DXMDy           <= (others => '0');
                        settings_poly.tex_Texture_S   <= '0' & signed(CommandData(55 downto 44)) & 19x"0";
                        settings_poly.tex_Texture_T   <= '0' & signed(CommandData(43 downto 32)) & 19x"0";
                        case (settings_textureImage.tex_size) is
                           when SIZE_4BIT  => settings_poly.tex_DsDx  <= x"02000000";
                           when SIZE_8BIT  => settings_poly.tex_DsDx  <= x"01000000";
                           when SIZE_16BIT => settings_poly.tex_DsDx  <= x"00800000";
                           when SIZE_32BIT => settings_poly.tex_DsDx  <= x"00400000";
                           when others => null;
                        end case;
                        settings_poly.tex_DtDx        <= (others => '0');     
                        settings_poly.tex_DsDe        <= (others => '0');
                        settings_poly.tex_DtDe        <= x"00200000";   
                        settings_poly.tex_DsDy        <= (others => '0');
                        settings_poly.tex_DtDy        <= x"00200000";
                        
                     when 6x"32" => -- set tile size
                        commandWordDone        <= '1';        
                        tileSize_WrAddr        <= std_logic_vector(CommandData(26 downto 24));
                        tileSize_WrData        <= std_logic_vector(CommandData(55 downto 32)) & std_logic_vector(CommandData(23 downto 0));
                        tileSize_we            <= '1'; 
                     
                     when 6x"33" => -- load block
                        commandWordDone        <= '1';  
                        poly_start             <= '1';
                        poly_loading_mode      <= '1';
                        state                  <= WAITRASTER;   
                        commandRAMPtr          <= commandRAMPtr;                        
                        tile_RdAddr            <= std_logic_vector(CommandData(26 downto 24));
                        tileSize_WrAddr        <= std_logic_vector(CommandData(26 downto 24));
                        tileSize_WrData        <= std_logic_vector(CommandData(55 downto 32)) & std_logic_vector(CommandData(23 downto 0));
                        tileSize_we            <= '1'; 
                        settings_loadtype      <= LOADTYPE_BLOCK;
                        settings_poly.lft             <= '1';
                        settings_poly.YL              <= "000" & signed(CommandData(41 downto 32)) & "11";
                        settings_poly.YM              <= "000" & signed(CommandData(41 downto 32)) & "11";
                        settings_poly.YH              <= "000" & signed(CommandData(41 downto 32)) & "00";
                        settings_poly.XL              <= 4x"0" & signed(CommandData(23 downto 12)) & 16x"0";
                        settings_poly.XH              <= 4x"0" & signed(CommandData(55 downto 44)) & 16x"0";
                        settings_poly.XM              <= 4x"0" & signed(CommandData(23 downto 12)) & 16x"0";
                        settings_poly.DXLDy           <= (others => '0');
                        settings_poly.DXHDy           <= (others => '0');
                        settings_poly.DXMDy           <= (others => '0');
                        settings_poly.tex_Texture_S   <= '0' & signed(CommandData(55 downto 44)) & 19x"0";
                        settings_poly.tex_Texture_T   <= '0' & signed(CommandData(43 downto 32)) & 19x"0";
                        case (settings_textureImage.tex_size) is
                           when SIZE_4BIT  => settings_poly.tex_DsDx  <= x"0080000" & signed(CommandData(11 downto 8));
                           when SIZE_8BIT  => settings_poly.tex_DsDx  <= x"0040000" & signed(CommandData(11 downto 8));
                           when SIZE_16BIT => settings_poly.tex_DsDx  <= x"0020000" & signed(CommandData(11 downto 8));
                           when SIZE_32BIT => settings_poly.tex_DsDx  <= x"0010000" & signed(CommandData(11 downto 8));
                           when others => null;
                        end case;
                        settings_poly.tex_DtDx        <= x"000" & signed(CommandData(11 downto 0)) & x"00";     
                        settings_poly.tex_DsDe        <= (others => '0');
                        settings_poly.tex_DtDe        <= x"00200000";   
                        settings_poly.tex_DsDy        <= (others => '0');
                        settings_poly.tex_DtDy        <= x"00200000";
                     
                     when 6x"35" => -- set tile
                        commandWordDone        <= '1';        
                        tileSettings_WrAddr    <= std_logic_vector(CommandData(26 downto 24));
                        tileSettings_WrData    <= std_logic_vector(CommandData(55 downto 51)) & std_logic_vector(CommandData(49 downto 32)) & std_logic_vector(CommandData(23 downto 0));
                        tileSettings_we        <= '1';                          
                        
                     when 6x"36" => -- fill rectangle
                        commandWordDone            <= '1';
                        poly_start                 <= '1';
                        poly_loading_mode          <= '0';
                        commandRAMPtr              <= commandRAMPtr;
                        state                      <= WAITRASTER;
                        tile_RdAddr                <= (others => '0');
                        settings_poly.lft          <= '1';
                        settings_poly.maxLODlevel  <= (others => '0');
                        settings_poly.YL           <= "000" & signed(CommandData(43 downto 32));
                        settings_poly.YM           <= "000" & signed(CommandData(43 downto 32));
                        settings_poly.YH           <= "000" & signed(CommandData(11 downto  0));     
                        settings_poly.XL           <= 6x"0" & signed(CommandData(23 downto 12)) & 14x"0";
                        settings_poly.XH           <= 6x"0" & signed(CommandData(23 downto 12)) & 14x"0";
                        settings_poly.XM           <= 6x"0" & signed(CommandData(55 downto 44)) & 14x"0";
                        settings_poly.DXLDy        <= (others => '0');
                        settings_poly.DXHDy        <= (others => '0');
                        settings_poly.DXMDy        <= (others => '0');
                        if (settings_otherModes.cycleType >= 2) then
                           settings_poly.YL(1 downto 0) <= "11";
                           settings_poly.YM(1 downto 0) <= "11";
                        end if;
                        
                     when 6x"37" => -- set fill color
                        commandWordDone <= '1';
                        settings_fillcolor.color    <= CommandData(31 downto 0);                      
                        
                     when 6x"38" => -- set fog color
                        commandWordDone <= '1';
                        settings_fogcolor.fog_A  <= CommandData( 7 downto  0);
                        settings_fogcolor.fog_B  <= CommandData(15 downto  8);
                        settings_fogcolor.fog_G  <= CommandData(23 downto 16);
                        settings_fogcolor.fog_R  <= CommandData(31 downto 24);
                        
                     when 6x"39" => -- set blend color
                        commandWordDone <= '1';
                        settings_blendcolor.blend_A  <= CommandData( 7 downto  0);
                        settings_blendcolor.blend_B  <= CommandData(15 downto  8);
                        settings_blendcolor.blend_G  <= CommandData(23 downto 16);
                        settings_blendcolor.blend_R  <= CommandData(31 downto 24);
                        
                     when 6x"3A" => -- set prim color
                        commandWordDone <= '1';
                        settings_primcolor.prim_A          <= CommandData( 7 downto  0);
                        settings_primcolor.prim_B          <= CommandData(15 downto  8);
                        settings_primcolor.prim_G          <= CommandData(23 downto 16);
                        settings_primcolor.prim_R          <= CommandData(31 downto 24);
                        settings_primcolor.prim_levelFrac  <= CommandData(39 downto 32);
                        settings_primcolor.prim_minLevel   <= CommandData(44 downto 40);
                        
                     when 6x"3B" => -- set environment color
                        commandWordDone <= '1';
                        settings_envcolor.env_A  <= CommandData( 7 downto  0);
                        settings_envcolor.env_B  <= CommandData(15 downto  8);
                        settings_envcolor.env_G  <= CommandData(23 downto 16);
                        settings_envcolor.env_R  <= CommandData(31 downto 24);
                        
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
                        
                     when 6x"3D" => -- set texture image
                        commandWordDone <= '1';
                        settings_textureImage.tex_base      <= CommandData(24 downto 0);
                        settings_textureImage.tex_width_m1  <= CommandData(41 downto 32);
                        settings_textureImage.tex_size      <= CommandData(52 downto 51);
                        settings_textureImage.tex_format    <= CommandData(55 downto 53);
                        
                     when 6x"3E" => -- set Z image
                        commandWordDone <= '1';
                        settings_Z_base <= CommandData(24 downto 0);
                        
                     when 6x"3F" => -- set color image
                        commandWordDone <= '1';
                        settings_colorImage.FB_base      <= CommandData(24 downto 0);
                        settings_colorImage.FB_width_m1  <= CommandData(41 downto 32);
                        settings_colorImage.FB_size      <= CommandData(52 downto 51);
                        settings_colorImage.FB_format    <= CommandData(55 downto 53);
                     
                     when others => 
                        error <= '1';
                        commandWordDone <= '1';
                        -- synthesis translate_off
                        report to_hstring(CommandData(61 downto 56));
                        -- synthesis translate_on
                        report "Unknown RDP command" severity warning; 
                  
                  end case; -- command
                  
               when EVALTEXRECTANGLE | EVALTEXRECTANGLEFLIP =>
                  commandRAMPtr          <= commandRAMPtr + 1;
                  commandWordDone        <= '1';
                  state                  <= WAITRASTER;
                  commandRAMPtr          <= commandRAMPtr;
                  poly_start             <= '1';
                  poly_loading_mode      <= '0';
                  
                  settings_poly.tex_Texture_S   <= signed(CommandData(63 downto 48)) & 16x"0";
                  settings_poly.tex_Texture_T   <= signed(CommandData(47 downto 32)) & 16x"0";

                  if (state = EVALTEXRECTANGLE) then
                     settings_poly.tex_DsDx <= resize(signed(CommandData(31 downto 16)), 21) & 11x"0";
                     settings_poly.tex_DtDe <= resize(signed(CommandData(15 downto  0)), 21) & 11x"0";
                     settings_poly.tex_DtDy <= resize(signed(CommandData(15 downto  0)), 21) & 11x"0";
                  else
                     settings_poly.tex_DtDx <= resize(signed(CommandData(15 downto  0)), 21) & 11x"0";
                     settings_poly.tex_DsDe <= resize(signed(CommandData(31 downto 16)), 21) & 11x"0";
                     settings_poly.tex_DsDy <= resize(signed(CommandData(31 downto 16)), 21) & 11x"0";
                  end if;   
            
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
                        if (shade = '1') then 
                           state  <= EVALSHADE;
                           triCnt <= (others => '0');
                        elsif (texture = '1') then
                           state  <= EVALTEXTURE;
                           triCnt <= (others => '0');
                        elsif (zbuffer = '1') then
                           state  <= EVALZBUFFER;
                           triCnt <= (others => '0');
                        else
                           state                  <= WAITRASTER;
                           commandRAMPtr          <= commandRAMPtr;
                           poly_start             <= '1';
                           poly_loading_mode      <= '0';
                        end if;
                        
                     when others => null;
                  end case;
                  
               when EVALSHADE =>
                  commandRAMPtr   <= commandRAMPtr + 1;
                  commandWordDone <= '1';
                  triCnt <= triCnt + 1;
                  case (to_integer(triCnt)) is
                     when 0 =>
                        settings_poly.shade_Color_R(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_Color_G(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_Color_B(31 downto 16) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_Color_A(31 downto 16) <= signed(CommandData(15 downto  0));
                     when 1 =>
                        settings_poly.shade_DrDx(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_DgDx(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_DbDx(31 downto 16) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_DaDx(31 downto 16) <= signed(CommandData(15 downto  0));                   
                     when 2 =>
                        settings_poly.shade_Color_R(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_Color_G(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_Color_B(15 downto 0) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_Color_A(15 downto 0) <= signed(CommandData(15 downto  0));                     
                     when 3 =>
                        settings_poly.shade_DrDx(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_DgDx(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_DbDx(15 downto 0) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_DaDx(15 downto 0) <= signed(CommandData(15 downto  0));
                     when 4 =>
                        settings_poly.shade_DrDe(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_DgDe(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_DbDe(31 downto 16) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_DaDe(31 downto 16) <= signed(CommandData(15 downto  0));
                     when 5 =>
                        settings_poly.shade_DrDy(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_DgDy(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_DbDy(31 downto 16) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_DaDy(31 downto 16) <= signed(CommandData(15 downto  0));                   
                     when 6 =>
                        settings_poly.shade_DrDe(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_DgDe(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_DbDe(15 downto 0) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_DaDe(15 downto 0) <= signed(CommandData(15 downto  0));                     
                     when 7 =>
                        settings_poly.shade_DrDy(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.shade_DgDy(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.shade_DbDy(15 downto 0) <= signed(CommandData(31 downto 16));
                        settings_poly.shade_DaDy(15 downto 0) <= signed(CommandData(15 downto  0));
                        if (texture = '1') then
                           state  <= EVALTEXTURE;
                           triCnt <= (others => '0');
                        elsif (zbuffer = '1') then
                           state  <= EVALZBUFFER;
                           triCnt <= (others => '0');
                        else
                           state                  <= WAITRASTER;
                           commandRAMPtr          <= commandRAMPtr;
                           poly_start             <= '1';
                           poly_loading_mode      <= '0';
                        end if;
                        
                     when others => null;
                  end case;
               
               when EVALTEXTURE =>
                  commandRAMPtr   <= commandRAMPtr + 1;
                  commandWordDone <= '1';
                  triCnt <= triCnt + 1;
                  case (to_integer(triCnt)) is
                     when 0 =>
                        settings_poly.tex_Texture_S(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_Texture_T(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_Texture_W(31 downto 16) <= signed(CommandData(31 downto 16));
                     when 1 =>
                        settings_poly.tex_DsDx(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_DtDx(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_DwDx(31 downto 16) <= signed(CommandData(31 downto 16));                   
                     when 2 =>
                        settings_poly.tex_Texture_S(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_Texture_T(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_Texture_W(15 downto 0) <= signed(CommandData(31 downto 16));                   
                     when 3 =>
                        settings_poly.tex_DsDx(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_DtDx(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_DwDx(15 downto 0) <= signed(CommandData(31 downto 16));
                     when 4 =>
                        settings_poly.tex_DsDe(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_DtDe(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_DwDe(31 downto 16) <= signed(CommandData(31 downto 16));
                     when 5 =>
                        settings_poly.tex_DsDy(31 downto 16) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_DtDy(31 downto 16) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_DwDy(31 downto 16) <= signed(CommandData(31 downto 16));                  
                     when 6 =>
                        settings_poly.tex_DsDe(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_DtDe(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_DwDe(15 downto 0) <= signed(CommandData(31 downto 16));                   
                     when 7 =>
                        settings_poly.tex_DsDy(15 downto 0) <= signed(CommandData(63 downto 48));
                        settings_poly.tex_DtDy(15 downto 0) <= signed(CommandData(47 downto 32));
                        settings_poly.tex_DwDy(15 downto 0) <= signed(CommandData(31 downto 16));
                        if (zbuffer = '1') then
                           state  <= EVALZBUFFER;
                           triCnt <= (others => '0');
                        else
                           state                  <= WAITRASTER;
                           commandRAMPtr          <= commandRAMPtr;
                           poly_start             <= '1';
                           poly_loading_mode      <= '0';
                        end if;
                        
                     when others => null;
                  end case;

               when EVALZBUFFER =>
                  commandRAMPtr   <= commandRAMPtr + 1;
                  commandWordDone <= '1';
                  triCnt <= triCnt + 1;
                  case (to_integer(triCnt)) is
                     when 0 =>
                        settings_poly.zBuffer_Z    <= signed(CommandData(63 downto 32));
                        settings_poly.zBuffer_DzDx <= signed(CommandData(31 downto  0));
                     when 1 =>
                        settings_poly.zBuffer_DzDe <= signed(CommandData(63 downto 32));
                        settings_poly.zBuffer_DzDy <= signed(CommandData(31 downto  0));                     
                        state                  <= WAITRASTER;
                        commandRAMPtr          <= commandRAMPtr;
                        poly_start             <= '1';
                        poly_loading_mode      <= '0';
                        
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





