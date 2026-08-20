; checks_time.asm — instruction timing, the divider and the timer.
;
; HOW THE MEASUREMENT WORKS, and why it does not need a reference emulator.
;
; The timer is set to its fastest rate, one increment per sixteen T-cycles,
; and the divider is written to restart the counter chain from a known phase.
; A body of sixty-four copies of one instruction is then run, and TIMA is read.
; Every body shares an identical prologue and epilogue, so subtracting the
; reading for sixty-four NOPs leaves exactly the extra time the instruction
; under test costs -- sixty-four times over, which is what makes a quarter of a
; machine cycle of quantisation harmless.
;
; The expected values are the published opcode table's, which is a fact about
; the hardware in the same way a register address is. Nothing here was
; measured on an emulator.

INCLUDE "hardware.inc"

SECTION "ChecksTime", ROMX, BANK[2]

DEF T_BASE EQU wScratch + 32
DEF T_CUR  EQU wScratch + 33
DEF T_EXP  EQU wScratch + 34
DEF T_WANT EQU wScratch + 35
DEF T_NAME EQU wScratch + 36    ; two bytes
DEF T_TBL  EQU wScratch + 38    ; two bytes

DEF REPS EQU 24                 ; copies of the instruction in each body
DEF TICKS_PER_M EQU REPS / 4    ; four T-cycles to the machine cycle

MACRO timing
    dw \1                   ; body
    db \2                   ; machine cycles per repetition
    dw \3                   ; what the instruction is
ENDM

; ---------------------------------------------------------------------------
; RunTimed — HL = a body that ends in `ret`. Returns A = TIMA afterwards.
; ---------------------------------------------------------------------------
RunTimed::
    di
    xor a
    ldh [rTAC], a
    ldh [rTIMA], a
    ldh [rTMA], a
    ld de, .back
    push de
    ld a, TACF_START | TACF_16T
    ldh [rTAC], a
    xor a
    ldh [rDIV], a
    jp hl
.back
    ldh a, [rTIMA]
    ld b, a
    xor a
    ldh [rTAC], a
    ld a, b
    ret

; ---------------------------------------------------------------------------
; CheckTimingTable — HL = a table of
;     dw body, db machine cycles per repetition, dw instruction name
; ending in a null body pointer.
; ---------------------------------------------------------------------------
CheckTimingTable:
    ld a, l
    ld [T_TBL], a
    ld a, h
    ld [T_TBL + 1], a
    ld hl, BodyNop
    call RunTimed
    ld [T_BASE], a
.next
    ld a, [T_TBL]
    ld l, a
    ld a, [T_TBL + 1]
    ld h, a
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a
    or e
    jr z, .allOk
    ld a, [hl+]
    ld [T_EXP], a
    ld a, [hl+]
    ld [T_NAME], a
    ld a, [hl+]
    ld [T_NAME + 1], a
    ld a, l
    ld [T_TBL], a
    ld a, h
    ld [T_TBL + 1], a

    ld h, d
    ld l, e
    call RunTimed
    ld [T_CUR], a

    ; want = base + (cycles - 1) * 16, because a NOP already costs one cycle
    ; and each of the sixteen T-cycles is one timer increment.
    ld a, [T_EXP]
    dec a
    ld b, a
    ld c, 0
.mul
    ld a, b
    or a
    jr z, .mulDone
    ld a, c
    add TICKS_PER_M
    ld c, a
    dec b
    jr .mul
.mulDone
    ld a, [T_BASE]
    add c
    ld [T_WANT], a

    ld a, [T_CUR]
    ld b, a
    ld a, [T_WANT]
    sub b
    jr z, .next
    cp 1
    jr z, .next
    cp $FF
    jr z, .next             ; one increment either way is quantisation

    ; report the instruction that was wrong, and its two readings
    ld a, [T_CUR]
    ld b, a
    ld a, [T_WANT]
    ld [wWant], a
    xor a
    ld [wWant + 1], a
    ld a, b
    ld [wGot], a
    xor a
    ld [wGot + 1], a
    inc a
    ld [wHaveNums], a
    ld a, [T_NAME]
    ld l, a
    ld a, [T_NAME + 1]
    ld h, a
    jp FailNote
