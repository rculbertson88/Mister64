library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use STD.textio.all;

library mem;

entity pif is
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      pifrom_wraddress     : in  std_logic_vector(8 downto 0);
      pifrom_wrdata        : in  std_logic_vector(31 downto 0);
      pifrom_wren          : in  std_logic;
      
      SIPIF_write          : in  std_logic;
      SIPIF_read           : in  std_logic;
      SIPIF_done           : out std_logic := '0';
      
      bus_addr             : in  unsigned(10 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done             : out std_logic := '0'
   );
end entity;

architecture arch of pif is

   signal bus_read_rom     : std_logic := '0';
   signal bus_read_ram     : std_logic := '0';
   signal bus_write_ram    : std_logic := '0';
   
   signal pifrom_data      : std_logic_vector(31 downto 0) := (others => '0');
   signal pifrom_locked    : std_logic := '0';

   -- pif state machine
   type tState is
   (
      IDLE,
      WRITESTARTUP1,
      WRITESTARTUP2,
      WRITESTARTUP3,
      WRITECOMMAND,
      READCOMMAND,
      EVALWRITE,
      EVALREAD,
      WRITEBACKCOMMAND,
      
      CLEARRAM,
      CLEARREADCOMMAND,
      CLEARCOMPLETE
   );
   signal state                     : tState := IDLE;
   signal startup_complete          : std_logic := '0';
   
   signal SIPIF_write_latched       : std_logic := '0';
   signal SIPIF_read_latched        : std_logic := '0';
   signal pifreadmode               : std_logic := '0';
   
   -- PIFRAM
   signal pifram_wren               : std_logic := '0';
   signal pifram_busdata            : std_logic_vector(31 downto 0) := (others => '0');
      
   signal ram_address_b             : std_logic_vector(5 downto 0) := (others => '0');
   signal ram_data_b                : std_logic_vector(7 downto 0) := (others => '0');
   signal ram_wren_b                : std_logic := '0';   
   signal ram_q_b                   : std_logic_vector(7 downto 0); 
   
