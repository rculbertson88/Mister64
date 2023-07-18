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
      
      EEPROMTYPE           : in  std_logic_vector(1 downto 0); -- 00 -> off, 01 -> 4kbit, 10 -> 16kbit
      
      error                : out std_logic := '0';
      
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
      
      EXTCOMM_RESPONSETYPE,
      EXTCOMM_RESPONSEPAD,
      
      EXTCOMM_EEPROMINFO,
      
      EXTCOMM_EEPROMREAD_SETADDR,
      EXTCOMM_EEPROMREAD_READADDR,
      EXTCOMM_EEPROMREAD_DATAREAD,
      EXTCOMM_EEPROMREAD_DATAWRITE,
      
      EXTCOMM_EEPROMWRITE_READADDR,
      EXTCOMM_EEPROMWRITE_SETADDR,
      EXTCOMM_EEPROMWRITE_DATAREAD,
      EXTCOMM_EEPROMWRITE_DATAWRITE,
      
      EXTCOMM_RESPONSE_VALIDOVER,
      EXTCOMM_RESPONSE_WRITE,
      EXTCOMM_RESPONSE_END
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
   signal EXT_valid                 : std_logic := '0';
   signal EXT_over                  : std_logic := '0';
   signal EXP_responseindex         : unsigned(5 downto 0);
   
   type t_responsedata is array(0 to 7) of std_logic_vector(7 downto 0);
   signal EXT_responsedata : t_responsedata;      
   
   -- PIFRAM
   signal pifram_wren               : std_logic := '0';
   signal pifram_busdata            : std_logic_vector(31 downto 0) := (others => '0');
      
   signal ram_address_b             : std_logic_vector(5 downto 0) := (others => '0');
   signal ram_data_b                : std_logic_vector(7 downto 0) := (others => '0');
   signal ram_wren_b                : std_logic := '0';   
   signal ram_q_b                   : std_logic_vector(7 downto 0); 
   
   -- EEPROM
   signal eeprom_addr_a             : std_logic_vector(8 downto 0) := (others => '0');
   signal eeprom_wren_a             : std_logic := '0';
   signal eeprom_in_a               : std_logic_vector(31 downto 0) := (others => '0');
   signal eeprom_out_a              : std_logic_vector(31 downto 0) := (others => '0');
      
   signal eeprom_addr_b             : std_logic_vector(10 downto 0) := (others => '0');
   signal eeprom_wren_b             : std_logic := '0';
   signal eeprom_in_b               : std_logic_vector(7 downto 0) := (others => '0');
   signal eeprom_out_b              : std_logic_vector(7 downto 0) := (others => '0');
   
   type tEEPROMState is
   (
      EEPROM_IDLE,
      EEPROM_CLEAR
   );
   signal EEPROMState               : tEEPROMState := EEPROM_IDLE;
   
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
      
         error         <= '0';
         pifram_wren   <= '0';
         eeprom_wren_b <= '0';
      
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
                     state     <= CHECKDONE;
                     EXT_index <= (others => '0');
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
                  EXT_over      <= '0';
                  EXT_valid     <= '0';
                  if (EXT_channel < 4) then
                     state <= EXTCOMM_EVALTYPEGAMEPAD;
                  else
                     state <= EXTCOMM_EVALTYPEEEPROMRTC;
                  end if;
                  
               when EXTCOMM_EVALTYPEGAMEPAD =>
                  if (ram_q_b = x"00" or ram_q_b = x"FF") then -- type check
                     state         <= EXTCOMM_RESPONSETYPE;
                  elsif (ram_q_b = x"01") then -- pad response
                     state <= EXTCOMM_RESPONSEPAD;
                  else -- rumble and controller pak
                     state         <= EXTCOMM_RESPONSE_VALIDOVER;
                  end if;
               
               when EXTCOMM_EVALTYPEEEPROMRTC =>      
                  if (ram_q_b = x"00" or ram_q_b = x"FF") then
                     state         <= EXTCOMM_EEPROMINFO;
                  elsif (ram_q_b = x"04") then
                     state         <= EXTCOMM_EEPROMREAD_READADDR;
                     EXT_index     <= EXT_index + 1;
                     ram_address_b <= std_logic_vector(EXT_index + 1);                  
                  elsif (ram_q_b = x"05") then
                     state         <= EXTCOMM_EEPROMWRITE_READADDR;
                     EXT_index     <= EXT_index + 1;
                     ram_address_b <= std_logic_vector(EXT_index + 1);
                  else
                     state         <= EXTCOMM_RESPONSE_VALIDOVER;
                  end if;
            
               -- responses for gamepad
               when EXTCOMM_RESPONSETYPE =>
                  state               <= EXTCOMM_RESPONSE_VALIDOVER;
                  EXT_valid           <= '1';
                  EXT_responsedata(0) <= x"05";
                  EXT_responsedata(1) <= x"00";
                  EXT_responsedata(2) <= x"02";
               
               when EXTCOMM_RESPONSEPAD =>
                  state               <= EXTCOMM_RESPONSE_VALIDOVER;
                  EXT_valid           <= '1';
                  if (EXT_receive > 4) then
                     EXT_over         <= '1';
                  end if;
                  EXT_responsedata(0)(7) <= pad_0_A;         
                  EXT_responsedata(0)(6) <= pad_0_B;         
                  EXT_responsedata(0)(5) <= pad_0_Z;         
                  EXT_responsedata(0)(4) <= pad_0_START;     
                  EXT_responsedata(0)(3) <= pad_0_DPAD_UP;   
                  EXT_responsedata(0)(2) <= pad_0_DPAD_DOWN; 
                  EXT_responsedata(0)(1) <= pad_0_DPAD_LEFT; 
                  EXT_responsedata(0)(0) <= pad_0_DPAD_RIGHT;
                  
                  EXT_responsedata(1)(7 downto 6) <= "00";      
                  EXT_responsedata(1)(5) <= pad_0_L;      
                  EXT_responsedata(1)(4) <= pad_0_R;      
                  EXT_responsedata(1)(3) <= pad_0_C_UP;   
                  EXT_responsedata(1)(2) <= pad_0_C_DOWN; 
                  EXT_responsedata(1)(1) <= pad_0_C_LEFT; 
                  EXT_responsedata(1)(0) <= pad_0_C_RIGHT;
                  
                  EXT_responsedata(2) <= pad_0_analog_h;
                  EXT_responsedata(3) <= std_logic_vector(-signed(pad_0_analog_v));
                  
               -- responses for EEProm/RTC
               when EXTCOMM_EEPROMINFO =>
                  state <= EXTCOMM_RESPONSE_VALIDOVER;
                  if (EEPROMTYPE = "01") then -- 4kbit
                     EXT_valid           <= '1';
                     EXT_responsedata(0) <= x"00";
                     EXT_responsedata(1) <= x"80";
                     EXT_responsedata(2) <= x"00";
                  elsif (EEPROMTYPE = "10") then -- 16kbit
                     EXT_valid           <= '1';
                     EXT_responsedata(0) <= x"00";
                     EXT_responsedata(1) <= x"C0";
                     EXT_responsedata(2) <= x"00";
                  end if;
                  
               -- eeprom read
               when EXTCOMM_EEPROMREAD_READADDR =>
                  if (EXT_receive /= 8) then
                     error <= '1';
                  end if;
                  if (EXT_send >= 2) then
                     state     <= EXTCOMM_EEPROMREAD_SETADDR;
                     EXT_valid <= '1';
                  else
                     state     <= EXTCOMM_RESPONSE_VALIDOVER;
                  end if;
                     
               when EXTCOMM_EEPROMREAD_SETADDR =>
                  state             <= EXTCOMM_EEPROMREAD_DATAREAD;
                  eeprom_addr_b     <= ram_q_b & "000";
                  EXP_responseindex <= (others => '0');
                     
               when EXTCOMM_EEPROMREAD_DATAREAD =>
                  state                     <= EXTCOMM_EEPROMREAD_DATAWRITE;
                  eeprom_addr_b(2 downto 0) <= std_logic_vector(unsigned(eeprom_addr_b(2 downto 0)) + 1);
                  
               when EXTCOMM_EEPROMREAD_DATAWRITE =>
                  if (eeprom_addr_b(2 downto 0) = "000") then
                     state <= EXTCOMM_RESPONSE_VALIDOVER;
                  else
                     state <= EXTCOMM_EEPROMREAD_DATAREAD;
                  end if;
                  EXT_responsedata(to_integer(EXP_responseindex(2 downto 0))) <= eeprom_out_b;
                  EXP_responseindex <= EXP_responseindex + 1;
                  
               -- eeprom write
               when EXTCOMM_EEPROMWRITE_READADDR =>
                  EXT_send <= EXT_send - 1;
                  if (EXT_receive /= 1) then
                     error <= '1';
                  end if;
                  if (EXT_send >= 2 and EXT_receive >= 1) then
                     state     <= EXTCOMM_EEPROMWRITE_SETADDR;
                     EXT_valid <= '1';
                  else
                     state     <= EXTCOMM_RESPONSE_VALIDOVER;
                  end if;
                     
               when EXTCOMM_EEPROMWRITE_SETADDR =>
                  state               <= EXTCOMM_EEPROMWRITE_DATAREAD;
                  eeprom_addr_b       <= ram_q_b & "111";
                  EXT_responsedata(0) <= x"00";
                  EXT_send            <= EXT_send - 1;
                  EXT_index           <= EXT_index + 1;
                  ram_address_b       <= std_logic_vector(EXT_index + 1);    
                  
               when EXTCOMM_EEPROMWRITE_DATAREAD =>
                  if (EXT_send = 0) then
                     state      <= EXTCOMM_RESPONSE_VALIDOVER;
                     EXT_index  <= EXT_index - 1;
                  else
                     state      <= EXTCOMM_EEPROMWRITE_DATAWRITE;
                     EXT_index  <= EXT_index + 1;
                  end if;
                  ram_address_b  <= std_logic_vector(EXT_index + 1);    
                  EXT_send       <= EXT_send - 1;
                  eeprom_addr_b(2 downto 0) <= std_logic_vector(unsigned(eeprom_addr_b(2 downto 0)) + 1);  
                  
               when EXTCOMM_EEPROMWRITE_DATAWRITE =>
                  state         <= EXTCOMM_EEPROMWRITE_DATAREAD;
                  eeprom_in_b   <= ram_q_b;
                  eeprom_wren_b <= '1';
                  
               -- response writeback
               when EXTCOMM_RESPONSE_VALIDOVER =>
                  if (EXT_receive > 0 and EXT_valid = '1') then
                     state         <= EXTCOMM_RESPONSE_WRITE;
                  else
                     state         <= EXTCOMM_RESPONSE_END;
                  end if;
                  ram_wren_b        <= '1';
                  ram_address_b     <= std_logic_vector(EXT_recindex);
                  ram_data_b        <= (not EXT_valid) & EXT_over & std_logic_vector(EXT_receive);
                  EXP_responseindex <= (others => '0');
                                    
               when EXTCOMM_RESPONSE_WRITE =>
                  if (EXP_responseindex + 1 = EXT_receive) then
                     state <= EXTCOMM_RESPONSE_END;
                  end if;
                  ram_wren_b        <= '1';
                  EXT_index         <= EXT_index + 1;
                  ram_address_b     <= std_logic_vector(EXT_index + 1);
                  ram_data_b        <= EXT_responsedata(to_integer(EXP_responseindex(2 downto 0)));
                  EXP_responseindex <= EXP_responseindex + 1;
            
               when EXTCOMM_RESPONSE_END => 
                  state         <= EXTCOMM_FETCHNEXT;
                  EXT_channel   <= EXT_channel + 1;
                  EXT_index     <= EXT_index + 1;
            
            end case;
            
            if (EXT_index = 6x"3F" and state /= EXTCOMM_FETCHNEXT and state /= EXTCOMM_EVALREAD and state /= EXTCOMM_EVALCOMMAND) then -- safety out
               state       <= CHECKDONE;
               error       <= '1';
               EXT_index   <= (others => '0');
            end if;
            
         end if; -- ce
         
         if (SS_wren = '1') then
            ram_wren_b    <= '1';
            ram_address_b <= std_logic_vector(SS_Adr(5 downto 0));
            ram_data_b    <= SS_DataWrite(7 downto 0);
         end if;
         
      end if; -- clock
   end process;
   
--##############################################################
--############################### eeprom
--##############################################################
   
   iEEPROM: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 9,
      data_width_a  => 32,
      addr_width_b  => 11,
      data_width_b  => 8
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => eeprom_addr_a,
      data_a      => eeprom_in_a,
      wren_a      => eeprom_wren_a,
      q_a         => eeprom_out_a,
      
      clock_b     => clk1x,
      address_b   => eeprom_addr_b,
      data_b      => eeprom_in_b,
      wren_b      => eeprom_wren_b,
      q_b         => eeprom_out_b
   );
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         eeprom_wren_a <= '0';
      
         if (reset = '1') then
         
            EEPROMState   <= EEPROM_CLEAR;
            eeprom_addr_a <= (others => '0');
            eeprom_in_a   <= (others => '1');
         
         else
         
            case (EEPROMState) is
            
               when EEPROM_IDLE =>
                  null;
                  
               when EEPROM_CLEAR =>
                  eeprom_addr_a <= std_logic_vector(unsigned(eeprom_addr_a) + 1);
                  eeprom_wren_a <= '1';
                  if (eeprom_addr_a = 9x"1FF") then
                      EEPROMState <= EEPROM_IDLE;
                  end if;
            
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