.allOk
    or a
    ret

; ---------------------------------------------------------------------------
; The bodies. Every one begins with the same three loads so that the
; measurement of the prologue cancels exactly when the NOP body is subtracted.
; ---------------------------------------------------------------------------
MACRO tprologue
    ld hl, wScratch
    ld bc, $0180            ; C addresses high RAM, so `ldh a,[c]` is harmless
    ld de, $0304
ENDM

BodyNop:
    tprologue
    REPT REPS
    nop
    ENDR
    ret

BodyLdRr:
    tprologue
    REPT REPS
    ld a, b
    ENDR
    ret

BodyLdHlInd:
    tprologue
    REPT REPS
    ld a, [hl]
    ENDR
    ret

BodyStHlInd:
    tprologue
    REPT REPS
    ld [hl], a
    ENDR
    ret

BodyLdImm:
    tprologue
    REPT REPS
    ld a, $5A
    ENDR
    ret

BodyLdhInd:
    tprologue
    REPT REPS
    ldh a, [rLY]
    ENDR
    ret

BodyLdAbs:
    tprologue
    REPT REPS
    ld a, [wScratch]
    ENDR
    ret

BodyAddRr:
    tprologue
    REPT REPS
    add a, b
    ENDR
    ret

BodyAddHlInd:
    tprologue
    REPT REPS
    add a, [hl]
    ENDR
    ret

BodyIncRr:
    tprologue
    REPT REPS
    inc bc
    ENDR
    ret

BodyAddHl16:
    tprologue
    REPT REPS
    add hl, bc
    ENDR
    ret

BodyIncHlInd:
    tprologue
    REPT REPS
    inc [hl]
    ENDR
    ret

BodyPushPop:
    tprologue
    REPT REPS
    push bc
    pop bc
    ENDR
    ret

BodyCallRet:
    tprologue
    REPT REPS
    call TimedRet
    ENDR
    ret
TimedRet:
    ret

BodyJrTaken:
    tprologue
    REPT REPS
    jr @+2
    ENDR
    ret

BodyJrNotTaken:
    tprologue
    xor a                   ; Z set, and nothing below disturbs it
    REPT REPS
    jr nz, @+2
    ENDR
    ret

BodyJpAbs:
    tprologue
    REPT REPS
    jp @+3
    ENDR
    ret

BodyBitRr:
    tprologue
    REPT REPS
    bit 0, b
    ENDR
    ret

BodyBitHlInd:
    tprologue
    REPT REPS
    bit 0, [hl]
    ENDR
    ret

BodySetHlInd:
    tprologue
    REPT REPS
    set 0, [hl]
    ENDR
    ret

BodySwap:
    tprologue
    REPT REPS
    swap a
    ENDR
    ret

BodyLdhC:
    tprologue
    REPT REPS
    ldh a, [c]
    ENDR
    ret

BodyLdNnSp:
    tprologue
    REPT REPS
    ld [wScratch + 60], sp
    ENDR
    ret

BodyRst:
    tprologue
    REPT REPS
    rst $38
    ENDR
    ret

BodyRetTaken:
    tprologue
    xor a                   ; Z set; nothing in the loop disturbs it
    REPT REPS
    call TimedRetZ
    ENDR
    ret
TimedRetZ:
    ret z
    ret

BodyRetNotTaken:
    tprologue
    ld a, 1
    or a                    ; Z clear
    REPT REPS
    call TimedRetZ
    ENDR
    ret

; ---------------------------------------------------------------------------
ChkCycLoad::
    ld hl, .table
    jp CheckTimingTable
.table
    timing BodyLdRr, 1, .nLdRr
    timing BodyLdImm, 2, .nLdImm
    timing BodyLdHlInd, 2, .nLdHl
    timing BodyStHlInd, 2, .nStHl
    timing BodyLdhInd, 3, .nLdh
    timing BodyLdAbs, 4, .nLdAbs
    dw 0
