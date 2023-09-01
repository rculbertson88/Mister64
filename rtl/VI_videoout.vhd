library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pVI.all;

entity VI_videoout is
   generic
   (
      use2Xclock           : in  std_logic
   );
   port 
   (
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;
      clkvid               : in  std_logic;
      ce                   : in  std_logic;
      reset_1x             : in  std_logic;
      
      errorEna             : in  std_logic;
      errorCode            : in  unsigned(19 downto 0);
      
      fpscountOn           : in  std_logic;
      fpscountBCD          : in  unsigned(7 downto 0);  
      
      VI_CTRL_TYPE         : in unsigned(1 downto 0);
      VI_CTRL_SERRATE      : in std_logic;
      VI_ORIGIN            : in unsigned(23 downto 0);
      VI_WIDTH             : in unsigned(11 downto 0);
      VI_X_SCALE_FACTOR    : in unsigned(11 downto 0);
      VI_Y_SCALE_FACTOR    : in unsigned(11 downto 0);
      VI_Y_SCALE_OFFSET    : in unsigned(11 downto 0);
      VI_V_VIDEO_START     : in unsigned(9 downto 0);
      VI_V_VIDEO_END       : in unsigned(9 downto 0);
      
      newLine              : out std_logic;
      VI_CURRENT           : out unsigned(9 downto 0);
      
      rdram_request        : out std_logic := '0';
      rdram_rnw            : out std_logic := '0'; 
      rdram_address        : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount     : out unsigned(9 downto 0):= (others => '0');
      rdram_granted        : in  std_logic;
      rdram_done           : in  std_logic;
      ddr3_DOUT            : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY      : in  std_logic;
        
      video_hsync          : out std_logic := '0';
      video_vsync          : out std_logic := '0';
      video_hblank         : out std_logic := '0';
      video_vblank         : out std_logic := '0';
      video_ce             : out std_logic;
      video_interlace      : out std_logic;
      video_r              : out std_logic_vector(7 downto 0);
      video_g              : out std_logic_vector(7 downto 0);
      video_b              : out std_logic_vector(7 downto 0);
      
      SS_VI_CURRENT        : in unsigned(9 downto 0);
      SS_nextHCount        : in unsigned(11 downto 0)
   );
end entity;

