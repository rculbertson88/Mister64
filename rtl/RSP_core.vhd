library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;   
use STD.textio.all;

library mem;
use work.pFunctions.all;
use work.pRSP.all;

entity RSP_core is
   port 
   (
      clk1x                 : in  std_logic;
      ce_1x                 : in  std_logic;
      reset_1x              : in  std_logic;
      
      PC_trigger            : in  std_logic;
      PC_in                 : in  unsigned(11 downto 0);
      PC_out                : out unsigned(11 downto 0);
      break_out             : out std_logic;
      
      imem_addr             : out std_logic_vector(9 downto 0);
      imem_dataRead         : in  std_logic_vector(31 downto 0);
      
      dmem_addr             : out tDMEMarray;
      dmem_dataWrite        : out tDMEMarray;
      dmem_WriteEnable      : out std_logic_vector(15 downto 0);
      dmem_dataRead         : in  tDMEMarray;
      
      error_instr           : out std_logic := '0';
      error_stall           : out std_logic := '0'
   );
end entity;

architecture arch of RSP_core is
     
   -- register file
   signal regs_address_a               : std_logic_vector(4 downto 0);
   signal regs_data_a                  : std_logic_vector(31 downto 0);
   signal regs_wren_a                  : std_logic;
   signal regs1_address_b              : std_logic_vector(4 downto 0);
   signal regs1_q_b                    : std_logic_vector(31 downto 0);
   signal regs2_address_b              : std_logic_vector(4 downto 0);
   signal regs2_q_b                    : std_logic_vector(31 downto 0);  
   
   -- other register
   signal PC                           : unsigned(11 downto 0) := (others => '0');               
   
   signal stallNew2                    : std_logic := '0';
   signal stallNew3                    : std_logic := '0';
   signal stallNew4                    : std_logic := '0';
               
   signal stall2                       : std_logic := '0';
   signal stall3                       : std_logic := '0';
   signal stall4                       : std_logic := '0';
   signal stall                        : unsigned(3 downto 1) := (others => '0');
   signal stall4Masked                 : unsigned(3 downto 1) := (others => '0');             
               
-- synthesis translate_off
   signal opcode1                      : unsigned(31 downto 0) := (others => '0');
   signal opcode2                      : unsigned(31 downto 0) := (others => '0');
   signal opcode3                      : unsigned(31 downto 0) := (others => '0');
   signal opcode4                      : unsigned(31 downto 0) := (others => '0');
-- synthesis translate_on  
  
-- synthesis translate_off
   signal PCold1                       : unsigned(11 downto 0) := (others => '0');
   signal PCold2                       : unsigned(11 downto 0) := (others => '0');
   signal PCold3                       : unsigned(11 downto 0) := (others => '0');
   signal PCold4                       : unsigned(11 downto 0) := (others => '0');
