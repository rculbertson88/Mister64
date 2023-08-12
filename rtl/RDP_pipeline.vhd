library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;
use work.pFunctions.all;

entity RDP_pipeline is
   port 
   (
      clk1x                   : in  std_logic;
      reset                   : in  std_logic;
      
      errorCombine            : out std_logic;
      
      pipe_busy               : out std_logic;
   
      settings_poly           : in  tsettings_poly;
      settings_otherModes     : in  tsettings_otherModes;
      settings_blendcolor     : in  tsettings_blendcolor;
      settings_colorImage     : in  tsettings_colorImage;
      settings_textureImage   : in  tsettings_textureImage;
      settings_tile           : in  tsettings_tile;
      settings_combineMode    : in  tsettings_combineMode;
     
      pipeIn_trigger          : in  std_logic;
      pipeIn_valid            : in  std_logic;
      pipeIn_Addr             : in  unsigned(25 downto 0);
      pipeIn_xIndex           : in  unsigned(11 downto 0);
      pipeIn_X                : in  unsigned(11 downto 0);
      pipeIn_Y                : in  unsigned(11 downto 0);
      pipeIn_cvgValue         : in  unsigned(7 downto 0);
      pipeIn_offX             : in  unsigned(1 downto 0);
      pipeIn_offY             : in  unsigned(1 downto 0);
      pipeInColor             : in  tcolor4_s16;
      pipeIn_S                : in  signed(15 downto 0);
      pipeIn_T                : in  signed(15 downto 0);
      
      TextureAddr             : out unsigned(11 downto 0);
      TextureRamData          : in  tTextureRamData;
      
      FBAddr                  : out unsigned(10 downto 0);
      FBData                  : in  std_logic_vector(31 downto 0);
     
      -- synthesis translate_off
      pipeIn_cvg16            : in  unsigned(15 downto 0);
      pipeInColorFull         : in  tcolor4_s32;
      pipeInSTWZ              : in  tcolor4_s32;
      
      export_pipeDone         : out std_logic := '0';       
      export_pipeO            : out rdp_export_type := (others => (others => '0'));
      export_Color            : out rdp_export_type := (others => (others => '0'));
      export_LOD              : out rdp_export_type := (others => (others => '0'));
      export_TexCoord         : out rdp_export_type := (others => (others => '0'));
      export_TexFetch         : out rdp_export_type := (others => (others => '0'));
      export_TexColor         : out rdp_export_type := (others => (others => '0'));
      export_Comb             : out rdp_export_type := (others => (others => '0'));
      export_FBMem            : out rdp_export_type := (others => (others => '0'));
      -- synthesis translate_on
      
      writePixel              : out std_logic := '0';
      writePixelAddr          : out unsigned(25 downto 0);
      writePixelX             : out unsigned(11 downto 0) := (others => '0');
      writePixelY             : out unsigned(11 downto 0) := (others => '0');
      writePixelColor         : out tcolor3_u8 := (others => (others => '0'));
      writePixelCvg           : out unsigned(2 downto 0)
   );
end entity;

