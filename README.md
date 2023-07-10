
## Hardware Requirements
SDRAM of any size is required.

## Bios
Rename your PIF ROM file (e.g. `pif.ntsc.rom` ) and place it in the `./games/N64/` folder as `boot.rom`

## Video output

Only HDMI supported for now.

## Error messages

If there is a recognized problem, an overlay is displayed, showing which error has occured.
Errors are hex encoded by bits, so the error code can represent more than 1 error.

List of Errors:
- Bit 0 - Memory access to unmapped area
- Bit 1 - CPU Instruction not implemented
- Bit 2 - CPU stall timeout
- Bit 3 - DDR3 timeout    
- Bit 4 - FPU error    
- Bit 5 - PI error
- Bit 6 - critical Exception occured (heuristic, typically games crash when that happens, but can be false positive)
  
## Status

work in progress