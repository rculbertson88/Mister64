//============================================================================
//  N64 for MiSTer
//  Copyright (C) 2023 Robert Peip
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
   output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign HDMI_FREEZE = 1'b0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = status[8:7];

assign LED_USER  = 0;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VIDEO_ARX = 12'd4;
assign VIDEO_ARY = 12'd3;

///////////////////////  CLOCK/RESET  ///////////////////////////////////

wire clk_1x;
wire clk_93;
wire clk_2x;
wire clk_vid;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_1x),
	.outclk_1(clk_93),
	.outclk_2(clk_2x),
   .locked(pll_locked)
);

pll2 pll2
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid)
);

wire reset_or = RESET | buttons[1] | status[0] | cart_download;

////////////////////////////  HPS I/O  //////////////////////////////////

// Status Bit Map: (0..31 => "O", 32..63 => "o")
// 0         1         2         3          4         5         6          7         8         9
// 01234567890123456789012345678901 23456789012345678901234567890123 45678901234567890123456789012345
// todo
// 

`include "build_id.v"
parameter CONF_STR = {
	"N64;SS3C000000:1000000;",
   "FS1,N64z64n64v64,Load;",
   "-;",
	"O[36],Savestates to SDCard,On,Off;",
	"O[3],Autoincrement Slot,Off,On;",
	"O[38:37],Savestate Slot,1,2,3,4;",
	"RH,Save state (Alt-F1);",
	"RI,Restore state (F1);",
	"-;",
   "O[11],Write Bit 9,Off,On;",
   "O[12],Read Bit 9,Off,On;",
   "O[13],Wait Bit 9,Off,On;",
	"-;",
   "O[1],Swap Interlaced,Off,On;",
   "O[2],Error Overlay,Off,On;",
   "O[28],FPS Overlay,Off,On;",
   "O[10:9],EEPROM type,None,4 KBit,16 KBit;",
   "O[8:7],Stereo Mix,None,25%,50%,100%;",
   "-;",
   
   "P2,System settings;",
	"P2-;",
   "P2-,WIP-no function yet!;",
	"P2O[64],Auto Detect,On,Off;",
   "P2O[70],RAM size,8MByte,4MByte;",
   "P2O[80:79],System Type,NTSC,PAL;",
	"P2O[68:65],CIC,6101,6102,7101,7102,6103,7103,6105,7105,6106,7106,8303,8401,5167,DDUS;",
   "P2O[71],ControllerPak,Off,On;",
   "P2O[72],RumblePak,Off,On;",
   "P2O[73],TransferPak,Off,On;",
   "P2O[74],RTC,Off,On;",
   "P2O[77:75],Save Type,None,EEPROM4,EEPROM16,SRAM32,SRAM96,Flash;",
   "-;",
   
	"R0,Reset;",
   "J1,A,B,Start,L,R,Z,C Up,C Right,C Down,C Left,Savestates;",
	"jn,A,B,Start,L,R,Z,C Up,C Right,C Down,C Left;",
	"I,",
	"Load=DPAD Up|Save=Down|Slot=L+R,",
	"Active Slot 1,",
	"Active Slot 2,",
	"Active Slot 3,",
	"Active Slot 4,",
	"Save to state 1,",
	"Restore state 1,",
	"Save to state 2,",
	"Restore state 2,",
	"Save to state 3,",
	"Restore state 3,",
	"Save to state 4,",
	"Restore state 4;",
	"V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [127:0] status;
wire        forced_scandoubler;

wire [19:0] joy;
wire [19:0] joy_unmod;
wire [19:0] joy2;
wire [19:0] joy3;
wire [19:0] joy4;

wire [15:0] joystick_analog_l0;
wire [15:0] joystick_analog_l1;
wire [15:0] joystick_analog_l2;
wire [15:0] joystick_analog_l3;

wire [10:0] ps2_key;

wire [127:0] status_in = {status[127:39],ss_slot,status[36:0]};
wire [15:0] status_menumask = 16'd0;


wire bk_pending;
wire DIRECT_VIDEO;

wire        ioctl_download;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
reg         ioctl_wait = 0;

reg [7:0] info_index;
reg info_req;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_1x),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),

   .ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),

   .joystick_0(joy_unmod),
	.joystick_1(joy2),
	.joystick_2(joy3),
	.joystick_3(joy4),
	.ps2_key(ps2_key),

	.status(status),
	.status_in(status_in),
	.status_set(statusUpdate),
	.status_menumask(status_menumask),
	.info_req(info_req),
	.info(info_index),
   
   .joystick_l_analog_0(joystick_analog_l0), 
   .joystick_l_analog_1(joystick_analog_l1),
   .joystick_l_analog_2(joystick_analog_l2),
   .joystick_l_analog_3(joystick_analog_l3),
   
   .direct_video(DIRECT_VIDEO)
);

assign joy = joy_unmod[14] ? 20'b0 : joy_unmod;

////////////////////////////  PIFROM download  ///////////////////////////////////

reg  [8:0] pifrom_wraddress;
reg [31:0] pifrom_wrdata;   
reg        pifrom_wren;   
reg        pifrom_download;


always @(posedge clk_1x) begin

   pifrom_download   <= ioctl_download & (ioctl_index[5:0] == 0);

	pifrom_wren <= 0;
	if(pifrom_download) begin
      if (ioctl_wr) begin
         if(~ioctl_addr[1]) begin
            pifrom_wrdata[31:24] <= ioctl_dout[7:0];
            pifrom_wrdata[23:16] <= ioctl_dout[15:8];
            pifrom_wraddress    <= ioctl_addr[10:2];                                  
         end else begin
            pifrom_wrdata[15:8] <= ioctl_dout[7:0];
            pifrom_wrdata[7:0]  <= ioctl_dout[15:8];
            pifrom_wren          <= 1;
         end
      end
	end
   
end

////////////////////////////  SDRAM  ///////////////////////////////////

reg [26:0] ramdownload_wraddr;
reg [31:0] ramdownload_wrdata;
reg        ramdownload_wr;
wire       ramdownload_ready;
reg        cart_download;
reg        cart_loaded = 0;

localparam CART_START = 8388608;

always @(posedge clk_1x) begin

   cart_download     <= ioctl_download & (ioctl_index[5:0] == 1);

	ramdownload_wr <= 0;
	if(cart_download) begin
      cart_loaded <= 1;
      if (ioctl_wr) begin
         if(~ioctl_addr[1]) begin
            ramdownload_wrdata[15:0] <= ioctl_dout;
            ramdownload_wraddr <= ioctl_addr[26:0] + CART_START[26:0];                                  
         end else begin
            ramdownload_wrdata[31:16] <= ioctl_dout;
            ramdownload_wr            <= 1;
            ioctl_wait                <= 1;
         end
      end
      if(ramdownload_ready) ioctl_wait <= 0;
   end else begin 
      ioctl_wait <= 0;
	end
   
end

wire        sdram_ena;
wire        sdram_rnw;
wire [26:0] sdram_Adr;
wire  [3:0] sdram_be;
wire [31:0] sdram_dataWrite;
wire        sdram_done;  
wire [31:0] sdram_dataRead;

sdram sdram
(
	.*,
	.init(~pll_locked),
	.clk(clk_1x),

	.ch1_addr(sdram_Adr),
	.ch1_din(sdram_dataWrite),
	.ch1_dout(sdram_dataRead),
	.ch1_req(sdram_ena),
	.ch1_rnw(sdram_rnw),
	.ch1_be(sdram_be),
	.ch1_ready(sdram_done),

	.ch2_addr (ramdownload_wraddr),
	.ch2_din  (ramdownload_wrdata),
	.ch2_dout (),
	.ch2_req  (ramdownload_wr),
	.ch2_rnw  (1'b0),
	.ch2_ready(ramdownload_ready),

	.ch3_addr(27'b0),
	.ch3_din(16'b0),
	.ch3_dout(),
	.ch3_req(1'b0),
	.ch3_rnw(1'b1),
	.ch3_ready()
);

///////////////////////////  SAVESTATE  /////////////////////////////////

wire [1:0] ss_slot;
wire [7:0] ss_info;
wire ss_save, ss_load, ss_info_req;
wire statusUpdate;

savestate_ui savestate_ui
(
	.clk            (clk_1x        ),
	.ps2_key        (ps2_key[10:0] ),
	.allow_ss       (cart_loaded   ),
	.joySS          (joy_unmod[14] ),
	.joyRight       (joy_unmod[0]  ),
	.joyLeft        (joy_unmod[1]  ),
	.joyDown        (joy_unmod[2]  ),
	.joyUp          (joy_unmod[3]  ),
	.joyRewind      (0             ),
	.rewindEnable   (0             ), 
	.status_slot    (status[38:37] ),
	.autoincslot    (status[3]     ),
	.OSD_saveload   (status[18:17] ),
	.ss_save        (ss_save       ),
	.ss_load        (ss_load       ),
	.ss_info_req    (info_req      ),
	.ss_info        (info_index    ),
	.statusUpdate   (statusUpdate  ),
	.selected_slot  (ss_slot       )
);
defparam savestate_ui.INFO_TIMEOUT_BITS = 25;

////////////////////////////  SYSTEM  ///////////////////////////////////

wire HBlank;
wire VBlank;
wire Interlaced;

assign DDRAM_CLK = clk_2x;

n64top n64top
(
   .clk1x(clk_1x),          
   .clk93(clk_93),          
   //.clk93(clk_1x),          
   .clk2x(clk_2x),          
   .clkvid(clk_vid),
   .reset(reset_or),
   .pause(OSD_STATUS),
   .errorCodesOn(status[2]),
   .fpscountOn(status[28]),
   
   .CICTYPE(status[68:65]),
   
   .write9(status[11]), 
   .read9(status[12]),  
   .wait9(status[13]),  
   
   // savestates              
   .increaseSSHeaderCount (!status[36]),
   .save_state            (ss_save),
   .load_state            (ss_load),
   .savestate_number      (ss_slot),
   .state_loaded          (),
   
   // PIFROM download port
   .pifrom_wraddress (pifrom_wraddress),
   .pifrom_wrdata    (pifrom_wrdata   ),
   .pifrom_wren      (pifrom_wren     ),
   
   // RDRAM
   .ddr3_BUSY        (DDRAM_BUSY      ),
   .ddr3_BURSTCNT    (DDRAM_BURSTCNT  ),
   .ddr3_ADDR        (DDRAM_ADDR      ),
   .ddr3_DOUT        (DDRAM_DOUT      ),
   .ddr3_DOUT_READY  (DDRAM_DOUT_READY),
   .ddr3_RD          (DDRAM_RD        ),
   .ddr3_DIN         (DDRAM_DIN       ),
   .ddr3_BE          (DDRAM_BE        ),
   .ddr3_WE          (DDRAM_WE        ),
   
   // ROM+SRAM+FLASH
   .sdram_ena        (sdram_ena      ),
   .sdram_rnw        (sdram_rnw      ),
   .sdram_Adr        (sdram_Adr      ),
   .sdram_be         (sdram_be       ),
   .sdram_dataWrite  (sdram_dataWrite),
   .sdram_done       (sdram_done     ),
   .sdram_dataRead   (sdram_dataRead ),
      
   // pad
   .pad_0_A          (joy[4]),
   .pad_0_B          (joy[5]),
   .pad_0_Z          (joy[9]),
   .pad_0_START      (joy[6]),
   .pad_0_DPAD_UP    (joy[3]),
   .pad_0_DPAD_DOWN  (joy[2]),
   .pad_0_DPAD_LEFT  (joy[1]),
   .pad_0_DPAD_RIGHT (joy[0]),
   .pad_0_L          (joy[7]),
   .pad_0_R          (joy[8]),
   .pad_0_C_UP       (joy[10]),
   .pad_0_C_DOWN     (joy[12]),
   .pad_0_C_LEFT     (joy[13]),
   .pad_0_C_RIGHT    (joy[11]),
   .pad_0_analog_h   (joystick_analog_l0[7:0]),
   .pad_0_analog_v   (joystick_analog_l0[15:8]),
      
   // audio
   .sound_out_left   (AUDIO_L),
   .sound_out_right  (AUDIO_R),  
   
   // Saves
   .EEPROMTYPE       (status[10:9]),
   
   // video out   
   .video_hsync      (VGA_HS),
   .video_vsync      (VGA_VS),
   .video_hblank     (HBlank),
   .video_vblank     (VBlank),
   .video_ce         (CE_PIXEL),
   .video_interlace  (Interlaced),
   .video_r          (VGA_R),
   .video_g          (VGA_G),
   .video_b          (VGA_B)
);

assign CLK_VIDEO = clk_1x;
assign VGA_DE = ~(HBlank | VBlank);
assign VGA_F1 = Interlaced ^ status[1];
assign VGA_SL = 0;
assign VGA_DISABLE = 0;


endmodule

      
      

  
      
       
        
        
        