; print.asm — the report goes two places at once.
;
; The screen is a 20x18 character buffer in WRAM, blitted to the tilemap with
; the LCD off between areas. The serial port gets the same text, unabridged,
; one byte at a time, because that is what a host can capture without anyone
; watching — and it is the convention every existing Game Boy test ROM runner
; already understands.
;
; The two sinks are separately maskable (`wSinks`): the screen gets a
; one-line-per-area summary so it stays readable on a 20-column display, and
; the serial log gets every check, every measured number and every explanation.

INCLUDE "hardware.inc"

SECTION "Print", ROM0

DEF SCREEN_W EQU 20
DEF SCREEN_H EQU 18

; ---------------------------------------------------------------------------
; ClearScreen — blank the character buffer and home the cursor.
; ---------------------------------------------------------------------------
ClearScreen::
    ld hl, wTextBuf
    ld bc, SCREEN_W * SCREEN_H
.next
    ld a, ' '
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .next
    xor a
    ld [wCurX], a
    ld [wCurY], a
    ret

; ---------------------------------------------------------------------------
; ShowScreen — copy the character buffer into the background tilemap.
;
; Done with the LCD off, which is the one way to write VRAM that is correct on
; every machine whatever its mode-3 length: an emulator that blocks VRAM during
; mode 3 (as hardware does) and one that does not both see the same writes.
; The cartridge must not depend on its own report being drawn correctly.
; ---------------------------------------------------------------------------
ShowScreen::
    push bc
    push de
    push hl
    call LcdOff
    ld hl, wTextBuf
    ld de, _SCRN0
    ld c, SCREEN_H
.row
    ld b, SCREEN_W
.col
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .col
    ; the tilemap is 32 wide; skip the 12 columns off the right of the screen
    push hl
    ld hl, 32 - SCREEN_W
    add hl, de
    ld d, h
    ld e, l
    pop hl
    dec c
    jr nz, .row
    call LcdOn
    pop hl
    pop de
    pop bc
    ret

; ---------------------------------------------------------------------------
; ScreenChar — A = character, into the buffer, wrapping and scrolling.
; ---------------------------------------------------------------------------
ScreenChar:
    push af
    push bc
    push de
    push hl
    cp $0A
    jr z, .newline
    cp ' '
    jr c, .bad
    cp $80                  ; the font covers $20..$7F; see font.asm
    jr c, .ok
.bad
    ld a, '?'
.ok
    ld b, a
    ; buffer index = y * 20 + x
    ld a, [wCurY]
    ld l, a
    ld h, 0
    add hl, hl              ; y*2
    ld d, h
    ld e, l
    add hl, hl              ; y*4
    add hl, hl              ; y*8
    add hl, de              ; y*10
    add hl, hl              ; y*20
    ld a, [wCurX]
    ld e, a
    ld d, 0
    add hl, de
    ld de, wTextBuf
    add hl, de
    ld [hl], b
    ld a, [wCurX]
    inc a
    ld [wCurX], a
    cp SCREEN_W
    jr c, .done
.newline
    xor a
    ld [wCurX], a
    ld a, [wCurY]
    inc a
    cp SCREEN_H
    jr c, .storeY
    call ScrollUp
    ld a, SCREEN_H - 1
.storeY
    ld [wCurY], a
.done
    pop hl
    pop de
    pop bc
    pop af
    ret

ScrollUp:
    ld hl, wTextBuf + SCREEN_W
    ld de, wTextBuf
    ld bc, SCREEN_W * (SCREEN_H - 1)
.copy
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .copy
    ld b, SCREEN_W
    ld a, ' '
.clear
    ld [de], a
    inc de
    dec b
    jr nz, .clear
    ret

; ---------------------------------------------------------------------------
; SerialChar — A = character, out of the link port.
;
; The transfer is started with the internal clock and waited for, because a
; real Game Boy shifts one bit per 8192 Hz tick and a byte written on top of an
; unfinished transfer is a byte lost. The wait is bounded: a machine whose SC
; bit 7 never clears is not one to hang on, so the port is written off for the
; rest of the run and the screen carries the report alone.
; ---------------------------------------------------------------------------
SerialChar::
    push af
    push bc
    ld a, [wSerialOK]
    or a
    jr z, .gone
    pop bc
    pop af
    push af
    push bc
    ldh [rSB], a
    ld a, [wSerialFast]
    or SCF_START | SCF_INTERNAL
    ldh [rSC], a
    push hl
    ld hl, wSerialSent
    call IncWord
    pop hl
    ld bc, 8000
.wait
    ldh a, [rSC]
    bit 7, a
    jr z, .gone
    dec bc
    ld a, b
    or c
    jr nz, .wait
    xor a
    ld [wSerialOK], a
.gone
    pop bc
    pop af
    ret

; ---------------------------------------------------------------------------
; The public entry points. PrintX honours `wSinks`; SerialX always goes to the
; link port only, whatever the mask says.
; ---------------------------------------------------------------------------
PrintChar::
    push af
    ld a, [wSinks]
    and SINK_SCREEN
    jr z, .noScreen
    pop af
    push af
    call ScreenChar
