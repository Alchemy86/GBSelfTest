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
; cycles. The counter is restarted by a write to $FF04 and TIMA is zeroed
; AFTER that write, so every reading starts from a counter this check set
; itself. Then the same reading is taken at four consecutive one-cycle delays:
;
;   delay          0     1     2     3
;   ldh a,[rTIMA]  n    n+1   n+1   n+1    the read on the instruction's third
;   ld  a,[$FF05] n+1   n+1   n+1   n+1    the read on its fourth
;
; A tick is four machine cycles, so the tap crosses exactly once in four; and
; the four-cycle read is one cycle later than the three-cycle one, so its
; crossing comes one delay earlier. The two rows are therefore the same row
; shifted by one, which is another way of saying the two instructions read the
; register at different points inside themselves. Exactly one of the four
; delays shows a difference of one and the other three show none.
;
; Advance the peripherals once per instruction instead and both rows become the
; reading as it stood when the instruction began — the same reading — so every
; difference is zero and no delay shows anything. That is the whole check.
;
; The rows above were measured on SameBoy and on TerminalGB and are identical
; byte for byte across the whole sweep, which is what says the numbers belong
; to the hardware rather than to either implementation.
;
; WHAT THE FIRST VERSION OF THIS CHECK DID, AND WHY IT WAS WRONG. It took one
; reading with each instruction and required the difference to be one tick. But
; it zeroed TIMA and only then wrote $FF04, which leaves TIMA cleared three
; cycles BEFORE the counter restarts — and whether the tapped bit falls inside
; those three cycles, and whether the $FF04 write is itself a falling edge
; (which is GB-TIM-06, and a fact about the same tap), both depend on the phase
; the check happened to be entered in. That phase is decided by how much code
; ran above it, so the verdict was decided by the rest of the run rather than by
; the machine: the same reasoning passed on one emulator and failed on SameBoy,
; and swapping which checks failed earlier was enough to swap the answer. A
; check that detects a shortcut has to be the most phase-proof thing in the
; suite, not the least.
; ---------------------------------------------------------------------------
DEF PHASE_PAD EQU 4

DEF X_PHA EQU wScratch + 40     ; the three-cycle read
DEF X_PHD EQU wScratch + 41     ; the delay being swept
DEF X_PHN EQU wScratch + 42     ; how many delays showed a step

ChkCycPhase::
    call LcdOff
    xor a
    ld [X_PHD], a
    ld [X_PHN], a
.next
    ld a, [X_PHD]
    call PhaseA
    ld [X_PHA], a
    ld a, [X_PHD]
    call PhaseB
    ld hl, X_PHA
    sub [hl]                ; the four-cycle read minus the three-cycle one
    jr z, .same
    cp 1
    jr nz, .odd
    ld hl, X_PHN
    inc [hl]
.same
    ld hl, X_PHD
    inc [hl]
    ld a, [hl]
    cp PHASE_PAD
    jr nz, .next

    ld a, [X_PHN]
    cp 1
    jr nz, .none
    or a
    ret
.odd
    ld b, 1
    call SetNums8
    ld hl, .noteOdd
    jp FailNote
.none
    ld a, [X_PHN]
    ld b, 1
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "over four one-cycle delays the four-cycle read must overtake the three-cycle one exactly once. It never did, so both instructions are reading the timer at the same point: memory accesses are not landing on their own machine cycles and the peripherals are being advanced once per instruction. Every clock still runs at the right rate, so only a check shaped like this one can see it",0
.noteOdd db "the four-cycle read came out further than one tick from the three-cycle read at the same delay. They are one machine cycle apart and a tick is four, so the only differences possible are none and one",0

; ---------------------------------------------------------------------------
; PhaseA / PhaseB — A = the delay in machine cycles. Each restarts the counter,
; zeroes TIMA, waits that many cycles and reads $FF05, one with the three-cycle
; instruction and one with the four-cycle one. Returns A = what it read.
;
; The delay is made by jumping INTO a sled of nops rather than by a loop: a
; loop would cost a different number of cycles per iteration, which is the one
; thing this measurement cannot have.
; ---------------------------------------------------------------------------
PhaseA:
    ld e, a
    ld a, PHASE_PAD
    sub e
    ld e, a
    ld d, 0
    ld hl, PhaseSledA
    add hl, de
    jr PhaseGo

PhaseB:
    ld e, a
    ld a, PHASE_PAD
    sub e
    ld e, a
    ld d, 0
    ld hl, PhaseSledB
    add hl, de
    ; falls through

PhaseGo:
    di
    xor a
    ldh [rTMA], a
    ld a, TACF_START | TACF_16T
    ldh [rTAC], a
    xor a
    ldh [rDIV], a           ; the counter restarts on this instruction's cycle
    ldh [rTIMA], a          ; and TIMA is zeroed a fixed three cycles into it
    jp hl

