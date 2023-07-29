library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pRSP is

   type tDMEMarray is array(0 to 15) of std_logic_vector(7 downto 0);

   type VECTOR_CALCTYPE is
   (
      VCALC_VMUDH,
      VCALC_VMADN,
      VCALC_VADD,
      VCALC_VSUB,
      VCALC_VADDC,
      VCALC_VSUBC,
      VCALC_VABS,
      VCALC_VSAR,
      VCALC_VMOV,
      VCALC_VZERO,
      VCALC_VNOP
   );

end package;