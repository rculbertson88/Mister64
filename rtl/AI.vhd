library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use STD.textio.all;

library mem;

entity AI is
   port 
   (
      clk1x            : in  std_logic;
      ce               : in  std_logic;
      reset            : in  std_logic;
      
      irq_out          : out std_logic := '0';
      
      sound_out_left   : out std_logic_vector(15 downto 0) := (others => '0');
      sound_out_right  : out std_logic_vector(15 downto 0) := (others => '0');
      
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
      rdram_done       : in  std_logic;
      rdram_dataRead   : in  std_logic_vector(63 downto 0);
      
      SS_reset         : in  std_logic;
      SS_DataWrite     : in  std_logic_vector(63 downto 0);
      SS_Adr           : in  unsigned(1 downto 0);
      SS_wren          : in  std_logic;
      SS_rden          : in  std_logic;
      SS_DataRead      : out std_logic_vector(63 downto 0);
      SS_idle          : out std_logic
   );
end entity;

architecture arch of AI is

   signal bus_read_latch      : std_logic := '0';
   signal bus_write_latch     : std_logic := '0';

   signal AI_DRAM_ADDR        : unsigned(23 downto 0) := (others => '0'); -- 0x04500000 (W): [23:0] starting RDRAM address (8B-aligned)
   signal AI_LEN              : unsigned(17 downto 0) := (others => '0'); -- 0x04500004 (RW) : [14:0] transfer length(v1.0) - Bottom 3 bits are ignored [17:0] transfer length(v2.0) - Bottom 3 bits are ignored
   signal AI_CONTROL_DMAON    : std_logic := '0';                         -- 0x04500008 (W): [0] DMA enable - if LSB == 1, DMA is enabled
   signal AI_DACRATE          : unsigned(13 downto 0) := (others => '0'); -- 0x04500010 (W): [13:0] dac rate      -vid_clock / (dperiod + 1) is the DAC sample rate      -(dperiod + 1) >= 66 * (aclockhp + 1) must be true
   signal AI_BITRATE          : unsigned(3 downto 0)  := (others => '0'); -- 0x04500014 (W): [3:0] bit rate (abus clock half period register - aclockhp)   -vid_clock / (2 * (aclockhp + 1)) is the DAC clock rate    -The abus clock stops if aclockhp is zero
   
   signal AI_DRAM_ADDR_next   : unsigned(23 downto 0) := (others => '0');
   signal AI_LEN_next         : unsigned(17 downto 0) := (others => '0');
   
   signal carry               : std_logic := '0';
   signal fillcount           : integer range 0 to 2 := 0;
   signal waittime            : unsigned(14 downto 0) := (others => '0');

   type tState is
   (
      IDLE,
      NEXTDMA,
      STARTFETCH,
      FETCHNEXT
   );
   signal state                     : tState := IDLE;
   
   -- savestates
   type t_ssarray is array(0 to 3) of std_logic_vector(63 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
   signal ss_out : t_ssarray := (others => (others => '0'));     

begin 

   rdram_rnw        <= '1';
   rdram_address    <= x"0" & AI_DRAM_ADDR(23 downto 3) & "000";
   rdram_burstcount <= 10x"001";
   rdram_writeMask  <= (others => '0');
   rdram_dataWrite  <= (others => '0');
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         rdram_request <= '0';
      
         if (reset = '1') then
            
            bus_read_latch       <= '0';
            bus_write_latch      <= '0';
            bus_done             <= '0';
            irq_out              <= '0';

            AI_DRAM_ADDR         <= unsigned(ss_in(0)(23 downto  0)); -- (others => '0');
            AI_LEN               <= unsigned(ss_in(0)(41 downto 24)); -- (others => '0');
            AI_CONTROL_DMAON     <= ss_in(1)(42);                     -- '0';
            AI_DACRATE           <= unsigned(ss_in(0)(55 downto 42)); -- (others => '1');
            AI_BITRATE           <= unsigned(ss_in(0)(59 downto 56)); -- (others => '0');
               
            AI_DRAM_ADDR_next    <= unsigned(ss_in(1)(23 downto 0)); -- (others => '0');
            AI_LEN_next          <= unsigned(ss_in(1)(41 downto 24)); -- (others => '0');
                 
            carry                <= ss_in(1)(43); --'0';
            fillcount            <= to_integer(unsigned(ss_in(1)(45 downto 44))); -- 0 
            waittime             <= unsigned(ss_in(2)(14 downto  0)); -- (others => '0');
            state                <= IDLE;
            
         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_dataRead <= (others => '0');
            
            if (bus_read = '1') then
               bus_read_latch <= '1';
            end if;            
            if (bus_write = '1') then
               bus_write_latch <= '1';
            end if;
            
            if (waittime > 0) then
               waittime <= waittime - 1;
            end if;

            case (state) is
            
               when IDLE => 
                  if (waittime = 0) then
                  
                     waittime <= resize(AI_DACRATE,15) + (resize(AI_DACRATE,15) / 4) + (resize(AI_DACRATE,15) / 32); -- hack, should use video clock!
                     if (AI_DACRATE < 16#200#) then
                        waittime <= 15x"0200"; 
                     end if;
                     
                     if (fillcount > 0) then
                        if (AI_LEN > 0 and AI_CONTROL_DMAON = '1') then
                           state         <= STARTFETCH;
                           if (carry = '1') then
                              AI_DRAM_ADDR <= AI_DRAM_ADDR + 16#2000#;
                           end if;                           
                        elsif (AI_LEN = 0) then
                           state <= NEXTDMA;
                        end if;
                        
                     else
                        sound_out_left  <= (others => '0');
                        sound_out_right <= (others => '0');
                     end if;
                     
                  elsif (bus_read_latch = '1') then
                     bus_done       <= '1';
                     bus_read_latch <= '0';
                     case (bus_addr(19 downto 2) & "00") is   
                        when x"0000C" => -- AI_STATUS [0] ai_full(addr & len buffer full) [30] ai_busy Note that a 1 to0 transition in ai_full will set interrupt (W) : clear audio interrupt
                           if (fillcount > 1) then bus_dataRead(31) <= '1'; end if;
                           if (fillcount > 0) then bus_dataRead(30) <= '1'; end if;    
                           bus_dataRead(25) <= AI_CONTROL_DMAON;    
                           bus_dataRead(24) <= '1';    
                           bus_dataRead(20) <= '1';    
                           if (fillcount > 1) then bus_dataRead(0) <= '1'; end if;
                        when others   => bus_dataRead(17 downto 0) <= std_logic_vector(AI_LEN);                  
                     end case;
                  elsif (bus_write_latch = '1') then
                     bus_done        <= '1';
                     bus_write_latch <= '0';
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
                  
               when NEXTDMA =>
                  state <= IDLE;
                  if (fillcount > 1) then
                     AI_DRAM_ADDR <= AI_DRAM_ADDR_next;
                     AI_LEN       <= AI_LEN_next;
                     irq_out      <= '1';
                  end if;
                  fillcount <= fillcount - 1;
                  
               when STARTFETCH =>
                  state         <= FETCHNEXT;
                  rdram_request <= '1';
                  
               when FETCHNEXT =>
                  if (rdram_done = '1') then
                     if (AI_DRAM_ADDR(2) = '1') then
                        sound_out_left  <= rdram_dataRead(39 downto 32) & rdram_dataRead(47 downto 40);
                        sound_out_right <= rdram_dataRead(55 downto 48) & rdram_dataRead(63 downto 56);
                     else
                        sound_out_left  <= rdram_dataRead(7 downto 0) & rdram_dataRead(15 downto 8);
                        sound_out_right <= rdram_dataRead(23 downto 16) & rdram_dataRead(31 downto 24);
                     end if;
                     
                     AI_DRAM_ADDR(12 downto 0) <= AI_DRAM_ADDR(12 downto 0) + 4;
                     carry <= '0';
                     if (AI_DRAM_ADDR(12 downto 2) = 11x"7FF") then
                        carry <= '1';
                     end if;                     
                     
                     AI_LEN <= AI_LEN - 4;
                     if (AI_LEN = 4) then
                        state <= NEXTDMA;
                     else
                        state <= IDLE;
                     end if;
                     
                  end if;
                  
            end case;

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
         
            for i in 0 to 2 loop
               ss_in(i) <= (others => '0');
            end loop;
            
            ss_in(0) <= x"00FFFC0000000000";
            
         elsif (SS_wren = '1') then
            ss_in(to_integer(SS_Adr)) <= SS_DataWrite;
         end if;
         
         if (SS_rden = '1') then
            SS_DataRead <= ss_out(to_integer(SS_Adr));
         end if;
      
      end if;
   end process;
   
--##############################################################
--############################### export
--##############################################################
   
   -- synthesis translate_off
   goutput : if 1 = 1 generate
      signal out_count        : unsigned(31 downto 0) := (others => '0');
   begin
   
      process
         file outfile          : text;
         variable f_status     : FILE_OPEN_STATUS;
         variable line_out     : line;
         variable stringbuffer : string(1 to 31);
      begin
   
         file_open(f_status, outfile, "R:\\AI_n64_sim.txt", write_mode);
         file_close(outfile);
         file_open(f_status, outfile, "R:\\AI_n64_sim.txt", append_mode);
         
         while (true) loop
            
            wait until rising_edge(clk1x);

            if (state = FETCHNEXT and rdram_done = '1') then
               wait until rising_edge(clk1x);
               
               write(line_out, to_hstring(sound_out_left & sound_out_right));
               writeline(outfile, line_out);
               out_count <= out_count + 1;
            end if;
            
         end loop;
         
      end process;
   
   end generate goutput;

   -- synthesis translate_on  

end architecture;





