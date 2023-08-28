library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;   

library mem;
use work.pFunctions.all;
use work.pexport.all;

entity cpu is
   port 
   (
      clk1x                 : in  std_logic;
      clk93                 : in  std_logic;
      clk2x                 : in  std_logic;
      ce_1x                 : in  std_logic;
      ce_93                 : in  std_logic;
      reset_1x              : in  std_logic;
      reset_93              : in  std_logic;
      
      DATACACHEON           : in  std_logic;

      irqRequest            : in  std_logic;
      cpuPaused             : in  std_logic;
      
      error_instr           : out std_logic := '0';
      error_stall           : out std_logic := '0';
      error_FPU             : out std_logic := '0';
      error_exception       : out std_logic := '0';
      
      mem_request           : out std_logic := '0';
      mem_rnw               : out std_logic := '0'; 
      mem_address           : buffer unsigned(31 downto 0) := (others => '0'); 
      mem_req64             : out std_logic := '0'; 
      mem_size              : out unsigned(2 downto 0) := (others => '0');
      mem_writeMask         : out std_logic_vector(7 downto 0) := (others => '0'); 
      mem_dataWrite         : out std_logic_vector(63 downto 0) := (others => '0');
      mem_dataRead          : in  std_logic_vector(63 downto 0); 
      mem_done              : in  std_logic;
      rdram_granted2x       : in  std_logic;
      rdram_done            : in  std_logic;
      ddr3_DOUT             : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY       : in  std_logic;
      
      ram_done              : in  std_logic;
      ram_rnw               : in  std_logic;
      ram_dataRead          : in  std_logic_vector(31 downto 0); 
      
-- synthesis translate_off
      cpu_done              : out std_logic := '0'; 
      cpu_export            : out cpu_export_type := export_init;
-- synthesis translate_on
      
      SS_reset              : in  std_logic;
      SS_DataWrite          : in  std_logic_vector(63 downto 0);
      SS_Adr                : in  unsigned(11 downto 0);
      SS_wren_CPU           : in  std_logic;
      SS_rden_CPU           : in  std_logic;
      SS_DataRead_CPU       : out std_logic_vector(63 downto 0);
      SS_idle               : out std_logic
   );
end entity;

architecture arch of cpu is
     
   -- register file
   signal regs_address_a               : std_logic_vector(4 downto 0);
   signal regs_data_a                  : std_logic_vector(63 downto 0);
   signal regs_wren_a                  : std_logic;
   signal regs1_address_b              : std_logic_vector(4 downto 0);
   signal regs1_q_b                    : std_logic_vector(63 downto 0);
   signal regs2_address_b              : std_logic_vector(4 downto 0);
   signal regs2_q_b                    : std_logic_vector(63 downto 0);  

   -- FPU register file
   signal FPUregs_address_a            : std_logic_vector(4 downto 0);
   signal FPUregs_data_a               : std_logic_vector(63 downto 0);
   signal FPUregs_wren_a               : std_logic_vector(1 downto 0);
   signal FPUregs1_address_b           : std_logic_vector(4 downto 0);
   signal FPUregs1_q_b                 : std_logic_vector(63 downto 0);
   signal FPUregs2_address_b           : std_logic_vector(4 downto 0);
   signal FPUregs2_q_b                 : std_logic_vector(63 downto 0);  

   signal FPUWriteTarget               : unsigned(4 downto 0) := (others => '0');
   signal FPUWriteData                 : unsigned(63 downto 0) := (others => '0');
   signal FPUWriteEnable               : std_logic := '0';   
   signal FPUWriteMask                 : std_logic_vector(1 downto 0) := (others => '0');
   
   -- other register
   signal PC                           : unsigned(63 downto 0) := (others => '0');
   signal hi                           : unsigned(63 downto 0) := (others => '0');
   signal lo                           : unsigned(63 downto 0) := (others => '0');
          
   -- memory interface
   signal memoryMuxStage4              : std_logic := '0';
   signal mem1_request_latched         : std_logic := '0';
   signal mem1_cache_latched           : std_logic := '0';
   signal mem1_address_latched         : unsigned(31 downto 0) := (others => '0'); 
   
   signal mem_done_1                   : std_logic := '0';
   signal mem_finished_instr           : std_logic := '0';
   signal mem_finished_read            : std_logic := '0';
   signal mem_finished_write           : std_logic := '0';
   signal mem_finished_dataRead        : std_logic_vector(63 downto 0);
   signal mem4_request_latched         : std_logic := '0';
   signal mem4_address_latched         : unsigned(31 downto 0) := (others => '0');
   signal mem4_req64_latched           : std_logic := '0';
   signal mem4_rnw_latched             : std_logic := '0';
   signal mem4_data_latched            : std_logic_vector(63 downto 0) := (others => '0');  
   signal mem4_mask_latched            : std_logic_vector(7 downto 0) := (others => '0');  
   signal mem4_cache_latched           : std_logic := '0';
          
   -- common   
   type t_memstate is
   (
      MEMSTATE_IDLE,
      MEMSTATE_BUSY1,
      MEMSTATE_BUSY4
   );
   signal memstate : t_memstate := MEMSTATE_IDLE;                 
   
   signal stallNew1                    : std_logic := '0';
   signal stallNew2                    : std_logic := '0';
   signal stallNew3                    : std_logic := '0';
   signal stallNew4                    : std_logic := '0';
   signal stallNew5                    : std_logic := '0';
               
   signal stall1                       : std_logic := '0';
   signal stall2                       : std_logic := '0';
   signal stall3                       : std_logic := '0';
   signal stall4                       : std_logic := '0';
   signal stall                        : unsigned(4 downto 0) := (others => '0');
   signal stall4Masked                 : unsigned(4 downto 0) := (others => '0');
                     
   signal exception                    : std_logic;
   signal exceptionNew1                : std_logic := '0';
   signal exceptionNew3                : std_logic := '0';
   signal exceptionFPU                 : std_logic;
   signal exception_COP                : unsigned(1 downto 0);
   
   signal exception_SR                 : unsigned(31 downto 0) := (others => '0');
   signal exception_CAUSE              : unsigned(31 downto 0) := (others => '0');
   signal exception_EPC                : unsigned(31 downto 0) := (others => '0');
   signal exception_JMP                : unsigned(31 downto 0) := (others => '0');
   
   signal exceptionCode                : unsigned(3 downto 0);
   signal exceptionCode_3              : unsigned(3 downto 0);   
   signal exceptionInstr               : unsigned(1 downto 0);
   signal exception_PC                 : unsigned(31 downto 0);
   signal exception_branch             : std_logic;
   signal exception_brslot             : std_logic;
   signal exception_JMPnext            : unsigned(31 downto 0);     
               
   signal opcode0                      : unsigned(31 downto 0) := (others => '0');
   signal opcode1                      : unsigned(31 downto 0) := (others => '0');
-- synthesis translate_off
   signal opcode2                      : unsigned(31 downto 0) := (others => '0');
   signal opcode3                      : unsigned(31 downto 0) := (others => '0');
   signal opcode4                      : unsigned(31 downto 0) := (others => '0');
-- synthesis translate_on  
  
   signal PCold0                       : unsigned(63 downto 0) := (others => '0');
   signal PCold1                       : unsigned(63 downto 0) := (others => '0');
   
-- synthesis translate_off
   signal PCold2                       : unsigned(63 downto 0) := (others => '0');
   signal PCold3                       : unsigned(63 downto 0) := (others => '0');
   signal PCold4                       : unsigned(63 downto 0) := (others => '0');
   
   signal hi_1                         : unsigned(63 downto 0) := (others => '0');
   signal lo_1                         : unsigned(63 downto 0) := (others => '0');
   signal hi_2                         : unsigned(63 downto 0) := (others => '0');
   signal lo_2                         : unsigned(63 downto 0) := (others => '0');