architecture arch of RDP_pipeline is

   constant STAGE_INPUT     : integer := 0;
   constant STAGE_COMBINER  : integer := 1;
   constant STAGE_BLENDER   : integer := 2;
   constant STAGE_OUTPUT    : integer := 3;
   
   type t_stage_u32 is array(0 to STAGE_OUTPUT - 1) of unsigned(31 downto 0);
   type t_stage_u26 is array(0 to STAGE_OUTPUT - 1) of unsigned(25 downto 0);
   type t_stage_u16 is array(0 to STAGE_OUTPUT - 1) of unsigned(15 downto 0);
   type t_stage_u12 is array(0 to STAGE_OUTPUT - 1) of unsigned(11 downto 0);
   type t_stage_u10 is array(0 to STAGE_OUTPUT - 1) of unsigned(9 downto 0);
   type t_stage_u8 is array(0 to STAGE_OUTPUT - 1) of unsigned(7 downto 0);
   type t_stage_u4 is array(0 to STAGE_OUTPUT - 1) of unsigned(3 downto 0);
   type t_stage_u3 is array(0 to STAGE_OUTPUT - 1) of unsigned(2 downto 0);
   type t_stage_u2 is array(0 to STAGE_OUTPUT - 1) of unsigned(1 downto 0);
   type t_stage_s16 is array(0 to STAGE_OUTPUT - 1) of signed(15 downto 0);
   type t_stage_c32s is array(0 to STAGE_OUTPUT - 1) of tcolor4_s32;
   type t_stage_c16s is array(0 to STAGE_OUTPUT - 1) of tcolor4_s16;
   type t_stage_c8u is array(0 to STAGE_OUTPUT - 1) of tcolor4_u8;
   
   -- stage register
   signal stage_valid      : unsigned(0 to STAGE_OUTPUT - 1);
   signal stage_addr       : t_stage_u26;
   signal stage_x          : t_stage_u12;
   signal stage_y          : t_stage_u12;
   signal stage_cvgValue   : t_stage_u8;
   signal stage_offX       : t_stage_u2;
   signal stage_offY       : t_stage_u2;
   signal stage_cvgCount   : t_stage_u4;
   signal stage_Color      : t_stage_c16s := (others => (others => (others => '0')));

   -- modules
   signal texture_color    : tcolor3_u8;
   signal texture_alpha    : unsigned(7 downto 0);

   signal combine_color    : tcolor3_u8;
   signal combine_alpha    : unsigned(7 downto 0);
   
   signal FBcolor          : tcolor4_u8;
   signal cvgFB            : unsigned(2 downto 0);
   
   signal blender_color    : tcolor3_u8;
   
   -- stage calc
   signal texture_S_unclamped : signed(18 downto 0);
   signal texture_T_unclamped : signed(18 downto 0);
   
   signal texture_S_clamped   : signed(15 downto 0);
   signal texture_T_clamped   : signed(15 downto 0);
  
   signal texture_S_index     : unsigned(9 downto 0);
   signal texture_T_index     : unsigned(9 downto 0);
   signal texture_S_frac      : unsigned(4 downto 0);
   signal texture_T_frac      : unsigned(4 downto 0);
   signal texture_S_diff      : signed(1 downto 0);
   signal texture_T_diff      : signed(1 downto 0);

   -- export only
   -- synthesis translate_off
   signal stage_cvg16         : t_stage_u16;
   signal stage_colorFull     : t_stage_c32s;
   signal stage_STWZ          : t_stage_c32s;
   signal stage_texCoord_S    : t_stage_s16;
   signal stage_texCoord_T    : t_stage_s16;
   signal stage_texIndex_S    : t_stage_u10;
   signal stage_texIndex_T    : t_stage_u10;
   signal stage_texAddr       : t_stage_u12;
   signal stage_texFt_addr    : t_stage_u32;
   signal stage_texFt_data    : t_stage_u32;
   signal stage_texFt_db1     : t_stage_u32;
   signal stage_texFt_db3     : t_stage_u32;
   signal stage_combineC      : t_stage_c8u;
   signal stage_FBcolor       : t_stage_c8u;
   signal stage_cvgFB         : t_stage_u3;
   
   signal export_TexFt_addr   : unsigned(31 downto 0);
   signal export_TexFt_data   : unsigned(31 downto 0);
   signal export_TexFt_db1    : unsigned(31 downto 0);
   signal export_TexFt_db3    : unsigned(31 downto 0);
   -- synthesis translate_on