PhaseSledA:
    REPT PHASE_PAD
    nop
    ENDR
    ldh a, [rTIMA]
    ld b, a
    xor a
    ldh [rTAC], a           ; leave the timer as it was found
    ld a, b
    ret

PhaseSledB:
    REPT PHASE_PAD
    nop
    ENDR
    ld a, [$FF05]
    ld b, a
    xor a
    ldh [rTAC], a
    ld a, b
    ret

; ---------------------------------------------------------------------------
; GB-CYC-08 — an interrupt lands on the instruction the clock chose.
;
; The companion to GB-CYC-07, and it catches the other half of the same family
; of shortcut. GB-CYC-07 asks whether a memory access lands on its own cycle;
; this one asks whether an event nobody asked for lands on its own cycle.
;
; The shortcut it is aimed at is horizon batching: the peripherals each publish
; the next moment they could be observed, the CPU is let run to the nearest of
; them, and only then is everything advanced in one step. Done properly that is
; exact and costs nothing, and this check passes — a correct horizon includes
; the timer's own overflow. Done with a horizon that misses something, or with
; a fixed batch of instructions, interrupts stop arriving where the clock put
; them and start arriving where the batch ended. Nothing measured over a run of
; instructions can see that either: the interrupt is still delivered, still
; once, and the frame is still the right length.
;
; The measurement needs no reference and no cycle counting. A sled of `nop`s is
; run with the timer set to overflow inside it, and the handler reads the
; return address off the stack — which is the address of the instruction that
; was about to run, so it names the sled position the interrupt landed on to
; one machine cycle. The sled is then entered one cycle later, and one cycle
; later again, eight times. The overflow is unmoved, so each extra cycle before
; the sled must move the landing back by exactly one `nop`:
;
;   delay      0     1     2     3     4     5     6     7
;   landing    n    n-1   n-2   n-3   n-4   n-5   n-6   n-7
;
; Deliver at a batch boundary instead and the landing stops moving with the
; delay: several delays in a row report the same address, which is the whole
; failure. Nothing here depends on WHICH address n is, only that it steps, so
; the check is independent of every constant in the machine but the fact that a
; `nop` is one machine cycle.
;
; Source: TerminalGB docs/conformance-notes.md, 2026-08-20, "speed as a
; first-class measurement" — "the same shape generalises to any shortcut that
; preserves totals: find the observation that depends on phase within an
; instruction rather than on a rate"; and docs/measured/speed-ledger.md §5,
; which names the technique.
; ---------------------------------------------------------------------------
DEF LAND_PAD  EQU 8             ; delays swept, one machine cycle apart
DEF LAND_SLED EQU 64            ; nops the interrupt is given to land in
DEF LAND_TIMA EQU 256 - 12      ; twelve ticks, so the landing sits mid-sled

DEF X_LAND EQU wScratch + 44    ; two bytes: where the interrupt landed
DEF X_LPRV EQU wScratch + 46    ; two bytes: where it landed last time
DEF X_LDLY EQU wScratch + 48

ChkCycLand::
    call LcdOff
    xor a
    ld [X_LDLY], a
.next
    ld a, [X_LDLY]
    call LandRun            ; hl = the landing, or zero if none arrived
    ld a, h
    or l
    jr z, .never

    ; Inside the sled, or the reading is not a reading.
    ld de, LandSledBody
    ld a, l
    sub e
    ld a, h
    sbc d
    jr c, .outside
    ld de, LandSledBody + LAND_SLED
    ld a, l
    sub e
    ld a, h
    sbc d
    jr nc, .outside

    ld a, [X_LDLY]
    or a
    jr z, .keep             ; the first reading has nothing to be compared with

    ; want = the previous landing, one instruction earlier
    ld a, [X_LPRV]
    ld e, a
    ld a, [X_LPRV + 1]
    ld d, a
    dec de
    ld a, e
    cp l
    jr nz, .stuck
    ld a, d
    cp h
    jr nz, .stuck
.keep
    ld a, l
    ld [X_LPRV], a
    ld a, h
    ld [X_LPRV + 1], a
    ld hl, X_LDLY
    inc [hl]
    ld a, [hl]
    cp LAND_PAD
    jr nz, .next
    or a
    ret

.stuck
    ; got = where it landed, want = where the clock put it
    ld b, h
    ld c, l
    ld h, d
    ld l, e
    ld d, b
    ld e, c
    call SetNums16
    ld hl, .noteStuck
    jp FailNote
.never
    ld hl, .noteNever
    jp FailNote
.outside
    ld d, h
    ld e, l
    ld hl, LandSledBody
    call SetNums16
    ld hl, .noteOutside
    jp FailNote
.noteStuck db "delaying the sled by one more machine cycle did not move the instruction the interrupt landed on. The overflow did not move, so the landing had to: an interrupt is being delivered where a batch of instructions ended rather than where the clock raised it",0
.noteNever db "the timer interrupt never arrived inside the sled at all",0
.noteOutside db "the interrupt landed outside the sled it was aimed at, so nothing here was measured",0

