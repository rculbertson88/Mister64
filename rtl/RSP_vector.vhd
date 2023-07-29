library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;   

library mem;
use work.pFunctions.all;
use work.pRSP.all;

entity RSP_vector is
   generic 
   (
      V_INDEX : integer range 0 to 7
   );
   port 
   (
      clk1x                 : in  std_logic;
      
      CalcNew               : in  std_logic;
      CalcType              : in  VECTOR_CALCTYPE;
      CalcSign1             : in  std_logic;
      CalcSign2             : in  std_logic;
      VectorValue1          : in  std_logic_vector(15 downto 0);
      VectorValue2          : in  std_logic_vector(15 downto 0);
      element               : in  unsigned(3 downto 0);
      destElement           : in  unsigned(2 downto 0);
      
      set_vco               : in  std_logic;
      set_vcc               : in  std_logic;
      set_vce               : in  std_logic;
      vco_in_lo             : in  std_logic;
      vco_in_hi             : in  std_logic;
      vcc_in_lo             : in  std_logic;
      vcc_in_hi             : in  std_logic;
      vce_in                : in  std_logic;
      
      -- synthesis translate_off
      export_accu           : out unsigned(47 downto 0) := (others => '0');
      export_vco_lo         : out std_logic := '0';
      export_vco_hi         : out std_logic := '0';
      export_vcc_lo         : out std_logic := '0';
      export_vcc_hi         : out std_logic := '0';
      export_vce            : out std_logic := '0';
      -- synthesis translate_on
      
      writebackEna          : out std_logic := '0';
      writebackData         : out std_logic_vector(15 downto 0) := (others => '0');
      
      flag_vco_lo           : out std_logic;
      flag_vco_hi           : out std_logic;
      flag_vcc_lo           : out std_logic;
      flag_vcc_hi           : out std_logic;
      flag_vce              : out std_logic
   );
end entity;

architecture arch of RSP_vector is
          
   -- stage 3   
   signal value_in1       : signed(16 downto 0);
   signal value_in2       : signed(16 downto 0);
   
   signal carry_vector    : signed(16 downto 0);
   signal add_result      : signed(16 downto 0);
   signal sub_result      : signed(16 downto 0);

   signal mul_result      : signed(33 downto 0);
   
   signal acc             : signed(47 downto 0) := (others => '0');
   alias acc_h              is acc(47 downto 32);
   alias acc_m              is acc(31 downto 16);
   alias acc_l              is acc(15 downto  0);
   
   signal vco_lo          : std_logic := '0';
   signal vco_hi          : std_logic := '0';
   signal vcc_lo          : std_logic := '0';
   signal vcc_hi          : std_logic := '0';
   signal vce             : std_logic := '0';
   
   type toutputSelect is
   (
      OUTPUT_ZERO,
      OUTPUT_ACCL,
      OUTPUT_ACCM,
      OUTPUT_ACCH,
      CLAMP_SIGNED,
      CLAMP_UNSIGNED,
      CLAMP_ADDSUB
   );
   signal outputSelect : toutputSelect;
   
   signal add_carry       : std_logic := '0';
   
   -- stage 4 
   signal clamp_signbit   : std_logic;
  
   -- synthesis translate_off
   signal acc_1           : signed(47 downto 0) := (others => '0');
   signal vco_lo_1        : std_logic := '0';
   signal vco_hi_1        : std_logic := '0';
   signal vcc_lo_1        : std_logic := '0';
   signal vcc_hi_1        : std_logic := '0';
   signal vce_1           : std_logic := '0';
   -- synthesis translate_on
   
begin 

   flag_vco_lo <= vco_lo;
   flag_vco_hi <= vco_hi;
   flag_vcc_lo <= vcc_lo;
   flag_vcc_hi <= vcc_hi;
   flag_vce    <= vce;   
   
