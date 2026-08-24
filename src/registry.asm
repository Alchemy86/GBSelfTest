; registry.asm — what runs, in what order, under what code, and what a failure
; means in one line.
;
; The order matters and is not alphabetical. The CPU comes first because
; everything below it is written in instructions; the clocks come next because
; every timing measurement is expressed in them; the PPU and the APU come last
; because their checks are built on both. A failure high up can cascade, and
; the report is meant to be read top to bottom.
;
; Every check's code is stable for the life of the cartridge. Codes are never
; reused and never renumbered: a code is an anchor on a documentation page and
; a search term in somebody's bug tracker.
;
; The documentation page is per area rather than global so that a fork can send
; its readers somewhere else without touching anything but this table. They all
; point at the same page today; that page carries one heading per code and
; links on to the deeper write-ups.

INCLUDE "hardware.inc"

MACRO area
    dw \1                   ; name
    dw \2                   ; code prefix
    dw \3                   ; the check list
    dw \4                   ; the documentation page a failure points at
    db \5                   ; the ROM bank the check routines live in
ENDM

MACRO check
    dw \1                   ; routine
    db \2                   ; number, printed as GB-<area>-NN
    dw \3                   ; name
    dw \4                   ; what a failure means
ENDM

SECTION "Registry", ROM0

AreaTable::
    area NmCpu, PfxCpu, ListCpu, DocCpu, 1
    area NmCyc, PfxCyc, ListCyc, DocCyc, 2
    area NmTim, PfxTim, ListTim, DocTim, 2
    area NmInt, PfxInt, ListInt, DocInt, 2
    area NmMem, PfxMem, ListMem, DocMem, 2
    area NmPpu, PfxPpu, ListPpu, DocPpu, 3
    area NmDma, PfxDma, ListDma, DocDma, 3
    area NmApu, PfxApu, ListApu, DocApu, 3
    area NmMbc, PfxMbc, ListMbc, DocMbc, 0
    area NmBoot, PfxBoot, ListBoot, DocBoot, 3
    area NmSer, PfxSer, ListSer, DocSer, 3
    dw 0

; ---------------------------------------------------------------------------
NmCpu:  db "CPU: instruction behaviour and flags",0
PfxCpu: db "CPU",0
DocCpu: db "gbselftest.md",0

ListCpu:
    check ChkAdd,     1, NmAdd,     ExAdd
    check ChkSub,     2, NmSub,     ExSub
    check ChkLogic,   3, NmLogic,   ExLogic
    check ChkIncDec,  4, NmIncDec,  ExIncDec
    check ChkRotate,  5, NmRotate,  ExRotate
    check ChkBitOps,  6, NmBitOps,  ExBitOps
    check ChkPopAf,   7, NmPopAf,   ExPopAf
    check ChkSpAdd,   8, NmSpAdd,   ExSpAdd
    check ChkAddHl,   9, NmAddHl,   ExAddHl
    check ChkFlagOps,10, NmFlagOps, ExFlagOps
    check ChkInc16,  11, NmInc16,   ExInc16
    check ChkDaa,    12, NmDaa,     ExDaa
    check ChkRotateZ,13, NmRotateZ, ExRotateZ
    check ChkIncHl,  14, NmIncHl,   ExIncHl
    check ChkHlIncDec,15,NmHlIncDec,ExHlIncDec
    dw 0

; The CPU area's prose lives in the CPU area's own bank rather than in the
; fixed one, and this is the only thing in this file that is not where a reader
; would first look for it. The fixed bank is full: it has to hold the print
; code, the mapper checks (which cannot be in a bank they switch away from) and
; every table above, and there is not room for ninety-odd checks' worth of
; sentences as well.
;
; It is safe because of the one rule `RunCheckList` states: the area's bank is
; mapped before the check runs and is LEFT mapped through the reporting, which
; is what lets a failure note be a pointer into that bank. A name and an
; explanation are read in exactly the same window. What may NOT move is the
; area's own name, its code prefix and its documentation page: the name is
; printed before the bank is mapped, and the prefix is read again at the very
; end of the run when the failure list is spelled back out, by which time the
; bank is whatever the last area left behind.