-- synthesis translate_on
   
   signal value1                       : unsigned(31 downto 0) := (others => '0');
   signal value2                       : unsigned(31 downto 0) := (others => '0');
               
   -- stage 1          
   
   -- regs           
   signal fetchNew                     : std_logic := '0';
            
   -- stage 2           
   --regs      
   signal decodeNew                    : std_logic := '0';
   signal decodeImmData                : unsigned(15 downto 0) := (others => '0');
   signal decodeSource1                : unsigned(4 downto 0) := (others => '0');
   signal decodeSource2                : unsigned(4 downto 0) := (others => '0');
   signal decodeValue1                 : unsigned(31 downto 0) := (others => '0');
   signal decodeValue2                 : unsigned(31 downto 0) := (others => '0');
   signal decodeOP                     : unsigned(5 downto 0) := (others => '0');
   signal decodeFunct                  : unsigned(5 downto 0) := (others => '0');
   signal decodeShamt                  : unsigned(4 downto 0) := (others => '0');
   signal decodeRD                     : unsigned(4 downto 0) := (others => '0');
   signal decodeTarget                 : unsigned(4 downto 0) := (others => '0');
   signal decodeJumpTarget             : unsigned(25 downto 0) := (others => '0');
   signal decodeForwardValue1          : std_logic := '0';
   signal decodeForwardValue2          : std_logic := '0';
   signal decodeUseImmidateValue2      : std_logic := '0';
   signal decodeShiftSigned            : std_logic := '0';
   signal decodeShiftAmountType        : std_logic := '0';
   
   type t_decodeBitFuncType is
   (
      BITFUNC_SIGNED,
      BITFUNC_UNSIGNED,
      BITFUNC_IMM_SIGNED,
      BITFUNC_IMM_UNSIGNED
   );
   signal decodeBitFuncType : t_decodeBitFuncType;    

   type t_decodeBranchType is
   (
      BRANCH_OFF,
      BRANCH_ALWAYS_REG,
      BRANCH_JUMPIMM,
      BRANCH_BRANCH_BLTZ,
      BRANCH_BRANCH_BGEZ, 
      BRANCH_BRANCH_BEQ,
      BRANCH_BRANCH_BNE,
      BRANCH_BRANCH_BLEZ,
      BRANCH_BRANCH_BGTZ
   );
   signal decodeBranchType    : t_decodeBranchType;   

   type t_decodeResultMux is
   (
      RESULTMUX_SHIFTLEFT, 
      RESULTMUX_SHIFTRIGHT,
      RESULTMUX_ADD,       
      RESULTMUX_PC,
      RESULTMUX_SUB,       
      RESULTMUX_AND,       
      RESULTMUX_OR,        
      RESULTMUX_XOR,       
      RESULTMUX_NOR,       
      RESULTMUX_BIT,   
      RESULTMUX_LUI
   );
   signal decodeResultMux : t_decodeResultMux;   
   
   -- wires
   signal opcodeCacheMuxed             : unsigned(31 downto 0) := (others => '0');
   
   signal decImmData                   : unsigned(15 downto 0);
   signal decSource1                   : unsigned(4 downto 0);
   signal decSource2                   : unsigned(4 downto 0);
   signal decOP                        : unsigned(5 downto 0);
   signal decFunct                     : unsigned(5 downto 0);
   signal decShamt                     : unsigned(4 downto 0);
   signal decRD                        : unsigned(4 downto 0);
   signal decTarget                    : unsigned(4 downto 0);
   signal decJumpTarget                : unsigned(25 downto 0);
            
   -- stage 3   
   signal value2_muxedSigned           : unsigned(31 downto 0);
   signal value2_muxedLogical          : unsigned(31 downto 0);
   signal calcResult_add               : unsigned(31 downto 0);
   signal calcResult_sub               : unsigned(31 downto 0);
   signal calcResult_and               : unsigned(31 downto 0);
   signal calcResult_or                : unsigned(31 downto 0);
   signal calcResult_xor               : unsigned(31 downto 0);
   signal calcResult_nor               : unsigned(31 downto 0);
   signal calcMemAddr                  : unsigned(31 downto 0);
   
   signal calcResult_lesserSigned      : std_logic;
   signal calcResult_lesserUnSigned    : std_logic;
   signal calcResult_lesserIMMSigned   : std_logic;
   signal calcResult_lesserIMMUnsigned : std_logic;
   signal calcResult_bit               : unsigned(31 downto 0);
   
   signal executeShamt                 : unsigned(4 downto 0);
   signal shiftValue                   : signed(32 downto 0);
   signal calcResult_shiftL            : unsigned(31 downto 0);
   signal calcResult_shiftR            : unsigned(31 downto 0);
   
   signal cmpEqual                     : std_logic;
   signal cmpNegative                  : std_logic;
   signal cmpZero                      : std_logic;
   signal PCnext                       : unsigned(11 downto 0) := (others => '0');
   signal PCnextBranch                 : unsigned(11 downto 0) := (others => '0');
   signal FetchAddr                    : unsigned(11 downto 0) := (others => '0');
   
   signal resultDataMuxed              : unsigned(31 downto 0);
   
   type CPU_LOADTYPE is
   (
      LOADTYPE_SBYTE,
      LOADTYPE_SWORD,
      LOADTYPE_DWORD,
      LOADTYPE_BYTE,
      LOADTYPE_WORD
   );
   
   --regs         
   signal executeNew                   : std_logic := '0';
   signal executeStallFromMEM          : std_logic := '0';
   signal resultWriteEnable            : std_logic := '0';
   signal resultTarget                 : unsigned(4 downto 0) := (others => '0');
   signal resultData                   : unsigned(31 downto 0) := (others => '0');
   signal executeMemReadEnable         : std_logic := '0';
   signal executeLoadType              : CPU_LOADTYPE;
   signal executeLoadAddr              : unsigned(11 downto 0);

   --wires
   signal EXEresultWriteEnable         : std_logic;
   signal EXELoadType                  : CPU_LOADTYPE;
   signal EXEReadEnable                : std_logic := '0';
   signal EXEerror_instr               : std_logic := '0';
   
   -- stage 4 
   -- reg      
   signal writebackNew                 : std_logic := '0';
   signal writebackStallFromMEM        : std_logic := '0';
   signal writebackTarget              : unsigned(4 downto 0) := (others => '0');
   signal writebackData                : unsigned(31 downto 0) := (others => '0');
   signal writebackWriteEnable         : std_logic := '0';
   signal dmem_dataRead32              : std_logic_vector(31 downto 0);

   signal debugStallcounter            : unsigned(12 downto 0);
   
   -- export
-- synthesis translate_off
   type tRegs is array(0 to 31) of unsigned(31 downto 0);
   signal regs                         : tRegs := (others => (others => '0'));
   
   signal ce_1x_1                      : std_logic := '0';
   signal writeDoneNew                 : std_logic := '0';
-- synthesis translate_on
   
begin 

   -- common
   stall        <= stall4 & stall3 & stall2;

--##############################################################
--############################### register file
--##############################################################
   iregisterfile1 : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 32,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk1x,
      wren       => regs_wren_a,
      data       => regs_data_a,
      wraddress  => regs_address_a,
      rdaddress  => regs1_address_b,
      q          => regs1_q_b
	);
   
   regs_wren_a    <= writebackWriteEnable;
   
   regs_data_a    <= std_logic_vector(writebackData);
                     
   regs_address_a <= std_logic_vector(writebackTarget);
   
   regs1_address_b <= std_logic_vector(decSource1);
   regs2_address_b <= std_logic_vector(decSource2);
   
   iregisterfile2 : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 32,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk1x,
      wren       => regs_wren_a,
      data       => regs_data_a,
      wraddress  => regs_address_a,
      rdaddress  => regs2_address_b,
      q          => regs2_q_b
	);
   
--##############################################################
--############################### stage 1
--##############################################################
   
   PC_out <= PC;
   
   imem_addr <= std_logic_vector(FetchAddr(11 downto 2));
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (ce_1x = '0') then
         
            fetchNew <= '0';
            PC       <= PC_in;
         
         else
            
            if (stall = 0) then
               PC       <= FetchAddr;
               fetchNew <= '1';
            end if;
            
         end if;
         
         if (PC_trigger = '1') then
            PC <= PC_in;
         end if;
         
      end if;
   end process;
   
