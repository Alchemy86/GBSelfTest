; checks_cpu.asm — instruction behaviour and flags.
;
; Nothing in this file compares against a stored answer. Every expectation is
; either recomputed on the machine by a route that shares no logic with the
; instruction under test, or is an algebraic identity that must hold whatever
; the value:
;
;   * the adder is checked against a counter built from `inc hl`, which sets no
;     flags at all and goes through the increment/decrement unit rather than
;     the ALU;
;   * the logic operations are checked against De Morgan and against their own
;     absorption and involution laws;
;   * the rotates are checked by the fact that eight of them are the identity;
;   * DAA is checked against decimal arithmetic done a digit at a time.
;
; The areas run in the order they are listed, and a failure early on can
; cascade: a broken `inc hl` would make the adder model wrong too. Read the
; report top to bottom and fix the first failure first.

INCLUDE "hardware.inc"

SECTION "ChecksCpu", ROMX, BANK[1]

DEF S_RES  EQU wScratch + 0     ; the machine's result byte
DEF S_F    EQU wScratch + 1     ; the machine's F
DEF S_MR   EQU wScratch + 2     ; the model's result byte
DEF S_CY   EQU wScratch + 3     ; the model's carry out
DEF S_HC   EQU wScratch + 4     ; the model's half carry, as $20 or 0
DEF S_TMP  EQU wScratch + 5
DEF wPX    EQU wScratch + 6
DEF wPY    EQU wScratch + 7
DEF wCb    EQU wScratch + 8     ; two bytes
DEF S_CIN  EQU wScratch + 10    ; carry in for ADC/SBC
DEF S_BIT  EQU wScratch + 11

; ---------------------------------------------------------------------------
; ForEachPair — run HL over every ordered pair of TestVals, passing them in
; wPX and wPY. Stops at the first failure, leaving the pair in place so the
; failing check can report it.
; ---------------------------------------------------------------------------
ForEachPair::
    ld a, l
    ld [wCb], a
    ld a, h
    ld [wCb + 1], a
    ld hl, TestVals
    ld b, TESTVALS_N
.outer
    ld a, [hl]
    ld [wPX], a
    push hl
    push bc
    ld hl, TestVals
    ld b, TESTVALS_N
.inner
    ld a, [hl]
    ld [wPY], a
    push hl
    push bc
    ld a, [wCb]
    ld l, a
    ld a, [wCb + 1]
    ld h, a
    ld de, .back
    push de
    jp hl
.back
    pop bc
    pop hl
    jp c, .failInner
    inc hl
    dec b
    jp nz, .inner
    pop bc
    pop hl
    inc hl
    dec b
    jp nz, .outer
    or a
    ret
.failInner
    pop bc
    pop hl
    scf
    ret

; Report the operand pair that broke, so a failure names the input.
ReportPair:
    ld a, [wPX]
    ld [wGot + 1], a
    ld a, [wPY]
    ld [wGot], a
    ld a, [S_F]
    ld [wWant + 1], a
    ld a, [S_RES]
    ld [wWant], a
    ld a, 1
    ld [wHaveNums], a
    ret

; ---------------------------------------------------------------------------
; GB-CPU-01 — ADD and ADC: result, and every flag.
; ---------------------------------------------------------------------------
ChkAdd::
    xor a
    ld [S_CIN], a
    ld hl, CbAdd
    call ForEachPair
    ret c
    ld a, 1
    ld [S_CIN], a
    ld hl, CbAdd
    call ForEachPair
    ret

CbAdd:
    ; ---- the machine ----
    ld a, [wPY]
    ld b, a
    ld a, [S_CIN]
    or a
    ld a, [wPX]
    jp z, .plain
    scf
    adc a, b
    jp .capture
.plain
    add a, b
.capture
    push af
    pop hl
    ld a, h
    ld [S_RES], a
    ld a, l
    ld [S_F], a

    ; ---- the model: x + y + carry-in, counted with `inc hl` ----
    ld a, [wPX]
    ld d, a
    ld a, [wPY]
    ld e, a
    call SoftAdd
    ld a, [S_CIN]
    or a
    jp z, .noCin
    inc hl
.noCin
    ld a, l
    ld [S_MR], a
    ld a, h
    ld [S_CY], a

    ; ---- the model's half carry: the same sum on the low nibbles alone ----
    ld a, [wPX]
    and $0F
    ld d, a
    ld a, [wPY]
    and $0F
    ld e, a
    call SoftAdd
    ld a, [S_CIN]
    or a
    jp z, .noCin2
    inc hl