-- synthesis translate_on
   
   signal value1                       : unsigned(63 downto 0) := (others => '0');
   signal value2                       : unsigned(63 downto 0) := (others => '0');
               
   -- stage 1          
   -- cache
   signal FetchAddr                    : unsigned(63 downto 0) := (others => '0'); 
   signal FetchAddr1                   : unsigned(63 downto 0) := (others => '0'); 
   signal FetchAddr2                   : unsigned(63 downto 0) := (others => '0'); 
   signal FetchAddrSelect              : std_logic;
   signal fetchCache                   : std_logic;
   signal useCached_data               : std_logic := '0';
   
   signal instrcache_request           : std_logic;
   signal instrcache_active            : std_logic := '0';
   signal instrcache_hit               : std_logic;
   signal instrcache_data              : std_logic_vector(31 downto 0);
   signal instrcache_fill              : std_logic := '0';
   signal instrcache_fill_done         : std_logic;
   signal cache_commandEnable          : std_logic;
   
   signal cacheHitLast                 : std_logic := '0';
   
   -- regs           
   signal fetchReady                   : std_logic := '0';
   
   -- wires   
   signal mem1_request                 : std_logic := '0';
   signal mem1_cacherequest            : std_logic := '0';
   signal mem1_address                 : unsigned(31 downto 0) := (others => '0'); 
   
   signal blockIRQNext                 : std_logic := '0';
   signal blockIRQCntNext              : integer range 0 to 10;
            
   -- stage 2           
   --regs      
   signal decodeNew                    : std_logic := '0';
   signal decode_irq                   : std_logic := '0';
   signal blockIRQ                     : std_logic := '0';
   signal decodeImmData                : unsigned(15 downto 0) := (others => '0');
   signal decodeSource1                : unsigned(4 downto 0) := (others => '0');
   signal decodeSource2                : unsigned(4 downto 0) := (others => '0');
   signal decodeValue1                 : unsigned(63 downto 0) := (others => '0');
   signal decodeValue2                 : unsigned(63 downto 0) := (others => '0');
   signal decodeOP                     : unsigned(5 downto 0) := (others => '0');
   signal decodeFunct                  : unsigned(5 downto 0) := (others => '0');
   signal decodeShamt                  : unsigned(5 downto 0) := (others => '0');
   signal decodeRD                     : unsigned(4 downto 0) := (others => '0');
   signal decodeTarget                 : unsigned(4 downto 0) := (others => '0');
   signal decodeJumpTarget             : unsigned(25 downto 0) := (others => '0');
   signal decodeForwardValue1          : std_logic := '0';
   signal decodeForwardValue2          : std_logic := '0';
   signal decodeUseImmidateValue2      : std_logic := '0';
   signal decodeShiftSigned            : std_logic := '0';
   signal decodeShift32                : std_logic := '0';
   signal decodeShiftAmountType        : std_logic_vector(1 downto 0) := "00";
   signal decodeFPUSource1             : unsigned(4 downto 0) := (others => '0');
   signal decodeFPUSource2             : unsigned(4 downto 0) := (others => '0');
   signal decodeFPUValue1              : unsigned(63 downto 0) := (others => '0');
   signal decodeFPUValue2              : unsigned(63 downto 0) := (others => '0');
   signal decodeFPUForwardUse          : std_logic := '0';
   signal decodeFPUTarget              : unsigned(4 downto 0) := (others => '0');
   signal decodeFPUCommandEnable       : std_logic := '0';
   signal decodeFPUTransferEnable      : std_logic := '0';
   signal decodeFPUTransferWrite       : std_logic := '0';
   signal decodeFPUMULS                : std_logic := '0';
   signal decodeFPUMULD                : std_logic := '0';
   
   type t_decodeBitFuncType is
   (
      BITFUNC_SIGNED,
      BITFUNC_UNSIGNED,
      BITFUNC_IMM_SIGNED,
      BITFUNC_IMM_UNSIGNED,
      BITFUNC_SC
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
      BRANCH_BRANCH_BGTZ,
      BRANCH_BC1,
      BRANCH_ERET
   );
   signal decodeBranchType    : t_decodeBranchType;   
   signal decodeBranchLikely  : std_logic;

   type t_decodeResultMux is
   (
      RESULTMUX_SHIFTLEFT, 
      RESULTMUX_SHIFTRIGHT,
      RESULTMUX_ADD,       
      RESULTMUX_PC,        
      RESULTMUX_HI,        
      RESULTMUX_LO,        
      RESULTMUX_SUB,       
      RESULTMUX_AND,       
      RESULTMUX_OR,        
      RESULTMUX_XOR,       
      RESULTMUX_NOR,       
      RESULTMUX_BIT,
      RESULTMUX_FPU,      
      RESULTMUX_LUI
   );
   signal decodeResultMux : t_decodeResultMux;   
   signal decodeResult32               : std_logic := '0';
   
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
   signal decFPUSource1                : unsigned(4 downto 0);
   signal decFPUSource2                : unsigned(4 downto 0);
   signal decRequiresFPUreg1           : std_logic; 
   signal decRequiresFPUreg2           : std_logic;
   signal decFPUForwardUse             : std_logic;
            
   -- stage 3   
   signal value2_muxedSigned           : unsigned(63 downto 0);
   signal value2_muxedLogical          : unsigned(63 downto 0);
   signal calcResult_add               : unsigned(63 downto 0);
   signal calcResult_sub               : unsigned(63 downto 0);
   signal calcResult_and               : unsigned(63 downto 0);
   signal calcResult_or                : unsigned(63 downto 0);
   signal calcResult_xor               : unsigned(63 downto 0);
   signal calcResult_nor               : unsigned(63 downto 0);
   signal calcMemAddr                  : unsigned(63 downto 0);
   
   signal calcResult_lesserSigned      : std_logic;
   signal calcResult_lesserUnSigned    : std_logic;
   signal calcResult_lesserIMMSigned   : std_logic;
   signal calcResult_lesserIMMUnsigned : std_logic;
   signal calcResult_equal             : std_logic;
   signal calcResult_bit               : unsigned(63 downto 0);
   
   signal executeShamt                 : unsigned(5 downto 0);
   signal shiftValue                   : signed(64 downto 0);
   signal calcResult_shiftL            : unsigned(63 downto 0);
   signal calcResult_shiftR            : unsigned(63 downto 0);
   
   signal cmpEqual                     : std_logic;
   signal cmpNegative                  : std_logic;
   signal cmpZero                      : std_logic;
   signal PCnext                       : unsigned(63 downto 0) := (others => '0');
   signal PCnextBranch                 : unsigned(63 downto 0) := (others => '0');
   
   signal resultDataMuxed              : unsigned(63 downto 0);
   signal resultDataMuxed64            : unsigned(63 downto 0);
   
   type CPU_LOADTYPE is
   (
      LOADTYPE_SBYTE,
      LOADTYPE_SWORD,
      LOADTYPE_LEFT,
      LOADTYPE_DWORD,
      LOADTYPE_DWORDU,
      LOADTYPE_BYTE,
      LOADTYPE_WORD,
      LOADTYPE_RIGHT,
      LOADTYPE_QWORD,
      LOADTYPE_LEFT64,
      LOADTYPE_RIGHT64
   );
   
   --regs         
   signal executeNew                   : std_logic := '0';
   signal executeIgnoreNext            : std_logic := '0';
   signal executeStallFromMEM          : std_logic := '0';
   signal resultWriteEnable            : std_logic := '0';
   signal executeBranchdelaySlot       : std_logic := '0';
   signal resultTarget                 : unsigned(4 downto 0) := (others => '0');
   signal resultData                   : unsigned(63 downto 0) := (others => '0');
   signal executeMem64Bit              : std_logic;
   signal executeMemWriteEnable        : std_logic;
   signal executeMemWriteData          : unsigned(63 downto 0) := (others => '0');
   signal executeMemWriteMask          : std_logic_vector(7 downto 0) := (others => '0');
   signal executeMemAddress            : unsigned(63 downto 0) := (others => '0');
   signal executeMemReadEnable         : std_logic := '0';
   signal executeMemReadLastData       : unsigned(63 downto 0) := (others => '0');
   signal executeCOP0WriteEnable       : std_logic := '0';
   signal executeCOP0ReadEnable        : std_logic := '0';
   signal executeCOP0Read64            : std_logic := '0';
   signal executeCOP0Register          : unsigned(4 downto 0) := (others => '0');
   signal executeCOP0WriteValue        : unsigned(63 downto 0) := (others => '0');
   signal executeCOP2WriteEnable       : std_logic := '0';
   signal executeCOP2ReadEnable        : std_logic := '0';
   signal executeCOP2Read64            : std_logic := '0';
   signal executeLoadType              : CPU_LOADTYPE;
   signal executeCacheEnable           : std_logic := '0';
   signal executeCacheCommand          : unsigned(4 downto 0) := (others => '0');
   signal execute_COP1_Target          : unsigned(4 downto 0) := (others => '0');
   signal executeCOP1ReadEnable        : std_logic := '0';
   signal execute_unstallFPUForward    : std_logic := '0';
   signal execute_ERET                 : std_logic := '0';

   signal hiloWait                     : integer range 0 to 69;
   
   signal llBit                        : std_logic := '0';

   --wires
   signal EXEIgnoreNext                : std_logic := '0';
   signal EXEresultWriteEnable         : std_logic;
   signal EXEBranchdelaySlot           : std_logic := '0';
   signal EXEBranchTaken               : std_logic := '0';
   signal EXEMem64Bit                  : std_logic := '0';
   signal EXEMemWriteEnable            : std_logic := '0';
   signal EXEMemWriteData              : unsigned(63 downto 0) := (others => '0');
   signal EXEMemWriteMask              : std_logic_vector(7 downto 0) := (others => '0');
   signal EXEMemWriteException         : std_logic := '0';
   signal EXECOP0WriteEnable           : std_logic := '0';
   signal EXECOP0ReadEnable            : std_logic := '0';
   signal EXECOP0Read64                : std_logic := '0';
   signal EXECOP0Register              : unsigned(4 downto 0) := (others => '0');
   signal EXECOP0WriteValue            : unsigned(63 downto 0) := (others => '0');
   signal EXECOP2WriteEnable           : std_logic := '0';
   signal EXECOP2ReadEnable            : std_logic := '0';
   signal EXECOP2Read64                : std_logic := '0';
   signal EXELoadType                  : CPU_LOADTYPE;
   signal EXEReadEnable                : std_logic := '0';
   signal EXEReadException             : std_logic := '0';
   signal EXEcalcMULT                  : std_logic := '0';
   signal EXEcalcMULTU                 : std_logic := '0';
   signal EXEcalcDMULT                 : std_logic := '0';
   signal EXEcalcDMULTU                : std_logic := '0';
   signal EXEcalcDIV                   : std_logic := '0';
   signal EXEcalcDIVU                  : std_logic := '0';
   signal EXEcalcDDIV                  : std_logic := '0';
   signal EXEcalcDDIVU                 : std_logic := '0';
   signal EXEhiUpdate                  : std_logic := '0';
   signal EXEloUpdate                  : std_logic := '0';
   signal EXEerror_instr               : std_logic := '0';
   signal EXEllBit                     : std_logic := '0';
   signal EXEERET                      : std_logic := '0';
   signal EXECacheEnable               : std_logic := '0';
   signal EXECacheAddr                 : unsigned(28 downto 0);
   signal ExeCOP1ReadEnable            : std_logic := '0';
   
   --MULT/DIV
   type CPU_HILOCALC is
   (
      HILOCALC_MULT, 
      HILOCALC_MULTU,
      HILOCALC_DMULT,
      HILOCALC_DMULTU,
      HILOCALC_DIV,  
      HILOCALC_DIVU,
      HILOCALC_DDIV,  
      HILOCALC_DDIVU
   );
   signal hilocalc                     : CPU_HILOCALC;
   
   signal mulsign                      : std_logic;
   signal mul1                         : std_logic_vector(63 downto 0);
   signal mul2                         : std_logic_vector(63 downto 0);
   signal mulResult                    : std_logic_vector(127 downto 0);
   
   signal DIVstart                     : std_logic;
   signal DIVis32                      : std_logic;
   signal DIVdividend                  : signed(64 downto 0);
   signal DIVdivisor                   : signed(64 downto 0);
   signal DIVquotient                  : signed(64 downto 0);
   signal DIVremainder                 : signed(64 downto 0);     
         
   -- COP0
   signal eretPC                       : unsigned(63 downto 0) := (others => '0');
   signal exceptionPC                  : unsigned(63 downto 0) := (others => '0');
   signal COP0ReadValue                : unsigned(63 downto 0) := (others => '0');
   
   signal COP1_enable                  : std_logic;
   signal COP2_enable                  : std_logic;
   signal fpuRegMode                   : std_logic;
   signal privilegeMode                : unsigned(1 downto 0);
   signal irqTrigger                   : std_logic;

   -- COP1
   signal cop1_stage4_writeEnable      : std_logic := '0';
   signal cop1_stage4_writeMask        : std_logic_vector(1 downto 0) := (others => '0');
   signal cop1_stage4_data             : unsigned(63 downto 0) := (others => '0');
   signal cop1_stage4_target           : unsigned(4 downto 0) := (others => '0');

   signal FPU_CF                       : std_logic;
   signal FPU_command_ena              : std_logic := '0';
   signal FPU_command_done             : std_logic := '0';
   signal FPU_TransferEna              : std_logic := '0';
   signal FPU_TransferData             : unsigned(63 downto 0);

   -- COP2
   signal COP2Latch                    : unsigned(63 downto 0) := (others => '0');

   -- stage 4 
   -- reg      
   signal writebackNew                 : std_logic := '0';
   signal writebackStallFromMEM        : std_logic := '0';
   signal writebackTarget              : unsigned(4 downto 0) := (others => '0');
   signal writebackData                : unsigned(63 downto 0) := (others => '0');
   signal writebackWriteEnable         : std_logic := '0';
   signal writeback_UseCache           : std_logic := '0';
   signal writebackLoadType            : CPU_LOADTYPE;
   signal writebackReadAddress         : unsigned(31 downto 0) := (others => '0');
   signal writebackReadLastData        : unsigned(63 downto 0) := (others => '0');
   signal writeback_COP1_ReadEnable    : std_logic := '0'; 
         
   -- wire     
   signal mem4_request                 : std_logic := '0';
   signal mem4_address                 : unsigned(31 downto 0) := (others => '0');
   signal mem4_req64                   : std_logic := '0';
   signal mem4_rnw                     : std_logic := '0';
   signal mem4_dataWrite               : std_logic_vector(63 downto 0) := (others => '0');    
   signal mem4_writeMask               : std_logic_vector(7 downto 0) := (others => '0');    
   
   signal read4_dataReadData           : unsigned(63 downto 0);
   signal read4_dataReadRot64          : unsigned(63 downto 0);
   signal read4_dataReadRot32          : unsigned(31 downto 0);
   signal read4_Addr                   : unsigned(31 downto 0);
   signal read4_oldData                : unsigned(63 downto 0);
   signal read4_cop1_readEna           : std_logic;
   signal read4_cop1_target            : unsigned(4 downto 0);
   signal read4_useLoadType            : CPU_LOADTYPE;
   signal read4_useTarget              : unsigned(4 downto 0);
   
   -- Cache
   signal DATACACHEON_intern           : std_logic := '0';
   signal datacache_request            : std_logic;
   signal datacache_active             : std_logic := '0';
   signal datacache_reqAddr            : unsigned(31 downto 0);
   signal datacache_readena            : std_logic;
   signal datacache_readdone           : std_logic;
   signal datacache_addr               : unsigned(31 downto 0);   
   signal datacache_data_out           : std_logic_vector(63 downto 0);   
   signal datacache_writeena           : std_logic;
   signal datacache_writedone          : std_logic;
   signal datacache_CmdStall           : std_logic;
   signal datacache_CmdDone            : std_logic;
   
   signal datacache_wb_ena             : std_logic;
   signal datacache_wb_addr            : unsigned(31 downto 0);
   signal datacache_wb_data            : std_logic_vector(63 downto 0);
   
   -- savestates
   type t_ssarray is array(0 to 31) of std_logic_vector(63 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
   signal ss_out : t_ssarray := (others => (others => '0'));  

   signal regsSS_address_b             : std_logic_vector(4 downto 0) := (others => '0');
   signal regsSS_q_b                   : std_logic_vector(63 downto 0);
   signal regsSS_rden                  : std_logic := '0';
   
   signal ss_regs_loading              : std_logic := '0';
   signal ss_regs_load                 : std_logic := '0';
   signal ss_regs_addr                 : unsigned(4 downto 0);
   signal ss_regs_data                 : std_logic_vector(63 downto 0);   
   
   signal ss_FPUregs_load              : std_logic := '0';
   signal ss_FPUregs_addr              : unsigned(4 downto 0);
   signal ss_FPUregs_data              : std_logic_vector(63 downto 0);   
   
   -- debug
   signal debugCnt                     : unsigned(31 downto 0);
   signal debugSum                     : unsigned(31 downto 0);
   signal debugTmr                     : unsigned(31 downto 0);
   signal debugwrite                   : std_logic := '0';
   
-- synthesis translate_off
   signal stallcountNo                 : integer;
   signal stallcount1                  : integer;
   signal stallcount3                  : integer;
   signal stallcount4                  : integer;
   signal stallcountDMA                : integer;
-- synthesis translate_on
   
   signal debugStallcounter            : unsigned(12 downto 0);
   
   -- export
-- synthesis translate_off
   type tRegs is array(0 to 31) of unsigned(63 downto 0);
   signal regs                         : tRegs := (others => (others => '0'));
   signal FPUregs                      : tRegs := (others => (others => '0'));
   
   signal cop0_export                  : tExportRegs := (others => (others => '0'));
   signal cop0_export_1                : tExportRegs := (others => (others => '0'));
   signal csr_export                   : unsigned(24 downto 0) := (others => '0');
   signal csr_export_1                 : unsigned(24 downto 0) := (others => '0');
   signal csr_export_2                 : unsigned(24 downto 0) := (others => '0');
-- synthesis translate_on
   
begin 

   -- common
   stall        <= '0' & stall4 & stall3 & stall2 & stall1;
   
   process (clk93)
   begin
      if (rising_edge(clk93)) then
         if (reset_93 = '1') then
         
            mem1_request_latched  <= '0';
            mem4_request_latched  <= '0';
         
         else
            
            if (mem1_request = '1' or instrcache_request = '1') then
               mem1_request_latched <= '1';
               mem1_address_latched <= mem1_address;
               mem1_cache_latched   <= instrcache_request;
            end if;            
            
            if (mem4_request = '1' or datacache_request = '1') then
               mem4_request_latched <= '1';
               mem4_address_latched <= mem4_address;
               mem4_req64_latched   <= mem4_req64;
               mem4_rnw_latched     <= mem4_rnw;
               mem4_data_latched    <= mem4_dataWrite;
               mem4_mask_latched    <= mem4_writeMask;
               mem4_cache_latched   <= datacache_request;
               if (datacache_request = '1') then
                  mem4_address_latched <= datacache_reqAddr(31 downto 4) & "0000";
                  mem4_rnw_latched     <= '1';
               end if;
            end if;
            
            if (datacache_wb_ena = '1') then
               mem4_request_latched <= '1';
               mem4_address_latched <= datacache_wb_addr;
               mem4_req64_latched   <= '1';
               mem4_rnw_latched     <= '0';
               mem4_data_latched    <= datacache_wb_data;
               mem4_mask_latched    <= x"FF";
               mem4_cache_latched   <= '0';
            end if;
            
            if (mem_request = '1') then
               if (memoryMuxStage4) then 
                  mem4_request_latched <= '0';
               else
                  mem1_request_latched <= '0';
               end if;
            end if;
            
            mem_finished_dataRead <= mem_dataRead;
            mem_finished_instr    <= '0';
            mem_finished_read     <= '0';
            mem_finished_write    <= '0';
            mem_done_1            <= mem_done;
            if (mem_done = '1' and mem_done_1 = '0') then
               if (memoryMuxStage4 = '1') then
                  if (mem4_rnw_latched = '1') then
                     mem_finished_read <= '1';
                  else
                     mem_finished_write <= '1';
                  end if;
               else
                  mem_finished_instr <= '1';
               end if;
            end if;
            
         end if;
      end if;
   end process;
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
         if (reset_1x = '1') then
         
            memoryMuxStage4       <= '0'; 
            mem_request           <= '0';
            memstate              <= MEMSTATE_IDLE;
         
         else
         
            mem_request <= '0';
            
            case (memstate) is
               when MEMSTATE_IDLE => 
               
                  if (ce_1x = '1') then
                  
                     if (mem4_request_latched = '1') then
                     
                        memstate          <= MEMSTATE_BUSY4;
                        mem_request       <= '1';
                        memoryMuxStage4   <= '1';
                        mem_address       <= mem4_address_latched;
                        mem_rnw           <= mem4_rnw_latched;
                        mem_dataWrite     <= mem4_data_latched;
                        mem_writeMask     <= mem4_mask_latched;
                        mem_req64         <= mem4_req64_latched;
                        if (mem4_cache_latched = '1') then
                           mem_size          <= "010";
                           datacache_active  <= '1';
                        else
                           mem_size          <= "001";
                        end if;
   
                     elsif (mem1_request_latched = '1') then
                     
                        memstate          <= MEMSTATE_BUSY1;
                        mem_request       <= '1';
                        memoryMuxStage4   <= '0';
                        mem_address       <= mem1_address_latched;
                        mem_req64         <= '0';
                        mem_rnw           <= '1';
                        if (mem1_cache_latched = '1') then
                           mem_size          <= "100";
                           mem_address(4 downto 0) <= (others => '0');
                           instrcache_active <= '1';
                        else
                           mem_size          <= "001";
                        end if;
                     
                     end if;
                     
                  end if;
                  
               when MEMSTATE_BUSY1 =>
                  if (mem_done = '1') then
                     memstate          <= MEMSTATE_IDLE;
                     instrcache_active <= '0';
                  end if;               
                  
               when MEMSTATE_BUSY4 =>
                  if (mem_done = '1') then
                     memstate         <= MEMSTATE_IDLE;
                     datacache_active <= '0';
                  end if;
                  
            end case;
            
         end if;
      end if;
   end process;
   
--##############################################################
--############################### FPU register file
--##############################################################
   iregisterfileFPU1LO : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 32,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk93,
      wren       => FPUregs_wren_a(0),
      data       => FPUregs_data_a(31 downto 0),
      wraddress  => FPUregs_address_a,
      rdaddress  => FPUregs1_address_b,
      q          => FPUregs1_q_b(31 downto 0)
	);
   iregisterfileFPU1HI : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 32,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk93,
      wren       => FPUregs_wren_a(1),
      data       => FPUregs_data_a(63 downto 32),
      wraddress  => FPUregs_address_a,
      rdaddress  => FPUregs1_address_b,
      q          => FPUregs1_q_b(63 downto 32)
	);
   
   FPUregs_wren_a    <= "11" when (ss_fpuregs_load = '1') else
                        cop1_stage4_writeMask when (ce_93 = '1' and cop1_stage4_writeEnable = '1') else 
                        FPUWriteMask          when (ce_93 = '1' and FPUWriteEnable = '1') else 
                        "00";
   
   FPUregs_data_a    <= ss_FPUregs_data                    when (ss_FPUregs_load = '1') else 
                        std_logic_vector(cop1_stage4_data) when (cop1_stage4_writeEnable = '1') else
                        std_logic_vector(FPUWriteData);
                     
   FPUregs_address_a <= std_logic_vector(ss_FPUregs_addr)    when (ss_FPUregs_load = '1') else 
                        std_logic_vector(cop1_stage4_target) when (cop1_stage4_writeEnable = '1') else
                        std_logic_vector(FPUWriteTarget);
   
   FPUregs1_address_b <= std_logic_vector(decFPUSource1);
   FPUregs2_address_b <= std_logic_vector(decFPUSource2);
   
   iregisterfileFPU2LO : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 32,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk93,
      wren       => FPUregs_wren_a(0),
      data       => FPUregs_data_a(31 downto 0),
      wraddress  => FPUregs_address_a,
      rdaddress  => FPUregs2_address_b,
      q          => FPUregs2_q_b(31 downto 0)
	);
   iregisterfileFPU2HI : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 32,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk93,
      wren       => FPUregs_wren_a(1),
      data       => FPUregs_data_a(63 downto 32),
      wraddress  => FPUregs_address_a,
      rdaddress  => FPUregs2_address_b,
      q          => FPUregs2_q_b(63 downto 32)
	);
   