--##############################################################
--############################### stage 2
--##############################################################
   
   opcodeCacheMuxed <= byteswap32(unsigned(imem_dataRead));     
                       
   decImmData    <= opcodeCacheMuxed(15 downto 0);
   decJumpTarget <= opcodeCacheMuxed(25 downto 0);
   decSource1    <= opcodeCacheMuxed(25 downto 21);
   decSource2    <= opcodeCacheMuxed(20 downto 16);
   decOP         <= opcodeCacheMuxed(31 downto 26);
   decFunct      <= opcodeCacheMuxed(5 downto 0);
   decShamt      <= opcodeCacheMuxed(10 downto 6);
   decRD         <= opcodeCacheMuxed(15 downto 11);
   decTarget     <= opcodeCacheMuxed(20 downto 16) when (opcodeCacheMuxed(31 downto 26) > 0) else opcodeCacheMuxed(15 downto 11);                  

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (ce_1x = '0') then
         
            stall2           <= '0';
            decodeNew        <= '0';
            decodeBranchType <= BRANCH_OFF;
            
         else
         
            if (stall = 0) then
            
               decodeNew <= '0';
            
               if (fetchNew = '1') then
               
                  decodeNew        <= not break_out; 
               
-- synthesis translate_off
                  pcOld1           <= PC;
                  opcode1          <= opcodeCacheMuxed;
-- synthesis translate_on
                                    
                  decodeImmData    <= decImmData;   
                  decodeJumpTarget <= decJumpTarget;
                  decodeSource1    <= decSource1;
                  decodeSource2    <= decSource2;
                  decodeOP         <= decOP;
                  decodeFunct      <= decFunct;     
                  decodeShamt      <= decShamt;     
                  decodeRD         <= decRD;        
                  decodeTarget     <= decTarget;    
                  
                  -- operand fetching
                  decodeValue1     <= unsigned(regs1_q_b);
                  if    (decSource1 > 0 and resultTarget    = decSource1 and resultWriteEnable    = '1') then decodeValue1 <= resultData;
                  elsif (decSource1 > 0 and writebackTarget = decSource1 and writebackWriteEnable = '1') then decodeValue1 <= writebackData;
                  end if;
                  
                  decodeValue2     <= unsigned(regs2_q_b);
                  if    (decSource2 > 0 and resultTarget    = decSource2 and resultWriteEnable    = '1') then decodeValue2 <= resultData;
                  elsif (decSource2 > 0 and writebackTarget = decSource2 and writebackWriteEnable = '1') then decodeValue2 <= writebackData;
                  end if;
                  
                  decodeForwardValue1 <= '0';
                  decodeForwardValue2 <= '0';
                  if (decSource1 > 0 and decodeTarget = decSource1) then decodeForwardValue1 <= '1'; end if;
                  if (decSource2 > 0 and decodeTarget = decSource2) then decodeForwardValue2 <= '1'; end if;

                  -- decoding default
                  decodeUseImmidateValue2 <= '0';
                  decodeShiftSigned       <= '0';
                  decodeBranchType        <= BRANCH_OFF;

                  -- decoding opcode specific
                  case (to_integer(decOP)) is
         
                     when 16#00# =>
                        case (to_integer(decFunct)) is
                        
                           when 16#00# => -- SLL
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= '0';
                              
                           when 16#02# => -- SRL
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= '0';
                           
                           when 16#03# => -- SRA
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT; 
                              decodeShiftSigned       <= '1';
                              decodeShiftAmountType   <= '0';
                              
                           when 16#04# => -- SLLV
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= '1';
                              
                           when 16#06# => -- SRLV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= '1';
                           
                           when 16#07# => -- SRAV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftSigned       <= '1';
                              decodeShiftAmountType   <= '1';
                              
                           when 16#08# => -- JR
                              decodeBranchType        <= BRANCH_ALWAYS_REG;
                              
                           when 16#09# => -- JALR
                              decodeResultMux         <= RESULTMUX_PC;
                              decodeTarget            <= decRD;
                              decodeBranchType        <= BRANCH_ALWAYS_REG;
                              
                           when 16#0D# => -- break
                              null;
                           
                           when 16#20#| 16#21# => -- ADD/ADDU
                              decodeResultMux         <= RESULTMUX_ADD;
                              
                           when 16#22# | 16#23# => -- SUB/SUBU
                              decodeResultMux         <= RESULTMUX_SUB;
                           
                           when 16#24# => -- AND
                              decodeResultMux         <= RESULTMUX_AND;
                           
                           when 16#25# => -- OR
                              decodeResultMux         <= RESULTMUX_OR;
                              
                           when 16#26# => -- XOR
                              decodeResultMux         <= RESULTMUX_XOR;
                              
                           when 16#27# => -- NOR
                              decodeResultMux         <= RESULTMUX_NOR;
                              
                           when 16#2A# => -- SLT
                              decodeResultMux         <= RESULTMUX_BIT;
                              decodeBitFuncType       <= BITFUNC_SIGNED;
                           
                           when 16#2B# => -- SLTU
                              decodeResultMux         <= RESULTMUX_BIT;
                              decodeBitFuncType       <= BITFUNC_UNSIGNED;

                           when others => null;
                        end case;
  
                     when 16#01# => -- B: BLTZ, BGEZ
                        if (decSource2(4 downto 1) = "1000") then 
                           decodeResultMux      <= RESULTMUX_PC;
                           decodeTarget         <= to_unsigned(31, 5);
                        end if;
                        if (decSource2(0) = '1') then
                           decodeBranchType     <= BRANCH_BRANCH_BGEZ;
                        else
                           decodeBranchType     <= BRANCH_BRANCH_BLTZ;
                        end if;
                        
                     when 16#02# => -- J
                        decodeBranchType        <= BRANCH_JUMPIMM;
               
                     when 16#03# => -- JAL
                        decodeResultMux         <= RESULTMUX_PC;
                        decodeTarget            <= to_unsigned(31, 5);
                        decodeBranchType        <= BRANCH_JUMPIMM;
                        
                     when 16#04# => -- BEQ
                        decodeBranchType        <= BRANCH_BRANCH_BEQ;
                     
                     when 16#05# => -- BNE
                        decodeBranchType        <= BRANCH_BRANCH_BNE;
                     
                     when 16#06# => -- BLEZ
                        decodeBranchType        <= BRANCH_BRANCH_BLEZ;
                        
                     when 16#07# => -- BGTZ
                        decodeBranchType        <= BRANCH_BRANCH_BGTZ;
                        
                     when 16#08# | 16#09#  => -- ADDI / ADDIU
                        decodeResultMux         <= RESULTMUX_ADD;
                        decodeUseImmidateValue2 <= '1';
                        
                     when 16#0A# => -- SLTI
                        decodeResultMux         <= RESULTMUX_BIT;
                        decodeBitFuncType       <= BITFUNC_IMM_SIGNED;   
                        
                     when 16#0B# => -- SLTIU
                        decodeResultMux         <= RESULTMUX_BIT;
                        decodeBitFuncType       <= BITFUNC_IMM_UNSIGNED; 
                        
                     when 16#0C# => -- ANDI
                        decodeResultMux         <= RESULTMUX_AND;
                        decodeUseImmidateValue2 <= '1';
                        
                     when 16#0D# => -- ORI
                        decodeResultMux         <= RESULTMUX_OR;
                        decodeUseImmidateValue2 <= '1';
                        
                     when 16#0E# => -- XORI
                        decodeResultMux         <= RESULTMUX_XOR;
                        decodeUseImmidateValue2 <= '1';
                        
                     when 16#0F# => -- LUI
                        decodeResultMux         <= RESULTMUX_LUI;
                        
                     when 16#10# => -- COP0
                        null;  
                        
                     when 16#20# => null; -- LB
                     when 16#21# => null; -- LH
                     when 16#23# => null; -- LW
                     when 16#24# => null; -- LBU
                     when 16#25# => null; -- LHU
                     when 16#27# => null; -- LWU
                     when 16#28# => null; -- SB
                     when 16#29# => null; -- SH
                     when 16#2B# => null; -- SW
                     
                     when 16#32# => null; -- LWC2
                     when 16#3A# => null; -- SWC2
                          
                     when others => null;   
                     
                  end case;
                  
               end if; -- fetchReady
      
            else
               
               -- operand forwarding in stall
               if (decodeSource1 > 0 and writebackTarget = decodeSource1 and writebackWriteEnable = '1') then decodeValue1 <= writebackData; end if;
               if (decodeSource2 > 0 and writebackTarget = decodeSource2 and writebackWriteEnable = '1') then decodeValue2 <= writebackData; end if;
      
            end if; -- stall

         end if; -- ce
      end if; -- clk
   end process;
   
   
