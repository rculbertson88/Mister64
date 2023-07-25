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
      
      reg_addr              : out unsigned(6 downto 0);
      reg_dataWrite         : out unsigned(31 downto 0);
      reg_RSP_read          : out std_logic;
      reg_RDP_read          : out std_logic;
      reg_RSP_write         : out std_logic;
      reg_RDP_write         : out std_logic;
      reg_RSP_dataRead      : in  unsigned(31 downto 0);
      reg_RDP_dataRead      : in  unsigned(31 downto 0);
      
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
   
   -- vector regs
   type t_vec_addr is array(0 to 7) of std_logic_vector(4 downto 0);
   signal vec_addr_a                   : t_vec_addr;
   signal vec_addr_b_1                 : t_vec_addr;
   signal vec_addr_b_2                 : t_vec_addr;
   
   type t_vec_data is array(0 to 15) of std_logic_vector(7 downto 0);
   signal vec_data_a                   : t_vec_data;
   signal vec_data_b_1                 : t_vec_data;
   signal vec_data_b_2                 : t_vec_data;
   
   signal vec_writeEna                 : std_logic_vector(15 downto 0);
   
   -- other register
   signal PC                           : unsigned(11 downto 0) := (others => '0');               
   
   signal stall2                       : std_logic := '0';
   signal stall3                       : std_logic := '0';
   signal stall                        : unsigned(2 downto 1) := (others => '0');           
               
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
   
   signal decVectorElement             : unsigned(3 downto 0);
   signal decVectorDestEle             : unsigned(2 downto 0);
   signal decVectorMfcE                : unsigned(3 downto 0);
   
   --regs    
   signal decodeStallcount             : integer range 0 to 2 := 0;
   
   signal decodeNew                    : std_logic := '0';
   signal decodeImmData                : unsigned(15 downto 0) := (others => '0');
   signal decodeSource1                : unsigned(4 downto 0) := (others => '0');
   signal decodeSource2                : unsigned(4 downto 0) := (others => '0');
   signal decodeValue1                 : unsigned(31 downto 0) := (others => '0');
   signal decodeValue2                 : unsigned(31 downto 0) := (others => '0');
   signal decodeShamt                  : unsigned(4 downto 0) := (others => '0');
   signal decodeRD                     : unsigned(4 downto 0) := (others => '0');
   signal decodeTarget                 : unsigned(4 downto 0) := (others => '0');
   signal decodeJumpTarget             : unsigned(25 downto 0) := (others => '0');
   signal decodeForwardValue1          : std_logic := '0';
   signal decodeForwardValue2          : std_logic := '0';
   signal decodeUseImmidateValue2      : std_logic := '0';
   signal decodeShiftSigned            : std_logic := '0';
   signal decodeShiftAmountType        : std_logic := '0';
   signal decodeWriteEnable            : std_logic := '0';
   signal decode_break                 : std_logic := '0';
   signal decodeReadEnable             : std_logic := '0';
   signal decodeReadRSPReg             : std_logic := '0';
   signal decodeReadRDPReg             : std_logic := '0';   
   signal decodeWriteRSPReg            : std_logic := '0';
   signal decodeWriteRDPReg            : std_logic := '0';
   signal decodeRegAddr                : unsigned(6 downto 0) := (others => '0');
   signal decodeMemOffset              : signed(15 downto 0) := (others => '0');
   
   signal decodeVectorNew              : std_logic := '0';
   signal decodeVectorValue1           : t_vec_data;
   signal decodeVectorValue2           : t_vec_data;
   signal decodeVectorAddrWrap         : std_logic := '0';
   signal decodeVectorWriteEnable      : std_logic := '0';
   signal decodeVectorReadEnable       : std_logic := '0';
   signal decodeVectorShiftEnable      : unsigned(15 downto 0) := (others => '0');
   signal decodeVectorElement          : unsigned(3 downto 0);
   signal decodeVectorDestEle          : unsigned(2 downto 0);
   signal decodeVectorMfcE             : unsigned(3 downto 0);
   signal decodeVectorMTC2             : std_logic := '0';
   signal decode_set_vco               : std_logic := '0';
   signal decode_set_vcc               : std_logic := '0';
   signal decode_set_vce               : std_logic := '0';
   signal decodeVectorCalcType         : VECTOR_CALCTYPE; 
   
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
      RESULTMUX_LUI,
      RESULTMUX_VCO,
      RESULTMUX_VCC,
      RESULTMUX_VCE,
      RESULTMUX_VECTOR
   );
   signal decodeResultMux : t_decodeResultMux;  

   type CPU_LOADTYPE is
   (
      LOADTYPE_SBYTE,
      LOADTYPE_SWORD,
      LOADTYPE_DWORD,
      LOADTYPE_BYTE,
      LOADTYPE_WORD
   );
   signal decodeLoadType               : CPU_LOADTYPE;   
   
   type CPU_SAVETYPE is
   (
      SAVETYPE_NONE,
      SAVETYPE_DWORD,
      SAVETYPE_BYTE,
      SAVETYPE_WORD
   );
   signal decodeSaveType               : CPU_SAVETYPE;     
   
   type VECTOR_LOADTYPE is
   (
      VECTORLOADTYPE_LBV,
      VECTORLOADTYPE_LSV,
      VECTORLOADTYPE_LLV,
      VECTORLOADTYPE_LDV,
      VECTORLOADTYPE_LQV
   );
   signal decodeVectorLoadType         : VECTOR_LOADTYPE;   
            
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
   signal PCnextBranch                 : unsigned(17 downto 0) := (others => '0');
   signal FetchAddr                    : unsigned(11 downto 0) := (others => '0');
   
   signal resultDataMuxed              : unsigned(31 downto 0);
   
   signal vco                          : unsigned(15 downto 0);
   signal vcc                          : unsigned(15 downto 0);
   signal vce                          : unsigned(7 downto 0);
   signal MFC2_value                   : std_logic_vector(15 downto 0);
   
   --regs         
   signal executeNew                   : std_logic := '0';
   signal executeStallFromMEM          : std_logic := '0';
   signal resultWriteEnable            : std_logic := '0';
   signal resultTarget                 : unsigned(4 downto 0) := (others => '0');
   signal resultData                   : unsigned(31 downto 0) := (others => '0');
   signal executeMemReadEnable         : std_logic := '0';
   signal executeLoadType              : CPU_LOADTYPE;
   signal executeLoadAddr              : unsigned(11 downto 0);
   signal executeReadRSPReg            : std_logic := '0';
   signal executeReadRDPReg            : std_logic := '0';
   
   signal executeVectorNew             : std_logic := '0';
   signal executeVectorTarget          : unsigned(4 downto 0) := (others => '0');
   signal executeVectorReadEnable      : std_logic := '0';
   signal executeVectorBE              : std_logic_vector(15 downto 0) := (others => '0');
   signal executeVectorReadTarget      : unsigned(4 downto 0) := (others => '0');
   signal executeVectorWritebackEna    : std_logic_vector(7 downto 0);
   type texecuteVectorWritebackData is array(0 to 7) of std_logic_vector(15 downto 0);
   signal executeVectorWritebackData   : texecuteVectorWritebackData;
   signal executeVectorMfcE            : unsigned(3 downto 0) := (others => '0');
   signal executeVectorMTC2            : std_logic := '0';
   signal executeVectorMTC2Data        : std_logic_vector(15 downto 0) := (others => '0');
   
   type t_vec_mux is array(0 to 15) of unsigned(3 downto 0);
   signal executeVectorReadMux : t_vec_mux;
   
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
   
   type tVregs is array(0 to 31, 0 to 7) of unsigned(15 downto 0);
   signal Vregs : tVregs :=  (others => (others => (others => '0')));   
   
   type tAccu is array(0 to 7) of unsigned(47 downto 0);
   signal accu : tAccu :=  (others => (others => '0'));
   
   signal export_vco : unsigned(15 downto 0);
   signal export_vcc : unsigned(15 downto 0);
   signal export_vce : unsigned(7 downto 0);
   
   signal ce_1x_1                      : std_logic := '0';
   signal writeDoneNew                 : std_logic := '0';
