; font.asm — a 5x7 bitmap font, drawn for this cartridge.
;
; Original letterforms. Nothing here is extracted from a boot ROM, a commercial
; cartridge or any other font: a glyph bitmap is expressive content, so the only
; safe font to ship is one you drew yourself.
;
; Storage is one byte per row, five pixels wide, written as 5-bit binary and
; shifted into the top of the byte at assembly time so the source reads as a
; picture of the letter. Seven rows per glyph, 96 glyphs, covering ASCII
; $20..$7F — which is every character this cartridge can print.
;
; At run time each glyph is expanded into an 8x8 two-bits-per-pixel tile whose
; TILE ID IS THE CHARACTER'S ASCII CODE. That is deliberate and it is the
; single most useful thing about this font: a host that can read VRAM can read
; the report off the tilemap as plain text with no font table and no decoder.
; Blargg's ROMs use the same trick and every emulator test harness that reads
; a screen already knows it.

INCLUDE "hardware.inc"

DEF FONT_FIRST EQU $20
DEF FONT_LAST  EQU $7F
DEF FONT_ROWS  EQU 7

MACRO glyph
    db (\1) << 3, (\2) << 3, (\3) << 3, (\4) << 3
    db (\5) << 3, (\6) << 3, (\7) << 3
ENDM

; The glyphs themselves are 672 bytes of pure data with exactly one reader, so
; they live in a switchable bank and LoadFont maps it -- the same arrangement
; the coverage statement has had since the beginning. The fixed bank is where
; everything that must be reachable from any bank lives, and it is nearly full;
; a table nobody reads except at start-up has no business in it.
SECTION "FontData", ROMX, BANK[1]