--##############################################################
--############################### register file
--##############################################################
   iregisterfile1 : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 64,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk93,
      wren       => regs_wren_a,
      data       => regs_data_a,
      wraddress  => regs_address_a,
      rdaddress  => regs1_address_b,
      q          => regs1_q_b
	);
   
   regs_wren_a    <= '1' when (ss_regs_load = '1') else
                     '1' when (ce_93 = '1' and writebackWriteEnable = '1') else 
                     '0';
   
   regs_data_a    <= ss_regs_data when (ss_regs_load = '1') else 
                     std_logic_vector(writebackData);
                     
   regs_address_a <= std_logic_vector(ss_regs_addr) when (ss_regs_load = '1') else 
                     std_logic_vector(writebackTarget);
   
   regs1_address_b <= std_logic_vector(decSource1);
   regs2_address_b <= std_logic_vector(decSource2);
   
   iregisterfile2 : entity mem.RamMLAB
	GENERIC MAP 
   (
      width                               => 64,
      widthad                             => 5
	)
	PORT MAP (
      inclock    => clk93,
      wren       => regs_wren_a,
      data       => regs_data_a,
      wraddress  => regs_address_a,
      rdaddress  => regs2_address_b,
      q          => regs2_q_b
	);
   
   --iregisterfileSS : entity mem.RamMLAB
	--GENERIC MAP 
   --(
   --   width                               => 64,
   --   widthad                             => 5
	--)
	--PORT MAP (
   --   inclock    => clk93,
   --   wren       => regs_wren_a,
   --   data       => regs_data_a,
   --   wraddress  => regs_address_a,
   --   rdaddress  => regsSS_address_b,
   --   q          => regsSS_q_b
	--);

--##############################################################
--############################### stage 1
--##############################################################
   
   cache_commandEnable <= executeCacheEnable when (stall = 0) else '0';
   
   icpu_instrcache : entity work.cpu_instrcache
   port map
   (
      clk93             => clk93,
      clk2x             => clk2x,
      reset_93          => reset_93,
      ce_93             => ce_93,
      
      ram_request       => instrcache_request,
      ram_active        => instrcache_active,
      ram_grant         => rdram_granted2X,
      ram_done          => mem_finished_instr,
      ram_addr          => mem_address(28 downto 0),
      ddr3_DOUT         => ddr3_DOUT,      
      ddr3_DOUT_READY   => ddr3_DOUT_READY,
      
      read_select       => FetchAddrSelect,
      read_addr1        => FetchAddr1(28 downto 0),
      read_addr2        => FetchAddr2(28 downto 0),
      read_hit          => instrcache_hit,
      read_data         => instrcache_data,
      
      fill_request      => instrcache_fill,
      fill_addr         => mem1_address(28 downto 0),
      fill_done         => instrcache_fill_done,
      
      CacheCommandEna   => cache_commandEnable,
      CacheCommand      => executeCacheCommand,
      CacheCommandAddr  => executeMemAddress(31 downto 0),
      
      SS_reset          => SS_reset
   );
                     
   exceptionNew1   <= '0';
   
   -- todo: only in kernelmode and only in 32bit mode
   fetchCache     <= '1' when (FetchAddr1(31 downto 29) = "100") else '0';
   
   FetchAddr <= FetchAddr2 when (FetchAddrSelect = '1') else FetchAddr1;
   
   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         instrcache_fill <= '0';
         
         if (reset_93 = '1') then
                     
            mem1_request   <= '1';
            if (ss_in(16)(3) = '1') then
               mem1_address   <= unsigned(ss_in(5)(31 downto 0)); -- last was branch -> should be patched in the savestate already
               PC             <= unsigned(ss_in(5)); 
            else
               mem1_address   <= unsigned(ss_in(0)(31 downto 0)); -- x"FFFFFFFFBFC00000";    
               PC             <= unsigned(ss_in(0)); -- x"FFFFFFFFBFC00000";                    
            end if;
            stall1         <= '1';
            fetchReady     <= '1';
            useCached_data <= '0';
            
                 

            opcode0        <= (others => '0'); --unsigned(ss_in(14));
         
         elsif (ce_93 = '1') then
         
            mem1_request    <= '0';

            if (stall = 0) then
               fetchReady <= '0';
            end if;
            
            cacheHitLast <= instrcache_hit;
            if (useCached_data = '1' and cacheHitLast = '1' and stall(4 downto 1) > 0 and stall1 = '0') then
               useCached_data <= '0';
               opcode0        <= unsigned(instrcache_data);
            end if;
         
            if (stall1 = '1') then
            
               if (instrcache_fill_done = '1' and useCached_data = '1') then
                  useCached_data <= '0';
                  stall1         <= '0';
                  opcode0        <= unsigned(instrcache_data);
               elsif (mem_finished_instr = '1' and useCached_data = '0') then
                  stall1         <= '0';
                  opcode0        <= unsigned(byteswap32(mem_finished_dataRead(31 downto 0)));
               end if;
            
            elsif (stall = 0 or fetchReady = '0') then
            
               PCold0             <= FetchAddr;
               mem1_address       <= FetchAddr(31 downto 0);
               PC                 <= FetchAddr;
               useCached_data     <= fetchCache;
               fetchReady         <= '1';
     
               if (fetchCache = '1') then
                  if (instrcache_hit = '0') then
                     instrcache_fill    <= '1';
                     stall1             <= '1';
                  end if;
               else
                  mem1_request    <= '1';
                  stall1          <= '1';     
               end  if;  
               
            end if;
              
         end if;
      end if;
     
   end process;
   
   
