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
            
      RSP_RDP_reg_addr     : in  unsigned(6 downto 0);
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

   signal DPC_START_NEXT            : unsigned(23 downto 0); -- 0x04100000 (RW): [23:0] DMEM/RDRAM start address
   signal DPC_END_NEXT              : unsigned(23 downto 0); -- 0x04100004 (RW): [23:0] DMEM/RDRAM end address
   signal DPC_CURRENT               : unsigned(23 downto 0); -- 0x04100008 (R): [23:0] DMEM/RDRAM current address
   signal DPC_STATUS_xbus_dmem_dma  : std_logic;
   signal DPC_STATUS_freeze         : std_logic;
   signal DPC_STATUS_flush          : std_logic;
   signal DPC_STATUS_start_gclk     : std_logic;
   signal DPC_STATUS_cbuf_ready     : std_logic;
   signal DPC_STATUS_dma_busy       : std_logic;
   signal DPC_STATUS_end_pending    : std_logic;
   signal DPC_STATUS_start_pending  : std_logic;
   signal DPC_CLOCK                 : unsigned(23 downto 0); -- 0x04100010 (R): [23:0] clock counter
   signal DPC_BUFBUSY               : unsigned(23 downto 0); -- 0x04100014 (R): [23:0] clock counter
   signal DPC_PIPEBUSY              : unsigned(23 downto 0); -- 0x04100018 (R): [23:0] clock counter
   signal DPC_TMEM                  : unsigned(23 downto 0); -- 0x0410001C (R): [23:0] clock counter

   -- bus/mem multiplexing
   signal bus_read_latched          : std_logic := '0';
   signal bus_write_latched         : std_logic := '0';
   signal reg_addr                  : unsigned(19 downto 0); 
   signal reg_dataWrite             : std_logic_vector(31 downto 0);

   -- Command RAM
   signal DPC_END                   : unsigned(23 downto 0);
   
   signal fillAddr                  : unsigned(4 downto 0) := (others => '0');
   
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
   
   type tmemState is 
   (  
      MEMIDLE, 
      WAITCOMMANDDATA,
      WAITTEXTUREDATA
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
   signal settings_blendcolor       : tsettings_blendcolor;
   signal settings_combineMode      : tsettings_combineMode;
   signal settings_colorImage       : tsettings_colorImage;
   signal settings_textureImage     : tsettings_textureImage;
   signal settings_tile             : tsettings_tile;
   signal settings_loadtype         : tsettings_loadtype;
   
   -- Texture RAM
   signal TextureRamAddr            : unsigned(8 downto 0) := (others => '0');    
   signal TextureRam0Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam1Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam2Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRam3Data           : std_logic_vector(15 downto 0) := (others => '0');
   signal TextureRamWE              : std_logic_vector(7 downto 0)  := (others => '0');
   type tTextureRamData is array(0 to 7) of std_logic_vector(15 downto 0);
   signal TextureRamDataIn          : tTextureRamData;
   
   -- Fill line
   signal writePixel                : std_logic;
   signal writePixelX               : unsigned(11 downto 0);
   signal writePixelY               : unsigned(11 downto 0);
   signal writePixelColor           : unsigned(31 downto 0);

   -- Pixel merging
   signal pixelAddr                 : unsigned(25 downto 0) := (others => '0');
   signal pixelColor                : std_logic_vector(31 downto 0) := (others => '0');
   signal pixelBE                   : unsigned(23 downto 0) := (others => '0');
   signal pixelWrite                : std_logic := '0';
      
   signal pixel64data               : std_logic_vector(63 downto 0) := (others => '0');
   signal pixel64BE                 : std_logic_vector(7 downto 0) := (others => '0');
   signal pixel64addr               : std_logic_vector(19 downto 0) := (others => '0');
   signal pixel64filled             : std_logic := '0';
   signal pixel64timeout            : integer range 0 to 15;

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
   -- synthesis translate_on   

begin 

   reg_addr      <= 13x"0" & RSP_RDP_reg_addr when (RSP_RDP_reg_read = '1' or RSP_RDP_reg_write = '1') else bus_addr;     
   reg_dataWrite <= std_logic_vector(RSP_RDP_reg_dataOut) when (RSP_RDP_reg_write = '1') else bus_dataWrite;

   rdram_rnw <= '1';

   process (clk1x)
      variable var_dataRead : std_logic_vector(31 downto 0) := (others => '0');
   begin
      if rising_edge(clk1x) then
      
         irq_out             <= '0';
         RSP2RDP_req         <= '0';
         rdram_request       <= '0';
         TextureReqRAMReady  <= '0';
      
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
                     DPC_STATUS_end_pending <= '0';
                     DPC_CURRENT            <= DPC_START_NEXT;
                     DPC_END                <= DPC_END_NEXT;
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
            fillAddr <= (others => '0');
            if (memState = WAITCOMMANDDATA) then
               commandRAMstore <= '1';
            elsif (memState = WAITTEXTUREDATA) then
               TextureReqRAMstore <= '1';
            end if;
         elsif (ddr3_DOUT_READY = '1') then
            fillAddr <= fillAddr + 1;
         end if;
         
         if (rdram_done = '1') then
            commandRAMstore    <= '0';
            TextureReqRAMstore <= '0';
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
      address_a   => std_logic_vector(fillAddr),
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
                                                
      commandRAMPtr           => commandRAMPtr,  
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
      settings_blendcolor     => settings_blendcolor, 
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
      address_a   => std_logic_vector(fillAddr),
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
                              
      settings_poly           => settings_poly,      
      settings_scissor        => settings_scissor,   
      settings_otherModes     => settings_otherModes, 
      settings_fillcolor      => settings_fillcolor,  
      settings_blendcolor     => settings_blendcolor, 
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
      TextureRamWE            => TextureRamWE,   
      
      -- synthesis translate_off
      export_line_done        => export_line_done,
      export_line_list        => export_line_list,
         
      export_load_done        => export_load_done,
      export_loadFetch        => export_loadFetch,
      export_loadData         => export_loadData, 
      export_loadValue        => export_loadValue,
      -- synthesis translate_on

      writePixel              => writePixel,     
      writePixelX             => writePixelX,    
      writePixelY             => writePixelY,   
      writePixelColor         => writePixelColor     
   );
   
   TextureRamDataIn(0) <= TextureRam0Data;
   TextureRamDataIn(1) <= TextureRam1Data;
   TextureRamDataIn(2) <= TextureRam2Data;
   TextureRamDataIn(3) <= TextureRam3Data;
   TextureRamDataIn(4) <= TextureRam0Data;
   TextureRamDataIn(5) <= TextureRam1Data;
   TextureRamDataIn(6) <= TextureRam2Data;
   TextureRamDataIn(7) <= TextureRam3Data;
   
   gTextureRam: for i in 0 to 7 generate
   begin
   
      iTextureRAM: entity mem.dpram
      generic map 
      ( 
         addr_width  => 9,
         data_width  => 16
      )
      port map
      (
         clock_a     => clk1x,
         address_a   => std_logic_vector(TextureRamAddr),
         data_a      => TextureRamDataIn(i),
         wren_a      => TextureRamWE(i),
         
         clock_b     => clk1x,
         address_b   => 9x"0",
         data_b      => 16x"0",
         wren_b      => '0',
         q_b         => open
      );
      
   end generate;
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         --fifoOut_Wr_1 <= fifoOut_Wr; -- fifoOut_Wr_1 used for idle test
      
         fifoOut_Wr   <= '0';
         fifoOut_Din  <= pixel64BE & pixel64Addr & pixel64data;
         
         -- stage 0 -> calculate FB address
         pixelWrite <= writePixel;
         pixelColor <= std_logic_vector(writePixelColor);
         if (settings_colorImage.FB_size = SIZE_16BIT) then
            pixelAddr <= resize(settings_colorImage.FB_base + ((writePixelY * (settings_colorImage.FB_width_m1 + 1)) + writePixelX) * 2, 26);
         elsif (settings_colorImage.FB_size = SIZE_32BIT) then     
            pixelAddr <= resize(settings_colorImage.FB_base + ((writePixelY * (settings_colorImage.FB_width_m1 + 1)) + writePixelX) * 4, 26);
         end if;
         
         -- stage 1 -> write to 64bit buffer
         if (pixelWrite = '1' and pixelAddr(25 downto 23) = 0) then -- change max bit according to 4/8mbyte rdram, currently 8mbyte only
         
            pixel64timeout <= 15;
         
            if (pixel64filled = '0' or pixelAddr(22 downto 3) /= unsigned(pixel64Addr)) then
            
               fifoOut_Wr <= pixel64filled;
               
               pixel64Addr <= std_logic_vector(pixelAddr(22 downto 3));
               
               if (settings_colorImage.FB_size = SIZE_16BIT) then
                  case (pixelAddr(2 downto 1)) is
                     when "00" => pixel64data(15 downto  0) <= pixelColor(15 downto 0); pixel64BE <= "00000011";
                     when "01" => pixel64data(31 downto 16) <= pixelColor(15 downto 0); pixel64BE <= "00001100";
                     when "10" => pixel64data(47 downto 32) <= pixelColor(15 downto 0); pixel64BE <= "00110000";
                     when "11" => pixel64data(63 downto 48) <= pixelColor(15 downto 0); pixel64BE <= "11000000";
                     when others => null;
                  end case;
               elsif (settings_colorImage.FB_size = SIZE_32BIT) then     
                  case (pixelAddr(2)) is
                     when '0' => pixel64data(31 downto  0) <= pixelColor; pixel64BE <= "00001111";
                     when '1' => pixel64data(63 downto 32) <= pixelColor; pixel64BE <= "11110000";
                     when others => null;
                  end case;
               end if;
               
               pixel64filled <= '1';
            
            else
               
               if (settings_colorImage.FB_size = SIZE_16BIT) then
                  case (pixelAddr(2 downto 1)) is
                     when "00" => pixel64data(15 downto  0) <= pixelColor(15 downto 0); pixel64BE(1 downto 0) <= "11";
                     when "01" => pixel64data(31 downto 16) <= pixelColor(15 downto 0); pixel64BE(3 downto 2) <= "11";
                     when "10" => pixel64data(47 downto 32) <= pixelColor(15 downto 0); pixel64BE(5 downto 4) <= "11";
                     when "11" => pixel64data(63 downto 48) <= pixelColor(15 downto 0); pixel64BE(7 downto 6) <= "11";
                     when others => null;
                  end case;
               elsif (settings_colorImage.FB_size = SIZE_32BIT) then     
                  case (pixelAddr(2)) is
                     when '0' => pixel64data(31 downto  0) <= pixelColor; pixel64BE(3 downto 0) <= "1111";
                     when '1' => pixel64data(63 downto 32) <= pixelColor; pixel64BE(7 downto 4) <= "1111";
                     when others => null;
                  end case;
               end if;

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
         file outfile          : text;
         variable f_status     : FILE_OPEN_STATUS;
         variable line_out     : line;
         variable stringbuffer : string(1 to 31);
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
            
            if (export_line_done = '1') then
               write(line_out, string'("LINE: I ")); 
               write(line_out, to_string_len(tracecounts_out(20) + 1, 8));
               write(line_out, string'(" A 00000000 D 00000000 X    0 Y ")); 
               write(line_out, to_string_len(to_integer(export_line_list.y), 4));
               write(line_out, string'(" D1 "));
               write(line_out, to_hstring(export_line_list.debug1));
               write(line_out, string'(" D2 "));
               write(line_out, to_hstring(export_line_list.debug2));
               write(line_out, string'(" D3 "));
               write(line_out, to_hstring(export_line_list.debug3));
               writeline(outfile, line_out);
               tracecounts_out(20) <= tracecounts_out(20) + 1;
            end if;
            
            if (export_load_done = '1') then
               write(line_out, string'("LoadFetch: I ")); 
               write(line_out, to_string_len(tracecounts_out(16) + 1, 8));
               write(line_out, string'(" A ")); 
               write(line_out, to_hstring(export_loadFetch.addr));
               write(line_out, string'(" D ")); 
               write(line_out, to_hstring(export_loadFetch.data(31 downto 0)));
               write(line_out, string'(" X ")); 
               write(line_out, to_string_len(to_integer(export_loadFetch.x), 4));
               write(line_out, string'(" Y ")); 
               write(line_out, to_string_len(to_integer(export_loadFetch.y), 4));
               write(line_out, string'(" D1 "));
               write(line_out, to_hstring(export_loadFetch.debug1));
               write(line_out, string'(" D2 "));
               write(line_out, to_hstring(export_loadFetch.debug2));
               write(line_out, string'(" D3 "));
               write(line_out, to_hstring(export_loadFetch.debug3));
               writeline(outfile, line_out);
               tracecounts_out(16) <= tracecounts_out(16) + 1;
               
               write(line_out, string'("LoadData: I ")); 
               write(line_out, to_string_len(tracecounts_out(17) + 1, 8));
               write(line_out, string'(" A ")); 
               write(line_out, to_hstring(export_LoadData.addr));
               write(line_out, string'(" D ")); 
               write(line_out, to_hstring(export_LoadData.data));
               write(line_out, string'(" X ")); 
               write(line_out, to_string_len(to_integer(export_LoadData.x), 4));
               write(line_out, string'(" Y ")); 
               write(line_out, to_string_len(to_integer(export_LoadData.y), 4));
               write(line_out, string'(" D1 "));
               write(line_out, to_hstring(export_LoadData.debug1));
               write(line_out, string'(" D2 "));
               write(line_out, to_hstring(export_LoadData.debug2));
               write(line_out, string'(" D3 "));
               write(line_out, to_hstring(export_LoadData.debug3));
               writeline(outfile, line_out);
               tracecounts_out(17) <= tracecounts_out(17) + 1;
               
               write(line_out, string'("LoadValue: I ")); 
               write(line_out, to_string_len(tracecounts_out(18) + 1, 8));
               write(line_out, string'(" A ")); 
               write(line_out, to_hstring(export_LoadValue.addr));
               write(line_out, string'(" D ")); 
               write(line_out, to_hstring(export_LoadValue.data(31 downto 0)));
               write(line_out, string'(" X ")); 
               write(line_out, to_string_len(to_integer(export_LoadValue.x), 4));
               write(line_out, string'(" Y ")); 
               write(line_out, to_string_len(to_integer(export_LoadValue.y), 4));
               write(line_out, string'(" D1 "));
               write(line_out, to_hstring(export_LoadValue.debug1));
               write(line_out, string'(" D2 "));
               write(line_out, to_hstring(export_LoadValue.debug2));
               write(line_out, string'(" D3 "));
               write(line_out, to_hstring(export_LoadValue.debug3));
               writeline(outfile, line_out);
               tracecounts_out(18) <= tracecounts_out(18) + 1;
            end if;
            
         end loop;
         
      end process;
   
   end generate goutput;

   -- synthesis translate_on   


end architecture;





