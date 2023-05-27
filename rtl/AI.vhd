library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity AI is
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

architecture arch of AI is

   signal AI_DRAM_ADDR        : unsigned(23 downto 0); -- 0x04500000 (W): [23:0] starting RDRAM address (8B-aligned)
   signal AI_LEN              : unsigned(17 downto 0); -- 0x04500004 (RW) : [14:0] transfer length(v1.0) - Bottom 3 bits are ignored [17:0] transfer length(v2.0) - Bottom 3 bits are ignored
   signal AI_CONTROL_DMAON    : std_logic;              -- 0x04500008 (W): [0] DMA enable - if LSB == 1, DMA is enabled
   signal AI_DACRATE          : unsigned(13 downto 0); -- 0x04500010 (W): [13:0] dac rate      -vid_clock / (dperiod + 1) is the DAC sample rate      -(dperiod + 1) >= 66 * (aclockhp + 1) must be true
   signal AI_BITRATE          : unsigned(3 downto 0);  -- 0x04500014 (W): [3:0] bit rate (abus clock half period register - aclockhp)   -vid_clock / (2 * (aclockhp + 1)) is the DAC clock rate    -The abus clock stops if aclockhp is zero
   
   signal AI_DRAM_ADDR_next   : unsigned(23 downto 0);
   signal AI_LEN_next         : unsigned(17 downto 0);
   
   signal carry               : std_logic;
   signal fillcount           : integer range 0 to 2;

begin 

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (reset = '1') then
            
            bus_done             <= '0';
            irq_out              <= '0';

            AI_DRAM_ADDR         <= (others => '0');
            AI_LEN               <= (others => '0');
            AI_CONTROL_DMAON     <= '0';
            AI_DACRATE           <= (others => '0');
            AI_BITRATE           <= (others => '0');
               
            AI_DRAM_ADDR_next    <= (others => '0');
            AI_LEN_next          <= (others => '0');
                 
            carry                <= '0';
            fillcount            <= 0;
            
         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_dataRead <= (others => '0');

            -- bus read
            if (bus_read = '1') then
               bus_done <= '1';
               case (bus_addr(19 downto 2) & "00") is   
                  when x"0000C" => -- AI_STATUS [0] ai_full(addr & len buffer full) [30] ai_busy Note that a 1 to0 transition in ai_full will set interrupt (W) : clear audio interrupt
                     if (fillcount > 1) then bus_dataRead(31) <= '1'; end if;
                     if (fillcount > 0) then bus_dataRead(31) <= '1'; end if;    
                     bus_dataRead(25) <= AI_CONTROL_DMAON;    
                     bus_dataRead(24) <= '1';    
                     bus_dataRead(20) <= '1';    
                     if (fillcount > 1) then bus_dataRead(0) <= '1'; end if;
                  when others   => bus_dataRead(17 downto 0) <= std_logic_vector(AI_LEN);                  
               end case;
            end if;
            
            -- bus write
            if (bus_write = '1') then
               bus_done <= '1';
               
               case (bus_addr(19 downto 2) & "00") is
                  when x"00000" => 
                     if (fillcount = 0) then
                        AI_DRAM_ADDR <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                     elsif (fillcount = 1) then
                        AI_DRAM_ADDR_next <= unsigned(bus_dataWrite(23 downto 3)) & "000";
                     end if;
                  
                  when x"00004" => 
                     if (fillcount = 0) then
                        AI_LEN    <= unsigned(bus_dataWrite(17 downto 3)) & "000";
                        fillcount <= 1;
                        irq_out   <= '1';
                     elsif (fillcount = 1) then
                        AI_LEN_next <= unsigned(bus_dataWrite(17 downto 3)) & "000";
                        fillcount   <= 2;
                     end if;
                  
                  when x"00008" => AI_CONTROL_DMAON <= bus_dataWrite(0);
                  when x"0000C" => irq_out <= '0';
                  when x"00010" => AI_DACRATE <= unsigned(bus_dataWrite(13 downto 0));
                  when x"00014" => AI_BITRATE <= unsigned(bus_dataWrite(3 downto 0));
                  
                  when others   => null;                  
               end case;
               
            end if;
            
            -- only start new dma when no bus write is coming in!

         end if;
      end if;
   end process;

end architecture;





