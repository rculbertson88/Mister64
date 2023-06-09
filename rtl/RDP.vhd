library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pFunctions.all;

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

   signal DPC_START                 : unsigned(23 downto 0); -- 0x04100000 (RW): [23:0] DMEM/RDRAM start address
   signal DPC_END_REG               : unsigned(23 downto 0); -- 0x04100004 (RW): [23:0] DMEM/RDRAM end address
   signal DPC_CURRENT               : unsigned(23 downto 0); -- 0x04100008 (R): [23:0] DMEM/RDRAM current address
   signal DPC_STATUS_xbus_dmem_dma  : std_logic;
   signal DPC_STATUS_freeze         : std_logic;
   signal DPC_STATUS_flush          : std_logic;
   signal DPC_STATUS_start_gclk     : std_logic;
   signal DPC_STATUS_cbuf_ready     : std_logic;
   signal DPC_STATUS_dma_busy       : std_logic;
   signal DPC_STATUS_end_valid      : std_logic;
   signal DPC_STATUS_start_valid    : std_logic;
   signal DPC_CLOCK                 : unsigned(23 downto 0); -- 0x04100010 (R): [23:0] clock counter
   signal DPC_BUFBUSY               : unsigned(23 downto 0); -- 0x04100014 (R): [23:0] clock counter
   signal DPC_PIPEBUSY              : unsigned(23 downto 0); -- 0x04100018 (R): [23:0] clock counter
   signal DPC_TMEM                  : unsigned(23 downto 0); -- 0x0410001C (R): [23:0] clock counter

   signal bus_write_latched         : std_logic := '0';

   -- Command RAM
   signal fillAddr                  : unsigned(4 downto 0) := (others => '0');
   signal store                     : std_logic := '0';

   signal commandRAMWaiting         : std_logic := '0';
   signal commandRAMReady           : std_logic := '0';
   signal CommandData               : std_logic_vector(63 downto 0);
   signal commandCntNext            : unsigned(4 downto 0) := (others => '0');
   signal commandRAMPtr             : unsigned(4 downto 0);
   signal commandIsIdle             : std_logic;
   signal commandWordDone           : std_logic;

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
            
            DPC_START                <= ss_in(0)(23 downto 0); --(others => '0');
            DPC_END_REG              <= ss_in(0)(47 downto 24); --(others => '0');
            DPC_CURRENT              <= ss_in(1)(23 downto 0); --(others => '0');
            DPC_STATUS_xbus_dmem_dma <= ss_in(0)(48); --'0';
            DPC_STATUS_freeze        <= ss_in(0)(49); --'0';
            DPC_STATUS_flush         <= ss_in(0)(50); --'0';
            DPC_STATUS_start_gclk    <= ss_in(0)(51); --'0';
            DPC_STATUS_cbuf_ready    <= ss_in(0)(52); --'1';
            DPC_STATUS_dma_busy      <= ss_in(0)(53); --'0';
            DPC_STATUS_end_valid     <= ss_in(0)(54); --'0';
            DPC_STATUS_start_valid   <= ss_in(0)(55); --'0';
            DPC_CLOCK                <= (others => '0');
            DPC_BUFBUSY              <= (others => '0');
            DPC_PIPEBUSY             <= (others => '0');
            DPC_TMEM                 <= (others => '0');
            
            bus_write_latched        <= '0';
            
            commandRAMWaiting        <= '0';
            commandRAMReady          <= '0';
            
         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_dataRead <= (others => '0');

            -- bus read
            if (bus_read = '1') then
               bus_done <= '1';
               case (bus_addr(19 downto 0)) is   
                  when x"00000" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_START);  
                  when x"00004" => bus_dataRead(23 downto 0) <= std_logic_vector(DPC_END_REG);
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
                     bus_dataRead(9)  <= DPC_STATUS_end_valid;
                     bus_dataRead(10) <= DPC_STATUS_start_valid;
                  
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
            
            if (bus_write_latched = '1') then
               bus_write_latched <= '0';
               bus_done          <= '1';
               
               case (bus_addr(19 downto 0)) is
                  when x"00000" =>
                     if (DPC_STATUS_start_valid = '0') then -- wrong according to n64brew, should always update
                        DPC_START <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                     end if;
                     DPC_STATUS_start_valid <= '1';
                  
                  when x"00004" => 
                     DPC_END_REG <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                     if (DPC_STATUS_start_valid = '1') then
                        DPC_STATUS_start_valid <= '0';
                        DPC_CURRENT <= DPC_START;
                        --start work
                     end if;
                  
                  when x"0000C" => 
                     if (bus_dataWrite(0) = '1') then DPC_STATUS_xbus_dmem_dma <= '0'; end if;
                     if (bus_dataWrite(1) = '1') then DPC_STATUS_xbus_dmem_dma <= '1'; end if;
                     if (bus_dataWrite(2) = '1') then 
                        DPC_STATUS_freeze <= '0'; 
                        --start work
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
               
            elsif (commandWordDone = '1') then
               DPC_CURRENT   <= DPC_CURRENT + 8;
            end if;

            if (DPC_STATUS_freeze = '0' and commandRAMWaiting = '0' and commandRAMReady = '0' and commandIsIdle = '1' and commandWordDone = '0' and DPC_CURRENT < DPC_END_REG) then
               commandRAMWaiting <= '1';
               rdram_request     <= '1';
               rdram_rnw         <= '1';
               rdram_address     <= x"0" & DPC_CURRENT;
               if ((DPC_END_REG(23 downto 3) - DPC_CURRENT(23 downto 3)) > 22) then
                  commandCntNext    <= to_unsigned(22, 5);
                  rdram_burstcount  <= to_unsigned(22, 10); -- max length for tri with all options on
               else
                  commandCntNext    <= resize(DPC_END_REG(23 downto 3) - DPC_CURRENT(23 downto 3), 5);
                  rdram_burstcount  <= "00000" & resize(DPC_END_REG(23 downto 3) - DPC_CURRENT(23 downto 3), 5);
               end if;
            end if;
            
            if (rdram_done = '1') then
               commandRAMWaiting <= '0';
               commandRAMReady   <= '1';
            end if;
            
            if (commandIsIdle = '1' and commandRAMReady = '1') then
               commandRAMReady <= '0';
            end if;

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
      clk1x            => clk1x,          
      reset            => reset,          
                                         
      commandRAMReady  => commandRAMReady,
      CommandData      => unsigned(CommandData),    
      commandCntNext   => commandCntNext, 
                                         
      commandRAMPtr    => commandRAMPtr,  
      commandIsIdle    => commandIsIdle,  
      commandWordDone  => commandWordDone
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