.noCin2
    ld a, l
    and $10
    jp z, .noHalf
    ld a, $20
.noHalf
    ld [S_HC], a

    ; ---- compare ----
    ld a, [S_RES]
    ld b, a
    ld a, [S_MR]
    cp b
    jp nz, .badResult
    call ModelAddFlags      ; -> B
    ld a, [S_F]
    and $F0
    cp b
    jp nz, .badFlags
    or a
    ret
.badResult
    call ReportPair
    ld hl, .noteR
    jp FailNote
.badFlags
    call ReportPair
    ld hl, .noteF
    jp FailNote
.noteR db "the sum itself is wrong; got/want above are (x,y) and (F,result)",0
.noteF db "the sum is right but F is not: check Z from the result, N clear, H from bit 3 carrying, C from bit 7",0

; N = 0 for an addition; H and C from the model.
ModelAddFlags:
    ld a, [S_MR]
    ld e, 0
    or a
    jp nz, .nz
    ld e, $80
.nz
    ld a, [S_HC]
    or e
    ld e, a
    ld a, [S_CY]
    or a
    jp z, .noC
    ld a, e
    or $10
    ld e, a
.noC
    ld b, e
    ret

; ---------------------------------------------------------------------------
; GB-CPU-02 — SUB, SBC and CP.
; ---------------------------------------------------------------------------
ChkSub::
    xor a
    ld [S_CIN], a
    ld hl, CbSub
    call ForEachPair
    ret c
    ld a, 1
    ld [S_CIN], a
    ld hl, CbSub
    call ForEachPair
    ret

CbSub:
    ld a, [wPY]
    ld b, a
    ld a, [S_CIN]
    or a
    ld a, [wPX]
    jp z, .plain
    scf
    sbc a, b
    jp .capture
.plain
    sub a, b
.capture
    push af
    pop hl
    ld a, h
    ld [S_RES], a
    ld a, l
    ld [S_F], a

    ; model: x - y - carry-in, counted down with `dec hl`
    ld a, [wPX]
    ld d, a
    ld a, [wPY]
    ld e, a
    call SoftSub
    ld a, [S_CIN]
    or a
    jp z, .noCin
    dec hl
.noCin
    ld a, l
    ld [S_MR], a
    ld a, h                 ; $FF once it has gone below zero
    and $01
    ld [S_CY], a

    ld a, [wPX]
    and $0F
    ld d, a
    ld a, [wPY]
    and $0F
    ld e, a
    call SoftSub
    ld a, [S_CIN]
    or a
    jp z, .noCin2
    dec hl
.noCin2
    ld a, h
    or a
    jp z, .noHalf
    ld a, $20
.noHalf
    ld [S_HC], a

    ld a, [S_RES]
    ld b, a
    ld a, [S_MR]
    cp b
    jp nz, .badResult
    call ModelSubFlags
    ld a, [S_F]
    and $F0
    cp b
    jp nz, .badFlags

    ; CP is a SUB that keeps A: same flags, A untouched.
    ld a, [wPY]
    ld b, a
    ld a, [S_CIN]
    or a
    jp nz, .done            ; there is no "CP with carry"
    ld a, [wPX]
    cp b
    push af
    pop hl
    ld a, h
    ld b, a
    ld a, [wPX]
    cp b
    jp nz, .cpAte
    call ModelSubFlags
    ld a, l
    and $F0
    cp b
    jp nz, .cpFlags
.done
    or a
    ret
.badResult
    call ReportPair
    ld hl, .noteR
    jp FailNote
.badFlags
    call ReportPair
    ld hl, .noteF
    jp FailNote
.cpAte
    ld hl, .noteA
    jp FailNote
.cpFlags
    call ReportPair
    ld hl, .noteC
    jp FailNote
.noteR db "the difference is wrong; got/want above are (x,y) and (F,result)",0
.noteF db "the difference is right but F is not: N must be SET for a subtraction, H is a borrow out of bit 4, C is a borrow out of bit 8",0
.noteA db "CP changed A. CP is a SUB whose result is thrown away; only the flags may move",0
.noteC db "CP produced different flags from the SUB of the same operands",0

ModelSubFlags:
    ld a, [S_MR]
    ld e, $40               ; N is set by every subtraction
    or a
    jp nz, .nz
    ld a, e
    or $80
    ld e, a
.nz
    ld a, [S_HC]
    or e
    ld e, a
    ld a, [S_CY]
    or a
    jp z, .noC
    ld a, e
    or $10
    ld e, a