-- synthesis translate_on
   
begin 

   -- common
   stall        <= stall3 & stall2;

--##############################################################
--############################### register file
--##############################################################
   iregisterfile1 : entity mem.RamMLAB
	GENERIC MAP 
   (
      width      => 32,
      widthad    => 5
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
      width      => 32,
      widthad    => 5
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
--############################### vector regs
--##############################################################

   gVectorRegs : for i in 0 to 7 generate
   begin
      iregisterfile1_hi : entity mem.RamMLAB
      GENERIC MAP 
      (
         width      => 8,
         widthad    => 5
      )
      PORT MAP (
         inclock    => clk1x,
         wren       => vec_writeEna((i * 2) + 1),
         data       => vec_data_a((i * 2) + 1),
         wraddress  => vec_addr_a(i),
         rdaddress  => vec_addr_b_1(i),
         q          => vec_data_b_1((i * 2) + 1)
      );
      
      iregisterfile1_lo : entity mem.RamMLAB
      GENERIC MAP 
      (
         width      => 8,
         widthad    => 5
      )
      PORT MAP (
         inclock    => clk1x,
         wren       => vec_writeEna(i * 2),
         data       => vec_data_a(i * 2),
         wraddress  => vec_addr_a(i),
         rdaddress  => vec_addr_b_1(i),
         q          => vec_data_b_1(i * 2)
      );
      
      iregisterfile2_hi : entity mem.RamMLAB
      GENERIC MAP 
      (
         width      => 8,
         widthad    => 5
      )
      PORT MAP (
         inclock    => clk1x,
         wren       => vec_writeEna((i * 2) + 1),
         data       => vec_data_a((i * 2) + 1),
         wraddress  => vec_addr_a(i),
         rdaddress  => vec_addr_b_2(i),
         q          => vec_data_b_2((i * 2) + 1)
      );
      
      iregisterfile2_lo : entity mem.RamMLAB
      GENERIC MAP 
      (
         width      => 8,
         widthad    => 5
      )
      PORT MAP (
         inclock    => clk1x,
         wren       => vec_writeEna(i * 2),
         data       => vec_data_a(i * 2),
         wraddress  => vec_addr_a(i),
         rdaddress  => vec_addr_b_2(i),
         q          => vec_data_b_2(i * 2)
      );
      
   end generate;
   
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
                       
   decImmData       <= opcodeCacheMuxed(15 downto 0);
   decJumpTarget    <= opcodeCacheMuxed(25 downto 0);
   decSource1       <= opcodeCacheMuxed(25 downto 21);
   decSource2       <= opcodeCacheMuxed(20 downto 16);
   decOP            <= opcodeCacheMuxed(31 downto 26);
   decFunct         <= opcodeCacheMuxed(5 downto 0);
   decShamt         <= opcodeCacheMuxed(10 downto 6);
   decRD            <= opcodeCacheMuxed(15 downto 11);
   decTarget        <= opcodeCacheMuxed(20 downto 16) when (opcodeCacheMuxed(31 downto 26) > 0) else opcodeCacheMuxed(15 downto 11);                  
   decVectorElement <= opcodeCacheMuxed(24 downto 21);
   decVectorDestEle <= opcodeCacheMuxed(13 downto 11);
   decVectorMfcE    <= opcodeCacheMuxed(10 downto 7);

   -- fetch vector
   process (all)
   begin
   
      for i in 0 to 7 loop
         
         vec_addr_b_1(i) <= std_logic_vector(opcodeCacheMuxed(15 downto 11));
         vec_addr_b_2(i) <= std_logic_vector(opcodeCacheMuxed(20 downto 16));
      
      end loop;
   
   end process;
   

   process (clk1x)
      variable decVectorUpdate : std_logic := '0';
   begin
      if (rising_edge(clk1x)) then
      
         error_instr     <= '0';
         decVectorUpdate := '0';
         
         if (stall3 = '0') then
            decodeNew       <= '0';
            decodeVectorNew <= '0';
            decode_set_vco  <= '0';
            decode_set_vcc  <= '0';
            decode_set_vce  <= '0';
         end if;
      
         if (ce_1x = '0') then
         
            stall2           <= '0';
            decodeBranchType <= BRANCH_OFF;
            
         else
         
            if (stall2 = '1') then
               if (decodeStallcount > 0) then
                  decodeStallcount <= decodeStallcount - 1;
               else
                  decVectorUpdate := '1';
                  stall2          <= '0';
               end if;
            end if;
         
            if (stall = 0) then
            
               if (fetchNew = '1') then
               
                  decodeNew            <= '1'; 
                  decVectorUpdate      := '1';
                     
-- synthesis translate_off    
                  pcOld1               <= PC;
                  opcode1              <= opcodeCacheMuxed;
-- synthesis translate_on     
                                          
                  decodeImmData        <= decImmData;   
                  decodeJumpTarget     <= decJumpTarget;
                  decodeSource1        <= decSource1;
                  decodeSource2        <= decSource2; 
                  decodeShamt          <= decShamt;          
                  decodeRD             <= decRd;          
                  decodeTarget         <= decTarget;   
                  decodeRegAddr        <= decRD & "00";
                  
                  decodeVectorElement  <= decVectorElement;
                  decodeVectorDestEle  <= decVectorDestEle;
                  decodeVectorMfcE     <= decVectorMfcE;
                  
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
                  decodeWriteEnable       <= '0';
                  decode_break            <= '0';
                  decodeReadEnable        <= '0';
                  decodeSaveType          <= SAVETYPE_NONE;
                  decodeReadRSPReg        <= '0';
                  decodeReadRDPReg        <= '0';
                  decodeWriteRSPReg       <= '0';
                  decodeWriteRDPReg       <= '0';
                          
                  decodeMemOffset         <= signed(decImmData);
                  decodeVectorReadEnable  <= '0';
                  decodeVectorAddrWrap    <= '0';
                  decodeVectorWriteEnable <= '0';
                  decodeVectorMTC2        <= '0';
                  decode_set_vco          <= '0';
                  decode_set_vcc          <= '0';
                  decode_set_vce          <= '0';
                      
                  -- decoding opcode specific
                  case (to_integer(decOP)) is
         
                     when 16#00# =>
                        case (to_integer(decFunct)) is
                        
                           when 16#00# => -- SLL
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= '0';
                              decodeWriteEnable       <= '1';
                              
                           when 16#02# => -- SRL
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= '0';
                              decodeWriteEnable       <= '1';
                           
                           when 16#03# => -- SRA
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT; 
                              decodeShiftSigned       <= '1';
                              decodeShiftAmountType   <= '0';
                              decodeWriteEnable       <= '1';
                              
                           when 16#04# => -- SLLV
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= '1';
                              decodeWriteEnable       <= '1';
                              
                           when 16#06# => -- SRLV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= '1';
                              decodeWriteEnable       <= '1';
                           
                           when 16#07# => -- SRAV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftSigned       <= '1';
                              decodeShiftAmountType   <= '1';
                              decodeWriteEnable       <= '1';
                              
                           when 16#08# => -- JR
                              decodeBranchType        <= BRANCH_ALWAYS_REG;
                              
                           when 16#09# => -- JALR
                              decodeResultMux         <= RESULTMUX_PC;
                              decodeTarget            <= decRD;
                              decodeBranchType        <= BRANCH_ALWAYS_REG;
                              decodeWriteEnable       <= '1';
                              
                           when 16#0D# => -- break
                              decode_break            <= '1';
                           
                           when 16#20#| 16#21# => -- ADD/ADDU
                              decodeResultMux         <= RESULTMUX_ADD;
                              decodeWriteEnable       <= '1';
                              
                           when 16#22# | 16#23# => -- SUB/SUBU
                              decodeResultMux         <= RESULTMUX_SUB;
                              decodeWriteEnable       <= '1';
                           
                           when 16#24# => -- AND
                              decodeResultMux         <= RESULTMUX_AND;
                              decodeWriteEnable       <= '1';
                           
                           when 16#25# => -- OR
                              decodeResultMux         <= RESULTMUX_OR;
                              decodeWriteEnable       <= '1';
                              
                           when 16#26# => -- XOR
                              decodeResultMux         <= RESULTMUX_XOR;
                              decodeWriteEnable       <= '1';
                              
                           when 16#27# => -- NOR
                              decodeResultMux         <= RESULTMUX_NOR;
                              decodeWriteEnable       <= '1';
                              
                           when 16#2A# => -- SLT
                              decodeResultMux         <= RESULTMUX_BIT;
                              decodeBitFuncType       <= BITFUNC_SIGNED;
                              decodeWriteEnable       <= '1';
                           
                           when 16#2B# => -- SLTU
                              decodeResultMux         <= RESULTMUX_BIT;
                              decodeBitFuncType       <= BITFUNC_UNSIGNED;
                              decodeWriteEnable       <= '1';

                           when others =>
                              -- synthesis translate_off
                              report to_hstring(decFunct);
                              -- synthesis translate_on
                              --report "Unknown extended opcode" severity failure; 
                              error_instr  <= '1';
                        end case;
  
                     when 16#01# => -- B: BLTZ, BGEZ
                        if (decSource2(4 downto 1) = "1000") then 
                           decodeResultMux      <= RESULTMUX_PC;
                           decodeTarget         <= to_unsigned(31, 5);
                           decodeWriteEnable    <= '1';
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
                        decodeWriteEnable       <= '1';
                        
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
                        decodeWriteEnable       <= '1';
                        
                     when 16#0A# => -- SLTI
                        decodeResultMux         <= RESULTMUX_BIT;
                        decodeBitFuncType       <= BITFUNC_IMM_SIGNED;   
                        decodeWriteEnable       <= '1';
                        
                     when 16#0B# => -- SLTIU
                        decodeResultMux         <= RESULTMUX_BIT;
                        decodeBitFuncType       <= BITFUNC_IMM_UNSIGNED; 
                        decodeWriteEnable       <= '1';
                        
                     when 16#0C# => -- ANDI
                        decodeResultMux         <= RESULTMUX_AND;
                        decodeUseImmidateValue2 <= '1';
                        decodeWriteEnable       <= '1';
                        
                     when 16#0D# => -- ORI
                        decodeResultMux         <= RESULTMUX_OR;
                        decodeUseImmidateValue2 <= '1';
                        decodeWriteEnable       <= '1';
                        
                     when 16#0E# => -- XORI
                        decodeResultMux         <= RESULTMUX_XOR;
                        decodeUseImmidateValue2 <= '1';
                        decodeWriteEnable       <= '1';
                        
                     when 16#0F# => -- LUI
                        decodeResultMux         <= RESULTMUX_LUI;
                        decodeWriteEnable       <= '1';
                        
                     when 16#10# => -- COP0
                        if (decSource1 = 0) then
                           if (decRD(3) = '1') then
                              decodeReadRDPReg <= '1';
                           else
                              decodeReadRSPReg <= '1';
                           end if;
                        elsif (decSource1 = 4) then
                           if (decRD(3) = '1') then
                              decodeWriteRDPReg <= '1';
                           else
                              decodeWriteRSPReg <= '1';
                           end if;
                        end if;
                        
                     when 16#12# => -- COP2/vector
                        if (decSource1(4) = '0') then 
                           case (decSource1(3 downto 0)) is
                              
                              when x"0" => --mfc2
                                 decodeWriteEnable    <= '1';
                                 decodeResultMux      <= RESULTMUX_VECTOR;
                              
                              when x"2" => --cfc2
                                 decodeWriteEnable       <= '1';
                                 case (decRd(1 downto 0)) is
                                    when "00"   => decodeResultMux <= RESULTMUX_VCO;
                                    when "01"   => decodeResultMux <= RESULTMUX_VCC;
                                    when others => decodeResultMux <= RESULTMUX_VCE;
                                 end case;
                              
                              when x"4" => --mtc2
                                 decodeVectorMTC2 <= '1';
                                 stall2           <= '1';
                                 decodeStallcount <= 2;
                              
                              when x"6" => --ctc2
                                 case (decRd(1 downto 0)) is
                                    when "00"   => decode_set_vco <= '1';
                                    when "01"   => decode_set_vcc <= '1';
                                    when others => decode_set_vce <= '1';
                                 end case;
                              
                              when others =>
                                 -- synthesis translate_off
                                 report to_hstring(decOP);
                                 -- synthesis translate_on
                                 error_instr  <= '1';    
                              
                           end case;
                        else 
                        
                           decodeVectorNew  <= '1';
                           stall2           <= '1';
                           decodeStallcount <= 2;
                        
                           case (to_integer(decFunct)) is

                              when 16#13# => decodeVectorCalcType <= VCALC_VABS; -- VABS
                              
                              when 16#1D# => decodeVectorCalcType <= VCALC_VSAR; -- VSAR
                              
                              when 16#33# => decodeVectorCalcType <= VCALC_VMOV; -- VMOV 

                              when others =>
                                 -- synthesis translate_off
                                 report to_hstring(decOP);
                                 -- synthesis translate_on
                                 error_instr  <= '1'; 

                           end case;
                        
                        end if;

                     when 16#20# => -- LB
                        decodeLoadType       <= LOADTYPE_SBYTE;
                        decodeReadEnable     <= '1';
                        
                     when 16#21# => -- LH
                        decodeLoadType       <= LOADTYPE_SWORD;
                        decodeReadEnable     <= '1';
                        
                     when 16#23# | 16#27# => -- LW / LWU
                        decodeLoadType       <= LOADTYPE_DWORD;
                        decodeReadEnable     <= '1';
         
                     when 16#24# => -- LBU
                        decodeLoadType       <= LOADTYPE_BYTE;
                        decodeReadEnable     <= '1';
         
                     when 16#25# => -- LHU
                        decodeLoadType       <= LOADTYPE_WORD;
                        decodeReadEnable     <= '1';
                     
                     when 16#28# => -- SB
                        decodeSaveType       <= SAVETYPE_BYTE;
                     
                     when 16#29# => -- SH
                        decodeSaveType       <= SAVETYPE_WORD;
                        
                     when 16#2B# => -- SW
                        decodeSaveType       <= SAVETYPE_DWORD;
                     
                     when 16#32# => -- LWC2
                        stall2           <= '1';
                        decodeStallcount <= 2;
                     
                        case (to_integer(decRD)) is
                        
                           when 16#00# =>
                              decodeVectorLoadType    <= VECTORLOADTYPE_LBV;
                              decodeVectorReadEnable  <= '1';
                              decodeMemOffset         <= resize(signed(decImmData(6 downto 0)), 16);
                              decodeVectorShiftEnable <= x"0001";  
                              
                           when 16#01# =>
                              decodeVectorLoadType    <= VECTORLOADTYPE_LSV;
                              decodeVectorReadEnable  <= '1';
                              decodeMemOffset         <= resize(signed(decImmData(6 downto 0)) & "0", 16);
                              decodeVectorShiftEnable <= x"0003";  
                              
                           when 16#02# =>
                              decodeVectorLoadType    <= VECTORLOADTYPE_LLV;
                              decodeVectorReadEnable  <= '1';
                              decodeMemOffset         <= resize(signed(decImmData(6 downto 0)) & "00", 16);
                              decodeVectorShiftEnable <= x"000F";  
                        
                           when 16#03# =>
                              decodeVectorLoadType    <= VECTORLOADTYPE_LDV;
                              decodeVectorReadEnable  <= '1';
                              decodeMemOffset         <= resize(signed(decImmData(6 downto 0)) & "000", 16);
                              decodeVectorShiftEnable <= x"00FF";                           
                              
                           when 16#04# =>
                              decodeVectorLoadType    <= VECTORLOADTYPE_LQV;
                              decodeVectorReadEnable  <= '1';
                              decodeMemOffset         <= resize(signed(decImmData(6 downto 0)) & "0000", 16);
                              decodeVectorAddrWrap    <= '1';
                              decodeVectorShiftEnable <= x"FFFF";
                        
                           when others =>
                              -- synthesis translate_off
                              report to_hstring(decOP);
                              -- synthesis translate_on
                              error_instr  <= '1';    
                           
                        end case;
                     
                     when 16#3A# => -- SWC2
                        case (to_integer(decRD)) is
                        
                           when 16#04# =>
                              decodeVectorWriteEnable <= '1';
                              decodeVectorAddrWrap    <= '1';
                              decodeMemOffset         <= resize(signed(decImmData(6 downto 0)) & "0000", 16);
                        
                           when others =>
                              -- synthesis translate_off
                              report to_hstring(decOP);
                              -- synthesis translate_on
                              error_instr  <= '1';    
                           
                        end case;
                          
                     when others =>
                        -- synthesis translate_off
                        report to_hstring(decOP);
                        -- synthesis translate_on
                        --report "Unknown opcode" severity failure; 
                        error_instr  <= '1';                     
                     
                  end case;
                  
               end if; -- fetchReady
      
            else
               
               -- operand forwarding in stall
               if (decodeSource1 > 0 and writebackTarget = decodeSource1 and writebackWriteEnable = '1') then decodeValue1 <= writebackData; end if;
               if (decodeSource2 > 0 and writebackTarget = decodeSource2 and writebackWriteEnable = '1') then decodeValue2 <= writebackData; end if;
      
            end if; -- stall
            
            -- vector operand fetching
            if (decVectorUpdate = '1') then
               for i in 0 to 15 loop
                  decodeVectorValue1(i) <= vec_data_b_1(i);
                  decodeVectorValue2(i) <= vec_data_b_2(i);
               end loop;
            end if;

         end if; -- ce
         
         if (break_out = '1') then
            decodeNew       <= '0';
            decodeVectorNew <= '0';
         end if;
         
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
   
   calcMemAddr        <= value1 + unsigned(resize(decodeMemOffset, 32));
   
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
   PCnextBranch <= ("000000" & PC) + (decodeImmData & "00");
   
   cmpEqual    <= '1' when (value1 = value2) else '0';
   cmpNegative <= value1(31);
   cmpZero     <= '1' when (value1 = 0) else '0';
   
   FetchAddr   <= PC                                  when (fetchNew = '0' or stall > 0) else
                  PCnext                              when (decodeNew = '0') else
                  value1(11 downto 0)                 when (decodeBranchType = BRANCH_ALWAYS_REG) else
                  decodeJumpTarget(9 downto 0) & "00" when (decodeBranchType = BRANCH_JUMPIMM) else
                  PCnextBranch(11 downto 0)           when (decodeBranchType = BRANCH_BRANCH_BGEZ and (cmpZero = '1' or cmpNegative = '0'))  else
                  PCnextBranch(11 downto 0)           when (decodeBranchType = BRANCH_BRANCH_BLTZ and cmpNegative = '1')                     else
                  PCnextBranch(11 downto 0)           when (decodeBranchType = BRANCH_BRANCH_BEQ  and cmpEqual = '1')                        else
                  PCnextBranch(11 downto 0)           when (decodeBranchType = BRANCH_BRANCH_BNE  and cmpEqual = '0')                        else
                  PCnextBranch(11 downto 0)           when (decodeBranchType = BRANCH_BRANCH_BLEZ and (cmpZero = '1' or cmpNegative = '1'))  else
                  PCnextBranch(11 downto 0)           when (decodeBranchType = BRANCH_BRANCH_BGTZ and (cmpZero = '0' and cmpNegative = '0')) else
                  PCnext;     
  
   ---------------------- MFC2 muxing ------------------
   
   MFC2_value <= decodeVectorValue1(14) & decodeVectorValue1(1) when (decodeVectorMfcE = x"F") else
                 decodeVectorValue1(to_integer(decodeVectorMfcE) - 1) & decodeVectorValue1(to_integer(decodeVectorMfcE) + 2) when (decodeVectorMfcE(0) = '1') else 
                 decodeVectorValue1(to_integer(decodeVectorMfcE) + 1) & decodeVectorValue1(to_integer(decodeVectorMfcE));
 
   ---------------------- result muxing ------------------
   resultDataMuxed <= calcResult_shiftL                  when (decodeResultMux = RESULTMUX_SHIFTLEFT)  else
                      calcResult_shiftR                  when (decodeResultMux = RESULTMUX_SHIFTRIGHT) else
                      calcResult_add                     when (decodeResultMux = RESULTMUX_ADD)        else
                      20x"0" & PCnext                    when (decodeResultMux = RESULTMUX_PC)         else
                      calcResult_sub                     when (decodeResultMux = RESULTMUX_SUB)        else
                      calcResult_and                     when (decodeResultMux = RESULTMUX_AND)        else
                      calcResult_or                      when (decodeResultMux = RESULTMUX_OR )        else
                      calcResult_xor                     when (decodeResultMux = RESULTMUX_XOR)        else
                      calcResult_nor                     when (decodeResultMux = RESULTMUX_NOR)        else
                      calcResult_bit                     when (decodeResultMux = RESULTMUX_BIT)        else
                      unsigned(resize(signed(vco), 32))  when (decodeResultMux = RESULTMUX_VCO)        else
                      unsigned(resize(signed(vcc), 32))  when (decodeResultMux = RESULTMUX_VCC)        else
                      24x"0" & vce                       when (decodeResultMux = RESULTMUX_VCE)        else
                      unsigned(resize(signed(MFC2_value), 32))  when (decodeResultMux = RESULTMUX_VECTOR)     else
                      unsigned(resize(signed(decodeImmData) & x"0000", 32)); -- (decodeResultMux = RESULTMUX_LUI);  
   
   reg_addr      <= decodeRegAddr;
   reg_dataWrite <= value2;

   process (all)
      type trotatedData is array(0 to 3) of std_logic_vector(7 downto 0);
      variable rotatedData : trotatedData;
      variable rotateAddrMuxAdd : integer range 0 to 3;
   begin
   
      break_out         <= '0';      
      reg_RSP_read      <= '0';      
      reg_RDP_read      <= '0';      
      reg_RSP_write     <= '0';      
      reg_RDP_write     <= '0';      
      
      -- DMEM muxing 
      rotateAddrMuxAdd := 0;
      if (decodeSaveType = SAVETYPE_BYTE) then -- SB
         case (calcMemAddr(1 downto 0)) is
            when "00" => rotateAddrMuxAdd := 3;
            when "01" => rotateAddrMuxAdd := 2;
            when "10" => rotateAddrMuxAdd := 1;
            when "11" => rotateAddrMuxAdd := 0;
            when others => null;
         end case;
      elsif (decodeSaveType = SAVETYPE_WORD) then -- SH
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
      
      if (decodeVectorAddrWrap = '1') then
         for i in 0 to 15 loop
            dmem_addr(i)      <= std_logic_vector(calcMemAddr(11 downto 4));
         end loop;
      else
         for i in 0 to 15 loop
            if (calcMemAddr(3 downto 0) > i) then
               dmem_addr(i)      <= std_logic_vector(calcMemAddr(11 downto 4) + 1);
            else
               dmem_addr(i)      <= std_logic_vector(calcMemAddr(11 downto 4));
            end if;
         end loop;
      end if;

      dmem_WriteEnable <= (others => '0'); 
      if (decodeVectorWriteEnable = '1') then
      
         for i in 0 to 15 loop
            dmem_WriteEnable  <= (others => '1');  
         end loop;
         
         for i in 0 to 7 loop
            dmem_dataWrite((i * 2) + 0) <= decodeVectorValue2((i * 2) + 1);
            dmem_dataWrite((i * 2) + 1) <= decodeVectorValue2((i * 2) + 0);
         end loop;
      
      else
      
         for i in 0 to 15 loop
            dmem_dataWrite(i) <= rotatedData((i + rotateAddrMuxAdd) mod 4);
         end loop;
      
      end if;
      
      if (stall = 0 and decodeNew = '1') then
      
         break_out     <= decode_break;
         
         reg_RSP_read  <= decodeReadRSPReg; 
         reg_RDP_read  <= decodeReadRDPReg; 
         reg_RSP_write <= decodeWriteRSPReg;
         reg_RDP_write <= decodeWriteRDPReg;
             
         case (decodeSaveType) is
            when SAVETYPE_BYTE =>
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0))) <= '1';
            when SAVETYPE_WORD => 
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 0)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 1)) <= '1';
            when SAVETYPE_DWORD =>
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 0)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 1)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 2)) <= '1';
               dmem_WriteEnable(to_integer(calcMemAddr(3 downto 0) + 3)) <= '1';
            when others => null;
         end case;
             
      end if;
      
   end process;
   
   
   process (clk1x)
      variable vectorAddrEleAdd : unsigned(3 downto 0);
   begin
      if (rising_edge(clk1x)) then
      
         executeNew        <= '0';
         executeVectorNew  <= '0';
      
         if (ce_1x = '0') then
         
            stall3                        <= '0';
            
            executeStallFromMEM           <= '0';
            resultWriteEnable             <= '0';
            
         else
            
            -- load delay block
            if (stall3) then
            
               executeStallFromMEM <= '0';
               if (writebackStallFromMEM = '1' and writebackNew = '1') then
                  stall3 <= '0';
               end if;
               
            else

               resultData              <= resultDataMuxed;    
               resultTarget            <= decodeTarget;   

               executeVectorMfcE       <= decodeVectorMfcE; 
               if (decodeVectorMfcE(0) = '1') then
                  executeVectorMTC2Data   <= std_logic_vector(value2(7 downto 0)) & std_logic_vector(value2(15 downto 8));  
               else
                  executeVectorMTC2Data   <= std_logic_vector(value2(15 downto 0));  
               end if;
               
               -- vector load write enable
               case (decodeVectorLoadType) is
               
                  when VECTORLOADTYPE_LBV | VECTORLOADTYPE_LSV | VECTORLOADTYPE_LLV | VECTORLOADTYPE_LDV =>
                     executeVectorBE <= std_logic_vector(decodeVectorShiftEnable sll to_integer(decodeVectorMfcE));
                  
                  when VECTORLOADTYPE_LQV =>
                     executeVectorBE <= std_logic_vector(shift_right(decodeVectorShiftEnable, to_integer(calcMemAddr(3 downto 0))) sll to_integer(decodeVectorMfcE));
             
               end case;
               
               -- vector load mux mapping
               vectorAddrEleAdd := decodeVectorMfcE - calcMemAddr(3 downto 0);
               case (decodeVectorLoadType) is
               
                  when VECTORLOADTYPE_LBV | VECTORLOADTYPE_LSV | VECTORLOADTYPE_LLV | VECTORLOADTYPE_LDV | VECTORLOADTYPE_LQV =>
                     for i in 0 to 15 loop
                        executeVectorReadMux(i) <= to_unsigned(i, 4) - vectorAddrEleAdd;
                     end loop;
                  
               end case;
            
               if (decodeNew = '1') then     
               
                  executeNew           <= '1';
               
