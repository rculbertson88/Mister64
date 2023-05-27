library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity PI is
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      irq_out              : out std_logic := '0';
      
      sdram_ena            : out std_logic;
      sdram_rnw            : out std_logic;
      sdram_Adr            : out std_logic_vector(26 downto 0);
      sdram_be             : out std_logic_vector(3 downto 0);
      sdram_dataWrite      : out std_logic_vector(31 downto 0);
      sdram_done           : in  std_logic;  
      sdram_dataRead       : in  std_logic_vector(31 downto 0);
      
      RAMMASK              : in  unsigned(23 downto 0);
      rdram_request        : out std_logic := '0';
      rdram_rnw            : out std_logic := '0'; 
      rdram_address        : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount     : out unsigned(9 downto 0):= (others => '0');
      rdram_writeMask      : out std_logic_vector(7 downto 0) := (others => '0'); 
      rdram_dataWrite      : out std_logic_vector(63 downto 0) := (others => '0');
      rdram_done           : in  std_logic;
      
      bus_reg_addr         : in  unsigned(19 downto 0); 
      bus_reg_dataWrite    : in  std_logic_vector(31 downto 0);
      bus_reg_read         : in  std_logic;
      bus_reg_write        : in  std_logic;
      bus_reg_dataRead     : out std_logic_vector(31 downto 0) := (others => '0');
      bus_reg_done         : out std_logic := '0';
      
      bus_cart_addr        : in  unsigned(31 downto 0); 
      bus_cart_dataWrite   : in  std_logic_vector(31 downto 0);
      bus_cart_read        : in  std_logic;
      bus_cart_write       : in  std_logic;
      bus_cart_dataRead    : out std_logic_vector(31 downto 0) := (others => '0');
      bus_cart_done        : out std_logic := '0'
   );
end entity;

architecture arch of PI is

   signal PI_DRAM_ADDR           : unsigned(23 downto 0);  -- 0x04600000 PI DRAM address (RW) : [23:0] starting RDRAM address
   signal PI_CART_ADDR           : unsigned(31 downto 0);  -- 0x04600004 PI pbus (cartridge) address (RW) : [31:0] starting AD16 address
   signal PI_LEN                 : unsigned(24 downto 0);  -- 0x04600008/C PI read/write length (RW) : [23:0] read data length
   signal PI_STATUS_DMAbusy      : std_logic;              -- 0x04600010 PI status (R) : [0] DMA busy [1] I/O busy [2] DMA error [3] Interrupt (DMA completed) (W) : [0] reset controller [1] clear intr
   signal PI_STATUS_IObusy       : std_logic;  
   signal PI_STATUS_DMAerror     : std_logic;  
   signal PI_STATUS_irq          : std_logic;  
   signal PI_BSD_DOM1_LAT        : unsigned(7 downto 0);   -- 0x04600014 PI dom1 latency (RW) : [7:0] domain 1 device latency
   signal PI_BSD_DOM1_PWD        : unsigned(7 downto 0);   -- 0x04600018 PI dom1 pulse width (RW) : [7:0] domain 1 device R / W strobe pulse width
   signal PI_BSD_DOM1_PGS        : unsigned(3 downto 0);   -- 0x0460001C PI dom1 page size(RW) : [3:0] domain 1 device page size
   signal PI_BSD_DOM1_RLS        : unsigned(1 downto 0);   -- 0x04600020 PI dom1 release (RW) : [1:0] domain 1 device R / W release duration
   signal PI_BSD_DOM2_LAT        : unsigned(7 downto 0);   -- 0x04600024 PI dom2 latency (RW) : [7:0] domain 2 device latency
   signal PI_BSD_DOM2_PWD        : unsigned(7 downto 0);   -- 0x04600028 PI dom2 pulse width (RW) : [7:0] domain 2 device R / W strobe pulse width
   signal PI_BSD_DOM2_PGS        : unsigned(3 downto 0);   -- 0x0460002C PI dom2 page size (RW) : [3:0] domain 2 device page size
   signal PI_BSD_DOM2_RLS        : unsigned(1 downto 0);   -- 0x04600030 PI dom2 release (RW) : [1:0] domain 2 device R / W release duration
   
   signal dmaIsWrite             : std_logic;
   signal first128               : std_logic;
   signal blocklength            : integer range 0 to 128;
   signal maxram                 : integer range 0 to 128;
   signal copycnt                : integer range 0 to 128;
      
   -- PI state machine  
   type tState is 
   (  
      IDLE, 
      READROM,
      COPYDMABLOCK,
      DMA_READCART,
      DMA_WRITERDRAM
   ); 
   signal state                  : tState := IDLE;
   
   signal written                : std_logic := '0';   
   signal writtenData            : std_logic_vector(31 downto 0) := (others => '0');   
   signal writtenTime            : integer range 0 to 200 := 0; 

   signal bus_cart_read_latched  : std_logic := '0';  
   signal bus_cart_write_latched : std_logic := '0';    

