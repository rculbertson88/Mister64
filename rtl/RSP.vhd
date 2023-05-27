library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pFunctions.all;

entity RSP is
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      irq_out              : out std_logic := '0';
      
      bus_addr             : in  unsigned(19 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done             : out std_logic := '0'
   );
end entity;

architecture arch of RSP is

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

   signal SP_DMA_CURRENT_SPADDR     : unsigned(12 downto 3) := (others => '0');
   signal SP_DMA_CURRENT_RAMADDR    : unsigned(23 downto 3) := (others => '0');
   signal SP_DMA_CURRENT_LEN        : unsigned(11 downto 3) := (others => '0');
   signal SP_DMA_CURRENT_COUNT      : unsigned(7 downto 0)  := (others => '0');
   signal SP_DMA_CURRENT_SKIP       : unsigned(11 downto 3) := (others => '0');
   
   signal dma_next_isWrite          : std_logic := '0';
   signal dma_isWrite               : std_logic := '0';
   
   signal bus_dmem_ram              : std_logic := '0';
   signal bus_dmem_ram_1            : std_logic := '0';
   signal bus_imem_ram              : std_logic := '0';
   signal bus_imem_ram_1            : std_logic := '0';
   
   signal mem_address_bus           : std_logic_vector(9 downto 0) := (others => '0');
   signal mem_address_dma           : std_logic_vector(9 downto 0) := (others => '0');
   signal mem_data_bus              : std_logic_vector(31 downto 0) := (others => '0');
   signal mem_data_dma              : std_logic_vector(31 downto 0) := (others => '0');
   
   -- DMEM
   signal dmem_address_a            : std_logic_vector(9 downto 0) := (others => '0');
   signal dmem_address_b            : std_logic_vector(9 downto 0) := (others => '0');    
   signal dmem_data_a               : std_logic_vector(31 downto 0) := (others => '0');
   signal dmem_data_b               : std_logic_vector(31 downto 0) := (others => '0');
   signal dmem_wren_a               : std_logic := '0'; 
   signal dmem_wren_a_dma           : std_logic := '0'; 
   signal dmem_wren_a_bus           : std_logic := '0'; 
   signal dmem_wren_b               : std_logic := '0';   
   signal dmem_q_a                  : std_logic_vector(31 downto 0); 
   signal dmem_q_b                  : std_logic_vector(31 downto 0);  
   
   -- IMEM
   signal imem_address_a            : std_logic_vector(9 downto 0) := (others => '0');
   signal imem_address_b            : std_logic_vector(9 downto 0) := (others => '0');    
   signal imem_data_a               : std_logic_vector(31 downto 0) := (others => '0');
   signal imem_data_b               : std_logic_vector(31 downto 0) := (others => '0');
   signal imem_wren_a               : std_logic := '0'; 
   signal imem_wren_a_dma           : std_logic := '0'; 
   signal imem_wren_a_bus           : std_logic := '0'; 
   signal imem_wren_b               : std_logic := '0';   
   signal imem_q_a                  : std_logic_vector(31 downto 0); 
   signal imem_q_b                  : std_logic_vector(31 downto 0); 

