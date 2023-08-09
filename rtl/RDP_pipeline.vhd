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
   
      settings_otherModes     : in  tsettings_otherModes;
      settings_blendcolor     : in  tsettings_blendcolor;
      settings_colorImage     : in  tsettings_colorImage;
      settings_textureImage   : in  tsettings_textureImage;
      settings_tile           : in  tsettings_tile;
      settings_combineMode    : in  tsettings_combineMode;
     
      pipeIn_trigger          : in  std_logic;
      pipeIn_valid            : in  std_logic;
      pipeIn_Addr             : in  unsigned(25 downto 0);
      pipeIn_X                : in  unsigned(11 downto 0);
      pipeIn_Y                : in  unsigned(11 downto 0);
      pipeIn_cvgValue         : in  unsigned(7 downto 0);
      pipeIn_offX             : in  unsigned(1 downto 0);
      pipeIn_offY             : in  unsigned(1 downto 0);
      pipeInColor             : in  tcolor4_s16;
     
      -- synthesis translate_off
      pipeIn_cvg16            : in  unsigned(15 downto 0);
      pipeInColorFull         : in  tcolor4_s32;
      
      export_pipeDone         : out std_logic := '0';       
      export_pipeO            : out rdp_export_type := (others => (others => '0'));
      export_Color            : out rdp_export_type := (others => (others => '0'));
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

   constant STAGE_INPUT : integer := 0;
   constant STAGE_COMBINER : integer := 1;
   constant STAGE_BLENDER : integer := 2;
   constant STAGE_OUTPUT : integer := 3;
   
   type t_stage_u26 is array(0 to STAGE_OUTPUT - 1) of unsigned(25 downto 0);
   type t_stage_u16 is array(0 to STAGE_OUTPUT - 1) of unsigned(15 downto 0);
   type t_stage_u12 is array(0 to STAGE_OUTPUT - 1) of unsigned(11 downto 0);
   type t_stage_u8 is array(0 to STAGE_OUTPUT - 1) of unsigned(7 downto 0);
   type t_stage_u4 is array(0 to STAGE_OUTPUT - 1) of unsigned(3 downto 0);
   type t_stage_u2 is array(0 to STAGE_OUTPUT - 1) of unsigned(1 downto 0);
   type t_stage_c32s is array(0 to STAGE_OUTPUT - 1) of tcolor4_s32;
   
   signal stage_valid      : unsigned(0 to STAGE_OUTPUT - 1);
   signal stage_addr       : t_stage_u26;
   signal stage_x          : t_stage_u12;
   signal stage_y          : t_stage_u12;
   signal stage_cvgValue   : t_stage_u8;
   signal stage_offX       : t_stage_u2;
   signal stage_offY       : t_stage_u2;
   signal stage_cvgCount   : t_stage_u4;
   
   signal combine_color    : tcolor3_u8;
   signal blender_color    : tcolor3_u8;
  
   -- export only
   -- synthesis translate_off
   signal stage_cvg16      : t_stage_u16;
   signal stage_colorFull  : t_stage_c32s;
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
            
            cvgCounter := (others => '0');
            for i in 0 to 7 loop
               if (pipeIn_cvgValue(i) = '1') then
                  cvgCounter := cvgCounter + 1;
               end if;
            end loop;
            stage_cvgCount(STAGE_INPUT) <= cvgCounter;
            
            -- synthesis translate_off
            stage_cvg16(STAGE_INPUT)     <= pipeIn_cvg16;
            stage_colorFull(STAGE_INPUT) <= pipeInColorFull;
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
            stage_cvg16(STAGE_COMBINER)     <= stage_cvg16(STAGE_INPUT);
            stage_colorFull(STAGE_COMBINER) <= stage_colorFull(STAGE_INPUT);
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
            stage_cvg16(STAGE_BLENDER)     <= stage_cvg16(STAGE_COMBINER);
            stage_colorFull(STAGE_BLENDER) <= stage_colorFull(STAGE_COMBINER);
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
            
            -- todo: should be part of blend color
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
            
            export_pipeO.addr   <= resize(stage_offX(STAGE_OUTPUT - 1), 32);
            export_pipeO.data   <= resize(stage_offY(STAGE_OUTPUT - 1), 64);
            export_pipeO.x      <= resize(stage_x(STAGE_OUTPUT - 1), 16);
            export_pipeO.y      <= resize(stage_y(STAGE_OUTPUT - 1), 16);
            export_pipeO.debug1 <= stage_cvg16(STAGE_OUTPUT - 1) & resize(stage_cvgValue(STAGE_OUTPUT - 1), 16);
            export_pipeO.debug2 <= resize(stage_cvgCount(STAGE_OUTPUT - 1), 32);
            export_pipeO.debug3 <= 31x"0" & stage_cvgValue(STAGE_OUTPUT - 1)(7);            
            
            export_Color.addr   <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(3));
            export_Color.data   <= (others => '0');
            export_Color.x      <= resize(stage_x(STAGE_OUTPUT - 1), 16);
            export_Color.y      <= resize(stage_y(STAGE_OUTPUT - 1), 16);
            export_Color.debug1 <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(0));
            export_Color.debug2 <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(1));
            export_Color.debug3 <= unsigned(stage_colorFull(STAGE_OUTPUT - 1)(2));
            -- synthesis translate_on

         end if;
      end if;
   end process;
   
   iRDP_CombineColor : entity work.RDP_CombineColor
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
      
      errorCombine            => errorCombine,
   
      settings_otherModes     => settings_otherModes,
      settings_combineMode    => settings_combineMode,
      
      pipeInColor             => pipeInColor,
     
      combine_color           => combine_color
   );
   
   iRDP_BlendColor : entity work.RDP_BlendColor
   port map
   (
      clk1x                   => clk1x,
      trigger                 => pipeIn_trigger,
   
      settings_otherModes     => settings_otherModes,
      settings_blendcolor     => settings_blendcolor,
      
      combine_color           => combine_color,
      
      blender_color           => blender_color
   );

end architecture;





