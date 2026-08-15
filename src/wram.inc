; wram.inc — where everything lives in work RAM.
;
; Laid out with RSSET/RB/RW rather than as a WRAM section, so that every
; source file sees the same addresses as ASSEMBLY-TIME CONSTANTS. The check
; files need that: they carve their own scratch out of `wScratch` with
; expressions like `wScratch + 12`, and a link-time label cannot be used in a
; constant expression.

IF !DEF(WRAM_INC)
DEF WRAM_INC EQU 1

RSSET $C000

; --- the state the boot ROM handed over, captured on the first instruction.
; Copied straight off the stack after `push hl / de / bc / af`. The LAST push
; sits at the LOWEST address and each pair stores its low byte first, so what
; comes back is F, A, C, B, E, D, L, H -- not the order the pushes were
; written in, which is a mistake worth making only once.
DEF wBootRegs   RB 8
DEF wBootSP     RW 1
DEF wBootIF     RB 1
DEF wConsole    RB 1

DEF BOOT_F EQU wBootRegs + 0
DEF BOOT_A EQU wBootRegs + 1
DEF BOOT_C EQU wBootRegs + 2
DEF BOOT_B EQU wBootRegs + 3
DEF BOOT_E EQU wBootRegs + 4
DEF BOOT_D EQU wBootRegs + 5
DEF BOOT_L EQU wBootRegs + 6
DEF BOOT_H EQU wBootRegs + 7

; --- one hook per interrupt vector, so a check can borrow a vector and give
; it back afterwards.
DEF wHookVBlank RW 1
DEF wHookStat   RW 1
DEF wHookTimer  RW 1
DEF wHookSerial RW 1
DEF wHookJoypad RW 1

; --- the report
DEF wTextBuf    RB 20 * 18      ; the screen as characters; tile id == ASCII
DEF wCurX       RB 1
DEF wCurY       RB 1
DEF wSinks      RB 1
DEF wSerialOK   RB 1            ; cleared if the link port stops acknowledging
DEF wSerialFast RB 1            ; SC bit 1: a Color console's faster clock
DEF wDecSeen    RB 1
DEF wSerialSent RW 1            ; bytes out of the link port, which on a DMG
                                ; is 8192 bits per second and so is most of
                                ; what a run costs in wall-clock time

; --- the run
DEF wPassed     RW 1
DEF wFailed     RW 1
DEF wSkipped    RW 1
DEF wAreaPass   RB 1
DEF wAreaFail   RB 1
DEF wAreaSkip   RB 1
DEF wFrames     RW 1
; Three bytes a failure: the area prefix's address and the check number, which
; is everything the screen needs to spell the stable code back out. It used to
; hold the check's title instead, and a title is prose -- it wrapped over two
; of the twenty columns available and told a reader nothing they could look up.
DEF wFailList   RB 3 * 10
DEF wFailCount  RB 1

; --- the descriptor of the check currently running
DEF wPrefix     RW 1
DEF wDocPage    RW 1
DEF wAreaCur    RW 1
DEF wAreaBank   RB 1
DEF wCursor     RW 1
DEF wRt         RW 1
DEF wNum        RB 1
DEF wName       RW 1
DEF wExpl       RW 1

; --- what a check leaves behind to explain itself
DEF wDetail     RW 1
DEF wGot        RW 1
DEF wWant       RW 1
DEF wHaveNums   RB 1
DEF wSkipFlag   RB 1

; --- what one check needs to know about another before it dares run
DEF wTimerWorks RB 1            ; GB-TIM-05 saw the timer raise its interrupt
DEF wStatWorks  RB 1            ; the coincidence interrupt fires at all
DEF wSledJump   RW 1            ; where in the delay sled the handler jumps

; --- scratch for the checks themselves
DEF wScratch    RB 96
DEF wModel      RB 32
DEF wWramEnd    RB 0

DEF SINK_SCREEN EQU %00000001
DEF SINK_SERIAL EQU %00000010

DEF CONSOLE_DMG EQU 0
DEF CONSOLE_MGB EQU 1
DEF CONSOLE_CGB EQU 2
DEF CONSOLE_AGB EQU 3
DEF CONSOLE_UNK EQU 4

ENDC