--##############################################################
--############################### stage 3
--##############################################################
   
   ---------------------- Operand forward ------------------
   
   value1 <= resultData when (decodeForwardValue1 = '1' and resultWriteEnable = '1') else decodeValue1;
   value2 <= resultData when (decodeForwardValue2 = '1' and resultWriteEnable = '1') else decodeValue2;
   
   ---------------------- Adder ------------------
   value2_muxedSigned <= unsigned(resize(signed(decodeImmData), 32)) when (decodeUseImmidateValue2) else value2;
   calcResult_add     <= value1 + value2_muxedSigned;
   
   calcMemAddr        <= value1 + unsigned(resize(signed(decodeImmData), 32));
   
   ---------------------- Shifter ------------------
   -- multiplex immidiate and register based shift amount, so both types can use the same shifters
   executeShamt <= decodeShamt when (decodeShiftAmountType = '0') else
                   value1(4 downto 0);
   
   -- multiplex high bit of rightshift so arithmetic shift can be reused for logical shift
   shiftValue(31 downto 0)  <= signed(value2(31 downto 0));
   shiftValue(32) <= value2(31) when (decodeShiftSigned = '1') else '0';

   calcResult_shiftL <= value2 sll to_integer(executeShamt);
   calcResult_shiftR <= resize(unsigned(shift_right(shiftValue,to_integer(executeShamt))), 32);  

   ---------------------- Sub ------------------
   calcResult_sub    <= value1 - value2;
   
   ---------------------- logical calcs ------------------
   value2_muxedLogical <= x"0000" & decodeImmData when (decodeUseImmidateValue2) else value2;
   
   calcResult_and    <= value1 and value2_muxedLogical;
   calcResult_or     <= value1 or value2_muxedLogical;
   calcResult_xor    <= value1 xor value2_muxedLogical;
   calcResult_nor    <= value1 nor value2;

   ---------------------- bit functions ------------------
   
   calcResult_lesserSigned      <= '1' when (signed(value1) < signed(value2)) else '0'; 
   calcResult_lesserUnsigned    <= '1' when (value1 < value2) else '0';    
   calcResult_lesserIMMSigned   <= '1' when (signed(value1) < resize(signed(decodeImmData), 32)) else '0'; 
   calcResult_lesserIMMUnsigned <= '1' when (value1 < unsigned(resize(signed(decodeImmData), 32))) else '0'; 
   
   calcResult_bit(31 downto 1) <= (others => '0');
   calcResult_bit(0) <= calcResult_lesserSigned       when (decodeBitFuncType = BITFUNC_SIGNED) else
                        calcResult_lesserUnSigned     when (decodeBitFuncType = BITFUNC_UNSIGNED) else
                        calcResult_lesserIMMSigned    when (decodeBitFuncType = BITFUNC_IMM_SIGNED) else
                        calcResult_lesserIMMUnsigned;  -- when (decodeBitFuncType = BITFUNC_IMM_UNSIGNED)
   
   ---------------------- branching ------------------
   PCnext       <= PC + 4;
   PCnextBranch <= PC + unsigned((resize(signed(decodeImmData), 10) & "00"));
   
   cmpEqual    <= '1' when (value1 = value2) else '0';
   cmpNegative <= value1(31);
   cmpZero     <= '1' when (value1 = 0) else '0';
   
   FetchAddr   <= PC                                  when (fetchNew = '0' or stall > 0) else
                  PCnext                              when (decodeNew = '0') else
                  value1(11 downto 0)                 when (decodeBranchType = BRANCH_ALWAYS_REG) else
                  decodeJumpTarget(9 downto 0) & "00" when (decodeBranchType = BRANCH_JUMPIMM) else
                  PCnextBranch                        when (decodeBranchType = BRANCH_BRANCH_BGEZ and (cmpZero = '1' or cmpNegative = '0'))  else
                  PCnextBranch                        when (decodeBranchType = BRANCH_BRANCH_BLTZ and cmpNegative = '1')                     else
                  PCnextBranch                        when (decodeBranchType = BRANCH_BRANCH_BEQ  and cmpEqual = '1')                        else
                  PCnextBranch                        when (decodeBranchType = BRANCH_BRANCH_BNE  and cmpEqual = '0')                        else
                  PCnextBranch                        when (decodeBranchType = BRANCH_BRANCH_BLEZ and (cmpZero = '1' or cmpNegative = '1'))  else
                  PCnextBranch                        when (decodeBranchType = BRANCH_BRANCH_BGTZ and (cmpZero = '0' and cmpNegative = '0')) else
                  PCnext;     

   ---------------------- result muxing ------------------
   resultDataMuxed <= calcResult_shiftL when (decodeResultMux = RESULTMUX_SHIFTLEFT)  else
                      calcResult_shiftR when (decodeResultMux = RESULTMUX_SHIFTRIGHT) else
                      calcResult_add    when (decodeResultMux = RESULTMUX_ADD)        else
                      20x"0" & PCnext   when (decodeResultMux = RESULTMUX_PC)         else
                      calcResult_sub    when (decodeResultMux = RESULTMUX_SUB)        else
                      calcResult_and    when (decodeResultMux = RESULTMUX_AND)        else
                      calcResult_or     when (decodeResultMux = RESULTMUX_OR )        else
                      calcResult_xor    when (decodeResultMux = RESULTMUX_XOR)        else
                      calcResult_nor    when (decodeResultMux = RESULTMUX_NOR)        else
                      calcResult_bit    when (decodeResultMux = RESULTMUX_BIT)        else
                      unsigned(resize(signed(decodeImmData) & x"0000", 32)); -- (decodeResultMux = RESULTMUX_LUI);  

   
   
   process (decodeSource2, decodeOP, decodeFunct, stall3, stall, value2, decodeNew, calcMemAddr)
      type trotatedData is array(0 to 3) of std_logic_vector(7 downto 0);
      variable rotatedData : trotatedData;
      variable rotateAddrMuxAdd : integer range 0 to 3;
   begin
   
      EXEerror_instr          <= '0';
   
      stallNew3               <= stall3;
      EXEresultWriteEnable    <= '0';  
      break_out               <= '0';      
      
      -- DMEM muxing 
      rotateAddrMuxAdd := 0;
      if (to_integer(decodeOP) = 16#28#) then -- SB
         case (calcMemAddr(1 downto 0)) is
            when "00" => rotateAddrMuxAdd := 3;
            when "01" => rotateAddrMuxAdd := 2;
            when "10" => rotateAddrMuxAdd := 1;
            when "11" => rotateAddrMuxAdd := 0;
            when others => null;
         end case;
      elsif (to_integer(decodeOP) = 16#29#) then -- SH
         case (calcMemAddr(1 downto 0)) is
            when "00" => rotateAddrMuxAdd := 2;
            when "01" => rotateAddrMuxAdd := 1;
            when "10" => rotateAddrMuxAdd := 0;
            when "11" => rotateAddrMuxAdd := 3;
            when others => null;
         end case;
      else
         case (calcMemAddr(1 downto 0)) is
            when "00" => rotateAddrMuxAdd := 0;
            when "01" => rotateAddrMuxAdd := 3;
            when "10" => rotateAddrMuxAdd := 2;
            when "11" => rotateAddrMuxAdd := 1;
            when others => null;
         end case;
      end if;
      
      rotatedData(0) := std_logic_vector(value2(31 downto 24));
      rotatedData(1) := std_logic_vector(value2(23 downto 16));
      rotatedData(2) := std_logic_vector(value2(15 downto  8));
      rotatedData(3) := std_logic_vector(value2( 7 downto  0));
      
      EXELoadType             <= LOADTYPE_DWORD;
      EXEReadEnable           <= '0';
      
      for i in 0 to 15 loop
         if (calcMemAddr(3 downto 0) > i) then
            dmem_addr(i)      <= std_logic_vector(calcMemAddr(11 downto 4) + 1);
         else
            dmem_addr(i)      <= std_logic_vector(calcMemAddr(11 downto 4));
         end if;
         dmem_WriteEnable     <= (others => '0');   
         dmem_dataWrite(i)    <= rotatedData((i + rotateAddrMuxAdd) mod 4);
      end loop;

      
      if (stall = 0 and decodeNew = '1') then
             
         case (to_integer(decodeOP)) is
         
            when 16#00# =>
               case (to_integer(decodeFunct)) is
         
                  when 16#00# | 16#04# => -- SLL | SLLV
                     EXEresultWriteEnable <= '1';

                  when 16#02# | 16#03# | 16#06# | 16#07# => -- SRL | SRA | SRLV | SRAV
                     EXEresultWriteEnable <= '1';               
                    
                  when 16#08# => -- JR        
                     null;
                    
                  when 16#09# => -- JALR        
                     EXEresultWriteEnable <= '1';

                  when 16#0D# => -- BREAK
                     break_out <= '1';
                     
                  when 16#20# | 16#21# => -- ADD / ADDU        
                     EXEresultWriteEnable <= '1';
                    
                  when 16#22# |16#23# => -- SUB | SUBU       
                     EXEresultWriteEnable <= '1';
                  
                  when 16#24# => -- AND
                     EXEresultWriteEnable <= '1';
                    
                  when 16#25# => -- OR
                     EXEresultWriteEnable <= '1';
                     
                  when 16#26# => -- XOR
                     EXEresultWriteEnable <= '1';
                     
                  when 16#27# => -- NOR
                     EXEresultWriteEnable <= '1';
                  
                  when 16#2A# => -- SLT
                     EXEresultWriteEnable <= '1'; 
                   
                  when 16#2B# => -- SLTU
                     EXEresultWriteEnable <= '1';
                 
                  when others => 
                  -- synthesis translate_off
                     report to_hstring(decodeFunct);
                  -- synthesis translate_on
                     --report "Unknown extended opcode" severity failure; 
                     EXEerror_instr  <= '1';
                     
               end case;
               
            when 16#01# => 
               if (decodeSource2(4 downto 1) = "1000") then
                  EXEresultWriteEnable <= '1';
               end if;
               
            when 16#02# => -- J
               null;            
               
            when 16#03# => -- JAL         
               EXEresultWriteEnable <= '1';
               
            when 16#04# => -- BEQ
               null;
            
            when 16#05# => -- BNE
               null;
            
            when 16#06# => -- BLEZ
               null;
               
            when 16#07# => -- BGTZ
               null;
            
            when 16#08# | 16#09# => -- ADDI | ADDIU           
               EXEresultWriteEnable <= '1';
               
            when 16#0A# => -- SLTI
               EXEresultWriteEnable <= '1';
               
            when 16#0B# => -- SLTIU
               EXEresultWriteEnable <= '1';

            when 16#0C# => -- ANDI
               EXEresultWriteEnable <= '1';
               
            when 16#0D# => -- ORI
               EXEresultWriteEnable <= '1';
               
            when 16#0E# => -- XORI
               EXEresultWriteEnable <= '1';
               
            when 16#0F# => -- LUI
               EXEresultWriteEnable <= '1';
               
            when 16#10# => -- COP0
               null;
               
            when 16#20# => -- LB
               EXELoadType   <= LOADTYPE_SBYTE;
               EXEReadEnable <= '1';
               
            when 16#21# => -- LH
               EXELoadType <= LOADTYPE_SWORD;
               EXEReadEnable <= '1';
               
            when 16#23# | 16#27# => -- LW / LWU
               EXELoadType <= LOADTYPE_DWORD;
               EXEReadEnable <= '1';

            when 16#24# => -- LBU
               EXELoadType <= LOADTYPE_BYTE;
               EXEReadEnable <= '1';

            when 16#25# => -- LHU
               EXELoadType <= LOADTYPE_WORD;
               EXEReadEnable <= '1';

            when 16#28# => -- SB
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0))) <= '1';

            when 16#29# => -- SH
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 0)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 1)) <= '1';
               
            when 16#2B# => -- SW
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 0)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 1)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 2)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 3)) <= '1';
           
            when 16#32# => -- LWC2
               null;
               
            when 16#3A# => -- SWC2
               null;
          
            when others => 
               -- synthesis translate_off
               report to_hstring(decodeOP);
               -- synthesis translate_on
               --report "Unknown opcode" severity failure; 
               EXEerror_instr  <= '1';
         
         end case;
             
      end if;
      
   end process;
   
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         error_instr <= '0';
      
         if (ce_1x = '0') then
         
            stall3                        <= '0';
            executeNew                    <= '0';
            executeStallFromMEM           <= '0';
            resultWriteEnable             <= '0';
            
         else
            
            -- load delay block
            if (stall3) then
            
               if (stall = "010") then
                  executeStallFromMEM <= '0';
                  executeNew          <= '0';
               end if;

               if (writebackStallFromMEM = '1' and writebackNew = '1') then
                  stall3 <= '0';
               end if;
               
            end if;

            if (stall = 0) then
            
               executeNew <= '0';
               
               resultData              <= resultDataMuxed;    
               resultTarget            <= decodeTarget;                   
            
               if (decodeNew = '1') then     
               
                  executeNew           <= '1';
                  
                  error_instr          <= EXEerror_instr;
               
