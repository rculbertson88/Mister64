library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pRSP is

   type tDMEMarray is array(0 to 15) of std_logic_vector(7 downto 0);

   type VECTOR_CALCTYPE is
   (
      VCALC_VMULF,
      VCALC_VMUDH,
      VCALC_VMADN,
      VCALC_VADD,
      VCALC_VSUB,
      VCALC_VADDC,
      VCALC_VSUBC,
      VCALC_VABS,
      VCALC_VSAR,
      VCALC_VLT,
      VCALC_VEQ,
      VCALC_VNE,
      VCALC_VGE,
      VCALC_VCL,
      VCALC_VCH,
      VCALC_VCR,
      VCALC_VMRG,
      VCALC_VAND,
      VCALC_VNAND,
      VCALC_VOR,
      VCALC_VNOR,
      VCALC_VXOR,
      VCALC_VNXOR,
      VCALC_VMOV,
      VCALC_VZERO,
      VCALC_VNOP
   );

end package;