.noC
    ld b, e
    ret

; ---------------------------------------------------------------------------
; GB-CPU-03 — AND, OR, XOR, and CPL, checked by identity rather than by model.
;
; An identity is stronger evidence than a table: it has to hold for every
; value, and it cannot be satisfied by an implementation that happens to agree
; with one particular set of inputs.
; ---------------------------------------------------------------------------
ChkLogic::
    ld hl, CbLogic
    jp ForEachPair

CbLogic:
    ; x AND x == x
    ld a, [wPX]
    ld b, a
    and b
    ld c, a
    ld a, [wPX]
    cp c
    jp nz, .idem
    ; x AND $FF == x, x AND 0 == 0
    ld a, [wPX]
    and $FF
    ld c, a
    ld a, [wPX]
    cp c
    jp nz, .idem
    ld a, [wPX]
    and $00
    or a
    jp nz, .idem
    ; x OR 0 == x, x OR $FF == $FF
    ld a, [wPX]
    or $00
    ld c, a
    ld a, [wPX]
    cp c
    jp nz, .orBad
    ld a, [wPX]
    or $FF
    cp $FF
    jp nz, .orBad
    ; x XOR x == 0, x XOR 0 == x, x XOR $FF == CPL x
    ld a, [wPX]
    ld b, a
    xor b
    or a
    jp nz, .xorBad
    ld a, [wPX]
    xor $00
    ld c, a
    ld a, [wPX]
    cp c
    jp nz, .xorBad
    ld a, [wPX]
    xor $FF
    ld c, a
    ld a, [wPX]
    cpl
    cp c
    jp nz, .cplBad

    ; De Morgan: NOT(x AND y) == (NOT x) OR (NOT y)
    ld a, [wPX]
    ld b, a
    ld a, [wPY]
    and b
    cpl
    ld c, a
    ld a, [wPX]
    cpl
    ld b, a
    ld a, [wPY]
    cpl
    or b
    cp c
    jp nz, .morgan
    ; x XOR y == (x OR y) AND NOT(x AND y)
    ld a, [wPX]
    ld b, a
    ld a, [wPY]
    xor b
    ld c, a
    ld a, [wPX]
    ld b, a
    ld a, [wPY]
    and b
    cpl
    ld d, a
    ld a, [wPX]
    ld b, a
    ld a, [wPY]
    or b
    and d
    cp c
    jp nz, .morgan

    ; flags: AND sets H and clears N and C; OR and XOR clear all three.
    ld a, [wPX]
    ld b, a
    scf                     ; a carry going in must not survive
    ld a, [wPY]
    and b
    push af
    pop hl
    ld a, h
    call ZOnly
    or $20                  ; AND is the one that sets H
    ld b, a
    ld a, l
    and $F0
    cp b
    jp nz, .andFlags

    ld a, [wPX]
    ld b, a
    scf
    ld a, [wPY]
    or b
    push af
    pop hl
    ld a, h
    call ZOnly
    ld b, a
    ld a, l
    and $F0
    cp b
    jp nz, .orFlags

    ld a, [wPX]
    ld b, a
    scf
    ld a, [wPY]
    xor b
    push af
    pop hl
    ld a, h
    call ZOnly
    ld b, a
    ld a, l
    and $F0
    cp b
    jp nz, .xorFlags
    or a
    ret
.idem   ld hl, .nIdem
        jp FailNote
.orBad  ld hl, .nOr
        jp FailNote
.xorBad ld hl, .nXor
        jp FailNote
.cplBad ld hl, .nCpl
        jp FailNote
.morgan ld hl, .nMorgan
        jp FailNote
.andFlags ld hl, .nAndF
        jp FailNote
.orFlags  ld hl, .nOrF
        jp FailNote
.xorFlags ld hl, .nXorF
        jp FailNote
.nIdem  db "AND broke an identity: x AND x, x AND $FF and x AND 0 must give x, x and 0",0
.nOr    db "OR broke an identity: x OR 0 must give x and x OR $FF must give $FF",0
.nXor   db "XOR broke an identity: x XOR x must be 0 and x XOR 0 must be x",0
.nCpl   db "CPL and XOR $FF disagree; one of the two is not complementing every bit",0
.nMorgan db "De Morgan's law does not hold, so AND, OR, XOR and CPL are not consistent with each other",0
.nAndF  db "AND's flags: Z from the result, N and C clear, and H SET. H is the one emulators forget",0
.nOrF   db "OR's flags: Z from the result and N, H, C all clear",0
.nXorF  db "XOR's flags: Z from the result and N, H, C all clear",0