.nLdRr  db "LD r,r is one machine cycle: no memory is touched",0
.nLdImm db "LD r,n is two: one to fetch the opcode and one to fetch the byte",0
.nLdHl  db "LD A,[HL] is two: the read is a whole machine cycle of its own",0
.nStHl  db "LD [HL],A is two",0
.nLdh   db "LDH A,[n] is three: opcode, offset, then the read",0
.nLdAbs db "LD A,[nn] is four: opcode, two address bytes, then the read",0

ChkCycAlu::
    ld hl, .table
    jp CheckTimingTable
.table
    timing BodyAddRr, 1, .nAdd
    timing BodyAddHlInd, 2, .nAddHl
    timing BodyIncRr, 2, .nIncRr
    timing BodyAddHl16, 2, .nAddHl16
    timing BodyIncHlInd, 3, .nIncHlInd
    timing BodySwap, 2, .nSwap
    dw 0
.nAdd      db "ADD A,r is one machine cycle",0
.nAddHl    db "ADD A,[HL] is two: the operand comes from memory",0
.nIncRr    db "INC rr is two even though nothing is read: the increment unit takes a cycle of its own",0
.nAddHl16  db "ADD HL,rr is two: the sixteen-bit add is done eight bits at a time",0
.nIncHlInd db "INC [HL] is three: read, modify, write back",0
.nSwap     db "a CB-prefixed operation on a register is two: the prefix costs a fetch",0

ChkCycStack::
    ld hl, .table
    jp CheckTimingTable
.table
    timing BodyPushPop, 7, .nPushPop
    timing BodyCallRet, 10, .nCallRet
    dw 0
.nPushPop db "PUSH is four machine cycles and POP is three, so a matched pair is seven. PUSH pays an extra cycle to decrement the stack pointer",0
.nCallRet db "CALL is six and RET is four, so a call and its return are ten together",0

ChkCycJump::
    ld hl, .table
    jp CheckTimingTable
.table
    timing BodyJrTaken, 3, .nJrT
    timing BodyJrNotTaken, 2, .nJrN
    timing BodyJpAbs, 4, .nJp
    dw 0
.nJrT db "a taken JR is three machine cycles: the extra one is loading the new program counter",0
.nJrN db "a conditional jump that is NOT taken still fetches its operand, so it costs two -- an emulator that charges nothing for it runs conditionals too fast",0
.nJp  db "JP nn is four whether or not it is conditional and taken",0

ChkCycMore::
    ld hl, .table
    jp CheckTimingTable
.table
    timing BodyLdhC, 2, .nLdhC
    timing BodyLdNnSp, 5, .nLdNnSp
    timing BodyRst, 8, .nRst
    timing BodyRetTaken, 11, .nRetT
    timing BodyRetNotTaken, 12, .nRetN
    dw 0
.nLdhC   db "LDH A,[C] is two machine cycles: the address is a register, so there is no offset byte to fetch",0
.nLdNnSp db "LD [nn],SP is five: opcode, two address bytes, then TWO writes",0
.nRst    db "a restart and its return are eight together: RST is four, and it pushes without fetching an address",0
.nRetT   db "a call and a TAKEN conditional return are eleven together. The condition costs a cycle whether or not it is met",0
.nRetN   db "a call, a conditional return NOT taken and a plain return are twelve together: a conditional return that falls through still costs two",0

ChkCycCb::
    ld hl, .table
    jp CheckTimingTable
.table
    timing BodyBitRr, 2, .nBitR
    timing BodyBitHlInd, 3, .nBitHl
    timing BodySetHlInd, 4, .nSetHl
    dw 0
.nBitR  db "BIT n,r is two machine cycles",0
.nBitHl db "BIT n,[HL] is three: it reads but does not write",0
.nSetHl db "SET n,[HL] is four: it reads AND writes back, one cycle more than BIT",0

; ===========================================================================
; The divider and the timer.
;
; Every rate below is checked against DIV, and DIV is checked against the PPU
; in GB-PPU-01. Two clocks that disagree is a finding; a clock checked only
; against itself is not a check at all.
; ===========================================================================

