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
      error_combineAlpha      : out std_logic;
      
      pipe_busy               : out std_logic;
   
      settings_poly           : in  tsettings_poly;
      settings_otherModes     : in  tsettings_otherModes;
      settings_fogcolor       : in  tsettings_fogcolor;
      settings_blendcolor     : in  tsettings_blendcolor;
      settings_primcolor      : in  tsettings_primcolor;
      settings_envcolor       : in  tsettings_envcolor;
      settings_colorImage     : in  tsettings_colorImage;
      settings_textureImage   : in  tsettings_textureImage;
      settings_tile           : in  tsettings_tile;
      settings_combineMode    : in  tsettings_combineMode;
     
      pipeIn_trigger          : in  std_logic;
      pipeIn_valid            : in  std_logic;
      pipeIn_Addr             : in  unsigned(25 downto 0);
      pipeIn_AddrZ            : in  unsigned(25 downto 0);
      pipeIn_xIndexPx         : in  unsigned(11 downto 0);
      pipeIn_xIndex9          : in  unsigned(11 downto 0);
      pipeIn_X                : in  unsigned(11 downto 0);
      pipeIn_Y                : in  unsigned(11 downto 0);
      pipeIn_cvgValue         : in  unsigned(7 downto 0);
      pipeIn_offX             : in  unsigned(1 downto 0);
      pipeIn_offY             : in  unsigned(1 downto 0);
      pipeInColor             : in  tcolor4_s16;
      pipeIn_S                : in  signed(15 downto 0);
      pipeIn_T                : in  signed(15 downto 0);
      pipeInWShift            : in  integer range 0 to 14 := 0;
      pipeInWNormLow          : in  unsigned(7 downto 0) := (others => '0');
      pipeInWtemppoint        : in  signed(15 downto 0) := (others => '0');
      pipeInWtempslope        : in  unsigned(7 downto 0) := (others => '0');
      pipeIn_Z                : in  signed(21 downto 0);
      pipeIn_dzPix            : in  unsigned(15 downto 0);
      
      TextureAddr             : out unsigned(11 downto 0);
      TextureRamData          : in  tTextureRamData;
      
      FBAddr                  : out unsigned(10 downto 0);
      FBData                  : in  std_logic_vector(31 downto 0);
      
      FBAddr9                 : out unsigned(7 downto 0);
      FBData9                 : in  std_logic_vector(31 downto 0);
      FBData9Z                : in  std_logic_vector(31 downto 0);
      
      FBAddrZ                 : out unsigned(11 downto 0);
      FBDataZ                 : in  std_logic_vector(15 downto 0);
     
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
      export_Z                : out rdp_export_type := (others => (others => '0'));
      -- synthesis translate_on
      
      writePixel              : out std_logic := '0';
      writePixelAddr          : out unsigned(25 downto 0);
      writePixelX             : out unsigned(11 downto 0) := (others => '0');
      writePixelY             : out unsigned(11 downto 0) := (others => '0');
      writePixelColor         : out tcolor3_u8 := (others => (others => '0'));
      writePixelCvg           : out unsigned(2 downto 0);
      writePixelFBData9       : out unsigned(31 downto 0);
      
      writePixelZ             : out std_logic := '0';
      writePixelAddrZ         : out unsigned(25 downto 0) := (others => '0');
      writePixelDataZ         : out unsigned(17 downto 0) := (others => '0');
      writePixelFBData9Z      : out unsigned(31 downto 0) := (others => '0')
   );
end entity;

