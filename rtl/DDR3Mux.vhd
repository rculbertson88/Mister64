-----------------------------------------------------------------
--------------- DDR3Mux Package  --------------------------------
-----------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pDDR3 is

   constant DDR3MUXCOUNT : integer := 7;
   
   constant DDR3MUX_MEMMUX : integer := 0;
   constant DDR3MUX_PI     : integer := 1;
   constant DDR3MUX_VI     : integer := 2;
   constant DDR3MUX_SS     : integer := 3;
   constant DDR3MUX_RDP    : integer := 4;
   constant DDR3MUX_SI     : integer := 5;
   constant DDR3MUX_AI     : integer := 6;
   
   type tDDDR3Single     is array(0 to DDR3MUXCOUNT - 1) of std_logic;
   type tDDDR3ReqAddr    is array(0 to DDR3MUXCOUNT - 1) of unsigned(27 downto 0);
   type tDDDR3Burstcount is array(0 to DDR3MUXCOUNT - 1) of unsigned(9 downto 0);
   type tDDDR3BwriteMask is array(0 to DDR3MUXCOUNT - 1) of std_logic_vector(7 downto 0);
   type tDDDR3BwriteData is array(0 to DDR3MUXCOUNT - 1) of std_logic_vector(63 downto 0);
  
end package;

-----------------------------------------------------------------
--------------- DDR3Mux module    -------------------------------
-----------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pDDR3.all;

entity DDR3Mux is
   port 
   (
      clk1x            : in  std_logic;
      clk2x            : in  std_logic;
      
      error            : out std_logic;

      ddr3_BUSY        : in  std_logic;                    
      ddr3_DOUT        : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY  : in  std_logic;
      ddr3_BURSTCNT    : out std_logic_vector(7 downto 0) := (others => '0'); 
      ddr3_ADDR        : out std_logic_vector(28 downto 0) := (others => '0');                       
      ddr3_DIN         : out std_logic_vector(63 downto 0) := (others => '0');
      ddr3_BE          : out std_logic_vector(7 downto 0) := (others => '0'); 
      ddr3_WE          : out std_logic := '0';
      ddr3_RD          : out std_logic := '0';
      
      rdram_request    : in  tDDDR3Single;
      rdram_rnw        : in  tDDDR3Single;    
      rdram_address    : in  tDDDR3ReqAddr;
      rdram_burstcount : in  tDDDR3Burstcount;  
      rdram_writeMask  : in  tDDDR3BwriteMask;  
      rdram_dataWrite  : in  tDDDR3BwriteData;
      rdram_granted    : out tDDDR3Single;
      rdram_granted2X  : out tDDDR3Single;
      rdram_done       : out tDDDR3Single;
      rdram_dataRead   : out std_logic_vector(63 downto 0)
   );
end entity;

architecture arch of DDR3Mux is

   type tddr3State is
   (
      IDLE,
      WAITREAD,
      READAGAIN
   );
   signal ddr3State     : tddr3State := IDLE;
   
   signal readCount     : unsigned(7 downto 0);
   signal timeoutCount  : unsigned(12 downto 0);
   
   signal req_latched   : tDDDR3Single;
   signal lastIndex     : integer range 0 to DDR3MUXCOUNT - 1;
   signal remain        : unsigned(9 downto 0);
   signal lastReadReq   : std_logic;
   
   type tdone is array(0 to DDR3MUXCOUNT - 1) of std_logic_vector(1 downto 0);
   signal done    : tdone := (others => (others => '0'));
   signal granted : tdone := (others => (others => '0'));

begin 

   ddr3_ADDR(28 downto 25) <= "0011";

   process (clk2x)
      variable activeRequest : std_logic;
      variable activeIndex   : integer range 0 to DDR3MUXCOUNT - 1;
   begin
      if rising_edge(clk2x) then
      
         error <= '0';
      
         if (ddr3_BUSY = '0') then
            ddr3_WE <= '0';
            ddr3_RD <= '0';
         end if;

         -- request handling
         activeRequest := '0';
         for i in 0 to DDR3MUXCOUNT - 1 loop
            if (rdram_request(i) = '1') then
               req_latched(i) <= '1';
            end if;
            
            if (req_latched(i) = '1') then
               activeRequest := '1';
               activeIndex   := i;
            end if;
            
            rdram_done(i) <= '0';
            done(i) <= '0' & done(i)(1);
            if (done(i) /= "00") then
               rdram_done(i) <= '1';
            end if;
            
            rdram_granted(i) <= '0';
            granted(i) <= '0' & granted(i)(1);
            if (granted(i) /= "00") then
               rdram_granted(i) <= '1';
            end if;
            rdram_granted2X(i) <= '0';
            
         end loop;

         -- main statemachine
         case (ddr3State) is
            when IDLE =>
               
               lastIndex    <= activeIndex;
               timeoutCount <= (others => '0');
            
               if ((ddr3_BUSY = '0' or ddr3_WE = '0') and activeRequest = '1') then
                  
                  req_latched(activeIndex) <= '0';
                  ddr3_DIN                 <= rdram_dataWrite(activeIndex);
                  ddr3_BE                  <= rdram_writeMask(activeIndex);
                  ddr3_ADDR(24 downto 0)   <= std_logic_vector(rdram_address(activeIndex)(27 downto 3));
                  
                  if (rdram_burstcount(activeIndex)(9 downto 8) = "00") then
                     ddr3_BURSTCNT  <= std_logic_vector(rdram_burstcount(activeIndex)(7 downto 0));
                     readCount      <= rdram_burstcount(activeIndex)(7 downto 0);
                     lastReadReq    <= '1';
                  else
                     ddr3_BURSTCNT  <= x"FF";
                     readCount      <= x"FF";
                     lastReadReq    <= '0';
                  end if;
                  
                  remain    <= rdram_burstcount(activeIndex) - 16#FF#;

                  if (rdram_rnw(activeIndex) = '1') then
                     ddr3State                     <= WAITREAD;
                     ddr3_RD                       <= '1';
                     granted(activeIndex)          <= "11";
                     rdram_granted2X(activeIndex)  <= '1';
                  else
                     ddr3_WE                       <= '1';
                     done(activeIndex)             <= "11"; 
                  end if;
                  
               end if;
                  
            when WAITREAD =>
               timeoutCount <= timeoutCount + 1;
               if (timeoutCount(timeoutCount'high) = '1') then
                  error <= '1';
               end if;
               if (ddr3_DOUT_READY = '1') then
                  rdram_dataRead  <= ddr3_DOUT;
                  timeoutCount    <= (others => '0');
                  readCount       <= readCount - 1;
                  if (readCount = 1) then
                     if (lastReadReq = '1') then
                        ddr3State       <= IDLE;  
                        done(lastIndex) <= "11";    
                     else
                        ddr3State       <= READAGAIN; 
                     end if;
                  end if;
               end if;
               
            when READAGAIN =>
               ddr3_ADDR(20 downto 0)   <= std_logic_vector(unsigned(ddr3_ADDR(20 downto 0)) + 16#FF#);
                  
               if (remain(9 downto 8) = "00") then
                  ddr3_BURSTCNT  <= std_logic_vector(remain(7 downto 0));
                  readCount      <= remain(7 downto 0);
                  lastReadReq    <= '1';
               else
                  ddr3_BURSTCNT  <= x"FF";
                  readCount      <= x"FF";
                  lastReadReq    <= '0';
               end if;
               
               ddr3State <= WAITREAD;
               ddr3_RD   <= '1';
               remain    <= remain - 16#FF#;
         
         end case;

      end if;
   end process;

end architecture;