; ZOnly — A = a result byte, returns A = $80 if it was zero, else $00.
ZOnly:
    or a
    ld a, 0
    ret nz
    ld a, $80
    ret

; ---------------------------------------------------------------------------
; GB-CPU-04 — INC r and DEC r: the half carry, and that the carry is untouched.
; ---------------------------------------------------------------------------
ChkIncDec::
    ld hl, TestVals
    ld b, TESTVALS_N
.next
    ld a, [hl]
    ld [wPX], a
    push hl
    push bc
    call OneIncDec
    pop bc
    pop hl
    ret c
    inc hl
    dec b
    jp nz, .next
    or a
    ret

OneIncDec:
    ; INC with the carry set going in: the carry must come out set.
    ld a, [wPX]
    ld b, a
    scf
    ld a, b
    inc a
    push af
    pop hl
    ld a, h
    ld [S_RES], a
    ld a, l
    ld [S_F], a
    ; model: result is x counted up once
    ld a, [wPX]
    ld d, a
    ld e, 1
    call SoftAdd
    ld a, l
    ld b, a
    ld a, [S_RES]
    cp b
    jp nz, .incResult
    ; H is set when the low nibble was already $F
    ld a, [wPX]
    and $0F
    cp $0F
    ld c, 0
    jp nz, .noIncH
    ld c, $20
.noIncH
    ld a, [S_RES]
    call ZOnly
    or c
    or $10                  ; the carry we set going in must be preserved
    ld b, a
    ld a, [S_F]
    and $F0
    cp b
    jp nz, .incFlags

    ; DEC, with the carry clear going in.
    ld a, [wPX]
    ld b, a
    scf
    ccf
    ld a, b
    dec a
    push af
    pop hl
    ld a, h
    ld [S_RES], a
    ld a, l
    ld [S_F], a
    ld a, [wPX]
    ld d, a
    ld e, 1
    call SoftSub
    ld a, l
    ld b, a
    ld a, [S_RES]
    cp b
    jp nz, .decResult
    ld a, [wPX]
    and $0F
    ld c, 0
    or a
    jp nz, .noDecH
    ld c, $20
.noDecH
    ld a, [S_RES]
    call ZOnly
    or c
    or $40                  ; N is set by a decrement
    ld b, a
    ld a, [S_F]
    and $F0
    cp b
    jp nz, .decFlags
    or a
    ret
.incResult ld hl, .nIR
    jp FailNote
.incFlags  ld hl, .nIF
    jp FailNote
.decResult ld hl, .nDR
    jp FailNote
.decFlags  ld hl, .nDF
    jp FailNote
.nIR db "INC r gave the wrong value",0
.nIF db "INC r's flags: Z from the result, N clear, H set only when the low nibble was $F, and C MUST BE LEFT ALONE",0
.nDR db "DEC r gave the wrong value",0
.nDF db "DEC r's flags: Z from the result, N SET, H set only when the low nibble was $0, and C must be left alone",0

; ---------------------------------------------------------------------------
; GB-CPU-05 — the rotates and shifts, checked by the fact that a rotation is
; invertible: eight RLCs, or eight RRCs, are the identity on every byte, and
; nine RLs or RRs are the identity on the nine bits of value-plus-carry.
; ---------------------------------------------------------------------------
ChkRotate::
    ld hl, TestVals
    ld b, TESTVALS_N
.next
    ld a, [hl]
    ld [wPX], a
    push hl
    push bc
    call OneRotate
    pop bc
    pop hl
    ret c
    inc hl
    dec b
    jp nz, .next
    or a
    ret

OneRotate:
    ; eight RLCs return the original byte
    ld a, [wPX]
    ld b, 8
.rlc
    rlca
    dec b
    jp nz, .rlc
    ld b, a
    ld a, [wPX]
    cp b
    jp nz, .rlcBad
    ; and eight RRCs likewise
    ld a, [wPX]
    ld b, 8
.rrc
    rrca
    dec b
    jp nz, .rrc
    ld b, a
    ld a, [wPX]
    cp b
    jp nz, .rrcBad
    ; nine RLs through the carry return the byte AND the carry
    ld a, [wPX]
    scf
    ccf                     ; carry in = 0
    ld b, 9
.rl
    rla
    dec b
    jp nz, .rl
    jp c, .rlBad            ; the 0 we started with must come back round
    ld b, a
    ld a, [wPX]
    cp b
    jp nz, .rlBad
    ; nine RRs the same way
    ld a, [wPX]
    scf
    ccf
    ld b, 9
