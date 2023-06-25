library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;    

entity cpu_FPU is
   port 
   (
      clk93             : in  std_logic;
      reset             : in  std_logic;
      error_FPU         : out std_logic := '0';
      
      -- synthesis translate_off
      csr_export       : out unsigned(24 downto 0);
      -- synthesis translate_on
      
      fpuRegMode        : in  std_logic;

      command_ena       : in  std_logic;
      command_code      : in  unsigned(31 downto 0);
      command_op1       : in  unsigned(63 downto 0);
      command_op2       : in  unsigned(63 downto 0);
      command_done      : out std_logic := '0';
      
      transfer_ena      : in  std_logic;
      transfer_code     : in  unsigned(3 downto 0);
      transfer_RD       : in  unsigned(4 downto 0);
      transfer_value    : in  unsigned(63 downto 0);
      transfer_data     : out unsigned(63 downto 0);
      
      exceptionFPU      : out std_logic := '0';
      FPU_CF            : out std_logic := '0';
      
      FPUWriteTarget    : out unsigned(4 downto 0) := (others => '0');
      FPUWriteData      : out unsigned(63 downto 0) := (others => '0');
      FPUWriteEnable    : out std_logic := '0'
   );
end entity;

architecture arch of cpu_FPU is
   
   constant OP_ABS : unsigned(5 downto 0) := 6x"05";
   
   signal csr     : unsigned(24 downto 0) := (others => '0'); 
   alias csr_roundmode              is csr(1 downto 0);
   alias csr_flag_inexact           is csr(2);
   alias csr_flag_underflow         is csr(3);
   alias csr_flag_overflow          is csr(4);
   alias csr_flag_divisionByZero    is csr(5);
   alias csr_flag_invalidOperation  is csr(6);
   alias csr_ena_inexact            is csr(7);
   alias csr_ena_underflow          is csr(8);
   alias csr_ena_overflow           is csr(9);
   alias csr_ena_divisionByZero     is csr(10);
   alias csr_ena_invalidOperation   is csr(11);
   alias csr_cause_inexact          is csr(12);
   alias csr_cause_underflow        is csr(13);
   alias csr_cause_overflow         is csr(14);
   alias csr_cause_divisionByZero   is csr(15);
   alias csr_cause_invalidOperation is csr(16);
   alias csr_cause_unimplemented    is csr(17);
   alias csr_compare                is csr(23);
   alias csr_flushSubnormals        is csr(24);
   
   signal bit64   : std_logic;
   signal OPgroup : unsigned(4 downto 0);
   signal OP      : unsigned(5 downto 0);
   
   signal causeReset    : std_logic;
   signal operandCount2 : std_logic;
   signal checkInputs   : std_logic;
   signal outputInvalid : std_logic;
   
   signal signA      : std_logic;
   signal signB      : std_logic;   
   signal expA       : unsigned(10 downto 0);
   signal expB       : unsigned(10 downto 0);   
   signal mantA      : unsigned(51 downto 0);
   signal mantB      : unsigned(51 downto 0);
   
   signal infA      : std_logic;
   signal infB      : std_logic;      
   signal nanA      : std_logic;
   signal nanB      : std_logic;   
   signal dnA       : std_logic;
   signal dnB       : std_logic;      
   signal zeroA     : std_logic;
   signal zeroB     : std_logic;   

