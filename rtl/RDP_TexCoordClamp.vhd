library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

use work.pRDP.all;

entity RDP_TexCoordClamp is
   port 
   (
      coordIn  : in  signed(18 downto 0);
      coordout : out signed(15 downto 0)
   );
end entity;

architecture arch of RDP_TexCoordClamp is

begin 

  coordout <= x"7FFF" when (coordIn(18) = '1') else
              x"8000" when (coordIn(17) = '1') else
              x"7FFF" when (coordIn(16 downto 15) = "01") else
              x"8000" when (coordIn(16 downto 15) = "10") else
              coordIn(15 downto 0);

end architecture;