--##############################################################
--############################### stage 2
--##############################################################
   
   opcodeCacheMuxed <= unsigned(instrcache_data) when (useCached_data = '1') else 
                       opcode0;     
                       
   decImmData    <= opcodeCacheMuxed(15 downto 0);
   decJumpTarget <= opcodeCacheMuxed(25 downto 0);
   decSource1    <= opcodeCacheMuxed(25 downto 21);
   decSource2    <= opcodeCacheMuxed(20 downto 16);
   decOP         <= opcodeCacheMuxed(31 downto 26);
   decFunct      <= opcodeCacheMuxed(5 downto 0);
   decShamt      <= opcodeCacheMuxed(10 downto 6);
   decRD         <= opcodeCacheMuxed(15 downto 11);
   decTarget     <= opcodeCacheMuxed(20 downto 16) when (opcodeCacheMuxed(31 downto 26) > 0) else opcodeCacheMuxed(15 downto 11);                  

   process (opcodeCacheMuxed, fpuRegMode, decOP)
   begin
      decFPUSource1 <= opcodeCacheMuxed(15 downto 11);
      decFPUSource2 <= opcodeCacheMuxed(20 downto 16);
   
      if (fpuRegMode = '0') then
         decFPUSource1(0) <= '0';
         if (decOP = 16#39# or decOP = 16#3D#) then -- SWC1 and SDC1
            decFPUSource2(0) <= '0';
         end if;
      end if;
  
   end process;
   
   decRequiresFPUreg1 <= '1' when (decOP = 16#11# and (decSource1(4) = '1' or decSource1(3 downto 1) = 0)) else 
                         '0';
                         
   -- can be optimized to only request opcodes that really need 2 ops
   decRequiresFPUreg2 <= '1' when (decOP = 16#11# and (decSource1(4) = '1' or decSource1(3 downto 1) = 0)) else 
                         '1' when (decOP = 16#39# or decOP = 16#3D#) else
                         '0';
   
   decFPUForwardUse <= (decodeFPUCommandEnable or decodeFPUTransferEnable) when (decRequiresFPUreg1 = '1' and decodeFPUTarget = decFPUSource1) else
                       (decodeFPUCommandEnable or decodeFPUTransferEnable) when (decRequiresFPUreg2 = '1' and decodeFPUTarget = decFPUSource2) else
                       '0';

   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         if (reset_93 = '1') then
         
            stall2           <= '0';
            decodeNew        <= '0';
            decode_irq       <= '0';
            decodeBranchType <= BRANCH_OFF;
            
         elsif (ce_93 = '1') then
         
            if (stall = 0) then
            
               decodeNew <= '0';
            
               if (exception = '1') then
               
                  decode_irq <= '0';
               
               elsif (fetchReady = '1') then
               
                  decodeNew        <= '1'; 
               
                  pcOld1           <= pcOld0;
                  opcode1          <= opcodeCacheMuxed;
                                    
                  decodeImmData    <= decImmData;   
                  decodeJumpTarget <= decJumpTarget;
                  decodeSource1    <= decSource1;
                  decodeSource2    <= decSource2;
                  decodeOP         <= decOP;
                  decodeFunct      <= decFunct;     
                  decodeShamt      <= '0' & decShamt;     
                  decodeRD         <= decRD;        
                  decodeTarget     <= decTarget;    
                  decodeFPUSource1 <= decFPUSource1;
                  decodeFPUSource2 <= decFPUSource2;
                  
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

                  -- FPU operand featching
                  decodeFPUValue1 <= unsigned(FPUregs1_q_b);
                  decodeFPUValue2 <= unsigned(FPUregs2_q_b);
                  decodeFPUTarget <= opcodeCacheMuxed(10 downto 6);
                  
                  if (unsigned(FPUregs_address_a) = decFPUSource1 and FPUregs_wren_a(1) = '1') then decodeFPUValue1(63 downto 32) <= unsigned(FPUregs_data_a(63 downto 32)); end if;
                  if (unsigned(FPUregs_address_a) = decFPUSource1 and FPUregs_wren_a(0) = '1') then decodeFPUValue1(31 downto  0) <= unsigned(FPUregs_data_a(31 downto  0)); end if;
                  if (unsigned(FPUregs_address_a) = decFPUSource2 and FPUregs_wren_a(1) = '1') then decodeFPUValue2(63 downto 32) <= unsigned(FPUregs_data_a(63 downto 32)); end if;
                  if (unsigned(FPUregs_address_a) = decFPUSource2 and FPUregs_wren_a(0) = '1') then decodeFPUValue2(31 downto  0) <= unsigned(FPUregs_data_a(31 downto  0)); end if;

                  decodeFPUForwardUse <= decFPUForwardUse;

                  -- decoding default
                  decodeUseImmidateValue2 <= '0';
                  decodeShiftSigned       <= '0';
                  decodeShift32           <= '0';
                  decodeResult32          <= '0';
                  decodeBranchType        <= BRANCH_OFF;
                  decodeBranchLikely      <= '0';
                  decodeFPUCommandEnable  <= '0';
                  decodeFPUTransferEnable <= '0';
                  decodeFPUTransferWrite  <= '0';
                  decodeFPUMULS           <= '0';
                  decodeFPUMULD           <= '0';
                  blockIRQ                <= '0';

                  -- decoding opcode specific
                  case (to_integer(decOP)) is
         
                     when 16#00# =>
                        case (to_integer(decFunct)) is
                        
                           when 16#00# => -- SLL
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= "00";
                              decodeResult32          <= '1';
                              
                           when 16#02# => -- SRL
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShift32           <= '1';
                              decodeShiftAmountType   <= "00";
                              decodeResult32          <= '1';
                           
                           when 16#03# => -- SRA
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT; 
                              decodeShiftSigned       <= '1';
                              decodeShiftAmountType   <= "00";
                              decodeResult32          <= '1';
                              
                           when 16#04# => -- SLLV
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= "01";
                              decodeResult32          <= '1';
                              
                           when 16#06# => -- SRLV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShift32           <= '1';
                              decodeShiftAmountType   <= "01";
                              decodeResult32          <= '1';
                           
                           when 16#07# => -- SRAV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftSigned       <= '1';
                              decodeShiftAmountType   <= "01";
                              decodeResult32          <= '1';
                              
                           when 16#08# => -- JR
                              decodeBranchType        <= BRANCH_ALWAYS_REG;
                              
                           when 16#09# => -- JALR
                              decodeResultMux         <= RESULTMUX_PC;
                              decodeTarget            <= decRD;
                              decodeBranchType        <= BRANCH_ALWAYS_REG;
                              
                           when 16#10# => -- MFHI
                              decodeResultMux         <= RESULTMUX_HI;
                  
                           when 16#12# => -- MFLO
                              decodeResultMux         <= RESULTMUX_LO;
                              
                           when 16#14# => -- DSLLV
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= "10";   
                  
                           when 16#16# => -- DSRLV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= "10";   
                              
                           when 16#17# => -- DSRAV
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= "10";   
                              decodeShiftSigned       <= '1';
                              
                           when 16#20# => -- ADD
                              decodeResultMux         <= RESULTMUX_ADD;
                              decodeResult32          <= '1';
                  
                           when 16#21# => -- ADDU
                              decodeResultMux         <= RESULTMUX_ADD;
                              decodeResult32          <= '1';
                              
                           when 16#22# => -- SUB
                              decodeResultMux         <= RESULTMUX_SUB;
                              decodeResult32          <= '1';
                           
                           when 16#23# => -- SUBU
                              decodeResultMux         <= RESULTMUX_SUB;
                              decodeResult32          <= '1';
                           
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
                              
                           when 16#2C# => -- DADD        
                              decodeResultMux         <= RESULTMUX_ADD;
                  
                           when 16#2D# => -- DADDU
                              decodeResultMux         <= RESULTMUX_ADD;  
                              
                           when 16#2E# => -- DSUB
                              decodeResultMux         <= RESULTMUX_SUB;
                              
                           when 16#2F# => -- DSUBU
                              decodeResultMux         <= RESULTMUX_SUB;
                  
                           when 16#38# => -- DSLL
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= "00"; 
                  
                           when 16#3A# => -- DSRL
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= "00"; 
                              
                           when 16#3B# => -- DSRA
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= "00"; 
                              decodeShiftSigned       <= '1';
                              
                           when 16#3C# => -- DSLL + 32
                              decodeResultMux         <= RESULTMUX_SHIFTLEFT;
                              decodeShiftAmountType   <= "00"; 
                              decodeShamt(5)          <= '1';
                              
                           when 16#3E# => -- DSRL + 32
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= "00"; 
                              decodeShamt(5)          <= '1';
                              
                           when 16#3F# => -- DSRA + 32
                              decodeResultMux         <= RESULTMUX_SHIFTRIGHT;
                              decodeShiftAmountType   <= "00"; 
                              decodeShamt(5)          <= '1';
                              decodeShiftSigned       <= '1';

                           when others => null;
                        end case;
  
                     when 16#01# => 
                        if (decSource2(3) = '1') then -- Traps
                           null;
                        else -- B: BLTZ, BGEZ, BLTZAL, BGEZAL
                           if (decSource2(4) = '1') then
                              decodeResultMux      <= RESULTMUX_PC;
                              decodeTarget         <= to_unsigned(31, 5);
                           end if;
                           if (decSource2(0) = '1') then
                              decodeBranchType     <= BRANCH_BRANCH_BGEZ;
                           else
                              decodeBranchType     <= BRANCH_BRANCH_BLTZ;
                           end if;
                           decodeBranchLikely      <= decSource2(1);
                           if (decSource2(1) = '1') then blockIRQ <= '1'; end if;
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
                        
                     when 16#08# => -- ADDI
                        decodeResultMux         <= RESULTMUX_ADD;
                        decodeResult32          <= '1';
                        decodeUseImmidateValue2 <= '1';
            
                     when 16#09# => -- ADDIU
                        decodeResultMux         <= RESULTMUX_ADD;
                        decodeResult32          <= '1';
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
                        blockIRQ <= '1';
                        if (decSource1(4) = '1' and decImmData(6 downto 0) = 16#18#) then -- ERET
                           decodeBranchType     <= BRANCH_ERET;
                        end if;                     
                        
                     when 16#11# => -- COP1
                        decodeResultMux         <= RESULTMUX_FPU;
                        if (decSource1(4) = '1') then -- FPU execute
                           decodeFPUCommandEnable  <= COP1_enable;
                           if (decFunct = 2) then
                              if (decSource1 = 16) then decodeFPUMULS <= '1'; end if;
                              if (decSource1 = 17) then decodeFPUMULD <= '1'; end if;
                           end if;
                        else
                           decodeFPUTarget         <= decRD;
                           decodeFPUTransferEnable <= COP1_enable;
                           if (decSource1(3 downto 0) < 3) then
                              decodeFPUTransferWrite <= '1';
                           end if;
                           if (decSource1(3 downto 0) = x"8") then
                              decodeBranchType   <= BRANCH_BC1;
                              decodeBranchLikely <= decSource2(1);
                              if (decSource2(1) = '1') then blockIRQ <= '1'; end if;
                           end if;
                        end if;
                        
                     when 16#14# => -- BEQL
                        decodeBranchType        <= BRANCH_BRANCH_BEQ;
                        decodeBranchLikely      <= '1';
                        blockIRQ                <= '1';
                           
                     when 16#15# => -- BNEL
                        decodeBranchType        <= BRANCH_BRANCH_BNE;
                        decodeBranchLikely      <= '1';
                        blockIRQ                <= '1';
                        
                     when 16#16# => -- BLEZL
                        decodeBranchType        <= BRANCH_BRANCH_BLEZ;
                        decodeBranchLikely      <= '1';
                        blockIRQ                <= '1';
                        
                     when 16#17# => -- BGTZL
                        decodeBranchType        <= BRANCH_BRANCH_BGTZ;
                        decodeBranchLikely      <= '1';
                        blockIRQ                <= '1';
                        
                     when 16#18# => -- DADDI   
                        decodeResultMux         <= RESULTMUX_ADD;
                        decodeUseImmidateValue2 <= '1';
            
                     when 16#19# => -- DADDIU 
                        decodeResultMux         <= RESULTMUX_ADD;
                        decodeUseImmidateValue2 <= '1';
                        
                     when 16#38# => -- SC
                        decodeResultMux         <= RESULTMUX_BIT;
                        decodeBitFuncType       <= BITFUNC_SC;
                        
                     when 16#3C# => -- SCD 
                        decodeResultMux         <= RESULTMUX_BIT;
                        decodeBitFuncType       <= BITFUNC_SC;
                     
                     when others => null;   
                     
                  end case;
                  
                  if (irqTrigger = '1' and blockIRQ = '0') then
                     decode_irq <= '1';
                     decodeNew  <= '0';
                  end if;
                  
                  if (decode_irq = '1') then
                     decodeNew <= '0';
                  end if;
                  
               end if; -- fetchReady
      
            else
               
               -- operand forwarding in stall
               if (decodeSource1 > 0 and writebackTarget = decodeSource1 and writebackWriteEnable = '1') then decodeValue1 <= writebackData; end if;
               if (decodeSource2 > 0 and writebackTarget = decodeSource2 and writebackWriteEnable = '1') then decodeValue2 <= writebackData; end if;
      
               if (unsigned(FPUregs_address_a) = decodeFPUSource1 and FPUregs_wren_a(1) = '1') then decodeFPUValue1(63 downto 32) <= unsigned(FPUregs_data_a(63 downto 32)); end if;
               if (unsigned(FPUregs_address_a) = decodeFPUSource1 and FPUregs_wren_a(0) = '1') then decodeFPUValue1(31 downto  0) <= unsigned(FPUregs_data_a(31 downto  0)); end if;
               if (unsigned(FPUregs_address_a) = decodeFPUSource2 and FPUregs_wren_a(1) = '1') then decodeFPUValue2(63 downto 32) <= unsigned(FPUregs_data_a(63 downto 32)); end if;
               if (unsigned(FPUregs_address_a) = decodeFPUSource2 and FPUregs_wren_a(0) = '1') then decodeFPUValue2(31 downto  0) <= unsigned(FPUregs_data_a(31 downto  0)); end if;
      
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
   value2_muxedSigned <= unsigned(resize(signed(decodeImmData), 64)) when (decodeUseImmidateValue2) else value2;
   calcResult_add     <= value1 + value2_muxedSigned;
   
   calcMemAddr        <= value1 + unsigned(resize(signed(decodeImmData), 64));
   
   ---------------------- Shifter ------------------
   -- multiplex immidiate and register based shift amount, so both types can use the same shifters
   executeShamt <= decodeShamt              when (decodeShiftAmountType = "00") else
                   '0' & value1(4 downto 0) when (decodeShiftAmountType = "01") else
                   value1(5 downto 0);
   
   -- multiplex high bit of rightshift so arithmetic shift can be reused for logical shift
   shiftValue(31 downto 0)  <= signed(value2(31 downto 0));
   shiftValue(63 downto 32) <= (others => '0') when (decodeShift32 = '1') else signed(value2(63 downto 32));
   shiftValue(64) <= value2(63) when (decodeShiftSigned = '1') else '0';

   calcResult_shiftL <= value2 sll to_integer(executeShamt);
   calcResult_shiftR <= resize(unsigned(shift_right(shiftValue,to_integer(executeShamt))), 64);  

   ---------------------- Sub ------------------
   calcResult_sub    <= value1 - value2;
   
   ---------------------- logical calcs ------------------
   value2_muxedLogical <= x"000000000000" & decodeImmData when (decodeUseImmidateValue2) else value2;
   
   calcResult_and    <= value1 and value2_muxedLogical;
   calcResult_or     <= value1 or value2_muxedLogical;
   calcResult_xor    <= value1 xor value2_muxedLogical;
   calcResult_nor    <= value1 nor value2;

   ---------------------- bit functions ------------------
   
   calcResult_lesserSigned      <= '1' when (signed(value1) < signed(value2)) else '0'; 
   calcResult_lesserUnsigned    <= '1' when (value1 < value2) else '0';    
   calcResult_lesserIMMSigned   <= '1' when (signed(value1) < resize(signed(decodeImmData), 64)) else '0'; 
   calcResult_lesserIMMUnsigned <= '1' when (value1 < unsigned(resize(signed(decodeImmData), 64))) else '0'; 
   calcResult_equal             <= '1' when (signed(value1) = resize(signed(decodeImmData), 64)) else '0'; 
   
   calcResult_bit(63 downto 1) <= (others => '0');
   calcResult_bit(0) <= calcResult_lesserSigned       when (decodeBitFuncType = BITFUNC_SIGNED) else
                        calcResult_lesserUnSigned     when (decodeBitFuncType = BITFUNC_UNSIGNED) else
                        calcResult_lesserIMMSigned    when (decodeBitFuncType = BITFUNC_IMM_SIGNED) else
                        calcResult_lesserIMMUnsigned  when (decodeBitFuncType = BITFUNC_IMM_UNSIGNED) else
                        llBit;
   
   ---------------------- branching ------------------
   --PCnext       <= PC + 4;
   --PCnextBranch <= pcOld0 + unsigned((resize(signed(decodeImmData), 62) & "00"));
   -- assume region change cannot/will not happen with counting up or short jumps
   PCnext       <= PC(63 downto 29) & (PC(28 downto 0) + 4);
   PCnextBranch <= pcOld0(63 downto 29) & (pcOld0(28 downto 0) + unsigned((resize(signed(decodeImmData), 27) & "00")));
   
   cmpEqual    <= '1' when (value1 = value2) else '0';
   cmpNegative <= value1(63);
   cmpZero     <= '1' when (value1 = 0) else '0';
   
   -- use two nextaddress/branch paths with 2 tag rams, so different paths can be calculated in parallel to improve timing
   
   FetchAddrSelect <= '0'  when (exception = '1' or executeIgnoreNext = '1' or decodeNew = '0') else
                      '1'  when (decodeBranchType = BRANCH_BRANCH_BGEZ and (cmpZero = '1' or cmpNegative = '0'))  else
                      '1'  when (decodeBranchType = BRANCH_BRANCH_BLTZ and cmpNegative = '1')                     else
                      '1'  when (decodeBranchType = BRANCH_BRANCH_BEQ  and cmpEqual = '1')                        else
                      '1'  when (decodeBranchType = BRANCH_BRANCH_BNE  and cmpEqual = '0')                        else
                      '1'  when (decodeBranchType = BRANCH_BRANCH_BLEZ and (cmpZero = '1' or cmpNegative = '1'))  else
                      '1'  when (decodeBranchType = BRANCH_BRANCH_BGTZ and (cmpZero = '0' and cmpNegative = '0')) else
                      '1'  when (decodeBranchType = BRANCH_BC1         and decodeSource2(0) = FPU_CF) else
                      '0';
   
   FetchAddr1 <= exceptionPC                                    when (exception = '1') else
                 PCnext                                         when (executeIgnoreNext = '1' or decodeNew = '0') else
                 value1                                         when (decodeBranchType = BRANCH_ALWAYS_REG) else
                 pcOld0(63 downto 28) & decodeJumpTarget & "00" when (decodeBranchType = BRANCH_JUMPIMM) else
                 eretPC                                         when (decodeBranchType = BRANCH_ERET) else
                 PCnext;

   FetchAddr2 <= PCnextBranch;

   EXEBranchdelaySlot <= '0' when (executeIgnoreNext = '1') else
                         '1' when (decodeBranchType = BRANCH_ALWAYS_REG) else
                         '1' when (decodeBranchType = BRANCH_JUMPIMM) else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BGEZ and (decodeBranchLikely = '0' or (cmpZero = '1' or cmpNegative = '0')))  else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BLTZ and (decodeBranchLikely = '0' or cmpNegative = '1')                   )  else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BEQ  and (decodeBranchLikely = '0' or cmpEqual = '1')                      )  else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BNE  and (decodeBranchLikely = '0' or cmpEqual = '0')                      )  else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BLEZ and (decodeBranchLikely = '0' or (cmpZero = '1' or cmpNegative = '1')))  else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BGTZ and (decodeBranchLikely = '0' or (cmpZero = '0' and cmpNegative = '0'))) else
                         '1' when (decodeBranchType = BRANCH_BC1         and (decodeBranchLikely = '0' or decodeSource2(0) = FPU_CF))             else
                         '0';
                         
   EXEIgnoreNext      <= '0' when (executeIgnoreNext = '1') else
                         '1' when (decodeBranchType = BRANCH_ERET) else                      
                         '1' when (decodeBranchType = BRANCH_BRANCH_BGEZ and decodeBranchLikely = '1' and cmpZero = '0' and cmpNegative = '1')  else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BLTZ and decodeBranchLikely = '1' and cmpNegative = '0')                    else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BEQ  and decodeBranchLikely = '1' and cmpEqual = '0')                       else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BNE  and decodeBranchLikely = '1' and cmpEqual = '1')                       else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BLEZ and decodeBranchLikely = '1' and cmpZero = '0' and cmpNegative = '0')  else
                         '1' when (decodeBranchType = BRANCH_BRANCH_BGTZ and decodeBranchLikely = '1' and (cmpZero = '1' or cmpNegative = '1')) else
                         '1' when (decodeBranchType = BRANCH_BC1         and decodeBranchLikely = '1' and decodeSource2(0) /= FPU_CF)           else
                         '0';

   ---------------------- result muxing ------------------
   resultDataMuxed <= calcResult_shiftL when (decodeResultMux = RESULTMUX_SHIFTLEFT)  else
                      calcResult_shiftR when (decodeResultMux = RESULTMUX_SHIFTRIGHT) else
                      calcResult_add    when (decodeResultMux = RESULTMUX_ADD)        else
                      PCnext            when (decodeResultMux = RESULTMUX_PC)         else
                      HI                when (decodeResultMux = RESULTMUX_HI)         else
                      LO                when (decodeResultMux = RESULTMUX_LO)         else
                      calcResult_sub    when (decodeResultMux = RESULTMUX_SUB)        else
                      calcResult_and    when (decodeResultMux = RESULTMUX_AND)        else
                      calcResult_or     when (decodeResultMux = RESULTMUX_OR )        else
                      calcResult_xor    when (decodeResultMux = RESULTMUX_XOR)        else
                      calcResult_nor    when (decodeResultMux = RESULTMUX_NOR)        else
                      calcResult_bit    when (decodeResultMux = RESULTMUX_BIT)        else
                      FPU_TransferData  when (decodeResultMux = RESULTMUX_FPU)        else
                      unsigned(resize(signed(decodeImmData) & x"0000", 64)); -- (decodeResultMux = RESULTMUX_LUI);
                      
   resultDataMuxed64(31 downto 0) <= resultDataMuxed(31 downto 0);
   resultDataMuxed64(63 downto 32) <= (others => resultDataMuxed(31)) when decodeResult32 else resultDataMuxed(63 downto 32);

   process (decodeImmData, decodeJumpTarget, decodeSource1, decodeSource2, decodeValue1, decodeValue2, decodeOP, decodeFunct, decodeShamt, decodeRD, 
            exception, stall3, stall, value1, value2, pcOld0, resultData, eretPC, decodeFPUValue2, decodeFPUCommandEnable, decodeFPUTransferEnable, decodeFPUTransferWrite,
            hi, lo, executeIgnoreNext, decodeNew, llBit, calcResult_add, calcResult_sub, calcMemAddr, COP1_enable, COP2_enable, cmpEqual, fpuRegMode,
            calcResult_lesserSigned, calcResult_lesserUnsigned, calcResult_lesserIMMSigned, calcResult_lesserIMMUnsigned, calcResult_equal)
      variable calcResult           : unsigned(63 downto 0);
      variable rotatedData          : unsigned(63 downto 0) := (others => '0');
   begin
   
      EXEerror_instr          <= '0';
   
      exceptionNew3           <= '0';
      exception_COP           <= "00";
      EXEERET                 <= '0';
      stallNew3               <= stall3;
      EXEresultWriteEnable    <= '0';          
      
      rotatedData             := byteswap32(value2(63 downto 32)) & byteswap32(value2(31 downto 0));
      EXEMem64Bit             <= '0';
      EXEMemWriteEnable       <= '0';
      EXEMemWriteData         <= rotatedData;
      EXEMemWriteMask         <= "00000000";
      EXEMemWriteException    <= '0';
      
      EXELoadType             <= LOADTYPE_DWORD;
      EXEReadEnable           <= '0';
      EXEReadException        <= '0';
      
      EXECacheEnable          <= '0';
      EXECacheAddr            <= calcMemAddr(28 downto 0);  
      
      EXECOP0WriteEnable      <= '0';
      EXECOP0ReadEnable       <= '0';
      EXECOP0Read64           <= '0';
      EXECOP0Register         <= decodeRD;
      EXECOP0WriteValue       <= value2;
      
      ExeCOP1ReadEnable       <= '0';
      
      EXECOP2WriteEnable      <= '0';
      EXECOP2ReadEnable       <= '0';
      EXECOP2Read64           <= '0';
      
      EXEcalcMULT             <= '0';
      EXEcalcMULTU            <= '0';      
      EXEcalcDMULT            <= '0';
      EXEcalcDMULTU           <= '0';
      EXEcalcDIV              <= '0';
      EXEcalcDIVU             <= '0';
      EXEcalcDDIV             <= '0';
      EXEcalcDDIVU            <= '0';
      
      EXEhiUpdate             <= '0';
      EXEloUpdate             <= '0';
      
      EXEllBit                <= llBit;
      
      exceptionCode_3         <= x"0";
      
      FPU_command_ena         <= '0';
      FPU_TransferEna         <= '0';
      
      if (exception = '0' and stall = 0 and executeIgnoreNext = '0' and decodeNew = '1') then
             
         FPU_command_ena      <= decodeFPUCommandEnable;
         FPU_TransferEna      <= decodeFPUTransferEnable;
             
         case (to_integer(decodeOP)) is
         
            when 16#00# =>
               case (to_integer(decodeFunct)) is
         
                  when 16#00# | 16#04# => -- SLL | SLLV
                     EXEresultWriteEnable <= '1';

                  when 16#02# | 16#03# | 16#06# | 16#07# => -- SRL | SRA | SRLV | SRAV
                     EXEresultWriteEnable <= '1';               
                    
                  when 16#08# => -- JR        
                     if (value1(1 downto 0) > 0) then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"4";
                     end if;
                    
                  when 16#09# => -- JALR        
                     EXEresultWriteEnable <= '1';
                     if (value1(1 downto 0) > 0) then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"4";
                     end if;

                  when 16#0C# => -- SYSCALL
                     exceptionNew3   <= '1';
                     exceptionCode_3 <= x"8";
                     
                  when 16#0D# => -- BREAK
                     exceptionNew3   <= '1';
                     exceptionCode_3 <= x"9";
                     
                  when 16#0F# => -- SYNC
                     null;

                  when 16#10# => -- MFHI
                     EXEresultWriteEnable <= '1';
                     
                  when 16#11# => -- MTHI
                     EXEhiUpdate <= '1';
                     
                  when 16#12# => -- MFLO
                     EXEresultWriteEnable <= '1';
                     
                  when 16#13# => -- MTLO
                     EXEloUpdate <= '1';
                     
                  when 16#14# | 16#38# | 16#3C# => -- DSLLV | DSLL | DSLL + 32
                     EXEresultWriteEnable <= '1'; 
                     
                  when 16#16# | 16#17# | 16#3A# | 16#3B# | 16#3E# | 16#3F# => -- DSRLV | DSRAV | DSRL | DSRA | DSRL + 32 | DSRA + 32
                     EXEresultWriteEnable <= '1';
                     
                  when 16#18# => -- MULT
                     EXEcalcMULT <= '1';
                     
                  when 16#19# => -- MULTU
                     EXEcalcMULTU <= '1';
                     
                  when 16#1A# => -- DIV
                     EXEcalcDIV <= '1';
                     
                  when 16#1B# => -- DIVU
                     EXEcalcDIVU <= '1';
                     
                  when 16#1C# => -- DMULT
                     EXEcalcDMULT <= '1';                
                     
                  when 16#1D# => -- DMULTU
                     EXEcalcDMULTU <= '1';                  
                     
                  when 16#1E# => -- DDIV
                     EXEcalcDDIV <= '1';             
                     
                  when 16#1F# => -- DDIVU
                     EXEcalcDDIVU <= '1';
                  
                  when 16#20# => -- ADD        
                     if (((calcResult_add(31) xor value1(31)) and (calcResult_add(31) xor value2(31))) = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"C";
                     else
                        EXEresultWriteEnable <= '1';
                     end if;
                  
                  when 16#21# => -- ADDU
                     EXEresultWriteEnable <= '1';
                    
                  when 16#22# => -- SUB         
                     if (((calcResult_sub(31) xor value1(31)) and (value1(31) xor value2(31))) = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"C";
                     else
                        EXEresultWriteEnable <= '1';
                     end if;
                  
                  when 16#23# => -- SUBU
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
                     
                  when 16#2C# => -- DADD        
                     if (((calcResult_add(63) xor value1(63)) and (calcResult_add(63) xor value2(63))) = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"C";
                     else
                        EXEresultWriteEnable <= '1';
                     end if; 
                  
                  when 16#2D# => -- DADDU
                     EXEresultWriteEnable <= '1';                
                     
                  when 16#2E# => -- DSUB            
                     if (((calcResult_sub(63) xor value1(63)) and (value1(63) xor value2(63))) = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"C";
                     else
                        EXEresultWriteEnable <= '1';
                     end if;
                     
                  when 16#2F# => -- DSUBU
                     EXEresultWriteEnable <= '1';
                     
                  when 16#30# => -- TGE
                     if (calcResult_lesserSigned = '0') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"D";
                     end if;
                     
                  when 16#31# => -- TGEU
                     if (calcResult_lesserUnsigned = '0') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"D";
                     end if;
                     
                  when 16#32# => -- TLT
                     if (calcResult_lesserSigned = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"D";
                     end if;
                     
                  when 16#33# => -- TLTU
                     if (calcResult_lesserUnsigned = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"D";
                     end if;
                     
                  when 16#34# => -- TEQ
                     if (cmpEqual = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"D";
                     end if;
                     
                  when 16#36# => -- TNE
                     if (cmpEqual = '0') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"D";
                     end if;
                     
                  -- 16#38# | 16#3C# | 16#3A# | 16#3B# | 16#3E# | 16#3F# => covered at 16#14#
                     
                  when others => 
                  -- synthesis translate_off
                     report to_hstring(decodeFunct);
                  -- synthesis translate_on
                     --report "Unknown extended opcode" severity failure; 
                     exceptionNew3   <= '1';
                     exceptionCode_3 <= x"A";
                     EXEerror_instr  <= '1';
                     
               end case;
               
            when 16#01# => 
               if (decodeSource2(3) = '1') then -- Traps
                  case (decodeSource2(2 downto 0)) is
                     when 3x"0" => -- TGEI
                        if (calcResult_lesserIMMSigned = '0') then
                           exceptionNew3   <= '1';
                           exceptionCode_3 <= x"D";
                        end if;
                        
                     when 3x"1" => -- TGEIU
                        if (calcResult_lesserIMMUnsigned = '0') then
                           exceptionNew3   <= '1';
                           exceptionCode_3 <= x"D";
                        end if;
                        
                     when 3x"2" => -- TLTI
                        if (calcResult_lesserIMMSigned = '1') then
                           exceptionNew3   <= '1';
                           exceptionCode_3 <= x"D";
                        end if;
                        
                     when 3x"3" => -- TLTIU
                        if (calcResult_lesserIMMUnsigned = '1') then
                           exceptionNew3   <= '1';
                           exceptionCode_3 <= x"D";
                        end if;
                        
                     when 3x"4" => -- TEQI
                        if (calcResult_equal = '1') then
                           exceptionNew3   <= '1';
                           exceptionCode_3 <= x"D";
                        end if;
                        
                     when 3x"6" => -- TNEI
                        if (calcResult_equal = '0') then
                           exceptionNew3   <= '1';
                           exceptionCode_3 <= x"D";
                        end if;
                     
                     when others =>
                     -- synthesis translate_off
                        report to_hstring(decodeFunct);
                     -- synthesis translate_on
                        --report "Unknown traps opcode" severity failure; 
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"A";
                        EXEerror_instr  <= '1';
                  end case;
               else -- B: BLTZ, BGEZ, BLTZAL, BGEZAL
                  if (decodeSource2(4) = '1') then
                     EXEresultWriteEnable <= '1';
                  end if;
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
            
            when 16#08# => -- ADDI             
               if (((calcResult_add(31) xor value1(31)) and (calcResult_add(31) xor decodeImmData(15))) = '1') then
                  exceptionNew3   <= '1';
                  exceptionCode_3 <= x"C";
               else
                  EXEresultWriteEnable <= '1';
               end if;
            
            when 16#09# => -- ADDIU          
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
               --if (cop0_SR(1) = '1' and cop0_SR(28) = '0') then
               --   exceptionNew3   <= '1';
               --   exceptionCode_3 <= x"B";
               --else
                  if (decodeSource1(4) = '1') then
                     case (to_integer(decodeImmData(5 downto 0))) is
                        when 1 =>
                           report "TLBR command not implemented" severity warning;
                           EXEerror_instr     <= '1';                           
                           
                        when 2 | 6 =>
                           report "TLBWI and TLBWR command not implemented" severity warning; 
                           if (to_integer(decodeImmData(5 downto 0)) = 6) then --TLBWR
                              EXEerror_instr     <= '1';
                           end if;

                        when 8 =>
                           report "TLBP command not implemented" severity warning;     
                           EXEerror_instr     <= '1';

                        when 16#18# => -- ERET
                           EXEllBit       <= '0';
                           EXEERET        <= '1';
                           
                        when others => 
                           report "should not happen" severity failure; 
                           EXEerror_instr  <= '1';
                           
                     end case;
                  else
                     case (to_integer(decodeSource1(3 downto 0))) is
                     
                        when 0 => -- mfc0
                           EXECOP0ReadEnable  <= '1';
                           EXECOP0Read64      <= '0';
                                             
                        when 1 => -- dmfc0
                           EXECOP0ReadEnable  <= '1';
                           EXECOP0Read64      <= '1';

                        when 4 => -- mtc0
                           exeCOP0WriteEnable <= '1';
                           exeCOP0WriteValue  <= unsigned(resize(signed(value2(31 downto 0)), 64));
                           
                        when 5 => -- dmtc0
                           exeCOP0WriteEnable <= '1';
                         
                        when others => 
                           report "should not happen" severity failure; 
                           EXEerror_instr     <= '1';
                           
                     end case;
                  end if;
               --end if;
               
            when 16#11# => -- COP1
               if (COP1_enable = '0' or (decodeSource1(4) = '0' and decodeSource1(3 downto 0) > 8)) then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"B";
                  exception_COP    <= "01";
               else  
                  EXEresultWriteEnable <= decodeFPUTransferWrite;
               end if;
               
            when 16#12# => -- COP2
               if (COP2_enable = '0') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"B";
                  exception_COP    <= "10";
               else  
                  case (to_integer(decodeSource1)) is
                  
                     when 0 | 2 =>
                        EXECOP2ReadEnable <= '1';
                     
                     when 1 =>
                        EXECOP2ReadEnable <= '1';
                        EXECOP2Read64 <= '1';
                        
                     when 4 | 5 | 6 =>
                        EXECOP2WriteEnable <= '1';
                  
                     when others =>
                        exceptionNew3    <= '1';
                        exceptionCode_3  <= x"A";
                        exception_COP    <= "10";
                        
                  end case;
               end if;
               
            when 16#13# => -- COP3 -> does not exist
               exceptionNew3    <= '1';
               exceptionCode_3  <= x"A";
               
            when 16#14# => -- BEQL
               null;
               
            when 16#15# => -- BNEL
               null;
               
            when 16#16# => -- BLEZL
               null;
               
            when 16#17# => -- BGTZL
               null;

            when 16#18# => -- DADDI             
               if (((calcResult_add(63) xor value1(63)) and (calcResult_add(63) xor decodeImmData(15))) = '1') then
                  exceptionNew3   <= '1';
                  exceptionCode_3 <= x"C";
               else
                  EXEresultWriteEnable <= '1';
               end if;
            
            when 16#19# => -- DADDIU           
               EXEresultWriteEnable <= '1';
               
            when 16#1A# => -- LDL
               EXELoadType   <= LOADTYPE_LEFT64;
               EXEReadEnable <= '1';
               EXEMem64Bit   <= '1';
               EXECacheAddr(2 downto 0) <= "000";
               
            when 16#1B# => -- LDR
               EXELoadType   <= LOADTYPE_RIGHT64;
               EXEReadEnable <= '1';
               EXEMem64Bit   <= '1';
               EXECacheAddr(2 downto 0) <= "000";

            when 16#20# => -- LB
               EXELoadType   <= LOADTYPE_SBYTE;
               EXEReadEnable <= '1';
               
            when 16#21# => -- LH
               EXELoadType <= LOADTYPE_SWORD;
               if (calcMemAddr(0) = '1') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if;  

            when 16#22# => -- LWL
               EXELoadType   <= LOADTYPE_LEFT;
               EXEReadEnable <= '1';
               EXECacheAddr(1 downto 0) <= "00";
               
            when 16#23# => -- LW
               EXELoadType <= LOADTYPE_DWORD;
               if (calcMemAddr(1 downto 0) /= "00") then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if;  

            when 16#24# => -- LBU
               EXELoadType <= LOADTYPE_BYTE;
               EXEReadEnable <= '1';

            when 16#25# => -- LHU
               EXELoadType <= LOADTYPE_WORD;
               if (calcMemAddr(0) = '1') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if; 
               
            when 16#26# => -- LWR
               EXELoadType   <= LOADTYPE_RIGHT;
               EXEReadEnable <= '1';
               EXECacheAddr(1 downto 0) <= "00";

            when 16#27# => -- LWU
               EXELoadType <= LOADTYPE_DWORDU;
               if (calcMemAddr(1 downto 0) /= "00") then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if;                

            when 16#28# => -- SB
               case (to_integer(calcMemAddr(1 downto 0))) is 
                  when 0 => EXEMemWriteMask(3 downto 0) <= "0001"; EXEMemWriteData <= x"00000000" & x"000000" & rotatedData(31 downto 24); 
                  when 1 => EXEMemWriteMask(3 downto 0) <= "0010"; EXEMemWriteData <= x"00000000" & x"0000" &   rotatedData(31 downto 16);   
                  when 2 => EXEMemWriteMask(3 downto 0) <= "0100"; EXEMemWriteData <= x"00000000" & x"00" &     rotatedData(31 downto 8);   
                  when 3 => EXEMemWriteMask(3 downto 0) <= "1000"; EXEMemWriteData <= x"00000000" &             rotatedData(31 downto 0);   
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';

            when 16#29# => -- SH
               if (calcMemAddr(1) = '1') then
                  EXEMemWriteMask(3 downto 0) <= "1100";
               else
                  EXEMemWriteData <= x"00000000" & x"0000" & rotatedData(31 downto 16);
                  EXEMemWriteMask(3 downto 0) <= "0011";
               end if;
               if (calcMemAddr(0) = '1') then
                  exceptionNew3        <= '1';
                  exceptionCode_3      <= x"5";
                  EXEMemWriteException <= '1';
               else
                  EXEMemWriteEnable <= '1';
               end if;
               
            when 16#2A# => -- SWL
               case (to_integer(calcMemAddr(1 downto 0))) is 
                  when 0 => EXEMemWriteMask(3 downto 0) <= "1111"; EXEMemWriteData <= x"00000000" & rotatedData(31 downto 0);
                  when 1 => EXEMemWriteMask(3 downto 0) <= "1110"; EXEMemWriteData <= x"00000000" & rotatedData(23 downto 0) & x"00";
                  when 2 => EXEMemWriteMask(3 downto 0) <= "1100"; EXEMemWriteData <= x"00000000" & rotatedData(15 downto 0) & x"0000";
                  when 3 => EXEMemWriteMask(3 downto 0) <= "1000"; EXEMemWriteData <= x"00000000" & rotatedData( 7 downto 0) & x"000000";
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';   

            when 16#2B# => -- SW
               EXEMemWriteMask(3 downto 0) <= "1111";
               if (calcMemAddr(1 downto 0) /= "00") then
                  exceptionNew3        <= '1';
                  exceptionCode_3      <= x"5";
                  EXEMemWriteException <= '1';
               else
                  EXEMemWriteEnable <= '1';
               end if;
               
            when 16#2C# => -- SDL
               EXEMem64Bit   <= '1';
               case (to_integer(calcMemAddr(2 downto 0))) is 
                  when 0 => EXEMemWriteMask <= "11111111"; EXEMemWriteData <= rotatedData(63 downto 0);
                  when 1 => EXEMemWriteMask <= "11101111"; EXEMemWriteData <= rotatedData(55 downto 0) & rotatedData(63 downto 56);
                  when 2 => EXEMemWriteMask <= "11001111"; EXEMemWriteData <= rotatedData(47 downto 0) & rotatedData(63 downto 48);
                  when 3 => EXEMemWriteMask <= "10001111"; EXEMemWriteData <= rotatedData(39 downto 0) & rotatedData(63 downto 40);
                  when 4 => EXEMemWriteMask <= "00001111"; EXEMemWriteData <= rotatedData(31 downto 0) & rotatedData(63 downto 32);
                  when 5 => EXEMemWriteMask <= "00001110"; EXEMemWriteData <= rotatedData(23 downto 0) & rotatedData(63 downto 24);
                  when 6 => EXEMemWriteMask <= "00001100"; EXEMemWriteData <= rotatedData(15 downto 0) & rotatedData(63 downto 16);
                  when 7 => EXEMemWriteMask <= "00001000"; EXEMemWriteData <= rotatedData( 7 downto 0) & rotatedData(63 downto 8);
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';
            
            when 16#2D# => -- SDR
               EXEMem64Bit   <= '1';
               case (to_integer(calcMemAddr(2 downto 0))) is 
                  when 0 => EXEMemWriteMask <= "00010000"; EXEMemWriteData <= rotatedData(55 downto 0) & rotatedData(63 downto 56);
                  when 1 => EXEMemWriteMask <= "00110000"; EXEMemWriteData <= rotatedData(47 downto 0) & rotatedData(63 downto 48);
                  when 2 => EXEMemWriteMask <= "01110000"; EXEMemWriteData <= rotatedData(39 downto 0) & rotatedData(63 downto 40);
                  when 3 => EXEMemWriteMask <= "11110000"; EXEMemWriteData <= rotatedData(31 downto 0) & rotatedData(63 downto 32);
                  when 4 => EXEMemWriteMask <= "11110001"; EXEMemWriteData <= rotatedData(23 downto 0) & rotatedData(63 downto 24);
                  when 5 => EXEMemWriteMask <= "11110011"; EXEMemWriteData <= rotatedData(15 downto 0) & rotatedData(63 downto 16);
                  when 6 => EXEMemWriteMask <= "11110111"; EXEMemWriteData <= rotatedData( 7 downto 0) & rotatedData(63 downto 8);
                  when 7 => EXEMemWriteMask <= "11111111"; EXEMemWriteData <= rotatedData(63 downto 0);
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';
            
               
            when 16#2E# => -- SWR
               case (to_integer(calcMemAddr(1 downto 0))) is 
                  when 0 => EXEMemWriteMask(3 downto 0) <= "0001"; EXEMemWriteData <= x"00000000" & x"000000" & rotatedData(31 downto 24);
                  when 1 => EXEMemWriteMask(3 downto 0) <= "0011"; EXEMemWriteData <= x"00000000" & x"0000" &   rotatedData(31 downto 16);
                  when 2 => EXEMemWriteMask(3 downto 0) <= "0111"; EXEMemWriteData <= x"00000000" & x"00" &     rotatedData(31 downto  8);
                  when 3 => EXEMemWriteMask(3 downto 0) <= "1111"; EXEMemWriteData <= x"00000000" &             rotatedData(31 downto  0);
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';    
            
            when 16#2F# => -- Cache
               EXECacheEnable <= '1';
            
            when 16#30# => -- LL
               EXELoadType <= LOADTYPE_DWORD;
               if (calcMemAddr(1 downto 0) /= "00") then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable      <= '1';
                  EXEllBit           <= '1';
                  exeCOP0WriteEnable <= '1';
                  EXECOP0Register    <= to_unsigned(17,5);
                  exeCOP0WriteValue(31 downto 0) <= 7x"0" & calcMemAddr(28 downto 4); -- todo: should be modified by TLB and region check
               end if; 

            when 16#31# => -- LWC1
               EXELoadType <= LOADTYPE_DWORD;
               if (COP1_enable = '0') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"B";
                  exception_COP    <= "01";
               else
                  ExeCOP1ReadEnable <= '1';
                  EXEReadEnable     <= '1';
               end if;

            when 16#32# => -- LWC2 -> NOP
               null;
               
            when 16#33# => -- LWC3 -> NOP 
               null; 

            when 16#34# => -- LLD 
               EXELoadType <= LOADTYPE_QWORD;
               EXEMem64Bit <= '1';
               if (calcMemAddr(2 downto 0) /= "000") then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable      <= '1';
                  EXEllBit           <= '1';
                  exeCOP0WriteEnable <= '1';
                  EXECOP0Register    <= to_unsigned(17,5);
                  exeCOP0WriteValue(31 downto 0) <= 7x"0" & calcMemAddr(28 downto 4); -- todo: should be modified by TLB and region check
               end if;             

            when 16#35# => -- LDC1 
               EXELoadType <= LOADTYPE_QWORD;
               EXEMem64Bit <= '1';
               if (COP1_enable = '0') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"B";
                  exception_COP    <= "01";
               else
                  ExeCOP1ReadEnable <= '1';
                  EXEReadEnable     <= '1';
               end if;

            when 16#37# => -- LD
               EXELoadType <= LOADTYPE_QWORD;
               EXEMem64Bit <= '1';
               if (calcMemAddr(2 downto 0) /= "000") then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if;                 
               
            when 16#38# => -- SC
               EXEMemWriteMask(3 downto 0) <= "1111";
               if (calcMemAddr(1 downto 0) /= "00") then
                  exceptionNew3        <= '1';
                  exceptionCode_3      <= x"5";
                  EXEMemWriteException <= '1';
               else
                  EXEresultWriteEnable <= '1';
                  EXEMemWriteEnable    <= llBit;
               end if;
               
            when 16#39# => -- SWC1 
               EXEMemWriteMask(3 downto 0) <= "1111";
               if (COP1_enable = '0') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"B";
                  exception_COP    <= "01";
               else
                  EXEMemWriteEnable            <= '1';
                  EXEMemWriteData(31 downto 0) <= byteswap32(decodeFPUValue2(31 downto 0));
                  if (fpuRegMode = '0' and decodeSource2(0) = '1') then
                     EXEMemWriteData(31 downto 0) <= byteswap32(decodeFPUValue2(63 downto 32));
                  end if;
               end if;
               
            when 16#3A# => -- SWC2 -> nop
               null;
               
            when 16#3B# => -- SWC3 -> NOP 
               null; 
               
            when 16#3C# => -- SCD 
               EXEMem64Bit     <= '1';
               EXEMemWriteMask <= "11111111";
               if (calcMemAddr(2 downto 0) /= "000") then
                  exceptionNew3        <= '1';
                  exceptionCode_3      <= x"5";
                  EXEMemWriteException <= '1';
               else
                  EXEresultWriteEnable <= '1';
                  EXEMemWriteEnable    <= llBit;
               end if;          
               
            when 16#3D# => -- SDC1 
               EXEMem64Bit     <= '1';
               EXEMemWriteMask <= "11111111";
               if (COP1_enable = '0') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"B";
                  exception_COP    <= "01";
               else
                  EXEMemWriteEnable <= '1';
                  EXEMemWriteData   <= byteswap32(decodeFPUValue2(63 downto 32)) & byteswap32(decodeFPUValue2(31 downto 0));
               end if;
               
            when 16#3F# => -- SD
               EXEMem64Bit     <= '1';
               EXEMemWriteMask <= "11111111";
               if (calcMemAddr(2 downto 0) /= "00") then
                  exceptionNew3        <= '1';
                  exceptionCode_3      <= x"5";
                  EXEMemWriteException <= '1';
               else
                  EXEMemWriteEnable <= '1';
               end if;
               
            when others => 
               -- synthesis translate_off
               report to_hstring(decodeOP);
               -- synthesis translate_on
               --report "Unknown opcode" severity failure; 
               exceptionNew3   <= '1';
               exceptionCode_3 <= x"A";
               EXEerror_instr  <= '1';
         
         end case;
             
      end if;
      
   end process;
   
   
   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         DIVstart    <= '0';
         error_instr <= '0';
      
         if (reset_93 = '1') then
         
            stall3                        <= '0';
            executeNew                    <= '0';
            executeIgnoreNext             <= '0';
            executeStallFromMEM           <= '0';

            resultWriteEnable             <= '0';
            executeBranchdelaySlot        <= '0';
            executeMemWriteEnable         <= '0';
            executeMemReadEnable          <= '0';
            executeCOP0WriteEnable        <= '0';
            executeCacheEnable            <= '0';
            llBit                         <= '0';
            hiloWait                      <= 0;
            
            hi                            <= unsigned(ss_in(3)); -- (others => '0');
            lo                            <= unsigned(ss_in(4)); -- (others => '0');
            
         elsif (ce_93 = '1') then
            
            -- load delay block
            if (stall3) then
            
               if (stall = "00100") then
                  executeStallFromMEM <= '0';
                  executeNew          <= '0';
               end if;

               if (writebackStallFromMEM = '1' and writebackNew = '1') then
                  stall3 <= '0';
               end if;
               
            end if;
            
            -- mul/div calc/wait
            if (hiloWait > 0) then
               hiloWait <= hiloWait - 1;
               if (hiloWait = 1) then
                  stall3     <= '0';
                  executeNew <= '1';
                  case (hilocalc) is
                     when HILOCALC_MULT | HILOCALC_MULTU => 
                        hi <= unsigned(resize(  signed(mulResult(63 downto 32)),64)); 
                        lo <= unsigned(resize(  signed(mulResult(31 downto 0)),64));
                     when HILOCALC_DMULT | HILOCALC_DMULTU => 
                        hi <= unsigned(mulResult(127 downto 64)); 
                        lo <= unsigned(mulResult(63 downto 0));
                     when HILOCALC_DIV | HILOCALC_DIVU => 
                        hi <= unsigned(resize(DIVremainder(31 downto  0), 64)); 
                        lo <= unsigned(resize(DIVquotient(31 downto 0), 64));
                     when HILOCALC_DDIV | HILOCALC_DDIVU => 
                        hi <= unsigned(DIVremainder(63 downto  0)); 
                        lo <= unsigned(DIVquotient(63 downto 0));
                  end case;
               end if;
            end if;
            
            -- FPU unstall
            execute_unstallFPUForward <= '0';
            
            if (FPU_command_done = '1') then
               if (decodeFPUForwardUse = '1') then
                  execute_unstallFPUForward <= '1';
               else
                  stall3     <= '0';
                  executeNew <= '1';
               end if;
            end if;
            
            if (execute_unstallFPUForward = '1') then
               stall3     <= '0';
               executeNew <= '1';
            end if;

            if (stall = 0) then
            
               executeNew              <= '0';
               executeCacheEnable      <= '0';
               
               resultData              <= resultDataMuxed64;    
               resultTarget            <= decodeTarget;
                  
               executeMem64Bit         <= EXEMem64Bit;
               executeMemWriteData     <= EXEMemWriteData;             
               executeMemWriteMask     <= EXEMemWriteMask;             
               executeMemAddress       <= calcMemAddr; 
               executeMemReadLastData  <= value2;              
               
               executeCOP0WriteValue   <= EXECOP0WriteValue; 

               executeBranchdelaySlot  <= EXEBranchdelaySlot;                
            
               if (exception = '1') then
                                                
                  stall3                        <= '0';
                  executeNew                    <= '0';
                  executeIgnoreNext             <= '0';
                     
                  resultWriteEnable             <= '0';
                  executeMemReadEnable          <= '0';
                  executeMemWriteEnable         <= '0';
                  executeCOP0WriteEnable        <= '0';
                  
               elsif (decodeNew = '1') then     
               
                  executeIgnoreNext             <= EXEIgnoreNext;
                   
                  
                  if (executeIgnoreNext = '1') then
                  
                     resultWriteEnable      <= '0';
                     executeCOP0WriteEnable <= '0';
                     executeCOP0ReadEnable  <= '0';
                     executeCacheEnable     <= '0';
                     executeMemReadEnable   <= '0';
                     executeMemWriteEnable  <= '0';
                  
                  else
               
                     executeNew                    <= '1';
                     
                     error_instr                   <= EXEerror_instr;
               
-- synthesis translate_off
                     pcOld2                        <= pcOld1;  
                     opcode2                       <= opcode1;
-- synthesis translate_on
                           
                     stall3                        <= stallNew3;
                           
                     -- from calculation
                     if (decodeTarget = 0) then
                        resultWriteEnable <= '0';
                     else
                        resultWriteEnable <= EXEresultWriteEnable;
                     end if;
                           
                     executeMemWriteEnable         <= EXEMemWriteEnable;  
   
                     executeLoadType               <= EXELoadType;   
                     executeMemReadEnable          <= EXEReadEnable; 
   
                     execute_ERET                  <= EXEERET;
                     executeCOP0WriteEnable        <= EXECOP0WriteEnable;     
                     executeCOP0ReadEnable         <= EXECOP0ReadEnable;     
                     executeCOP0Read64             <= EXECOP0Read64;     
                     executeCOP0Register           <= EXECOP0Register;
                     
                     executeCOP2WriteEnable        <= EXECOP2WriteEnable;     
                     executeCOP2ReadEnable         <= EXECOP2ReadEnable;     
                     executeCOP2Read64             <= EXECOP2Read64;     

                     llBit                         <= EXEllBit;  
                     
                     executeCOP1ReadEnable         <= ExeCOP1ReadEnable;

                     executeCacheEnable            <= EXECacheEnable;
                     executeCacheCommand           <= decodeSource2;
                     
                     execute_COP1_Target           <= decodeSource2;
                     
                     -- new mul/div
                     if (EXEcalcMULT = '1') then
                        hilocalc <= HILOCALC_MULT;
                        mulsign  <= '1';
                        mul1     <= std_logic_vector(resize(signed(value1(31 downto 0)), 64));
                        mul2     <= std_logic_vector(resize(signed(value2(31 downto 0)), 64));
                        hiloWait <= 4;
                        stall3   <= '1';
                     end if;
                     
                     if (EXEcalcMULTU = '1') then
                        hilocalc <= HILOCALC_MULTU;
                        mulsign  <= '0';
                        mul1     <= x"00000000" & std_logic_vector(value1(31 downto 0));
                        mul2     <= x"00000000" & std_logic_vector(value2(31 downto 0));
                        hiloWait <= 4;
                        stall3   <= '1';
                     end if;
                     
                     if (EXEcalcDMULT = '1') then
                        hilocalc <= HILOCALC_DMULT;
                        mulsign  <= '1';
                        mul1     <= std_logic_vector(value1);
                        mul2     <= std_logic_vector(value2);
                        hiloWait <= 7;
                        stall3   <= '1';
                     end if;
                     
                     if (EXEcalcDMULTU = '1') then
                        hilocalc <= HILOCALC_DMULTU;
                        mulsign  <= '0';
                        mul1     <= std_logic_vector(value1);
                        mul2     <= std_logic_vector(value2);
                        hiloWait <= 7;
                        stall3   <= '1';
                     end if;
                     
                     if (decodeFPUMULS = '1') then
                        mulsign  <= '0';
                        mul1 <= 40x"0" & '0' & std_logic_vector(decodeFPUValue1(22 downto 0));
                        mul2 <= 40x"0" & '0' & std_logic_vector(decodeFPUValue2(22 downto 0));
                        if (decodeFPUValue1(30 downto 23) > 0) then mul1(23) <= '1'; end if;
                        if (decodeFPUValue2(30 downto 23) > 0) then mul2(23) <= '1'; end if;
                     end if;
                     
                     if (decodeFPUMULD = '1') then
                        mulsign  <= '0';
                        mul1 <= 11x"0" & '0' & std_logic_vector(decodeFPUValue1(51 downto 0));
                        mul2 <= 11x"0" & '0' & std_logic_vector(decodeFPUValue2(51 downto 0));
                        if (decodeFPUValue1(62 downto 52) > 0) then mul1(52) <= '1'; end if;
                        if (decodeFPUValue2(62 downto 52) > 0) then mul2(52) <= '1'; end if;
                     end if;
                     
                     if (EXEcalcDIV = '1') then
                        DIVis32     <= '1';
                        hiloWait    <= 36;
                        stall3      <= '1';
                        DIVdividend <= resize(signed(value1(31 downto 0)), 65);
                        DIVdivisor  <= resize(signed(value2(31 downto 0)), 65);
                        hilocalc    <= HILOCALC_DIV;
                        DIVstart    <= '1';
                     end if;
                     
                      if (EXEcalcDDIV = '1') then
                        DIVis32     <= '0';
                        hiloWait    <= 68;
                        stall3      <= '1';
                        DIVdividend <= resize(signed(value1), 65);
                        DIVdivisor  <= resize(signed(value2), 65);
                        hilocalc    <= HILOCALC_DDIV;
                        DIVstart    <= '1';
                     end if;
                     
                     if (EXEcalcDIVU = '1') then
                        DIVis32     <= '1';
                        hiloWait    <= 36;
                        stall3      <= '1';
                        DIVdividend <= '0' & x"00000000" & signed(value1(31 downto 0));
                        DIVdivisor  <= '0' & x"00000000" & signed(value2(31 downto 0));
                        hilocalc    <= HILOCALC_DIVU;
                        DIVstart    <= '1';
                     end if;
                     
                     if (EXEcalcDDIVU = '1') then
                        DIVis32     <= '0';
                        hiloWait    <= 68;
                        stall3      <= '1';
                        DIVdividend <= '0' & signed(value1);
                        DIVdivisor  <= '0' & signed(value2);
                        hilocalc    <= HILOCALC_DDIVU;
                        DIVstart    <= '1';
                     end if;
                     
                     if (EXEhiUpdate = '1') then hi <= value1; end if;
                     if (EXEloUpdate = '1') then lo <= value1; end if;
                     
                     if (EXEReadEnable = '1' or EXECOP0ReadEnable = '1' or EXECOP2ReadEnable = '1') then
                        stall3              <= '1';
                        executeStallFromMEM <= '1';
                     end if;
                     
                     if (FPU_command_ena = '1' and FPU_command_done = '0') then
                        stall3 <= '1';
                     end if;
                     
                     if (decFPUForwardUse = '1') then
                        stall3 <= '1';
                        if (FPU_command_done = '1' or FPU_command_ena = '0') then
                           execute_unstallFPUForward <= '1';
                        end if;
                     end if;
                     
                  end if;
                  
               end if;
               
               
            end if;

         end if;
         
      end if;
   end process;
   
   
--##############################################################
--############################### stage 4
--##############################################################

   icpu_datacache : entity work.cpu_datacache
   port map
   (
      clk93             => clk93,
      clk2x             => clk2x,
      reset_93          => reset_93,
      ce_93             => ce_93,
      stall             => stall,
      stall4            => stall4,
      
      ram_request       => datacache_request,
      ram_reqAddr       => datacache_reqAddr,
      ram_active        => datacache_active,
      ram_grant         => rdram_granted2X,
      ram_done          => mem_finished_read,
      ram_addr          => mem_address(28 downto 0),
      ddr3_DOUT         => ddr3_DOUT,      
      ddr3_DOUT_READY   => ddr3_DOUT_READY,
      
      writeback_ena     => datacache_wb_ena,  
      writeback_addr    => datacache_wb_addr, 
      writeback_data    => datacache_wb_data,
      writeback_done    => mem_finished_write,
      
      tag_addr          => EXECacheAddr,
      
      read_ena          => datacache_readena,
      RW_addr           => datacache_addr,
      RW_64             => executeMem64Bit,
      read_done         => datacache_readdone,
      read_data         => datacache_data_out,
      
      write_ena         => datacache_writeena,
      write_be          => executeMemWriteMask,
      write_data        => std_logic_vector(executeMemWriteData),
      write_done        => datacache_writedone,
      
      CacheCommandEna   => cache_commandEnable,
      CacheCommand      => executeCacheCommand,
      CacheCommandAddr  => executeMemAddress(31 downto 0),
      CachecommandStall => datacache_CmdStall,
      CachecommandDone  => datacache_CmdDone,    
      
      SS_reset          => SS_reset
   );

   stall4Masked <= stall(4 downto 3) & (stall(2) and (not executeStallFromMEM)) & stall(1 downto 0);
   
   process (all)
      variable skipmem : std_logic;
   begin
   
      stallNew4            <= stall4;
            
      mem4_request         <= '0';
      mem4_req64           <= executeMem64Bit;
      mem4_address         <= executeMemAddress(31 downto 0);
      mem4_rnw             <= '1';
      mem4_dataWrite       <= std_logic_vector(executeMemWriteData);
      mem4_writeMask       <= executeMemWriteMask;
      
      datacache_writeena   <= '0';
      datacache_readena    <= '0';
      
      datacache_addr   <= executeMemAddress(31 downto 0);
      if (executeMemReadEnable = '1') then
         if (executeLoadType = LOADTYPE_LEFT or executeLoadType = LOADTYPE_RIGHT) then 
            datacache_addr(1 downto 0) <= "00";
         end if;
         if (executeLoadType = LOADTYPE_LEFT64 or executeLoadType = LOADTYPE_RIGHT64) then 
            datacache_addr(2 downto 0) <= "000";
         end if;
      end if;
      
      -- ############
      -- Load/Store
      -- ############
      
      if (stall4Masked = 0 and executeNew = '1') then
      
         if (executeMemWriteEnable = '1') then
            skipmem := '0';
         
            if (to_integer(unsigned(executeMemAddress(31 downto 29))) = 4 and privilegeMode = "00" and DATACACHEON_intern = '1') then
               datacache_writeena <= '1';
               skipmem            := '1';
               if (datacache_writedone = '0') then
                  stallNew4      <= '1';
               end if;
            end if;
            
            if (skipmem = '0') then
               mem4_request   <= '1';
               stallNew4      <= '1';
            end if;
            
            mem4_rnw       <= '0';
            if (executeMem64Bit = '1') then
               mem4_address(2 downto 0) <= "000";
            else
               mem4_address(1 downto 0) <= "00";
            end if;
         
         end if;
         
         if (executeMemReadEnable = '1') then
            skipmem := '0';
            
            if (to_integer(unsigned(executeMemAddress(31 downto 29))) = 4 and privilegeMode = "00" and DATACACHEON_intern = '1') then
               datacache_readena  <= '1';
               skipmem            := '1';
               if (datacache_readdone = '0') then
                  stallNew4      <= '1';
               end if;
            end if;

            if (skipmem = '0') then
               mem4_request   <= '1';
               stallNew4      <= '1';
            end if;
            
            if (executeLoadType = LOADTYPE_LEFT or executeLoadType = LOADTYPE_RIGHT) then 
               mem4_address(1 downto 0) <= "00";
            end if;
            if (executeLoadType = LOADTYPE_LEFT64 or executeLoadType = LOADTYPE_RIGHT64) then 
               mem4_address(2 downto 0) <= "000";
            end if;
         
         end if;
         
      end if;
      
   end process;
   
   read4_dataReadData   <= unsigned(datacache_data_out) when (writeback_UseCache = '1' or datacache_readena = '1') else unsigned(mem_finished_dataRead);
   read4_dataReadRot64  <= byteswap32(read4_dataReadData(31 downto 0)) & byteswap32(read4_dataReadData(63 downto 32));
   read4_dataReadRot32  <= byteswap32(read4_dataReadData(31 downto 0));
   
   read4_Addr         <= writebackReadAddress         when (stall4 = '1') else executeMemAddress(31 downto 0);
   read4_oldData      <= writebackReadLastData        when (stall4 = '1') else executeMemReadLastData;
   read4_cop1_readEna <= writeback_COP1_ReadEnable    when (stall4 = '1') else executeCOP1ReadEnable;
   read4_cop1_target  <= cop1_stage4_target           when (stall4 = '1') else execute_COP1_Target;
   read4_useLoadType  <= writebackLoadType            when (stall4 = '1') else executeLoadType;       
   read4_useTarget    <= writebackTarget              when (stall4 = '1') else resultTarget;
   
   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         DATACACHEON_intern <= DATACACHEON;
      
         if (reset_93 = '1') then
         
            stall4                           <= '0';
            writebackNew                     <= '0';
            writebackStallFromMEM            <= '0';                  
            writebackWriteEnable             <= '0';
            cop1_stage4_writeEnable          <= '0';
            COP2Latch                        <= (others => '0');
            
         elsif (ce_93 = '1') then
         
            stall4                  <= stallNew4;    
            
            cop1_stage4_writeEnable <= '0';

            if (stall4Masked = 0) then
            
               writebackNew   <= '0';
            
               if (executeNew = '1') then
               
                  writebackStallFromMEM        <= executeStallFromMEM;
               
-- synthesis translate_off
                  pcOld3                       <= pcOld2;
                  opcode3                      <= opcode2;
                  hi_1                         <= hi;
                  lo_1                         <= lo;
-- synthesis translate_on
               
                  writebackTarget              <= resultTarget;
                  writebackData                <= resultData;
                  writebackReadLastData        <= executeMemReadLastData;

                  writebackWriteEnable         <= resultWriteEnable;
                  writeback_UseCache           <= datacache_readena or datacache_writeena or executeCacheEnable;
                  
                  writeback_COP1_ReadEnable    <= executeCOP1ReadEnable;
                  cop1_stage4_target           <= execute_COP1_Target;
                  
                  if (executeMemWriteEnable = '1') then
                  
                  elsif (executeMemReadEnable = '1') then
                  
                     writebackLoadType       <= executeLoadType;
                     writebackReadAddress    <= executeMemAddress(31 downto 0);

                  else

                     writebackNew         <= '1';
                     
                  end if;
                  
                  if (executeCOP0ReadEnable = '1') then
                     if (resultTarget > 0) then
                        writebackWriteEnable <= '1';
                     end if;
                     
                     if (executeCOP0Read64 = '1') then
                        writebackData <= COP0ReadValue;
                     else
                        writebackData <= unsigned(resize(signed(COP0ReadValue(31 downto 0)), 64));
                     end if;
                  end if;
                  
                  if (executeCOP2ReadEnable = '1') then
                     if (resultTarget > 0) then
                        writebackWriteEnable <= '1';
                     end if;
                     
                     if (executeCOP2Read64 = '1') then
                        writebackData <= COP2Latch;
                     else
                        writebackData <= unsigned(resize(signed(COP2Latch(31 downto 0)), 64));
                     end if;
                  end if;
                  
                  if (executeCOP2WriteEnable = '1') then
                     COP2Latch <= executeMemReadLastData;
                  end if;

                  if (datacache_CmdStall = '1') then
                     stall4 <= '1';
                  end if;

               end if;
               
            end if;
            
            if (datacache_CmdDone = '1') then
               stall4        <= '0';
               writebackNew  <= '1';
            end if;
            
            if ((writeback_UseCache = '0' and mem_finished_write = '1') or datacache_writedone = '1') then
               stall4        <= '0';
               writebackNew  <= '1';
            end if;
            
            if ((writeback_UseCache = '0' and mem_finished_read = '1') or datacache_readdone = '1') then
            
               stall4        <= '0';
               writebackNew  <= '1';
               
               cop1_stage4_data <= byteswap32(read4_dataReadData(31 downto 0)) & byteswap32(read4_dataReadData(63 downto 32));
               
               if (read4_cop1_readEna = '1') then
                  cop1_stage4_writeEnable <= '1';
                  cop1_stage4_writeMask   <= "11";
                  if (fpuRegMode = '1') then
                     if (read4_useLoadType = LOADTYPE_DWORD) then
                        cop1_stage4_data(31 downto 0) <= byteswap32(read4_dataReadData(31 downto 0));
                        cop1_stage4_writeMask         <= "01";
                     end if;
                  else
                     cop1_stage4_target(0) <= '0';
                     if (read4_useLoadType = LOADTYPE_DWORD) then
                        if (read4_cop1_target(0) = '1') then
                           cop1_stage4_data(63 downto 32) <= byteswap32(read4_dataReadData(31 downto 0));
                           cop1_stage4_writeMask          <= "10";
                        else
                           cop1_stage4_data(31 downto 0) <= byteswap32(read4_dataReadData(31 downto 0));
                           cop1_stage4_writeMask         <= "01";
                        end if;
                     end if;
                  end if;
               end if;
               
               if (read4_useTarget > 0 and read4_cop1_readEna = '0') then
                  writebackWriteEnable <= '1';
               end if;
               
               case (read4_useLoadType) is
                  
                  when LOADTYPE_SBYTE => writebackData <= unsigned(resize(signed(read4_dataReadData(7 downto 0)), 64));
                  when LOADTYPE_SWORD => writebackData <= unsigned(resize(signed(byteswap16(read4_dataReadData(15 downto 0))), 64));
                  when LOADTYPE_LEFT =>
                     case (to_integer(read4_Addr(1 downto 0))) is
                        when 3 => writebackData <= unsigned(resize(signed(read4_dataReadRot32( 7 downto 0)) & signed(read4_oldData(23 downto 0)), 64));
                        when 2 => writebackData <= unsigned(resize(signed(read4_dataReadRot32(15 downto 0)) & signed(read4_oldData(15 downto 0)), 64));
                        when 1 => writebackData <= unsigned(resize(signed(read4_dataReadRot32(23 downto 0)) & signed(read4_oldData( 7 downto 0)), 64)); 
                        when 0 => writebackData <= unsigned(resize(signed(read4_dataReadRot32(31 downto 0)), 64));
                        when others => null;
                     end case;
                        
                  when LOADTYPE_DWORD  => writebackData <= unsigned(resize(signed(byteswap32(read4_dataReadData(31 downto 0))), 64));
                  when LOADTYPE_DWORDU => writebackData <= x"00000000" & byteswap32(read4_dataReadData(31 downto 0));
                  when LOADTYPE_BYTE  => writebackData <= x"00000000" & x"000000" & read4_dataReadData(7 downto 0);
                  when LOADTYPE_WORD  => writebackData <= x"00000000" & x"0000" & byteswap16(read4_dataReadData(15 downto 0));
                  when LOADTYPE_RIGHT =>
                     case (to_integer(read4_Addr(1 downto 0))) is
                        when 3 => writebackData <= unsigned(resize(signed(read4_dataReadRot32(31 downto 0)), 64));
                        when 2 => writebackData <= unsigned(resize(signed(read4_oldData(31 downto 24)) & signed(read4_dataReadRot32(31 downto  8)), 64));
                        when 1 => writebackData <= unsigned(resize(signed(read4_oldData(31 downto 16)) & signed(read4_dataReadRot32(31 downto 16)), 64));
                        when 0 => writebackData <= unsigned(resize(signed(read4_oldData(31 downto  8)) & signed(read4_dataReadRot32(31 downto 24)), 64));
                        when others => null;
                     end case;
                     
                  when LOADTYPE_QWORD =>  writebackData <= byteswap32(read4_dataReadData(31 downto 0)) & byteswap32(read4_dataReadData(63 downto 32));
                  
                  when LOADTYPE_LEFT64 => 
                     case (to_integer(read4_Addr(2 downto 0))) is
                        when 7 => writebackData <= read4_dataReadRot64( 7 downto 0) & read4_oldData(55 downto 0);
                        when 6 => writebackData <= read4_dataReadRot64(15 downto 0) & read4_oldData(47 downto 0);
                        when 5 => writebackData <= read4_dataReadRot64(23 downto 0) & read4_oldData(39 downto 0);
                        when 4 => writebackData <= read4_dataReadRot64(31 downto 0) & read4_oldData(31 downto 0);
                        when 3 => writebackData <= read4_dataReadRot64(39 downto 0) & read4_oldData(23 downto 0);
                        when 2 => writebackData <= read4_dataReadRot64(47 downto 0) & read4_oldData(15 downto 0);
                        when 1 => writebackData <= read4_dataReadRot64(55 downto 0) & read4_oldData( 7 downto 0);
                        when 0 => writebackData <= read4_dataReadRot64;
                        when others => null;
                     end case;
                  
                  when LOADTYPE_RIGHT64 =>
                     case (to_integer(read4_Addr(2 downto 0))) is
                        when 7 => writebackData <= read4_dataReadRot64;
                        when 6 => writebackData <= read4_oldData(63 downto 56) & read4_dataReadRot64(63 downto  8);
                        when 5 => writebackData <= read4_oldData(63 downto 48) & read4_dataReadRot64(63 downto 16);
                        when 4 => writebackData <= read4_oldData(63 downto 40) & read4_dataReadRot64(63 downto 24);
                        when 3 => writebackData <= read4_oldData(63 downto 32) & read4_dataReadRot64(63 downto 32);
                        when 2 => writebackData <= read4_oldData(63 downto 24) & read4_dataReadRot64(63 downto 40);
                        when 1 => writebackData <= read4_oldData(63 downto 16) & read4_dataReadRot64(63 downto 48);
                        when 0 => writebackData <= read4_oldData(63 downto  8) & read4_dataReadRot64(63 downto 56);
                        when others => null;
                     end case;
                     
               end case; 
               
            end if; -- mem_finished_read

         end if; -- ce
         

      end if;
   end process;
   
   
--##############################################################
--############################### stage 5
--##############################################################
   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
-- synthesis translate_off
         cpu_done <= '0';
-- synthesis translate_on
         
         debugTmr <= debugTmr + 1;

         if (reset_93 = '1') then
            
            debugCnt             <= (others => '0');
            debugSum             <= (others => '0');
            debugTmr             <= (others => '0');
         
         elsif (ce_93 = '1') then
            
            if (stall4Masked = 0 and writebackNew = '1') then
            
-- synthesis translate_off
               pcOld4               <= pcOld3;
               opcode4              <= opcode3;
               hi_2                 <= hi_1;
               lo_2                 <= lo_1;
-- synthesis translate_on
               
               -- export
               if (writebackWriteEnable = '1') then 
                  if (writebackTarget > 0) then
-- synthesis translate_off
                     regs(to_integer(writebackTarget)) <= writebackData;
-- synthesis translate_on
                     debugSum <= debugSum + writebackData(31 downto 0);
                  end if;
               end if;
               debugCnt          <= debugCnt + 1;
-- synthesis translate_off

               cpu_done          <= '1';
               cpu_export.pc     <= pcOld4;
               cpu_export.opcode <= opcode4;
               cpu_export.hi     <= hi_2;
               cpu_export.lo     <= lo_2;
               for i in 0 to 31 loop
                  cpu_export.regs(i)    <= regs(i);
                  cpu_export.FPUregs(i) <= FPUregs(i);
               end loop;
               cop0_export_1       <= cop0_export;
               cpu_export.cop0regs <= cop0_export_1;
               
               csr_export_1        <= csr_export;
               csr_export_2        <= csr_export_1;
               cpu_export.csr      <= 7x"0" & csr_export_2;
               
-- synthesis translate_on
               debugwrite <= '1';
               if (debugCnt(31) = '1' and debugSum(31) = '1' and debugTmr(31) = '1' and writebackTarget = 0) then
                  debugwrite <= '0';
               end if;
               
            end if;
             
         end if;
         
         -- export
-- synthesis translate_off
         if (ss_regs_load = '1') then
            regs(to_integer(ss_regs_addr)) <= unsigned(ss_regs_data);
         end if;          
         if (ss_FPUregs_load = '1') then
            FPUregs(to_integer(ss_FPUregs_addr)) <= unsigned(ss_FPUregs_data);
         end if; 
         
         if (FPUregs_wren_a(0) = '1') then
            FPUregs(to_integer(unsigned(FPUregs_address_a)))(31 downto 0) <= unsigned(FPUregs_data_a(31 downto 0));
         end if;        
         
         if (FPUregs_wren_a(1) = '1') then
            FPUregs(to_integer(unsigned(FPUregs_address_a)))(63 downto 32) <= unsigned(FPUregs_data_a(63 downto 32));
         end if;
-- synthesis translate_on
         
      end if;
   end process;

--##############################################################
--############################### submodules
--##############################################################
   
   
   icop0 : entity work.cpu_cop0
   port map
   (
      clk93             => clk93,
      ce                => ce_93,   
      stall             => stall,
      stall4Masked      => stall4Masked,
      executeNew        => executeNew,
      reset             => reset_93,
      
      error_exception   => error_exception,

      irqRequest        => irqRequest,
      irqTrigger        => irqTrigger,
      decode_irq        => decode_irq,

-- synthesis translate_off
      cop0_export       => cop0_export,
-- synthesis translate_on

      eret              => execute_ERET,
      exception3        => exceptionNew3,
      exception1        => exceptionNew1,
      exceptionFPU      => exceptionFPU,
      exceptionCode_1   => "0000", -- todo
      exceptionCode_3   => exceptionCode_3,
      exception_COP     => exception_COP,
      isDelaySlot       => executeBranchdelaySlot,
      pcOld1            => PCold1,
      
      eretPC            => eretPC,
      exceptionPC       => exceptionPC,
      exception         => exception,   
      
      COP1_enable       => COP1_enable,
      COP2_enable       => COP2_enable,
      fpuRegMode        => fpuRegMode,
      privilegeMode     => privilegeMode,

      writeEnable       => executeCOP0WriteEnable,
      regIndex          => executeCOP0Register,
      writeValue        => executeCOP0WriteValue,
      readValue         => COP0ReadValue,
      
      SS_reset          => SS_reset,    
      SS_DataWrite      => SS_DataWrite,
      SS_Adr            => SS_Adr,      
      SS_wren_CPU       => SS_wren_CPU, 
      SS_rden_CPU       => SS_rden_CPU 
   );
   
   icpu_mul : entity work.cpu_mul
   port map
   (
      clk       => clk93,
      sign      => mulsign,
      value1_in => mul1,
      value2_in => mul2,
      result    => mulResult
   );
   
   idivider : entity work.divider
   port map
   (
      clk       => clk93,      
      start     => DIVstart,
      is32      => DIVis32,
      done      => open,      
      busy      => open,
      dividend  => DIVdividend, 
      divisor   => DIVdivisor,  
      quotient  => DIVquotient, 
      remainder => DIVremainder
   );
   
   icpu_FPU : entity work.cpu_FPU
   port map
   (
      clk93             => clk93,         
      reset             => reset_93, 
      error_FPU         => error_FPU,
      
      -- synthesis translate_off
      csr_export        => csr_export,
      -- synthesis translate_on
      
      fpuRegMode        => fpuRegMode,      
                                         
      command_ena       => FPU_command_ena,
      command_code      => opcode1,  
      command_op1       => decodeFPUValue1,  
      command_op2       => decodeFPUValue2,   
      command_done      => FPU_command_done,
      
      transfer_ena      => FPU_TransferEna,
      transfer_code     => decodeSource1(3 downto 0),
      transfer_RD       => decodeRD,
      transfer_value    => value2,
      transfer_data     => FPU_TransferData,
      
      mul_result        => unsigned(mulResult),
      
      exceptionFPU      => exceptionFPU,
      FPU_CF            => FPU_CF,
                                      
      FPUWriteTarget    => FPUWriteTarget,
      FPUWriteData      => FPUWriteData,  
      FPUWriteEnable    => FPUWriteEnable,
      FPUWriteMask      => FPUWriteMask
   );
   
--##############################################################
--############################### savestates
--##############################################################

   SS_idle <= '1';

   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         ss_regs_load    <= '0';
         ss_FPUregs_load <= '0';
      
         if (SS_reset = '1' and debugwrite = '1') then
         
            for i in 0 to 31 loop
               ss_in(i) <= (others => '0');
            end loop;
            
            ss_in(0)  <= x"FFFFFFFFBFC00000"; -- PC
            
            ss_regs_loading <= '1';
            ss_regs_addr    <= (others => '0');
            ss_regs_data    <= (others => '0');
            ss_FPUregs_addr <= (others => '0');
            ss_FPUregs_data <= (others => '0');
            
         elsif (SS_wren_CPU = '1' and SS_Adr < 32) then
            ss_in(to_integer(SS_Adr)) <= SS_DataWrite;
         elsif (SS_wren_CPU = '1' and SS_Adr >= 32 and SS_Adr < 64) then
            ss_regs_load <= '1';
            ss_regs_addr <= SS_Adr(4 downto 0);
            ss_regs_data <= SS_DataWrite;
         elsif (SS_wren_CPU = '1' and SS_Adr >= 96 and SS_Adr < 128) then
            ss_FPUregs_load <= '1';
            ss_FPUregs_addr <= SS_Adr(4 downto 0);
            ss_FPUregs_data <= SS_DataWrite;
         end if;
         
         if (ss_regs_loading = '1') then
            ss_regs_load    <= '1';
            ss_regs_addr    <= ss_regs_addr + 1;            
            ss_FPUregs_load <= '1';
            ss_FPUregs_addr <= ss_regs_addr + 1;
            if (ss_regs_addr = 31) then
               ss_regs_loading <= '0';
            end if;
         end if;
      
         --SS_idle <= '0';
         --if (hiloWait = 0 and blockIRQ = '0' and (irqRequest = '0' or cop0_SR(0) = '0') and mem_done = '0') then
         --   SS_idle <= '1';
         --end if;
      
         --regsSS_rden <= '0';
         --if (SS_rden_CPU = '1' and SS_Adr >= 32 and SS_Adr < 64) then
         --   regsSS_address_b <= std_logic_vector(SS_Adr(4 downto 0));
         --   regsSS_rden      <= '1';
         --end if;
         --
         --if (regsSS_rden = '1') then
         --   SS_DataRead_CPU <= regsSS_q_b;
         --elsif (SS_rden_CPU = '1' and SS_Adr < 31) then
         --   SS_DataRead_CPU <= ss_out(to_integer(SS_Adr));
         --end if;
      
      end if;
   end process;
   
--##############################################################
--############################### debug
--##############################################################

   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         error_stall <= '0';
      
         if (reset_93 = '1') then
         
            debugStallcounter <= (others => '0');
            
-- synthesis translate_off
            stallcountNo      <= 0;
            stallcount1       <= 0;
            stallcount3       <= 0;
            stallcount4       <= 0;
            stallcountDMA     <= 0;
-- synthesis translate_on
      
         elsif (ce_93 = '1') then
         
            if (stall = 0) then
               debugStallcounter <= (others => '0');
            elsif (cpuPaused = '0') then  
               debugStallcounter <= debugStallcounter + 1;
            end if;         
            
            if (debugStallcounter(12) = '1') then
               error_stall       <= '1';
            end if;
            
-- synthesis translate_off
            
            if (stallcountNo = 0 and stallcount4 = 0 and stallcount3 = 0 and stallcount1 = 0 and stallcountDMA = 0) then
               stallcountNo <= 0;
            end if;
            
            -- performance counters
            if (stall = 0) then
               stallcountNo <= stallcountNo + 1;
            elsif (stall4 = '1') then
               stallcount4 <= stallcount4 + 1;
            elsif (stall3 = '1') then
               stallcount3 <= stallcount3 + 1;
            elsif (stall1 = '1') then
               stallcount1 <= stallcount1 + 1;
            end if;
            
         else
            
            stallcountDMA <= stallcountDMA + 1;
            
-- synthesis translate_on
            
         end if;
         
      end if;
   end process;
   
   

end architecture;