SECTION "RegistryTextCpu", ROMX, BANK[1]

NmAdd:     db "ADD and ADC, against a counter-built adder",0
ExAdd:     db "the sum or its flags disagree with the same addition counted out with INC HL",0
NmSub:     db "SUB, SBC and CP",0
ExSub:     db "the difference or its flags disagree with the same subtraction counted out with DEC HL",0
NmLogic:   db "AND, OR, XOR and CPL by identity",0
ExLogic:   db "a law that holds for every byte does not hold here",0
NmIncDec:  db "INC r and DEC r flags",0
ExIncDec:  db "the half carry or the preserved carry is wrong",0
NmRotate:  db "rotates and shifts are invertible",0
ExRotate:  db "a rotate is losing, duplicating or misplacing a bit",0
NmBitOps:  db "BIT, RES and SET",0
ExBitOps:  db "a bit operation reached a bit it should not have, or BIT's flags are wrong",0
NmPopAf:   db "POP AF masks the unused flag bits",0
ExPopAf:   db "F's low four bits are being stored; they do not exist on this CPU",0
NmSpAdd:   db "LD HL,SP+e flags come from the low byte",0
ExSpAdd:   db "an eight-bit carry is being taken from a sixteen-bit addition",0
NmAddHl:   db "ADD HL,rr flags",0
ExAddHl:   db "H must come from bit 11 and Z must be left alone",0
NmFlagOps: db "SCF, CCF and CPL",0
ExFlagOps: db "a flag instruction is setting where it should complement, or clearing what it should keep",0
NmInc16:   db "INC rr and DEC rr set no flags",0
ExInc16:   db "a sixteen-bit increment is writing to F",0
NmRotateZ: db "the one-byte rotates always clear Z",0
ExRotateZ: db "RLCA and its three relatives never set Z; their prefixed namesakes always do",0
NmIncHl:   db "INC and DEC through HL",0
ExIncHl:   db "a read-modify-write took its flags from the wrong byte",0
NmHlIncDec: db "the pointer forms of LD move HL",0
ExHlIncDec: db "LD [HL+] and its relatives must step the pointer after the access",0
NmDaa:     db "DAA against decimal arithmetic",0
ExDaa:     db "the decimal adjust disagrees with the same sum done a digit at a time",0


SECTION FRAGMENT "Registry2", ROM0

; ---------------------------------------------------------------------------
NmCyc:  db "CYC: instruction and memory timing",0
PfxCyc: db "CYC",0
DocCyc: db "gbselftest.md",0

ListCyc:
    check ChkCycLoad,  1, NmCycLoad,  ExCyc
    check ChkCycAlu,   2, NmCycAlu,   ExCyc
    check ChkCycStack, 3, NmCycStack, ExCyc
    check ChkCycJump,  4, NmCycJump,  ExCyc
    check ChkCycCb,    5, NmCycCb,    ExCyc
    check ChkCycMore,  6, NmCycMore,  ExCyc
    check ChkCycPhase, 7, NmCycPhase, ExCycPhase
    check ChkCycLand,  8, NmCycLand,  ExCycLand
    check ChkDoubleSpeedCyc, 9, NmCycSpeed, ExCycSpeed
    dw 0

NmCycLand:  db "an interrupt lands on the cycle it was raised",0
ExCycLand:  db "running a batch of instructions and delivering at the end of it keeps every rate right and still fails this",0
NmCycPhase: db "an access lands on its own cycle",0
ExCycPhase: db "advancing the clocks once per instruction keeps every rate right and still fails this",0
NmCycLoad:  db "loads and memory accesses",0
NmCycAlu:   db "arithmetic and sixteen-bit operations",0
NmCycStack: db "PUSH, POP, CALL and RET",0
NmCycJump:  db "jumps taken and not taken",0
NmCycCb:    db "CB-prefixed operations",0
NmCycMore:  db "restarts, returns and the register-addressed load",0
ExCyc:      db "an instruction took a different number of machine cycles from the published opcode table",0