.noScreen
    ld a, [wSinks]
    and SINK_SERIAL
    jr z, .noSerial
    pop af
    push af
    call SerialChar
.noSerial
    pop af
    ret

PrintStr::
    push af
    push hl
.next
    ld a, [hl+]
    or a
    jr z, .done
    call PrintChar
    jr .next
.done
    pop hl
    pop af
    ret

PrintNewline::
    push af
    ld a, [wSinks]
    and SINK_SCREEN
    jr z, .noScreen
    ld a, $0A
    call ScreenChar
.noScreen
    ld a, [wSinks]
    and SINK_SERIAL
    jr z, .noSerial
    ld a, $0D
    call SerialChar
    ld a, $0A
    call SerialChar
.noSerial
    pop af
    ret

PrintLine::
    call PrintStr
    call PrintNewline
    ret

SerialStr::
    push af
    push hl
.next
    ld a, [hl+]
    or a
    jr z, .done
    call SerialChar
    jr .next
.done
    pop hl
    pop af
    ret

SerialNewline::
    push af
    ld a, $0D
    call SerialChar
    ld a, $0A
    call SerialChar
    pop af
    ret

SerialLine::
    call SerialStr
    call SerialNewline
    ret

; ---------------------------------------------------------------------------
; Numbers
; ---------------------------------------------------------------------------

; SerialDec2 — A as exactly two decimal digits (check numbers read better
; zero-padded, so GB-CPU-04 sorts next to GB-CPU-12).
SerialDec2::
    push af
    push bc
    ld c, 0
.tens
    cp 10
    jr c, .ones
    sub 10
    inc c
    jr .tens
.ones
    ld b, a
    ld a, c
    add '0'
    call SerialChar
    ld a, b
    add '0'
    call SerialChar
    pop bc
    pop af
    ret

; PrintHexNib — low nibble of A
PrintHexNib:
    and $0F
    cp 10
    jr c, .digit
    add 'A' - 10
    jr .out
.digit
    add '0'
.out
    call SerialChar
    ret

; SerialByteHex — A as two hex digits
SerialByteHex::
    push af
    push af
    swap a
    call PrintHexNib
    pop af
    call PrintHexNib
    pop af
    ret

; SerialWordHex — HL points at a little-endian 16-bit value
SerialWordHex::
    push af
    push hl
    inc hl
    ld a, [hl-]
    call SerialByteHex
    ld a, [hl]
    call SerialByteHex
    pop hl
    pop af
    ret

; PrintDec3 — A in decimal, no leading zeros, 1..3 digits
; PrintDec2 — A as exactly two digits, to whichever sinks are enabled. The
; check codes are fixed width on purpose: `GB-PPU-08`, never `GB-PPU-8`, so
; that a reader, a grep and a documentation anchor all spell them the same way.
PrintDec2::
    push af
    push bc
    ld c, 0
.tens
    cp 10
    jr c, .ones
    sub 10
    inc c
    jr .tens
.ones
    ld b, a
    ld a, c
    add '0'
    call PrintChar
    ld a, b
    add '0'
    call PrintChar
    pop bc
    pop af
    ret

PrintDec3::
    push af
    push bc
    ld c, 0                 ; hundreds
.h
    cp 100
    jr c, .t
    sub 100
    inc c
    jr .h
.t
    ld b, 0
.t2
    cp 10
    jr c, .u
    sub 10
    inc b
    jr .t2
.u
    push af
    ld a, c
    or a
    jr z, .noHundreds
    add '0'
    call PrintChar
    ld a, b
    add '0'
    call PrintChar
    jr .units
.noHundreds
    ld a, b
    or a
    jr z, .units
    add '0'
    call PrintChar
.units
    pop af
    add '0'
    call PrintChar
    pop bc
    pop af
    ret

; PrintWordDec — HL points at a little-endian 16-bit value, printed in decimal
; with no leading zeros. Repeated subtraction: this CPU has no divide.
PrintWordDec::
    push af
    push bc
    push de
    push hl
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a                 ; de = the value
    xor a
    ld [wDecSeen], a
    ld hl, .powers
.place
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld b, a                 ; bc = this decimal place
    or c
    jr z, .final
    push hl
    ld l, 0                 ; digit
.sub
    ld a, e
    sub c
    ld h, a
    ld a, d
    sbc b
    jr c, .digitDone
    ld d, a
    ld e, h
    inc l
    jr .sub
.digitDone
    ld a, l
    pop hl
    or a
    jr nz, .emit
    ld a, [wDecSeen]
    or a
    jr z, .place            ; a leading zero: say nothing
    xor a
.emit
    ld [wDecSeen], a        ; any non-zero digit also marks "seen"
    add '0'
    call PrintChar
    ld a, 1
    ld [wDecSeen], a
    jr .place
.final
    ld a, e
    add '0'
    call PrintChar
    pop hl
    pop de
    pop bc
    pop af
    ret
.powers
    dw 10000, 1000, 100, 10, 0