-- synthesis translate_off
                  pcOld2               <= pcOld1;  
                  opcode2              <= opcode1;
-- synthesis translate_on
                        
                  stall3               <= stallNew3;
                        
                  -- from calculation
                  if (decodeTarget = 0) then
                     resultWriteEnable <= '0';
                  else
                     resultWriteEnable <= EXEresultWriteEnable;
                  end if;
                        
                  executeLoadType               <= EXELoadType;   
                  executeMemReadEnable          <= EXEReadEnable; 
                  executeLoadAddr               <= calcMemAddr(11 downto 0); 

                  if (EXEReadEnable = '1') then
                     stall3              <= '1';
                     executeStallFromMEM <= '1';
                  end if;
                  
               end if;
               
               
            end if;

         end if;
         
      end if;
   end process;
   
   
--##############################################################
--############################### stage 4
--##############################################################

   stall4Masked <= stall(3) & (stall(2) and (not executeStallFromMEM)) & stall(1);
   
   dmem_dataRead32 <= dmem_dataRead(3 ) & dmem_dataRead(2 ) & dmem_dataRead(1 ) & dmem_dataRead(0 ) when (executeLoadAddr(3 downto 0) = x"0") else
                      dmem_dataRead(4 ) & dmem_dataRead(3 ) & dmem_dataRead(2 ) & dmem_dataRead(1 ) when (executeLoadAddr(3 downto 0) = x"1") else
                      dmem_dataRead(5 ) & dmem_dataRead(4 ) & dmem_dataRead(3 ) & dmem_dataRead(2 ) when (executeLoadAddr(3 downto 0) = x"2") else
                      dmem_dataRead(6 ) & dmem_dataRead(5 ) & dmem_dataRead(4 ) & dmem_dataRead(3 ) when (executeLoadAddr(3 downto 0) = x"3") else
                      dmem_dataRead(7 ) & dmem_dataRead(6 ) & dmem_dataRead(5 ) & dmem_dataRead(4 ) when (executeLoadAddr(3 downto 0) = x"4") else
                      dmem_dataRead(8 ) & dmem_dataRead(7 ) & dmem_dataRead(6 ) & dmem_dataRead(5 ) when (executeLoadAddr(3 downto 0) = x"5") else
                      dmem_dataRead(9 ) & dmem_dataRead(8 ) & dmem_dataRead(7 ) & dmem_dataRead(6 ) when (executeLoadAddr(3 downto 0) = x"6") else
                      dmem_dataRead(10) & dmem_dataRead(9 ) & dmem_dataRead(8 ) & dmem_dataRead(7 ) when (executeLoadAddr(3 downto 0) = x"7") else
                      dmem_dataRead(11) & dmem_dataRead(10) & dmem_dataRead(9 ) & dmem_dataRead(8 ) when (executeLoadAddr(3 downto 0) = x"8") else
                      dmem_dataRead(12) & dmem_dataRead(11) & dmem_dataRead(10) & dmem_dataRead(9 ) when (executeLoadAddr(3 downto 0) = x"9") else
                      dmem_dataRead(13) & dmem_dataRead(12) & dmem_dataRead(11) & dmem_dataRead(10) when (executeLoadAddr(3 downto 0) = x"A") else
                      dmem_dataRead(14) & dmem_dataRead(13) & dmem_dataRead(12) & dmem_dataRead(11) when (executeLoadAddr(3 downto 0) = x"B") else
                      dmem_dataRead(15) & dmem_dataRead(14) & dmem_dataRead(13) & dmem_dataRead(12) when (executeLoadAddr(3 downto 0) = x"C") else
                      dmem_dataRead( 0) & dmem_dataRead(15) & dmem_dataRead(14) & dmem_dataRead(13) when (executeLoadAddr(3 downto 0) = x"D") else
                      dmem_dataRead( 1) & dmem_dataRead( 0) & dmem_dataRead(15) & dmem_dataRead(14) when (executeLoadAddr(3 downto 0) = x"E") else
                      dmem_dataRead( 2) & dmem_dataRead( 1) & dmem_dataRead( 0) & dmem_dataRead(15);
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (ce_1x = '0') then
         
            stall4                           <= '0';
            writebackNew                     <= '0';
            writebackStallFromMEM            <= '0';                  
            writebackWriteEnable             <= '0';
            
         else
         
            stall4                  <= '0';

            if (stall4Masked = 0) then
            
               writebackNew   <= '0';
            
               if (executeNew = '1') then
               
                  writebackNew                 <= '1';
               
                  writebackStallFromMEM        <= executeStallFromMEM;
               