begin 

   irq_out <= PI_STATUS_irq;
   
   rdram_burstcount <= 10x"01";

   process (clk1x)
      variable blocklength_new : integer range 0 to 128;
      variable count_new       : unsigned(24 downto 0);
      variable writemask_new   : std_logic_vector(1 downto 0);
   begin
      if rising_edge(clk1x) then
      
         if (reset = '1') then
            
            bus_reg_done            <= '0';

            PI_DRAM_ADDR            <= (others => '0');
            PI_CART_ADDR            <= (others => '0');
            PI_LEN                  <= (others => '0');
            PI_STATUS_DMAbusy       <= '0';
            PI_STATUS_IObusy        <= '0';
            PI_STATUS_DMAerror      <= '0';
            PI_STATUS_irq           <= '0';
            PI_BSD_DOM1_LAT         <= (others => '0');
            PI_BSD_DOM1_PWD         <= (others => '0');
            PI_BSD_DOM1_PGS         <= (others => '0');
            PI_BSD_DOM1_RLS         <= (others => '0');
            PI_BSD_DOM2_LAT         <= (others => '0');
            PI_BSD_DOM2_PWD         <= (others => '0');
            PI_BSD_DOM2_PGS         <= (others => '0');
            PI_BSD_DOM2_RLS         <= (others => '0');
               
            state                   <= IDLE;
               
            written                 <= '0';
            bus_cart_read_latched   <= '0';
            bus_cart_write_latched  <= '0';
 
         elsif (ce = '1') then
         
            bus_reg_done     <= '0';
            bus_reg_dataRead <= (others => '0');

            -- bus regs read
            if (bus_reg_read = '1') then
               bus_reg_done <= '1';
               case (bus_reg_addr(19 downto 2) & "00") is
                  when x"00000" => bus_reg_dataRead(23 downto 0) <= std_logic_vector(PI_DRAM_ADDR);    
                  when x"00004" => bus_reg_dataRead(31 downto 0) <= std_logic_vector(PI_CART_ADDR);    
                  when x"00008" | x"0000C" => bus_reg_dataRead( 6 downto 0) <= (others => '1'); -- maybe different for writes < 8?   
                  when x"00010" => 
                     bus_reg_dataRead(0) <= PI_STATUS_DMAbusy;    
                     bus_reg_dataRead(1) <= PI_STATUS_IObusy;    
                     bus_reg_dataRead(2) <= PI_STATUS_DMAerror;    
                     bus_reg_dataRead(3) <= PI_STATUS_irq; 
                  when x"00014" => bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM1_LAT);    
                  when x"00018" => bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM1_PWD);    
                  when x"0001C" => bus_reg_dataRead(3 downto 0) <= std_logic_vector(PI_BSD_DOM1_PGS);    
                  when x"00020" => bus_reg_dataRead(1 downto 0) <= std_logic_vector(PI_BSD_DOM1_RLS);    
                  when x"00024" => bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM2_LAT);    
                  when x"00028" => bus_reg_dataRead(7 downto 0) <= std_logic_vector(PI_BSD_DOM2_PWD);    
                  when x"0002C" => bus_reg_dataRead(3 downto 0) <= std_logic_vector(PI_BSD_DOM2_PGS);    
                  when x"00030" => bus_reg_dataRead(1 downto 0) <= std_logic_vector(PI_BSD_DOM2_RLS);  
                  when others   => null;                  
               end case;
            end if;

            -- bus regs write
            if (bus_reg_write = '1') then
               bus_reg_done <= '1';
               case (bus_reg_addr(19 downto 2) & "00") is
                  when x"00000" => PI_DRAM_ADDR <= unsigned(bus_reg_dataWrite(23 downto 1)) & '0';   
                  when x"00004" => PI_CART_ADDR <= unsigned(bus_reg_dataWrite(31 downto 1)) & '0';
                  
                  when x"00008" | x"0000C" => 
                     PI_STATUS_DMAbusy <= '1';
                     first128          <= '1';
                     PI_LEN            <= resize(unsigned(bus_reg_dataWrite(23 downto 0)), 25) + to_unsigned(1, 25);         
                     if (bus_reg_addr(19 downto 2) & "00" = x"00008") then dmaIsWrite <= '0'; else dmaIsWrite <= '1'; end if;
                     
                  when x"00010" => 
                     if (bus_reg_dataWrite(1) = '1') then
                        PI_STATUS_irq <= '0';
                     end if;
                     if (bus_reg_dataWrite(0) = '1') then
                        PI_STATUS_DMAbusy  <= '0';
                        PI_STATUS_DMAerror <= '0';
                     end if;
                  
                  when x"00014" => PI_BSD_DOM1_LAT <= unsigned(bus_reg_dataWrite(7 downto 0));    
                  when x"00018" => PI_BSD_DOM1_PWD <= unsigned(bus_reg_dataWrite(7 downto 0));    
                  when x"0001C" => PI_BSD_DOM1_PGS <= unsigned(bus_reg_dataWrite(3 downto 0));    
                  when x"00020" => PI_BSD_DOM1_RLS <= unsigned(bus_reg_dataWrite(1 downto 0));    
                  when x"00024" => PI_BSD_DOM2_LAT <= unsigned(bus_reg_dataWrite(7 downto 0));    
                  when x"00028" => PI_BSD_DOM2_PWD <= unsigned(bus_reg_dataWrite(7 downto 0));    
                  when x"0002C" => PI_BSD_DOM2_PGS <= unsigned(bus_reg_dataWrite(3 downto 0));    
                  when x"00030" => PI_BSD_DOM2_RLS <= unsigned(bus_reg_dataWrite(1 downto 0));
                  when others   => null;
               end case;
            end if;
            
            
            -- PI state machine
            bus_cart_done     <= '0';
            bus_cart_dataRead <= (others => '0');
            sdram_ena         <= '0';
            rdram_request     <= '0';
            
            if (writtenTime > 0) then
               writtenTime <= writtenTime - 1;
            else
               written <= '0';
            end if;
            
            if (bus_cart_read = '1') then
               bus_cart_read_latched <= '1';
            end if;            
            if (bus_cart_write = '1') then
               bus_cart_write_latched <= '1';
            end if;
            
            case (state) is
            
               when IDLE =>
                  
                  if (bus_cart_read_latched = '1') then
                     bus_cart_read_latched <= '0';
                     bus_cart_dataRead     <= std_logic_vector(bus_cart_addr(15 downto 0)) & std_logic_vector(bus_cart_addr(15 downto 0)); -- open bus is default
                     
                     if (bus_cart_addr(28 downto 0) < 16#08000000#) then -- DD
                        bus_cart_done <= '1';
                     elsif (bus_cart_addr(28 downto 0) < 16#10000000#) then -- SRAM+FLASH  
                        report "SRAM + FLASH read not implemented" severity failure;
                     elsif (bus_cart_addr(28 downto 0) < 16#13FF0000#) then -- game rom
                        if (written = '1') then
                           written           <= '0';
                           bus_cart_dataRead <= writtenData;
                           bus_cart_done     <= '1';
                        else
                           state     <= READROM;
                           sdram_ena <= '1';
                           sdram_rnw <= '1';
                           sdram_Adr <= std_logic_vector((bus_cart_addr(25 downto 1) & '0') + to_unsigned(16#100000#, 27));
                        end if;
                     else
                        bus_cart_done <= '1';
                     end if;
                     
                  elsif (bus_cart_write_latched = '1') then
                  
                     bus_cart_write_latched <= '0';
                  
                     if (written = '0') then 
                        written     <= '1';
                        writtenData <= bus_cart_dataWrite;
                        writtenTime <= 200;
                     end if;

                     if (bus_cart_addr(28 downto 0) < 16#08000000#) then -- DD
                        bus_cart_done <= '1';
                     elsif (bus_cart_addr(28 downto 0) < 16#10000000#) then -- SRAM+FLASH  
                        report "SRAM + FLASH write not implemented" severity failure;
                     else
                        bus_cart_done <= '1';
                     end if;
                     
                  elsif (PI_STATUS_DMAbusy = '1') then
                     
                     if (PI_LEN > 0) then
                     
                        if (dmaIsWrite = '1') then
                           state <= COPYDMABLOCK;
                           
                           blocklength_new := 128;
                           if (PI_LEN < 128) then
                              blocklength_new := to_integer(PI_LEN);
                           end if;
                           
                           count_new := PI_LEN - blocklength_new;
                           if (count_new(0) = '1') then 
                              count_new := count_new + 1;
                           end if;
                              
                           maxram <= blocklength_new;
                           if (first128 = '1') then
                              blocklength_new := blocklength_new - to_integer(PI_DRAM_ADDR(2 downto 0));
                              if (count_new >= 128) then
                                 maxram <= blocklength_new - to_integer(PI_DRAM_ADDR(2 downto 0));
                                 count_new := count_new - to_integer(PI_DRAM_ADDR(2 downto 0));
                              end if;
                           end if;
                           
                           blocklength <= blocklength_new;
                           PI_LEN      <= count_new;
                           copycnt     <= 0;
                           
                        else
                           report "SRAM + FLASH DMA write not implemented" severity failure;
                        end if;
                     
                     
                     else
                        PI_STATUS_irq     <= '1';
                        PI_STATUS_DMAbusy <= '0';
                     end if;
                     
                  end if;
            
               when READROM => 
                  if (sdram_done = '1') then
                     state             <= IDLE;
                     bus_cart_dataRead <= sdram_dataRead(7 downto 0) & sdram_dataRead(15 downto 8) & sdram_dataRead(23 downto 16) & sdram_dataRead(31 downto 24);
                     bus_cart_done     <= '1';
                  end if;
            
               when COPYDMABLOCK =>
                  first128 <= '0';
                  if (copycnt < blocklength) then
                     state     <= DMA_READCART;
                     sdram_ena <= '1';
                     sdram_rnw <= '1';
                     
                     if (PI_CART_ADDR(28 downto 0) < 16#08000000#) then -- DD
                        report "DD DMA read not implemented" severity failure;
                     elsif (PI_CART_ADDR(28 downto 0) < 16#10000000#) then -- SRAM+FLASH  
                        report "SRAM + FLASH DMA read not implemented" severity failure;
                     elsif (PI_CART_ADDR(28 downto 0) < 16#13FF0000#) then -- game rom
                        sdram_Adr <= std_logic_vector((PI_CART_ADDR(25 downto 1) & '0') + to_unsigned(16#100000#, 27));
                     else
                        report "Openbus DMA read not implemented" severity failure;
                     end if;
                  else
                     state <= IDLE;
                     PI_DRAM_ADDR <= PI_DRAM_ADDR + 7;
                     PI_DRAM_ADDR(2 downto 0) <= "000";
                     PI_CART_ADDR <= PI_CART_ADDR + 1;
                     PI_CART_ADDR(0) <= '0';
                  end if;
                  
               when DMA_READCART =>
                  if (sdram_done = '1') then
                  
                     state <= DMA_WRITERDRAM;
                  
                     writemask_new := "00";
                     if (copycnt < maxram) then
                        writemask_new(0) := '1';
                     end if;
                     if ((copycnt + 1) < maxram) then
                        writemask_new(1) := '1';
                     end if;
                     
                     rdram_request   <= '1';
                     rdram_rnw       <= '0';
                     rdram_dataWrite <= (others => '0');
                     rdram_address   <= "0000" & PI_DRAM_ADDR(23 downto 3) & "000";
                     case (PI_DRAM_ADDR(2 downto 1)) is
                        when "00" => rdram_dataWrite(15 downto  0) <= sdram_dataRead(15 downto 0); rdram_writeMask <= "000000" & writemask_new;
                        when "01" => rdram_dataWrite(31 downto 16) <= sdram_dataRead(15 downto 0); rdram_writeMask <= "0000" & writemask_new & "00";
                        when "10" => rdram_dataWrite(47 downto 32) <= sdram_dataRead(15 downto 0); rdram_writeMask <= "00" & writemask_new & "0000";
                        when "11" => rdram_dataWrite(63 downto 48) <= sdram_dataRead(15 downto 0); rdram_writeMask <= writemask_new & "000000";
                        when others => null;
                     end case;
                     
                  end if;
                  
               when DMA_WRITERDRAM =>
                  if (rdram_done = '1') then
                     state        <= COPYDMABLOCK;
                     copycnt      <= copycnt + 2;
                     PI_DRAM_ADDR <= PI_DRAM_ADDR + 2;
                     PI_CART_ADDR <= PI_CART_ADDR + 2;
                  end if;
                  
            end case;

         end if;
      end if;
   end process;

end architecture;