begin 
   
   -- synthesis translate_off
   csr_export <= csr;
   -- synthesis translate_on
   
   FPU_CF <= csr_compare;
   

   bit64   <= command_code(21);
   OPgroup <= command_code(25 downto 21);
   OP      <= command_code( 5 downto  0);
   
   
   signA   <= command_op1(63) when (bit64 = '1') else command_op1(31);
   signB   <= command_op2(63) when (bit64 = '1') else command_op2(31);          
   expA    <= command_op1(62 downto 52) when (bit64 = '1') else "000" & command_op1(30 downto 23);
   expB    <= command_op2(62 downto 52) when (bit64 = '1') else "000" & command_op2(30 downto 23);   
   mantA   <= command_op1(51 downto 0) when (bit64 = '1') else 29x"0" & command_op1(22 downto 0);
   mantB   <= command_op2(51 downto 0) when (bit64 = '1') else 29x"0" & command_op2(22 downto 0);

   infA    <= '1' when ((bit64 = '1' and command_op1(62 downto 52) = 11x"7FF") or (bit64 = '0' and command_op1(30 downto 23) = x"FF")) else '0';
   infB    <= '1' when ((bit64 = '1' and command_op2(62 downto 52) = 11x"7FF") or (bit64 = '0' and command_op2(30 downto 23) = x"FF")) else '0';
   
   nanA    <= '1' when (infA = '1' and mantA > 0) else '0';
   nanB    <= '1' when (infB = '1' and mantB > 0) else '0';   
   
   dnA    <= '1' when (expA = 0 and mantA > 0) else '0';
   dnB    <= '1' when (expB = 0 and mantB > 0) else '0';   
   
   zeroA  <= '1' when (expA = 0 and mantA = 0) else '0';
   zeroB  <= '1' when (expB = 0 and mantB = 0) else '0';

   process (all)
   begin
      
      command_done   <= '0';
      exceptionFPU   <= '0';
      causeReset     <= '0';
      operandCount2  <= '0';
      checkInputs    <= '0';
      outputInvalid  <= '0';
      
      if (command_ena = '1') then
         if (OPgroup = 16 or OPgroup = 17) then
            if (op = 6 or op = 7 or op = 16#21# or op >= 16#30#) then -- FABS, FMOV, FNEG, CVT.d and all compares complete in 1 clock cycle
               command_done <= '1';
            else
               command_done <= '1'; -- workaround so CPU doesn't hang up
            end if;
            
            case (op) is
               when OP_ABS =>
                  command_done  <= '1';
                  causeReset    <= '1';
                  checkInputs   <= '1';
                  outputInvalid <= nanA;
               
               when others => null;   
            end case;
            
         end if;
      end if;
      
      transfer_data <= command_op1;
      
      case (transfer_code) is
         when x"0" => -- mfc1
            transfer_data <= unsigned(resize(signed(command_op1(31 downto 0)), 64));
            if (fpuRegMode = '1' and transfer_RD(0) = '1') then
               transfer_data <= unsigned(resize(signed(command_op1(63 downto 32)), 64));
            end if;
         
         when x"2" => -- cfc1
            transfer_data <= (others => '0');
            if (transfer_RD = 0) then
               transfer_data(11 downto 8) <= x"A";  -- revision
            end if;
            if (transfer_RD = 31) then
               transfer_data(24 downto 0) <= csr; 
            end if;
            
         when x"3" | x"7" => -- DCFC1 / DCTC1
            if (transfer_ena = '1') then
               exceptionFPU <= '1';  
               causeReset   <= '1';
            end if;
            
         when x"6" => -- ctc1
            if (transfer_ena = '1' and transfer_RD = 31) then
               if (transfer_value(17) = '1')                              then exceptionFPU <= '1'; end if;
               if (transfer_value(16) = '1' and transfer_value(11) = '1') then exceptionFPU <= '1'; end if;
               if (transfer_value(15) = '1' and transfer_value(10) = '1') then exceptionFPU <= '1'; end if;
               if (transfer_value(14) = '1' and transfer_value( 9) = '1') then exceptionFPU <= '1'; end if;
               if (transfer_value(13) = '1' and transfer_value( 8) = '1') then exceptionFPU <= '1'; end if;
               if (transfer_value(12) = '1' and transfer_value( 7) = '1') then exceptionFPU <= '1'; end if;
            end if;
            
         when x"8" =>  -- BC1 
            if (transfer_ena = '1') then  
               causeReset   <= '1';
            end if;
            
         when others => null;
      end case;
      
      if (checkInputs = '1') then
         if (dnA = '1') then
            exceptionFPU <= '1';
         elsif (nanA = '1') then
            if ((bit64 = '1' and command_op1(51) = '1') or (bit64 = '0' and command_op1(22) = '1')) then
               if (csr_ena_invalidOperation = '1') then
                  exceptionFPU <= '1';
               end if;
            else
               exceptionFPU <= '1';
            end if;
         end if;
      end if;
  
   end process;

   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         FPUWriteEnable <= '0';
         error_FPU      <= '0';
      
         if (reset = '1') then
         
            csr <= (others => '0');
           
         else 
         
            if (causeReset = '1') then
               csr_cause_inexact          <= '0';
               csr_cause_underflow        <= '0';
               csr_cause_overflow         <= '0';
               csr_cause_divisionByZero   <= '0';
               csr_cause_invalidOperation <= '0';
               csr_cause_unimplemented    <= '0';
            end if;
         
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
 
               if (checkInputs = '1') then
                  if (dnA = '1') then
                     csr_cause_unimplemented <= '1';
                   elsif (nanA = '1') then
                     if ((bit64 = '1' and command_op1(51) = '1') or (bit64 = '0' and command_op1(22) = '1')) then
                        csr_cause_invalidOperation <= '1';
                        if (csr_ena_invalidOperation = '0') then
                           csr_flag_invalidOperation <= '1';
                        end if;
                     else
                        csr_cause_unimplemented <= '1';
                     end if;
                  end if;
               end if;
 
            end if;
            
            if (exceptionFPU = '1') then
               FPUWriteEnable <= '0';
            end if;
            
            if (outputInvalid = '1') then
               if (bit64 = '1') then
                  FPUWriteData <= x"7FF7FFFFFFFFFFFF";
               else
                  FPUWriteData <= 32x"0" & x"7FBFFFFF";
               end if;
            end if;
            
            if (transfer_ena = '1') then
            
               FPUWriteTarget <= transfer_RD;
               FPUWriteData   <= transfer_value;
            
               case (transfer_code) is
                  when x"0" => null; -- mfc1
                  when x"1" => null; -- dmfc1
                  when x"2" => null; -- cfc1
                     
                  when x"3" | x"7" => -- DCFC1 / DCTC1
                     csr_cause_unimplemented    <= '1';
                  
                  when x"4" => -- mtc1
                     FPUWriteEnable             <= '1';
                     -- todo: only writes upper/lower 32 bit depending on fpuRegMode
                  
                  when x"5" => -- dmtc1
                     FPUWriteEnable             <= '1';
                     
                  when x"6" => -- ctc1
                     if (transfer_RD = 31) then
                        csr(17 downto  0) <= transfer_value(17 downto  0);
                        csr(24 downto 23) <= transfer_value(24 downto 23);
                     end if;
                  
                  when x"8" => null; -- BC1 
                  
                  when others => null;
               end case;
            end if;
                  
         end if;

      end if;
   end process;

end architecture;