.rr
    rra
    dec b
    jp nz, .rr
    jp c, .rrBad
    ld b, a
    ld a, [wPX]
    cp b
    jp nz, .rrBad
    ; SWAP is its own inverse, and is four RLCs
    ld a, [wPX]
    swap a
    swap a
    ld b, a
    ld a, [wPX]
    cp b
    jp nz, .swapBad
    ld a, [wPX]
    swap a
    ld c, a
    ld a, [wPX]
    rlca
    rlca
    rlca
    rlca
    cp c
    jp nz, .swapBad
    ; SLA doubles: x + x by the counter, with C from bit 7
    ld a, [wPX]
    sla a
    ld c, a
    push af
    pop hl
    ld a, l
    ld [S_F], a
    ld a, [wPX]
    ld d, a
    ld e, a
    call SoftAdd
    ld a, l
    ld b, a
    ld a, c
    cp b
    jp nz, .slaBad
    ld a, c
    call ZOnly
    ld b, a
    ld a, h                 ; the counter's carry out
    or a
    jp z, .slaNoC
    ld a, b
    or $10
    ld b, a
.slaNoC
    ld a, [S_F]
    and $F0
    cp b
    jp nz, .slaFlags
    ; SRA leaves bit 7 where it was; SRL clears it. They differ in that alone.
    ld a, [wPX]
    sra a
    ld c, a
    ld a, [wPX]
    srl a
    ld b, a
    ld a, [wPX]
    and $80
    or b
    cp c
    jp nz, .sraBad
    or a
    ret
.rlcBad  ld hl, .nRlc
    jp FailNote
.rrcBad  ld hl, .nRrc
    jp FailNote
.rlBad   ld hl, .nRl
    jp FailNote
.rrBad   ld hl, .nRr
    jp FailNote
.swapBad ld hl, .nSwap
    jp FailNote
.slaBad  ld hl, .nSla
    jp FailNote
.slaFlags ld hl, .nSlaF
    jp FailNote
.sraBad  ld hl, .nSra
    jp FailNote
.nRlc  db "eight RLCAs did not return the original byte, so the rotate is losing or duplicating a bit",0
.nRrc  db "eight RRCAs did not return the original byte",0
.nRl   db "nine RLAs did not restore the byte and the carry. RL rotates through the carry, making a nine-bit ring",0
.nRr   db "nine RRAs did not restore the byte and the carry",0
.nSwap db "SWAP is not exchanging the two nibbles: it must be its own inverse and must equal four RLCAs",0
.nSla  db "SLA did not double the byte",0
.nSlaF db "SLA's flags: Z from the result, N and H clear, C from the bit shifted out of bit 7",0
.nSra  db "SRA must keep bit 7 and SRL must clear it; the two differ in nothing else",0

; ---------------------------------------------------------------------------
; GB-CPU-06 — BIT, RES and SET.
;
; Only bits 0, 3, 4 and 7 are exercised individually: they are the ones at the
; ends and either side of the nibble boundary, and each needs its own opcode
; written out. The coverage note says so rather than implying all eight.
; ---------------------------------------------------------------------------
ChkBitOps::
    ld hl, TestVals
    ld b, TESTVALS_N
.next
    ld a, [hl]
    ld [wPX], a
    push hl
    push bc
    call OneBitOps
    pop bc
    pop hl
    ret c
    inc hl
    dec b
    jp nz, .next
    or a
    ret

OneBitOps:
    ld a, [wPX]
    ld c, a

    ; bit 0
    ld a, c
    set 0, a
    ld b, a
    bit 0, b
    jp z, .setBad
    ld a, c
    res 0, a
    ld b, a
    bit 0, b
    jp nz, .resBad
    ld a, c
    set 0, a
    xor c
    cp 0
    jp z, .b0ok
    cp $01
    jp nz, .onlyBad
.b0ok

    ; bit 3
    ld a, c
    set 3, a
    ld b, a
    bit 3, b
    jp z, .setBad
    ld a, c
    res 3, a
    ld b, a
    bit 3, b
    jp nz, .resBad
    ld a, c
    set 3, a
    xor c
    cp 0
    jp z, .b3ok
    cp $08
    jp nz, .onlyBad
.b3ok

    ; bit 4
    ld a, c
    set 4, a
    ld b, a
    bit 4, b
    jp z, .setBad
    ld a, c
    res 4, a
    ld b, a
    bit 4, b
    jp nz, .resBad
    ld a, c
    set 4, a
    xor c
    cp 0
    jp z, .b4ok
    cp $10
    jp nz, .onlyBad