; GB-CYC-09's name and explanation live in bank 2, the CYC/TIM area's own bank,
; on the same licence CPU's prose has in bank 1: RunCheckList maps the area's
; bank before the check runs and leaves it mapped through the reporting.
; ROM0 has no room left for another sentence (AGENTS.md, "The fixed bank is
; full").
SECTION "RegistryTextCyc", ROMX, BANK[2]

NmCycSpeed: db "KEY1's double speed switch, and what it does not change",0
ExCycSpeed: db "either the switch itself did not engage, or it changed how many machine cycles an instruction costs, which it must not",0

SECTION FRAGMENT "Registry2", ROM0

; ---------------------------------------------------------------------------
NmTim:  db "TIM: the divider and the timer",0
PfxTim: db "TIM",0
DocTim: db "gbselftest.md",0

ListTim:
    check ChkDivRate,   1, NmDivRate,   ExDivRate
    check ChkDivReset,  2, NmDivReset,  ExDivReset
    check ChkTimaRates, 3, NmTimaRates, ExTimaRates
    check ChkTimaStop,  4, NmTimaStop,  ExTimaStop
    check ChkTimaWrap,  5, NmTimaWrap,  ExTimaWrap
    check ChkDivGlitch, 6, NmDivGlitch, ExDivGlitch
    check ChkTacDisableGlitch,7,NmTacGlitch,ExTacGlitch
    dw 0

NmDivRate:   db "the divider and the timer share one counter",0
ExDivRate:   db "DIV and TIMA are not being clocked from the same chain",0
NmDivReset:  db "writing DIV clears it",0
ExDivReset:  db "a write to $FF04 must zero the whole sixteen-bit counter, not just the byte you can read",0
NmTimaRates: db "all four TAC rates, measured against DIV",0
ExTimaRates: db "a TAC rate is not the documented number of cycles per increment",0
NmTimaStop:  db "TAC bit 2 stops the timer",0
ExTimaStop:  db "TIMA moved while the timer was switched off",0
NmDivGlitch: db "writing DIV can itself clock the timer",0
ExDivGlitch: db "the timer watches a bit of the divider's counter and a write that clears that bit is a falling edge",0
NmTacGlitch: db "switching the timer off can clock it once more",0
ExTacGlitch: db "what is counted is the watched bit ANDed with the enable, so clearing the enable is itself a falling edge",0
NmTimaWrap:  db "overflow reloads TMA and raises the interrupt",0
ExTimaWrap:  db "TIMA wrapping must reload from TMA and set bit 2 of IF",0

; ---------------------------------------------------------------------------
NmInt:  db "INT: interrupts",0
PfxInt: db "INT",0
DocInt: db "gbselftest.md",0

ListInt:
    check ChkIfBits,    1, NmIfBits,    ExIfBits
    check ChkEiDelay,   2, NmEiDelay,   ExEiDelay
    check ChkEiTakes,   3, NmEiTakes,   ExEiTakes
    check ChkPriority,  4, NmPriority,  ExPriority
    check ChkHaltBug,   5, NmHaltBug,   ExHaltBug
    check ChkHaltWake,  6, NmHaltWake,  ExHaltWake
    check ChkDispatch,  7, NmDispatch,  ExDispatch
    check ChkIeBits,    8, NmIeBits,    ExIeBits
    check ChkReti,      9, NmReti,      ExReti
    check ChkIfCancel, 10, NmIfCancel,  ExIfCancel
    check ChkIeCancel, 11, NmIeCancel,  ExIeCancel
    check ChkEiSequence,12,NmEiSeq,     ExEiSeq
    dw 0

NmIfBits:   db "IF's top three bits read as one",0
ExIfBits:   db "the three unimplemented bits of IF must read back set",0
NmEiSeq:    db "a run of EI instructions still enables",0
ExEiSeq:    db "EI arms a latch; an EI that restarts a countdown already running means the enable is never reached at all",0
NmEiDelay:  db "EI is delayed and DI cancels it",0
ExEiDelay:  db "an interrupt was taken between EI and the instruction after it",0
NmEiTakes:  db "EI then NOP does take the interrupt",0
ExEiTakes:  db "interrupts never became enabled at all",0
NmPriority: db "the lowest vector wins",0
ExPriority: db "with several interrupts pending the lowest-numbered vector must be serviced first",0
NmHaltBug:  db "HALT with IME clear and a pending interrupt",0
ExHaltBug:  db "the byte after HALT must be executed twice; this is a documented CPU defect, not an option",0
NmHaltWake: db "HALT wakes without servicing when IME is clear",0
ExHaltWake: db "HALT must resume on a pending interrupt even with IME clear, and must not jump to a vector",0
NmIeBits:   db "IE stores all eight bits, IF does not",0
ExIeBits:   db "the enable register is real storage throughout; the flag register's top three bits are not implemented",0
NmReti:     db "RETI restores the master enable",0
ExReti:     db "returning from a handler with RETI re-enables interrupts with none of EI's delay",0
NmIfCancel: db "clearing IF cancels a pending interrupt",0
ExIfCancel: db "IF is a register a program can write, and clearing a bit before the interrupt is taken takes the request back",0
NmIeCancel: db "clearing IE prevents dispatch and keeps the flag",0
ExIeCancel: db "IE is consulted at the moment of dispatch, and only dispatch clears a flag",0
NmDispatch: db "dispatch costs five machine cycles",0
ExDispatch: db "taking an interrupt is two idle cycles, two pushes and a vector fetch",0

; ---------------------------------------------------------------------------
NmMem:  db "MEM: the memory map",0
PfxMem: db "MEM",0
DocMem: db "gbselftest.md",0

ListMem:
    check ChkEchoRam,  1, NmEchoRam,  ExEchoRam
    check ChkHram,     2, NmHram,     ExHram
    check ChkRomWrite, 3, NmRomWrite, ExRomWrite
    check ChkVramSize, 4, NmVramSize, ExVramSize
    check ChkOamSize,  5, NmOamSize,  ExOamSize
    check ChkProhibited, 6, NmProhibited, ExProhibited
    dw 0

NmProhibited: db "$FEA0-$FEFF answers, per console",0
ExProhibited: db "the bytes above object memory are not open bus once the screen is off",0
NmEchoRam:  db "work RAM appears again at $E000",0
ExEchoRam:  db "the echo is the same memory seen through a second door, and games read through it",0
NmHram:     db "high RAM is its own 127 bytes",0
ExHram:     db "the bytes at $FF80 are on the processor die, not a window onto work RAM",0
NmRomWrite: db "writes to the ROM area do not stick",0
ExRomWrite: db "$0000 to $7FFF is where the mapper's registers are decoded; a write there is a command",0
NmVramSize: db "video RAM is eight kilobytes",0
ExVramSize: db "the whole of $8000 to $9FFF must hold what is written with the LCD off",0
NmOamSize:  db "object memory is 160 bytes and stops",0
ExOamSize:  db "the block above $FE9F is not more object memory",0

; ---------------------------------------------------------------------------
NmPpu:  db "PPU: timing and the rendering fingerprint",0
PfxPpu: db "PPU",0
DocPpu: db "gbselftest.md",0

ListPpu:
    check ChkFrameLen,  1, NmFrameLen,  ExFrameLen
    check ChkLineLen,   2, NmLineLen,   ExLineLen
    check ChkLyRange,   3, NmLyRange,   ExLyRange
    check ChkModeSeq,   4, NmModeSeq,   ExModeSeq
    check ChkLyc,       5, NmLyc,       ExLyc
    check ChkMode3Base, 6, NmMode3Base, ExMode3Base
    check ChkMode3Scx,  7, NmMode3Scx,  ExMode3Scx
    check ChkMode3Obj,  8, NmMode3Obj,  ExMode3Obj
    check ChkMode3Win,  9, NmMode3Win,  ExMode3Win
    check ChkVramBlock,10, NmVramBlock, ExVramBlock
    check ChkOamBlock, 11, NmOamBlock,  ExOamBlock
    check ChkObjLimit, 12, NmObjLimit,  ExObjLimit
    check ChkObjDisabled,13,NmObjDis,   ExObjDis
    check ChkLcdOff,   14, NmLcdOff,    ExLcdOff
    check ChkStatBlocking,15,NmStatBlk, ExStatBlk
    check ChkStatWriteBug,16,NmStatBug, ExStatBug
    check ChkWindowOffScreen,17,NmWinOff,ExWinOff
    check ChkObjOffLeft,18, NmObjLeft,  ExObjLeft
    check ChkMode3Scy, 19, NmScyFree,   ExScyFree
    check ChkVramWriteBlock,20,NmVramWr, ExVramWr
    check ChkOamWriteBlock, 21,NmOamWr,  ExOamWr
    check ChkOamBug,        22,NmOamBug, ExOamBug
    check ChkTileAddressing,23,NmTileAddr,ExTileAddr
    dw 0

NmFrameLen:  db "a frame is 70224 cycles, measured against DIV",0
ExFrameLen:  db "the PPU and the divider disagree about how long a frame is",0
NmLineLen:   db "a scanline is 456 cycles",0
ExLineLen:   db "LY is not advancing at one line per 456 cycles",0
NmLyRange:   db "LY counts 0 to 153 and wraps",0
ExLyRange:   db "the frame is not 154 lines long",0
NmModeSeq:   db "STAT reports mode 2, then 3, then 0",0
ExModeSeq:   db "the mode sequence on a visible line is wrong, or VBlank does not report mode 1",0
NmLyc:       db "the LY equals LYC flag and its interrupt",0
ExLyc:       db "the coincidence flag is not latching, or its interrupt does not fire",0
NmMode3Base: db "mode 3 is 172 cycles with nothing to draw",0
ExMode3Base: db "the shortest possible mode 3 is not the documented length",0
NmMode3Scx:  db "fine scrolling lengthens mode 3",0
ExMode3Scx:  db "SCX modulo 8 must delay the first pixel by that many cycles",0
NmMode3Obj:  db "objects on a line lengthen mode 3",0
ExMode3Obj:  db "each object costs the fetcher at least six cycles; a fixed-length mode 3 cannot show that",0
NmMode3Win:  db "the window lengthens mode 3",0
ExMode3Win:  db "starting the window costs at least six cycles",0
NmObjLimit: db "only ten objects are drawn per line",0
ExObjLimit: db "the scan keeps the first ten that cover the line, so beyond ten the cost stops rising",0
NmObjDis:   db "objects switched off in LCDC cost nothing",0
ExObjDis:   db "the enable bit is read by the scan, not only by whatever draws the pixels",0
NmLcdOff:   db "the LCD off means LY 0 and mode 0",0
ExLcdOff:   db "switching the screen off stops the timing chain and resets the line counter",0
NmStatBlk:  db "the STAT interrupt is one line, not four",0
ExStatBlk:  db "the selected conditions are ORed together and only the rising edge of the result raises anything",0
NmStatBug:  db "writing STAT raises a spurious interrupt",0
ExStatBug:  db "on the original silicon the write acts for one cycle as though every condition were selected, and games depend on it",0
NmWinOff:   db "a window past the right edge costs nothing",0
ExWinOff:   db "the cost is the takeover, not the enable bit",0
NmObjLeft:  db "an object off the left edge still costs",0
ExObjLeft:  db "the scan finds it and its row is fetched; only the drawing is thrown away",0
NmScyFree:  db "vertical scrolling costs the fetcher nothing",0
ExScyFree:  db "only SCX discards fetched pixels; SCY just picks which row of the tile is read",0
NmOamBug:    db "object memory corrupts, or does not, per console",0
ExOamBug:    db "the increment unit drives the address bus with no access behind it, and the original silicon lets that reach the object scan",0
NmTileAddr:  db "tile id $19 is unsigned-addressed to $8190",0
ExTileAddr:  db "unsigned tile addressing is $8000 + 16*id; a wrong base or stride is invisible until a tile is identified by number, which every OAM entry and every unsigned BG tilemap byte does",0
NmVramWr:    db "a VRAM write during mode 3 is dropped",0
ExVramWr:    db "the fetcher owns that bus while it draws, so the write never reaches the memory and the picture never shows it",0
NmOamWr:     db "an OAM write during the scan is dropped",0
ExOamWr:     db "the PPU owns object memory through modes 2 and 3, which is why every game moves its objects in the blank",0
NmVramBlock: db "VRAM is unreadable during mode 3",0
ExVramBlock: db "the CPU must read $FF from VRAM while the fetcher owns it",0
NmOamBlock:  db "OAM is unreadable during modes 2 and 3",0
ExOamBlock:  db "the CPU must read $FF from OAM while the PPU is scanning or drawing",0

; ---------------------------------------------------------------------------
NmDma:  db "DMA: the object transfer",0
PfxDma: db "DMA",0
DocDma: db "gbselftest.md",0

ListDma:
    check ChkDmaCopy,  1, NmDmaCopy,  ExDmaCopy
    check ChkDmaTime,  2, NmDmaTime,  ExDmaTime
    check ChkDmaReg,   3, NmDmaReg,   ExDmaReg
    check ChkDmaBus,   4, NmDmaBus,   ExDmaBus
    check ChkDmaA12,   5, NmDmaA12,   ExDmaA12
    check ChkDmaScan,  6, NmDmaScan,  ExDmaScan
    check ChkDmaWram,  7, NmDmaWram,  ExDmaWram
    dw 0

NmDmaScan: db "a transfer stops the scan reading objects",0
ExDmaScan: db "the controller drives the object address lines, so the scan reads none",0
NmDmaA12:  db "an OAM DMA transfer overrides address bit 12 of a work-RAM access",0
ExDmaA12:  db "on a Color console, $C000 and $D000 can trade places while the transfer's source has that bit set",0
NmDmaWram: db "a write into the transfer's own source page does not land",0
ExDmaWram: db "a work-RAM-sourced transfer's own bus answers with its own byte, not the processor's, on any console",0
NmDmaBus:  db "the transfer shares the cartridge bus",0
ExDmaBus:  db "the transfer has no bus of its own, so a read on the bus it uses sees its byte",0
NmDmaCopy: db "the transfer copies 160 bytes",0
ExDmaCopy: db "the object attribute memory does not hold what was sent to it",0
NmDmaTime: db "the transfer is not instantaneous",0
ExDmaTime: db "160 machine cycles cannot have elapsed one instruction after the transfer began",0
NmDmaReg:  db "$FF46 reads back the page written",0
ExDmaReg:  db "the transfer register must read back the last value written to it",0

; ---------------------------------------------------------------------------
NmApu:  db "APU: registers and the length counter",0
PfxApu: db "APU",0
DocApu: db "gbselftest.md",0

ListApu:
    check ChkApuMasks,  1, NmApuMasks,  ExApuMasks
    check ChkApuPower,  2, NmApuPower,  ExApuPower
    check ChkApuStatus, 3, NmApuStatus, ExApuStatus
    check ChkApuWave,   4, NmApuWave,   ExApuWave
    check ChkApuDac,    5, NmApuDac,    ExApuDac
    check ChkApuPowerOff,6,NmApuOff,    ExApuOff
    check ChkApuWaveRetained,7,NmApuKeep,ExApuKeep
    dw 0

NmApuMasks:  db "every register reads back its documented bits",0
ExApuMasks:  db "a sound register is not ORing in the bits that are write-only or unused",0
NmApuPower:  db "powering off clears the registers and locks them",0
ExApuPower:  db "clearing bit 7 of NR52 must zero NR10 to NR51 and ignore writes until the power comes back",0
NmApuStatus: db "NR52 reports which channels are on",0
ExApuStatus: db "a triggered channel must show in NR52, and a channel whose length runs out must stop showing",0
NmApuDac:    db "a channel with its converter off stays off",0
ExApuDac:    db "the top five bits of NRx2 drive the converter, and a channel without one cannot be triggered on",0
NmApuOff:    db "powering off switches every channel off",0
ExApuOff:    db "clearing bit 7 of NR52 stops everything, and the status bits go with it",0
NmApuKeep:   db "wave memory survives a power cycle",0
ExApuKeep:   db "the registers are cleared by a power cycle; the sixteen bytes of wave memory are not",0
NmApuWave:   db "wave RAM is readable while the channel is off",0
ExApuWave:   db "the sixteen bytes at $FF30 are ordinary memory when channel 3 is not playing",0

; ---------------------------------------------------------------------------
NmMbc:  db "MBC: banking and cartridge RAM",0
PfxMbc: db "MBC",0
DocMbc: db "gbselftest.md",0

ListMbc:
    check ChkMbcBanks, 1, NmMbcBanks, ExMbcBanks
    check ChkMbcZero,  2, NmMbcZero,  ExMbcZero
    check ChkMbcRam,   3, NmMbcRam,   ExMbcRam
    check ChkMbcMask,  4, NmMbcMask,  ExMbcMask
    check ChkMbcRamEnableNibble,5,NmMbcNib,ExMbcNib
    dw 0

NmMbcBanks: db "each ROM bank reads back its own number",0
ExMbcBanks: db "the bank selected at $2000 is not the bank appearing at $4000",0
NmMbcZero:  db "bank 0 is translated to bank 1",0
ExMbcZero:  db "writing a bank number of zero to an MBC1 selects bank 1; the mapper cannot map bank 0 twice",0
NmMbcMask:  db "a bank number past the end wraps",0
ExMbcMask:  db "only as many of the register's five bits are connected as the cartridge has banks",0
NmMbcNib:   db "the RAM enable decodes four bits only",0
ExMbcNib:   db "any value whose low nibble is $A enables cartridge RAM; anything else locks it",0
NmMbcRam:   db "cartridge RAM only answers when enabled",0
ExMbcRam:   db "a write to cartridge RAM must be discarded unless $0A was written to $0000",0

; ---------------------------------------------------------------------------
NmBoot: db "BOOT: the state handed over at $0100",0
PfxBoot: db "BOOT",0
DocBoot: db "gbselftest.md",0

ListBoot:
    check ChkBootSp,   1, NmBootSp,   ExBootSp
    check ChkBootA,    2, NmBootA,    ExBootA
    check ChkBootRegs, 3, NmBootRegs, ExBootRegs
    check ChkBootIo,   4, NmBootIo,   ExBootIo
    check ChkBootIf,   5, NmBootIf,   ExBootIf
    check ChkBootDiv,  6, NmBootDiv,  ExBootDiv
    check ChkBootLogoTiles,7,NmBootLogo,ExBootLogo
    dw 0

NmBootSp:   db "the stack pointer starts at $FFFE",0
ExBootSp:   db "every console's boot ROM leaves SP at the top of high RAM",0
NmBootA:    db "A identifies the console",0
ExBootA:    db "A must be one of $01, $FF or $11 at handover; software has always used it to tell the machines apart",0
NmBootRegs: db "the whole register set matches this console",0
ExBootRegs: db "the boot ROM leaves a documented value in every register, and games read them",0
NmBootDiv:  db "the divider is not zero at hand-over",0
ExBootDiv:  db "the counter behind $FF04 has been running since power-on, and games seed their randomness from what it holds",0
NmBootIf:   db "the boot ROM leaves its vertical blank pending",0
ExBootIf:   db "IF reads $E1 at hand-over: the boot ROM waits for the screen before letting go",0
NmBootIo:   db "unimplemented I/O reads back as ones",0
ExBootIo:   db "an address with no register behind it must read $FF, not $00",0
NmBootLogo: db "the cartridge's own header logo decompresses into $8010-$818F",0
ExBootLogo: db "the monochrome boot ROMs unpack the header's Nintendo-logo bitmap into 24 tiles by a documented algorithm; this recomputes it from the cartridge's own header and checks it against what was actually left in VRAM",0

; ---------------------------------------------------------------------------
NmSer:  db "SER: the link port",0
PfxSer: db "SER",0
DocSer: db "gbselftest.md",0

ListSer:
    check ChkSerSb,     1, NmSerSb,     ExSerSb
    check ChkSerUnused, 2, NmSerUnused, ExSerUnused
    check ChkSerXfer,   3, NmSerXfer,   ExSerXfer
    check ChkSerExternal,4,NmSerExt,   ExSerExt
    dw 0

NmSerSb:     db "SB is a plain read/write register",0
ExSerSb:     db "$FF01 holds whatever is written to it while no transfer is running",0
NmSerUnused: db "SC's unused bits read as ones",0
ExSerUnused: db "only bits 7, 1 and 0 exist in SC, and only bit 1 on a Color console",0
NmSerExt:    db "an externally clocked transfer does not",0
ExSerExt:    db "with bit 0 of SC clear the other console drives the clock, and with nothing attached the transfer never ends",0
NmSerXfer:   db "an internally clocked transfer completes",0
ExSerXfer:   db "the console drives the clock itself, so a transfer finishes and raises its interrupt whether or not anything is plugged in",0

; ---------------------------------------------------------------------------
; The coverage statement. Printed at the end of every run, because a suite that
; does not say what it left out is claiming more than it measured.
; ---------------------------------------------------------------------------
SECTION "Coverage", ROMX, BANK[1]

CoverageText::
    db "This cartridge tests the machine from the inside. That bounds what it",13,10
    db "can see, and the bounds are these:",13,10
    db 13,10
    db "NOT TESTED, and not testable from a cartridge:",13,10
    db "  * the composited picture. There is no framebuffer to read: the PPU",13,10
    db "    streams pixels to the panel and keeps none of them. Pixel accuracy",13,10
    db "    needs a host holding a reference image -- use the Mealybug Tearoom",13,10
    db "    tests for that. What IS tested here is the rendering FINGERPRINT:",13,10
    db "    mode 3 gets longer when the fetcher has more work to do, and that",13,10
    db "    is measurable from inside to a resolution of four dots.",13,10
    db "  * anything finer than four dots. The CPU can only observe on machine",13,10
    db "    cycle boundaries, so a one, two or three dot difference -- an SCX of",13,10
    db "    1, 2 or 3 for instance -- is below the floor for any cartridge.",13,10
    db "  * the four-dot window at the top of the last scanline, where LY",13,10
    db "    reads 153 before reading 0. It is below the resolution above, so",13,10
    db "    GB-PPU-03 accepts either reading and says so.",13,10
    db "  * sound as sound. Register behaviour and the length counter are",13,10
    db "    checked; what comes out of the speaker is not.",13,10
    db "  * the boot ROM itself, which has already finished.",13,10
    db "  * other consoles. Every run reports which machine it thinks it is on",13,10
    db "    and skips what does not apply, rather than guessing.",13,10
    db "  * which VRAM source a double-speed PPU write commits to. GB-CYC-09",13,10
    db "    and GB-PPU-07 check that double speed switches at all and that the",13,10
    db "    PPU's dot clock does not speed up with the CPU, but a commit-timing",13,10
    db "    bug that only changes which tile a dot samples is a pixel, and no",13,10
    db "    cartridge can read one. See docs/double-speed.md.",13,10
    db 13,10
    db "DELIBERATELY THIN, because other people cover it far better:",13,10
    db "  * exhaustive instruction sweeps -- Blargg's cpu_instrs.",13,10
    db "  * cycle-exact PPU and timer edges -- the Mooneye test suite.",13,10
    db "  * the sound chip in detail -- SameSuite and Blargg's dmg_sound.",13,10
    db "  * mappers in detail -- the MBC test suites.",13,10
    db "This is a first-response cartridge: broad, fast, self-explaining, and",13,10
    db "one file. It is not a replacement for any of the above.",13,10
    db 0
