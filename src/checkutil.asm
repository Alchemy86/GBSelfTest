; checkutil.asm — the small vocabulary every check is written in.
;
; A check routine takes no arguments and returns with the carry flag clear for
; a pass and set for a failure. Before returning it may leave behind:
;
;   wDetail    a string saying what specifically was wrong, more precise than
;              the one-line explanation in the registry
;   wGot/wWant two numbers, printed as hex beside the failure
;   wSkipFlag  set instead of a verdict when the check does not apply to this
;              machine; the reason goes in wDetail
;
; Nothing here decides an expected value. These are only the plumbing.

INCLUDE "hardware.inc"

SECTION "CheckUtil", ROM0

; ---------------------------------------------------------------------------
; FailNote — HL = a string explaining the failure. Tail-call it: `jp FailNote`.
; ---------------------------------------------------------------------------
FailNote::
    ld a, l
    ld [wDetail], a
    ld a, h
    ld [wDetail + 1], a
    scf
    ret

; ---------------------------------------------------------------------------
; SetNums8 — record a one-byte got/want pair for the report. A = got, B = want.
; ---------------------------------------------------------------------------
SetNums8::
    ld [wGot], a
    xor a
    ld [wGot + 1], a
    ld a, b
    ld [wWant], a
    xor a
    ld [wWant + 1], a
    inc a
    ld [wHaveNums], a
    ret

; SetNums16 — DE = got, HL = want.
SetNums16::
    ld a, e
    ld [wGot], a
    ld a, d
    ld [wGot + 1], a
    ld a, l
    ld [wWant], a
    ld a, h
    ld [wWant + 1], a
    ld a, 1
    ld [wHaveNums], a
    ret

; ---------------------------------------------------------------------------
; Skip — HL = the reason. A skipped check is not a pass: it is counted and
; printed separately, because a suite that quietly drops what it cannot answer
; is worse than one that says so.
; ---------------------------------------------------------------------------
SkipWith::
    ld a, l
    ld [wDetail], a
    ld a, h
    ld [wDetail + 1], a
    ld a, 1
    ld [wSkipFlag], a
    or a                    ; clear carry
    ret

Pass::
    or a
    ret

; ---------------------------------------------------------------------------
; SoftAdd — x + y computed with nothing but `inc hl`, which sets no flags at
; all and shares no logic with the adder under test.
;
;   D = x, E = y  ->  HL = x + y as a 16-bit sum (H is the carry out)
; ---------------------------------------------------------------------------
SoftAdd::
    ld h, 0
    ld l, d
    ld a, e
    or a
    ret z
    ld b, a
.next
    inc hl
    dec b
    jr nz, .next
    ret

; ---------------------------------------------------------------------------
; SoftSub — x - y the same way, with `dec hl`. H = $FF means a borrow.
; ---------------------------------------------------------------------------
SoftSub::
    ld h, 0
    ld l, d
    ld a, e
    or a
    ret z
    ld b, a
.next
    dec hl
    dec b
    jr nz, .next
    ret

; ---------------------------------------------------------------------------
; ExpectFlags — compare the machine's F against a model.
;   A = F as the CPU left it, B = the model's F.
; The low nibble of F does not exist on this CPU, so it is masked out of the
; comparison here and checked on its own by GB-CPU-07.
; ---------------------------------------------------------------------------
ExpectFlags::
    and $F0
    push af
    ld a, b
    and $F0
    ld b, a
    pop af
    cp b
    ret z
    call SetNums8
    scf
    ret

; ---------------------------------------------------------------------------
; ModelFlags — build an F byte. C = 1 in the bit position wanted.
;   Call with: A = result byte, B = N flag (0/1), C = H (0/1), D = carry (0/1)
;   Returns B = the model F.
; ---------------------------------------------------------------------------
ModelFlags::
    ld e, 0
    or a                    ; Z comes from the result byte
    jr nz, .notZero
    ld e, $80
.notZero
    ld a, b
    or a
    jr z, .noN
    ld a, e
    or $40
    ld e, a
.noN
    ld a, c
    or a
    jr z, .noH
    ld a, e
    or $20
    ld e, a
.noH
    ld a, d
    or a
    jr z, .noC
    ld a, e
    or $10
    ld e, a
.noC
    ld b, e
    ret

; Within — A = measured, B = expected, C = the slack allowed. Returns A
; unchanged so the caller can report it, with the carry set if it is outside.
Within::
    ld d, a
    sub b
    jr nc, .positive
    ld a, b
    sub d
.positive
    cp c
    jr z, .ok
    jr c, .ok
    ld a, d
    scf
    ret
.ok
    ld a, d
    or a
    ret

; ---------------------------------------------------------------------------
; Delay — burn roughly A * 768 M-cycles. Only ever used where the exact figure
; does not matter (waiting for something slow to happen); anything that is
; being measured uses the timer, never this.
; ---------------------------------------------------------------------------
DelayA::
    ld b, a
.outer
    ld c, 0
.inner
    dec c
    jr nz, .inner
    dec b
    jr nz, .outer
    ret

; ---------------------------------------------------------------------------
; WaitVBlankEdge — wait for the start of the next VBlank, counting frames so
; the report can say how long the run took. Requires the LCD to be on.
; ---------------------------------------------------------------------------
WaitVBlankEdge::
    push af
.notYet
    ldh a, [rLY]
    cp 144
    jr nc, .notYet
.wait
    ldh a, [rLY]
    cp 144
    jr c, .wait
    ld hl, wFrames
    call IncWord
    pop af
    ret

; ---------------------------------------------------------------------------
; FlipSpeed — switch the CPU to whichever speed it is not currently running
; at, via the documented STOP sequence (Pan Docs, "KEY1 Register": set bit 0,
; execute STOP, and "the Game Boy will operate at the 'other' speed" once it
; resumes -- bit 0 clears itself). CGB/AGB only; callers decide that.
;
; The LCD is switched off first regardless of console: "Reducing Power
; Consumption" documents that leaving it on for a STOP risks a black screen on
; Color and a damaged DMG, and this routine has no way to know what the caller
; was drawing. IE and IF end up cleared, which is the same state DisarmSled
; already leaves every PPU timing check in.
; ---------------------------------------------------------------------------
FlipSpeed::
    call LcdOff
    di
    xor a
    ldh [rIE], a
    ldh [rIF], a
    ld a, $30
    ldh [rP1], a
    ld a, 1
    ldh [rKEY1], a
    stop
    ret

; ---------------------------------------------------------------------------
; TestVals — the byte values every sweep uses. Not a random selection: these
; are the boundaries where a carry, a half-carry, a sign or a zero can appear,
; which is where an arithmetic bug lives. Sweeping all 65536 pairs would take
; minutes on real hardware and find nothing these do not.
; ---------------------------------------------------------------------------
TestVals::
    db $00, $01, $0F, $10, $7F, $80, $81, $FE, $FF
