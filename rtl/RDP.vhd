library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use STD.textio.all;

library mem;
use work.pFunctions.all;
use work.pRDP.all;

entity RDP is
   port 
   (
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      command_error        : out std_logic;
      errorCombine         : out std_logic;
      error_combineAlpha   : out std_logic;
      
      write9               : in  std_logic;
      read9                : in  std_logic;
      wait9                : in  std_logic;
            
      irq_out              : out std_logic := '0';
            
      bus_addr             : in  unsigned(19 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done             : out std_logic := '0';
            
      rdram_request        : out std_logic := '0';
      rdram_rnw            : out std_logic := '0'; 
      rdram_address        : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount     : out unsigned(9 downto 0):= (others => '0');
      rdram_writeMask      : out std_logic_vector(7 downto 0) := (others => '0'); 
      rdram_dataWrite      : out std_logic_vector(63 downto 0) := (others => '0');
      rdram_granted        : in  std_logic;
      rdram_done           : in  std_logic;
      ddr3_DOUT            : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY      : in  std_logic;
            
      fifoout_reset        : out std_logic := '0'; 
      fifoout_Din          : out std_logic_vector(91 downto 0) := (others => '0'); -- 64bit data + 20 bit address + 8 byte enables
      fifoout_Wr           : out std_logic := '0';  
      fifoout_nearfull     : in  std_logic;   
      fifoout_empty        : in  std_logic;  
      
      sdram_request        : out std_logic := '0';
      sdram_rnw            : out std_logic := '0'; 
      sdram_address        : out unsigned(26 downto 0):= (others => '0');
      sdram_burstcount     : out unsigned(7 downto 0):= (others => '0');
      sdram_writeMask      : out std_logic_vector(3 downto 0) := (others => '0'); 
      sdram_dataWrite      : out std_logic_vector(31 downto 0) := (others => '0');
      sdram_granted        : in  std_logic;
      sdram_done           : in  std_logic;
      sdram_dataRead       : in  std_logic_vector(31 downto 0);
      sdram_valid          : in  std_logic;
      
      rdp9fifo_reset       : out std_logic := '0'; 
      rdp9fifo_Din         : out std_logic_vector(49 downto 0) := (others => '0'); -- 32bit data + 18 bit address
      rdp9fifo_Wr          : out std_logic := '0';  
      rdp9fifo_nearfull    : in  std_logic;  
      rdp9fifo_empty       : in  std_logic;
            
      RSP_RDP_reg_addr     : in  unsigned(4 downto 0);
      RSP_RDP_reg_dataOut  : in  unsigned(31 downto 0);
      RSP_RDP_reg_read     : in  std_logic;
      RSP_RDP_reg_write    : in  std_logic;
      RSP_RDP_reg_dataIn   : out unsigned(31 downto 0) := (others => '0'); 
      
      RSP2RDP_rdaddr       : out unsigned(11 downto 0) := (others => '0'); 
      RSP2RDP_len          : out unsigned(4 downto 0) := (others => '0'); 
      RSP2RDP_req          : out std_logic := '0';
      RSP2RDP_wraddr       : in  unsigned(4 downto 0);
      RSP2RDP_data         : in  std_logic_vector(63 downto 0);
      RSP2RDP_we           : in  std_logic;
      RSP2RDP_done         : in  std_logic;
      
      -- synthesis translate_off
      commandIsIdle_out    : out std_logic;
      -- synthesis translate_on
      
      SS_reset             : in  std_logic;
      SS_DataWrite         : in  std_logic_vector(63 downto 0);
      SS_Adr               : in  unsigned(0 downto 0);
      SS_wren              : in  std_logic;
      SS_rden              : in  std_logic;
      SS_DataRead          : out std_logic_vector(63 downto 0);
      SS_idle              : out std_logic
   );
end entity;

architecture arch of RDP is

   signal DPC_START_NEXT            : unsigned(23 downto 0) := (others => '0'); -- 0x04100000 (RW): [23:0] DMEM/RDRAM start address
   signal DPC_END_NEXT              : unsigned(23 downto 0) := (others => '0'); -- 0x04100004 (RW): [23:0] DMEM/RDRAM end address
   signal DPC_CURRENT               : unsigned(23 downto 0) := (others => '0'); -- 0x04100008 (R): [23:0] DMEM/RDRAM current address
   signal DPC_STATUS_xbus_dmem_dma  : std_logic := '0';
   signal DPC_STATUS_freeze         : std_logic := '0';
   signal DPC_STATUS_flush          : std_logic := '0';
   signal DPC_STATUS_start_gclk     : std_logic := '0';
   signal DPC_STATUS_cbuf_ready     : std_logic := '0';
   signal DPC_STATUS_dma_busy       : std_logic := '0';
   signal DPC_STATUS_end_pending    : std_logic := '0';
   signal DPC_STATUS_start_pending  : std_logic := '0';
   signal DPC_CLOCK                 : unsigned(23 downto 0) := (others => '0'); -- 0x04100010 (R): [23:0] clock counter
   signal DPC_BUFBUSY               : unsigned(23 downto 0) := (others => '0'); -- 0x04100014 (R): [23:0] clock counter
   signal DPC_PIPEBUSY              : unsigned(23 downto 0) := (others => '0'); -- 0x04100018 (R): [23:0] clock counter
   signal DPC_TMEM                  : unsigned(23 downto 0) := (others => '0'); -- 0x0410001C (R): [23:0] clock counter

   -- bus/mem multiplexing
   signal bus_read_latched          : std_logic := '0';
   signal bus_write_latched         : std_logic := '0';
   signal reg_addr                  : unsigned(19 downto 0); 
   signal reg_dataWrite             : std_logic_vector(31 downto 0);

   -- Command RAM
   signal DPC_END                   : unsigned(23 downto 0) := (others => '0');
   
   signal RDRAM_fillAddr            : unsigned(9 downto 0) := (others => '0');
   signal SDRAM_fillAddr            : unsigned(7 downto 0) := (others => '0');
   
   signal commandRAMstore           : std_logic := '0';
   signal commandRAMReady           : std_logic := '0';
   signal commandRAMMux             : std_logic := '0';
   signal CommandData_RAM           : std_logic_vector(63 downto 0);
   signal CommandData_RSP           : std_logic_vector(63 downto 0);
   signal CommandData               : std_logic_vector(63 downto 0);
   signal commandCntNext            : unsigned(4 downto 0) := (others => '0');
   signal commandRAMPtr             : unsigned(4 downto 0);
   signal commandIsIdle             : std_logic;
   signal commandWordDone           : std_logic;
   signal commandSyncFull           : std_logic;
   
   -- Texture request ram
   signal TextureReqRAMreq          : std_logic;
   signal TextureReqRAMaddr         : unsigned(25 downto 0);
   signal TextureReqRAMstore        : std_logic := '0';
   signal TextureReqRAMReady        : std_logic := '0';
   signal TextureReqRAMData         : std_logic_vector(63 downto 0);
   signal TextureReqRAMPtr          : unsigned(4 downto 0);
   
   -- Framebuffer request
   signal FBreq                     : std_logic;
   signal FBRAMgrant                : std_logic;
   signal rdram_finished            : std_logic;
   signal sdram_finished            : std_logic;
   signal FB_req_addr               : unsigned(25 downto 0);
   signal FBaddr                    : unsigned(25 downto 0);
   signal FBodd                     : std_logic;
   signal FBdone                    : std_logic := '0';
   signal FBRAMstore                : std_logic := '0';
   signal FBRAM9store               : std_logic := '0';
   signal FBReadAddr                : unsigned(10 downto 0);
   signal FBReadAddr9               : unsigned(7 downto 0);
   signal FBReadData                : std_logic_vector(31 downto 0);
   signal FBReadData9               : std_logic_vector(31 downto 0);
   
   type tmemState is 
   (  
      MEMIDLE, 
      WAITCOMMANDDATA,
      WAITTEXTUREDATA,
      WAITFBDATA
   ); 
   signal memState  : tmemState := MEMIDLE;

   -- Command Eval    
   signal settings_poly             : tsettings_poly;
   signal poly_start                : std_logic;
   signal poly_loading_mode         : std_logic;
   signal poly_done                 : std_logic;
   signal settings_scissor          : tsettings_scissor;
   signal settings_otherModes       : tsettings_otherModes;
   signal settings_fillcolor        : tsettings_fillcolor;
   signal settings_fogcolor         : tsettings_fogcolor;
   signal settings_blendcolor       : tsettings_blendcolor;
   signal settings_primcolor        : tsettings_primcolor;
   signal settings_envcolor         : tsettings_envcolor;
   signal settings_combineMode      : tsettings_combineMode;
   signal settings_colorImage       : tsettings_colorImage;
   signal settings_textureImage     : tsettings_textureImage;
   signal settings_tile             : tsettings_tile;
   signal settings_loadtype         : tsettings_loadtype;
   
   -- Texture RAM
   signal TextureRamAddr            : unsigned(7 downto 0) := (others => '0');    
   signal TextureRam0Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam1Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam2Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam3Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam4Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam5Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam6Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam7Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRamWE              : std_logic_vector(7 downto 0)  := (others => '0');
   signal TextureRamDataIn          : tTextureRamData;
   signal TextureReadData           : tTextureRamData;
   signal TextureReadAddr           : unsigned(11 downto 0) := (others => '0');    
   
   -- Fill line
   signal stall_raster              : std_logic := '0';
   
   signal fillWrite                 : std_logic;
   signal fillBE                    : unsigned(7 downto 0);
   signal fillColor                 : unsigned(63 downto 0);
   signal fillAddr                  : unsigned(25 downto 0) := (others => '0');
   signal fillX                     : unsigned(11 downto 0) := (others => '0');
   signal fillY                     : unsigned(11 downto 0) := (others => '0');

   -- pipeline
   signal pipe_busy                 : std_logic;
   
   signal pipeIn_trigger            : std_logic;
   signal pipeIn_valid              : std_logic;
   signal pipeIn_Addr               : unsigned(25 downto 0);
   signal pipeIn_xIndexPx           : unsigned(11 downto 0);
   signal pipeIn_xIndex9            : unsigned(11 downto 0);
   signal pipeIn_X                  : unsigned(11 downto 0);
   signal pipeIn_Y                  : unsigned(11 downto 0);
   signal pipeIn_cvgValue           : unsigned(7 downto 0);
   signal pipeIn_offX               : unsigned(1 downto 0);
   signal pipeIn_offY               : unsigned(1 downto 0);
   signal pipeInColor               : tcolor4_s16;
   signal pipeIn_S                  : signed(15 downto 0);
   signal pipeIn_T                  : signed(15 downto 0);
   signal pipeInWShift              : integer range 0 to 14;
   signal pipeInWNormLow            : unsigned(7 downto 0);
   signal pipeInWtemppoint          : signed(15 downto 0);
   signal pipeInWtempslope          : unsigned(7 downto 0);
   
   signal writePixel                : std_logic;
   signal writePixelAddr            : unsigned(25 downto 0);
   signal writePixelX               : unsigned(11 downto 0);
   signal writePixelY               : unsigned(11 downto 0);
   signal writePixelColor           : tcolor3_u8;
   signal writePixelCvg             : unsigned(2 downto 0);
   signal writePixelFBData9         : unsigned(31 downto 0);
   
   signal writePixelData16          : unsigned(15 downto 0);
   signal writePixelData32          : unsigned(31 downto 0);

   -- Pixel merging
   signal pixel64data               : std_logic_vector(63 downto 0) := (others => '0');
   signal pixel64BE                 : std_logic_vector(7 downto 0) := (others => '0');
   signal pixel64addr               : std_logic_vector(19 downto 0) := (others => '0');
   signal pixel64filled             : std_logic := '0';
   signal pixel64timeout            : integer range 0 to 15;
   
   -- Bit 9 writing
   signal pixel9data                : std_logic_vector(31 downto 0) := (others => '0');
   signal pixel9addr                : std_logic_vector(17 downto 0) := (others => '0');
   signal pixel9filled              : std_logic := '0';

   -- savestates
   type t_ssarray is array(0 to 1) of unsigned(63 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
   signal ss_out : t_ssarray := (others => (others => '0')); 

   --export
   -- synthesis translate_off
   signal export_command_done       : std_logic; 
   signal export_command_array      : rdp_export_type;
   
   signal export_line_done          : std_logic; 
   signal export_line_list          : rdp_export_type; 
   
   signal export_load_done          : std_logic; 
   signal export_loadFetch          : rdp_export_type; 
   signal export_loadData           : rdp_export_type; 
   signal export_loadValue          : rdp_export_type; 
   
   signal export_pipeDone           : std_logic;       
   signal export_pipeO              : rdp_export_type;
   signal export_Color              : rdp_export_type;
   signal export_LOD                : rdp_export_type;
   signal export_TexCoord           : rdp_export_type;
   signal export_TexFetch           : rdp_export_type;
   signal export_TexColor           : rdp_export_type;
   signal export_Comb               : rdp_export_type;
   signal export_FBMem              : rdp_export_type;
   
   signal pipeIn_cvg16              : unsigned(15 downto 0);
   signal pipeInColorFull           : tcolor4_s32;
   signal pipeInSTWZ                : tcolor4_s32;
   -- synthesis translate_on   

begin 

   reg_addr      <= 15x"0" & RSP_RDP_reg_addr when (RSP_RDP_reg_read = '1' or RSP_RDP_reg_write = '1') else bus_addr;     
   reg_dataWrite <= std_logic_vector(RSP_RDP_reg_dataOut) when (RSP_RDP_reg_write = '1') else bus_dataWrite;

   rdram_rnw <= '1';
   
   FB_req_addr <= settings_colorImage.FB_base + FBaddr;

   process (clk1x)
      variable var_dataRead         : std_logic_vector(31 downto 0) := (others => '0');
      variable rdram_finished_new   : std_logic;
      variable sdram_finished_new   : std_logic;
   begin
      if rising_edge(clk1x) then
      
         irq_out             <= '0';
         RSP2RDP_req         <= '0';
         rdram_request       <= '0';
         sdram_request       <= '0';
         TextureReqRAMReady  <= '0';
         FBdone              <= '0';
      
         if (reset = '1') then
            
            bus_done                 <= '0';
            
            DPC_START_NEXT           <= ss_in(0)(23 downto 0); --(others => '0');
            DPC_END_NEXT             <= ss_in(0)(47 downto 24); --(others => '0');
            DPC_CURRENT              <= ss_in(1)(23 downto 0); --(others => '0');
            DPC_STATUS_xbus_dmem_dma <= ss_in(0)(48); --'0';
            DPC_STATUS_freeze        <= ss_in(0)(49); --'0';
            DPC_STATUS_flush         <= ss_in(0)(50); --'0';
            DPC_STATUS_start_gclk    <= ss_in(0)(51); --'0';
            DPC_STATUS_cbuf_ready    <= ss_in(0)(52); --'1';
            DPC_STATUS_dma_busy      <= ss_in(0)(53); --'0';
            DPC_STATUS_end_pending   <= ss_in(0)(54); --'0';
            DPC_STATUS_start_pending <= ss_in(0)(55); --'0';
            DPC_CLOCK                <= (others => '0');
            DPC_BUFBUSY              <= (others => '0');
            DPC_PIPEBUSY             <= (others => '0');
            DPC_TMEM                 <= (others => '0');
            
            bus_read_latched         <= '0';
            bus_write_latched        <= '0';
            
            DPC_END                  <= ss_in(0)(47 downto 24); --(others => '0');
            commandRAMReady          <= '0';
            memState                 <= MEMIDLE;
            
         else
            if (ce = '1') then
         
               bus_done     <= '0';
               bus_dataRead <= (others => '0');
   
               if (commandSyncFull = '1') then
                  irq_out               <= '1';
                  DPC_BUFBUSY           <= (others => '0');
                  DPC_PIPEBUSY          <= (others => '0');
                  DPC_STATUS_start_gclk <= '0';
               end if;
   
   
               -- bus read
               if (bus_read = '1') then
                  bus_read_latched <= '1';
               end if;
               
               var_dataRead := (others => '0');
               case (reg_addr(19 downto 0)) is   
                  when x"00000" => var_dataRead(23 downto 0) := std_logic_vector(DPC_START_NEXT);  
                  when x"00004" => var_dataRead(23 downto 0) := std_logic_vector(DPC_END_NEXT);
                  when x"00008" => var_dataRead(23 downto 0) := std_logic_vector(DPC_CURRENT);
                  when x"0000C" =>
                     var_dataRead(0)  := DPC_STATUS_xbus_dmem_dma;
                     var_dataRead(1)  := DPC_STATUS_freeze;
                     var_dataRead(2)  := DPC_STATUS_flush;
                     var_dataRead(3)  := DPC_STATUS_start_gclk;
                     if (DPC_TMEM > 0) then var_dataRead(4)      := '1'; end if;
                     if (DPC_PIPEBUSY > 0) then var_dataRead(5)  := '1'; end if;
                     --if (DPC_BUFBUSY > 0) then var_dataRead(6)  := '1'; end if;
                     var_dataRead(7)  := DPC_STATUS_cbuf_ready;
                     var_dataRead(8)  := DPC_STATUS_dma_busy;
                     var_dataRead(9)  := DPC_STATUS_end_pending;
                     var_dataRead(10) := DPC_STATUS_start_pending;
                  
                  when x"00010" => var_dataRead(23 downto 0) := std_logic_vector(DPC_CLOCK);  
                  when x"00014" => var_dataRead(23 downto 0) := std_logic_vector(DPC_BUFBUSY);  
                  when x"00018" => var_dataRead(23 downto 0) := std_logic_vector(DPC_PIPEBUSY);  
                  when x"0001C" => var_dataRead(23 downto 0) := std_logic_vector(DPC_TMEM);  
                  when others   => null;             
               end case;
               
               if (bus_read_latched = '1' and RSP_RDP_reg_read = '0') then
                  bus_done         <= '1';
                  bus_dataRead     <= var_dataRead;
                  bus_read_latched <= '0';
               end if;
               
               RSP_RDP_reg_dataIn <= unsigned(var_dataRead);
               
               -- bus write
               if (bus_write = '1') then
                  bus_write_latched <= '1';
               end if;
               
               if (commandWordDone = '1') then
                  DPC_CURRENT   <= DPC_CURRENT + 8;
               end if;
               
               if (bus_write_latched = '1' or RSP_RDP_reg_write = '1') then
               
                  if (bus_write_latched = '1' and RSP_RDP_reg_write = '0') then
                     bus_write_latched <= '0';
                     bus_done          <= '1';
                  end if;
                  
                  case (reg_addr(19 downto 0)) is
                     when x"00000" =>
                        if (DPC_STATUS_start_pending = '0') then -- wrong according to n64brew, should always update, systemtest proves otherwise!
                           DPC_START_NEXT <= unsigned(reg_dataWrite(23 downto 3)) & "000";
                        end if;
                        DPC_STATUS_start_pending <= '1';
                     
                     when x"00004" => 
                        DPC_END_NEXT <= unsigned(reg_dataWrite(23 downto 3)) & "000";
                        
                        if (DPC_STATUS_start_pending = '0') then
                           DPC_STATUS_dma_busy <= '1';
                           DPC_END             <= unsigned(reg_dataWrite(23 downto 3)) & "000";
                        else
                           if (DPC_STATUS_dma_busy = '0') then
                              DPC_STATUS_start_pending <= '0';
                              DPC_STATUS_dma_busy      <= '1';
                              DPC_CURRENT              <= DPC_START_NEXT;
                              DPC_END                  <= unsigned(reg_dataWrite(23 downto 3)) & "000";
                           else
                              DPC_STATUS_end_pending <= '1';
                           end if;
                        end if;
                        
                        if (DPC_STATUS_freeze = '0') then
                           DPC_STATUS_start_gclk <= '1';
                           DPC_BUFBUSY           <= x"000001"; -- hack
                           DPC_PIPEBUSY          <= x"000001"; -- hack
                        end if;
                     
                     when x"0000C" => 
                        if (reg_dataWrite(0) = '1') then DPC_STATUS_xbus_dmem_dma <= '0'; end if;
                        if (reg_dataWrite(1) = '1') then DPC_STATUS_xbus_dmem_dma <= '1'; end if;
                        if (reg_dataWrite(2) = '1') then 
                           DPC_STATUS_freeze     <= '0'; 
                           DPC_STATUS_start_gclk <= '1';
                           DPC_BUFBUSY           <= x"000001"; -- hack
                           DPC_PIPEBUSY          <= x"000001"; -- hack
                        end if;
                        if (reg_dataWrite(3) = '1') then DPC_STATUS_freeze        <= '1'; end if;
                        if (reg_dataWrite(4) = '1') then DPC_STATUS_flush         <= '0'; end if;
                        if (reg_dataWrite(5) = '1') then DPC_STATUS_flush         <= '1'; end if;
                        if (reg_dataWrite(6) = '1') then DPC_TMEM     <= (others => '0'); end if;
                        if (reg_dataWrite(7) = '1') then DPC_PIPEBUSY <= (others => '0'); end if;
                        if (reg_dataWrite(8) = '1') then DPC_BUFBUSY  <= (others => '0'); end if;
                        if (reg_dataWrite(9) = '1') then DPC_CLOCK    <= (others => '0'); end if;
                     
                     when others   => null; 

                  end case;
                  
               elsif (DPC_STATUS_dma_busy = '1' and DPC_CURRENT = DPC_END) then
               
                  if (DPC_STATUS_end_pending = '1') then
                     DPC_STATUS_start_pending <= '0';
                     DPC_STATUS_end_pending   <= '0';
                     DPC_CURRENT              <= DPC_START_NEXT;
                     DPC_END                  <= DPC_END_NEXT;
                  else
                     DPC_STATUS_dma_busy <= '0';
                  end if;
                  
               end if;

            end if; -- ce
         
         end if; -- no reset
            
         -- memory statemachine
         case (memState) is
         
            when MEMIDLE =>
               if (TextureReqRAMreq = '1') then
                  memState          <= WAITTEXTUREDATA;
                  rdram_request     <= '1';
                  rdram_address     <= "00" & TextureReqRAMaddr;
                  rdram_burstcount  <= to_unsigned(32, 10);
               elsif (FBreq = '1') then
                  memState          <= WAITFBDATA;
                  FBRAMgrant        <= '0';
                  rdram_finished    <= '0';
                  sdram_finished    <= (not wait9) or (not read9); --'0';
                  
                  rdram_request     <= '1';
                  rdram_address     <= "00" & FB_req_addr(25 downto 3) & "000";
                  rdram_burstcount  <= to_unsigned(65, 10);
                  
                  sdram_request     <= read9; --'1';
                  sdram_address     <= 7x"0" & FB_req_addr(22 downto 5) & "00";
                  sdram_burstcount  <= to_unsigned(17, 8);
                  
               elsif (DPC_STATUS_freeze = '0' and commandRAMReady = '0' and commandIsIdle = '1' and commandWordDone = '0' and DPC_STATUS_dma_busy = '1') then
                  if (DPC_CURRENT < DPC_END) then
                     memState          <= WAITCOMMANDDATA;
                     commandRAMMux     <= DPC_STATUS_xbus_dmem_dma;
                     RSP2RDP_req       <= DPC_STATUS_xbus_dmem_dma;
                     rdram_request     <= not DPC_STATUS_xbus_dmem_dma;
                     RSP2RDP_rdaddr    <= DPC_CURRENT(11 downto 0);
                     rdram_address     <= x"0" & DPC_CURRENT;
                     if ((DPC_END(23 downto 3) - DPC_CURRENT(23 downto 3)) > 22) then
                        commandCntNext    <= to_unsigned(22, 5);
                        rdram_burstcount  <= to_unsigned(22, 10); -- max length for tri with all options on
                     else
                        commandCntNext    <= resize(DPC_END(23 downto 3) - DPC_CURRENT(23 downto 3), 5);
                        rdram_burstcount  <= "00000" & resize(DPC_END(23 downto 3) - DPC_CURRENT(23 downto 3), 5);
                     end if;
                     -- synthesis translate_off
                     export_command_array.addr <= x"00" & DPC_CURRENT;
                     -- synthesis translate_on
                  end if;
               end if;
               
            when WAITCOMMANDDATA =>
               if (rdram_done = '1' or RSP2RDP_done = '1') then
                  commandRAMReady   <= '1';
                  memState          <= MEMIDLE;
               end if;
               
            when WAITTEXTUREDATA =>
               if (rdram_done = '1') then
                  TextureReqRAMReady   <= '1';
                  memState             <= MEMIDLE;
               end if;            
               
            when WAITFBDATA =>
               rdram_finished_new := rdram_finished;
               sdram_finished_new := sdram_finished;
               if (rdram_granted = '1') then FBRAMgrant <= '1'; end if;
               if (rdram_done = '1' and FBRAMgrant = '1')  then rdram_finished_new := '1'; end if;
               if (sdram_done = '1' and FBRAM9store = '1') then sdram_finished_new := '1'; end if;
               rdram_finished <= rdram_finished_new;
               sdram_finished <= sdram_finished_new;
               
               if (rdram_finished_new = '1' and sdram_finished_new = '1') then
                  FBdone   <= '1';
                  memState <= MEMIDLE;
               end if;
         
         end case;
  
         if (commandIsIdle = '1' and commandRAMReady = '1') then
            commandRAMReady <= '0';
         end if;

      end if;
   end process;
   
   RSP2RDP_len <= commandCntNext;
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         
         if (rdram_granted = '1') then
            RDRAM_fillAddr <= (others => '0');
            if (memState = WAITCOMMANDDATA) then
               commandRAMstore <= '1';
            elsif (memState = WAITTEXTUREDATA) then
               TextureReqRAMstore <= '1';            
            elsif (memState = WAITFBDATA) then
               FBRAMstore       <= '1';
               RDRAM_fillAddr(9) <= FBodd;
            end if;
         elsif (ddr3_DOUT_READY = '1') then
            RDRAM_fillAddr(8 downto 0) <= RDRAM_fillAddr(8 downto 0) + 1;
         end if;
         
         if (rdram_done = '1') then
            commandRAMstore    <= '0';
            TextureReqRAMstore <= '0';
            FBRAMstore         <= '0';
         end if;
         
      end if;
   end process; 
   
   iCommandRAM: entity mem.dpram
   generic map 
   ( 
      addr_width  => 5,
      data_width  => 64
   )
   port map
   (
      clock_a     => clk2x,
      address_a   => std_logic_vector(RDRAM_fillAddr(4 downto 0)),
      data_a      => byteswap64(ddr3_DOUT),
      wren_a      => (ddr3_DOUT_READY and commandRAMstore),
      
      clock_b     => clk1x,
      address_b   => std_logic_vector(commandRAMPtr),
      data_b      => 64x"0",
      wren_b      => '0',
      q_b         => CommandData_RAM
   );   
   
   iCommandRSP: entity mem.dpram
   generic map 
   ( 
      addr_width  => 5,
      data_width  => 64
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => std_logic_vector(RSP2RDP_wraddr),
      data_a      => RSP2RDP_data,
      wren_a      => RSP2RDP_we,
      
      clock_b     => clk1x,
      address_b   => std_logic_vector(commandRAMPtr),
      data_b      => 64x"0",
      wren_b      => '0',
      q_b         => CommandData_RSP
   );   
   
   CommandData <= CommandData_RSP when (commandRAMMux = '1') else CommandData_RAM;
   
   iRDP_command : entity work.RDP_command
   port map
   (
      clk1x                   => clk1x,          
      reset                   => reset,          
   
      error                   => command_error,
                                          
      commandRAMReady         => commandRAMReady,
      CommandData             => unsigned(CommandData),    
      commandCntNext          => commandCntNext, 
                                                
      commandRAMPtr_out       => commandRAMPtr,  
      commandIsIdle           => commandIsIdle,  
      commandWordDone         => commandWordDone,
         
      poly_done               => poly_done,       
      settings_poly           => settings_poly,       
      poly_start              => poly_start,     
      poly_loading_mode       => poly_loading_mode,     
      sync_full               => commandSyncFull,     

      -- synthesis translate_off
      export_command_done     => export_command_done, 
      -- synthesis translate_on      
                              
      settings_scissor        => settings_scissor,   
      settings_otherModes     => settings_otherModes, 
      settings_fillcolor      => settings_fillcolor,  
      settings_fogcolor       => settings_fogcolor, 
      settings_blendcolor     => settings_blendcolor, 
      settings_primcolor      => settings_primcolor, 
      settings_envcolor       => settings_envcolor, 
      settings_combineMode    => settings_combineMode,
      settings_textureImage   => settings_textureImage,
      settings_colorImage     => settings_colorImage,
      settings_tile           => settings_tile,      
      settings_loadtype       => settings_loadtype      
   );
   
   -- synthesis translate_off
   commandIsIdle_out <= commandIsIdle;
   -- synthesis translate_on
   
   iTextureReceiveRAM: entity mem.dpram
   generic map 
   ( 
      addr_width  => 5,
      data_width  => 64
   )
   port map
   (
      clock_a     => clk2x,
      address_a   => std_logic_vector(RDRAM_fillAddr(4 downto 0)),
      data_a      => byteswap64(ddr3_DOUT),
      wren_a      => (ddr3_DOUT_READY and TextureReqRAMstore),
      
      clock_b     => clk1x,
      address_b   => std_logic_vector(textureReqRAMPtr),
      data_b      => 64x"0",
      wren_b      => '0',
      q_b         => TextureReqRAMData
   );
   
   iRDP_raster : entity work.RDP_raster
   port map
   (
      clk1x                   => clk1x,        
      reset                   => reset,       

      stall_raster            => stall_raster,
                              
      settings_poly           => settings_poly,      
      settings_scissor        => settings_scissor,   
      settings_otherModes     => settings_otherModes, 
      settings_fillcolor      => settings_fillcolor,  
      settings_colorImage     => settings_colorImage, 
      settings_textureImage   => settings_textureImage,
      settings_tile           => settings_tile,    
      settings_loadtype       => settings_loadtype,    
      poly_start              => poly_start,   
      loading_mode            => poly_loading_mode,
      poly_done               => poly_done,
      
      TextureReqRAMreq        => TextureReqRAMreq,   
      TextureReqRAMaddr       => TextureReqRAMaddr,  
      TextureReqRAMPtr        => TextureReqRAMPtr,   
      TextureReqRAMData       => TextureReqRAMData,  
      TextureReqRAMReady      => TextureReqRAMReady, 
      
      TextureRamAddr          => TextureRamAddr, 
      TextureRam0Data         => TextureRam0Data,
      TextureRam1Data         => TextureRam1Data,
      TextureRam2Data         => TextureRam2Data,
      TextureRam3Data         => TextureRam3Data,
      TextureRam4Data         => TextureRam4Data,
      TextureRam5Data         => TextureRam5Data,
      TextureRam6Data         => TextureRam6Data,
      TextureRam7Data         => TextureRam7Data,
      TextureRamWE            => TextureRamWE,   
      
      FBreq                   => FBreq, 
      FBaddr                  => FBaddr,
      FBodd                   => FBodd, 
      FBdone                  => FBdone,
      
      -- synthesis translate_off
      export_line_done        => export_line_done,
      export_line_list        => export_line_list,
         
      export_load_done        => export_load_done,
      export_loadFetch        => export_loadFetch,
      export_loadData         => export_loadData, 
      export_loadValue        => export_loadValue,
      -- synthesis translate_on
      
      pipe_busy               => pipe_busy,
      
      pipeIn_trigger          => pipeIn_trigger,
      pipeIn_valid            => pipeIn_valid,  
      pipeIn_Addr             => pipeIn_Addr,   
      pipeIn_xIndexPx         => pipeIn_xIndexPx,      
      pipeIn_xIndex9          => pipeIn_xIndex9,      
      pipeIn_X                => pipeIn_X,      
      pipeIn_Y                => pipeIn_Y, 
      pipeIn_cvgValue         => pipeIn_cvgValue, 
      pipeIn_offX             => pipeIn_offX, 
      pipeIn_offY             => pipeIn_offY, 
      pipeInColor             => pipeInColor, 
      pipeIn_S                => pipeIn_S,
      pipeIn_T                => pipeIn_T,
      pipeInWShift            => pipeInWShift,   
      pipeInWNormLow          => pipeInWNormLow, 
      pipeInWtemppoint        => pipeInWtemppoint,
      pipeInWtempslope        => pipeInWtempslope,

      -- synthesis translate_off
      pipeIn_cvg16            => pipeIn_cvg16, 
      pipeInColorFull         => pipeInColorFull,
      pipeInSTWZ              => pipeInSTWZ,
      -- synthesis translate_on

      fillWrite               => fillWrite,
      fillBE                  => fillBE,   
      fillColor               => fillColor,
      fillAddr                => fillAddr,
      fillX                   => fillX,   
      fillY                   => fillY   
   );
   
   TextureRamDataIn(0) <= TextureRam0Data;
   TextureRamDataIn(1) <= TextureRam1Data;
   TextureRamDataIn(2) <= TextureRam2Data;
   TextureRamDataIn(3) <= TextureRam3Data;
   TextureRamDataIn(4) <= TextureRam4Data;
   TextureRamDataIn(5) <= TextureRam5Data;
   TextureRamDataIn(6) <= TextureRam6Data;
   TextureRamDataIn(7) <= TextureRam7Data;
   
   gTextureRam: for i in 0 to 7 generate
   begin
   
      iTextureRAM: entity mem.dpram
      generic map 
      ( 
         addr_width  => 8,
         data_width  => 16
      )
      port map
      (
         clock_a     => clk1x,
         address_a   => std_logic_vector(TextureRamAddr),
         data_a      => TextureRamDataIn(i),
         wren_a      => TextureRamWE(i),
         
         clock_b     => clk1x,
         clken_b     => pipeIn_trigger,
         address_b   => std_logic_vector(TextureReadAddr(10 downto 3)),
         data_b      => 16x"0",
         wren_b      => '0',
         q_b         => TextureReadData(i)
      );
      
   end generate;
   
   iFBRAM: entity mem.dpram_dif
   generic map 
   ( 
      addr_width_a => 10,
      data_width_a => 64,
      addr_width_b => 11,
      data_width_b => 32
   )
   port map
   (
      clock_a     => clk2x,
      address_a   => std_logic_vector(RDRAM_fillAddr),
      data_a      => ddr3_DOUT,
      wren_a      => (ddr3_DOUT_READY and FBRAMstore),
      
      clock_b     => clk1x,
      clken_b     => pipeIn_trigger,
      address_b   => std_logic_vector(FBReadAddr),
      data_b      => 32x"0",
      wren_b      => '0',
      q_b         => FBReadData
   );
   
   iFBRAM9: entity mem.dpram_dif
   generic map 
   ( 
      addr_width_a => 8,
      data_width_a => 32,
      addr_width_b => 8,
      data_width_b => 32
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => std_logic_vector(SDRAM_fillAddr),
      data_a      => sdram_dataRead,
      wren_a      => (sdram_valid and FBRAM9store),
      
      clock_b     => clk1x,
      clken_b     => pipeIn_trigger,
      address_b   => std_logic_vector(FBReadAddr9),
      data_b      => 32x"0",
      wren_b      => '0',
      q_b         => FBReadData9
   );
   
   sdram_rnw       <= '1';  
   sdram_writeMask <= x"0";
   sdram_dataWrite <= (others => '0');
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         
         if (sdram_granted = '1') then
            SDRAM_fillAddr <= (others => '0');
            if (memState = WAITFBDATA) then
               FBRAM9store       <= '1';
               SDRAM_fillAddr(7) <= FBodd;
            end if;
         elsif (sdram_valid = '1') then
            SDRAM_fillAddr(6 downto 0) <= SDRAM_fillAddr(6 downto 0) + 1;
         end if;
         
         if (sdram_done = '1') then
            FBRAM9store <= '0';
         end if;
         
      end if;
   end process;

   iRDP_pipeline : entity work.RDP_pipeline
   port map
   (
      clk1x                   => clk1x,                
      reset                   => reset,   

      errorCombine            => errorCombine,
      error_combineAlpha      => error_combineAlpha,
      
      pipe_busy               => pipe_busy,
                                                      
      settings_poly           => settings_poly,  
      settings_otherModes     => settings_otherModes,  
      settings_fogcolor       => settings_fogcolor, 
      settings_blendcolor     => settings_blendcolor, 
      settings_primcolor      => settings_primcolor, 
      settings_envcolor       => settings_envcolor,  
      settings_colorImage     => settings_colorImage,  
      settings_textureImage   => settings_textureImage,
      settings_tile           => settings_tile,        
      settings_combineMode    => settings_combineMode,        
                                                      
      pipeIn_trigger          => pipeIn_trigger,
      pipeIn_valid            => pipeIn_valid,  
      pipeIn_Addr             => pipeIn_Addr,   
      pipeIn_xIndexPx         => pipeIn_xIndexPx,      
      pipeIn_xIndex9          => pipeIn_xIndex9,      
      pipeIn_X                => pipeIn_X,      
      pipeIn_Y                => pipeIn_Y,      
      pipeIn_cvgValue         => pipeIn_cvgValue,  
      pipeIn_offX             => pipeIn_offX,  
      pipeIn_offY             => pipeIn_offY,  
      pipeInColor             => pipeInColor,     
      pipeIn_S                => pipeIn_S,
      pipeIn_T                => pipeIn_T,    
      pipeInWShift            => pipeInWShift,   
      pipeInWNormLow          => pipeInWNormLow, 
      pipeInWtemppoint         => pipeInWtemppoint,
      pipeInWtempslope         => pipeInWtempslope,

      TextureAddr             => TextureReadAddr,
      TextureRamData          => TextureReadData,
      
      FBAddr                  => FBReadAddr,
      FBData                  => FBReadData,
      
      FBAddr9                 => FBReadAddr9,
      FBData9                 => FBReadData9,
     
      -- synthesis translate_off
      pipeIn_cvg16            => pipeIn_cvg16,  
      pipeInColorFull         => pipeInColorFull,
      pipeInSTWZ              => pipeInSTWZ,
      
      export_pipeDone         => export_pipeDone,
      export_pipeO            => export_pipeO,   
      export_Color            => export_Color,   
      export_LOD              => export_LOD,   
      export_TexCoord         => export_TexCoord,   
      export_TexFetch         => export_TexFetch,   
      export_TexColor         => export_TexColor,   
      export_Comb             => export_Comb,   
      export_FBMem            => export_FBMem,   
      -- synthesis translate_on
      
      writePixel              => writePixel,     
      writePixelAddr          => writePixelAddr,    
      writePixelX             => writePixelX,    
      writePixelY             => writePixelY,   
      writePixelColor         => writePixelColor,
      writePixelCvg           => writePixelCvg,
      writePixelFBData9       => writePixelFBData9
   );
   
   writePixelData16 <= writePixelColor(0)(7 downto 3) & writePixelColor(1)(7 downto 3) & writePixelColor(2)(7 downto 3) & writePixelCvg(2);
   writePixelData32 <= writePixelColor(0) & writePixelColor(1) & writePixelColor(2) & writePixelCvg & "00000";
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         stall_raster <= fifoout_nearfull or rdp9fifo_nearfull;
      
         --fifoOut_Wr_1 <= fifoOut_Wr; -- fifoOut_Wr_1 used for idle test
      
         fifoOut_Wr   <= '0';
         fifoOut_Din  <= pixel64BE & pixel64Addr & pixel64data;
         
         if (fillWrite = '1') then
         
            fifoOut_Wr   <= '1';
            fifoOut_Din(91 downto 84) <= std_logic_vector(fillBE sll to_integer(fillAddr(2 downto 0)));
            fifoOut_Din(83 downto 64) <= std_logic_vector(fillAddr(22 downto 3));
            fifoOut_Din(63 downto  0) <= std_logic_vector(fillColor);
         
         elsif (writePixel = '1' and writePixelAddr(25 downto 23) = 0) then -- todo: move max ram check to ddr3mux
         
            pixel64timeout <= 15;
         
            if (pixel64filled = '0' or writePixelAddr(22 downto 3) /= unsigned(pixel64Addr)) then
               fifoOut_Wr  <= pixel64filled;
               pixel64Addr <= std_logic_vector(writePixelAddr(22 downto 3));
               pixel64BE   <= (others => '0');
               pixel64filled <= '1';
            end if;
            
            if (settings_colorImage.FB_size = SIZE_16BIT) then
               case (writePixelAddr(2 downto 1)) is
                  when "00" => pixel64data(15 downto  0) <= std_logic_vector(byteswap16(writePixelData16)); pixel64BE(1 downto 0) <= "11";
                  when "01" => pixel64data(31 downto 16) <= std_logic_vector(byteswap16(writePixelData16)); pixel64BE(3 downto 2) <= "11";
                  when "10" => pixel64data(47 downto 32) <= std_logic_vector(byteswap16(writePixelData16)); pixel64BE(5 downto 4) <= "11";
                  when "11" => pixel64data(63 downto 48) <= std_logic_vector(byteswap16(writePixelData16)); pixel64BE(7 downto 6) <= "11";
                  when others => null;
               end case;
            elsif (settings_colorImage.FB_size = SIZE_32BIT) then     
               case (writePixelAddr(2)) is
                  when '0' => pixel64data(31 downto  0) <= std_logic_vector(byteswap32(writePixelData32)); pixel64BE(3 downto 0) <= "1111";
                  when '1' => pixel64data(63 downto 32) <= std_logic_vector(byteswap32(writePixelData32)); pixel64BE(7 downto 4) <= "1111";
                  when others => null;
               end case;
            end if;
         
         elsif (pixel64timeout > 0) then
         
            pixel64timeout <= pixel64timeout - 1;
            if (pixel64timeout = 1) then
               pixel64filled  <= '0';
               fifoOut_Wr     <= '1';
               pixel64timeout <= 0;
            end if;
            
         end if;

      end if;
   end process;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         rdp9fifo_Wr   <= '0';
         rdp9fifo_Din  <= pixel9Addr & pixel9data;
         
         if (fillWrite = '1') then
         
            if (pixel9filled = '0' or fillAddr(22 downto 5) /= unsigned(pixel9Addr)) then
               rdp9fifo_Wr  <= pixel9filled and write9;
               pixel9Addr   <= std_logic_vector(fillAddr(22 downto 5));
               pixel9filled <= '1';
            end if;
            
            case (fillAddr(4 downto 3)) is
               when "00" => pixel9data( 7 downto  0) <= fillColor(56) & fillColor(56) & fillColor(40) & fillColor(40) & fillColor(24) & fillColor(24) & fillColor(8) & fillColor(8);
               when "01" => pixel9data(15 downto  8) <= fillColor(56) & fillColor(56) & fillColor(40) & fillColor(40) & fillColor(24) & fillColor(24) & fillColor(8) & fillColor(8);
               when "10" => pixel9data(23 downto 16) <= fillColor(56) & fillColor(56) & fillColor(40) & fillColor(40) & fillColor(24) & fillColor(24) & fillColor(8) & fillColor(8);
               when "11" => pixel9data(31 downto 24) <= fillColor(56) & fillColor(56) & fillColor(40) & fillColor(40) & fillColor(24) & fillColor(24) & fillColor(8) & fillColor(8);
               when others => null;
            end case;
         
         elsif (writePixel = '1' and writePixelAddr(25 downto 23) = 0) then -- todo: move max ram check to ddr3mux
         
            if (pixel9filled = '0' or writePixelAddr(22 downto 5) /= unsigned(pixel9Addr)) then
               pixel9data   <= std_logic_vector(writePixelFBData9); -- must fill in old data because only 2 bits are updated, byte enable not possible
               rdp9fifo_Wr  <= pixel9filled and write9;
               pixel9Addr   <= std_logic_vector(writePixelAddr(22 downto 5));
               pixel9filled <= '1';
            end if;
            
            if (settings_colorImage.FB_size = SIZE_16BIT) then
               pixel9data((to_integer(writePixelAddr(4 downto 1)) * 2) + 1) <= writePixelCvg(1);
               pixel9data((to_integer(writePixelAddr(4 downto 1)) * 2) + 0) <= writePixelCvg(0);
            end if;
         
         elsif (poly_done = '1') then

            pixel9filled  <= '0';
            rdp9fifo_Wr   <= pixel9filled and write9;
            
         end if;

      end if;
   end process;
   
--##############################################################
--############################### savestates
--##############################################################

   SS_idle <= '1';

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (SS_reset = '1') then
         
            for i in 0 to 1 loop
               ss_in(i) <= (others => '0');
            end loop;
            
            ss_in(0)(52) <= '1'; -- DPC_STATUS_cbuf_ready = 1
            
         elsif (SS_wren = '1') then
            ss_in(to_integer(SS_Adr)) <= unsigned(SS_DataWrite);
         end if;
         
         if (SS_rden = '1') then
            SS_DataRead <= std_logic_vector(ss_out(to_integer(SS_Adr)));
         end if;
      
      end if;
   end process;
   
--##############################################################
--############################### export
--##############################################################
   
   -- synthesis translate_off
   goutput : if 1 = 1 generate
      type ttracecounts_out is array(0 to 29) of integer;
      signal tracecounts_out : ttracecounts_out;
   begin
   
      process
         file outfile               : text;
         variable f_status          : FILE_OPEN_STATUS;
         variable line_out          : line;
         variable stringbuffer      : string(1 to 31);
         variable export_fillAddr   : unsigned(25 downto 0);
         variable export_fillColor  : unsigned(63 downto 0);
         variable export_fillBE     : unsigned(7 downto 0);
         variable export_fillX      : unsigned(11 downto 0);
         variable export_fillIndex  : integer;
         variable useTexture        : std_logic;
      begin
   
         file_open(f_status, outfile, "R:\\rdp_n64_sim.txt", write_mode);
         file_close(outfile);
         file_open(f_status, outfile, "R:\\rdp_n64_sim.txt", append_mode);
         
         for i in 0 to 29 loop
            tracecounts_out(i) <= 0;
         end loop;
         
         while (true) loop
            
            wait until rising_edge(clk1x);
            
            if (export_command_done = '1') then
               write(line_out, string'("Command: I ")); 
               write(line_out, to_string_len(tracecounts_out(2) + 1, 8));
               write(line_out, string'(" A ")); 
               --write(line_out, to_hstring(export_command_array.addr + (commandRAMPtr - 1) * 8));
               write(line_out, to_hstring(to_unsigned(0, 32)));
               write(line_out, string'(" D "));
               write(line_out, to_hstring(CommandData));
               writeline(outfile, line_out);
               tracecounts_out(2) <= tracecounts_out(2) + 1;
            end if;
            
            --if (export_line_done = '1') then
            --   write(line_out, string'("LINE: I ")); 
            --   write(line_out, to_string_len(tracecounts_out(20) + 1, 8));
            --   write(line_out, string'(" A 00000000 D 00000000 X    0 Y ")); 
            --   write(line_out, to_string_len(to_integer(export_line_list.y), 4));
            --   write(line_out, string'(" D1 "));
            --   write(line_out, to_hstring(export_line_list.debug1));
            --   write(line_out, string'(" D2 "));
            --   write(line_out, to_hstring(export_line_list.debug2));
            --   write(line_out, string'(" D3 "));
            --   write(line_out, to_hstring(export_line_list.debug3));
            --   writeline(outfile, line_out);
            --   tracecounts_out(20) <= tracecounts_out(20) + 1;
            --end if;
            
            if (export_load_done = '1') then
               export_gpu32(16, tracecounts_out(16), export_loadFetch, outfile); tracecounts_out(16) <= tracecounts_out(16) + 1;
               export_gpu64(17, tracecounts_out(17), export_LoadData,  outfile); tracecounts_out(17) <= tracecounts_out(17) + 1;
               export_gpu32(18, tracecounts_out(18), export_LoadValue, outfile); tracecounts_out(18) <= tracecounts_out(18) + 1;
            end if;

            useTexture := '0';
            case (to_integer(settings_combineMode.combine_sub_a_R_1)) is  when 1 | 2 => useTexture := '1'; when others => null;  end case;
            case (to_integer(settings_combineMode.combine_sub_b_R_1)) is  when 1 | 2 => useTexture := '1'; when others => null;  end case;
            case (to_integer(settings_combineMode.combine_mul_R_1))   is  when 1 | 2 | 8 | 9 | 13 | 14 => useTexture := '1'; when others => null;  end case;
            case (to_integer(settings_combineMode.combine_add_R_1))   is  when 1 | 2 => useTexture := '1'; when others => null;  end case;
            case (to_integer(settings_combineMode.combine_sub_a_A_1)) is  when 1 | 2 => useTexture := '1'; when others => null;  end case;
            case (to_integer(settings_combineMode.combine_sub_b_A_1)) is  when 1 | 2 => useTexture := '1'; when others => null;  end case;
            case (to_integer(settings_combineMode.combine_mul_A_1))   is  when 1 | 2 | 6 => useTexture := '1'; when others => null;  end case;
            case (to_integer(settings_combineMode.combine_add_A_1))   is  when 1 | 2 => useTexture := '1'; when others => null;  end case;
            
            if (export_pipeDone = '1') then
               export_gpu32( 3, tracecounts_out( 3), export_pipeO,    outfile); tracecounts_out( 3) <= tracecounts_out( 3) + 1;
               export_gpu32( 4, tracecounts_out( 4), export_color,    outfile); tracecounts_out( 4) <= tracecounts_out( 4) + 1;
               if (useTexture = '1') then
                  export_gpu32(19, tracecounts_out(19), export_LOD,      outfile); tracecounts_out(19) <= tracecounts_out(19) + 1;
                  export_gpu32(11, tracecounts_out(11), export_TexCoord, outfile); tracecounts_out(11) <= tracecounts_out(11) + 1;
                  export_gpu32( 7, tracecounts_out( 7), export_TexFetch, outfile); tracecounts_out( 7) <= tracecounts_out( 7) + 1;
                  export_gpu32(13, tracecounts_out(13), export_TexColor, outfile); tracecounts_out(13) <= tracecounts_out(13) + 1;
               end if;
               export_gpu32(23, tracecounts_out(23), export_Comb    , outfile); tracecounts_out(23) <= tracecounts_out(23) + 1;
               if (settings_otherModes.imageRead = '1') then
                  export_gpu32(24, tracecounts_out(24), export_FBMem   , outfile); tracecounts_out(24) <= tracecounts_out(24) + 1;
               end if;
            end if;
            
            if (writePixel = '1') then
               write(line_out, string'("Pixel: I ")); 
               write(line_out, to_string_len(tracecounts_out(1) + 1, 8));
               write(line_out, string'(" A ")); 
               write(line_out, to_hstring(resize(writePixelAddr, 32)));
               write(line_out, string'(" D ")); 
               if (settings_colorImage.FB_size = SIZE_16BIT) then
                  write(line_out, to_hstring(x"0000" & writePixelData16));
               else
                  write(line_out, to_hstring(writePixelData32));
               end if;
               write(line_out, string'(" X ")); 
               write(line_out, to_string_len(to_integer(writePixelX), 4));
               write(line_out, string'(" Y ")); 
               write(line_out, to_string_len(to_integer(writePixelY), 4));
               write(line_out, string'(" D1 "));
               if (settings_colorImage.FB_size = SIZE_16BIT) then
                  write(line_out, to_hstring(to_unsigned(0, 30) & writePixelCvg(1 downto 0)));
               else
                  write(line_out, to_hstring(to_unsigned(0, 32)));
               end if;
               write(line_out, string'(" D2 "));
               write(line_out, to_hstring(to_unsigned(0, 32)));
               write(line_out, string'(" D3 "));
               write(line_out, to_hstring(to_unsigned(0, 32)));
               writeline(outfile, line_out);
               tracecounts_out(1) <= tracecounts_out(1) + 1;
            end if;
            
            if (fillWrite = '1') then
               case (settings_colorImage.FB_size) is
                  when SIZE_8BIT  => report "8 Bit Fill mode export not implemented" severity failure; 
                  
                  when SIZE_16BIT => 
                     export_fillAddr  := fillAddr(25 downto 3) & "000";
                     export_fillColor := fillColor;
                     export_fillBE    := fillBE sll to_integer(fillAddr(2 downto 0));
                     export_fillX     := fillX;
                     export_fillIndex := tracecounts_out(1);
                     while (export_fillBE(1 downto 0) /= "11") loop
                        export_fillAddr  := export_fillAddr + 2;
                        export_fillColor := x"0000" & export_fillColor(63 downto 16);
                        export_fillBE    := "00" & export_fillBE(7 downto 2);
                     end loop;
                     for i in 0 to 3 loop
                        if (export_fillBE(1 downto 0) = "11") then
                           write(line_out, string'("Pixel: I ")); 
                           write(line_out, to_string_len(export_fillIndex + 1, 8));
                           write(line_out, string'(" A ")); 
                           write(line_out, to_hstring(resize(export_fillAddr, 32)));
                           write(line_out, string'(" D ")); 
                           write(line_out, to_hstring(x"0000" & byteswap16(export_fillColor(15 downto 0))));
                           write(line_out, string'(" X ")); 
                           write(line_out, to_string_len(to_integer(export_fillX), 4));
                           write(line_out, string'(" Y ")); 
                           write(line_out, to_string_len(to_integer(fillY), 4));
                           write(line_out, string'(" D1 "));
                           write(line_out, to_hstring(to_unsigned(0, 30) & export_fillColor(8) & export_fillColor(8)));
                           write(line_out, string'(" D2 "));
                           write(line_out, to_hstring(to_unsigned(0, 32)));
                           write(line_out, string'(" D3 "));
                           write(line_out, to_hstring(to_unsigned(0, 32)));
                           writeline(outfile, line_out);
                           export_fillIndex := export_fillIndex + 1;
                        end if;
                        export_fillAddr  := export_fillAddr + 2;
                        export_fillColor := x"0000" & export_fillColor(63 downto 16);
                        export_fillBE    := "00" & export_fillBE(7 downto 2);
                        export_fillX     := export_fillX + 1;
                     end loop;
                     tracecounts_out(1) <= export_fillIndex;

                  when SIZE_32BIT => 
                     export_fillAddr  := fillAddr(25 downto 3) & "000";
                     export_fillColor := fillColor;
                     export_fillBE    := fillBE sll to_integer(fillAddr(2 downto 0));
                     export_fillX     := fillX;
                     export_fillIndex := tracecounts_out(1);
                     while (export_fillBE(3 downto 0) /= "1111") loop
                        export_fillAddr  := export_fillAddr + 4;
                        export_fillColor := x"00000000" & export_fillColor(63 downto 32);
                        export_fillBE    := "0000" & export_fillBE(7 downto 4);
                     end loop;
                     for i in 0 to 1 loop
                        if (export_fillBE(3 downto 0) = "1111") then
                           write(line_out, string'("Pixel: I ")); 
                           write(line_out, to_string_len(export_fillIndex + 1, 8));
                           write(line_out, string'(" A ")); 
                           write(line_out, to_hstring(resize(export_fillAddr, 32)));
                           write(line_out, string'(" D ")); 
                           write(line_out, to_hstring(byteswap32(export_fillColor(31 downto 0))));
                           write(line_out, string'(" X ")); 
                           write(line_out, to_string_len(to_integer(export_fillX), 4));
                           write(line_out, string'(" Y ")); 
                           write(line_out, to_string_len(to_integer(fillY), 4));
                           write(line_out, string'(" D1 "));
                           write(line_out, to_hstring(to_unsigned(0, 32)));
                           write(line_out, string'(" D2 "));
                           write(line_out, to_hstring(to_unsigned(0, 32)));
                           write(line_out, string'(" D3 "));
                           write(line_out, to_hstring(to_unsigned(0, 32)));
                           writeline(outfile, line_out);
                           export_fillIndex := export_fillIndex + 1;
                        end if;
                        export_fillAddr  := export_fillAddr + 4;
                        export_fillColor := x"00000000" & export_fillColor(63 downto 32);
                        export_fillBE    := "0000" & export_fillBE(7 downto 4);
                        export_fillX     := export_fillX + 1;
                     end loop;
                     tracecounts_out(1) <= export_fillIndex;
                  
                  when others => null; 
               end case;
            end if;
            
            
         end loop;
         
      end process;
   
   end generate goutput;

   -- synthesis translate_on   


end architecture;