--##############################################################
--############################### stage 3
--##############################################################
   
   -- signed/unsigned
   value_in1 <= resize(signed(VectorValue1), 17) when (CalcSign1 = '1') else '0' & signed(VectorValue1);
   value_in2 <= resize(signed(VectorValue2), 17) when (CalcSign2 = '1') else '0' & signed(VectorValue2);
   
   -- calc
   carry_vector <= x"0000" & vco_lo when (CalcType = VCALC_VADD or CalcType = VCALC_VSUB) else (others => '0');
   
   add_result <= value_in1 + value_in2 + carry_vector;
   sub_result <= value_in1 - value_in2 - carry_vector;
   mul_result <= value_in1 * value_in2;
   
   process (all)
   begin
   
      
   end process;
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         writebackEna <= '0';
         
         if (set_vco = '1') then
            vco_lo <= vco_in_lo;
            vco_hi <= vco_in_hi;
         end if;
         
         if (set_vcc = '1') then
            vcc_lo <= vcc_in_lo;
            vcc_hi <= vcc_in_hi;
         end if;
         
         if (set_vce = '1') then
            vce <= vce_in;
         end if;   
      
         if (CalcNew = '1') then
         
            case (CalcType) is
         
               when VCALC_VMUDH =>
                  acc            <= mul_result(31 downto 0) & x"0000";
                  writebackEna   <= '1';
                  outputSelect   <= CLAMP_SIGNED;               
                  
               when VCALC_VMADN =>
                  acc            <= acc + resize(mul_result, 48);
                  writebackEna   <= '1';
                  outputSelect   <= CLAMP_UNSIGNED;               
                  
               when VCALC_VADD =>
                  acc(15 downto 0) <= add_result(15 downto 0);
                  writebackEna     <= '1';
                  outputSelect     <= CLAMP_ADDSUB;
                  vco_lo           <= '0';
                  vco_hi           <= '0';
                  add_carry        <= add_result(16);               
                  
               when VCALC_VSUB =>
                  acc(15 downto 0) <= sub_result(15 downto 0);
                  writebackEna     <= '1';
                  outputSelect     <= CLAMP_ADDSUB;
                  vco_lo           <= '0';
                  vco_hi           <= '0';
                  add_carry        <= sub_result(16);
         
               when VCALC_VABS =>
                  writebackEna     <= '1';
                  outputSelect     <= OUTPUT_ACCL;
                  if (signed(VectorValue1) < 0) then
                     acc(15 downto 0) <= -signed(VectorValue2);
                     if (VectorValue2 = x"8000") then
                        outputSelect     <= CLAMP_ADDSUB;
                        add_carry        <= '0';
                     end if;
                  elsif (signed(VectorValue1) > 0) then
                     acc(15 downto 0) <= signed(VectorValue2);
                  else
                     acc(15 downto 0) <= (others => '0');
                  end if;
                  
                   
               when VCALC_VADDC =>
                  acc(15 downto 0) <= add_result(15 downto 0);
                  writebackEna     <= '1';
                  outputSelect     <= OUTPUT_ACCL;
                  vco_lo           <= add_result(16); 
                  vco_hi           <= '0';
                  
               when VCALC_VSUBC =>
                  acc(15 downto 0) <= sub_result(15 downto 0);
                  writebackEna     <= '1';
                  outputSelect     <= OUTPUT_ACCL;
                  vco_lo           <= sub_result(16);
                  if (sub_result /= 0) then vco_hi <= '1'; else vco_hi <= '0'; end if;
                  
               when VCALC_VSAR => 
                  writebackEna     <= '1';
                  case (element) is
                     when x"8"   => outputSelect <= OUTPUT_ACCH;
                     when x"9"   => outputSelect <= OUTPUT_ACCM;
                     when x"A"   => outputSelect <= OUTPUT_ACCL;
                     when others => outputSelect <= OUTPUT_ZERO;
                  end case;
                  
               when VCALC_VMOV =>
                  if (destElement = V_INDEX) then
                     writebackEna     <= '1';
                  end if;
                  outputSelect     <= OUTPUT_ACCL;
                  acc(15 downto 0) <= signed(VectorValue2);
                  
               when VCALC_VZERO =>
                  acc(15 downto 0) <= add_result(15 downto 0);
                  writebackEna     <= '1';
                  outputSelect     <= OUTPUT_ZERO;

               when others => null;
         
            end case;
         
         end if;
         
      end if; -- clock
   end process;
   
   
--##############################################################
--############################### stage 4
--##############################################################
   
   clamp_signbit <= '1' when (outputSelect = CLAMP_SIGNED) else '0';
   
   process (all)
   begin
      
      case (outputSelect) is
      
         when OUTPUT_ZERO => writebackData <= (others => '0');
         when OUTPUT_ACCL => writebackData <= std_logic_vector(acc_l);
         when OUTPUT_ACCM => writebackData <= std_logic_vector(acc_m);
         when OUTPUT_ACCH => writebackData <= std_logic_vector(acc_h);
         
         when CLAMP_SIGNED | CLAMP_UNSIGNED => 
            if    (acc_h < 0  and acc_h /= x"FFFF") then writebackData <= clamp_signbit & 15X"0";
            elsif (acc_h < 0  and acc_m > 0)        then writebackData <= clamp_signbit & 15X"0";
            elsif (acc_h >= 0 and acc_h /= 0)       then writebackData <= (not clamp_signbit) & 15X"7FFF";
            elsif (acc_h >= 0 and acc_m < 0)        then writebackData <= (not clamp_signbit) & 15X"7FFF";
            elsif (outputSelect = CLAMP_SIGNED)     then writebackData <= std_logic_vector(acc_m); 
            else                                         writebackData <= std_logic_vector(acc_l); 
            end if;
            
         when CLAMP_ADDSUB =>
            if (add_carry = '0' and acc_l(15) = '1') then
               writebackData <= x"7FFF";
            elsif (add_carry = '1' and acc_l(15) = '0') then
               writebackData <= x"8000";
            else
               writebackData <= std_logic_vector(acc_l);
            end if;
            
      end case;
      
   end process;
   
--##############################################################
--############################### export
--############################################################## 
   
-- synthesis translate_off
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         acc_1 <= acc;
         export_accu <= unsigned(acc_1);
         
         vco_lo_1 <= vco_lo;
         vco_hi_1 <= vco_hi;
         vcc_lo_1 <= vcc_lo;
         vcc_hi_1 <= vcc_hi;
         vce_1    <= vce;
         export_vco_lo <= vco_lo_1;
         export_vco_hi <= vco_hi_1;
         export_vcc_lo <= vcc_lo_1;
         export_vcc_hi <= vcc_hi_1;
         export_vce    <= vce_1;
         
      end if;
   end process;
-- synthesis translate_on

end architecture;