begin 

  process (clk1x)
   begin
      if rising_edge(clk1x) then
      
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
 
         elsif (ce = '1') then
         
            bus_done     <= '0';

            bus_dataRead <= (others => '0');
            
            if (SP_DMA_STATUS_dmabusy = '0') then -- read when DMA is idle
               bus_dmem_ram_1    <= bus_dmem_ram;
               bus_imem_ram_1    <= bus_imem_ram;
               bus_dmem_ram      <= '0';
               bus_imem_ram      <= '0';
               dmem_wren_a_bus   <= '0';
               imem_wren_a_bus   <= '0';
               
               if (dmem_wren_a_bus= '1' or imem_wren_a_bus = '1') then
                  bus_done       <= '1';
               end if;
            end if;
            
            if (bus_dmem_ram_1 = '1') then -- return data one clock cycle later
               bus_done       <= '1';
               bus_dataRead   <= byteswap32(dmem_q_a);
            end if;            
            
            if (bus_imem_ram_1 = '1') then
               bus_done       <= '1';
               bus_dataRead   <= byteswap32(imem_q_a);
            end if;

            -- bus read
            if (bus_read = '1') then
            
               mem_address_bus <= std_logic_vector(bus_addr(11 downto 2));
            
               if (bus_addr < 16#40000#) then -- DMEM/IMEM
                  if (bus_addr(12) = '1') then
                     bus_imem_ram <= '1';
                  else
                     bus_dmem_ram <= '1';
                  end if;
               else
                  bus_done <= '1';
                  case (bus_addr(19 downto 2) & "00") is
                     when x"40000" => bus_dataRead(12 downto 3) <= std_logic_vector(SP_DMA_CURRENT_SPADDR);    
                     when x"40004" => bus_dataRead(23 downto 3) <= std_logic_vector(SP_DMA_CURRENT_RAMADDR);    
                     when x"40008" | x"4000C" => 
                        bus_dataRead(11 downto  3) <= std_logic_vector(SP_DMA_CURRENT_LEN);    
                        bus_dataRead(19 downto 12) <= std_logic_vector(SP_DMA_CURRENT_COUNT);    
                        bus_dataRead(31 downto 23) <= std_logic_vector(SP_DMA_CURRENT_SKIP);    
                     when x"40010" => 
                        bus_dataRead(0)  <= SP_DMA_STATUS_halt;    
                        bus_dataRead(1)  <= SP_DMA_STATUS_broke;    
                        bus_dataRead(2)  <= SP_DMA_STATUS_dmabusy;    
                        bus_dataRead(3)  <= SP_DMA_STATUS_dmafull;    
                        bus_dataRead(4)  <= SP_DMA_STATUS_iofull;    
                        bus_dataRead(5)  <= SP_DMA_STATUS_singlestep;    
                        bus_dataRead(6)  <= SP_DMA_STATUS_irqonbreak;    
                        bus_dataRead(7)  <= SP_DMA_STATUS_signal0set;    
                        bus_dataRead(8)  <= SP_DMA_STATUS_signal1set;    
                        bus_dataRead(9)  <= SP_DMA_STATUS_signal2set;    
                        bus_dataRead(10) <= SP_DMA_STATUS_signal3set;    
                        bus_dataRead(11) <= SP_DMA_STATUS_signal4set;    
                        bus_dataRead(12) <= SP_DMA_STATUS_signal5set;    
                        bus_dataRead(13) <= SP_DMA_STATUS_signal6set;    
                        bus_dataRead(14) <= SP_DMA_STATUS_signal7set;    
                     when x"40014" => bus_dataRead(0) <= SP_DMA_STATUS_dmafull;    
                     when x"40018" => bus_dataRead(0) <= SP_DMA_STATUS_dmabusy;    
                     when x"4001C" => 
                        bus_dataRead(0) <= SP_SEMAPHORE;    
                        SP_SEMAPHORE    <= '1';
                     when x"80000" => bus_dataRead(11 downto 0) <= std_logic_vector(SP_PC);    
                     when others   => null;
                  end case;
               end if;
            end if;

            -- bus write
            if (bus_write = '1') then
               
               mem_address_bus <= std_logic_vector(bus_addr(11 downto 2));
               mem_data_bus    <= bus_dataWrite;
            
               if (bus_addr < 16#40000#) then -- DMEM/IMEM
                  if (bus_addr(12) = '1') then
                     imem_wren_a_bus <= '1';
                  else
                     dmem_wren_a_bus <= '1';
                  end if; 
               else
                  bus_done <= '1';
                  case (bus_addr(19 downto 2) & "00") is
                     when x"40000" => SP_DMA_SPADDR  <= unsigned(bus_dataWrite(12 downto 3));   
                     when x"40004" => SP_DMA_RAMADDR <= unsigned(bus_dataWrite(23 downto 3));   
                     when x"40008" | x"4000C" => 
                        SP_DMA_LEN    <= unsigned(bus_dataWrite(11 downto  3));     
                        SP_DMA_COUNT  <= unsigned(bus_dataWrite(19 downto 12));     
                        SP_DMA_SKIP   <= unsigned(bus_dataWrite(31 downto 23));
                        SP_DMA_STATUS_dmafull <= '1';
                        if (bus_addr(19 downto 2) & "00" = x"40008") then dma_next_isWrite <= '0'; else dma_next_isWrite <= '1'; end if;
                     when x"40010" => 
                        if (bus_dataWrite(0 ) = '1') then SP_DMA_STATUS_halt        <= '0'; end if;
                        if (bus_dataWrite(1 ) = '1') then SP_DMA_STATUS_halt        <= '1'; end if;
                        if (bus_dataWrite(2 ) = '1') then SP_DMA_STATUS_broke       <= '0'; end if;
                        if (bus_dataWrite(3 ) = '1') then irq_out                   <= '0'; end if;
                        if (bus_dataWrite(4 ) = '1') then irq_out                   <= '1'; end if;
                        if (bus_dataWrite(5 ) = '1') then SP_DMA_STATUS_singlestep  <= '0'; end if;
                        if (bus_dataWrite(6 ) = '1') then SP_DMA_STATUS_singlestep  <= '1'; end if;
                        if (bus_dataWrite(7 ) = '1') then SP_DMA_STATUS_irqonbreak  <= '0'; end if;
                        if (bus_dataWrite(8 ) = '1') then SP_DMA_STATUS_irqonbreak  <= '1'; end if;
                        if (bus_dataWrite(9 ) = '1') then SP_DMA_STATUS_signal0set  <= '0'; end if;
                        if (bus_dataWrite(10) = '1') then SP_DMA_STATUS_signal0set  <= '1'; end if;
                        if (bus_dataWrite(11) = '1') then SP_DMA_STATUS_signal1set  <= '0'; end if;
                        if (bus_dataWrite(12) = '1') then SP_DMA_STATUS_signal1set  <= '1'; end if;
                        if (bus_dataWrite(13) = '1') then SP_DMA_STATUS_signal2set  <= '0'; end if;
                        if (bus_dataWrite(14) = '1') then SP_DMA_STATUS_signal2set  <= '1'; end if;
                        if (bus_dataWrite(15) = '1') then SP_DMA_STATUS_signal3set  <= '0'; end if;
                        if (bus_dataWrite(16) = '1') then SP_DMA_STATUS_signal3set  <= '1'; end if;
                        if (bus_dataWrite(17) = '1') then SP_DMA_STATUS_signal4set  <= '0'; end if;
                        if (bus_dataWrite(18) = '1') then SP_DMA_STATUS_signal4set  <= '1'; end if;
                        if (bus_dataWrite(19) = '1') then SP_DMA_STATUS_signal5set  <= '0'; end if;
                        if (bus_dataWrite(20) = '1') then SP_DMA_STATUS_signal5set  <= '1'; end if;
                        if (bus_dataWrite(21) = '1') then SP_DMA_STATUS_signal6set  <= '0'; end if;
                        if (bus_dataWrite(22) = '1') then SP_DMA_STATUS_signal6set  <= '1'; end if;
                        if (bus_dataWrite(23) = '1') then SP_DMA_STATUS_signal7set  <= '0'; end if;
                        if (bus_dataWrite(24) = '1') then SP_DMA_STATUS_signal7set  <= '1'; end if;
                     when x"4001C" => SP_SEMAPHORE <= '0';    
                     when x"80000" => SP_PC <= unsigned(bus_dataWrite(11 downto 0));    
                     when others   => null;
                  end case;
               end if;
            end if;
            
            if (SP_DMA_STATUS_dmafull = '1') then
               report "RSP DMA not implemented" severity failure;
            end if;

         end if;
      end if;
   end process;
   
   dmem_address_a    <= mem_address_dma when (SP_DMA_STATUS_dmabusy = '1') else mem_address_bus;
   dmem_data_a       <= mem_data_dma when (SP_DMA_STATUS_dmabusy = '1') else byteswap32(mem_data_bus);
   dmem_wren_a       <= dmem_wren_a_bus or dmem_wren_a_dma;
   
   iDMEM: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 10,
      data_width_a  => 32, -- must be 64bit for DMA!
      addr_width_b  => 10,
      data_width_b  => 32
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => dmem_address_a,
      data_a      => dmem_data_a,
      wren_a      => dmem_wren_a,
      q_a         => dmem_q_a,
      
      clock_b     => clk1x,
      address_b   => dmem_address_b,
      data_b      => dmem_data_b,
      wren_b      => dmem_wren_b,
      q_b         => dmem_q_b
   );
   
   imem_address_a    <= mem_address_dma when (SP_DMA_STATUS_dmabusy = '1') else mem_address_bus;
   imem_data_a       <= mem_data_dma when (SP_DMA_STATUS_dmabusy = '1') else byteswap32(mem_data_bus);
   imem_wren_a       <= imem_wren_a_bus or imem_wren_a_dma;
   
   iIMEM: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 10,
      data_width_a  => 32, -- must be 64bit for DMA!
      addr_width_b  => 10,
      data_width_b  => 32
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => imem_address_a,
      data_a      => imem_data_a,
      wren_a      => imem_wren_a,
      q_a         => imem_q_a,
      
      clock_b     => clk1x,
      address_b   => imem_address_b,
      data_b      => imem_data_b,
      wren_b      => imem_wren_b,
      q_b         => imem_q_b
   );
        
end architecture;





