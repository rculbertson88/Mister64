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
   signal executeV_result : signed(15 downto 0);
   
   signal acc             : signed(47 downto 0) := (others => '0');
   signal vco_lo          : std_logic := '0';
   signal vco_hi          : std_logic := '0';
   signal vcc_lo          : std_logic := '0';
   signal vcc_hi          : std_logic := '0';
   signal vce             : std_logic := '0';
   -- stage 4 
  
  
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
   
   process (all)
   begin
   
      executeV_result <= signed(VectorValue1) + signed(VectorValue2);
   
      case (CalcType) is
            
         when VCALC_VABS =>
            if (signed(VectorValue1) < 0) then
               executeV_result <= -signed(VectorValue2);
            elsif (signed(VectorValue1) > 0) then
               executeV_result <= signed(VectorValue2);
            else
               executeV_result <= (others => '0');
            end if;
            
         when VCALC_VSAR => 
            null;
         
         when VCALC_VMOV =>
            executeV_result <= signed(VectorValue2);
            
         when others => null;
      
      end case;
      
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
         
               when VCALC_VABS =>
                  writebackEna     <= '1';
                  writebackData    <= std_logic_vector(executeV_result);
                  acc(15 downto 0) <= executeV_result;
                  
               when VCALC_VSAR => 
                  writebackEna     <= '1';
                  case (element) is
                     when x"8"   => writebackData <= std_logic_vector(acc(47 downto 32));
                     when x"9"   => writebackData <= std_logic_vector(acc(31 downto 16));
                     when x"A"   => writebackData <= std_logic_vector(acc(15 downto  0));
                     when others => writebackData <= (others => '0');
                  end case;
                  
               when VCALC_VMOV =>
                  if (destElement = V_INDEX) then
                     writebackEna     <= '1';
                  end if;
                  writebackData    <= std_logic_vector(executeV_result);
                  acc(15 downto 0) <= executeV_result;

               when others => null;
         
            end case;
         
         end if;
         
      end if; -- clock
   end process;
   
   
--##############################################################
--############################### stage 4
--##############################################################
   
   process (all)
   begin
      
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





