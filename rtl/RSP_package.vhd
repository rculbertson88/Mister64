library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pRSP is

   type tDMEMarray is array(0 to 15) of std_logic_vector(7 downto 0);

   type VECTOR_CALCTYPE is
   (
      VCALC_VABS,
      VCALC_VSAR,
      VCALC_VMOV
   );

end package;