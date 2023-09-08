-----------------------------------------------------------------
--------------- DDR3Mux Package  --------------------------------
-----------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pSDRAM is

   constant SDRAMMUXCOUNT : integer := 3;
   
   constant SDRAMMUX_SAV  : integer := 0;
   constant SDRAMMUX_PI   : integer := 1;
   constant SDRAMMUX_RDP  : integer := 2;
   
   type tSDRAMSingle     is array(0 to SDRAMMUXCOUNT - 1) of std_logic;
   type tSDRAMReqAddr    is array(0 to SDRAMMUXCOUNT - 1) of unsigned(26 downto 0);
   type tSDRAMBurstcount is array(0 to SDRAMMUXCOUNT - 1) of unsigned(7 downto 0);
   type tSDRAMBwriteMask is array(0 to SDRAMMUXCOUNT - 1) of std_logic_vector(3 downto 0);
   type tSDRAMBwriteData is array(0 to SDRAMMUXCOUNT - 1) of std_logic_vector(31 downto 0);
  
end package;

-----------------------------------------------------------------
--------------- SDRamMux module    -------------------------------
-----------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pSDRAM.all;

entity SDRamMux is
   port 
   (
      clk1x                : in  std_logic;
                           
      error                : out std_logic;
      
      sdram_ena            : out std_logic;
      sdram_rnw            : out std_logic;
      sdram_Adr            : out std_logic_vector(26 downto 0);
      sdram_be             : out std_logic_vector(3 downto 0);
      sdram_dataWrite      : out std_logic_vector(31 downto 0);
      sdram_done           : in  std_logic;  
      sdram_dataRead       : in  std_logic_vector(31 downto 0);

      sdramMux_request     : in  tSDRAMSingle;
      sdramMux_rnw         : in  tSDRAMSingle;    
      sdramMux_address     : in  tSDRAMReqAddr;
      sdramMux_burstcount  : in  tSDRAMBurstcount;  
      sdramMux_writeMask   : in  tSDRAMBwriteMask;  
      sdramMux_dataWrite   : in  tSDRAMBwriteData;
      sdramMux_granted     : out tSDRAMSingle;
      sdramMux_done        : out tSDRAMSingle;
      sdramMux_dataRead    : out std_logic_vector(31 downto 0);
      
      rdp9fifo_reset       : in  std_logic; 
      rdp9fifo_Din         : in  std_logic_vector(49 downto 0); -- 32bit data + 18 bit address
      rdp9fifo_Wr          : in  std_logic;  
      rdp9fifo_nearfull    : out std_logic;  
      rdp9fifo_empty       : out std_logic;        
      
      rdp9fifoZ_reset      : in  std_logic; 
      rdp9fifoZ_Din        : in  std_logic_vector(49 downto 0); -- 32bit data + 18 bit address
      rdp9fifoZ_Wr         : in  std_logic;  
      rdp9fifoZ_nearfull   : out std_logic;  
      rdp9fifoZ_empty      : out std_logic  
   );
end entity;

architecture arch of SDRamMux is

   type tstate is
   (
      IDLE,
      WAITREAD,
      WAITWRITE,
      WAITFIFOWRITE
   );
   signal state         : tstate := IDLE;
   
   signal timeoutCount  : unsigned(12 downto 0);
   
   signal req_latched   : tSDRAMSingle := (others => '0');
   signal lastIndex     : integer range 0 to SDRAMMUXCOUNT - 1;
   signal remain        : unsigned(7 downto 0);

   -- rdp fifo
   signal rdpfifo_Dout     : std_logic_vector(49 downto 0);
   signal rdpfifo_Rd       : std_logic := '0';    
   
   -- rdp fifo Z Buffer
   signal rdpfifoZ_Dout    : std_logic_vector(49 downto 0);
   signal rdpfifoZ_Rd      : std_logic := '0'; 

