library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity SI is
   port 
   (
      clk1x            : in  std_logic;
      ce               : in  std_logic;
      reset            : in  std_logic;
      
      irq_out          : out std_logic := '0';
      
      bus_addr         : in  unsigned(19 downto 0); 
      bus_dataWrite    : in  std_logic_vector(31 downto 0);
      bus_read         : in  std_logic;
      bus_write        : in  std_logic;
      bus_dataRead     : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done         : out std_logic := '0'
   );
end entity;

architecture arch of SI is

   signal SI_DRAM_ADDR           : unsigned(23 downto 0); -- 0x04800000 (W): [23:0] starting RDRAM address
   signal SI_PIF_ADDR_RD64B      : unsigned(31 downto 0); -- 0x04800004 SI address read 64B (W): [] any write causes a 64B DMA write
   signal SI_PIF_ADDR_WR64B      : unsigned(31 downto 0); -- 0x04800010 SI address write 64B (W) : [] any write causes a 64B DMA read
   signal SI_STATUS_DMA_busy     : std_logic;             -- 0x04800018 (W): [] any write clears interrupt (R) : [0] DMA busy
   signal SI_STATUS_IO_busy      : std_logic;             -- 0x04800018 (W): [] any write clears interrupt (R) : [1] IO read busy 
   signal SI_STATUS_readPending  : std_logic;             -- 0x04800018 (W): [] any write clears interrupt (R) : [2] readPending
   signal SI_STATUS_DMA_error    : std_logic;             -- 0x04800018 (W): [] any write clears interrupt (R) : [3] dmaError
   signal SI_STATUS_pchState     : unsigned(3 downto 0);  -- 0x04800018 (W): [] any write clears interrupt (R) : [7:4] pchState
   signal SI_STATUS_dmaState     : unsigned(3 downto 0);  -- 0x04800018 (W): [] any write clears interrupt (R) : [11:8] dmaState
   signal SI_STATUS_IRQ          : std_logic;             -- 0x04800018 (W): [] any write clears interrupt (R) : [12] interrupt

begin 

   irq_out <= SI_STATUS_IRQ;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (reset = '1') then
            
            bus_done             <= '0';
            
            SI_DRAM_ADDR            <= (others => '0');
            SI_PIF_ADDR_RD64B       <= (others => '0');
            SI_PIF_ADDR_WR64B       <= (others => '0');
            SI_STATUS_DMA_busy      <= '0';
            SI_STATUS_IO_busy       <= '0';
            SI_STATUS_readPending   <= '0';
            SI_STATUS_DMA_error     <= '0';
            SI_STATUS_pchState      <= (others => '0');
            SI_STATUS_dmaState      <= (others => '0');
            SI_STATUS_IRQ           <= '0';
            
         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_dataRead <= (others => '0');

            -- bus read
            if (bus_read = '1') then
               bus_done <= '1';
               case (bus_addr(19 downto 2) & "00") is   
                  when x"00000" => bus_dataRead(23 downto 0) <= std_logic_vector(SI_DRAM_ADDR);
                  when x"00004" => bus_dataRead              <= std_logic_vector(SI_PIF_ADDR_RD64B);
                  when x"00010" => bus_dataRead              <= std_logic_vector(SI_PIF_ADDR_WR64B);
                  when x"00018" =>
                     bus_dataRead(0)            <= SI_STATUS_DMA_busy;  
                     bus_dataRead(1)            <= SI_STATUS_IO_busy;    
                     bus_dataRead(2)            <= SI_STATUS_readPending;
                     bus_dataRead(3)            <= SI_STATUS_DMA_error;  
                     bus_dataRead(7 downto 4)   <= std_logic_vector(SI_STATUS_pchState);   
                     bus_dataRead(11 downto 8)  <= std_logic_vector(SI_STATUS_dmaState);   
                     bus_dataRead(12)           <= SI_STATUS_IRQ;        
                  when others   => null;                  
               end case;
            end if;
            
            -- bus write
            if (bus_write = '1') then
               bus_done <= '1';
               
               case (bus_addr(19 downto 2) & "00") is
                  when x"00000" => SI_DRAM_ADDR      <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                  when x"00004" => 
                     SI_PIF_ADDR_RD64B  <= unsigned(bus_dataWrite(31 downto 1)) & '0';
                     SI_STATUS_DMA_busy <= '1';
                     
                  when x"00010" => 
                     SI_PIF_ADDR_WR64B  <= unsigned(bus_dataWrite(31 downto 1)) & '0';
                     SI_STATUS_DMA_busy <= '1';
                     
                  when x"00018" => SI_STATUS_IRQ     <= '0';
                  when others   => null;                  
               end case;
               
            end if;
            
            if (SI_STATUS_DMA_busy = '1') then
               report "SI DMA not implemented" severity failure;
            end if;

         end if;
      end if;
   end process;

end architecture;