-- synthesis translate_off
                  pcOld3                       <= pcOld2;
                  opcode3                      <= opcode2;
-- synthesis translate_on
               
                  writebackTarget              <= resultTarget;
                  writebackData                <= resultData;
                  writebackWriteEnable         <= resultWriteEnable;
                  
                  if (executeMemReadEnable = '1') then
                  
                     if (resultTarget > 0) then
                        writebackWriteEnable <= '1';
                     end if;
                     
                     case (executeLoadType) is
                        
                        when LOADTYPE_SBYTE => null; writebackData <= unsigned(resize(signed(dmem_dataRead32(7 downto 0)), 32));
                        when LOADTYPE_SWORD => null; writebackData <= unsigned(resize(signed(byteswap16(dmem_dataRead32(15 downto 0))), 32));     
                        when LOADTYPE_DWORD => null; writebackData <= unsigned(resize(signed(byteswap32(dmem_dataRead32(31 downto 0))), 32));
                        when LOADTYPE_BYTE  => null; writebackData <= x"000000" & unsigned(dmem_dataRead32(7 downto 0));
                        when LOADTYPE_WORD  => null; writebackData <= x"0000" & unsigned(byteswap16(dmem_dataRead32(15 downto 0)));
                           
                     end case; 

                  end if;

               end if;
               
            end if;

         end if; -- ce
         

      end if;
   end process;
   
   
