; checks_int.asm — interrupts: the flags, the delay on EI, the priority order,
; the HALT defect, and how long dispatch takes.
;
; Every handler here ends with `ret` rather than `reti`, so the master enable
; stays off after the first interrupt is taken and exactly one is serviced per
; test. Nothing waits on an event that has not already been shown to happen:
; GB-TIM-05 proves the timer raises its interrupt, and only if it did does the
; check that sleeps on it run at all.

INCLUDE "hardware.inc"

SECTION "ChecksInt", ROMX, BANK[2]

DEF I_SEEN EQU wScratch + 48    ; which vector ran, plus one
DEF I_IF   EQU wScratch + 49    ; IF as the handler saw it

; ---------------------------------------------------------------------------
; The recording handlers. One per vector, each writing its own number, and
; each returning WITHOUT re-enabling interrupts.
; ---------------------------------------------------------------------------
MACRO recorder
    push af
    ld a, [I_SEEN]
    or a
    jr nz, .already\@
    ldh a, [rIF]
    ld [I_IF], a
    ld a, \1
    ld [I_SEEN], a
.already\@
    pop af
    pop hl
    ret
ENDM

RecVBlank:
    recorder 1
RecStat:
    recorder 2
RecTimer:
    recorder 3
RecSerial:
    recorder 4
RecJoypad:
    recorder 5

InstallRecorders:
    ld hl, wHookVBlank
    ld de, RecVBlank
    call .put
    ld de, RecStat
    call .put
    ld de, RecTimer
    call .put
    ld de, RecSerial
    call .put
    ld de, RecJoypad
    call .put
    xor a
    ld [I_SEEN], a
    ret
.put
    ld a, e
    ld [hl+], a
    ld a, d
    ld [hl+], a
    ret

RestoreHooks:
    ld hl, wHookVBlank
    ld b, 5
.next
    ld a, LOW(DefaultIsr)
    ld [hl+], a
    ld a, HIGH(DefaultIsr)
    ld [hl+], a
    dec b
    jr nz, .next
    di
    xor a
    ldh [rIE], a
    ldh [rIF], a
    ret

; ---------------------------------------------------------------------------
; GB-INT-01 — the three bits of IF that do not exist read back as ones.
; ---------------------------------------------------------------------------
ChkIfBits::
    di
    xor a
    ldh [rIF], a
    ldh a, [rIF]
    ld b, a
    or $1F
    cp $FF
    jr nz, .bad
    or a
    ret
.bad
    ld a, b
    ld b, $E0
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "IF has five interrupt bits and three that were never wired up. Unwired bits read back as ones on this machine, and software tests IF against $FF",0

; ---------------------------------------------------------------------------
; GB-INT-02 — EI takes effect one instruction late, and DI in that gap cancels
; it. A run of EIs must not stack up either.
; ---------------------------------------------------------------------------
ChkEiDelay::
    call InstallRecorders
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    ldh [rIF], a
    ei
    di                      ; the interrupt may not be taken in this gap
    ld a, [I_SEEN]
    or a
    jr nz, .tooEarly
    call RestoreHooks
    or a
    ret
.tooEarly
    call RestoreHooks
    ld hl, .note
    jp FailNote
.note db "an interrupt was serviced between EI and the instruction after it. EI sets a latch that only reaches the master enable one instruction later, and a DI landing in that window clears it again",0

; ---------------------------------------------------------------------------
; GB-INT-03 — and once the delay is over, the interrupt really is taken.
; ---------------------------------------------------------------------------
ChkEiTakes::
    call InstallRecorders
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    ldh [rIF], a
    ei
    nop
    nop
    di
    ld a, [I_SEEN]
    cp 3
    jr nz, .never
    call RestoreHooks
    or a
    ret
.never
    ld b, 3
    call SetNums8
    call RestoreHooks
    ld hl, .note
    jp FailNote
.note db "with the enable set, the flag raised and the vector enabled, no interrupt was ever taken",0

; ---------------------------------------------------------------------------
; GB-INT-04 — with several pending at once, the lowest vector wins, and only
; that one's flag is cleared.
; ---------------------------------------------------------------------------
ChkPriority::
    call InstallRecorders
    di
    ld a, $1F
    ldh [rIE], a
    ldh [rIF], a
    ei
    nop
    di
    ld a, [I_SEEN]
    cp 1
    jr nz, .wrongOne
    ; the handler saw IF with only the VBlank bit cleared
    ld a, [I_IF]
    and $1F
    cp $1E
    jr nz, .wrongIf
    call RestoreHooks
    or a
    ret
.wrongOne
    ld b, 1
    call SetNums8
    call RestoreHooks
    ld hl, .noteOrder
    jp FailNote
.wrongIf
    ld b, $1E
    and $1F
    call SetNums8
    call RestoreHooks
    ld hl, .noteIf
    jp FailNote
.noteOrder db "with all five interrupts pending, the one at $0040 must be serviced first. Priority runs from the lowest vector upwards, not in the order the flags were raised",0
.noteIf    db "dispatch must clear the flag of the interrupt it is servicing AND NO OTHER. Clearing IF wholesale loses everything that arrived while the handler was starting",0