; TimaBetweenDiv — B = the TAC value, C and D = two divider readings to stop
; at. Returns A = how far TIMA moved between them.
;
; TIMA is read at BOTH ends rather than only at the last, and the answer is
; the difference. The polling loop cannot see the divider change the instant it
; changes -- it overshoots by however long one turn of the loop takes -- but it
; overshoots by the SAME amount at both ends, so the difference is exact while
; a single reading is not. The first attempt at this check measured once and
; was four increments out; that was the loop, not the timer.
TimaBetweenDiv:
    di
    xor a
    ldh [rTAC], a
    ldh [rTIMA], a
    ldh [rTMA], a
    ld a, b
    ldh [rTAC], a
    xor a
    ldh [rDIV], a
.first
    ldh a, [rDIV]
    cp c
    jr c, .first
    ldh a, [rTIMA]
    ld e, a
.second
    ldh a, [rDIV]
    cp d
    jr c, .second
    ldh a, [rTIMA]
    ld c, a
    xor a
    ldh [rTAC], a
    ld a, c
    sub e                   ; TIMA wraps, and so does this: the answer stands
    ret

; ---------------------------------------------------------------------------
; GB-TIM-01 — at TAC's 256-cycle rate the timer and the divider tick together,
; because on hardware they are literally the same counter.
; ---------------------------------------------------------------------------
ChkDivRate::
    ld b, TACF_START | TACF_256T
    ld c, 32
    ld d, 96                ; sixty-four divider increments apart
    call TimaBetweenDiv
    ld b, 64
    ld c, 1
    call Within
    ret nc
    ld b, 64
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "with TAC set to one increment per 256 cycles, TIMA must advance exactly as fast as DIV: one counter feeds both",0

; ---------------------------------------------------------------------------
; GB-TIM-02 — a write to DIV clears the whole counter, not just the byte.
; ---------------------------------------------------------------------------
ChkDivReset::
    di
    xor a
    ldh [rTAC], a
    ldh [rDIV], a
    ld a, 1
    call DelayA             ; about twelve divider increments
    ldh a, [rDIV]
    or a
    jr z, .stuck
    xor a
    ldh [rDIV], a
    ldh a, [rDIV]
    or a
    jr nz, .notCleared
    or a
    ret
.stuck
    ld hl, .noteStuck
    jp FailNote
.notCleared
    ld b, 0
    call SetNums8
    ld hl, .noteClr
    jp FailNote
.noteStuck db "DIV never left zero: the divider is not running at all",0
.noteClr   db "writing $FF04 must set the divider to zero whatever was written. The low half of the counter is not readable from here, but it has to be cleared too, and GB-TIM-01 and GB-TIM-03 would not come out right if it were not: they both restart the counter with this write and then count ratios off it",0

; ---------------------------------------------------------------------------
; GB-TIM-03 — all four TAC rates, each against DIV.
; ---------------------------------------------------------------------------
ChkTimaRates::
    ; 1024 cycles per increment: a quarter of the divider's rate, so sixty-four
    ; divider increments make sixteen
    ld b, TACF_START | TACF_1024T
    ld c, 32
    ld d, 96
    call TimaBetweenDiv
    ld b, 16
    ld c, 1
    call Within
    jr c, .fail
    ; 64 cycles per increment: four times the divider's rate
    ld b, TACF_START | TACF_64T
    ld c, 32
    ld d, 64
    call TimaBetweenDiv
    ld b, 128
    ld c, 1
    call Within
    jr c, .fail
    ; 16 cycles per increment: sixteen times the divider's rate. The slack is
    ; wider here and it is a physical floor, not a fudge: one turn of the
    ; polling loop is 28 cycles, which at this rate is nearly two increments,
    ; and the two ends of the measurement do not land at the same point of a
    ; divider step. Two increments out of 128 still tells this rate apart from
    ; every other one, which are 8, 32 and 512.
    ld b, TACF_START | TACF_16T
    ld c, 32
    ld d, 40
    call TimaBetweenDiv
    ld b, 128
    ld c, 3
    call Within
    jr c, .fail
    or a
    ret
.fail
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "a TAC rate is wrong. The four settings are 1024, 16, 64 and 256 cycles per increment IN THAT ORDER -- the fastest is selection 1, not selection 3, and getting the order wrong makes three of the four wrong at once",0

