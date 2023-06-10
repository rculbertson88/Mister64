library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pFunctions.all;
use work.pRDP.all;

entity RDP is
   port 
   (
      clk1x            : in  std_logic;
      clk2x            : in  std_logic;
      ce               : in  std_logic;
      reset            : in  std_logic;
      
      irq_out          : out std_logic := '0';
      
      bus_addr         : in  unsigned(19 downto 0); 
      bus_dataWrite    : in  std_logic_vector(31 downto 0);
      bus_read         : in  std_logic;
      bus_write        : in  std_logic;
      bus_dataRead     : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done         : out std_logic := '0';
      
      rdram_request    : out std_logic := '0';
      rdram_rnw        : out std_logic := '0'; 
      rdram_address    : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount : out unsigned(9 downto 0):= (others => '0');
      rdram_writeMask  : out std_logic_vector(7 downto 0) := (others => '0'); 
      rdram_dataWrite  : out std_logic_vector(63 downto 0) := (others => '0');
      rdram_granted    : in  std_logic;
      rdram_done       : in  std_logic;
      ddr3_DOUT        : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY  : in  std_logic;
      
      SS_reset         : in  std_logic;
      SS_DataWrite     : in  std_logic_vector(63 downto 0);
      SS_Adr           : in  unsigned(0 downto 0);
      SS_wren          : in  std_logic;
      SS_rden          : in  std_logic;
      SS_DataRead      : out std_logic_vector(63 downto 0);
      SS_idle          : out std_logic
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

   signal bus_write_latched         : std_logic := '0';

   -- Command RAM
   signal DPC_END                   : unsigned(23 downto 0);
   
   signal fillAddr                  : unsigned(4 downto 0) := (others => '0');
   signal store                     : std_logic := '0';

   signal commandRAMReady           : std_logic := '0';
   signal CommandData               : std_logic_vector(63 downto 0);
   signal commandCntNext            : unsigned(4 downto 0) := (others => '0');
   signal commandRAMPtr             : unsigned(4 downto 0);
   signal commandIsIdle             : std_logic;
   signal commandWordDone           : std_logic;
   
   type tmemState is 
   (  
      MEMIDLE, 
      WAITCOMMANDDATA,
      WAITWRITEPIXEL
   ); 
   signal memState  : tmemState := MEMIDLE;

   -- Command Eval    
   signal settings_poly             : tsettings_poly;
   signal poly_start                : std_logic;
   signal poly_done                 : std_logic;
   signal settings_scissor          : tsettings_scissor;
   signal settings_otherModes       : tsettings_otherModes;
   signal settings_fillcolor        : tsettings_fillcolor;
   signal settings_blendcolor       : tsettings_blendcolor;
   signal settings_combineMode      : tsettings_combineMode;
   signal settings_colorImage       : tsettings_colorImage;
   
   -- Fill line
   signal writePixel                : std_logic;
   signal writePixelX               : unsigned(11 downto 0);
   signal writePixelY               : unsigned(11 downto 0);
   signal writePixelSize            : unsigned(1 downto 0);
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

   signal fifoOut_Din               : std_logic_vector(91 downto 0);
   signal fifoOut_Wr                : std_logic; 
   signal fifoOut_Wr_1              : std_logic; 
   signal fifoOut_NearFull          : std_logic;
   signal fifoOut_Dout              : std_logic_vector(91 downto 0);
   signal fifoOut_Rd                : std_logic := '0';
   signal fifoOut_Empty             : std_logic;

   -- savestates
   type t_ssarray is array(0 to 1) of unsigned(63 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
   signal ss_out : t_ssarray := (others => (others => '0'));   

begin 

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         rdram_request    <= '0';
      
         if (reset = '1') then
            
            bus_done             <= '0';
            irq_out              <= '0';
            
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
            
            bus_write_latched        <= '0';
            
            DPC_END                  <= ss_in(0)(47 downto 24); --(others => '0');
            commandRAMReady          <= '0';
            memState                 <= MEMIDLE;
            
         else
            if (ce = '1') then
         
               bus_done     <= '0';
               bus_dataRead <= (others => '0');
   
               -- bus read
               if (bus_read = '1') then
                  bus_done <= '1';
                  case (bus_addr(19 downto 0)) is   
                     when x"00000" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_START_NEXT);  
                     when x"00004" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_END_NEXT);
                     when x"00008" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_CURRENT);
                     when x"0000C" =>
                        bus_dataRead(0)  <= DPC_STATUS_xbus_dmem_dma;
                        bus_dataRead(1)  <= DPC_STATUS_freeze;
                        bus_dataRead(2)  <= DPC_STATUS_flush;
                        bus_dataRead(3)  <= DPC_STATUS_start_gclk;
                        if (DPC_TMEM > 0) then bus_dataRead(4)      <= '1'; end if;
                        if (DPC_PIPEBUSY > 0) then bus_dataRead(5)  <= '1'; end if;
                        --if (DPC_BUFBUSY > 0) then bus_dataRead(6)  <= '1'; end if;
                        bus_dataRead(7)  <= DPC_STATUS_cbuf_ready;
                        bus_dataRead(8)  <= DPC_STATUS_dma_busy;
                        bus_dataRead(9)  <= DPC_STATUS_end_pending;
                        bus_dataRead(10) <= DPC_STATUS_start_pending;
                     
                     when x"00010" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_CLOCK);  
                     when x"00014" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_BUFBUSY);  
                     when x"00018" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_PIPEBUSY);  
                     when x"0001C" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_TMEM);  
                     when others   => null;             
                  end case;
               end if;
               
               if (bus_write = '1') then
                  bus_write_latched <= '1';
               end if;
               
               if (commandWordDone = '1') then
                  DPC_CURRENT   <= DPC_CURRENT + 8;
                  if (DPC_CURRENT + 8 = DPC_END) then
                     if (DPC_STATUS_end_pending = '1') then
                        DPC_STATUS_end_pending <= '0';
                        DPC_CURRENT            <= DPC_START_NEXT;
                        DPC_END                <= DPC_END_NEXT;
                     else
                        DPC_STATUS_dma_busy <= '0';
                     end if;
                  end if;
               elsif (bus_write_latched = '1') then
                  bus_write_latched <= '0';
                  bus_done          <= '1';
                  
                  case (bus_addr(19 downto 0)) is
                     when x"00000" =>
                        --if (DPC_STATUS_start_valid = '0') then -- wrong according to n64brew, should always update
                           DPC_START_NEXT <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                        --end if;
                        DPC_STATUS_start_pending <= '1';
                     
                     when x"00004" => 
                        DPC_END_NEXT <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                        
                        if (DPC_STATUS_start_pending = '0') then
                           DPC_STATUS_dma_busy <= '1';
                           DPC_END             <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                        else
                           if (DPC_STATUS_dma_busy = '0') then
                              DPC_STATUS_start_pending <= '0';
                              DPC_STATUS_dma_busy      <= '1';
                              DPC_CURRENT              <= DPC_START_NEXT;
                              DPC_END                  <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                           else
                              DPC_STATUS_end_pending <= '1';
                           end if;
                        end if;
                     
                     when x"0000C" => 
                        if (bus_dataWrite(0) = '1') then DPC_STATUS_xbus_dmem_dma <= '0'; end if;
                        if (bus_dataWrite(1) = '1') then DPC_STATUS_xbus_dmem_dma <= '1'; end if;
                        if (bus_dataWrite(2) = '1') then 
                           DPC_STATUS_freeze <= '0'; 
                        end if;
                        if (bus_dataWrite(3) = '1') then DPC_STATUS_freeze        <= '1'; end if;
                        if (bus_dataWrite(4) = '1') then DPC_STATUS_flush         <= '0'; end if;
                        if (bus_dataWrite(5) = '1') then DPC_STATUS_flush         <= '1'; end if;
                        if (bus_dataWrite(6) = '1') then DPC_TMEM     <= (others => '0'); end if;
                        if (bus_dataWrite(7) = '1') then DPC_PIPEBUSY <= (others => '0'); end if;
                        if (bus_dataWrite(8) = '1') then DPC_BUFBUSY  <= (others => '0'); end if;
                        if (bus_dataWrite(9) = '1') then DPC_CLOCK    <= (others => '0'); end if;
                     
                     when others   => null;                  
                  end case;
                  
               end if; -- bus_write_latched

            end if; -- ce
         
         end if; -- no reset
            
         -- memory statemachine
         case (memState) is
         
            when MEMIDLE =>
               if (fifoOut_Empty = '0') then
                  memState          <= WAITWRITEPIXEL;
                  rdram_request     <= '1';
                  rdram_rnw         <= '0';
                  rdram_address     <= 5x"0" & unsigned(fifoOut_Dout(83 downto 64)) & "000";
                  rdram_writeMask   <= fifoOut_Dout(91 downto 84);
                  rdram_dataWrite   <= byteswap64(fifoOut_Dout(63 downto 0));
                  rdram_burstcount  <= to_unsigned(1, 10);
               elsif (DPC_STATUS_freeze = '0' and commandRAMReady = '0' and commandIsIdle = '1' and commandWordDone = '0' and DPC_STATUS_dma_busy = '1') then
                  memState          <= WAITCOMMANDDATA;
                  rdram_request     <= '1';
                  rdram_rnw         <= '1';
                  rdram_address     <= x"0" & DPC_CURRENT;
                  if ((DPC_END(23 downto 3) - DPC_CURRENT(23 downto 3)) > 22) then
                     commandCntNext    <= to_unsigned(22, 5);
                     rdram_burstcount  <= to_unsigned(22, 10); -- max length for tri with all options on
                  else
                     commandCntNext    <= resize(DPC_END(23 downto 3) - DPC_CURRENT(23 downto 3), 5);
                     rdram_burstcount  <= "00000" & resize(DPC_END(23 downto 3) - DPC_CURRENT(23 downto 3), 5);
                  end if;
               end if;
               
            when WAITCOMMANDDATA =>
               if (rdram_done = '1') then
                  commandRAMReady   <= '1';
                  memState          <= MEMIDLE;
               end if;
               
            when WAITWRITEPIXEL =>
               if (rdram_done = '1') then
                  memState          <= MEMIDLE;
               end if;
         
         end case;
  
         if (commandIsIdle = '1' and commandRAMReady = '1') then
            commandRAMReady <= '0';
         end if;

      end if;
   end process;
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         
         if (rdram_granted = '1') then
            fillAddr <= (others => '0');
            store    <= '1';
         elsif (ddr3_DOUT_READY = '1') then
            fillAddr <= fillAddr + 1;
         end if;
         
         if (rdram_done = '1') then
            store <= '0';
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
      wren_a      => (ddr3_DOUT_READY and store),
      
      clock_b     => clk1x,
      address_b   => std_logic_vector(commandRAMPtr),
      data_b      => 64x"0",
      wren_b      => '0',
      q_b         => CommandData
   );   
   
   iRDP_command : entity work.RDP_command
   port map
   (
      clk1x                => clk1x,          
      reset                => reset,          
                                             
      commandRAMReady      => commandRAMReady,
      CommandData          => unsigned(CommandData),    
      commandCntNext       => commandCntNext, 
                                             
      commandRAMPtr        => commandRAMPtr,  
      commandIsIdle        => commandIsIdle,  
      commandWordDone      => commandWordDone,
      
      poly_done            => poly_done,       
      settings_poly        => settings_poly,       
      poly_start           => poly_start,          
                              
      settings_scissor     => settings_scissor,   
      settings_otherModes  => settings_otherModes, 
      settings_fillcolor   => settings_fillcolor,  
      settings_blendcolor  => settings_blendcolor, 
      settings_combineMode => settings_combineMode,
      settings_colorImage  => settings_colorImage 
   );
   
   iRDP_raster : entity work.RDP_raster
   port map
   (
      clk1x                => clk1x,        
      reset                => reset,        
                           
      settings_poly        => settings_poly,      
      settings_scissor     => settings_scissor,   
      settings_otherModes  => settings_otherModes, 
      settings_fillcolor   => settings_fillcolor,  
      settings_blendcolor  => settings_blendcolor, 
      settings_colorImage  => settings_colorImage, 
      poly_start           => poly_start,   
      loading_mode         => '0',
      poly_done            => poly_done,

      writePixel           => writePixel,     
      writePixelX          => writePixelX,    
      writePixelY          => writePixelY,   
      writePixelColor      => writePixelColor     
   );
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         fifoOut_Wr_1 <= fifoOut_Wr; -- fifoOut_Wr_1 used for idle test
      
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
   
   -- pixel writing fifo
   fifoOut_Rd <= '1' when (memState = MEMIDLE and fifoOut_Empty = '0') else '0';
   
   iSyncFifo_OUT: entity mem.SyncFifoFallThrough
   generic map
   (
      SIZE             => 256,
      DATAWIDTH        => 64 + 20 + 8,  -- 64bit data + 20 bit address + 8 bit byte enable
      NEARFULLDISTANCE => 250
   )
   port map
   ( 
      clk      => clk1x,
      reset    => reset,  
      Din      => fifoOut_Din,     
      Wr       => fifoOut_Wr,      
      Full     => open,    
      NearFull => fifoOut_NearFull,
      Dout     => fifoOut_Dout,    
      Rd       => fifoOut_Rd,      
      Empty    => fifoOut_Empty   
   );
   
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
            
         elsif (SS_wren = '1') then
            ss_in(to_integer(SS_Adr)) <= unsigned(SS_DataWrite);
         end if;
         
         if (SS_rden = '1') then
            SS_DataRead <= std_logic_vector(ss_out(to_integer(SS_Adr)));
         end if;
      
      end if;
   end process;

end architecture;





