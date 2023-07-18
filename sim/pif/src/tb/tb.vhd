library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     
use IEEE.std_logic_textio.all; 
library STD;    
use STD.textio.all;

library n64;

entity etb  is
end entity;

architecture arch of etb is

   signal clk1x            : std_logic := '1';
   signal reset            : std_logic := '1';
      
   signal SIPIF_ramreq     : std_logic := '0';
   signal SIPIF_addr       : unsigned(5 downto 0) := (others => '0');
   signal SIPIF_writeEna   : std_logic := '0'; 
   signal SIPIF_writeData  : std_logic_vector(7 downto 0);
   signal SIPIF_ramgrant   : std_logic;

   signal SIPIF_writeProc  : std_logic := '0';
   signal SIPIF_readProc   : std_logic := '0';
   signal SIPIF_ProcDone   : std_logic := '0';
   
   -- testbench
   signal cmdCount         : integer := 0;


begin

   clk1x <= not clk1x after 8 ns;
   reset <= '0' after 600 ns;
 
   iPIF: entity N64.pif
   port map
   (
      clk1x                => clk1x,
      ce                   => '1',
      reset                => reset,
      
      EEPROMTYPE           => "01",
                           
      pifrom_wraddress     => 9x"0",
      pifrom_wrdata        => 32x"0",
      pifrom_wren          => '0',
                           
      SIPIF_ramreq         => SIPIF_ramreq,   
      SIPIF_addr           => SIPIF_addr,     
      SIPIF_writeEna       => SIPIF_writeEna, 
      SIPIF_writeData      => SIPIF_writeData,
      SIPIF_ramgrant       => SIPIF_ramgrant,
      SIPIF_readData       => open,
                            
      SIPIF_writeProc      => SIPIF_writeProc,
      SIPIF_readProc       => SIPIF_readProc, 
      SIPIF_ProcDone       => SIPIF_ProcDone, 
                           
      bus_addr             => 11x"0",
      bus_dataWrite        => 32x"0",
      bus_read             => '0',
      bus_write            => '0',
      bus_dataRead         => open,
      bus_done             => open,
      
      pad_0_A              => '0',
      pad_0_B              => '0',
      pad_0_Z              => '0',
      pad_0_START          => '0',
      pad_0_DPAD_UP        => '0',
      pad_0_DPAD_DOWN      => '0',
      pad_0_DPAD_LEFT      => '0',
      pad_0_DPAD_RIGHT     => '0',
      pad_0_L              => '0',
      pad_0_R              => '0',
      pad_0_C_UP           => '0',
      pad_0_C_DOWN         => '0',
      pad_0_C_LEFT         => '0',
      pad_0_C_RIGHT        => '0',
      pad_0_analog_h       => x"00",
      pad_0_analog_v       => x"00",
      
      SS_reset             => '0',
      loading_savestate    => '0',
      SS_DataWrite         => 64x"0",
      SS_Adr               => 7x"0",
      SS_wren              => '0',
      SS_rden              => '0',
      SS_DataRead          => open,
      SS_idle              => open
   );
   
   process
      file infile          : text;
      variable f_status    : FILE_OPEN_STATUS;
      variable inLine      : LINE;
      variable para_data8  : std_logic_vector(7 downto 0);
      variable char        : character;
      variable command     : string(1 to 10);
   begin
      
      wait until reset = '0';
         
      file_open(f_status, infile, "R:\pif_FPGN64.txt", read_mode);
      
      while (not endfile(infile)) loop
         
         cmdCount <= cmdCount + 1;
         wait until rising_edge(clk1x);
         
         readline(infile,inLine);
         
         Read(inLine, command);
         if (command = "WriteIN : " or command = "ReadIN  : ") then
            SIPIF_ramreq <= '1';
            wait until SIPIF_ramgrant = '1';
            for i in 0 to 63 loop
               HREAD(inLine, para_data8);
               SIPIF_addr      <= to_unsigned(i, 6);
               SIPIF_writeEna  <= '1';
               SIPIF_writeData <= para_data8;
               wait until rising_edge(clk1x);
            end loop;
            SIPIF_writeEna <= '0';
            SIPIF_ramreq   <= '0';
            wait until SIPIF_ramgrant = '0';
         end if;
         
         if (command = "WriteOUT: ") then
            SIPIF_writeProc <= '1';
            wait until rising_edge(clk1x);
            SIPIF_writeProc <= '0';
            wait until rising_edge(clk1x);
            wait until SIPIF_ProcDone = '1';
         end if;
         
         if (command = "ReadOUT : ") then
            SIPIF_readProc <= '1';
            wait until rising_edge(clk1x);
            SIPIF_readProc <= '0';
            wait until rising_edge(clk1x);
            wait until SIPIF_ProcDone = '1';
         end if;

         for i in 0 to 999 loop
            wait until rising_edge(clk1x);
         end loop;
      end loop;
      
      file_close(infile);
      
      wait for 10 us;
      
      if (cmdCount >= 0) then
         report "DONE" severity failure;
      end if;
      
   end process;
   
   
end architecture;