begin 

   ipifrom : entity work.pifrom
   port map
   (
      clk       => clk1x,
      address   => std_logic_vector(bus_addr(10 downto 2)),
      data      => pifrom_data,

      wraddress => pifrom_wraddress,
      wrdata    => pifrom_wrdata,   
      wren      => pifrom_wren     
   );
   
   iPIFRAM: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 4,
      data_width_a  => 32,
      addr_width_b  => 6,
      data_width_b  => 8
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => std_logic_vector(bus_addr(5 downto 2)),
      data_a      => bus_dataWrite,
      wren_a      => pifram_wren,
      q_a         => pifram_busdata,
      
      clock_b     => clk1x,
      address_b   => ram_address_b,
      data_b      => ram_data_b,
      wren_b      => ram_wren_b,
      q_b         => ram_q_b
   );
   

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         pifram_wren <= '0';
      
         if (reset = '1') then
            
            bus_done             <= '0';
            bus_read_rom         <= '0';
            bus_read_ram         <= '0';
            bus_write_ram        <= '0';
                  
            pifrom_locked        <= '0';
               
            state                <= CLEARRAM;
            startup_complete     <= '0';
            ram_address_b        <= (others => '0');
            ram_data_b           <= (others => '0');
            ram_wren_b           <= '1';
            
            SIPIF_write_latched  <= '0';
            SIPIF_read_latched   <= '0';
            
         elsif (ce = '1') then
         
            SIPIF_done   <= '0';
            ram_wren_b   <= '0';
         
            bus_done     <= '0';
            bus_read_rom <= '0';
            bus_dataRead <= (others => '0');

            if (bus_read_rom = '1') then
               bus_done <= '1';
               if (pifrom_locked = '0') then
                  bus_dataRead <= pifrom_data;
               end if;
            end if;

            -- bus read
            if (bus_read = '1') then
               if (bus_addr < 16#7C0#) then
                  bus_read_rom <= '1';
               else
                  bus_read_ram <= '1';
               end if;
            end if;

            -- bus write
            if (bus_write = '1') then
               if (bus_addr < 16#7C0#) then
                  bus_done <= '1';
               else
                  bus_write_ram <= '1';
               end if;
            end if;
            
            -- pif state machine
            if (SIPIF_write = '1') then SIPIF_write_latched <= '1'; end if;
            if (SIPIF_read  = '1') then SIPIF_read_latched  <= '1'; end if;
            
            case (state) is
            
               when IDLE =>
                  if (bus_write_ram = '1') then
                     bus_write_ram <= '0';
                     bus_done      <= '1';
                     pifram_wren   <= '1';
                     if (bus_addr(5 downto 2) = x"F") then
                        state         <= WRITECOMMAND;
                        ram_address_b <= 6x"3F";
                     end if;
                  elsif (bus_read_ram = '1') then
                     bus_read_ram <= '0';
                     bus_done     <= '1';
                     bus_dataRead <= pifram_busdata(7 downto 0) & pifram_busdata(15 downto 8) & pifram_busdata(23 downto 16) & pifram_busdata(31 downto 24);
                  elsif (SIPIF_write_latched = '1' or SIPIF_read_latched = '1') then
                     state         <= READCOMMAND;
                     ram_address_b <= 6x"3F";
                     pifreadmode   <= SIPIF_read_latched;
                  end if;
            
               when WRITESTARTUP1 =>
                  state          <= WRITESTARTUP2;
                  ram_address_b  <= 6x"27";
                  ram_data_b     <= x"3F";
                  ram_wren_b     <= '1';               
                  
               when WRITESTARTUP2 =>
                  state          <= WRITESTARTUP3;
                  ram_address_b  <= 6x"26";
                  ram_data_b     <= x"3F"; -- seed, depends on CIC
                  ram_wren_b     <= '1';
               
               when WRITESTARTUP3 =>
                  state            <= IDLE;  
                  ram_address_b    <= 6x"25";
                  ram_data_b       <= x"00"; -- version and type, depends on CIC
                  ram_wren_b       <= '1';   
                  startup_complete <= '1';
            
               when WRITECOMMAND =>
                  state <= READCOMMAND;
            
               when READCOMMAND =>
                  if (pifreadmode = '1') then
                     state            <= EVALREAD;
                  else
                     state            <= EVALWRITE;
                  end if;
                  SIPIF_write_latched <= '0';
                  SIPIF_read_latched  <= '0';
                  
               when EVALWRITE =>
                  state <= IDLE;
                  
                  if (ram_q_b(1) = '1') then -- CIC-NUS-6105 challenge/response
                     report "unimplemented PIF CIC challenge" severity warning;
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(1) <= '0';
                     
                  elsif (ram_q_b(2) = '1') then -- unknown
                     report "unimplemented PIF unknown command 2" severity warning;
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(2) <= '0';
                     
                  elsif (ram_q_b(3) = '1') then -- will lock up if not done
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(3) <= '0';
                     
                  elsif (ram_q_b(4) = '1') then -- PIFROM locked
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(4) <= '0';
                     pifrom_locked <= '1';
                     
                  elsif (ram_q_b(5) = '1') then -- init
                     state         <= WRITEBACKCOMMAND;
                     ram_wren_b    <= '1';
                     ram_data_b    <= ram_q_b;
                     ram_data_b(5) <= '0';
                     ram_data_b(7) <= '1';
                     
                  elsif (ram_q_b(6) = '1') then -- clear pif ram
                     state         <= CLEARRAM;
                     ram_address_b <= (others => '0');
                     ram_data_b    <= (others => '0');
                     ram_wren_b    <= '1';
                  end if;
                  
               when EVALREAD =>
                  state <= IDLE;
                  
               when WRITEBACKCOMMAND =>
                  state         <= READCOMMAND;
            
               when CLEARRAM =>
                  ram_address_b <= std_logic_vector(unsigned(ram_address_b) + 1);
                  ram_wren_b    <= '1';
                  if (ram_address_b = 6x"3E") then
                     if (startup_complete = '1') then
                        state      <= CLEARREADCOMMAND;
                        ram_wren_b <= '0';
                     else
                        state <= WRITESTARTUP1;
                     end if;
                  end if;
                  
               when CLEARREADCOMMAND =>
                  state <= CLEARCOMPLETE;
               
               when CLEARCOMPLETE =>
                  state <= WRITEBACKCOMMAND;
                  ram_wren_b    <= '1';
                  ram_data_b    <= ram_q_b;
                  ram_data_b(6) <= '0'; 
            
            end case;
            

         end if;
      end if;
   end process;

--##############################################################
--############################### export
--##############################################################
   
   -- synthesis translate_off
   goutput : if 1 = 1 generate
      type tpifRamExport is array(0 to 63) of std_logic_vector(7 downto 0);
      signal pifRamExport : tpifRamExport;
      signal state_last   : tState := IDLE;
   begin
   
      process
         file outfile          : text;
         variable f_status     : FILE_OPEN_STATUS;
         variable line_out     : line;
      begin
         
         for i in 0 to 63 loop
            pifRamExport(i) <= (others => '0');
         end loop;
         
         file_open(f_status, outfile, "R:\\pif_n64_sim.txt", write_mode);
         file_close(outfile);
         file_open(f_status, outfile, "R:\\pif_n64_sim.txt", append_mode);
         
         while (true) loop
         
            if (reset = '1') then
               file_close(outfile);
               file_open(f_status, outfile, "R:\\pif_n64_sim.txt", write_mode);
               file_close(outfile);
               file_open(f_status, outfile, "R:\\pif_n64_sim.txt", append_mode);
            end if;
            
            wait until rising_edge(clk1x);
            
            -- write from bus
            if (pifram_wren = '1') then
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 0) <= bus_dataWrite( 7 downto  0);
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 1) <= bus_dataWrite(15 downto  8);
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 2) <= bus_dataWrite(23 downto 16);
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 3) <= bus_dataWrite(31 downto 24);
            end if;
            
            -- start transfer
            if (state = READCOMMAND) then    
               if (pifreadmode = '1') then
                  write(line_out, string'("ReadIN: "));
               else
                  write(line_out, string'("WriteIN: "));
               end if;
               for i in 0 to 63 loop
                  write(line_out, to_hstring(pifRamExport(i)));
               end loop;
               writeline(outfile, line_out);
            end if;
            
            -- end transfer
            state_last <= state;
            if (state = IDLE and state_last /= IDLE and state_last /= WRITESTARTUP3) then
               if (pifreadmode = '1') then
                  write(line_out, string'("ReadOUT: "));
               else
                  write(line_out, string'("WriteOUT: "));
               end if;
               for i in 0 to 63 loop
                  write(line_out, to_hstring(pifRamExport(i)));
               end loop;
               writeline(outfile, line_out);
            end if;  
            
         end loop;
         
      end process;
   
   end generate goutput;

   -- synthesis translate_on 

end architecture;





