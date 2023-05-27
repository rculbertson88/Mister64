--space.name = {address, upper, lower, size, default}
n64 = {}
n64.Reg_n64_on = {1056768,0,0,1,0,"n64.Reg_n64_on"} -- on = 1
n64.Reg_n64_lockspeed = {1056769,0,0,1,0,"n64.Reg_n64_lockspeed"} -- 1 = 100% speed
n64.Reg_n64_flash_1m = {1056770,0,0,1,0,"n64.Reg_n64_flash_1m"}
n64.Reg_n64_CyclePrecalc = {1056771,15,0,1,100,"n64.Reg_n64_CyclePrecalc"}
n64.Reg_n64_CyclesMissing = {1056772,31,0,1,0,"n64.Reg_n64_CyclesMissing"}
n64.Reg_n64_BusAddr = {1056773,27,0,1,0,"n64.Reg_n64_BusAddr"}
n64.Reg_n64_BusRnW = {1056773,28,28,1,0,"n64.Reg_n64_BusRnW"}
n64.Reg_n64_BusACC = {1056773,30,29,1,0,"n64.Reg_n64_BusACC"}
n64.Reg_n64_BusWriteData = {1056774,31,0,1,0,"n64.Reg_n64_BusWriteData"}
n64.Reg_n64_BusReadData = {1056775,31,0,1,0,"n64.Reg_n64_BusReadData"}
n64.Reg_n64_MaxPakAddr = {1056776,24,0,1,0,"n64.Reg_n64_MaxPakAddr"}
n64.Reg_n64_VsyncSpeed = {1056777,31,0,1,0,"n64.Reg_n64_VsyncSpeed"}
n64.Reg_n64_KeyUp = {1056778,0,0,1,0,"n64.Reg_n64_KeyUp"}
n64.Reg_n64_KeyDown = {1056778,1,1,1,0,"n64.Reg_n64_KeyDown"}
n64.Reg_n64_KeyLeft = {1056778,2,2,1,0,"n64.Reg_n64_KeyLeft"}
n64.Reg_n64_KeyRight = {1056778,3,3,1,0,"n64.Reg_n64_KeyRight"}
n64.Reg_n64_KeyA = {1056778,4,4,1,0,"n64.Reg_n64_KeyA"}
n64.Reg_n64_KeyB = {1056778,5,5,1,0,"n64.Reg_n64_KeyB"}
n64.Reg_n64_KeyL = {1056778,6,6,1,0,"n64.Reg_n64_KeyL"}
n64.Reg_n64_KeyR = {1056778,7,7,1,0,"n64.Reg_n64_KeyR"}
n64.Reg_n64_KeyStart = {1056778,8,8,1,0,"n64.Reg_n64_KeyStart"}
n64.Reg_n64_KeySelect = {1056778,9,9,1,0,"n64.Reg_n64_KeySelect"}
n64.Reg_n64_cputurbo = {1056780,0,0,1,0,"n64.Reg_n64_cputurbo"} -- 1 = cpu free running, all other 16 mhz
n64.Reg_n64_SramFlashEna = {1056781,0,0,1,0,"n64.Reg_n64_SramFlashEna"} -- 1 = enabled, 0 = disable (disable for copy protection in some games)
n64.Reg_n64_MemoryRemap = {1056782,0,0,1,0,"n64.Reg_n64_MemoryRemap"} -- 1 = enabled, 0 = disable (enable for copy protection in some games)
n64.Reg_n64_SaveState = {1056783,0,0,1,0,"n64.Reg_n64_SaveState"}
n64.Reg_n64_LoadState = {1056784,0,0,1,0,"n64.Reg_n64_LoadState"}
n64.Reg_n64_FrameBlend = {1056785,0,0,1,0,"n64.Reg_n64_FrameBlend"} -- mix last and current frame
n64.Reg_n64_Pixelshade = {1056786,2,0,1,0,"n64.Reg_n64_Pixelshade"} -- pixel shade 1..4, 0 = off
n64.Reg_n64_SaveStateAddr = {1056787,25,0,1,0,"n64.Reg_n64_SaveStateAddr"} -- address to save/load savestate
n64.Reg_n64_Rewind_on = {1056788,0,0,1,0,"n64.Reg_n64_Rewind_on"}
n64.Reg_n64_Rewind_active = {1056789,0,0,1,0,"n64.Reg_n64_Rewind_active"}
n64.Reg_n64_LoadExe = {1056790,0,0,1,0,"n64.Reg_n64_LoadExe"}
n64.Reg_n64_DEBUG_CPU_PC = {1056800,31,0,1,0,"n64.Reg_n64_DEBUG_CPU_PC"}
n64.Reg_n64_DEBUG_CPU_MIX = {1056801,31,0,1,0,"n64.Reg_n64_DEBUG_CPU_MIX"}
n64.Reg_n64_DEBUG_IRQ = {1056802,31,0,1,0,"n64.Reg_n64_DEBUG_IRQ"}
n64.Reg_n64_DEBUG_DMA = {1056803,31,0,1,0,"n64.Reg_n64_DEBUG_DMA"}
n64.Reg_n64_DEBUG_MEM = {1056804,31,0,1,0,"n64.Reg_n64_DEBUG_MEM"}
n64.Reg_n64_CHEAT_FLAGS = {1056810,31,0,1,0,"n64.Reg_n64_CHEAT_FLAGS"}
n64.Reg_n64_CHEAT_ADDRESS = {1056811,31,0,1,0,"n64.Reg_n64_CHEAT_ADDRESS"}
n64.Reg_n64_CHEAT_COMPARE = {1056812,31,0,1,0,"n64.Reg_n64_CHEAT_COMPARE"}
n64.Reg_n64_CHEAT_REPLACE = {1056813,31,0,1,0,"n64.Reg_n64_CHEAT_REPLACE"}
n64.Reg_n64_CHEAT_RESET = {1056814,0,0,1,0,"n64.Reg_n64_CHEAT_RESET"}