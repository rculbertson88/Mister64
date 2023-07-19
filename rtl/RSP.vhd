library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pFunctions.all;

entity RSP is
   port 
   (
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;
      clk2xIndex           : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
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
      ddr3_DOUT_READY      : in  std_logic
   );
end entity;

architecture arch of RSP is

   -- register
   signal SP_DMA_SPADDR             : unsigned(12 downto 3); -- 0x04040000 Address in IMEM / DMEM for a DMA transfer //(RW) : [12] MEM_BANK [11:3] MEM_ADDR[11:3] [2:0] = 0
   signal SP_DMA_RAMADDR            : unsigned(23 downto 3); -- 0x04040004 Address in RDRAM for a DMA transfer
   signal SP_DMA_LEN                : unsigned(11 downto 3);
   signal SP_DMA_COUNT              : unsigned(7 downto 0);
   signal SP_DMA_SKIP               : unsigned(11 downto 3);
   signal SP_DMA_STATUS_halt        : std_logic; -- 0x04040010 RSP status register
   signal SP_DMA_STATUS_broke       : std_logic;
   signal SP_DMA_STATUS_dmabusy     : std_logic;
   signal SP_DMA_STATUS_dmafull     : std_logic;
   signal SP_DMA_STATUS_iofull      : std_logic;
   signal SP_DMA_STATUS_singlestep  : std_logic;
   signal SP_DMA_STATUS_irqonbreak  : std_logic;
   signal SP_DMA_STATUS_signal0set  : std_logic;
   signal SP_DMA_STATUS_signal1set  : std_logic;
   signal SP_DMA_STATUS_signal2set  : std_logic;
   signal SP_DMA_STATUS_signal3set  : std_logic;
   signal SP_DMA_STATUS_signal4set  : std_logic;
   signal SP_DMA_STATUS_signal5set  : std_logic;
   signal SP_DMA_STATUS_signal6set  : std_logic;
   signal SP_DMA_STATUS_signal7set  : std_logic;
   signal SP_SEMAPHORE              : std_logic; -- 0x0404001C Register to assist implementing a simple mutex between VR4300 and RSP. 
   signal SP_PC                     : unsigned(11 downto 0); -- 0x04080000 PC //(RW) : [11:0]

   -- bus/mem multiplexing
   signal bus_reg_req_read          : std_logic := '0';
   signal bus_reg_req_write         : std_logic := '0';
   signal reg_addr                  : unsigned(19 downto 0); 
   signal reg_dataWrite             : std_logic_vector(31 downto 0);

   -- DMA
   signal SP_DMA_CURRENT_SPADDR     : unsigned(12 downto 3) := (others => '0');
   signal SP_DMA_CURRENT_RAMADDR    : unsigned(23 downto 3) := (others => '0');
   signal SP_DMA_CURRENT_LEN        : unsigned(11 downto 3) := (others => '0');
   signal SP_DMA_CURRENT_COUNT      : unsigned(7 downto 0)  := (others => '0');
   signal SP_DMA_CURRENT_SKIP       : unsigned(11 downto 3) := (others => '0');
   signal SP_DMA_CURRENT_WORKLEN    : unsigned(9 downto 0) := (others => '0');
   
   signal SP_DMA_CURRENT_WORKLEN2   : unsigned(9 downto 0) := (others => '0');
   signal SP_DMA_CURRENT_FETCHLEN   : integer range 0 to 16;
      
   signal dma_next_isWrite          : std_logic := '0';
   signal dma_isWrite               : std_logic := '0';
   
   signal imem_rden_bus             : std_logic := '0';
   signal dmem_rden_bus             : std_logic := '0';
   signal imem_wren_bus             : std_logic := '0';
   signal dmem_wren_bus             : std_logic := '0';
   
   type tMEMSTATE is
   (
      MEM_IDLE,
      MEM_BUS_WAIT_IMEM,
      MEM_READ_IMEM,
      MEM_BUS_WAIT_DMEM,
      MEM_READ_DMEM,
      MEM_STARTDMA,
      MEM_RUNDMA
   );
   signal MEMSTATE : tMEMSTATE := MEM_IDLE;
   
   signal dma_startnext             : std_logic := '0';
   
   signal dma_store                 : std_logic := '0';
   
   signal fifo_reset                : std_logic := '0'; 
   
   signal fifoin_Dout               : std_logic_vector(63 downto 0);
   signal fifoin_Rd                 : std_logic := '0'; 
   signal fifoin_nearfull           : std_logic;    
   signal fifoin_Empty              : std_logic;    
   
   signal fifoout_Din               : std_logic_vector(63 downto 0);
   signal fifoout_Wr                : std_logic := '0'; 
   signal fifoout_Rd                : std_logic := '0'; 
   signal fifoout_nearfull          : std_logic;    
   signal fifoout_Empty             : std_logic;   
   
   type tDMASTATE is
   (
      DMA_IDLE,
      DMA_READBLOCK,
      DMA_WRITEONE
   );
   signal DMASTATE : tDMASTATE := DMA_IDLE;
   
   -- I/DMEM
   signal mem_address_a             : std_logic_vector(8 downto 0) := (others => '0');
   signal mem_data_a                : std_logic_vector(63 downto 0) := (others => '0');
   signal mem_be_a                  : std_logic_vector(7 downto 0) := (others => '0');
   
   signal dmem_address_b            : std_logic_vector(9 downto 0) := (others => '0');    
   signal dmem_data_b               : std_logic_vector(31 downto 0) := (others => '0');
   signal dmem_wren_a               : std_logic := '0'; 
   signal dmem_wren_b               : std_logic := '0';   
   signal dmem_q_a                  : std_logic_vector(63 downto 0); 
   signal dmem_q_b                  : std_logic_vector(31 downto 0);  
   
   signal imem_address_b            : std_logic_vector(9 downto 0) := (others => '0');    
   signal imem_data_b               : std_logic_vector(31 downto 0) := (others => '0');
   signal imem_wren_a               : std_logic := '0';
   signal imem_wren_b               : std_logic := '0';   
   signal imem_q_a                  : std_logic_vector(63 downto 0); 
   signal imem_q_b                  : std_logic_vector(31 downto 0); 