architecture arch of RDP_pipeline is

   constant STAGE_INPUT     : integer := 0;
   constant STAGE_PERSPCOR  : integer := 1;
   constant STAGE_TEXFETCH  : integer := 2;
   constant STAGE_COMBINER  : integer := 3;
   constant STAGE_BLENDER   : integer := 4;
   constant STAGE_OUTPUT    : integer := 5;
   
   type t_stage_std is array(0 to STAGE_OUTPUT - 1) of std_logic;
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
   signal stage_valid         : unsigned(0 to STAGE_OUTPUT - 1);
   signal stage_addr          : t_stage_u26 := (others => (others => '0'));
   signal stage_addrZ         : t_stage_u26 := (others => (others => '0'));
   signal stage_xIndexPx      : t_stage_u12 := (others => (others => '0'));
   signal stage_xIndex9       : t_stage_u12 := (others => (others => '0'));
   signal stage_x             : t_stage_u12 := (others => (others => '0'));
   signal stage_y             : t_stage_u12 := (others => (others => '0'));
   signal stage_cvgValue      : t_stage_u8 := (others => (others => '0'));
   signal stage_offX          : t_stage_u2 := (others => (others => '0'));
   signal stage_offY          : t_stage_u2 := (others => (others => '0'));
   signal stage_cvgCount      : t_stage_u4 := (others => (others => '0'));
   signal stage_Color         : t_stage_c16s := (others => (others => (others => '0')));
   signal stage_FBcolor       : t_stage_c8u := (others => (others => (others => '0')));
   signal stage_cvgFB         : t_stage_u3 := (others => (others => '0'));
   signal stage_cvgSum        : t_stage_u3 := (others => (others => '0'));
   signal stage_blendEna      : t_stage_std := (others => '0');
   signal stage_FBData9       : t_stage_u32 := (others => (others => '0'));
   signal stage_FBData9Z      : t_stage_u32 := (others => (others => '0'));
      
   -- only delayed once 
   signal pipeIn_S_1          : signed(15 downto 0) := (others => '0');
   signal pipeIn_T_1          : signed(15 downto 0) := (others => '0');
   signal pipeInWShift_1      : integer range 0 to 14 := 0;
   
   signal texture_S_unclamped : signed(18 downto 0) := (others => '0');
   signal texture_T_unclamped : signed(18 downto 0) := (others => '0');
   
   -- modules  
   signal texture_color       : tcolor3_u8;
   signal texture_alpha       : unsigned(7 downto 0);
   
   signal combine_color       : tcolor3_u8;
   signal combine_alpha       : unsigned(7 downto 0);
      
   signal FBcolor             : tcolor4_u8;
   signal cvgFB               : unsigned(2 downto 0);
   signal FBData9_old         : unsigned(31 downto 0);
   signal FBData9_oldZ        : unsigned(31 downto 0);
   signal old_Z_mem           : unsigned(17 downto 0);
      
   signal blender_color       : tcolor3_u8;
   
   -- stage calc
   signal wslopeMul           : signed(17 downto 0);
   signal wslopeResult        : signed(15 downto 0) := (others => '0');
   signal wMulS               : signed(31 downto 0);
   signal wMulT               : signed(31 downto 0);
   signal wShiftedS           : signed(32 downto 0);
   signal wShiftedT           : signed(32 downto 0);
   
   signal texture_S_clamped   : signed(15 downto 0);
   signal texture_T_clamped   : signed(15 downto 0);
  
   signal texture_S_index     : unsigned(9 downto 0);
   signal texture_T_index     : unsigned(9 downto 0);
   signal texture_S_frac      : unsigned(4 downto 0);
   signal texture_T_frac      : unsigned(4 downto 0);
   signal texture_S_diff      : signed(1 downto 0);
   signal texture_T_diff      : signed(1 downto 0);
   
   signal cvg_sum             : unsigned(3 downto 0);
   
   signal dzPixEnc            : unsigned(3 downto 0) := (others => '0');
   signal blend_enable        : std_logic;
   signal zUsePixel           : std_logic;
   signal zResult             : unsigned(15 downto 0);
   signal zResultH            : unsigned(1 downto 0);

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
   signal stage_zNewRaw       : t_stage_u32;
   signal stage_zOld          : t_stage_u32;
   signal stage_dzOld         : t_stage_u16;
   signal stage_dzNew         : t_stage_u16;
   
   signal export_TexFt_addr   : unsigned(31 downto 0);
   signal export_TexFt_data   : unsigned(31 downto 0);
   signal export_TexFt_db1    : unsigned(31 downto 0);
   signal export_TexFt_db3    : unsigned(31 downto 0);
   signal export_zNewRaw      : unsigned(31 downto 0);
   signal export_zOld         : unsigned(31 downto 0);
   signal export_dzOld        : unsigned(15 downto 0);
   signal export_dzNew        : unsigned(15 downto 0);
   -- synthesis translate_on

