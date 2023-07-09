vcom -93 -quiet -work  sim/mem ^
../system/src/mem/dpram.vhd ^
../system/src/mem/RamMLAB.vhd

vcom -93 -quiet -work sim/n64 ^
../system/src/mem/dpram.vhd

vcom -2008 -quiet -work sim/n64 ^
../../rtl/pifrom_ntsc_fast.vhd ^
../../rtl/PIF.vhd

vcom -2008 -quiet -work sim/tb ^
src/tb/tb.vhd