begin 

   reg_addr      <= bus_addr;     
   reg_dataWrite <= bus_dataWrite;
   
   process (clk1x)
      variable var_dataRead : std_logic_vector(31 downto 0) := (others => '0');
   begin
      if rising_edge(clk1x) then
      
         dmem_wren_a    <= '0';
         imem_wren_a    <= '0';
            
         fifo_reset     <= '0';
         fifoin_Rd      <= '0';
         fifoout_Wr     <= '0';
         fifoout_Rd     <= '0';
         
         rdram_request  <= '0';
      
         if (reset = '1') then
            
            bus_done                   <= '0';

            SP_DMA_SPADDR              <= (others => '0');
            SP_DMA_RAMADDR             <= (others => '0');
            SP_DMA_LEN                 <= (others => '0');
            SP_DMA_COUNT               <= (others => '0');
            SP_DMA_SKIP                <= (others => '0');
            SP_DMA_STATUS_halt         <= '1';
            SP_DMA_STATUS_broke        <= '0';
            SP_DMA_STATUS_dmabusy      <= '0';
            SP_DMA_STATUS_dmafull      <= '0';
            SP_DMA_STATUS_iofull       <= '0';
            SP_DMA_STATUS_singlestep   <= '0';
            SP_DMA_STATUS_irqonbreak   <= '0';
            SP_DMA_STATUS_signal0set   <= '0';
            SP_DMA_STATUS_signal1set   <= '0';
            SP_DMA_STATUS_signal2set   <= '0';
            SP_DMA_STATUS_signal3set   <= '0';
            SP_DMA_STATUS_signal4set   <= '0';
            SP_DMA_STATUS_signal5set   <= '0';
            SP_DMA_STATUS_signal6set   <= '0';
            SP_DMA_STATUS_signal7set   <= '0';
            SP_SEMAPHORE               <= '0';
            SP_PC                      <= (others => '0');
            
            SP_DMA_CURRENT_SPADDR      <= (others => '0');
            SP_DMA_CURRENT_RAMADDR     <= (others => '0');
            SP_DMA_CURRENT_LEN         <= (others => '0');
            SP_DMA_CURRENT_COUNT       <= (others => '0');
            SP_DMA_CURRENT_SKIP        <= (others => '0');
            
            irq_out                    <= '0';
            
            bus_reg_req_read           <= '0';
            bus_reg_req_write          <= '0';
            
            imem_rden_bus              <= '0';
            dmem_rden_bus              <= '0';
            imem_wren_bus              <= '0';
            dmem_wren_bus              <= '0';
            
            MEMSTATE                   <= MEM_IDLE;
            
            DMASTATE                   <= DMA_IDLE;
            dma_startnext              <= '0';
 
         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_dataRead <= (others => '0');
            
            -- bus access latch
            if (bus_read = '1') then
               if (bus_addr < 16#40000#) then -- DMEM/IMEM
                  if (bus_addr(12) = '1') then
                     imem_rden_bus <= '1';
                  else
                     dmem_rden_bus <= '1';
                  end if;
               else
                  bus_reg_req_read <= '1';
               end if;
            end if;
               
            if (bus_write = '1') then
               if (bus_addr < 16#40000#) then -- DMEM/IMEM
                  if (bus_addr(12) = '1') then
                     imem_wren_bus <= '1';
                  else
                     dmem_wren_bus <= '1';
                  end if; 
               else
                  bus_reg_req_write <= '1';
               end if;
            end if;

            -- register read access
            var_dataRead := (others => '0');
            case (reg_addr(19 downto 2) & "00") is
               when x"40000" => var_dataRead(12 downto 3) := std_logic_vector(SP_DMA_CURRENT_SPADDR);    
               when x"40004" => var_dataRead(23 downto 3) := std_logic_vector(SP_DMA_CURRENT_RAMADDR);    
               when x"40008" | x"4000C" => 
                  var_dataRead(11 downto  3) := std_logic_vector(SP_DMA_CURRENT_LEN);    
                  var_dataRead(19 downto 12) := std_logic_vector(SP_DMA_CURRENT_COUNT);    
                  var_dataRead(31 downto 23) := std_logic_vector(SP_DMA_CURRENT_SKIP);    
               when x"40010" => 
                  var_dataRead(0)  := SP_DMA_STATUS_halt;    
                  var_dataRead(1)  := SP_DMA_STATUS_broke;    
                  var_dataRead(2)  := SP_DMA_STATUS_dmabusy;    
                  var_dataRead(3)  := SP_DMA_STATUS_dmafull;    
                  var_dataRead(4)  := SP_DMA_STATUS_iofull;    
                  var_dataRead(5)  := SP_DMA_STATUS_singlestep;    
                  var_dataRead(6)  := SP_DMA_STATUS_irqonbreak;    
                  var_dataRead(7)  := SP_DMA_STATUS_signal0set;    
                  var_dataRead(8)  := SP_DMA_STATUS_signal1set;    
                  var_dataRead(9)  := SP_DMA_STATUS_signal2set;    
                  var_dataRead(10) := SP_DMA_STATUS_signal3set;    
                  var_dataRead(11) := SP_DMA_STATUS_signal4set;    
                  var_dataRead(12) := SP_DMA_STATUS_signal5set;    
                  var_dataRead(13) := SP_DMA_STATUS_signal6set;    
                  var_dataRead(14) := SP_DMA_STATUS_signal7set;    
               when x"40014" => var_dataRead(0) := SP_DMA_STATUS_dmafull;    
               when x"40018" => var_dataRead(0) := SP_DMA_STATUS_dmabusy;    
               when x"4001C" => 
                  var_dataRead(0) := SP_SEMAPHORE;    
                  SP_SEMAPHORE    <= '1';
               when x"80000" => var_dataRead(11 downto 0) := std_logic_vector(SP_PC);    
               when others   => null;
            end case;
              
            if (bus_reg_req_read = '1') then -- todo: check for RSP COP0
               bus_done         <= '1';              
               bus_dataRead     <= var_dataRead;
               bus_reg_req_read <= '0';
            end if;
            
            -- register write access
            if (bus_reg_req_write = '1') then -- todo: check for RSP COP0
            
               if (bus_reg_req_write = '1') then
                  bus_done          <= '1';
                  bus_reg_req_write <= '0';
               end if;
               
               case (reg_addr(19 downto 2) & "00") is
                  when x"40000" => SP_DMA_SPADDR  <= unsigned(reg_dataWrite(12 downto 3));   
                  when x"40004" => SP_DMA_RAMADDR <= unsigned(reg_dataWrite(23 downto 3));   
                  when x"40008" | x"4000C" => 
                     SP_DMA_LEN    <= unsigned(reg_dataWrite(11 downto  3));     
                     SP_DMA_COUNT  <= unsigned(reg_dataWrite(19 downto 12));     
                     SP_DMA_SKIP   <= unsigned(reg_dataWrite(31 downto 23));
                     SP_DMA_STATUS_dmafull <= '1';
                     if (bus_addr(19 downto 2) & "00" = x"40008") then dma_next_isWrite <= '0'; else dma_next_isWrite <= '1'; end if;
                  when x"40010" => 
                     if (reg_dataWrite(0 ) = '1') then SP_DMA_STATUS_halt        <= '0'; end if;
                     if (reg_dataWrite(1 ) = '1') then SP_DMA_STATUS_halt        <= '1'; end if;
                     if (reg_dataWrite(2 ) = '1') then SP_DMA_STATUS_broke       <= '0'; end if;
                     if (reg_dataWrite(3 ) = '1') then irq_out                   <= '0'; end if;
                     if (reg_dataWrite(4 ) = '1') then irq_out                   <= '1'; end if;
                     if (reg_dataWrite(5 ) = '1') then SP_DMA_STATUS_singlestep  <= '0'; end if;
                     if (reg_dataWrite(6 ) = '1') then SP_DMA_STATUS_singlestep  <= '1'; end if;
                     if (reg_dataWrite(7 ) = '1') then SP_DMA_STATUS_irqonbreak  <= '0'; end if;
                     if (reg_dataWrite(8 ) = '1') then SP_DMA_STATUS_irqonbreak  <= '1'; end if;
                     if (reg_dataWrite(9 ) = '1') then SP_DMA_STATUS_signal0set  <= '0'; end if;
                     if (reg_dataWrite(10) = '1') then SP_DMA_STATUS_signal0set  <= '1'; end if;
                     if (reg_dataWrite(11) = '1') then SP_DMA_STATUS_signal1set  <= '0'; end if;
                     if (reg_dataWrite(12) = '1') then SP_DMA_STATUS_signal1set  <= '1'; end if;
                     if (reg_dataWrite(13) = '1') then SP_DMA_STATUS_signal2set  <= '0'; end if;
                     if (reg_dataWrite(14) = '1') then SP_DMA_STATUS_signal2set  <= '1'; end if;
                     if (reg_dataWrite(15) = '1') then SP_DMA_STATUS_signal3set  <= '0'; end if;
                     if (reg_dataWrite(16) = '1') then SP_DMA_STATUS_signal3set  <= '1'; end if;
                     if (reg_dataWrite(17) = '1') then SP_DMA_STATUS_signal4set  <= '0'; end if;
                     if (reg_dataWrite(18) = '1') then SP_DMA_STATUS_signal4set  <= '1'; end if;
                     if (reg_dataWrite(19) = '1') then SP_DMA_STATUS_signal5set  <= '0'; end if;
                     if (reg_dataWrite(20) = '1') then SP_DMA_STATUS_signal5set  <= '1'; end if;
                     if (reg_dataWrite(21) = '1') then SP_DMA_STATUS_signal6set  <= '0'; end if;
                     if (reg_dataWrite(22) = '1') then SP_DMA_STATUS_signal6set  <= '1'; end if;
                     if (reg_dataWrite(23) = '1') then SP_DMA_STATUS_signal7set  <= '0'; end if;
                     if (reg_dataWrite(24) = '1') then SP_DMA_STATUS_signal7set  <= '1'; end if;
                  when x"4001C" => SP_SEMAPHORE <= '0';    
                  when x"80000" => SP_PC <= unsigned(reg_dataWrite(11 downto 0));    
                  when others   => null;
               end case;
            end if;
            
            -- Bus/DMA Memory access
            case (MEMSTATE) is
            
               when MEM_IDLE =>
                  if (imem_wren_bus = '1') then
                     bus_done       <= '1';
                     imem_wren_bus  <= '0';
                     imem_wren_a    <= '1';
                     mem_address_a <= std_logic_vector(bus_addr(11 downto 3));
                     if (bus_addr(2) = '1') then
                        mem_be_a   <= x"F0";
                        mem_data_a <= byteswap32(bus_dataWrite) & 32x"0";
                     else
                        mem_be_a   <= x"0F";
                        mem_data_a <= 32x"0" & byteswap32(bus_dataWrite);
                     end if;
                     
                  elsif (dmem_wren_bus = '1') then
                     bus_done       <= '1';
                     dmem_wren_bus  <= '0';
                     dmem_wren_a    <= '1';
                     mem_address_a <= std_logic_vector(bus_addr(11 downto 3));
                     if (bus_addr(2) = '1') then
                        mem_be_a   <= x"F0";
                        mem_data_a <= byteswap32(bus_dataWrite) & 32x"0";
                     else
                        mem_be_a   <= x"0F";
                        mem_data_a <= 32x"0" & byteswap32(bus_dataWrite);
                     end if;
                  
                  elsif (imem_rden_bus = '1') then
                     imem_rden_bus <= '0';
                     mem_address_a <= std_logic_vector(bus_addr(11 downto 3));
                     MEMSTATE      <= MEM_BUS_WAIT_IMEM;
                  
                  elsif (dmem_rden_bus = '1') then
                     dmem_rden_bus <= '0';
                     mem_address_a <= std_logic_vector(bus_addr(11 downto 3));
                     MEMSTATE      <= MEM_BUS_WAIT_DMEM;
                     
                  elsif (fifoin_Empty = '0') then
                     if (SP_DMA_CURRENT_SPADDR(12) = '1') then
                        imem_wren_a <= '1';
                     else
                        dmem_wren_a <= '1';
                     end if;
                     mem_address_a <= std_logic_vector(SP_DMA_CURRENT_SPADDR(11 downto 3));
                     mem_be_a      <= x"FF";
                     mem_data_a    <= fifoin_Dout;
                     fifoin_Rd     <= '1';
                     SP_DMA_CURRENT_SPADDR(11 downto 3) <= SP_DMA_CURRENT_SPADDR(11 downto 3) + 1;
                    
                  elsif (SP_DMA_STATUS_dmabusy = '1' and fifoout_nearfull = '0' and dma_isWrite = '1' and SP_DMA_CURRENT_WORKLEN2 > 0) then
                     MEMSTATE      <= MEM_STARTDMA;
                     mem_address_a <= std_logic_vector(SP_DMA_CURRENT_SPADDR(11 downto 3));
                     SP_DMA_CURRENT_SPADDR(11 downto 3) <= SP_DMA_CURRENT_SPADDR(11 downto 3) + 1;
                     if (SP_DMA_CURRENT_WORKLEN2 >= 16) then
                        SP_DMA_CURRENT_FETCHLEN <= 16;
                        SP_DMA_CURRENT_WORKLEN2 <= SP_DMA_CURRENT_WORKLEN2 - 16;
                     else
                        SP_DMA_CURRENT_FETCHLEN <= to_integer(SP_DMA_CURRENT_WORKLEN2(3 downto 0));
                        SP_DMA_CURRENT_WORKLEN2 <= (others => '0');
                     end if;
                     
                  end if;
                  
               when MEM_BUS_WAIT_IMEM =>
                  MEMSTATE <= MEM_READ_IMEM;
                  
               when MEM_READ_IMEM =>
                  MEMSTATE <= MEM_IDLE;
                  bus_done <= '1';
                  if (bus_addr(2) = '1') then
                     bus_dataRead   <= byteswap32(imem_q_a(63 downto 32));
                  else
                     bus_dataRead   <= byteswap32(imem_q_a(31 downto 0));
                  end if;
                  
               when MEM_BUS_WAIT_DMEM =>
                  MEMSTATE <= MEM_READ_DMEM;
                  
               when MEM_READ_DMEM =>
                  MEMSTATE <= MEM_IDLE;
                  bus_done <= '1';
                  if (bus_addr(2) = '1') then
                     bus_dataRead   <= byteswap32(dmem_q_a(63 downto 32));
                  else
                     bus_dataRead   <= byteswap32(dmem_q_a(31 downto 0));
                  end if;
                  
               when MEM_STARTDMA =>
                  MEMSTATE      <= MEM_RUNDMA;
                  mem_address_a <= std_logic_vector(SP_DMA_CURRENT_SPADDR(11 downto 3));
                  SP_DMA_CURRENT_SPADDR(11 downto 3) <= SP_DMA_CURRENT_SPADDR(11 downto 3) + 1;
            
               when MEM_RUNDMA =>
                  mem_address_a <= std_logic_vector(SP_DMA_CURRENT_SPADDR(11 downto 3));
                  if (SP_DMA_CURRENT_FETCHLEN > 1) then
                     SP_DMA_CURRENT_SPADDR(11 downto 3) <= SP_DMA_CURRENT_SPADDR(11 downto 3) + 1;
                  else
                     MEMSTATE <= MEM_IDLE;
                     SP_DMA_CURRENT_SPADDR(11 downto 3) <= SP_DMA_CURRENT_SPADDR(11 downto 3) - 1;
                  end if;
                  SP_DMA_CURRENT_FETCHLEN <= SP_DMA_CURRENT_FETCHLEN - 1;
                  if (SP_DMA_CURRENT_SPADDR(12) = '1') then
                     fifoout_Din <= imem_q_a;
                  else
                     fifoout_Din <= dmem_q_a;
                  end if;
                  fifoout_Wr <= '1';
            
            end case;
            
            -- next DMA
            if (bus_reg_req_write = '0' and SP_DMA_STATUS_dmafull = '1' and (SP_DMA_STATUS_dmabusy = '0' or dma_startnext = '1')) then
               dma_startnext           <= '0';
               fifo_reset              <= '1';
               SP_DMA_STATUS_dmabusy   <= '1';
               SP_DMA_STATUS_dmafull   <= '0';
               dma_isWrite             <= dma_next_isWrite;
               SP_DMA_CURRENT_SPADDR   <= SP_DMA_SPADDR;
               SP_DMA_CURRENT_RAMADDR  <= SP_DMA_RAMADDR;
               SP_DMA_CURRENT_LEN      <= SP_DMA_LEN;
               SP_DMA_CURRENT_COUNT    <= SP_DMA_COUNT;
               SP_DMA_CURRENT_SKIP     <= SP_DMA_SKIP;
               SP_DMA_CURRENT_WORKLEN  <= ('0' & SP_DMA_LEN) + 1;
               SP_DMA_CURRENT_WORKLEN2 <= ('0' & SP_DMA_LEN) + 1;
            end if;
            
            if (SP_DMA_STATUS_dmabusy = '1') then
               if ((dma_isWrite = '1' or (dma_isWrite = '0' and fifoin_Empty = '1')) and SP_DMA_CURRENT_WORKLEN = 0) then
                  if (SP_DMA_CURRENT_COUNT > 0) then
                     SP_DMA_CURRENT_COUNT    <= SP_DMA_CURRENT_COUNT - 1;
                     SP_DMA_CURRENT_RAMADDR  <= SP_DMA_CURRENT_RAMADDR + SP_DMA_CURRENT_SKIP;
                     SP_DMA_CURRENT_WORKLEN  <= ('0' & SP_DMA_LEN) + 1;
                     SP_DMA_CURRENT_WORKLEN2 <= ('0' & SP_DMA_LEN) + 1;
                  else
                     SP_DMA_CURRENT_LEN    <= (others => '1');
                     if (SP_DMA_STATUS_dmafull = '1') then
                        dma_startnext         <= '1';
                     else
                        SP_DMA_STATUS_dmabusy <= '0';
                     end if;
                  end if;
               end if;
            end if; 
            
            -- DMA prefetch
            case (DMASTATE) is
            
               when DMA_IDLE =>
                  if (SP_DMA_STATUS_dmabusy = '1') then
                     if (dma_isWrite = '0') then
                        if (fifoin_nearfull = '0' and SP_DMA_CURRENT_WORKLEN > 0) then
                           DMASTATE         <= DMA_READBLOCK;
                           rdram_request    <= '1';
                           rdram_rnw        <= '1';
                           rdram_address    <= "0000" & SP_DMA_CURRENT_RAMADDR & "000";
                           if (SP_DMA_CURRENT_WORKLEN >= 16) then
                              rdram_burstcount       <= to_unsigned(16,10);
                           else
                              rdram_burstcount       <= SP_DMA_CURRENT_WORKLEN;
                           end if;
                        end if;
                     else
                        if (fifoout_Empty = '0' and SP_DMA_CURRENT_WORKLEN > 0) then
                           DMASTATE         <= DMA_WRITEONE;
                           rdram_request    <= '1';
                           rdram_rnw        <= '0';
                           rdram_address    <= "0000" & SP_DMA_CURRENT_RAMADDR & "000";
                           rdram_burstcount <= 10x"001";
                        end if;                        
                     end if;
                  end if;
                  
               when DMA_READBLOCK =>
                  if (rdram_done = '1') then
                     DMASTATE               <= DMA_IDLE;
                     SP_DMA_CURRENT_WORKLEN <= SP_DMA_CURRENT_WORKLEN - rdram_burstcount;
                     SP_DMA_CURRENT_RAMADDR <= SP_DMA_CURRENT_RAMADDR + rdram_burstcount;
                  end if;
                  
               when DMA_WRITEONE =>
                  if (rdram_done = '1') then
                     DMASTATE               <= DMA_IDLE;
                     fifoout_Rd             <= '1';
                     SP_DMA_CURRENT_WORKLEN <= SP_DMA_CURRENT_WORKLEN - rdram_burstcount;
                     SP_DMA_CURRENT_RAMADDR <= SP_DMA_CURRENT_RAMADDR + rdram_burstcount;
                  end if;
            
            end case;
            
         end if;
      end if;
   end process;
   
   rdram_writeMask <= x"FF";
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         
         if (rdram_granted = '1') then
            dma_store <= '1';
         end if;
         
         if (rdram_done = '1') then
            dma_store <= '0';
         end if;
         
      end if;
   end process; 
   
   -- DMA exchange
   iSyncFifo_IN: entity mem.SyncFifoFallThrough
   generic map
   (
      SIZE             => 64,
      DATAWIDTH        => 64,
      NEARFULLDISTANCE => 16
   )
   port map
   ( 
      clk      => clk2x,
      reset    => fifo_reset,  
      Din      => ddr3_DOUT,     
      Wr       => (ddr3_DOUT_READY and dma_store),      
      Full     => open,    
      NearFull => fifoin_nearfull,
      Dout     => fifoin_Dout,    
      Rd       => (fifoin_Rd and clk2xIndex),      
      Empty    => fifoin_Empty   
   );
   
   iSyncFifo_OUT: entity mem.SyncFifoFallThrough
   generic map
   (
      SIZE             => 64,
      DATAWIDTH        => 64,
      NEARFULLDISTANCE => 32
   )
   port map
   ( 
      clk      => clk2x,
      reset    => fifo_reset,  
      Din      => fifoout_Din,     
      Wr       => (fifoout_Wr and clk2xIndex),
      Full     => open,    
      NearFull => fifoout_nearfull,
      Dout     => rdram_dataWrite,    
      Rd       => (fifoout_rd and clk2xIndex),      
      Empty    => fifoout_Empty   
   );
   
   -- Memory
   iDMEM: entity work.dpram_dif_be
   generic map 
   ( 
      addr_width_a    => 9,
      data_width_a    => 64,
      addr_width_b    => 10,
      data_width_b    => 32,
      width_byteena_a => 8,
      width_byteena_b => 4
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => mem_address_a,
      data_a      => mem_data_a,
      wren_a      => dmem_wren_a,
      byteena_a   => mem_be_a,
      q_a         => dmem_q_a,
      
      clock_b     => clk1x,
      address_b   => dmem_address_b,
      data_b      => dmem_data_b,
      wren_b      => dmem_wren_b,
      byteena_b   => "1111",
      q_b         => dmem_q_b
   );
   
   iIMEM: entity work.dpram_dif_be
   generic map 
   ( 
      addr_width_a    => 9,
      data_width_a    => 64,
      addr_width_b    => 10,
      data_width_b    => 32,
      width_byteena_a => 8,
      width_byteena_b => 4
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => mem_address_a,
      data_a      => mem_data_a,
      wren_a      => imem_wren_a,
      byteena_a   => mem_be_a,
      q_a         => imem_q_a,
      
      clock_b     => clk1x,
      address_b   => imem_address_b,
      data_b      => imem_data_b,
      wren_b      => imem_wren_b,
      byteena_b   => "1111",
      q_b         => imem_q_b
   );
        
end architecture;