--##############################################################
--############################### stage 5
--##############################################################
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
       
-- synthesis translate_off       
         writeDoneNew <= '0';
         ce_1x_1      <= ce_1x;
         
         if (ce_1x = '1' or ce_1x_1 = '1') then
            
            if (stall4Masked = 0 and writebackNew = '1') then

               writeDoneNew         <= '1';

               pcOld4               <= pcOld3;
               opcode4              <= opcode3;
               
               if (writebackWriteEnable = '1') then 
                  if (writebackTarget > 0) then
                     regs(to_integer(writebackTarget)) <= writebackData;
                  end if;
               end if;
               
            end if;
             
         end if;
-- synthesis translate_on
         
      end if;
   end process;

--##############################################################
--############################### submodules
--##############################################################
   

 
--##############################################################
--############################### debug
--##############################################################

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         error_stall <= '0';
      
         if (ce_1x = '0') then
         
            debugStallcounter <= (others => '0');
      
         else
         
            if (stall = 0) then
               debugStallcounter <= (others => '0');
            else
               debugStallcounter <= debugStallcounter + 1;
            end if;         
            
            if (debugStallcounter(12) = '1') then
               error_stall       <= '1';
            end if;
            
         end if;
         
      end if;
   end process;
   
--##############################################################
--############################### export
--##############################################################
   
   -- synthesis translate_off
   goutput : if 1 = 1 generate
      signal out_count        : unsigned(31 downto 0) := (others => '0');
      signal regs_last        : tRegs := (others => (others => '0'));
      signal firstExport      : std_logic := '0';
   begin
   
      process
         file outfile          : text;
         variable f_status     : FILE_OPEN_STATUS;
         variable line_out     : line;
         variable stringbuffer : string(1 to 31);
      begin
   
         file_open(f_status, outfile, "R:\\rsp_n64_sim.txt", write_mode);
         file_close(outfile);
         file_open(f_status, outfile, "R:\\rsp_n64_sim.txt", append_mode);
         
         while (true) loop
            
            wait until rising_edge(clk1x);
             
            if (reset_1x = '1') then
               file_close(outfile);
               file_open(f_status, outfile, "R:\\rsp_n64_sim.txt", write_mode);
               file_close(outfile);
               file_open(f_status, outfile, "R:\\rsp_n64_sim.txt", append_mode);
               out_count <= (others => '0');
            end if;
            
            if (ce_1x_1 = '0' and ce_1x = '1') then
               write(line_out, string'("Reset")); 
               writeline(outfile, line_out);
               out_count <= out_count + 1;
               firstExport <= '1';
            end if;
            
            if (writeDoneNew = '1') then
               -- count
               write(line_out, string'("# ")); 
               write(line_out, to_hstring(out_count));
               -- PC
               write(line_out, string'(" PC ")); 
               write(line_out, to_hstring(pcOld4));
               -- OP
               write(line_out, string'(" OP ")); 
               write(line_out, to_hstring(opcode4));
               write(line_out, string'(" "));
               -- regs
               for i in 0 to 31 loop
                  if (regs(i) /= regs_last(i) or firstExport = '1') then
                     write(line_out, string'("R"));
                     if (i < 10) then 
                        write(line_out, string'("0"));
                     end if;
                     write(line_out, to_string(i));
                     write(line_out, string'(" "));
                     write(line_out, to_hstring(regs(i)) & " ");
                  end if;
               end loop; 
               regs_last <= regs;
               firstExport <= '0';
               
               writeline(outfile, line_out);
               out_count <= out_count + 1;
               
               if (ce_1x_1 = '0') then
                  -- count
                  write(line_out, string'("# ")); 
                  write(line_out, to_hstring(out_count + 1));
                  -- PC
                  write(line_out, string'(" PC ")); 
                  write(line_out, to_hstring(pcOld2));
                  -- OP
                  write(line_out, string'(" OP ")); 
                  write(line_out, to_hstring(opcode2));
                  write(line_out, string'(" "));
               
                  writeline(outfile, line_out);
                  out_count <= out_count + 2;
               end if;
               
            end if;
            
            --if (export_command_done = '1') then
            --   write(line_out, string'("Command: I ")); 
            --   write(line_out, to_string_len(tracecounts_out(2) + 1, 8));
            --   write(line_out, string'(" A ")); 
            --   write(line_out, to_hstring(export_command_array.addr + (commandRAMPtr - 1) * 8));
            --   write(line_out, string'(" D "));
            --   write(line_out, to_hstring(CommandData));
            --   writeline(outfile, line_out);
            --   tracecounts_out(2) <= tracecounts_out(2) + 1;
            --end if;
           
            
         end loop;
         
      end process;
   
   end generate goutput;

   -- synthesis translate_on  
   

end architecture;