-- synthesis translate_off
                  pcOld2                  <= pcOld1;  
                  opcode2                 <= opcode1;
-- synthesis translate_on  
                        
                  -- from calculation
                  if (decodeTarget = 0) then
                     resultWriteEnable    <= '0';
                  else
                     resultWriteEnable    <= decodeWriteEnable;
                  end if;
                        
                  executeLoadType         <= decodeLoadType;   
                  executeMemReadEnable    <= decodeReadEnable; 
                  executeLoadAddr         <= calcMemAddr(11 downto 0); 
                     
                  executeReadRSPReg       <= decodeReadRSPReg;
                  executeReadRDPReg       <= decodeReadRDPReg;
                  
                  -- vector unit forward
                  executeVectorReadEnable <= decodeVectorReadEnable;     
                  executeVectorReadTarget <= decodeSource2;
                  
                  -- stalling
                  if (decodeReadEnable = '1' or decodeReadRSPReg = '1' or decodeReadRDPReg = '1') then
                     stall3              <= '1';
                     executeStallFromMEM <= '1';
                  end if;
                  
                  executeVectorMTC2     <= decodeVectorMTC2;
                  if (decodeVectorMTC2 = '1') then
                     executeVectorNew     <= '1';
                     executeVectorTarget  <= decodeRD;
                  end if;
                  
               end if;
               
               if (decodeVectorNew = '1') then
                  executeVectorNew      <= '1';
                  executeVectorTarget  <= decodeShamt;
               end if;
                
            end if; -- stall

         end if; -- ce
         
      end if; -- clock
   end process;
   
   
