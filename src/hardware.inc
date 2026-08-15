; hardware.inc — Game Boy I/O register addresses and bit meanings.
;
; Every value here is a documented fact about the hardware, taken from Pan Docs
; (CC0 1.0, public domain, https://gbdev.io/pandocs/) and written out in this
; project's own idiom. Deliberately not `gbdev/hardware.inc`: this cartridge
; ships with no third-party source at all, so the whole ROM can be
; redistributed under one permissive licence with nothing to audit.

IF !DEF(HARDWARE_INC)
DEF HARDWARE_INC EQU 1

INCLUDE "wram.inc"

DEF _VRAM        EQU $8000
DEF _SCRN0       EQU $9800
DEF _SCRN1       EQU $9C00
DEF _SRAM        EQU $A000
DEF _OAMRAM      EQU $FE00
DEF _HRAM        EQU $FF80

DEF rP1   EQU $FF00
DEF rSB   EQU $FF01
DEF rSC   EQU $FF02
DEF SCF_START    EQU %10000000
DEF SCF_INTERNAL EQU %00000001

DEF rDIV  EQU $FF04
DEF rTIMA EQU $FF05
DEF rTMA  EQU $FF06
DEF rTAC  EQU $FF07
DEF TACF_START  EQU %00000100
DEF TACF_1024T  EQU %00000000   ; one TIMA increment per 1024 T-cycles
DEF TACF_16T    EQU %00000001   ; one TIMA increment per   16 T-cycles
DEF TACF_64T    EQU %00000010   ; one TIMA increment per   64 T-cycles
DEF TACF_256T   EQU %00000011   ; one TIMA increment per  256 T-cycles

DEF rIF   EQU $FF0F
DEF rIE   EQU $FFFF
DEF IEF_VBLANK EQU %00000001
DEF IEF_STAT   EQU %00000010
DEF IEF_TIMER  EQU %00000100
DEF IEF_SERIAL EQU %00001000
DEF IEF_HILO   EQU %00010000

DEF rNR10 EQU $FF10
DEF rNR11 EQU $FF11
DEF rNR12 EQU $FF12
DEF rNR13 EQU $FF13
DEF rNR14 EQU $FF14
DEF rNR21 EQU $FF16
DEF rNR22 EQU $FF17
DEF rNR23 EQU $FF18
DEF rNR24 EQU $FF19
DEF rNR30 EQU $FF1A
DEF rNR31 EQU $FF1B
DEF rNR32 EQU $FF1C
DEF rNR33 EQU $FF1D
DEF rNR34 EQU $FF1E
DEF rNR41 EQU $FF20
DEF rNR42 EQU $FF21
DEF rNR43 EQU $FF22
DEF rNR44 EQU $FF23
DEF rNR50 EQU $FF24
DEF rNR51 EQU $FF25
DEF rNR52 EQU $FF26
DEF _AUD3WAVERAM EQU $FF30

DEF rLCDC EQU $FF40
DEF rSTAT EQU $FF41
DEF rSCY  EQU $FF42
DEF rSCX  EQU $FF43
DEF rLY   EQU $FF44
DEF rLYC  EQU $FF45
DEF rDMA  EQU $FF46
DEF rBGP  EQU $FF47
DEF rOBP0 EQU $FF48
DEF rOBP1 EQU $FF49
DEF rWY   EQU $FF4A
DEF rWX   EQU $FF4B
DEF rKEY1 EQU $FF4D
DEF rVBK  EQU $FF4F
DEF rSVBK EQU $FF70

DEF LCDCF_ON      EQU %10000000
DEF LCDCF_WIN9C00 EQU %01000000
DEF LCDCF_WINON   EQU %00100000
DEF LCDCF_BLK01   EQU %00010000   ; tile data at $8000, unsigned ids
DEF LCDCF_BG9C00  EQU %00001000
DEF LCDCF_OBJ16   EQU %00000100
DEF LCDCF_OBJON   EQU %00000010
DEF LCDCF_BGON    EQU %00000001

DEF STATF_LYC    EQU %01000000
DEF STATF_MODE10 EQU %00100000   ; mode 2 (OAM scan) interrupt select
DEF STATF_MODE01 EQU %00010000   ; mode 1 (VBlank)   interrupt select
DEF STATF_MODE00 EQU %00001000   ; mode 0 (HBlank)   interrupt select
DEF STATF_LYCF   EQU %00000100   ; the latched LY == LYC flag

; This cartridge is an MBC1 with four ROM banks. Bank 0 holds everything; the
; other three exist only so that the mapper has something to switch between,
; and each begins with its own number.
DEF ROM_BANKS EQU 4

; The byte values every arithmetic sweep uses, and how many there are. Not a
; random selection: these are the boundaries where a carry, a half carry, a
; sign or a zero can appear, which is where an arithmetic bug lives.
DEF TESTVALS_N EQU 9
DEF BCDVALS_N  EQU 9

; The DMG frame: 154 scanlines of 456 T-cycles = 70224 T-cycles, which at
; 4194304 Hz is 59.7275 frames per second. Used as expected values below.
DEF DOTS_PER_LINE   EQU 456
DEF LINES_PER_FRAME EQU 154

ENDC