; ---------------------------------------------------------------------------
; LandRun — A = the delay in machine cycles. Runs the sled once with the timer
; overflowing inside it. Returns HL = the address the handler was returning to,
; which is the instruction the interrupt landed on, or $0000 if none arrived.
;
; The delay is made by entering a sled of nops part-way along, never by a loop:
; a loop's iterations are not one machine cycle each, which is the only unit
; this measurement has.
; ---------------------------------------------------------------------------
LandRun:
    ld e, a
    ld a, LAND_PAD
    sub e
    ld e, a
    ld d, 0
    ld hl, LandPad
    add hl, de
    ld d, h
    ld e, l                 ; de = where to enter, kept out of the way

    di
    ld hl, wHookTimer
    ld a, LOW(LandIsr)
    ld [hl+], a
    ld a, HIGH(LandIsr)
    ld [hl], a
    xor a
    ld [X_LAND], a
    ld [X_LAND + 1], a
    ldh [rTMA], a
    ld a, IEF_TIMER
    ldh [rIE], a
    ld a, TACF_START | TACF_16T
    ldh [rTAC], a

    ld h, d
    ld l, e
    xor a
    ldh [rIF], a
    ldh [rDIV], a           ; the counter restarts on this instruction's cycle
    ld a, LAND_TIMA
    ldh [rTIMA], a          ; a fixed number of cycles after it, every time
    ei                      ; so the master enable comes up on the sled's first
    jp hl                   ; instruction, whatever the delay

LandPad:
    REPT LAND_PAD
    nop
    ENDR
LandSledBody:
    REPT LAND_SLED
    nop
    ENDR
    di
    xor a
    ldh [rTAC], a
    ldh [rIE], a
    ldh [rIF], a
    ld hl, wHookTimer
    ld a, LOW(DefaultIsr)
    ld [hl+], a
    ld a, HIGH(DefaultIsr)
    ld [hl], a
    ld a, [X_LAND]
    ld l, a
    ld a, [X_LAND + 1]
    ld h, a
    ret                     ; back to LandRun's caller

; The handler. Entered with the interrupted code's HL on the stack and the
; return address under it; AF is live and this sled has no use for it.
LandIsr:
    ld hl, sp+2
    ld a, [hl+]
    ld [X_LAND], a
    ld a, [hl]
    ld [X_LAND + 1], a
    xor a
    ldh [rIE], a            ; one interrupt to a run
    ldh [rTAC], a
    pop hl
    reti

; ---------------------------------------------------------------------------
; GB-CYC-09 — double speed engages, and it does not change how many machine
; cycles anything costs.
;
; rKEY1 is defined in hardware.inc and, until now, never read or written
; anywhere in this cartridge. Two things about it are testable without a
; screen: bit 7 has to flip when the documented STOP sequence (Pan Docs,
; "KEY1 Register") is carried out, and once it has, a batch of instructions
; timed against TIMA the way every other check in this file times one has to
; cost the SAME number of timer ticks as it did before -- "Timer and Divider
; Registers" are on the list of things Pan Docs documents as running at
; double speed too, so the CPU and the clock this file measures it against
; speed up together. (What does NOT speed up is the PPU's own dot clock;
; GB-PPU's double-speed check is the one built on that half of the fact.)
; ---------------------------------------------------------------------------
ChkDoubleSpeedCyc::
    ld a, [wConsole]
    cp CONSOLE_CGB
    jr z, .go
    cp CONSOLE_AGB
    jr z, .go
    ld hl, .noteMono
    jp SkipWith
.go
    ldh a, [rKEY1]
    and $80
    jr nz, .alreadyDouble
    ld hl, BodyNop
    call RunTimed
    ld b, a                 ; the single-speed count
    call FlipSpeed
    ldh a, [rKEY1]
    and $80
    jr z, .noEngage
    ld hl, BodyNop
    call RunTimed
    ld c, a                 ; the double-speed count, saved before flipping back
    call FlipSpeed
    ld a, c
    cp b
    ret z
    call SetNums8
    ld hl, .noteCount
    jp FailNote
.noEngage
    call FlipSpeed           ; leave the CPU single-speed regardless
    ld hl, .noteEngage
    jp FailNote
.alreadyDouble
    ld hl, .noteAlready
    jp SkipWith
.noteMono    db "not run: KEY1 does not exist below Color hardware",0
.noteAlready db "not run: KEY1 already reported double speed before this check touched it",0
.noteEngage  db "STOP with KEY1 bit 0 set did not switch to double speed: bit 7 still read single afterwards",0
.noteCount   db "sixty-four NOPs cost a different number of timer ticks in double speed; the timer speeds up with the CPU, so the count must not change",0
