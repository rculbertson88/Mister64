library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pVI is

   type tvideoout_settings is record
      CTRL_TYPE       : unsigned(1 downto 0);
      CTRL_SERRATE    : std_logic;
      X_SCALE_FACTOR  : unsigned(11 downto 0);
      VI_WIDTH        : unsigned(11 downto 0);
      isPAL           : std_logic;
      videoSizeY      : unsigned(9 downto 0);
   end record;
   
   type tvideoout_reports is record
      vsync                   : std_logic;
      inVsync                 : std_logic;
      interlacedDisplayField  : std_logic;
      newLine                 : std_logic;
      VI_CURRENT              : unsigned(8 downto 0);
   end record;
   
   type tvideoout_request is record
      fetch                   : std_logic;
      lineInNext              : unsigned(8 downto 0);
      xpos                    : integer range 0 to 1023;
      lineDisp                : unsigned(8 downto 0);
   end record;    
   
   type tvideoout_out is record
      hsync          : std_logic;
      vsync          : std_logic;
      hblank         : std_logic;
      vblank         : std_logic;
      ce             : std_logic;
      interlace      : std_logic;
      r              : std_logic_vector(7 downto 0);
      g              : std_logic_vector(7 downto 0);
      b              : std_logic_vector(7 downto 0);
   end record; 
   
end package;