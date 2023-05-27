library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity RDP is
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

begin 

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (reset = '1') then
            
            bus_done             <= '0';
            irq_out              <= '0';
            
            DPC_START                <= (others => '0');
            DPC_END_REG              <= (others => '0');
            DPC_CURRENT              <= (others => '0');
            DPC_STATUS_xbus_dmem_dma <= '0';
            DPC_STATUS_freeze        <= '0';
            DPC_STATUS_flush         <= '0';
            DPC_STATUS_start_gclk    <= '0';
            DPC_STATUS_cbuf_ready    <= '1';
            DPC_STATUS_dma_busy      <= '0';
            DPC_STATUS_end_valid     <= '0';
            DPC_STATUS_start_valid   <= '0';
            DPC_CLOCK                <= (others => '0');
            DPC_BUFBUSY              <= (others => '0');
            DPC_PIPEBUSY             <= (others => '0');
            DPC_TMEM                 <= (others => '0');
            
         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_dataRead <= (others => '0');

            -- bus read
            if (bus_read = '1') then
               bus_done <= '1';
               case (bus_addr(19 downto 2) & "00") is   
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
            
            -- bus write
            if (bus_write = '1') then
               bus_done <= '1';
               
               case (bus_addr(19 downto 2) & "00") is
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
               
            end if;

         end if;
      end if;
   end process;

end architecture;