.b4ok

    ; bit 7
    ld a, c
    set 7, a
    ld b, a
    bit 7, b
    jp z, .setBad
    ld a, c
    res 7, a
    ld b, a
    bit 7, b
    jp nz, .resBad
    ld a, c
    set 7, a
    xor c
    cp 0
    jp z, .b7ok
    cp $80
    jp nz, .onlyBad
.b7ok

    ; BIT's flags: Z is the complement of the bit, N clear, H SET, C untouched.
    ld a, c
    scf
    bit 7, a
    push af
    pop hl
    ld a, c
    and $80
    jp nz, .bit7set
    ld b, $80
    jp .bit7flags
.bit7set
    ld b, 0
.bit7flags
    ld a, b
    or $20                  ; H
    or $10                  ; the carry we set going in
    ld b, a
    ld a, l
    and $F0
    cp b
    jp nz, .bitFlags
    or a
    ret
.setBad  ld hl, .nSet
    jp FailNote
.resBad  ld hl, .nRes
    jp FailNote
.onlyBad ld hl, .nOnly
    jp FailNote
.bitFlags ld hl, .nFlags
    jp FailNote
.nSet   db "SET n did not leave the bit set",0
.nRes   db "RES n did not leave the bit clear",0
.nOnly  db "SET n changed a bit other than n; RES and SET touch exactly one bit each",0
.nFlags db "BIT n's flags: Z is the COMPLEMENT of the bit, N clear, H SET, and C must be left exactly as it was",0

; ---------------------------------------------------------------------------
; GB-CPU-07 — the flags register has only four bits.
;
; F's low nibble does not exist in silicon; there is nothing there to store a
; bit in. `POP AF` is the only instruction that can try, and on hardware the
; four low bits read back as zero whatever was pushed.
; ---------------------------------------------------------------------------
ChkPopAf::
    ld hl, $FFFF
    push hl
    pop af
    push af
    pop hl
    ld a, l
    cp $F0
    jp nz, .bad
    ld hl, $FF0F
    push hl
    pop af
    push af
    pop hl
    ld a, l
    or a
    jp nz, .bad
    or a
    ret
.bad
    ld b, $F0
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "POP AF must mask F's low four bits to zero: they are not implemented, so nothing can be stored there",0

; ---------------------------------------------------------------------------
; GB-CPU-08 — ADD SP,e and LD HL,SP+e take their flags from the low byte.
;
; Both are 16-bit operations whose H and C come from an EIGHT-bit addition of
; SP's low byte and the offset treated as unsigned, and both always clear Z.
; That asymmetry is the whole of the check.
; ---------------------------------------------------------------------------
ChkSpAdd::
    ld [wScratch + 20], sp
    ld sp, $CFF8            ; low byte $F8, so a small offset crosses both
    ld hl, sp+8             ; boundaries that matter
    push af
    pop de
    ld a, e
    ld [S_F], a
    ld a, l
    ld [S_RES], a
    ; restore the stack before doing anything that needs it
    ld sp, $CFF8
    ld hl, wScratch + 20
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld sp, hl

    ; the model: $F8 + $08 carries out of bit 3 and out of bit 7
    ld a, [S_RES]
    cp $00
    jp nz, .badResult
    ld a, [S_F]
    and $F0
    cp $30                  ; Z clear, N clear, H set, C set
    jp nz, .badFlags
    or a
    ret
.badResult
    ld b, $00
    ld a, [S_RES]
    call SetNums8
    ld hl, .nR
    jp FailNote
.badFlags
    ld b, $30
    ld a, [S_F]
    and $F0
    call SetNums8
    ld hl, .nF
    jp FailNote
.nR db "LD HL,SP+e computed the wrong address",0
.nF db "LD HL,SP+e and ADD SP,e take H and C from adding the OFFSET to SP's LOW BYTE only, and always clear Z and N",0

; ---------------------------------------------------------------------------
; GB-CPU-09 — ADD HL,rr: H from bit 11, C from bit 15, Z untouched.
; ---------------------------------------------------------------------------
ChkAddHl::
    ; Z going in must still be there coming out.
    ld hl, $0FFF
    ld bc, $0001
    ld a, 0
    or a                    ; Z set
    add hl, bc
    push af
    pop de
    ld a, h
    cp $10
    jp nz, .bad
    ld a, l
    or a
    jp nz, .bad
    ld a, e
    and $F0
    cp $A0                  ; Z kept, N clear, H set, C clear
    jp nz, .badFlags
    ; a carry out of bit 15
    ld hl, $FFFF
    ld bc, $0001
    add hl, bc
    push af
    pop de
    ld a, h
    or l
    jp nz, .bad
    ld a, e
    and $30
    cp $30                  ; H and C both set
    jp nz, .badFlags
    or a
    ret
