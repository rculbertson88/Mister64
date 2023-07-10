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
      
      SIPIF_ramreq         : in  std_logic := '0';
      SIPIF_addr           : in  unsigned(5 downto 0) := (others => '0');
      SIPIF_writeEna       : in  std_logic := '0'; 
      SIPIF_writeData      : in  std_logic_vector(7 downto 0);
      SIPIF_ramgrant       : out std_logic;
      SIPIF_readData       : out std_logic_vector(7 downto 0);
      
      SIPIF_writeProc      : in  std_logic;
      SIPIF_readProc       : in  std_logic;
      SIPIF_ProcDone       : out std_logic := '0';
      
      bus_addr             : in  unsigned(10 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done             : out std_logic := '0';
      
      pad_0_A              : in  std_logic;
      pad_0_B              : in  std_logic;
      pad_0_Z              : in  std_logic;
      pad_0_START          : in  std_logic;
      pad_0_DPAD_UP        : in  std_logic;
      pad_0_DPAD_DOWN      : in  std_logic;
      pad_0_DPAD_LEFT      : in  std_logic;
      pad_0_DPAD_RIGHT     : in  std_logic;
      pad_0_L              : in  std_logic;
      pad_0_R              : in  std_logic;
      pad_0_C_UP           : in  std_logic;
      pad_0_C_DOWN         : in  std_logic;
      pad_0_C_LEFT         : in  std_logic;
      pad_0_C_RIGHT        : in  std_logic;
      pad_0_analog_h       : in  std_logic_vector(7 downto 0);
      pad_0_analog_v       : in  std_logic_vector(7 downto 0);
      
      SS_reset             : in  std_logic;
      loading_savestate    : in  std_logic;
      SS_DataWrite         : in  std_logic_vector(63 downto 0);
      SS_Adr               : in  unsigned(6 downto 0);
      SS_wren              : in  std_logic;
      SS_rden              : in  std_logic;
      SS_DataRead          : out std_logic_vector(63 downto 0);
      SS_idle              : out std_logic
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
      
      CHECKDONE,
      RAMACCESS,
      
      CLEARRAM,
      CLEARREADCOMMAND,
      CLEARCOMPLETE,
      
      EXTCOMM_FETCHNEXT,
      EXTCOMM_EVALREAD,
      EXTCOMM_EVALCOMMAND,
      
      EXTCOMM_RECEIVEREAD,
      EXTCOMM_EVALRECEIVE,
      EXTCOMM_RECEIVETYPE,
      EXTCOMM_EVALTYPEGAMEPAD,
      EXTCOMM_EVALTYPEEEPROMRTC,
      
      EXTCOMM_RESPONSETYPE1,
      EXTCOMM_RESPONSETYPE2,
      EXTCOMM_RESPONSETYPE3,
      EXTCOMM_RESPONSETYPEDONE,
      
      EXTCOMM_RESPONSEPAD1,
      EXTCOMM_RESPONSEPAD2,
      EXTCOMM_RESPONSEPAD3,
      EXTCOMM_RESPONSEPAD4,
      EXTCOMM_RESPONSEPADDONE
   );
   signal state                     : tState := IDLE;
   signal startup_complete          : std_logic := '0';
   
   signal SIPIF_write_latched       : std_logic := '0';
   signal SIPIF_read_latched        : std_logic := '0';
   signal pifreadmode               : std_logic := '0';
   signal pifProcMode               : std_logic := '0';
   
   signal EXT_first                 : std_logic := '0';
   signal EXT_channel               : unsigned(5 downto 0);
   signal EXT_index                 : unsigned(5 downto 0);
   signal EXT_recindex              : unsigned(5 downto 0);
   signal EXT_send                  : unsigned(5 downto 0);
   signal EXT_receive               : unsigned(5 downto 0);
   
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
   
   SIPIF_readData <= ram_q_b;
   
   SS_DataRead <= (others => '0');
   SS_idle     <= '1';

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
            
            startup_complete     <= '0';
            ram_address_b        <= (others => '0');
            ram_data_b           <= (others => '0');
            
            
            SIPIF_ramgrant       <= '0';
            SIPIF_write_latched  <= '0';
            SIPIF_read_latched   <= '0';
            
            if (loading_savestate = '1') then
               state      <= IDLE;
               ram_wren_b <= '0';
            else
               state      <= CLEARRAM;
               ram_wren_b <= '1';
            end if;
            
         elsif (ce = '1') then
         
            SIPIF_ProcDone <= '0';
            ram_wren_b     <= '0';
         
            bus_done       <= '0';
            bus_read_rom   <= '0';
            bus_dataRead   <= (others => '0');

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
            if (SIPIF_writeProc = '1') then SIPIF_write_latched <= '1'; end if;
            if (SIPIF_readProc  = '1') then SIPIF_read_latched  <= '1'; end if;
            
            case (state) is
            
               when IDLE =>
                  pifreadmode <= '0';
                  pifProcMode <= '0';
                  EXT_first   <= '1';
                  if (SIPIF_ramreq = '1') then
                     state          <= RAMACCESS;
                     SIPIF_ramgrant <= '1';
                  elsif (SIPIF_write_latched = '1' or SIPIF_read_latched = '1') then
                     state         <= WRITECOMMAND;
                     ram_address_b <= 6x"3F";
                     pifreadmode   <= SIPIF_read_latched;
                     pifProcMode   <= '1';
                  elsif (bus_write_ram = '1') then
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
                  end if;
            
               -- startup values
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
            
               -- command evaluation
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
                  state     <= CHECKDONE;
                  EXT_first <= '0';
                  
                  if (unsigned(ram_q_b) > 1) then
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
                  elsif (EXT_first = '1') then
                     state         <= EXTCOMM_FETCHNEXT;
                     ram_address_b <= (others => '0');
                     EXT_channel   <= (others => '0');
                     EXT_index     <= (others => '0');
                  end if;
                  
               when EVALREAD =>
                  state <= CHECKDONE;
                  if (ram_q_b(1) = '1') then -- CIC-NUS-6105 challenge/response
                     null;
                  else
                     state         <= EXTCOMM_FETCHNEXT;
                     EXT_channel   <= (others => '0');
                     EXT_index     <= (others => '0');
                  end if;
                  
               when WRITEBACKCOMMAND =>
                  state         <= READCOMMAND;
            
               -- SI/PIF communication
               when CHECKDONE =>
                  state          <= IDLE;
                  SIPIF_ProcDone <= pifProcMode;
                  
               when RAMACCESS =>
                  if (SIPIF_ramreq = '0') then
                     state          <= IDLE;
                     SIPIF_ramgrant <= '0';
                  end if;
                  ram_address_b <= std_logic_vector(SIPIF_addr);
                  ram_data_b    <= SIPIF_writeData;
                  ram_wren_b    <= SIPIF_writeEna;
            
               -- clear
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
            
               -- extern communication
               when EXTCOMM_FETCHNEXT =>
                  state         <= EXTCOMM_EVALREAD;
                  ram_address_b <= std_logic_vector(EXT_index);
               
               when EXTCOMM_EVALREAD =>
                  state <= EXTCOMM_EVALCOMMAND;
                
               when EXTCOMM_EVALCOMMAND =>
                  if (EXT_index = 63 or ram_q_b = x"FE") then
                     state <= CHECKDONE;
                     if (pifreadmode = '0') then
                        ram_wren_b    <= '1';
                        ram_address_b <= 6x"3F";
                        ram_data_b    <= (others => '0');
                     end if;
                  elsif (ram_q_b = x"00") then
                     state         <= EXTCOMM_FETCHNEXT;
                     EXT_channel   <= EXT_channel + 1;
                     EXT_index     <= EXT_index + 1;
                  elsif (ram_q_b = x"FD" or ram_q_b = x"FF") then
                     state         <= EXTCOMM_FETCHNEXT;
                     EXT_index     <= EXT_index + 1;
                  else
                     state         <= EXTCOMM_RECEIVEREAD;
                     EXT_index     <= EXT_index + 1;
                     ram_address_b <= std_logic_vector(EXT_index + 1);
                     EXT_send      <= unsigned(ram_q_b(5 downto 0));
                  end if;
               
               when EXTCOMM_RECEIVEREAD =>
                  state        <= EXTCOMM_EVALRECEIVE;
                  EXT_recindex <= EXT_index;
                  
               when EXTCOMM_EVALRECEIVE =>
                  if (ram_q_b = x"FE") then
                     state <= CHECKDONE;
                     if (pifreadmode = '0') then
                        ram_wren_b    <= '1';
                        ram_address_b <= 6x"3F";
                        ram_data_b    <= (others => '0');
                     end if;
                  else
                     EXT_receive   <= unsigned(ram_q_b(5 downto 0));
                     state         <= EXTCOMM_RECEIVETYPE;
                     EXT_index     <= EXT_index + 1;
                     ram_address_b <= std_logic_vector(EXT_index + 1);
                  end if;
                  
               when EXTCOMM_RECEIVETYPE =>
                  if (EXT_channel < 4) then
                     state <= EXTCOMM_EVALTYPEGAMEPAD;
                  else
                     state <= EXTCOMM_EVALTYPEEEPROMRTC;
                  end if;
                  
               when EXTCOMM_EVALTYPEGAMEPAD =>
                  if (ram_q_b = x"00" or ram_q_b = x"FF") then -- type check
                     state         <= EXTCOMM_RESPONSETYPE1;
                  elsif (ram_q_b = x"01") then -- pad response
                     if (EXT_receive > 4) then
                        ram_wren_b    <= '1';
                        ram_address_b <= std_logic_vector(EXT_recindex);
                        ram_data_b    <= "01" & std_logic_vector(EXT_receive); -- over flag
                     end if;
                     state <= EXTCOMM_RESPONSEPAD1;
                  else -- rumble and controller pak
                     state         <= EXTCOMM_FETCHNEXT;
                     EXT_index     <= EXT_index + 1;
                     ram_wren_b    <= '1';
                     ram_address_b <= std_logic_vector(EXT_recindex);
                     ram_data_b    <= "10" & std_logic_vector(EXT_receive); -- invalid flag
                     EXT_channel   <= EXT_channel + 1;
                  end if;
               
               when EXTCOMM_EVALTYPEEEPROMRTC =>            
                  -- todo!
                  state         <= EXTCOMM_FETCHNEXT;
                  EXT_index     <= EXT_index + 1;
                  ram_wren_b    <= '1';
                  ram_address_b <= std_logic_vector(EXT_recindex);
                  ram_data_b    <= "10" & std_logic_vector(EXT_receive); -- invalid flag
                  EXT_channel   <= EXT_channel + 1;
               
               -- response for type
               when EXTCOMM_RESPONSETYPE1 =>
                  state         <= EXTCOMM_RESPONSETYPE2;
                  ram_wren_b    <= '1';
                  EXT_index     <= EXT_index + 1;
                  ram_address_b <= std_logic_vector(EXT_index + 1);
                  ram_data_b    <= x"05"; -- gamepad    
                  
               when EXTCOMM_RESPONSETYPE2 =>
                  state         <= EXTCOMM_RESPONSETYPE3;
                  ram_wren_b    <= '1';
                  EXT_index     <= EXT_index + 1;
                  ram_address_b <= std_logic_vector(EXT_index + 1);
                  ram_data_b    <= x"00";
                  
               when EXTCOMM_RESPONSETYPE3 =>
                  state         <= EXTCOMM_RESPONSETYPEDONE;
                  ram_wren_b    <= '1';
                  EXT_index     <= EXT_index + 1;
                  ram_address_b <= std_logic_vector(EXT_index + 1);
                  ram_data_b    <= x"02"; -- nothing in controller slot   
            
               when EXTCOMM_RESPONSETYPEDONE =>
                  state         <= EXTCOMM_FETCHNEXT;
                  EXT_channel   <= EXT_channel + 1;
                  EXT_index     <= EXT_index + 1;
            
               -- response for gamepad
               when EXTCOMM_RESPONSEPAD1 =>
                  state         <= EXTCOMM_RESPONSEPAD2;
                  ram_wren_b    <= '1';
                  EXT_index     <= EXT_index + 1;
                  ram_address_b <= std_logic_vector(EXT_index + 1);
                  ram_data_b    <= x"00";
                  if (EXT_channel = 0) then
                     ram_data_b(7) <= pad_0_A;         
                     ram_data_b(6) <= pad_0_B;         
                     ram_data_b(5) <= pad_0_Z;         
                     ram_data_b(4) <= pad_0_START;     
                     ram_data_b(3) <= pad_0_DPAD_UP;   
                     ram_data_b(2) <= pad_0_DPAD_DOWN; 
                     ram_data_b(1) <= pad_0_DPAD_LEFT; 
                     ram_data_b(0) <= pad_0_DPAD_RIGHT;
                  end if;
            
               when EXTCOMM_RESPONSEPAD2 =>
                  state         <= EXTCOMM_RESPONSEPAD3;
                  ram_wren_b    <= '1';
                  EXT_index     <= EXT_index + 1;
                  ram_address_b <= std_logic_vector(EXT_index + 1);
                  ram_data_b    <= x"00";
                  if (EXT_channel = 0) then        
                     ram_data_b(5) <= pad_0_L;      
                     ram_data_b(4) <= pad_0_R;      
                     ram_data_b(3) <= pad_0_C_UP;   
                     ram_data_b(2) <= pad_0_C_DOWN; 
                     ram_data_b(1) <= pad_0_C_LEFT; 
                     ram_data_b(0) <= pad_0_C_RIGHT;
                  end if;
                  
               when EXTCOMM_RESPONSEPAD3 =>
                  state         <= EXTCOMM_RESPONSEPAD4;
                  ram_wren_b    <= '1';
                  EXT_index     <= EXT_index + 1;
                  ram_address_b <= std_logic_vector(EXT_index + 1);
                  ram_data_b    <= x"00";
                  if (EXT_channel = 0) then 
                     ram_data_b <= pad_0_analog_h;
                  end if;
                  
               when EXTCOMM_RESPONSEPAD4 =>
                  state         <= EXTCOMM_RESPONSEPADDONE;
                  ram_wren_b    <= '1';
                  EXT_index     <= EXT_index + 1;
                  ram_address_b <= std_logic_vector(EXT_index + 1);
                  ram_data_b    <= x"00";
                  if (EXT_channel = 0) then 
                     ram_data_b <= std_logic_vector(-signed(pad_0_analog_v));
                  end if;
            
               when EXTCOMM_RESPONSEPADDONE =>
                  state         <= EXTCOMM_FETCHNEXT;
                  EXT_channel   <= EXT_channel + 1;
                  EXT_index     <= EXT_index + 1;

            
            end case;
            
         end if; -- ce
         
         if (SS_wren = '1') then
            ram_wren_b    <= '1';
            ram_address_b <= std_logic_vector(SS_Adr(5 downto 0));
            ram_data_b    <= SS_DataWrite(7 downto 0);
         end if;
         
      end if; -- clock
   end process;

