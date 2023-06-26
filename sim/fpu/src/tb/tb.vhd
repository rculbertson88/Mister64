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

   constant clk_speed : integer := 62500000;
   constant baud      : integer := 10000000;
 
   signal clk93       : std_logic := '1';
   signal reset       : std_logic := '1';
   
   signal fpuRegMode        : std_logic := '0';

   signal command_ena       : std_logic := '0';
   signal command_code      : unsigned(31 downto 0) := (others => '0');
   signal command_op1       : unsigned(63 downto 0) := (others => '0');
   signal command_op2       : unsigned(63 downto 0) := (others => '0');
   signal command_done      : std_logic := '0';

   signal transfer_ena      : std_logic := '0';
   signal transfer_code     : unsigned(3 downto 0) := (others => '0');
   signal transfer_RD       : unsigned(4 downto 0) := (others => '0');
   signal transfer_value    : unsigned(63 downto 0) := (others => '0');
   signal transfer_data     : unsigned(63 downto 0) := (others => '0');

   signal exceptionFPU      : std_logic := '0';
   signal FPU_CF            : std_logic := '0';

   signal FPUWriteTarget    : unsigned(4 downto 0) := (others => '0');
   signal FPUWriteData      : unsigned(63 downto 0) := (others => '0');
   signal FPUWriteEnable    : std_logic := '0';  
   
   -- testbench
   signal cmdCount          : integer := 0;
   signal errorCount        : integer := 0;
   signal errorsWE          : integer := 0;
   signal errorsRS          : integer := 0;
   signal errorsCSRA        : integer := 0;
   signal errorsE           : integer := 0;
   signal errorsCFA         : integer := 0;

   signal RS                : unsigned(63 downto 0);  
   signal CSRB              : unsigned(31 downto 0);  
   signal CSRA              : unsigned(31 downto 0);
   signal CFB               : std_logic;
   signal CFA               : std_logic;
   signal exceptionA        : std_logic;

begin

   clk93 <= not clk93 after 6 ns;
   reset <= '0' after 600 ns;
 
   icpu_FPU : entity N64.cpu_FPU
   port map
   (
      clk93             => clk93,         
      reset             => reset, 
      error_FPU         => open,
      
      fpuRegMode        => fpuRegMode,    
                                         
      command_ena       => command_ena,   
      command_code      => command_code,  
      command_op1       => command_op1,   
      command_op2       => command_op2,   
      command_done      => command_done,  
                           
      transfer_ena      => transfer_ena,  
      transfer_code     => transfer_code, 
      transfer_RD       => transfer_RD,   
      transfer_value    => transfer_value,
      transfer_data     => transfer_data, 
                           
      exceptionFPU      => exceptionFPU,  
      FPU_CF            => FPU_CF,        
                                         
      FPUWriteTarget    => FPUWriteTarget,
      FPUWriteData      => FPUWriteData,  
      FPUWriteEnable    => FPUWriteEnable
   );
   
   transfer_RD    <= 5x"1F";
   
   process
      file infile          : text;
      variable f_status    : FILE_OPEN_STATUS;
      variable inLine      : LINE;
      variable para_data4  : std_logic_vector(3 downto 0);
      variable para_data32 : std_logic_vector(31 downto 0);
      variable para_data64 : std_logic_vector(63 downto 0);
      variable char        : character;
   begin
      
      wait until reset = '0';
         
      file_open(f_status, infile, "R:\fpu_soft_FPGN64.txt", read_mode);
      
      while (not endfile(infile)) loop
         
         cmdCount <= cmdCount + 1;
         wait until rising_edge(clk93);
         
         readline(infile,inLine);
         
         -- "OP "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data32);
         command_code <= unsigned(para_data32);
         
         -- "RM "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data4);
         fpuRegMode <= para_data4(0);
         
         -- "R1 "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data64);
         command_op1 <= unsigned(para_data64);         
         
         -- "R2 "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data64);
         command_op2 <= unsigned(para_data64);         
         
         -- "RS "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data64);
         RS <= unsigned(para_data64);         
         
         -- "CSRB "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data32);
         CSRB <= unsigned(para_data32);         
         
         -- "CSRA "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data32);
         CSRA <= unsigned(para_data32);
         
         -- "CFB "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data4);
         CFB <= para_data4(0);         
         
         -- "CFA "
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data4);
         CFA <= para_data4(0);
         
         -- "E "
         Read(inLine, char);
         Read(inLine, char);
         HREAD(inLine, para_data4);
         exceptionA <= para_data4(0);
         
         wait until rising_edge(clk93);
         
         -- write CSRB to FPU
         transfer_ena   <= '1';
         transfer_code  <= x"6";
             
         transfer_value <= 32x"0" & CSRB;
         wait until rising_edge(clk93);
         transfer_ena   <= '0';
         wait until rising_edge(clk93);
         wait until rising_edge(clk93);

         -- execute command
         command_ena  <= '1'; 
         wait until rising_edge(clk93);
         command_ena  <= '0';
         while (command_done = '0') loop
            wait until rising_edge(clk93);
         end loop;
         
         -- eval exception
         if (exceptionFPU /= exceptionA) then
            errorCount <= errorCount + 1;
            errorsE    <= errorsE + 1;
         end if; 
         
         wait until rising_edge(clk93);
         
         -- eval result
         if (FPUWriteEnable = exceptionA) then
            errorCount <= errorCount + 1;
            errorsWE   <= errorsWE + 1;
         end if;      
         if (exceptionA = '0' and FPUWriteData /= RS) then
            errorCount <= errorCount + 1;
            errorsRS   <= errorsRS + 1;
         end if;         
         if (FPU_CF /= CFA) then
            errorCount <= errorCount + 1;
            errorsCFA  <= errorsCFA + 1;
         end if;
         
         -- read CSRA from FPU
         transfer_ena   <= '1';
         transfer_code  <= x"2";   
         wait until rising_edge(clk93);
         transfer_ena   <= '0';
         
         -- eval flags
         if (CSRA /= transfer_data) then
            errorCount <= errorCount + 1;
            errorsCSRA <= errorsCSRA + 1;
         end if;

         wait until rising_edge(clk93);
         wait until rising_edge(clk93);
         wait until rising_edge(clk93);
         wait until rising_edge(clk93);
         wait until rising_edge(clk93);
      end loop;
      
      file_close(infile);
      
      wait for 10 ms;
      
      if (cmdCount >= 0) then
         report "DONE" severity failure;
      end if;
      
   end process;
   
   
end architecture;