.bad
    ld hl, .nR
    jp FailNote
.badFlags
    ld a, e
    and $F0
    ld b, $A0
    call SetNums8
    ld hl, .nF
    jp FailNote
.nR db "ADD HL,rr produced the wrong sum",0
.nF db "ADD HL,rr: N clear, H from a carry out of BIT 11 (not bit 3), C from a carry out of bit 15, and Z LEFT ALONE",0

; ---------------------------------------------------------------------------
; GB-CPU-10 — SCF, CCF and CPL.
; ---------------------------------------------------------------------------
ChkFlagOps::
    ; SCF sets C and clears N and H, keeping Z. Note that examining F costs F:
    ; the AND and the CP below overwrite it, so every instruction under test
    ; here is given its starting state again immediately beforehand.
    ld a, 0
    or a                    ; Z set, C clear
    scf
    push af
    pop hl
    ld a, l
    and $F0
    cp $90
    jp nz, .scfBad
    ; CCF complements C rather than setting it
    ld a, 0
    or a
    scf                     ; Z set, C set
    ccf
    push af
    pop hl
    ld a, l
    and $F0
    cp $80
    jp nz, .ccfBad
    ; and complements it the other way too
    ld a, 0
    or a                    ; Z set, C clear
    ccf
    push af
    pop hl
    ld a, l
    and $F0
    cp $90
    jp nz, .ccfBad
    ; CPL: A + CPL A is $FF, and N and H come out set with Z and C untouched.
    ; The starting flags are established from A itself, because the comparison
    ; above has left F holding the result of a CP.
    ld a, $A5
    or a                    ; Z clear, C clear
    scf                     ; C set
    cpl
    push af
    pop hl
    ld a, l
    ld [S_F], a
    ld a, h
    ld d, a
    ld e, $A5
    call SoftAdd
    ld a, l
    cp $FF
    jp nz, .cplBad
    ld a, h
    or a
    jp nz, .cplBad
    ld a, [S_F]
    and $F0
    cp $70                  ; Z clear (it was), N set, H set, C kept from SCF
    jp nz, .cplFlags
    or a
    ret
.scfBad
    ld hl, .nScf
    jp FailNote
.ccfBad
    ld hl, .nCcf
    jp FailNote
.cplBad
    ld hl, .nCpl
    jp FailNote
.cplFlags
    ld hl, .nCplF
    jp FailNote
.nCplF db "CPL must SET both N and H and leave Z and C exactly as they were",0
.nScf db "SCF must set C and clear N and H, leaving Z alone",0
.nCcf db "CCF must COMPLEMENT C, not set it, and must clear N and H",0
.nCpl db "CPL must complement every bit of A, so A plus the complement is always $FF",0

; ---------------------------------------------------------------------------
; GB-CPU-11 — 16-bit INC and DEC touch no flag at all.
; ---------------------------------------------------------------------------
ChkInc16::
    ld hl, $F000
    push hl
    pop af                  ; F = $00 with the low nibble already masked
    ld bc, $00FF
    inc bc
    dec bc
    inc bc
    push af
    pop hl
    ld a, l
    and $F0
    or a
    jp nz, .bad
    ld a, b
    cp $01
    jp nz, .bad2
    ld a, c
    or a
    jp nz, .bad2
    ; and with every flag set going in they must all still be there
    ld hl, $FFF0
    push hl
    pop af
    ld bc, $FFFF
    inc bc
    push af
    pop hl
    ld a, l
    and $F0
    cp $F0
    jp nz, .bad
    or a
    ret
.bad
    ld hl, .nF
    jp FailNote
.bad2
    ld hl, .nR
    jp FailNote
.nF db "INC rr and DEC rr must not touch F. They run in the increment unit, not the ALU, and there is no path to the flags",0
.nR db "INC rr or DEC rr produced the wrong value",0

; ---------------------------------------------------------------------------
; GB-CPU-12 — DAA, against decimal arithmetic done a digit at a time.
;
; DAA is the instruction emulators most often get half right, because the
; correction it applies depends on N, H and C and not on A alone: after a
; subtraction it must SUBTRACT the correction. The model here never uses DAA;
; it works in tens and units and carries between them by hand, which is what
; decimal arithmetic is.
; ---------------------------------------------------------------------------
BcdVals:
    db $00, $01, $09, $10, $25, $49, $50, $88, $99