--##############################################################
--############################### stage 4
--##############################################################

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
      
         writebackWriteEnable <= '0';
         vec_writeEna         <= (others => '0');
      
         if (ce_1x = '0') then
         
            writebackNew                     <= '0';
            writebackStallFromMEM            <= '0';                  
            
         else
            
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
               
               if (executeReadRSPReg = '1') then
                  if (resultTarget > 0) then
                     writebackWriteEnable <= '1';
                  end if;
                  writebackData <= reg_RSP_dataRead;
               end if;
               
               if (executeReadRDPReg = '1') then
                  if (resultTarget > 0) then
                     writebackWriteEnable <= '1';
                  end if;
                  writebackData <= reg_RDP_dataRead;
               end if;
               
               -- vector writeback
               if (executeVectorReadEnable = '1') then
                  
                  vec_writeEna <= executeVectorBE;
               
                  for i in 0 to 7 loop
                     vec_addr_a(i) <= std_logic_vector(executeVectorReadTarget);
                  end loop;
                  
                  for i in 0 to 7 loop
                     vec_writeEna((i * 2) + 1) <= executeVectorBE((i * 2) + 0);
                     vec_writeEna((i * 2) + 0) <= executeVectorBE((i * 2) + 1);
                  
                     vec_data_a((i * 2) + 1) <= dmem_dataRead(to_integer(executeVectorReadMux((i * 2) + 0)));
                     vec_data_a((i * 2) + 0) <= dmem_dataRead(to_integer(executeVectorReadMux((i * 2) + 1)));
                  end loop;
                  
               end if;

            end if; -- executeNew
            
            if (executeVectorNew = '1') then
               
               for i in 0 to 7 loop
                  vec_addr_a(i)             <= std_logic_vector(executeVectorTarget);
                  vec_writeEna((i * 2) + 0) <= executeVectorWritebackEna(i);
                  vec_writeEna((i * 2) + 1) <= executeVectorWritebackEna(i);
                  vec_data_a((i * 2) + 0)   <= executeVectorWritebackData(i)( 7 downto 0);
                  vec_data_a((i * 2) + 1)   <= executeVectorWritebackData(i)(15 downto 8);
               end loop;
               
               if (executeVectorMTC2 = '1') then
                  
                  for i in 0 to 7 loop
                     vec_data_a((i * 2) + 0) <= executeVectorMTC2Data(7 downto 0);
                     vec_data_a((i * 2) + 1) <= executeVectorMTC2Data(15 downto 8);
                  end loop;
               
                  if (executeVectorMfcE(0) = '1') then
                     vec_writeEna(to_integer(executeVectorMfcE) - 1) <= '1';
                     if (executeVectorMfcE < 15) then 
                        vec_writeEna(to_integer(executeVectorMfcE) + 2) <= '1';
                     end if;
                  else
                     vec_writeEna(to_integer(executeVectorMfcE))     <= '1';
                     vec_writeEna(to_integer(executeVectorMfcE) + 1) <= '1';
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
            
            if (writebackNew = '1') then

               writeDoneNew         <= '1';

               pcOld4               <= pcOld3;
               opcode4              <= opcode3;
               
            end if;
             
         end if;
         
         if (writebackWriteEnable = '1') then 
            regs(to_integer(writebackTarget)) <= writebackData;
         end if;
         
         if (vec_writeEna(0 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(0))), 0)( 7 downto 0) <= unsigned(vec_data_a(0 )); end if;
         if (vec_writeEna(1 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(0))), 0)(15 downto 8) <= unsigned(vec_data_a(1 )); end if;
         if (vec_writeEna(2 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(1))), 1)( 7 downto 0) <= unsigned(vec_data_a(2 )); end if;
         if (vec_writeEna(3 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(1))), 1)(15 downto 8) <= unsigned(vec_data_a(3 )); end if;
         if (vec_writeEna(4 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(2))), 2)( 7 downto 0) <= unsigned(vec_data_a(4 )); end if;
         if (vec_writeEna(5 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(2))), 2)(15 downto 8) <= unsigned(vec_data_a(5 )); end if;
         if (vec_writeEna(6 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(3))), 3)( 7 downto 0) <= unsigned(vec_data_a(6 )); end if;
         if (vec_writeEna(7 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(3))), 3)(15 downto 8) <= unsigned(vec_data_a(7 )); end if;
         if (vec_writeEna(8 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(4))), 4)( 7 downto 0) <= unsigned(vec_data_a(8 )); end if;
         if (vec_writeEna(9 ) = '1') then Vregs(to_integer(unsigned(vec_addr_a(4))), 4)(15 downto 8) <= unsigned(vec_data_a(9 )); end if;
         if (vec_writeEna(10) = '1') then Vregs(to_integer(unsigned(vec_addr_a(5))), 5)( 7 downto 0) <= unsigned(vec_data_a(10)); end if;
         if (vec_writeEna(11) = '1') then Vregs(to_integer(unsigned(vec_addr_a(5))), 5)(15 downto 8) <= unsigned(vec_data_a(11)); end if;
         if (vec_writeEna(12) = '1') then Vregs(to_integer(unsigned(vec_addr_a(6))), 6)( 7 downto 0) <= unsigned(vec_data_a(12)); end if;
         if (vec_writeEna(13) = '1') then Vregs(to_integer(unsigned(vec_addr_a(6))), 6)(15 downto 8) <= unsigned(vec_data_a(13)); end if;
         if (vec_writeEna(14) = '1') then Vregs(to_integer(unsigned(vec_addr_a(7))), 7)( 7 downto 0) <= unsigned(vec_data_a(14)); end if;
         if (vec_writeEna(15) = '1') then Vregs(to_integer(unsigned(vec_addr_a(7))), 7)(15 downto 8) <= unsigned(vec_data_a(15)); end if;
         
