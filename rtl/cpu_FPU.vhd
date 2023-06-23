library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;    

entity cpu_FPU is
   port 
   (
      clk93             : in  std_logic;
      reset             : in  std_logic;
      error_FPU         : out std_logic := '0';
      
      fpuRegMode        : in  std_logic;

      command_ena       : in  std_logic;
      command_code      : in  unsigned(31 downto 0);
      command_op1       : in  unsigned(63 downto 0);
      command_op2       : in  unsigned(63 downto 0);
      command_done      : out std_logic := '0';
      
      transfer_ena      : in  std_logic;
      transfer_code     : in  unsigned(3 downto 0);
      transfer_RD       : in  unsigned(4 downto 0);
      transfer_data     : out unsigned(63 downto 0);
      
      FPUWriteTarget    : out unsigned(4 downto 0) := (others => '0');
      FPUWriteData      : out unsigned(63 downto 0) := (others => '0');
      FPUWriteEnable    : out std_logic := '0'
   );
end entity;

architecture arch of cpu_FPU is
   
   signal csr     : unsigned(24 downto 0) := (others => '0'); 
   
   signal bit64   : std_logic;
   signal OPgroup : unsigned(4 downto 0);
   signal OP      : unsigned(5 downto 0);

begin 

   bit64   <= command_code(21);
   OPgroup <= command_code(25 downto 21);
   OP      <= command_code( 5 downto  0);

   process (all)
   begin
      
      command_done <= '0';
      
      if (command_ena = '1') then
         if (OPgroup = 16 or OPgroup = 17) then
            if (op = 5 or op = 6 or op = 7 or op = 16#21# or op >= 16#30#) then -- FABS, FMOV, FNEG, CVT.d and all compares complete in 1 clock cycle
               command_done <= '1';
            end if;
         end if;
      end if;
      
      transfer_data <= command_op1;
      
      case (transfer_code) is
         when x"0" => -- mfc1
            transfer_data <= unsigned(resize(signed(command_op1(31 downto 0)), 64));
            if (fpuRegMode = '1' and transfer_RD(0) = '1') then
               transfer_data <= unsigned(resize(signed(command_op1(63 downto 32)), 64));
            end if;
         
         when x"2" =>
            transfer_data <= (others => '0');
            if (transfer_RD = 0) then
               transfer_data(11 downto 8) <= x"A";  -- revision
            end if;
            if (transfer_RD = 31) then
               transfer_data(24 downto 0) <= csr; 
            end if;
            
         when others => null;
      end case;
  
   end process;

   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         FPUWriteEnable <= '0';
         error_FPU      <= '0';
      
         if (reset = '1') then
         
            csr <= (others => '0');
           
         else 
         
            if (command_ena = '1') then
            
               FPUWriteTarget <= command_code(10 downto 6);
            
               if (OPgroup = 16 or OPgroup = 17) then
                  if (op = 5) then -- FABS
                     FPUWriteEnable <= '1';
                     if (bit64) then
                        FPUWriteData <= '0' & command_op1(62 downto 0);
                     else
                        FPUWriteData <= 33x"0" & command_op1(30 downto 0);
                     end if;
                  end if;
                  if (op = 6) then -- FABS
                     FPUWriteEnable <= '1';
                     FPUWriteData   <= command_op1;
                  end if;
                  if (op = 7) then -- FNEG
                     FPUWriteEnable <= '1';
                     if (bit64) then
                        FPUWriteData <= not(command_op1(63)) & command_op1(62 downto 0);
                     else
                        FPUWriteData <= 32x"0" & not(command_op1(31)) & command_op1(30 downto 0);
                     end if;
                  end if;
               end if;
            end if;
            
            if (transfer_ena = '1') then
               case (transfer_code) is
                  when x"0" => null; -- mfc1
                  when x"1" => null; -- dmfc1
                  when x"2" => null; -- cfc1
                     
                  when x"3" => error_FPU <= '1'; -- DCFC1
                  when x"4" => error_FPU <= '1'; -- mtc1
                  when x"5" => error_FPU <= '1'; -- dmtc1
                  when x"6" => error_FPU <= '1'; -- ctc1
                  when x"7" => error_FPU <= '1'; -- DCTC1
                  when x"8" => error_FPU <= '1'; -- BC1 
                  when others => null;
               end case;
            end if;
                  
         end if;

      end if;
   end process;

end architecture;