FontData::
    ; $20 space
    glyph %00000,%00000,%00000,%00000,%00000,%00000,%00000
    ; $21 !
    glyph %00100,%00100,%00100,%00100,%00100,%00000,%00100
    ; $22 "
    glyph %01010,%01010,%00000,%00000,%00000,%00000,%00000
    ; $23 #
    glyph %01010,%01010,%11111,%01010,%11111,%01010,%01010
    ; $24 $
    glyph %00100,%01111,%10100,%01110,%00101,%11110,%00100
    ; $25 %
    glyph %11001,%11010,%00010,%00100,%01000,%01011,%10011
    ; $26 &
    glyph %01100,%10010,%10100,%01000,%10101,%10010,%01101
    ; $27 '
    glyph %00100,%00100,%00000,%00000,%00000,%00000,%00000
    ; $28 (
    glyph %00010,%00100,%01000,%01000,%01000,%00100,%00010
    ; $29 )
    glyph %01000,%00100,%00010,%00010,%00010,%00100,%01000
    ; $2A *
    glyph %00000,%00100,%10101,%01110,%10101,%00100,%00000
    ; $2B +
    glyph %00000,%00100,%00100,%11111,%00100,%00100,%00000
    ; $2C ,
    glyph %00000,%00000,%00000,%00000,%00110,%00110,%01100
    ; $2D -
    glyph %00000,%00000,%00000,%11111,%00000,%00000,%00000
    ; $2E .
    glyph %00000,%00000,%00000,%00000,%00000,%01100,%01100
    ; $2F /
    glyph %00001,%00010,%00010,%00100,%01000,%01000,%10000
    ; $30 0
    glyph %01110,%10001,%10011,%10101,%11001,%10001,%01110
    ; $31 1
    glyph %00100,%01100,%00100,%00100,%00100,%00100,%01110
    ; $32 2
    glyph %01110,%10001,%00001,%00010,%00100,%01000,%11111
    ; $33 3
    glyph %11111,%00010,%00100,%00010,%00001,%10001,%01110
    ; $34 4
    glyph %00010,%00110,%01010,%10010,%11111,%00010,%00010
    ; $35 5
    glyph %11111,%10000,%11110,%00001,%00001,%10001,%01110
    ; $36 6
    glyph %00110,%01000,%10000,%11110,%10001,%10001,%01110
    ; $37 7
    glyph %11111,%10001,%00010,%00100,%01000,%01000,%01000
    ; $38 8
    glyph %01110,%10001,%10001,%01110,%10001,%10001,%01110
    ; $39 9
    glyph %01110,%10001,%10001,%01111,%00001,%00010,%01100
    ; $3A :
    glyph %00000,%01100,%01100,%00000,%01100,%01100,%00000
    ; $3B ;
    glyph %00000,%01100,%01100,%00000,%01100,%00100,%01000
    ; $3C <
    glyph %00010,%00100,%01000,%10000,%01000,%00100,%00010
    ; $3D =
    glyph %00000,%00000,%11111,%00000,%11111,%00000,%00000
    ; $3E >
    glyph %01000,%00100,%00010,%00001,%00010,%00100,%01000
    ; $3F ?
    glyph %01110,%10001,%00001,%00010,%00100,%00000,%00100
    ; $40 @
    glyph %01110,%10001,%10111,%10101,%10111,%10000,%01110
    ; $41 A
    glyph %01110,%10001,%10001,%11111,%10001,%10001,%10001
    ; $42 B
    glyph %11110,%10001,%10001,%11110,%10001,%10001,%11110
    ; $43 C
    glyph %01110,%10001,%10000,%10000,%10000,%10001,%01110
    ; $44 D
    glyph %11100,%10010,%10001,%10001,%10001,%10010,%11100
    ; $45 E
    glyph %11111,%10000,%10000,%11110,%10000,%10000,%11111
    ; $46 F
    glyph %11111,%10000,%10000,%11110,%10000,%10000,%10000
    ; $47 G
    glyph %01110,%10001,%10000,%10111,%10001,%10001,%01111
    ; $48 H
    glyph %10001,%10001,%10001,%11111,%10001,%10001,%10001
    ; $49 I
    glyph %01110,%00100,%00100,%00100,%00100,%00100,%01110
    ; $4A J
    glyph %00111,%00010,%00010,%00010,%00010,%10010,%01100
    ; $4B K
    glyph %10001,%10010,%10100,%11000,%10100,%10010,%10001
    ; $4C L
    glyph %10000,%10000,%10000,%10000,%10000,%10000,%11111
    ; $4D M
    glyph %10001,%11011,%10101,%10101,%10001,%10001,%10001
    ; $4E N
    glyph %10001,%11001,%10101,%10011,%10001,%10001,%10001
    ; $4F O
    glyph %01110,%10001,%10001,%10001,%10001,%10001,%01110
    ; $50 P
    glyph %11110,%10001,%10001,%11110,%10000,%10000,%10000
    ; $51 Q
    glyph %01110,%10001,%10001,%10001,%10101,%10010,%01101
    ; $52 R
    glyph %11110,%10001,%10001,%11110,%10100,%10010,%10001
    ; $53 S
    glyph %01111,%10000,%10000,%01110,%00001,%00001,%11110
    ; $54 T
    glyph %11111,%00100,%00100,%00100,%00100,%00100,%00100
    ; $55 U
    glyph %10001,%10001,%10001,%10001,%10001,%10001,%01110
    ; $56 V
    glyph %10001,%10001,%10001,%10001,%10001,%01010,%00100
    ; $57 W
    glyph %10001,%10001,%10001,%10101,%10101,%11011,%10001
    ; $58 X
    glyph %10001,%10001,%01010,%00100,%01010,%10001,%10001
    ; $59 Y
    glyph %10001,%10001,%01010,%00100,%00100,%00100,%00100
    ; $5A Z
    glyph %11111,%00001,%00010,%00100,%01000,%10000,%11111
    ; $5B [
    glyph %01110,%01000,%01000,%01000,%01000,%01000,%01110
    ; $5C backslash
    glyph %10000,%01000,%01000,%00100,%00010,%00010,%00001
    ; $5D ]
    glyph %01110,%00010,%00010,%00010,%00010,%00010,%01110
    ; $5E ^
    glyph %00100,%01010,%10001,%00000,%00000,%00000,%00000
    ; $5F _
    glyph %00000,%00000,%00000,%00000,%00000,%00000,%11111

    ; ---- lower case ------------------------------------------------------
    ; The report is written in lower case -- "ok", "checks", "cost", "Passed"
    ; -- and the serial log had always carried it, so a screen that stopped at
    ; $5F printed a question mark for every one of them and the verdict read
    ; `P?????`. These are the same 5x7 grid and the same baseline as the
    ; capitals: seven rows, ink ending on row six.
    ;
    ; g j p q y have no descender. The eighth row of the tile is the gap
    ; between text rows and is deliberately left blank, so a tail drawn into it
    ; would touch the line below; every small screen font of this height makes
    ; the same trade and curls the tail up into the body instead.
    ; $60 `
    glyph %01000,%00100,%00000,%00000,%00000,%00000,%00000
    ; $61 a
    glyph %00000,%00000,%01110,%00001,%01111,%10001,%01111
    ; $62 b
    glyph %10000,%10000,%11110,%10001,%10001,%10001,%11110
    ; $63 c
    glyph %00000,%00000,%01110,%10001,%10000,%10001,%01110
    ; $64 d
    glyph %00001,%00001,%01111,%10001,%10001,%10001,%01111
    ; $65 e
    glyph %00000,%00000,%01110,%10001,%11111,%10000,%01110
    ; $66 f
    glyph %00110,%01001,%01000,%11110,%01000,%01000,%01000
    ; $67 g
    glyph %00000,%00000,%01111,%10001,%01111,%00001,%01110
    ; $68 h
    glyph %10000,%10000,%10110,%11001,%10001,%10001,%10001
    ; $69 i
    glyph %00100,%00000,%01100,%00100,%00100,%00100,%01110
    ; $6A j
    glyph %00010,%00000,%00110,%00010,%00010,%10010,%01100
    ; $6B k
    glyph %10000,%10000,%10010,%10100,%11000,%10100,%10010
    ; $6C l
    glyph %01100,%00100,%00100,%00100,%00100,%00100,%01110
    ; $6D m
    glyph %00000,%00000,%11010,%10101,%10101,%10101,%10101
    ; $6E n
    glyph %00000,%00000,%10110,%11001,%10001,%10001,%10001
    ; $6F o
    glyph %00000,%00000,%01110,%10001,%10001,%10001,%01110
    ; $70 p
    glyph %00000,%00000,%11110,%10001,%11110,%10000,%10000
    ; $71 q
    glyph %00000,%00000,%01111,%10001,%01111,%00001,%00001
    ; $72 r
    glyph %00000,%00000,%10110,%11001,%10000,%10000,%10000
    ; $73 s
    glyph %00000,%00000,%01111,%10000,%01110,%00001,%11110
    ; $74 t
    glyph %01000,%01000,%11110,%01000,%01000,%01001,%00110
    ; $75 u
    glyph %00000,%00000,%10001,%10001,%10001,%10011,%01101
    ; $76 v
    glyph %00000,%00000,%10001,%10001,%10001,%01010,%00100
    ; $77 w
    glyph %00000,%00000,%10001,%10001,%10101,%10101,%01010
    ; $78 x
    glyph %00000,%00000,%10001,%01010,%00100,%01010,%10001
    ; $79 y
    glyph %00000,%00000,%10001,%10001,%01111,%00001,%01110
    ; $7A z
    glyph %00000,%00000,%11111,%00010,%00100,%01000,%11111
    ; $7B {
    glyph %00110,%00100,%00100,%01000,%00100,%00100,%00110
    ; $7C |
    glyph %00100,%00100,%00100,%00100,%00100,%00100,%00100
    ; $7D }
    glyph %01100,%00100,%00100,%00010,%00100,%00100,%01100
    ; $7E ~
    glyph %00000,%01000,%10101,%00010,%00000,%00000,%00000
    ; $7F is not a character. It is drawn as an empty box so that a byte that
    ; should never reach the screen is unmistakable when one does.
    glyph %11111,%10001,%10001,%10001,%10001,%10001,%11111
FontDataEnd::

DEF FONT_GLYPHS EQU (FontDataEnd - FontData) / FONT_ROWS

SECTION "FontCode", ROM0

; ---------------------------------------------------------------------------
; LoadFont — expand the 5x7 font into VRAM tiles at $8000, one tile per
; character, at tile id == ASCII code. Call with the LCD off.
;
; A = the ROM bank that must be mapped when this returns. The glyphs are in
; bank 1 and reaching them means switching, and a caller sitting in a
; switchable bank would otherwise be returned into somebody else's code -- the
; failure is not subtle, but it is silent until the machine wanders off.
;
; Each glyph row becomes both bit planes of the tile row, so text is drawn in
; colour index 3 on index 0: black on white under the palette set below.
; ---------------------------------------------------------------------------
LoadFont::
    push af                 ; the caller's bank, restored on the way out
    ld a, 1
    ld [$2000], a

    ; Blank the whole of tile block 0 first, so an unprintable byte in the
    ; tilemap shows as an empty cell rather than as leftover VRAM.
    ;
    ; The zero is reloaded every time round. Hoisting it out of the loop is the
    ; obvious saving and it is wrong: `ld a, b` is the loop's own counter test,
    ; so from the second pass onwards this wrote the high byte of the counter
    ; into video RAM instead. It filled every tile's unwritten eighth row with
    ; ink, which drew a hairline through every row of the report on screen --
    ; and nothing at all in the serial log, which is why it went unnoticed
    ; until somebody looked at the screen.
    ld hl, _VRAM
    ld bc, $1000
.blank
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .blank

    ld de, FontData
    ld hl, _VRAM + FONT_FIRST * 16
    ld c, FONT_GLYPHS
.glyph
    ld b, FONT_ROWS
.row
    ld a, [de]
    inc de
    ld [hl+], a             ; low bit plane
    ld [hl+], a             ; high bit plane -> colour 3
    dec b
    jr nz, .row
    ; the eighth row is the descender gap, already zero
    inc hl
    inc hl
    dec c
    jr nz, .glyph

    ; 0 = white, 3 = black; the two middle shades are unused by the report.
    ld a, %11100100
    ldh [rBGP], a
    xor a
    ldh [rSCX], a
    ldh [rSCY], a

    pop af
    ld [$2000], a
    ret