architecture arch of VI_videoout is

   function to_unsigned(a : string) return unsigned is
      variable ret : unsigned(a'length*8-1 downto 0);
   begin
      for i in 1 to a'length loop
         ret((a'length - i)*8+7 downto (a'length - i)*8) := to_unsigned(character'pos(a(i)), 8);
      end loop;
      return ret;
   end function to_unsigned;
   
   function conv_number(a : unsigned) return unsigned is
      variable ret : unsigned((a'length * 2) -1 downto 0);
   begin
      for i in 0 to (a'length / 4)-1 loop
         if (a(((i * 4) + 3) downto (i * 4)) < 10) then
            ret(((i * 8) + 7) downto (i * 8)) := resize(a(((i * 4) + 3) downto (i * 4)), 8) + 16#30#;
         else
            ret(((i * 8) + 7) downto (i * 8)) := resize(a(((i * 4) + 3) downto (i * 4)), 8) + 16#37#;
         end if;
      end loop;
      return ret;
   end function conv_number;

   signal videoout_settings       : tvideoout_settings;
   signal videoout_reports        : tvideoout_reports;
   signal videoout_out            : tvideoout_out; 
   signal videoout_request        : tvideoout_request;  

   -- data fetch
   signal videoout_readAddr       : unsigned(11 downto 0);
   signal videoout_pixelRead      : std_logic_vector(15 downto 0);
   
   signal lineScaled              : unsigned(20 downto 0);
   
   signal rdram_address_calc      : unsigned(23 downto 0):= (others => '0');
   signal rdram_burstcount_calc   : unsigned(8 downto 0):= (others => '0'); 
   
   type tState is
   (
      WAITNEWLINE,
      WAITREQUEST,
      WAITGRANT,
      WAITREAD
   );
   signal state : tState := WAITNEWLINE;
   
   signal waitcnt             : integer range 0 to 3;
   
   signal lineAct             : unsigned(8 downto 0) := (others => '0');
   signal fillAddr            : unsigned(9 downto 0) := (others => '0');
   signal store               : std_logic := '0';

   -- overlay
   signal overlay_data        : std_logic_vector(23 downto 0);
   signal overlay_ena         : std_logic;
   
   signal fpstext             : unsigned(15 downto 0);
   signal overlay_fps_data    : std_logic_vector(23 downto 0);
   signal overlay_fps_ena     : std_logic;
   
   signal errortext           : unsigned(39 downto 0);
   signal overlay_error_data  : std_logic_vector(23 downto 0);
   signal overlay_error_ena   : std_logic;   
   
begin 
  
   video_hsync          <= videoout_out.hsync;         
   video_vsync          <= videoout_out.vsync;         
   video_hblank         <= videoout_out.hblank;        
   video_vblank         <= videoout_out.vblank;        
   video_ce             <= videoout_out.ce;             
   video_interlace      <= videoout_out.interlace;             
   video_r              <= videoout_out.r;             
   video_g              <= videoout_out.g;             
   video_b              <= videoout_out.b;  

   videoout_settings.CTRL_TYPE      <= VI_CTRL_TYPE;
   videoout_settings.CTRL_SERRATE   <= VI_CTRL_SERRATE;
   videoout_settings.X_SCALE_FACTOR <= VI_X_SCALE_FACTOR;
   videoout_settings.VI_WIDTH       <= VI_WIDTH;
   videoout_settings.isPAL          <= '0';
   videoout_settings.videoSizeY     <= VI_V_VIDEO_END - VI_V_VIDEO_START;
   
   newLine    <= videoout_reports.newLine;
   VI_CURRENT <= videoout_reports.VI_CURRENT & '0'; -- todo: need to find when interlace sets bit 0, can't be instant, otherwise Kroms CPU tests would hang in infinite loop 
   
   igpu_videoout_sync : entity work.gpu_videoout_sync
   port map
   (
      clk1x                   => clk1x,
      ce                      => ce,   
      reset                   => reset_1x,
               
      videoout_settings       => videoout_settings,
      videoout_reports        => videoout_reports,                 
                                                                      
      videoout_request        => videoout_request, 
      videoout_readAddr       => videoout_readAddr,  
      videoout_pixelRead      => videoout_pixelRead,   
   
      overlay_data            => overlay_data,
      overlay_ena             => overlay_ena,                     
                   
      videoout_out            => videoout_out,

      SS_VI_CURRENT           => SS_VI_CURRENT,
      SS_nextHCount           => SS_nextHCount
   );   
   
   rdram_rnw <= '1';
   
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (videoout_out.vblank = '1') then
            lineScaled <= resize(VI_Y_SCALE_OFFSET & '0', lineScaled'length);
         elsif (videoout_request.lineInNext /= lineAct and videoout_request.fetch = '1') then  
            lineScaled <= lineScaled + VI_Y_SCALE_FACTOR;     
         end if;
         
         if (VI_CTRL_TYPE = "10") then
            rdram_address_calc    <= VI_ORIGIN + to_unsigned(to_integer(lineScaled(lineScaled'left downto 10)) * to_integer(VI_WIDTH) * 2, 24);
            if (VI_X_SCALE_FACTOR > x"200") then -- hack for 320/640 pixel width
               rdram_burstcount_calc <= 9x"A0";
            else
               rdram_burstcount_calc <= 9x"50";
            end if;
         elsif (VI_CTRL_TYPE = "11") then
            rdram_address_calc    <= VI_ORIGIN + to_unsigned(to_integer(lineScaled(lineScaled'left downto 10)) * to_integer(VI_WIDTH) * 4, 24);
            if (VI_X_SCALE_FACTOR > x"200") then -- hack for 320/640 pixel width
               rdram_burstcount_calc <= 9x"140";
            else
               rdram_burstcount_calc <= 9x"A0";
            end if;
         end if;
   
      end if;
   end process;
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         
         rdram_request <= '0';
         
         case (state) is
         
            when WAITNEWLINE =>
               if (videoout_request.lineInNext /= lineAct and videoout_request.fetch = '1') then
                  waitcnt <= 3;
                  state   <= WAITREQUEST;
                  if (use2Xclock = '0') then
                     lineAct  <= videoout_request.lineInNext;
                     fillAddr <= videoout_request.lineInNext(0) & 9x"000";
                  end if;
               end if;
               
            when WAITREQUEST => 
            
               rdram_address     <= "0000" & rdram_address_calc;
               rdram_burstcount  <= '0' & rdram_burstcount_calc;
               
               if (use2Xclock = '1') then
                  lineAct  <= videoout_request.lineInNext;
                  fillAddr <= videoout_request.lineInNext(0) & 9x"000";
               end if;
               
               --if (videoout_settings.GPUSTAT_VerRes = '1') then
               --   fillAddr(8)  <= videoout_request.lineInNext(1);
               --end if;
            
               if (waitcnt > 0) then
                  waitcnt <= waitcnt - 1;
               else
                  if (VI_CTRL_TYPE = "10") then
                     state            <= WAITGRANT;
                     rdram_request    <= '1';
                  elsif (VI_CTRL_TYPE = "11") then
                     state            <= WAITGRANT;
                     rdram_request    <= '1';
                  else 
                     state <= WAITNEWLINE;
                  end if;
               end if;
               
            when WAITGRANT => 
               if (rdram_granted = '1') then
                  state <= WAITREAD;
                  store <= '1';
               end if;
            
            when WAITREAD  => 
               if (ddr3_DOUT_READY = '1') then
                  fillAddr <= fillAddr + 1;
               end if;
               if (rdram_done = '1') then
                  store  <= '0';
                  state <= WAITNEWLINE; 
               end if;
         
         end case;
         
      end if;
   end process; 
   
   ilineram: entity mem.dpram_dif
   generic map 
   ( 
      addr_width_a  => 10,
      data_width_a  => 64,
      addr_width_b  => 12,
      data_width_b  => 16
   )
   port map
   (
      clock_a     => clk2x,
      address_a   => std_logic_vector(fillAddr),
      data_a      => ddr3_DOUT,
      wren_a      => (ddr3_DOUT_READY and store),
      
      clock_b     => clk1x,
      address_b   => std_logic_vector(videoout_readAddr),
      data_b      => x"0000",
      wren_b      => '0',
      q_b(7 downto  0) => videoout_pixelRead(15 downto 8),
      q_b(15 downto 8) => videoout_pixelRead(7 downto 0)
   );   
   
   -- texts
   fpstext( 7 downto 0) <= resize(fpscountBCD(3 downto 0), 8) + 16#30#;
   fpstext(15 downto 8) <= resize(fpscountBCD(7 downto 4), 8) + 16#30#;
   
   ioverlayFPS : entity work.VI_overlay generic map (2, 4, 4, x"0000FF")
   port map
   (
      clk                    => clk1x,
      ce                     => videoout_out.ce,
      ena                    => fpscountOn,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => overlay_fps_data,
      o_pixel_out_ena        => overlay_fps_ena,
      textstring             => fpstext
   );
   
   errortext( 7 downto  0) <= resize(errorCode( 3 downto  0), 8) + 16#30# when (errorCode( 3 downto  0) < 10) else resize(errorCode( 3 downto  0), 8) + 16#37#;
   errortext(15 downto  8) <= resize(errorCode( 7 downto  4), 8) + 16#30# when (errorCode( 7 downto  4) < 10) else resize(errorCode( 7 downto  4), 8) + 16#37#;
   errortext(23 downto 16) <= resize(errorCode(11 downto  8), 8) + 16#30# when (errorCode(11 downto  8) < 10) else resize(errorCode(11 downto  8), 8) + 16#37#;
   errortext(31 downto 24) <= resize(errorCode(15 downto 12), 8) + 16#30# when (errorCode(15 downto 12) < 10) else resize(errorCode(15 downto 12), 8) + 16#37#;
   errortext(39 downto 32) <= resize(errorCode(19 downto 16), 8) + 16#30# when (errorCode(19 downto 16) < 10) else resize(errorCode(19 downto 16), 8) + 16#37#;
   ioverlayError : entity work.VI_overlay generic map (6, 4, 44, x"0000FF")
   port map
   (
      clk                    => clk1x,
      ce                     => videoout_out.ce,
      ena                    => errorEna,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => overlay_error_data,
      o_pixel_out_ena        => overlay_error_ena,
      textstring             => x"45" & errortext
   ); 
   
   overlay_ena <= overlay_fps_ena or overlay_error_ena;
   
   overlay_data <= overlay_fps_data   when (overlay_fps_ena = '1') else
                   overlay_error_data when (overlay_error_ena = '1') else
                   (others => '0');
   
end architecture;