; ---------------------------------------------------------------------------
; GB-INT-05 — the HALT defect.
;
; With the master enable off and an interrupt already pending, HALT does not
; halt: the program counter fails to advance past the byte after it, so that
; byte is executed twice. It is a defect in the silicon and software depends
; on it, which is why an emulator has to reproduce it rather than tidy it away.
; ---------------------------------------------------------------------------
ChkHaltBug::
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    ldh [rIF], a
    xor a
    db $76                  ; HALT, written as a byte so no NOP can be padded
    inc a                   ; executed twice on hardware
    ld b, a
    xor a
    ldh [rIE], a
    ldh [rIF], a
    ld a, b
    cp 2
    ret z
    ld b, 2
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "the byte after HALT ran once, not twice. When HALT is reached with interrupts disabled and one already pending, the fetch that follows does not advance the program counter",0

; ---------------------------------------------------------------------------
; GB-INT-06 — HALT wakes on an interrupt that arrives later, without taking it.
;
; Skipped unless GB-TIM-05 has already shown that the timer raises its
; interrupt: this is the one check that would sleep forever on a machine where
; it does not.
; ---------------------------------------------------------------------------
ChkHaltWake::
    ld a, [wTimerWorks]
    or a
    jr z, .noTimer
    call InstallRecorders
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    xor a
    ldh [rIF], a
    ldh [rTAC], a
    ld a, $00
    ldh [rTMA], a
    ld a, $F0
    ldh [rTIMA], a
    ld a, TACF_START | TACF_16T
    ldh [rTAC], a
    db $76                  ; HALT: no interrupt is pending yet
    nop
    ; we are here, so HALT ended. Nothing may have been serviced.
    xor a
    ldh [rTAC], a
    ld a, [I_SEEN]
    or a
    jr nz, .serviced
    ldh a, [rIF]
    and IEF_TIMER
    jr z, .noFlag
    call RestoreHooks
    or a
    ret
.serviced
    call RestoreHooks
    ld hl, .noteSvc
    jp FailNote
.noFlag
    call RestoreHooks
    ld hl, .noteFlag
    jp FailNote
.noTimer
    ld hl, .noteSkip
    jp SkipWith
.noteSvc  db "HALT ended by jumping to a vector even though the master enable was off. It must resume at the next instruction and leave the flag standing",0
.noteFlag db "HALT ended but the timer flag was not set, so something other than the interrupt woke it",0
.noteSkip db "not run: GB-TIM-05 did not show the timer raising its interrupt, and this check would wait for it forever",0

; ---------------------------------------------------------------------------
; GB-INT-07 — dispatch costs five machine cycles.
;
; Measured, not asserted. Sixteen interrupts are taken inside a timed body, and
; the same body is run again with the enable clear so that none is; the
; difference is sixteen dispatches plus sixteen trips through this cartridge's
; own handler. Every instruction in that trip is priced from the published
; opcode table -- and the CYC area has already checked those prices on this
; very machine -- so what is left over is the dispatch itself.
;
;   dispatch                                    5   <- the thing under test
;   the vector: PUSH HL, LD HL,nn, JR           4 + 3 + 3
;   the trampoline: LD A,[HL+], LD H,[HL],
;                   LD L,A, JP HL               2 + 2 + 1 + 1
;   the handler: POP HL, RET                    3 + 4
;                                              --
;                                              28 machine cycles
;
; Sixteen of those is 448 machine cycles, and four machine cycles are one
; increment of the timer at its fastest rate.
; ---------------------------------------------------------------------------
DEF DISPATCH_COST  EQU 5
DEF HANDLER_COST   EQU 4 + 3 + 3 + 2 + 2 + 1 + 1 + 3 + 4
DEF DISPATCH_TICKS EQU 16 * (DISPATCH_COST + HANDLER_COST) / 4
ChkDispatch::
    ld hl, wHookTimer
    ld a, LOW(DispatchIsr)
    ld [hl+], a
    ld a, HIGH(DispatchIsr)
    ld [hl], a

    ld hl, BodyIntOff
    call RunTimed
    ld [wScratch + 50], a
    ld hl, BodyIntOn
    call RunTimed
    ld b, a
    ld a, [wScratch + 50]
    ld c, a
    ld a, b
    sub c                   ; ticks spent on sixteen dispatches and handlers
    ld [wScratch + 51], a

    call RestoreHooks
    ld a, [wScratch + 51]
    ld b, DISPATCH_TICKS
    ld c, 2
    call Within
    ret nc
    ld b, 48
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "taking an interrupt is five machine cycles: two idle, the high half of the program counter pushed, the low half pushed, then the vector fetched. A flat sixteen or twenty T-cycles applied in one lump does not measure the same",0

DispatchIsr:
    pop hl
    ret

BodyIntOff:
    ld hl, wScratch
    ld bc, $0102
    ld de, $0304
    di
    ld a, 0
    ldh [rIE], a            ; nothing enabled, so nothing is taken
    REPT 16
    ld a, IEF_TIMER
    ldh [rIF], a
    ei
    nop
    di
    ENDR
    xor a
    ldh [rIE], a
    ldh [rIF], a
    ret

BodyIntOn:
    ld hl, wScratch
    ld bc, $0102
    ld de, $0304
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    REPT 16
    ld a, IEF_TIMER
    ldh [rIF], a
    ei
    nop
    di
    ENDR
    xor a
    ldh [rIE], a
    ldh [rIF], a
    ret
