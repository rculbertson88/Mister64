library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;    

library mem;

use work.pexport.all;

entity cpu_cop0 is
   port 
   (
      clk93             : in  std_logic;
      ce                : in  std_logic;
      stall             : in  unsigned(4 downto 0);
      stall4Masked      : in  unsigned(4 downto 0);
      executeNew        : in  std_logic;
      reset             : in  std_logic;
      
      error_exception   : out std_logic := '0';
      
      irqRequest        : in  std_logic;
      irqTrigger        : out std_logic;
      decode_irq        : in  std_logic;

-- synthesis translate_off
      cop0_export       : out tExportRegs := (others => (others => '0'));
-- synthesis translate_on
                    
      eret              : in  std_logic;
      exception3        : in  std_logic;
      exception1        : in  std_logic;
      exceptionFPU      : in  std_logic;
      exceptionCode_1   : in  unsigned(3 downto 0);
      exceptionCode_3   : in  unsigned(3 downto 0);
      exception_COP     : in  unsigned(1 downto 0);
      isDelaySlot       : in  std_logic;                   
      pcOld1            : in  unsigned(63 downto 0);
            
      eretPC            : out unsigned(63 downto 0) := (others => '0');
      exceptionPC       : out unsigned(63 downto 0) := (others => '0');
      exception         : out std_logic := '0';
      
      COP1_enable       : out std_logic;
      COP2_enable       : out std_logic;
      fpuRegMode        : out std_logic;
      privilegeMode     : out unsigned(1 downto 0) := (others => '0');
                        
      writeEnable       : in  std_logic;
      regIndex          : in  unsigned(4 downto 0);
      writeValue        : in  unsigned(63 downto 0);
      readValue         : out unsigned(63 downto 0) := (others => '0');
      
      SS_reset          : in  std_logic;
      SS_DataWrite      : in  std_logic_vector(63 downto 0);
      SS_Adr            : in  unsigned(11 downto 0);
      SS_wren_CPU       : in  std_logic;
      SS_rden_CPU       : in  std_logic
   );
end entity;