-- synthesis translate_on
         
      end if;
   end process;

--##############################################################
--############################### submodules
--##############################################################
   
   gVectorUnits : for i in 0 to 7 generate
   begin
   
      iRSP_vector : entity work.RSP_vector
      generic map
      (
         V_INDEX => i
      )
      port map
      (
         clk1x                 => clk1x,
         
         CalcNew               => decodeVectorNew,
         CalcType              => decodeVectorCalcType,
         VectorValue1          => decodeVectorValue1((i * 2) + 1) & decodeVectorValue1(i * 2),
         VectorValue2          => decodeVectorValue2((i * 2) + 1) & decodeVectorValue2(i * 2),
         element               => decodeVectorElement,
         destElement           => decodeVectorDestEle,
         
         set_vco               => decode_set_vco,
         set_vcc               => decode_set_vcc,
         set_vce               => decode_set_vce,
         vco_in_lo             => value2((i * 2) + 0),
         vco_in_hi             => value2((i * 2) + 1),
         vcc_in_lo             => value2((i * 2) + 0),
         vcc_in_hi             => value2((i * 2) + 1),
         vce_in                => value2(i),
         
         -- synthesis translate_off
         export_accu           => accu(i),
         export_vco_lo         => export_vco((i * 2) + 0),
         export_vco_hi         => export_vco((i * 2) + 1),
         export_vcc_lo         => export_vcc((i * 2) + 0),
         export_vcc_hi         => export_vcc((i * 2) + 1),
         export_vce            => export_vce(i),
         -- synthesis translate_on
         
         writebackEna          => executeVectorWritebackEna(i),
         writebackData         => executeVectorWritebackData(i),
         
         flag_vco_lo           => vco((i * 2) + 0),
         flag_vco_hi           => vco((i * 2) + 1),
         flag_vcc_lo           => vcc((i * 2) + 0),
         flag_vcc_hi           => vcc((i * 2) + 1),
         flag_vce              => vce(i)
      );
   
   end generate;
 
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
      signal Vregs_last       : tVRegs := (others => (others => (others => '0')));
      signal accu_last        : tAccu := (others => (others => '0'));
      signal export_vco_last  : unsigned(15 downto 0) := (others => '0');
      signal export_vcc_last  : unsigned(15 downto 0) := (others => '0');
      signal export_vce_last  : unsigned(7 downto 0) := (others => '0');
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
                  for j in 0 to 7 loop
                     if (vregs(i,j) /= vregs_last(i,j) or firstExport = '1') then
                        write(line_out, string'("V"));
                        if (i < 10) then 
                           write(line_out, string'("0"));
                        end if;
                        write(line_out, to_string(i));
                        write(line_out, string'("|"));
                        write(line_out, to_string(j));
                        write(line_out, string'(" "));
                        write(line_out, to_hstring(Vregs(i,j)) & " ");
                     end if;
                  end loop;
               end loop; 
               regs_last   <= regs;
               Vregs_last  <= Vregs;
               firstExport <= '0';
               
               for j in 0 to 7 loop
                  if (accu(j) /= accu_last(j) or firstExport = '1') then
                     write(line_out, string'("A"));
                     write(line_out, to_string(j));
                     write(line_out, string'(" "));
                     write(line_out, to_hstring(accu(j)) & " ");
                  end if;
               end loop;
               accu_last <= accu;
               
               if (export_vcc /= export_vcc_last or firstExport = '1') then
                  write(line_out, string'("VCC "));
                  write(line_out, to_hstring(export_vcc) & " ");
               end if;
               
               if (export_vco /= export_vco_last or firstExport = '1') then
                  write(line_out, string'("VCO "));
                  write(line_out, to_hstring(export_vco) & " ");
               end if;
               
               if (export_vce /= export_vce_last or firstExport = '1') then
                  write(line_out, string'("VCE "));
                  write(line_out, to_hstring(export_vce) & " ");
               end if;
               
               export_vcc_last <= export_vcc;
               export_vco_last <= export_vco;
               export_vce_last <= export_vce;
               
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