--##############################################################
--############################### export
--##############################################################
   
   -- synthesis translate_off
   goutput : if 1 = 1 generate
      type tpifRamExport is array(0 to 63) of std_logic_vector(7 downto 0);
      signal pifRamExport : tpifRamExport;
      signal state_last   : tState := IDLE;
      signal exportCount  : integer;
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
         exportCount <= 0;
         
         while (true) loop
         
            if (reset = '1') then
               file_close(outfile);
               file_open(f_status, outfile, "R:\\pif_n64_sim.txt", write_mode);
               file_close(outfile);
               file_open(f_status, outfile, "R:\\pif_n64_sim.txt", append_mode);
               exportCount <= 0;
            end if;
            
            wait until rising_edge(clk1x);
            
            -- write from bus
            if (pifram_wren = '1') then
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 0) <= bus_dataWrite( 7 downto  0);
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 1) <= bus_dataWrite(15 downto  8);
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 2) <= bus_dataWrite(23 downto 16);
               pifRamExport((to_integer(bus_addr(5 downto 2)) * 4) + 3) <= bus_dataWrite(31 downto 24);
            end if;
            
            -- write from pif
            if (ram_wren_b = '1') then
               pifRamExport(to_integer(unsigned(ram_address_b))) <= ram_data_b(7 downto 0);
            end if;
            
            -- start transfer
            if (state = WRITECOMMAND) then 
               wait until rising_edge(clk1x);
               if (pifreadmode = '1') then
                  write(line_out, string'("ReadIN  : "));
               else
                  write(line_out, string'("WriteIN : "));
               end if;
               for i in 0 to 63 loop
                  write(line_out, to_hstring(pifRamExport(i)));
               end loop;
               writeline(outfile, line_out);
               exportCount <= exportCount + 1;
            end if;
            
            -- end transfer
            state_last <= state;
            if (state_last = CHECKDONE) then
               if (pifreadmode = '1') then
                  write(line_out, string'("ReadOUT : "));
               else
                  write(line_out, string'("WriteOUT: "));
               end if;
               for i in 0 to 63 loop
                  write(line_out, to_hstring(pifRamExport(i)));
               end loop;
               writeline(outfile, line_out);
               exportCount <= exportCount + 1;
            end if;  
            
         end loop;
         
      end process;
   
   end generate goutput;

   -- synthesis translate_on 

end architecture;