begin 

   pipe_busy <= '1' when (stage_valid > 0) else '0';
   
   cvg_sum   <= stage_cvgCount(STAGE_TEXFETCH) + ('0' & cvgFB);
                
   -- perspective correction - input stage
   wslopeMul    <= ('1' & signed(pipeInWtempslope)) * ('0' & signed(pipeInWNormLow));
   
   -- perspective correction - perspective stage
   wMulS <= pipeIn_S_1 * wslopeResult;
   wMulT <= pipeIn_T_1 * wslopeResult;
   
   wShiftedS <= shift_right(wMulS & '0', pipeInWShift_1);
   wShiftedT <= shift_right(wMulT & '0', pipeInWShift_1);

   process (clk1x)
      variable cvgCounter : unsigned(3 downto 0);
   begin
      if rising_edge(clk1x) then
      
         writePixel  <= '0';
         writePixelZ <= '0';
         
         -- synthesis translate_off
         export_pipeDone <= '0';
         -- synthesis translate_on
         
         dzPixEnc <= (others => '0');
         if (pipeIn_dzPix(15 downto 8) > 0)                                                                                       then dzPixEnc(3) <= '1'; end if;
         if ((pipeIn_dzPix(15 downto 12) & pipeIn_dzPix(7 downto 4)) > 0)                                                         then dzPixEnc(2) <= '1'; end if;
         if ((pipeIn_dzPix(15 downto 14) & pipeIn_dzPix(11 downto 10) & pipeIn_dzPix(7 downto 6) & pipeIn_dzPix(3 downto 2)) > 0) then dzPixEnc(1) <= '1'; end if;
         if ((pipeIn_dzPix(15) or pipeIn_dzPix(13) or pipeIn_dzPix(11) or pipeIn_dzPix(9) or pipeIn_dzPix(7) or pipeIn_dzPix(5) or pipeIn_dzPix(3) or pipeIn_dzPix(1)) = '1') then dzPixEnc(0) <= '1'; end if;
      
         if (reset = '1') then
            stage_valid <= (others => '0');
         elsif (pipeIn_trigger = '1') then
      
            -- ##################################################
            -- ######### STAGE_INPUT ############################
            -- ##################################################
            stage_valid(STAGE_INPUT)      <= pipeIn_valid;
            stage_addr(STAGE_INPUT)       <= pipeIn_addr;
            stage_addrZ(STAGE_INPUT)      <= pipeIn_AddrZ;
            stage_xIndexPx(STAGE_INPUT)   <= pipeIn_xIndexPx;
            stage_xIndex9(STAGE_INPUT)    <= pipeIn_xIndex9;
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
            
            wslopeResult   <= pipeInWtemppoint + to_integer(wslopeMul(17 downto 8));
            pipeIn_S_1     <= pipeIn_S;    
            pipeIn_T_1     <= pipeIn_T;    
            pipeInWShift_1 <= pipeInWShift;
            -- synthesis translate_off
            stage_cvg16(STAGE_INPUT)      <= pipeIn_cvg16;
            stage_colorFull(STAGE_INPUT)  <= pipeInColorFull;
            stage_STWZ(STAGE_INPUT)       <= pipeInSTWZ;
            -- synthesis translate_on
            
            -- ##################################################
            -- ######### STAGE_PERSPCOR #########################
            -- ##################################################
            
            stage_valid(STAGE_PERSPCOR)    <= stage_valid(STAGE_INPUT);   
            stage_addr(STAGE_PERSPCOR)     <= stage_addr(STAGE_INPUT);  
            stage_addrZ(STAGE_PERSPCOR)    <= stage_addrZ(STAGE_INPUT);  
            stage_xIndexPx(STAGE_PERSPCOR) <= stage_xIndexPx(STAGE_INPUT);
            stage_xIndex9(STAGE_PERSPCOR)  <= stage_xIndex9(STAGE_INPUT);           
            stage_x(STAGE_PERSPCOR)        <= stage_x(STAGE_INPUT);          
            stage_y(STAGE_PERSPCOR)        <= stage_y(STAGE_INPUT);          
            stage_cvgValue(STAGE_PERSPCOR) <= stage_cvgValue(STAGE_INPUT);   
            stage_offX(STAGE_PERSPCOR)     <= stage_offX(STAGE_INPUT);   
            stage_offY(STAGE_PERSPCOR)     <= stage_offY(STAGE_INPUT);  
            stage_Color(STAGE_PERSPCOR)    <= stage_Color(STAGE_INPUT);         
            stage_cvgCount(STAGE_PERSPCOR) <= stage_cvgCount(STAGE_INPUT);
            
            if (settings_otherModes.perspTex = '1') then
               texture_S_unclamped <= "00" & wShiftedS(16 downto 0);
               texture_T_unclamped <= "00" & wShiftedT(16 downto 0);
            else
               texture_S_unclamped <= "00" & pipeIn_S_1(15) & pipeIn_S_1;
               texture_T_unclamped <= "00" & pipeIn_T_1(15) & pipeIn_T_1;
            end if;

            -- synthesis translate_off
            stage_cvg16(STAGE_PERSPCOR)      <= stage_cvg16(STAGE_INPUT);
            stage_colorFull(STAGE_PERSPCOR)  <= stage_colorFull(STAGE_INPUT);
            stage_STWZ(STAGE_PERSPCOR)       <= stage_STWZ(STAGE_INPUT);
            -- synthesis translate_on                 
            
            -- ##################################################
            -- ######### STAGE_TEXFETCH #########################
            -- ##################################################
            
            stage_valid(STAGE_TEXFETCH)    <= stage_valid(STAGE_PERSPCOR);   
            stage_addr(STAGE_TEXFETCH)     <= stage_addr(STAGE_PERSPCOR);       
            stage_addrZ(STAGE_TEXFETCH)    <= stage_addrZ(STAGE_PERSPCOR);       
            stage_x(STAGE_TEXFETCH)        <= stage_x(STAGE_PERSPCOR);          
            stage_y(STAGE_TEXFETCH)        <= stage_y(STAGE_PERSPCOR);          
            stage_cvgValue(STAGE_TEXFETCH) <= stage_cvgValue(STAGE_PERSPCOR);   
            stage_offX(STAGE_TEXFETCH)     <= stage_offX(STAGE_PERSPCOR);   
            stage_offY(STAGE_TEXFETCH)     <= stage_offY(STAGE_PERSPCOR);  
            stage_Color(STAGE_TEXFETCH)    <= stage_Color(STAGE_PERSPCOR);         
            stage_cvgCount(STAGE_TEXFETCH) <= stage_cvgCount(STAGE_PERSPCOR);

            -- synthesis translate_off
            stage_cvg16(STAGE_TEXFETCH)      <= stage_cvg16(STAGE_PERSPCOR);
            stage_colorFull(STAGE_TEXFETCH)  <= stage_colorFull(STAGE_PERSPCOR);
            stage_STWZ(STAGE_TEXFETCH)       <= stage_STWZ(STAGE_PERSPCOR);
            stage_texCoord_S(STAGE_TEXFETCH) <= texture_S_clamped;
            stage_texCoord_T(STAGE_TEXFETCH) <= texture_T_clamped;
            stage_texIndex_S(STAGE_TEXFETCH) <= texture_S_index;
            stage_texIndex_T(STAGE_TEXFETCH) <= texture_T_index;
            stage_texAddr(STAGE_TEXFETCH)    <= TextureAddr;
            -- synthesis translate_on         
            
            -- ##################################################
            -- ######### STAGE_COMBINER #########################
            -- ##################################################
            
            stage_valid(STAGE_COMBINER)    <= stage_valid(STAGE_TEXFETCH);   
            stage_addr(STAGE_COMBINER)     <= stage_addr(STAGE_TEXFETCH);       
            stage_addrZ(STAGE_COMBINER)    <= stage_addrZ(STAGE_TEXFETCH);       
            stage_x(STAGE_COMBINER)        <= stage_x(STAGE_TEXFETCH);          
            stage_y(STAGE_COMBINER)        <= stage_y(STAGE_TEXFETCH);          
            stage_cvgValue(STAGE_COMBINER) <= stage_cvgValue(STAGE_TEXFETCH);   
            stage_offX(STAGE_COMBINER)     <= stage_offX(STAGE_TEXFETCH);   
            stage_offY(STAGE_COMBINER)     <= stage_offY(STAGE_TEXFETCH);   
            stage_cvgCount(STAGE_COMBINER) <= stage_cvgCount(STAGE_TEXFETCH);
            stage_FBcolor(STAGE_COMBINER)  <= FBcolor;
            stage_cvgFB(STAGE_COMBINER)    <= cvgFB;
            stage_FBData9(STAGE_COMBINER)  <= FBData9_old;
            stage_FBData9Z(STAGE_COMBINER) <= FBData9_oldZ;
            if (cvg_sum(3) = '1') then stage_cvgSum(STAGE_COMBINER) <= "111";  else stage_cvgSum(STAGE_COMBINER) <= cvg_sum(2 downto 0); end if;

            -- synthesis translate_off
            stage_cvg16(STAGE_COMBINER)      <= stage_cvg16(STAGE_TEXFETCH);
            stage_colorFull(STAGE_COMBINER)  <= stage_colorFull(STAGE_TEXFETCH);
            stage_STWZ(STAGE_COMBINER)       <= stage_STWZ(STAGE_TEXFETCH);
            stage_texCoord_S(STAGE_COMBINER) <= stage_texCoord_S(STAGE_TEXFETCH);
            stage_texCoord_T(STAGE_COMBINER) <= stage_texCoord_T(STAGE_TEXFETCH);
            stage_texIndex_S(STAGE_COMBINER) <= stage_texIndex_S(STAGE_TEXFETCH);
            stage_texIndex_T(STAGE_COMBINER) <= stage_texIndex_T(STAGE_TEXFETCH);
            stage_texAddr(STAGE_COMBINER)    <= stage_texAddr(STAGE_TEXFETCH);
            stage_texFt_addr(STAGE_COMBINER) <= export_TexFt_addr;
            stage_texFt_data(STAGE_COMBINER) <= export_TexFt_data;
            stage_texFt_db1(STAGE_COMBINER)  <= export_TexFt_db1; 
            stage_texFt_db3(STAGE_COMBINER)  <= export_TexFt_db3; 
            -- synthesis translate_on         

            -- ##################################################
            -- ######### STAGE_BLENDER ##########################
            -- ##################################################
            
            stage_valid(STAGE_BLENDER)    <= stage_valid(STAGE_COMBINER);   
            stage_addr(STAGE_BLENDER)     <= stage_addr(STAGE_COMBINER);       
            stage_addrZ(STAGE_BLENDER)    <= stage_addrZ(STAGE_COMBINER);       
            stage_x(STAGE_BLENDER)        <= stage_x(STAGE_COMBINER);          
            stage_y(STAGE_BLENDER)        <= stage_y(STAGE_COMBINER);          
            stage_cvgValue(STAGE_BLENDER) <= stage_cvgValue(STAGE_COMBINER);   
            stage_offX(STAGE_BLENDER)     <= stage_offX(STAGE_COMBINER);   
            stage_offY(STAGE_BLENDER)     <= stage_offY(STAGE_COMBINER);   
            stage_cvgCount(STAGE_BLENDER) <= stage_cvgCount(STAGE_COMBINER);
            stage_FBcolor(STAGE_BLENDER)  <= stage_FBcolor(STAGE_COMBINER);
            stage_cvgFB(STAGE_BLENDER)    <= stage_cvgFB(STAGE_COMBINER);  
            stage_FBData9(STAGE_BLENDER)  <= stage_FBData9(STAGE_COMBINER);
            stage_FBData9Z(STAGE_BLENDER) <= stage_FBData9Z(STAGE_COMBINER);
            stage_blendEna(STAGE_BLENDER) <= blend_enable;        
            stage_cvgSum(STAGE_BLENDER)   <= stage_cvgSum(STAGE_COMBINER);
            
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
            stage_zNewRaw(STAGE_BLENDER)     <= export_zNewRaw;
            stage_zOld(STAGE_BLENDER)        <= export_zOld;
            stage_dzOld(STAGE_BLENDER)       <= export_dzOld;
            stage_dzNew(STAGE_BLENDER)       <= export_dzNew;
            -- synthesis translate_on                  
            
            -- ##################################################
            -- ######### STAGE_OUTPUT ###########################
            -- ##################################################
            writePixel        <= stage_valid(STAGE_OUTPUT - 1) and zUsePixel;
            writePixelAddr    <= stage_addr(STAGE_OUTPUT - 1);
            writePixelX       <= stage_x(STAGE_OUTPUT - 1);
            writePixelY       <= stage_y(STAGE_OUTPUT - 1);
            writePixelColor   <= blender_color;
            writePixelFBData9 <= stage_FBData9(STAGE_OUTPUT - 1);
            
            writePixelZ        <= stage_valid(STAGE_OUTPUT - 1) and zUsePixel and settings_otherModes.zUpdate;
            writePixelAddrZ    <= stage_addrZ(STAGE_OUTPUT - 1);
            writePixelDataZ    <= zResultH & zResult;
            writePixelFBData9Z <= stage_FBData9Z(STAGE_OUTPUT - 1);
            
            -- todo: alpha compare check
            if ((settings_otherModes.AntiAlias = '1' and stage_cvgValue(STAGE_OUTPUT - 1) = 0) or (settings_otherModes.AntiAlias = '0' and stage_cvgValue(STAGE_OUTPUT - 1)(7) = '0')) then
               writePixel  <= '0';
               writePixelZ <= '0';
            end if;
            
            case (settings_otherModes.cvgDest) is
               when "00" =>
                  if (stage_blendEna(STAGE_OUTPUT - 1)) then 
                     writePixelCvg <= stage_cvgSum(STAGE_OUTPUT - 1);
                  else
                     writePixelCvg <= resize(stage_cvgCount(STAGE_OUTPUT - 1) - 1, 3);
                  end if;
                  
               when "01" => writePixelCvg <= stage_cvgSum(STAGE_OUTPUT - 1);
               when "10" => writePixelCvg <= "111";
               when "11" => writePixelCvg <= stage_cvgFB(STAGE_OUTPUT - 1);
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
            
            export_Z.addr           <= 13x"0" & stage_dzNew(STAGE_OUTPUT - 1) & "000";
            export_Z.data           <= 32x"0" & pipeIn_dzPix & 7x"0" & zUsePixel & 4x"0" & dzPixEnc;
            export_Z.x              <= stage_dzOld(STAGE_OUTPUT - 1);
            export_Z.y              <= 14x"0" & zResultH;
            export_Z.debug1         <= 16x"0" & zResult;
            export_Z.debug2         <= stage_zNewRaw(STAGE_OUTPUT - 1);
            export_Z.debug3         <= stage_zOld(STAGE_OUTPUT - 1);
            -- synthesis translate_on

         end if;
      end if;
   end process;
   
   -- zBuffer - covers several stages
   iRDP_Zbuffer : entity work.RDP_Zbuffer
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
   
      settings_poly           => settings_poly,
      settings_otherModes     => settings_otherModes,
      dzPix                   => pipeIn_dzPix,
      dzPixEnc                => dzPixEnc,
      
      -- STAGE_INPUT
      zIn                     => pipeIn_Z,
      offX                    => pipeIn_offX,
      offY                    => pipeIn_offY,
      
      -- STAGE_PERSPCOR
      cvgCount                => stage_cvgCount(STAGE_INPUT),
      
      -- STAGE_TEXFETCH
      old_Z_mem               => old_Z_mem,
      
      -- STAGE_COMBINER
      cvgFB                   => cvgFB,
      cvgCount_2              => stage_cvgCount(STAGE_TEXFETCH),
      
      -- synthesis translate_off
      export_zNewRaw          => export_zNewRaw,
      export_zOld             => export_zOld,
      export_dzOld            => export_dzOld,
      export_dzNew            => export_dzNew,
      -- synthesis translate_on
      
      blend_enable            => blend_enable,
      zUsePixel               => zUsePixel,
      zResult                 => zResult,
      zResultH                => zResultH
   );
   
   -- STAGE_TEXFETCH
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
      trigger           => pipeIn_trigger,
      
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
      settings_primcolor      => settings_primcolor, 
      settings_envcolor       => settings_envcolor, 
      
      pipeInColor             => stage_Color(STAGE_TEXFETCH),
      texture_color           => texture_color,
     
      combine_color           => combine_color
   );
   
   iRDP_CombineAlpha : entity work.RDP_CombineAlpha
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
      
      error_combineAlpha      => error_combineAlpha,
                              
      settings_otherModes     => settings_otherModes,
      settings_combineMode    => settings_combineMode,
      settings_primcolor      => settings_primcolor, 
      settings_envcolor       => settings_envcolor, 
                              
      pipeInColor             => stage_Color(STAGE_TEXFETCH),
      tex_alpha               => texture_alpha,
      lod_frac                => x"FF", -- todo
      cvgCount                => stage_cvgCount(STAGE_TEXFETCH),
                              
      combine_alpha           => combine_alpha
   );
   
   iRDP_FBread : entity work.RDP_FBread
   port map
   (
      clk1x                   => clk1x,              
      trigger                 => pipeIn_trigger,            
                                                    
      settings_otherModes     => settings_otherModes,
      settings_colorImage     => settings_colorImage,
                                                    
      xIndexPx                => stage_xIndexPx(STAGE_INPUT),            
      xIndex9                 => stage_xIndex9(STAGE_INPUT),           
      yOdd                    => stage_y(STAGE_INPUT)(0),               
                                                    
      FBAddr                  => FBAddr,             
      FBData                  => unsigned(FBData),  

      FBAddr9                 => FBAddr9,
      FBData9                 => unsigned(FBData9),             
      FBData9Z                => unsigned(FBData9Z),   

      FBAddrZ                 => FBAddrZ,
      FBDataZ                 => unsigned(FBDataZ), 
                              
      FBcolor                 => FBcolor,
      cvgFB                   => cvgFB,
      FBData9_old             => FBData9_old,
      FBData9_oldZ            => FBData9_oldZ,
      old_Z_mem               => old_Z_mem
   );
   
   
   -- STAGE_BLENDER
   iRDP_BlendColor : entity work.RDP_BlendColor
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
   
      settings_otherModes     => settings_otherModes,
      settings_blendcolor     => settings_blendcolor,
      
      blend_ena               => blend_enable,
      combine_color           => combine_color,
      combine_alpha           => combine_alpha,
      FB_color                => stage_FBcolor(STAGE_COMBINER),     
      blend_shift_a           => "000",
      blend_shift_b           => "000",
      
      blender_color           => blender_color
   );

end architecture;