begin 

   pipe_busy <= '1' when (stage_valid > 0) else '0';

   process (clk1x)
      variable cvgCounter : unsigned(3 downto 0);
   begin
      if rising_edge(clk1x) then
      
         writePixel <= '0';
         
         -- synthesis translate_off
         export_pipeDone <= '0';
         -- synthesis translate_on
      
         if (reset = '1') then
            stage_valid <= (others => '0');
         elsif (pipeIn_trigger = '1') then
      
            -- ##################################################
            -- ######### STAGE_INPUT ############################
            -- ##################################################
            stage_valid(STAGE_INPUT)      <= pipeIn_valid;
            stage_addr(STAGE_INPUT)       <= pipeIn_addr;
            stage_x(STAGE_INPUT)          <= pipeIn_X;
            stage_y(STAGE_INPUT)          <= pipeIn_Y;
            stage_cvgValue(STAGE_INPUT)   <= pipeIn_cvgValue;
            stage_offX(STAGE_INPUT)       <= pipeIn_offX;
            stage_offY(STAGE_INPUT)       <= pipeIn_offY;
            stage_Color(STAGE_INPUT)      <= pipeInColor;
            
            cvgCounter := (others => '0');
            for i in 0 to 7 loop
               if (pipeIn_cvgValue(i) = '1') then
                  cvgCounter := cvgCounter + 1;
               end if;
            end loop;
            stage_cvgCount(STAGE_INPUT) <= cvgCounter;
            
            -- synthesis translate_off
            stage_cvg16(STAGE_INPUT)      <= pipeIn_cvg16;
            stage_colorFull(STAGE_INPUT)  <= pipeInColorFull;
            stage_STWZ(STAGE_INPUT)       <= pipeInSTWZ;
            stage_texCoord_S(STAGE_INPUT) <= texture_S_clamped;
            stage_texCoord_T(STAGE_INPUT) <= texture_T_clamped;
            stage_texIndex_S(STAGE_INPUT) <= texture_S_index;
            stage_texIndex_T(STAGE_INPUT) <= texture_T_index;
            stage_texAddr(STAGE_INPUT)    <= TextureAddr;
            -- synthesis translate_on
            
            -- ##################################################
            -- ######### STAGE_COMBINER #########################
            -- ##################################################
            
            stage_valid(STAGE_COMBINER)    <= stage_valid(STAGE_INPUT);   
            stage_addr(STAGE_COMBINER)     <= stage_addr(STAGE_INPUT);       
            stage_x(STAGE_COMBINER)        <= stage_x(STAGE_INPUT);          
            stage_y(STAGE_COMBINER)        <= stage_y(STAGE_INPUT);          
            stage_cvgValue(STAGE_COMBINER) <= stage_cvgValue(STAGE_INPUT);   
            stage_offX(STAGE_COMBINER)     <= stage_offX(STAGE_INPUT);   
            stage_offY(STAGE_COMBINER)     <= stage_offY(STAGE_INPUT);   
            stage_cvgCount(STAGE_COMBINER) <= stage_cvgCount(STAGE_INPUT);

            -- synthesis translate_off
            stage_cvg16(STAGE_COMBINER)      <= stage_cvg16(STAGE_INPUT);
            stage_colorFull(STAGE_COMBINER)  <= stage_colorFull(STAGE_INPUT);
            stage_STWZ(STAGE_COMBINER)       <= stage_STWZ(STAGE_INPUT);
            stage_texCoord_S(STAGE_COMBINER) <= stage_texCoord_S(STAGE_INPUT);
            stage_texCoord_T(STAGE_COMBINER) <= stage_texCoord_T(STAGE_INPUT);
            stage_texIndex_S(STAGE_COMBINER) <= stage_texIndex_S(STAGE_INPUT);
            stage_texIndex_T(STAGE_COMBINER) <= stage_texIndex_T(STAGE_INPUT);
            stage_texAddr(STAGE_COMBINER)    <= stage_texAddr(STAGE_INPUT);
            stage_texFt_addr(STAGE_COMBINER) <= export_TexFt_addr;
            stage_texFt_data(STAGE_COMBINER) <= export_TexFt_data;
            stage_texFt_db1(STAGE_COMBINER)  <= export_TexFt_db1; 
            stage_texFt_db3(STAGE_COMBINER)  <= export_TexFt_db3; 
            -- synthesis translate_on         

            -- ##################################################
            -- ######### STAGE_BLENDER #########################
            -- ##################################################
            
            stage_valid(STAGE_BLENDER)    <= stage_valid(STAGE_COMBINER);   
            stage_addr(STAGE_BLENDER)     <= stage_addr(STAGE_COMBINER);       
            stage_x(STAGE_BLENDER)        <= stage_x(STAGE_COMBINER);          
            stage_y(STAGE_BLENDER)        <= stage_y(STAGE_COMBINER);          
            stage_cvgValue(STAGE_BLENDER) <= stage_cvgValue(STAGE_COMBINER);   
            stage_offX(STAGE_BLENDER)     <= stage_offX(STAGE_COMBINER);   
            stage_offY(STAGE_BLENDER)     <= stage_offY(STAGE_COMBINER);   
            stage_cvgCount(STAGE_BLENDER) <= stage_cvgCount(STAGE_COMBINER);

            -- synthesis translate_off
            stage_cvg16(STAGE_BLENDER)       <= stage_cvg16(STAGE_COMBINER);
            stage_colorFull(STAGE_BLENDER)   <= stage_colorFull(STAGE_COMBINER);
            stage_STWZ(STAGE_BLENDER)        <= stage_STWZ(STAGE_COMBINER);
            stage_texCoord_S(STAGE_BLENDER)  <= stage_texCoord_S(STAGE_COMBINER);
            stage_texCoord_T(STAGE_BLENDER)  <= stage_texCoord_T(STAGE_COMBINER);
            stage_texIndex_S(STAGE_BLENDER)  <= stage_texIndex_S(STAGE_COMBINER);
            stage_texIndex_T(STAGE_BLENDER)  <= stage_texIndex_T(STAGE_COMBINER);
            stage_texAddr(STAGE_BLENDER)     <= stage_texAddr(STAGE_COMBINER);
            stage_texFt_addr(STAGE_BLENDER)  <= stage_texFt_addr(STAGE_COMBINER);
            stage_texFt_data(STAGE_BLENDER)  <= stage_texFt_data(STAGE_COMBINER);
            stage_texFt_db1(STAGE_BLENDER)   <= stage_texFt_db1(STAGE_COMBINER);
            stage_texFt_db3(STAGE_BLENDER)   <= stage_texFt_db3(STAGE_COMBINER);
            stage_combineC(STAGE_BLENDER)(0) <= combine_color(0);
            stage_combineC(STAGE_BLENDER)(1) <= combine_color(1);
            stage_combineC(STAGE_BLENDER)(2) <= combine_color(2);
            stage_combineC(STAGE_BLENDER)(3) <= combine_alpha;
            stage_FBcolor(STAGE_BLENDER)     <= FBcolor;
            stage_cvgFB(STAGE_BLENDER)       <= cvgFB;
            -- synthesis translate_on                  
            
            -- ##################################################
            -- ######### STAGE_OUTPUT ###########################
            -- ##################################################
            writePixel      <= stage_valid(STAGE_OUTPUT - 1);
            writePixelAddr  <= stage_addr(STAGE_OUTPUT - 1);
            writePixelX     <= stage_x(STAGE_OUTPUT - 1);
            writePixelY     <= stage_y(STAGE_OUTPUT - 1);
            writePixelColor <= blender_color;
            
            --writePixelColor <= x"0000" & byteswap16(settings_blendcolor.blend_R(7 downto 3) & settings_blendcolor.blend_G(7 downto 3) & settings_blendcolor.blend_B(7 downto 3) & '0');
            
            -- todo: alpha compare check
            if ((settings_otherModes.AntiAlias = '1' and stage_cvgValue(STAGE_OUTPUT - 1) = 0) or (settings_otherModes.AntiAlias = '0' and stage_cvgValue(STAGE_OUTPUT - 1)(7) = '0')) then
               writePixel <= '0';
            end if;
            
            case (settings_otherModes.cvgDest) is
               when "00" =>
                  -- todo : if blend_ena
                  writePixelCvg <= resize(stage_cvgCount(STAGE_OUTPUT - 1) - 1, 3);
                  
               when "01" => writePixelCvg <= "000"; -- todo: (cvg + cvgMem);
               when "10" => writePixelCvg <= "111";
               when "11" => writePixelCvg <= "000"; -- todo: cvg mem
               when others => null;
            end case;
            
            
            -- synthesis translate_off
            export_pipeDone <= stage_valid(STAGE_OUTPUT - 1); 
            
            export_pipeO.addr       <= resize(stage_offX(STAGE_OUTPUT - 1), 32);
            export_pipeO.data       <= resize(stage_offY(STAGE_OUTPUT - 1), 64);
            export_pipeO.x          <= resize(stage_x(STAGE_OUTPUT - 1), 16);
            export_pipeO.y          <= resize(stage_y(STAGE_OUTPUT - 1), 16);
            export_pipeO.debug1     <= stage_cvg16(STAGE_OUTPUT - 1) & resize(stage_cvgValue(STAGE_OUTPUT - 1), 16);
            export_pipeO.debug2     <= resize(stage_cvgCount(STAGE_OUTPUT - 1), 32);
            export_pipeO.debug3     <= 31x"0" & stage_cvgValue(STAGE_OUTPUT - 1)(7);            
                  
            export_Color.addr       <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(3));
            export_Color.data       <= (others => '0');
            export_Color.x          <= resize(stage_x(STAGE_OUTPUT - 1), 16);
            export_Color.y          <= resize(stage_y(STAGE_OUTPUT - 1), 16);
            export_Color.debug1     <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(0));
            export_Color.debug2     <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(1));
            export_Color.debug3     <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(2));            
                  
            export_LOD.addr         <= (others => '0');
            export_LOD.data         <= (others => '0');
            export_LOD.x            <= resize(settings_poly.tile, 16);
            export_LOD.y            <= resize(settings_poly.tile, 16);
            export_LOD.debug1       <= x"000000FF";
            export_LOD.debug2       <= (others => '0');
            export_LOD.debug3       <= (others => '0');            
            
            export_TexCoord.addr    <= 16x"0" & unsigned(stage_texCoord_S(STAGE_OUTPUT - 1));
            export_TexCoord.data    <= 48x"0" & unsigned(stage_texCoord_T(STAGE_OUTPUT - 1));
            export_TexCoord.x       <= resize(stage_x(STAGE_OUTPUT - 1), 16);
            export_TexCoord.y       <= resize(stage_y(STAGE_OUTPUT - 1), 16);
            export_TexCoord.debug1  <= unsigned(stage_STWZ(STAGE_OUTPUT - 1)(0));
            export_TexCoord.debug2  <= unsigned(stage_STWZ(STAGE_OUTPUT - 1)(1));
            export_TexCoord.debug3  <= unsigned(stage_STWZ(STAGE_OUTPUT - 1)(2));             
               
            export_TexFetch.addr    <= stage_texFt_addr(STAGE_OUTPUT - 1);
            export_TexFetch.data    <= resize(stage_texFt_data(STAGE_OUTPUT - 1), 64);
            export_TexFetch.x       <= resize(stage_texIndex_S(STAGE_OUTPUT - 1), 16);
            export_TexFetch.y       <= resize(stage_texIndex_T(STAGE_OUTPUT - 1), 16);
            export_TexFetch.debug1  <= stage_texFt_db1(STAGE_OUTPUT - 1);
            export_TexFetch.debug2  <= resize(stage_texAddr(STAGE_OUTPUT - 1), 32);
            export_TexFetch.debug3  <= stage_texFt_db3(STAGE_OUTPUT - 1);          
               
            export_TexColor.addr    <= (others => '0');
            export_TexColor.data    <= resize(stage_texFt_data(STAGE_OUTPUT - 1)(31 downto 24), 64);
            export_TexColor.x       <= resize(stage_texIndex_S(STAGE_OUTPUT - 1), 16);
            export_TexColor.y       <= resize(stage_texIndex_T(STAGE_OUTPUT - 1), 16);
            export_TexColor.debug1  <= resize(stage_texFt_data(STAGE_OUTPUT - 1)(23 downto 16), 32);
            export_TexColor.debug2  <= resize(stage_texFt_data(STAGE_OUTPUT - 1)(15 downto 8), 32);
            export_TexColor.debug3  <= resize(stage_texFt_data(STAGE_OUTPUT - 1)( 7 downto 0), 32);
               
            export_Comb.addr        <= resize(stage_combineC(STAGE_OUTPUT - 1)(3), 32);
            export_Comb.data        <= (others => '0');
            export_Comb.x           <= (others => '0');
            export_Comb.y           <= (others => '0');
            export_Comb.debug1      <= resize(stage_combineC(STAGE_OUTPUT - 1)(0), 32);
            export_Comb.debug2      <= resize(stage_combineC(STAGE_OUTPUT - 1)(1), 32);
            export_Comb.debug3      <= resize(stage_combineC(STAGE_OUTPUT - 1)(2), 32);            
               
            export_FBMem.addr       <= resize(stage_FBcolor(STAGE_OUTPUT - 1)(3), 32);
            export_FBMem.data       <= resize(stage_cvgFB(STAGE_OUTPUT - 1), 64);
            export_FBMem.x          <= (others => '0');
            export_FBMem.y          <= (others => '0');
            export_FBMem.debug1     <= resize(stage_FBcolor(STAGE_OUTPUT - 1)(0), 32);
            export_FBMem.debug2     <= resize(stage_FBcolor(STAGE_OUTPUT - 1)(1), 32);
            export_FBMem.debug3     <= resize(stage_FBcolor(STAGE_OUTPUT - 1)(2), 32);
            -- synthesis translate_on

         end if;
      end if;
   end process;
   
   -- STAGE_INPUT
   texture_S_unclamped <= "00" & pipeIn_S(15) & pipeIn_S;
   texture_T_unclamped <= "00" & pipeIn_T(15) & pipeIn_T;
   
   iRDP_TexCoordClamp_S : entity work.RDP_TexCoordClamp port map (texture_S_unclamped, texture_S_clamped);
   iRDP_TexCoordClamp_T : entity work.RDP_TexCoordClamp port map (texture_T_unclamped, texture_T_clamped);
    
   iRDP_TexTile_S: entity work.RDP_TexTile
   port map
   (
      coordIn        => texture_S_clamped,
      tile_max       => settings_tile.Tile_sh,
      tile_min       => settings_tile.Tile_sl,
      tile_clamp     => settings_tile.Tile_clampS, 
      tile_mirror    => settings_tile.Tile_mirrorS,
      tile_mask      => settings_tile.Tile_maskS,  
      tile_shift     => settings_tile.Tile_shiftS, 
                     
      index_out      => texture_S_index,
      frac_out       => texture_S_frac,
      diff_out       => texture_S_diff
   );
   
   iRDP_TexTile_T: entity work.RDP_TexTile
   port map
   (
      coordIn        => texture_T_clamped,
      tile_max       => settings_tile.Tile_th,
      tile_min       => settings_tile.Tile_tl,
      tile_clamp     => settings_tile.Tile_clampT, 
      tile_mirror    => settings_tile.Tile_mirrorT,
      tile_mask      => settings_tile.Tile_maskT,  
      tile_shift     => settings_tile.Tile_shiftT, 
                     
      index_out      => texture_T_index,
      frac_out       => texture_T_frac,
      diff_out       => texture_T_diff
   );
    
   iRDP_TexFetch: entity work.RDP_TexFetch
   port map
   (
      clk1x             => clk1x,
      
      settings_tile     => settings_tile,
      index_S           => texture_S_index,
      index_T           => texture_T_index,
                        
      tex_addr          => TextureAddr,
      tex_data          => TextureRamData,
      
      -- synthesis translate_off
      export_TexFt_addr => export_TexFt_addr,
      export_TexFt_data => export_TexFt_data,
      export_TexFt_db1  => export_TexFt_db1, 
      export_TexFt_db3  => export_TexFt_db3, 
      -- synthesis translate_on
                      
      tex_color         => texture_color,
      tex_alpha         => texture_alpha
   );

   -- STAGE_COMBINER
   iRDP_CombineColor : entity work.RDP_CombineColor
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
      
      errorCombine_out        => errorCombine,
   
      settings_otherModes     => settings_otherModes,
      settings_combineMode    => settings_combineMode,
      
      pipeInColor             => stage_Color(STAGE_INPUT),
      texture_color           => texture_color,
     
      combine_color           => combine_color
   );
   
   iRDP_CombineAlpha : entity work.RDP_CombineAlpha
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
                              
      settings_otherModes     => settings_otherModes,
      settings_combineMode    => settings_combineMode,
                              
      pipeInColor             => stage_Color(STAGE_INPUT),
      tex_alpha               => texture_alpha,
      lod_frac                => x"FF", -- todo
                              
      combine_alpha           => combine_alpha
   );
   
   iRDP_FBread : entity work.RDP_FBread
   port map
   (
      clk1x                   => clk1x,              
      trigger                 => pipeIn_trigger,            
                                                    
      settings_otherModes     => settings_otherModes,
      settings_colorImage     => settings_colorImage,
                                                    
      xIndex                  => pipeIn_xIndex,             
      yOdd                    => pipeIn_Y(0),               
                                                    
      FBAddr                  => FBAddr,             
      FBData                  => unsigned(FBData),             
                              
      FBcolor                 => FBcolor,
      cvgFB                   => cvgFB
   );
   
   
   -- STAGE_BLENDER
   
   iRDP_BlendColor : entity work.RDP_BlendColor
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
   
      settings_otherModes     => settings_otherModes,
      settings_blendcolor     => settings_blendcolor,
      
      combine_color           => combine_color,
      combine_alpha           => combine_alpha,
      FB_color                => FBcolor,     
      
      blender_color           => blender_color
   );

end architecture;





