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
   
   constant OP_ADD      : unsigned(5 downto 0) := 6x"00";
   constant OP_SUB      : unsigned(5 downto 0) := 6x"01";
   constant OP_MUL      : unsigned(5 downto 0) := 6x"02";
   constant OP_DIV      : unsigned(5 downto 0) := 6x"03";
   constant OP_SQRT     : unsigned(5 downto 0) := 6x"04";
   constant OP_ABS      : unsigned(5 downto 0) := 6x"05";
   constant OP_MOV      : unsigned(5 downto 0) := 6x"06";
   constant OP_NEG      : unsigned(5 downto 0) := 6x"07";
   constant OP_ROUND_L  : unsigned(5 downto 0) := 6x"08";
   constant OP_TRUNC_L  : unsigned(5 downto 0) := 6x"09";
   constant OP_CEIL_L   : unsigned(5 downto 0) := 6x"0A";
   constant OP_FLOOR_L  : unsigned(5 downto 0) := 6x"0B";
   constant OP_ROUND_W  : unsigned(5 downto 0) := 6x"0C";
   constant OP_TRUNC_W  : unsigned(5 downto 0) := 6x"0D";
   constant OP_CEIL_W   : unsigned(5 downto 0) := 6x"0E";
   constant OP_FLOOR_W  : unsigned(5 downto 0) := 6x"0F";
   constant OP_CVT_S    : unsigned(5 downto 0) := 6x"20";
   constant OP_CVT_D    : unsigned(5 downto 0) := 6x"21";
   constant OP_CVT_W    : unsigned(5 downto 0) := 6x"24";
   constant OP_CVT_L    : unsigned(5 downto 0) := 6x"25";
   constant OP_C_F      : unsigned(5 downto 0) := 6x"30";
   constant OP_C_UN     : unsigned(5 downto 0) := 6x"31";
   constant OP_C_EQ     : unsigned(5 downto 0) := 6x"32";
   constant OP_C_UEQ    : unsigned(5 downto 0) := 6x"33";
   constant OP_C_OLT    : unsigned(5 downto 0) := 6x"34";
   constant OP_C_ULT    : unsigned(5 downto 0) := 6x"35";
   constant OP_C_OLE    : unsigned(5 downto 0) := 6x"36";
   constant OP_C_ULE    : unsigned(5 downto 0) := 6x"37";
   constant OP_C_SF     : unsigned(5 downto 0) := 6x"38";
   constant OP_C_NGLE   : unsigned(5 downto 0) := 6x"39";
   constant OP_C_SEQ    : unsigned(5 downto 0) := 6x"3A";
   constant OP_C_NGL    : unsigned(5 downto 0) := 6x"3B";
   constant OP_C_LT     : unsigned(5 downto 0) := 6x"3C";
   constant OP_C_NGE    : unsigned(5 downto 0) := 6x"3D";
   constant OP_C_LE     : unsigned(5 downto 0) := 6x"3E";
   constant OP_C_NGT    : unsigned(5 downto 0) := 6x"3F";
   
   constant INT64_MAX   : signed(63 downto 0)  := x"0080000000000000";
   constant INT64_MIN   : signed(63 downto 0)  := x"FF80000000000000";
   
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
   signal InvalidWidth  : std_logic;
   
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

   -- calculation pipeline   
   signal flag_inexact     : std_logic := '0';
   signal flag_overflow    : std_logic := '0';
   signal flag_underflow   : std_logic := '0';
   signal flag_divbyzero   : std_logic := '0';
   signal flag_invalid     : std_logic := '0';
   signal flag_infinity    : std_logic := '0';
   
   signal signOut          : std_logic := '0';
   signal bit64Out         : std_logic := '0';
   signal roundmode_save   : unsigned(1 downto 0) := (others => '0');
   
   -- common stage 0
   signal signA_1                         : std_logic := '0';
   signal signB_1                         : std_logic := '0';  
   signal mantA_1                         : unsigned(51 downto 0) := (others => '0');
   signal infA_1                          : std_logic := '0';
   signal nanA_1                          : std_logic := '0';
   signal zeroA_1                         : std_logic := '0';
   
   signal int_abs                         : unsigned(56 downto 0) := (others => '0');
   signal clz_int                         : integer range 0 to 56 := 0;
   signal exception_checkInputConvert2F   : std_logic := '0';
   signal exception_inputInvalid          : std_logic := '0';
   
   -- common left/right shifter
   signal shifter_right    : std_logic := '0';
   signal shifter_amount   : integer range -63 to 63 := 0;
   signal shifter_input    : unsigned(56 downto 0) := (others => '0');
   signal shifter_output   : unsigned(56 downto 0) := (others => '0');
   signal shifter_lostbits : std_logic := '0';
   
   -- common rounding
   signal round_start      : std_logic := '0';
   signal sticky           : std_logic := '0';
   signal roundUp          : std_logic := '0';
   signal round_Mant       : unsigned(56 downto 0) := (others => '0');
   signal round_in_exp     : unsigned(10 downto 0) := (others => '0');
   signal round_out32_exp  : unsigned(7 downto 0) := (others => '0');
   signal round_out64_exp  : unsigned(10 downto 0) := (others => '0');
   signal round_out32_mant : unsigned(22 downto 0) := (others => '0');
   signal round_out64_mant : unsigned(51 downto 0) := (others => '0');
   signal round_inexact    : std_logic := '0';
   signal round_overflow   : std_logic := '0';
   
   signal overflow_overwrite  : std_logic := '0';
   signal underflow_overwrite : std_logic := '0';
   
   -- CDS
   signal CDS_start     : std_logic := '0';
   signal CDS_stage1    : std_logic := '0';
   signal CDS_exp       : integer range -2047 to 2047 := 0;
   
   -- CIS / CID
   signal CIS_start     : std_logic := '0';
   signal CIS_stage1    : std_logic := '0';
   signal CID_start     : std_logic := '0';
   signal CID_stage1    : std_logic := '0';
   signal CISD_stage2   : std_logic := '0';
   signal CISD_stage3   : std_logic := '0';
   signal CID_exp       : integer range -2047 to 2047 := 0;
   signal CID_shift     : integer range -63 to 63 := 0;

   -- synthesis translate_off
   signal debug_calc_count : integer := 0;
   -- synthesis translate_on
   
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
      
      InvalidWidth   <= bit64;

      if (command_ena = '1') then
         if (OPgroup = 16 or OPgroup = 17) then
            case (op) is
               
               when OP_ADD  => command_done <= '1'; -- todo
               when OP_SUB  => command_done <= '1'; -- todo
               when OP_MUL  => command_done <= '1'; -- todo
               when OP_DIV  => command_done <= '1'; -- todo
               when OP_SQRT => command_done <= '1'; -- todo
            
               when OP_ABS =>
                  command_done  <= '1';
                  causeReset    <= '1';
                  checkInputs   <= '1';
                  outputInvalid <= nanA;   

               when OP_MOV =>
                  command_done <= '1';
                  
               when OP_NEG =>
                  command_done  <= '1';
                  causeReset    <= '1';
                  checkInputs   <= '1';
                  outputInvalid <= nanA;
               
               when OP_ROUND_L  => command_done <= '1'; -- todo           
               when OP_TRUNC_L  => command_done <= '1'; -- todo              
               when OP_CEIL_L   => command_done <= '1'; -- todo              
               when OP_FLOOR_L  => command_done <= '1'; -- todo              
               when OP_ROUND_W  => command_done <= '1'; -- todo              
               when OP_TRUNC_W  => command_done <= '1'; -- todo              
               when OP_CEIL_W   => command_done <= '1'; -- todo              
               when OP_FLOOR_W  => command_done <= '1'; -- todo    
               
               when OP_CVT_S    =>            
                  outputInvalid <= nanA;
                  InvalidWidth  <= '0';
                  if (bit64 = '1') then
                     causeReset   <= '1';
                     checkInputs  <= '1';
                  else
                     command_done <= '1';
                     exceptionFPU <= '1';
                  end if;
               
               when OP_CVT_D    =>
                  command_done  <= '1';
                  outputInvalid <= nanA;
                  InvalidWidth  <= '1';
                  if (bit64 = '0') then
                     causeReset   <= '1';
                     checkInputs  <= '1';
                  else
                     exceptionFPU <= '1';
                  end if;
               
               when OP_CVT_W    => command_done <= '1'; -- todo                  
               when OP_CVT_L    => command_done <= '1'; -- todo                 
                  
               when OP_C_F | OP_C_UN | OP_C_EQ | OP_C_UEQ | OP_C_OLT | OP_C_ULT | OP_C_OLE | OP_C_ULE | OP_C_SF | OP_C_NGLE | OP_C_SEQ | OP_C_NGL | OP_C_LT | OP_C_NGE | OP_C_LE | OP_C_NGT =>
                  command_done <= '1'; -- todo  
               
               when others =>
                  command_done <= '1';
                  exceptionFPU <= '1';
               
            end case;
         end if;
         
         if (OPgroup = 20 or OPgroup = 21) then
            case (op) is
                         
               when OP_CVT_S    => 
                  causeReset   <= '1';
               
               when OP_CVT_D    => 
                  causeReset   <= '1';
               
               when others =>
                  exceptionFPU <= '1';
                  command_done <= '1';
               
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
            command_done <= '1';
         elsif (nanA = '1') then
            if ((bit64 = '1' and command_op1(51) = '1') or (bit64 = '0' and command_op1(22) = '1')) then
               if (csr_ena_invalidOperation = '1') then
                  exceptionFPU <= '1';
                  command_done <= '1';
               end if;
            else
               exceptionFPU <= '1';
               command_done <= '1';
            end if;
         end if;
      end if;
      
      if (exception_checkInputConvert2F = '1') then
         exceptionFPU <= '1';
         command_done <= '1';
      end if;
      
      if (round_start = '1') then
         command_done <= '1';
         
         if (flag_underflow = '1' and (csr_flushSubnormals = '0' or csr_ena_underflow = '1' or csr_ena_inexact = '1')) then
            exceptionFPU <= '1';
         end if;
        
         if (flag_invalid = '0' and (round_inexact = '1' or flag_inexact = '1') and csr_ena_inexact = '1') then
            exceptionFPU <= '1';
         end if;
         
         if ((round_overflow = '1' or flag_overflow = '1') and csr_ena_overflow = '1') then
            exceptionFPU <= '1';
         end if;
         
      end if;
  
   end process;

   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         signA_1        <= signA;
         signB_1        <= signB;
         mantA_1        <= mantA;
         infA_1         <= infA;
         nanA_1         <= nanA;
         zeroA_1        <= zeroA;
      
         FPUWriteEnable                <= '0';
         error_FPU                     <= '0';           
         CDS_start                     <= '0';
         CIS_start                     <= '0';
         CID_start                     <= '0';
         exception_checkInputConvert2F <= '0';
         exception_inputInvalid        <= '0';
      
         if (reset = '1') then
         
            csr    <= (others => '0');
           
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
               bit64Out       <= bit64;
               roundmode_save <= csr_roundmode;
            
               if (OPgroup = 16 or OPgroup = 17) then
                  case (op) is
                        
                     when OP_ADD  => null;
                     when OP_SUB  => null;
                     when OP_MUL  => null;
                     when OP_DIV  => null;
                     when OP_SQRT => null;
                  
                     when OP_ABS => 
                        FPUWriteEnable <= '1';
                        if (bit64) then
                           FPUWriteData <= '0' & command_op1(62 downto 0);
                        else
                           FPUWriteData <= 33x"0" & command_op1(30 downto 0);
                        end if;

                     when OP_MOV =>
                        FPUWriteEnable <= '1';
                        FPUWriteData   <= command_op1;

                     when OP_NEG => 
                        FPUWriteEnable <= '1';
                        if (bit64) then
                           FPUWriteData <= not(command_op1(63)) & command_op1(62 downto 0);
                        else
                           FPUWriteData <= 32x"0" & not(command_op1(31)) & command_op1(30 downto 0);
                        end if;
                     
                     when OP_ROUND_L  => null;             
                     when OP_TRUNC_L  => null;                
                     when OP_CEIL_L   => null;                
                     when OP_FLOOR_L  => null;                
                     when OP_ROUND_W  => null;                
                     when OP_TRUNC_W  => null;                
                     when OP_CEIL_W   => null;                
                     when OP_FLOOR_W  => null;  
                     
                     when OP_CVT_S    => 
                        if (bit64 = '1') then
                           CDS_start <= '1';
                           bit64Out  <= '0';
                        else
                           csr_cause_unimplemented <= '1';
                        end if;
                     
                     when OP_CVT_D    =>
                        FPUWriteEnable <= '1';
                        if (bit64 = '0') then
                           if (infA = '1') then
                              FPUWriteData <= signA & 11x"7FF" & mantA;
                           else
                              FPUWriteData <= signA & (expA + 1023 - 127) & mantA(22 downto 0) & 29x"0";
                              if (expA = 0) then
                                 FPUWriteData(62 downto 52) <= (others => '0');
                              end if;
                           end if;
                        else
                           csr_cause_unimplemented <= '1';
                        end if;
                     
                     when OP_CVT_W    => null;                
                     when OP_CVT_L    => null;                
                        
                     when OP_C_F | OP_C_UN | OP_C_EQ | OP_C_UEQ | OP_C_OLT | OP_C_ULT | OP_C_OLE | OP_C_ULE | OP_C_SF | OP_C_NGLE | OP_C_SEQ | OP_C_NGL | OP_C_LT | OP_C_NGE | OP_C_LE | OP_C_NGT =>
                        null;
                     
                     when others =>
                        error_FPU <= '1';
                        csr_cause_unimplemented <= '1';

                  end case;
               end if;
               
               if (OPgroup = 20 or OPgroup = 21) then
               
                  if (signed(command_op1) >= INT64_MAX or signed(command_op1) < INT64_MIN) then
                     exception_checkInputConvert2F <= '1';
                  end if;
               
                  case (op) is
                        
                     when OP_CVT_S =>
                        CIS_start <= '1';
                        bit64Out  <= '0';
                     
                     when OP_CVT_D =>
                        CID_start <= '1';
                        bit64Out  <= '1';
                        
                     when others =>
                        error_FPU <= '1';
                        csr_cause_unimplemented <= '1';

                  end case;
               end if;
 
               if (checkInputs = '1') then
                  if (dnA = '1') then
                     csr_cause_unimplemented <= '1';
                     exception_inputInvalid  <= '1';
                   elsif (nanA = '1') then
                     if ((bit64 = '1' and command_op1(51) = '1') or (bit64 = '0' and command_op1(22) = '1')) then
                        csr_cause_invalidOperation <= '1';
                        if (csr_ena_invalidOperation = '1') then
                           exception_inputInvalid <= '1';
                        else
                           csr_flag_invalidOperation <= '1';
                        end if;
                     else
                        exception_inputInvalid  <= '1';
                        csr_cause_unimplemented <= '1';
                     end if;
                  end if;
               end if;
 
            end if;
            
            if (exceptionFPU = '1') then
               FPUWriteEnable <= '0';
            end if;
            
            if (outputInvalid = '1') then
               if (InvalidWidth = '1') then
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
         
         if (exception_checkInputConvert2F = '1') then
            csr_cause_unimplemented <= '1';
         end if;
         
         -- writeback after rounding
         if (round_start = '1') then
            FPUWriteEnable <= '1';
            
            -- result data
            if (flag_invalid = '0') then
            
               if (bit64Out = '1') then
                  FPUWriteData <= signOut & round_out64_exp & round_out64_mant;
               else
                  FPUWriteData <= 32x"0" & signOut & round_out32_exp & round_out32_mant;
               end if;
               
               if (flag_infinity = '1') then
                  if (bit64Out = '1') then
                     FPUWriteData <= signOut & 11x"7FF" & 52x"0";
                  else
                     FPUWriteData <= 32x"0" & signOut & x"FF" & 23x"0";
                  end if;
               end if;
               
               if (overflow_overwrite = '1' and (round_overflow = '1' or flag_overflow = '1')) then
                  if (bit64Out = '1') then
                     FPUWriteData <= signOut & 11x"7FE" & x"FFFFFFFFFFFFF";
                  else
                     FPUWriteData <= 32x"0" & signOut & x"FE" & 23x"7FFFF";
                  end if;
               end if;            
               
               if (underflow_overwrite = '1' and flag_underflow = '1') then
                  if (bit64Out = '1') then
                     FPUWriteData <= signOut & 11x"001" & 52x"0";
                  else
                     FPUWriteData <= 32x"0" & signOut & x"01" & 23x"0";
                  end if;
               end if;
               
            end if;
            
            -- update flags
            if (flag_underflow = '1' and (csr_flushSubnormals = '0' or csr_ena_underflow = '1' or csr_ena_inexact = '1')) then
            
               csr_cause_unimplemented    <= '1';
               FPUWriteEnable             <= '0';
            
            else
            
               if (flag_invalid = '0' and (round_inexact = '1' or flag_inexact = '1')) then
                  csr_cause_inexact <= '1';
                  if (csr_ena_inexact = '1') then
                     FPUWriteEnable    <= '0';
                  else
                     csr_flag_inexact <= '1';
                  end if;
               end if;
               
               if (flag_underflow = '1') then
                  csr_cause_underflow <= '1';
                  if (csr_ena_underflow = '1') then
                     FPUWriteEnable    <= '0';
                  else
                     csr_flag_underflow <= '1';
                  end if;
               end if;                       
               
               if (round_overflow = '1' or flag_overflow = '1') then
                  csr_cause_overflow <= '1';
                  if (csr_ena_overflow = '1') then
                     FPUWriteEnable    <= '0';
                  else
                     csr_flag_overflow <= '1';
                  end if;
               end if;
               
                if (flag_invalid = '1') then
                  csr_cause_invalidOperation <= '1';
                  if (csr_ena_invalidOperation = '1') then
                     FPUWriteEnable    <= '0';
                  else
                     csr_flag_invalidOperation <= '1';
                  end if;
               end if;    
               
            end if;
            
         end if;

      end if;
   end process;
   
   -- leading zero count for int
   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         clz_int <= 56;
         for i in 0 to 55 loop
            if (int_abs(i) = '1') then
               clz_int <= 55 - i;
            end if;
         end loop;

      end if;
   end process;
   
   -- shifter
   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         shifter_lostbits <= '0';
      
         if (shifter_right = '1') then
            shifter_output <= shift_right(shifter_input, shifter_amount);  
            for i in 0 to 56 loop
               if (i < shifter_amount and shifter_input(i) = '1') then
                  shifter_lostbits <= '1';
               end if;
            end loop;
         else
            shifter_output <= shifter_input sll shifter_amount;
         end if;

      end if;
   end process;
   
   -- rounding
   sticky <= shifter_lostbits or shifter_output(0);
   
   roundUp <= '1' when (roundmode_save = "00" and shifter_output(2) = '1' and (shifter_output(1) = '1' or sticky = '1' or shifter_output(3) = '1')) else -- TONEAREST
              '0' when (roundmode_save = "01" and shifter_output(2) = '1' and (shifter_output(1) = '1' or sticky = '1' or shifter_output(3) = '1')) else -- TOWARDZERO
              '1' when (roundmode_save = "10" and signOut = '0' and (shifter_output(2) = '1' or shifter_output(1) = '1' or sticky = '1')) else -- UPWARD
              '1' when (roundmode_save = "11" and signOut = '1' and (shifter_output(2) = '1' or shifter_output(1) = '1' or sticky = '1')) else -- DOWNWARD
              '0';
   
   round_Mant <= (shifter_output + 8) when (roundUp = '1') else shifter_output;
   
   process (all)
   begin
      
      round_inexact  <= shifter_lostbits;
      round_overflow <= '0';

      -- 32bit part
      if (round_Mant(27) = '1') then
         if (round_in_exp(7 downto 0) = x"FF") then
            round_out32_exp <= x"FF";
         else
            round_out32_exp <= round_in_exp(7 downto 0) + 1;
         end if;
         round_out32_mant <=  round_Mant(26 downto 4);
      else
         round_out32_exp  <= round_in_exp(7 downto 0);
         round_out32_mant <=  round_Mant(25 downto 3);
         
      end if;
      
      -- 64bit part
      if (round_Mant(56) = '1') then
         if (round_in_exp = 11x"7FF") then
            round_out64_exp <= 11x"7FF";
         else
            round_out64_exp <= round_in_exp + 1;
         end if;
         round_out64_mant <=  round_Mant(55 downto 4);
         if (bit64Out = '1' and round_Mant(3 downto 0) > 0) then round_inexact <= '1'; end if;
      else
         round_out64_exp  <= round_in_exp;
         round_out64_mant <=  round_Mant(54 downto 3);
         if (round_Mant(2 downto 0) > 0) then round_inexact <= '1'; end if;
      end if;
      
      -- inexact
      if (round_Mant(2 downto 0) > 0) then round_inexact <= '1'; end if;
      if (bit64Out = '0' and round_Mant(27) = '1' and round_Mant(3) = '1') then round_inexact <= '1'; end if;
      if (bit64Out = '1' and round_Mant(56) = '1' and round_Mant(3) = '1') then round_inexact <= '1'; end if;
      
      -- overflow
      if (bit64Out = '0' and round_out32_exp = x"FF")    then round_overflow <= not flag_infinity; end if;
      if (bit64Out = '1' and round_out64_exp = 11x"7FF") then round_overflow <= not flag_infinity; end if;
      
   end process;
         
   -- all operations
   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         round_start <= '0';
         
         if (command_ena = '1') then
            flag_inexact   <= '0';
            flag_overflow  <= '0';
            flag_underflow <= '0';
            flag_divbyzero <= '0';
            flag_invalid   <= '0';
            flag_infinity  <= '0';
         end if;
         
         overflow_overwrite <= '0';
         if (roundmode_save = 1)                   then overflow_overwrite <= '1'; end if;
         if (roundmode_save = 2 and signOut = '1') then overflow_overwrite <= '1'; end if;
         if (roundmode_save = 3 and signOut = '0') then overflow_overwrite <= '1'; end if;         
         
         underflow_overwrite <= '0';
         if (roundmode_save = 2 and signOut = '0') then underflow_overwrite <= '1'; end if;
         if (roundmode_save = 3 and signOut = '1') then underflow_overwrite <= '1'; end if;
      
         ---------------------------------
         --------------- CIS / CID -------
         ---------------------------------
         CDS_stage1 <= CDS_start and (not exception_inputInvalid);
         
         -- stage 0
         CDS_exp <= to_integer(expA) + 127 - 1023;
         
         -- stage 1
         if (CDS_start = '1') then
            signOut        <= signA_1;
            flag_invalid   <= nanA_1;
            flag_infinity  <= infA_1;
            shifter_right  <= '1';
            shifter_amount <= 26;
            shifter_input  <= 5x"1" & mantA_1;
            if (CDS_exp < 0) then
               round_in_exp(7 downto 0) <= (others => '0');
               if (zeroA_1 = '0') then
                  flag_inexact   <= '1';
                  flag_underflow <= '1';
               end if;
            elsif (CDS_exp >= 255) then
               round_in_exp(7 downto 0) <= (others => '1');
               if (infA_1 = '0') then
                  flag_inexact   <= '1';
                  flag_overflow  <= '1';
               end if;
            elsif (CDS_exp = 0) then
               round_in_exp(7 downto 0) <= (others => '0');
               shifter_input            <= 6x"1" & mantA_1(51 downto 1);
               flag_underflow           <= '1';
            else
               round_in_exp(7 downto 0) <= to_unsigned(CDS_exp, 8);
            end if;
         end if;
         
         -- stage 2
         if (CDS_stage1 = '1') then
            round_start <= '1';
         end if;
      
         ---------------------------------
         --------------- CIS / CID -------
         ---------------------------------
         CIS_stage1 <= CIS_start and (not exception_checkInputConvert2F);
         CID_stage1 <= CID_start and (not exception_checkInputConvert2F);
         CISD_stage2 <= CIS_stage1 or CID_stage1;
         CISD_stage3 <= CISD_stage2;
         
         -- stage 0
         if (bit64 = '1') then
            int_abs <= unsigned(abs(resize(signed(command_op1(55 downto 0)), 57)));
         else
            int_abs <= 24x"0" & unsigned(abs(resize(signed(command_op1(31 downto 0)), 33)));
         end if;
         
         -- stage 1
         if (CIS_start = '1' or CID_start = '1') then
            signOut       <= signA_1;
            shifter_input <= int_abs;
         end if;
         
         -- stage 2
         if (CIS_stage1 = '1') then
            if (clz_int = 56) then 
               CID_exp <= 0;
            else
               CID_exp   <= 127 + (55 - clz_int);
               CID_shift <= 26 - (55 - clz_int);
            end if;
         end if;
         
         if (CID_stage1 = '1') then
            if (clz_int = 56) then 
               CID_exp <= 0;
            else
               CID_exp   <= 1023 + (55 - clz_int);
               CID_shift <= 55 - (55 - clz_int);
            end if;
         end if;
         
         -- stage 3
         if (CISD_stage2 = '1') then
            round_in_exp <= to_unsigned(CID_exp, 11);
            if (CID_shift < 0) then
               shifter_right  <= '1';
               shifter_amount <= -CID_shift;
            else
               shifter_right  <= '0';
               shifter_amount <= CID_shift;
            end if;
         end if;
         
         -- stage 4
         if (CISD_stage3 = '1') then
            round_start <= '1';
         end if;
         

      end if;
   end process;

   -- synthesis translate_off
   process (clk93)
   begin
      if (rising_edge(clk93)) then

         if (reset = '1') then
            debug_calc_count <= 0;
         else  
            if (command_ena = '1') then
               debug_calc_count <= debug_calc_count + 1;
            end if;
         end if;
      end if;
   end process;
  -- synthesis translate_on

end architecture;