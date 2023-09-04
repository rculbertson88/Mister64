
vcom -93 -quiet -work  sim/tb ^
src/tb/globals.vhd

vcom -93 -quiet -work sim/mem ^
../system/src/mem/dpram.vhd ^
../system/src/mem/RamMLAB.vhd

vcom -93 -quiet -work sim/n64 ^
../system/src/mem/dpram.vhd

vcom -93 -quiet -work  sim/mem ^
../../rtl/SyncFifo.vhd ^
../../rtl/SyncFifoFallThrough.vhd ^
../../rtl/SyncFifoFallThroughMLAB.vhd ^
../../rtl/SyncRam.vhd

vcom -quiet -work  sim/rs232 ^
src/rs232/rs232_receiver.vhd ^
src/rs232/rs232_transmitter.vhd ^
src/rs232/tbrs232_receiver.vhd ^
src/rs232/tbrs232_transmitter.vhd

vcom -quiet -work sim/procbus ^
src/procbus/proc_bus.vhd ^
src/procbus/testprocessor.vhd

vcom -quiet -work sim/reg_map ^
src/reg_map/reg_tb.vhd

vcom -2008 -quiet -work sim/n64 ^
../../rtl/functions.vhd ^
../../rtl/export.vhd ^
../../rtl/cpu_instrcache.vhd ^
../../rtl/cpu_datacache.vhd ^
../../rtl/divider.vhd ^
../../rtl/cpu_cop0.vhd ^
src/tb/cpu_mul.vhd ^
../../rtl/cpu_FPU_sqrt.vhd ^
../../rtl/cpu_FPU.vhd ^
../../rtl/cpu.vhd ^
../../rtl/memorymux.vhd ^
../../rtl/pifrom_ntsc_fast.vhd ^
../../rtl/PIF.vhd ^
../../rtl/RSP_package.vhd ^
../../rtl/RSP_divtable.vhd ^
../../rtl/RSP_divsqrt.vhd ^
../../rtl/RSP_vector.vhd ^
../../rtl/RSP_core.vhd ^
../../rtl/RSP.vhd ^
../../rtl/PI.vhd ^
../../rtl/VI_package.vhd ^
../../rtl/VI_overlay.vhd ^
../../rtl/VI_videoout_sync.vhd ^
../../rtl/VI_videoout.vhd ^
../../rtl/VI.vhd ^
../../rtl/AI.vhd ^
../../rtl/SI.vhd ^
../../rtl/RI.vhd ^
../../rtl/MI.vhd ^
../../rtl/RDRAMRegs.vhd ^
../../rtl/RDP_package.vhd ^
../../rtl/RDP_command.vhd ^
../../rtl/RDP_raster.vhd ^
../../rtl/RDP_TexCoordClamp.vhd ^
../../rtl/RDP_TexTile.vhd ^
../../rtl/RDP_TexSingle.vhd ^
../../rtl/RDP_TexFetch.vhd ^
../../rtl/RDP_FBread.vhd ^
../../rtl/RDP_CombineColor.vhd ^
../../rtl/RDP_CombineAlpha.vhd ^
../../rtl/RDP_BlendColor.vhd ^
../../rtl/RDP_Zbuffer.vhd ^
../../rtl/RDP_pipeline.vhd ^
../../rtl/RDP.vhd ^
../../rtl/DDR3Mux.vhd ^
../../rtl/SDRamMux.vhd ^
../../rtl/statemanager.vhd ^
../../rtl/savestates.vhd ^
../../rtl/savemem.vhd ^
../../rtl/n64top.vhd 

vcom -2008 -quiet -work sim/tb ^
src/tb/stringprocessor.vhd ^
src/tb/tb_interpreter.vhd ^
src/tb/ddrram_model.vhd ^
src/tb/sdram_model.vhd ^
src/tb/framebuffer.vhd ^
src/tb/tb.vhd

