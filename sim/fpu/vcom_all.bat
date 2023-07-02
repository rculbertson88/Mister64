vcom -93 -quiet -work  sim/mem ^
../system/src/mem/dpram.vhd ^
../system/src/mem/RamMLAB.vhd

vcom -2008 -quiet -work sim/n64 ^
../../rtl/cpu_FPU_sqrt.vhd ^
../../rtl/cpu_FPU.vhd

vcom -2008 -quiet -work sim/tb ^
src/tb/tb.vhd