architecture arch of cpu_cop0 is
     
   signal COP0_0_INDEX_tlbEntry           : unsigned(5 downto 0) := (others => '0');
   signal COP0_0_INDEX_probefailure       : std_logic := '0';
   signal COP0_1_RANDOM                   : unsigned(5 downto 0) := (others => '0');
   signal COP0_2_ENTRYLO0                 : unsigned(29 downto 0) := (others => '0');
   signal COP0_3_ENTRYLO1                 : unsigned(29 downto 0) := (others => '0');
   signal COP0_4_CONTEXT                  : unsigned(63 downto 0) := (others => '0');
   signal COP0_5_PAGEMASK                 : unsigned(11 downto 0) := (others => '0');
   signal COP0_6_WIRED                    : unsigned(5 downto 0)  := (others => '0');
   signal COP0_8_BADVIRTUALADDRESS        : unsigned(63 downto 0) := (others => '0');
   signal COP0_9_COUNT                    : unsigned(32 downto 0) := (others => '0');
   signal COP0_10_ENTRYHI_addressSpaceID  : unsigned(7 downto 0) := (others => '0'); 
   signal COP0_10_ENTRYHI_virtualAddress  : unsigned(26 downto 0) := (others => '0'); 
   signal COP0_10_ENTRYHI_region          : unsigned(1 downto 0) := (others => '0'); 
   signal COP0_11_COMPARE                 : unsigned(31 downto 0) := (others => '0');  
   signal COP0_12_SR_interruptEnable      : std_logic := '0';
   signal COP0_12_SR_exceptionLevel       : std_logic := '0';
   signal COP0_12_SR_errorLevel           : std_logic := '0';
   signal COP0_12_SR_privilegeMode        : unsigned(1 downto 0)  := (others => '0');
   signal COP0_12_SR_userExtendedAddr     : std_logic := '0';
   signal COP0_12_SR_supervisorAddr       : std_logic := '0';
   signal COP0_12_SR_kernelExtendedAddr   : std_logic := '0';
   signal COP0_12_SR_interruptMask        : unsigned(7 downto 0)  := (others => '0');
   signal COP0_12_SR_de                   : std_logic := '0';
   signal COP0_12_SR_ce                   : std_logic := '0';
   signal COP0_12_SR_condition            : std_logic := '0';
   signal COP0_12_SR_softReset            : std_logic := '0';
   signal COP0_12_SR_tlbShutdown          : std_logic := '0';
   signal COP0_12_SR_vectorLocation       : std_logic := '0';
   signal COP0_12_SR_instructionTracing   : std_logic := '0';
   signal COP0_12_SR_reverseEndian        : std_logic := '0';
   signal COP0_12_SR_floatingPointMode    : std_logic := '0';
   signal COP0_12_SR_lowPowerMode         : std_logic := '0';
   signal COP0_12_SR_enable_cop0          : std_logic := '0';
   signal COP0_12_SR_enable_cop1          : std_logic := '0';
   signal COP0_12_SR_enable_cop2          : std_logic := '0';
   signal COP0_12_SR_enable_cop3          : std_logic := '0';
   signal COP0_13_CAUSE_exceptionCode     : unsigned(4 downto 0) := (others => '0'); 
   signal COP0_13_CAUSE_interruptPending  : unsigned(7 downto 0) := (others => '0'); 
   signal COP0_13_CAUSE_coprocessorError  : unsigned(1 downto 0) := (others => '0'); 
   signal COP0_13_CAUSE_branchDelay       : std_logic := '0';
   signal COP0_14_EPC                     : unsigned(63 downto 0) := (others => '0'); 
   signal COP0_16_CONFIG_cacheAlgoKSEG0   : unsigned(1 downto 0) := (others => '0'); 
   signal COP0_16_CONFIG_cu               : unsigned(1 downto 0) := (others => '0'); 
   signal COP0_16_CONFIG_bigEndian        : std_logic := '0';
   signal COP0_16_CONFIG_sysadWBPattern   : unsigned(3 downto 0) := (others => '0'); 
   signal COP0_16_CONFIG_systemClockRatio : unsigned(2 downto 0) := (others => '0'); 
   signal COP0_17_LOADLINKEDADDRESS       : unsigned(63 downto 0) := (others => '0'); 
   signal COP0_18_WATCHLO                 : unsigned(31 downto 0) := (others => '0');   
   signal COP0_19_WATCHHI                 : unsigned(3 downto 0) := (others => '0');   
   signal COP0_20_XCONTEXT                : unsigned(63 downto 4) := (others => '0');
   signal COP0_26_PARITYERROR             : unsigned(7 downto 0) := (others => '0');  
   signal COP0_28_TAGLO_primaryCacheState : unsigned(1 downto 0) := (others => '0');     
   signal COP0_28_TAGLO_physicalAddress   : unsigned(19 downto 0) := (others => '0');     
   signal COP0_30_EPCERROR                : unsigned(63 downto 0) := (others => '0'); 
      
   signal COP0_LATCH                      : unsigned(63 downto 0) := (others => '0');   
   
   signal bit64mode                       : std_logic := '0';
   
   signal nextEPC_1                       : unsigned(63 downto 0) := (others => '0');
   signal isDelaySlot_1                   : std_logic := '0';
   
   signal cop0Written6                    : integer range 0 to 2 := 0;
   signal cop0Written9                    : integer range 0 to 3 := 0;
   
   --signal irq_offCount                    : unsigned(13 downto 0);
   
   -- savestates
   type t_ssarray is array(0 to 31) of unsigned(63 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  

begin 

   COP1_enable   <= COP0_12_SR_enable_cop1;
   COP2_enable   <= COP0_12_SR_enable_cop2;
   fpuRegMode    <= COP0_12_SR_floatingPointMode;
   privilegeMode <= COP0_12_SR_privilegeMode;
   
   process (all)
   begin
      
      readValue <= (others => '0');
   
      case (to_integer(regIndex)) is
            
         when 0 =>
            readValue(5 downto 0) <= COP0_0_INDEX_tlbEntry;
            readValue(31)         <= COP0_0_INDEX_probefailure;
            
         when 1 => readValue(5 downto 0)   <= COP0_1_RANDOM;
         when 2 => readValue(29 downto 0)  <= COP0_2_ENTRYLO0;
         when 3 => readValue(29 downto 0)  <= COP0_3_ENTRYLO1;
         when 4 => readValue               <= COP0_4_CONTEXT;
         when 5 => readValue(24 downto 13) <= COP0_5_PAGEMASK;
         when 6 => readValue(5 downto 0)   <= COP0_6_WIRED;
         when 8 => readValue               <= COP0_8_BADVIRTUALADDRESS;
         when 9 => readValue(31 downto 0)  <= COP0_9_COUNT(32 downto 1);
         
         when 10 =>
            readValue(7 downto 0)          <= COP0_10_ENTRYHI_addressSpaceID;
            readValue(39 downto 13)        <= COP0_10_ENTRYHI_virtualAddress;
            readValue(63 downto 62)        <= COP0_10_ENTRYHI_region;

         when 11 => readValue(31 downto 0)  <= COP0_11_COMPARE;
         
         when 12 =>
            readValue(0)            <= COP0_12_SR_interruptEnable;    
            readValue(1)            <= COP0_12_SR_exceptionLevel;     
            readValue(2)            <= COP0_12_SR_errorLevel;        
            readValue(4 downto 3)   <= COP0_12_SR_privilegeMode;      
            readValue(5)            <= COP0_12_SR_userExtendedAddr;   
            readValue(6)            <= COP0_12_SR_supervisorAddr;     
            readValue(7)            <= COP0_12_SR_kernelExtendedAddr; 
            readValue(15 downto 8)  <= COP0_12_SR_interruptMask;     
            readValue(16)           <= COP0_12_SR_de;                 
            readValue(17)           <= COP0_12_SR_ce;                 
            readValue(18)           <= COP0_12_SR_condition;          
            readValue(20)           <= COP0_12_SR_softReset;          
            readValue(21)           <= COP0_12_SR_tlbShutdown;      
            readValue(22)           <= COP0_12_SR_vectorLocation;     
            readValue(24)           <= COP0_12_SR_instructionTracing; 
            readValue(25)           <= COP0_12_SR_reverseEndian;      
            readValue(26)           <= COP0_12_SR_floatingPointMode;  
            readValue(27)           <= COP0_12_SR_lowPowerMode;       
            readValue(28)           <= COP0_12_SR_enable_cop0;
            readValue(29)           <= COP0_12_SR_enable_cop1;
            readValue(30)           <= COP0_12_SR_enable_cop2;
            readValue(31)           <= COP0_12_SR_enable_cop3;
            
         when 13 =>
            readValue(6 downto 2)   <= COP0_13_CAUSE_exceptionCode;   
            readValue(15 downto 8)  <= COP0_13_CAUSE_interruptPending;   
            readValue(29 downto 28) <= COP0_13_CAUSE_coprocessorError;   
            readValue(31)           <= COP0_13_CAUSE_branchDelay;   
            
         when 14 => readValue <= COP0_14_EPC;
            
         when 15 => readValue(11 downto 0) <= x"B22"; -- COP0_15_COPREVISION
         
         when 16 =>
            readValue(1 downto 0)   <= COP0_16_CONFIG_cacheAlgoKSEG0;
            readValue(3 downto 2)   <= COP0_16_CONFIG_cu;   
            readValue(14 downto 4)  <= "11001000110";
            readValue(15)           <= COP0_16_CONFIG_bigEndian;
            readValue(23 downto 16) <= "00000110"; 
            readValue(27 downto 24) <= COP0_16_CONFIG_sysadWBPattern; 
            readValue(30 downto 28) <= COP0_16_CONFIG_systemClockRatio;
            
         when 17 => readValue <= COP0_17_LOADLINKEDADDRESS;    
         when 18 => readValue(31 downto 0) <= COP0_18_WATCHLO;    
         when 19 => readValue(3 downto 0) <= COP0_19_WATCHHI;    
         when 20 => readValue(63 downto 4) <= COP0_20_XCONTEXT;    
         when 26 => readValue(7 downto 0) <= COP0_26_PARITYERROR;       

         when 27 => readValue <= (others => '0');

         when 28 =>
            readValue(7 downto 6)  <= COP0_28_TAGLO_primaryCacheState;
            readValue(27 downto 8) <= COP0_28_TAGLO_physicalAddress;
            
         when 29 => readValue <= (others => '0');
         
         when 30 => readValue <= COP0_30_EPCERROR;
          
         when others => readValue <= COP0_LATCH;
                     
      end case;
   end process;

   process (clk93)
      variable mode        : unsigned(1 downto 0); 
      variable nextEPC     : unsigned(63 downto 0);
   begin
      if (rising_edge(clk93)) then
      
         error_exception <= '0';
      
         if (COP0_12_SR_errorLevel = '1') then
            eretPC <= COP0_30_EPCERROR;
         else
            eretPC <= COP0_14_EPC;
         end if;
         
         if (COP0_12_SR_vectorLocation = '1') then
         
            -- todo tlb miss switch
         
            exceptionPC(31 downto 0) <= x"BFC00380";
         
         else
            
            -- todo tlb miss switch
            
            exceptionPC(31 downto 0) <= x"80000180";
            
         end if;
         if (bit64mode = '1') then
            exceptionPC(63 downto 32) <= (others => '1');
         else
            exceptionPC(63 downto 32) <= (others => '0');
         end if;
         
         --if (COP0_12_SR_interruptEnable = '1' or COP0_12_SR_exceptionLevel = '1') then    
         --   irq_offCount <= (others => '0');
         --else
         --   irq_offCount <= irq_offCount + 1;
         --end if;
         --error_exception <= irq_offCount(13);
      
         if (reset = '1') then
         
            COP0_0_INDEX_tlbEntry           <= (others => '0');
            COP0_0_INDEX_probefailure       <= '0';
            COP0_1_RANDOM                   <= (others => '0');
            COP0_2_ENTRYLO0                 <= (others => '0');
            COP0_3_ENTRYLO1                 <= (others => '0');
            COP0_4_CONTEXT                  <= (others => '0');
            COP0_5_PAGEMASK                 <= (others => '0');
            COP0_6_WIRED                    <= (others => '0');
            COP0_8_BADVIRTUALADDRESS        <= (others => '0');
            COP0_9_COUNT                    <= ss_in(9)(31 downto 0) & '0'; -- (others => '0');
            COP0_10_ENTRYHI_addressSpaceID  <= (others => '0'); 
            COP0_10_ENTRYHI_virtualAddress  <= (others => '0'); 
            COP0_10_ENTRYHI_region          <= (others => '0'); 
            COP0_11_COMPARE                 <= ss_in(11)(31 downto 0); -- (others => '0');
            COP0_12_SR_interruptEnable      <= ss_in(12)(0);           -- '0';
            COP0_12_SR_exceptionLevel       <= ss_in(12)(1);           -- '0';
            COP0_12_SR_errorLevel           <= ss_in(12)(2);           -- '1';
            COP0_12_SR_privilegeMode        <= ss_in(12)(4 downto 3);  -- (others => '0');
            COP0_12_SR_userExtendedAddr     <= ss_in(12)(5);           -- '0';
            COP0_12_SR_supervisorAddr       <= ss_in(12)(6);           -- '0';
            COP0_12_SR_kernelExtendedAddr   <= ss_in(12)(7);           -- '0';
            COP0_12_SR_interruptMask        <= ss_in(12)(15 downto 8); -- (others => '1');
            COP0_12_SR_de                   <= ss_in(12)(16);          -- '0';
            COP0_12_SR_ce                   <= ss_in(12)(17);          -- '0';
            COP0_12_SR_condition            <= ss_in(12)(18);          -- '0';
            COP0_12_SR_softReset            <= ss_in(12)(20);          -- '1';
            COP0_12_SR_tlbShutdown          <= ss_in(12)(21);          -- '0';
            COP0_12_SR_vectorLocation       <= ss_in(12)(22);          -- '1';
            COP0_12_SR_instructionTracing   <= ss_in(12)(24);          -- '0';
            COP0_12_SR_reverseEndian        <= ss_in(12)(25);          -- '0';
            COP0_12_SR_floatingPointMode    <= ss_in(12)(26);          -- '1';
            COP0_12_SR_lowPowerMode         <= ss_in(12)(27);          -- '0';
            COP0_12_SR_enable_cop0          <= ss_in(12)(28);          -- '1';
            COP0_12_SR_enable_cop1          <= ss_in(12)(29);          -- '1';
            COP0_12_SR_enable_cop2          <= ss_in(12)(30);          -- '0';
            COP0_12_SR_enable_cop3          <= ss_in(12)(31);          -- '0';
            COP0_13_CAUSE_exceptionCode     <= (others => '0'); 
            COP0_13_CAUSE_interruptPending  <= (others => '0'); 
            COP0_13_CAUSE_coprocessorError  <= (others => '0'); 
            COP0_13_CAUSE_branchDelay       <= '0';
            COP0_14_EPC                     <= (others => '0'); 
            COP0_16_CONFIG_cacheAlgoKSEG0   <= (others => '0'); 
            COP0_16_CONFIG_cu               <= (others => '0'); 
            COP0_16_CONFIG_bigEndian        <= '1';
            COP0_16_CONFIG_sysadWBPattern   <= (others => '0'); 
            COP0_16_CONFIG_systemClockRatio <= (others => '1'); 
            COP0_17_LOADLINKEDADDRESS       <= (others => '0'); 
            COP0_18_WATCHLO                 <= (others => '0');   
            COP0_19_WATCHHI                 <= (others => '0');   
            COP0_20_XCONTEXT                <= (others => '0');
            COP0_26_PARITYERROR             <= (others => '0');  
            COP0_28_TAGLO_primaryCacheState <= (others => '0');     
            COP0_28_TAGLO_physicalAddress   <= (others => '0');     
            COP0_30_EPCERROR                <= (others => '0'); 
            
            COP0_LATCH                      <= (others => '0'); 
            
            bit64mode                       <= '0';
            
            cop0Written6                    <= 0;
            cop0Written9                    <= 0;
            
            irqTrigger                      <= '0';

         elsif (ce = '1') then
         
            -- interrupt
            COP0_13_CAUSE_interruptPending(2) <= irqRequest;
            
            irqTrigger <= '0';
            if (COP0_12_SR_interruptEnable = '1' and COP0_12_SR_exceptionLevel = '0' and COP0_12_SR_errorLevel = '0') then
               if ((COP0_12_SR_interruptMask and COP0_13_CAUSE_interruptPending) > 0) then
                  irqTrigger <= '1';
               end if;
            end if;
         
            -- count
            if (cop0Written9 = 0) then
               COP0_9_COUNT <= COP0_9_COUNT + 1;
               if (COP0_9_COUNT(32 downto 1) = COP0_11_COMPARE) then
                  COP0_13_CAUSE_interruptPending(7) <= '1';
               end if;
            else
               cop0Written9 <= cop0Written9 - 1;
            end if;
            
            -- random
            if (stall = 0) then
               if (COP0_6_WIRED(5) = '0' and COP0_1_RANDOM(4 downto 0) = COP0_6_WIRED(4 downto 0)) then
                  COP0_1_RANDOM <= 6x"1F";
               else
                  COP0_1_RANDOM <= COP0_1_RANDOM - 1;
               end if;
            end if;
            
            if (cop0Written6 > 0) then
               cop0Written6 <= cop0Written6 - 1;
               if (cop0Written6 = 1) then
                  COP0_1_RANDOM   <= to_unsigned(31, 6);
               end if;
            end if;
            
            -- when debugging systemtest...
            --COP0_9_COUNT  <= (others => '0');
            --COP0_1_RANDOM <= (others => '0');
            --COP0_13_CAUSE_interruptPending(7) <= '0';
            
            -- CPU access
            if (exception = '1') then
         
               COP0_14_EPC               <= nextEPC_1;
               COP0_13_CAUSE_branchDelay <= isDelaySlot_1;
               
               case (COP0_13_CAUSE_exceptionCode(3 downto 0)) is
                  when x"4" | x"5" | x"9" | x"A" | x"C"  => error_exception <= '1';
                  when others => null;
               end case;
         
            elsif (stall4Masked = 0 and executeNew = '1') then
               if (writeEnable = '1') then
               
                  COP0_LATCH <= writeValue;
                  
                  case (to_integer(regIndex)) is
                     
                     when 0 =>
                        COP0_0_INDEX_tlbEntry     <= writeValue(5 downto 0);
                        COP0_0_INDEX_probefailure <= writeValue(31);
                        
                        when 2 => COP0_2_ENTRYLO0 <= writeValue(29 downto 0);
                        when 3 => COP0_3_ENTRYLO1 <= writeValue(29 downto 0);
                        when 4 => COP0_4_CONTEXT(63 downto 23) <= writeValue(63 downto 23);
                        when 5 => COP0_5_PAGEMASK <= writeValue(24 downto 13);
                        
                        when 6 => 
                           COP0_6_WIRED    <= writeValue(5 downto 0);
                           cop0Written6    <= 2;
                        
                        when 9 => 
                           COP0_9_COUNT <= writeValue(31 downto 0) & '0';
                           cop0Written9 <= 3;
                        
                        when 10 =>
                           COP0_10_ENTRYHI_addressSpaceID <= writeValue(7 downto 0);
                           COP0_10_ENTRYHI_virtualAddress <= writeValue(39 downto 13);
                           COP0_10_ENTRYHI_region         <= writeValue(63 downto 62);
                           
                        when 11 =>
                           COP0_11_COMPARE   <= writeValue(31 downto 0);
                           COP0_13_CAUSE_interruptPending(7) <= '0';
                        
                        when 12 =>
                           -- todo: missing setMode
                           COP0_12_SR_interruptEnable     <= writeValue(0 );
                           COP0_12_SR_exceptionLevel      <= writeValue(1 );
                           COP0_12_SR_errorLevel          <= writeValue(2 );
                           COP0_12_SR_privilegeMode       <= writeValue(4 downto 3);
                           COP0_12_SR_userExtendedAddr    <= writeValue(5);
                           COP0_12_SR_supervisorAddr      <= writeValue(6);
                           COP0_12_SR_kernelExtendedAddr  <= writeValue(7);
                           COP0_12_SR_interruptMask       <= writeValue(15 downto 8);
                           COP0_12_SR_de                  <= writeValue(16);
                           COP0_12_SR_ce                  <= writeValue(17);
                           COP0_12_SR_condition           <= writeValue(18);
                           COP0_12_SR_softReset           <= writeValue(20);
                           --COP0_12_SR_tlbShutdown         <= writeValue(21); -- read only
                           COP0_12_SR_vectorLocation      <= writeValue(22);
                           COP0_12_SR_instructionTracing  <= writeValue(24);
                           COP0_12_SR_reverseEndian       <= writeValue(25);
                           COP0_12_SR_floatingPointMode   <= writeValue(26);
                           COP0_12_SR_lowPowerMode        <= writeValue(27);
                           COP0_12_SR_enable_cop0         <= writeValue(28);
                           COP0_12_SR_enable_cop1         <= writeValue(29);
                           COP0_12_SR_enable_cop2         <= writeValue(30);
                           COP0_12_SR_enable_cop3         <= writeValue(31);
                           
                        when 13 => COP0_13_CAUSE_interruptPending(1 downto 0) <= writeValue(9 downto 8);
                        when 14 => COP0_14_EPC <= writeValue;
                        
                        when 16 =>
                           COP0_16_CONFIG_cacheAlgoKSEG0 <= writeValue(1 downto 0);
                           COP0_16_CONFIG_cu             <= writeValue(3 downto 2);   
                           COP0_16_CONFIG_bigEndian      <= writeValue(15);
                           COP0_16_CONFIG_sysadWBPattern <= writeValue(27 downto 24); 
                           --COP0_16_CONFIG_systemClockRatio <= writeValue(30 downto 28); -- read only
                     
                        when 17 => COP0_17_LOADLINKEDADDRESS(31 downto 0) <= writeValue(31 downto 0);
                        
                        when 18 => COP0_18_WATCHLO <= writeValue(31 downto 3) & '0' & writeValue(1 downto 0);
                        when 19 => COP0_19_WATCHHI <= writeValue(3 downto 0);
                        when 20 => COP0_20_XCONTEXT(63 downto 33) <= writeValue(63 downto 33);
                        when 26 => COP0_26_PARITYERROR <= writeValue(7 downto 0);
                        
                        when 28 =>
                           COP0_28_TAGLO_primaryCacheState <= writeValue(7 downto 6);
                           COP0_28_TAGLO_physicalAddress   <= writeValue(27 downto 8);
                           
                        when 30 => COP0_30_EPCERROR <= writeValue;
                     
                     when others => null;   
                        
                  end case;
                     
               end if; -- write enable
               
               -- eret
               if (eret = '1') then
                  if (COP0_12_SR_errorLevel = '1') then
                     COP0_12_SR_errorLevel <= '0';
                  else
                     COP0_12_SR_exceptionLevel <= '0';
                  end if;
               end if;
               
               -- set mode
               mode := COP0_12_SR_privilegeMode;
               if (mode > 2) then mode := "10"; end if;
               if (COP0_12_SR_exceptionLevel = '1') then mode := "00"; end if;
               if (COP0_12_SR_errorLevel     = '1') then mode := "00"; end if;
               -- should also switch endian mode, but we don't allow little endian in this CPU implementation!
               case (mode) is
                  when "00" => bit64mode <= COP0_12_SR_kernelExtendedAddr;
                  when "01" => bit64mode <= COP0_12_SR_supervisorAddr;
                  when "10" => bit64mode <= COP0_12_SR_userExtendedAddr;
                  when others => null;
               end case;
               
            end if; -- stall

            -- new exception
            nextEPC := pcOld1;
            if (isDelaySlot = '1') then
               nextEPC := pcOld1 - 4; -- should this be pcOld2 instead?
            end if;
            if (stall = 0) then
               exception     <= '0';
               nextEPC_1     <= nextEPC;
               isDelaySlot_1 <= isDelaySlot;
            end if;
            
            if (exception = '0') then
               if (stall = 0 or exceptionFPU = '1') then
                  if (decode_irq = '1' or exceptionFPU = '1' or exception3 = '1' or exception1 = '1') then
                  
                     exception <= '1';
                     
                     COP0_12_SR_exceptionLevel   <= '1';
                     
                     COP0_13_CAUSE_coprocessorError <= "00";
                     if (decode_irq = '1') then
                        COP0_13_CAUSE_exceptionCode    <= (others => '0');
                     elsif (exceptionFPU = '1') then
                        COP0_13_CAUSE_exceptionCode    <= '0' & x"F";
                     elsif (exception3 = '1') then
                        COP0_13_CAUSE_exceptionCode    <= '0' & exceptionCode_3;
                        COP0_13_CAUSE_coprocessorError <= exception_COP;
                     else
                        COP0_13_CAUSE_exceptionCode <= '0' & exceptionCode_1;
                     end if;
                  
                  end if;
               end if;
            end if;

         end if; -- ce
      end if;
   end process;
   
--##############################################################
--############################### savestates
--##############################################################

   process (clk93)
   begin
      if (rising_edge(clk93)) then
      
         if (SS_reset = '1') then
         
            for i in 0 to 31 loop
               ss_in(i) <= (others => '0');
            end loop;
            
            ss_in(12)(31 downto 0) <= x"3450FF04"; --cop12
            ss_in(16)(31 downto 0) <= x"7006E460"; --cop16
            
         elsif (SS_wren_CPU = '1' and SS_Adr >= 64 and SS_Adr < 96) then
            ss_in(to_integer(SS_Adr(4 downto 0))) <= unsigned(SS_DataWrite);
         end if;
      
      end if;
   end process;


   -- synthesis translate_off
   cop0_export(0)(5 downto 0)    <= COP0_0_INDEX_tlbEntry;
   cop0_export(0)(31)            <= COP0_0_INDEX_probefailure;
   
   cop0_export(1)(5 downto 0)    <= COP0_1_RANDOM;
   cop0_export(2)(29 downto 0)   <= COP0_2_ENTRYLO0;
   cop0_export(3)(29 downto 0)   <= COP0_3_ENTRYLO1;
   cop0_export(4)                <= COP0_4_CONTEXT;
   cop0_export(5)(24 downto 13)  <= COP0_5_PAGEMASK;
   cop0_export(6)(5 downto 0)    <= COP0_6_WIRED;
   cop0_export(8)                <= COP0_8_BADVIRTUALADDRESS;
   cop0_export(9)(31 downto 0)   <= COP0_9_COUNT(32 downto 1);
   
   cop0_export(10)(7 downto 0)   <= COP0_10_ENTRYHI_addressSpaceID;
   cop0_export(10)(39 downto 13) <= COP0_10_ENTRYHI_virtualAddress;
   cop0_export(10)(63 downto 62) <= COP0_10_ENTRYHI_region;
   
   cop0_export(11)(31 downto 0)  <= COP0_11_COMPARE;
   
   cop0_export(12)(0)            <= COP0_12_SR_interruptEnable;    
   cop0_export(12)(1)            <= COP0_12_SR_exceptionLevel;     
   cop0_export(12)(2)            <= COP0_12_SR_errorLevel;        
   cop0_export(12)(4 downto 3)   <= COP0_12_SR_privilegeMode;      
   cop0_export(12)(5)            <= COP0_12_SR_userExtendedAddr;   
   cop0_export(12)(6)            <= COP0_12_SR_supervisorAddr;     
   cop0_export(12)(7)            <= COP0_12_SR_kernelExtendedAddr; 
   cop0_export(12)(15 downto 8)  <= COP0_12_SR_interruptMask;     
   cop0_export(12)(16)           <= COP0_12_SR_de;                 
   cop0_export(12)(17)           <= COP0_12_SR_ce;                 
   cop0_export(12)(18)           <= COP0_12_SR_condition;          
   cop0_export(12)(20)           <= COP0_12_SR_softReset;          
   cop0_export(12)(21)           <= COP0_12_SR_tlbShutdown;      
   cop0_export(12)(22)           <= COP0_12_SR_vectorLocation;     
   cop0_export(12)(24)           <= COP0_12_SR_instructionTracing; 
   cop0_export(12)(25)           <= COP0_12_SR_reverseEndian;      
   cop0_export(12)(26)           <= COP0_12_SR_floatingPointMode;  
   cop0_export(12)(27)           <= COP0_12_SR_lowPowerMode;       
   cop0_export(12)(28)           <= COP0_12_SR_enable_cop0;
   cop0_export(12)(29)           <= COP0_12_SR_enable_cop1;
   cop0_export(12)(30)           <= COP0_12_SR_enable_cop2;
   cop0_export(12)(31)           <= COP0_12_SR_enable_cop3;
   
   cop0_export(13)(6 downto 2)   <= COP0_13_CAUSE_exceptionCode;   
   cop0_export(13)(15 downto 8)  <= COP0_13_CAUSE_interruptPending;   
   cop0_export(13)(29 downto 28) <= COP0_13_CAUSE_coprocessorError;   
   cop0_export(13)(31)           <= COP0_13_CAUSE_branchDelay;   
   
   cop0_export(14)               <= COP0_14_EPC;
   cop0_export(15)(11 downto 0)  <= x"B22";
   
   cop0_export(16)(1 downto 0)   <= COP0_16_CONFIG_cacheAlgoKSEG0;
   cop0_export(16)(3 downto 2)   <= COP0_16_CONFIG_cu;   
   cop0_export(16)(14 downto 4)  <= "11001000110";
   cop0_export(16)(15)           <= COP0_16_CONFIG_bigEndian;
   cop0_export(16)(23 downto 16) <= "00000110"; 
   cop0_export(16)(27 downto 24) <= COP0_16_CONFIG_sysadWBPattern; 
   cop0_export(16)(30 downto 28) <= COP0_16_CONFIG_systemClockRatio;
   
   cop0_export(17)               <= COP0_17_LOADLINKEDADDRESS;    
   cop0_export(18)(31 downto 0)  <= COP0_18_WATCHLO;    
   cop0_export(19)(3 downto 0)   <= COP0_19_WATCHHI;    
   cop0_export(20)(63 downto 4)  <= COP0_20_XCONTEXT;    
   cop0_export(26)(7 downto 0)   <= COP0_26_PARITYERROR;       
   
   cop0_export(28)(7 downto 6)   <= COP0_28_TAGLO_primaryCacheState;
   cop0_export(28)(27 downto 8)  <= COP0_28_TAGLO_physicalAddress;
   
   cop0_export(30)               <= COP0_30_EPCERROR;
   -- synthesis translate_on

end architecture;