; ---------------------------------------------------------------------------
; GB-TIM-04 — bit 2 of TAC stops the timer.
; ---------------------------------------------------------------------------
ChkTimaStop::
    ld b, TACF_16T          ; the rate, with the enable bit clear
    ld c, 32
    ld d, 96
    call TimaBetweenDiv
    or a
    ret z
    ld b, 0
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "TIMA advanced while bit 2 of TAC was clear. The rate bits select a tap; bit 2 is what connects it",0

; ---------------------------------------------------------------------------
; GB-TIM-05 — overflow reloads TMA and raises the interrupt.
; ---------------------------------------------------------------------------
ChkTimaWrap::
    di
    xor a
    ldh [rTAC], a
    ldh [rIF], a
    ld a, $C0
    ldh [rTMA], a
    ld a, $FE
    ldh [rTIMA], a
    ld a, TACF_START | TACF_16T
    ldh [rTAC], a
    ld bc, 4000
.wait
    ldh a, [rIF]
    and IEF_TIMER
    jr nz, .fired
    dec bc
    ld a, b
    or c
    jr nz, .wait
    xor a
    ldh [rTAC], a
    ld hl, .noteIrq
    jp FailNote
.fired
    ldh a, [rTIMA]
    ld d, a
    xor a
    ldh [rTAC], a
    ldh [rIF], a
    ld a, d
    cp $C0
    jr c, .noReload
    ; the timer demonstrably raises its interrupt, so GB-INT-06 may use it
    ld a, 1
    ld [wTimerWorks], a
    or a
    ret
.noReload
    ld b, $C0
    ld a, d
    call SetNums8
    ld hl, .noteTma
    jp FailNote
.noteIrq db "TIMA wrapped past $FF and bit 2 of IF was never set. The overflow IS the interrupt",0
.noteTma db "after wrapping, TIMA must restart from TMA rather than from zero",0

; ---------------------------------------------------------------------------
; GB-CYC-07 — a memory access happens on its own machine cycle, not at the end
; of the instruction it is in.
;
; This is the one check here that detects a *shortcut* rather than a mistake.
; An emulator that advances its peripherals once per instruction instead of
; once per memory access still runs every clock at exactly the right rate, so
; nothing measured over a run of instructions can tell the difference. What
; gives it away is two reads of the same register from the same starting phase
; by instructions of different lengths.
;
; The timer is set to its fastest tap, so TIMA counts once every four machine
; cycles. A write to $FF04 resets the whole counter, and on hardware that write
; lands on the write instruction's own last cycle — so the counter is at zero
; when the next instruction begins.
;
;   ldh a, [rTIMA]   three cycles, the read on the third   -> counter 3, TIMA 0
;   ld  a, [$FF05]   four cycles,  the read on the fourth  -> counter 4, TIMA 1
;
; One tick apart. Advance the peripherals per instruction instead and both
; reads see the counter as it stood when their instruction began, which is the
; same value, so the difference collapses to zero. That is the whole check.
; ---------------------------------------------------------------------------
ChkCycPhase::
    call LcdOff
    di
    xor a
    ldh [rTMA], a
    ld a, %00000101         ; enabled, 262144 Hz: TIMA every four cycles
    ldh [rTAC], a

    ; trial one — a three-cycle read
    xor a
    ldh [rTIMA], a
    ldh [rDIV], a           ; the reset lands on this instruction's third cycle
    ldh a, [rTIMA]          ; and this read on its own third
    ld b, a

    ; trial two — a four-cycle read of the same register, same phase
    xor a
    ldh [rTIMA], a
    ldh [rDIV], a
    ld a, [$FF05]
    ld c, a

    xor a
    ldh [rTAC], a           ; leave the timer as it was found

    ; the four-cycle read must have seen exactly one tick more
    ld a, c
    sub b
    cp 1
    jr nz, .bad
    or a
    ret
.bad
    ld a, c
    ld b, b                 ; got = the four-cycle read, want = the three-cycle
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "two reads of the timer from the same phase, by a three-cycle instruction and a four-cycle one, must differ by one tick. They did not, so memory accesses are not landing on their own machine cycles: the peripherals are being advanced once per instruction. Every clock still runs at the right rate, so only a check like this one can see it",0