begin 

   sdramMux_dataRead <= sdram_dataRead;

   process (all)
   begin
      
      sdramMux_done <= (others => '0');
      if (state = WAITWRITE and sdram_ena = '1') then
         sdramMux_done(lastIndex) <= '1';   
      elsif (state = WAITREAD and sdram_done = '1' and remain <= 1) then
         sdramMux_done(lastIndex) <= '1';    
      end if;
      
   end process;
      

   process (clk1x)
      variable activeRequest : std_logic;
      variable activeIndex   : integer range 0 to SDRAMMUXCOUNT - 1;
   begin
      if rising_edge(clk1x) then
      
         error             <= '0';
         sdram_ena         <= '0';
         rdpfifo_rd        <= '0';
         rdpfifoZ_rd       <= '0';
         sdramMux_granted  <= (others => '0');

         -- request handling
         activeRequest := '0';
         for i in 0 to SDRAMMUXCOUNT - 1 loop
            if (sdramMux_request(i) = '1') then
               req_latched(i) <= '1';
            end if;
            
            if (sdramMux_request(i) = '1' or req_latched(i) = '1') then
               activeRequest := '1';
               activeIndex   := i;
            end if;
            
         end loop;

         -- main statemachine
         case (state) is
            when IDLE =>
               
               lastIndex    <= activeIndex;
               timeoutCount <= (others => '0');
            
               if (activeRequest = '1') then
               
                  req_latched(activeIndex) <= '0';
                  sdram_dataWrite          <= sdramMux_dataWrite(activeIndex);
                  sdram_be                 <= sdramMux_writeMask(activeIndex);
                  sdram_Adr                <= std_logic_vector(sdramMux_address(activeIndex));
                  
                  remain                   <= sdramMux_burstcount(activeIndex);
   
                  if (sdramMux_rnw(activeIndex) = '1') then
                     state                         <= WAITREAD;
                     sdram_ena                     <= '1';
                     sdram_rnw                     <= '1';
                     sdramMux_granted(activeIndex) <= '1';
                  else
                     state                         <= WAITWRITE;
                     sdram_ena                     <= '1';
                     sdram_rnw                     <= '0';
                  end if;
                  
               elsif (rdp9fifo_empty = '0') then
                  
                  state             <= WAITFIFOWRITE;
                  rdpfifo_rd        <= '1';
                  sdram_ena         <= '1';
                  sdram_rnw         <= '0';
                  sdram_dataWrite   <= rdpfifo_Dout(31 downto 0);      
                  sdram_be          <= x"F";       
                  sdram_Adr         <= 7x"0" & rdpfifo_Dout(49 downto 32) & "00";               
                  
               elsif (rdp9fifoZ_empty = '0') then
                  
                  state             <= WAITFIFOWRITE;
                  rdpfifoZ_rd       <= '1';
                  sdram_ena         <= '1';
                  sdram_rnw         <= '0';
                  sdram_dataWrite   <= rdpfifoZ_Dout(31 downto 0);      
                  sdram_be          <= x"F";       
                  sdram_Adr         <= 7x"0" & rdpfifoZ_Dout(49 downto 32) & "00";
               
               end if;   
                  
            when WAITWRITE | WAITFIFOWRITE =>
               timeoutCount <= timeoutCount + 1;
               if (timeoutCount(timeoutCount'high) = '1') then
                  error <= '1';
               end if;
               if (sdram_done = '1') then
                  state <= IDLE;
               end if;
                  
            when WAITREAD =>
               timeoutCount <= timeoutCount + 1;
               if (timeoutCount(timeoutCount'high) = '1') then
                  error <= '1';
               end if;
               if (sdram_done = '1') then
                  timeoutCount <= (others => '0');
                  
                  remain <= remain - 1;
                  if (remain <= 1) then
                     state     <= IDLE;  
                  else
                     sdram_Adr <= std_logic_vector(unsigned(sdram_Adr) + 4);
                     sdram_ena <= '1';
                  end if;
               end if;
         
         end case;

      end if;
   end process;
   
   iRDPFifo: entity mem.SyncFifoFallThrough
   generic map
   (
      SIZE             => 128,
      DATAWIDTH        => 32 + 18, -- 32bit data + 18 bit address
      NEARFULLDISTANCE => 64
   )
   port map
   ( 
      clk      => clk1x,
      reset    => rdp9fifo_reset,  
      Din      => rdp9fifo_Din,     
      Wr       => rdp9fifo_Wr,
      Full     => open,    
      NearFull => rdp9fifo_nearfull,
      Dout     => rdpfifo_Dout,    
      Rd       => rdpfifo_rd,      
      Empty    => rdp9fifo_empty   
   );   
   
   iRDPFifoZ: entity mem.SyncFifoFallThrough
   generic map
   (
      SIZE             => 128,
      DATAWIDTH        => 32 + 18, -- 32bit data + 18 bit address
      NEARFULLDISTANCE => 64
   )
   port map
   ( 
      clk      => clk1x,
      reset    => rdp9fifoZ_reset,  
      Din      => rdp9fifoZ_Din,     
      Wr       => rdp9fifoZ_Wr,
      Full     => open,    
      NearFull => rdp9fifoZ_nearfull,
      Dout     => rdpfifoZ_Dout,    
      Rd       => rdpfifoZ_rd,      
      Empty    => rdp9fifoZ_empty   
   );

   
   
end architecture;