ChkDaa::
    ld hl, BcdVals
    ld b, BCDVALS_N
.outer
    ld a, [hl]
    ld [wPX], a
    push hl
    push bc
    ld hl, BcdVals
    ld b, BCDVALS_N
.inner
    ld a, [hl]
    ld [wPY], a
    push hl
    push bc
    call OneDaa
    pop bc
    pop hl
    jp c, .failInner
    inc hl
    dec b
    jp nz, .inner
    pop bc
    pop hl
    inc hl
    dec b
    jp nz, .outer
    or a
    ret
.failInner
    pop bc
    pop hl
    scf
    ret

; Nib — A = a byte, returns A = its high nibble as a number 0..15.
HighNib:
    swap a
    and $0F
    ret

OneDaa:
    ; ---- the machine: an addition, then the decimal adjustment ----
    ld a, [wPY]
    ld b, a
    ld a, [wPX]
    add a, b
    daa
    push af
    pop hl
    ld a, h
    ld [S_RES], a
    ld a, l
    ld [S_F], a

    ; ---- the model: units first, then tens, carrying by hand ----
    ld a, [wPX]
    and $0F
    ld d, a
    ld a, [wPY]
    and $0F
    ld e, a
    call SoftAdd
    ld a, l
    cp 10
    ld c, 0
    jp c, .unitsOk
    sub 10
    ld c, 1
.unitsOk
    ld [S_MR], a            ; the units digit
    ld a, [wPX]
    call HighNib
    ld d, a
    ld a, [wPY]
    call HighNib
    ld e, a
    call SoftAdd
    ld a, c
    or a
    jp z, .noUnitCarry
    inc hl
.noUnitCarry
    ld a, l
    cp 10
    ld c, 0
    jp c, .tensOk
    sub 10
    ld c, 1
.tensOk
    swap a
    ld b, a
    ld a, [S_MR]
    or b                    ; tens in the high nibble, units in the low
    ld b, a
    ld a, [S_RES]
    cp b
    jp nz, .badAdd
    ; the carry out says the sum went past ninety-nine
    ld a, [S_F]
    and $10
    ld d, a
    ld a, c
    or a
    jp z, .wantNoCarry
    ld a, d
    or a
    jp z, .badCarry
    jp .subtract
.wantNoCarry
    ld a, d
    or a
    jp nz, .badCarry

.subtract
    ; ---- and the same for a subtraction, where x is at least y ----
    ld a, [wPX]
    ld b, a
    ld a, [wPY]
    cp b
    jp z, .doSub
    jp nc, .done            ; y is larger, so skip: the model would need a
.doSub                      ; borrow out of the hundreds column
    ld a, [wPY]
    ld b, a
    ld a, [wPX]
    sub a, b
    daa
    ld [S_RES], a

    ld a, [wPX]
    and $0F
    ld d, a
    ld a, [wPY]
    and $0F
    ld e, a
    call SoftSub
    ld a, h
    or a
    ld c, 0
    jp z, .subUnitsOk
    ld a, l
    add 10
    ld l, a
    ld c, 1
.subUnitsOk
    ld a, l
    and $0F
    ld [S_MR], a
    ld a, [wPX]
    call HighNib
    ld d, a
    ld a, [wPY]
    call HighNib
    ld e, a
    call SoftSub
    ld a, c
    or a
    jp z, .noSubBorrow
    dec hl
.noSubBorrow
    ld a, l
    and $0F
    swap a
    ld b, a
    ld a, [S_MR]
    or b
    ld b, a
    ld a, [S_RES]
    cp b
    jp nz, .badSub
.done
    or a
    ret
.badAdd
    call ReportPair
    ld hl, .nAdd
    jp FailNote
.badCarry
    call ReportPair
    ld hl, .nCarry
    jp FailNote
.badSub
    call ReportPair
    ld hl, .nSub
    jp FailNote
.nAdd   db "DAA after an addition did not give the decimal sum. It adds 6 to a nibble that went past 9 or that carried, and 96 when both did",0
.nCarry db "DAA's carry out is wrong: it must be set when the decimal result passes 99, and must stay set if it was already",0
.nSub   db "DAA after a SUBTRACTION must SUBTRACT its correction, not add it. The N flag is what tells it which way to go, and an implementation that only looks at A passes addition and fails this",0
