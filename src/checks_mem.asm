; checks_mem.asm — the memory map itself.
;
; This is the area the public suites cover most thinly, and it is the one a
; cartridge is best placed to check: every question here is "write here, read
; there, did the byte arrive", which needs no host and no reference image.
;
; It is also where a rough emulator differs from a careful one most cheaply.
; Echo RAM, in particular, is a wiring accident of the real console that a
; from-scratch memory map will not have unless somebody knew to put it there,
; and commercial games do read through it.

INCLUDE "hardware.inc"

SECTION "ChecksMem", ROMX, BANK[2]

DEF E_TMP EQU wScratch + 80
; GB-MEM-06's two observed bytes.
DEF P_TMP EQU wScratch + 96

; A check may only scribble on memory the cartridge is not using. Writing to a
; convenient round address is exactly how the first version of the echo check
; landed a byte on top of the captured boot registers at $C000 and made
; GB-BOOT-03 report a value no console has ever handed over. Everything below
; goes through the cartridge's own scratch and its echo, and through $DDFF,
; which is above the transfer source page and below the stack.
DEF E_A EQU wScratch + 76
DEF E_B EQU wScratch + 77
DEF ECHO_OFFSET EQU $2000

; ---------------------------------------------------------------------------
; GB-MEM-01 — work RAM appears a second time at $E000.
;
; The console decodes only thirteen address bits for work RAM, so $E000-$FDFF
; is the same memory as $C000-$DDFF seen through a different door. It is not a
; copy: a write through either door is visible through the other.
; ---------------------------------------------------------------------------
ChkEchoRam::
    ld a, $A7
    ld [E_A], a
    ld a, [E_A + ECHO_OFFSET]
    cp $A7
    jr nz, .notMirrored
    ; and the other way round, so it cannot be a one-way copy
    ld a, $5C
    ld [E_B + ECHO_OFFSET], a
    ld a, [E_B]
    cp $5C
    jr nz, .notBack
    ; the top of the window, one byte below where it stops
    ld a, $3E
    ld [$DDFF], a
    ld a, [$FDFF]
    cp $3E
    jr nz, .notTop
    or a
    ret
.notMirrored
    ld b, $A7
    call SetNums8
    ld hl, .note1
    jp FailNote
.notBack
    ld b, $5C
    call SetNums8
    ld hl, .note2
    jp FailNote
.notTop
    ld b, $3E
    call SetNums8
    ld hl, .note3
    jp FailNote
.note1 db "a byte written in work RAM was not there 8192 bytes higher up. Work RAM is decoded with thirteen address bits, so it appears again from $E000 to $FDFF",0
.note2 db "a byte written through the echo was not visible in work RAM. The echo is the same memory, not a copy of it",0
.note3 db "the echo stops one byte short. It covers $E000 to $FDFF, mirroring $C000 to $DDFF; the last 512 bytes of work RAM have no echo because the object memory is in the way",0

; ---------------------------------------------------------------------------
; GB-MEM-02 — high RAM is its own 127 bytes.
; ---------------------------------------------------------------------------
ChkHram::
    ld c, $80
    ld b, $7F
    ld d, $10
.write
    ld a, d
    ldh [c], a
    inc d
    inc c
    dec b
    jr nz, .write
    ld c, $80
    ld b, $7F
    ld d, $10
.read
    ldh a, [c]
    cp d
    jr nz, .bad
    inc d
    inc c
    dec b
    jr nz, .read
    ; and it is not the same memory as work RAM
    ld a, $11
    ld [E_A], a
    ldh a, [$FF80]
    cp $11
    jr z, .aliased
    or a
    ret
.bad
    ld b, d
    call SetNums8
    ld hl, .noteRw
    jp FailNote
.aliased
    ld hl, .noteAlias
    jp FailNote
.noteRw    db "high RAM did not hold what was written to it. The 127 bytes from $FF80 to $FFFE are ordinary memory inside the processor, and they are the only memory reachable during an object transfer",0
.noteAlias db "high RAM and work RAM are the same storage here. They are separate: high RAM is on the processor die and stays reachable when the buses are busy",0

; ---------------------------------------------------------------------------
; GB-MEM-03 — a write to the ROM area does not change the ROM.
;
; Those addresses are the mapper's control registers, not memory. A write must
; reach the mapper and the byte underneath must be unchanged, which is what
; makes it safe for a game to keep code and its bank switches in the same bank.
; ---------------------------------------------------------------------------
ChkRomWrite::
    ld a, [$0100]
    ld b, a
    ld a, $FF
    ld [$0100], a           ; goes to the mapper's RAM enable, not to memory
    ld a, [$0100]
    cp b
    jr nz, .stuck
    xor a
    ld [$0000], a           ; leave the cartridge RAM disabled again
    or a
    ret
.stuck
    call SetNums8
    xor a
    ld [$0000], a
    ld hl, .note
    jp FailNote
.note db "a write to the ROM area changed what was read back. Cartridge ROM cannot be written; $0000 to $7FFF is where the mapper's registers are decoded and a write there is a command, not a store",0

; ---------------------------------------------------------------------------
; GB-MEM-04 — the whole of video RAM is there, and only while the LCD is off
; is it safe to say so.
; ---------------------------------------------------------------------------
ChkVramSize::
    call LcdOff
    ld hl, $8000
    ld d, $01
.write
    ld a, d
    ld [hl+], a
    inc d
    ld a, h
    cp $A0
    jr nz, .write
    ld hl, $8000
    ld d, $01
.read
    ld a, [hl+]
    cp d
    jr nz, .bad
    inc d
    ld a, h
    cp $A0
    jr nz, .read
    call LoadFont           ; the report needs its glyphs back
    or a
    ret
.bad
    ld b, d
    call SetNums8
    call LoadFont
    ld hl, .note
    jp FailNote
.note db "video RAM did not hold what was written across its full eight kilobytes from $8000 to $9FFF",0

; ---------------------------------------------------------------------------
; GB-MEM-05 — object memory is 160 bytes and stops there.
;
; The 96 bytes above it are not part of it. What they read is not the same on
; every console, so this checks only that they are not a continuation of the
; object memory -- which is the mistake worth catching, because a game that
; walks off the end of the object list would then corrupt it.
; ---------------------------------------------------------------------------
ChkOamSize::
    call LcdOff
    ld hl, _OAMRAM
    ld d, $20
    ld b, 160
.write
    ld a, d
    ld [hl+], a
    inc d
    dec b
    jr nz, .write
    ld hl, _OAMRAM
    ld d, $20
    ld b, 160
.read
    ld a, [hl+]
    cp d
    jr nz, .bad
    inc d
    dec b
    jr nz, .read
    ; $FEA0 is past the end: writing there must not disturb the last entry
    ld a, [_OAMRAM + 159]
    ld c, a
    ld a, $77
    ld [$FEA0], a
    ld a, [_OAMRAM + 159]
    cp c
    jr nz, .spilled
    or a
    ret
.bad
    ld b, d
    call SetNums8
    ld hl, .noteRw
    jp FailNote
.spilled
    ld hl, .noteSpill
    jp FailNote
.noteRw    db "object memory did not hold what was written across its 160 bytes",0
.noteSpill db "a write above $FE9F changed object memory. The object list is forty entries of four bytes and it ends at $FE9F; the block above it is not more of the same",0

; ===========================================================================
; A few more instruction behaviours that separate a careful implementation
; from a rough one. They belong to the CPU area, so they belong in its bank.
; ===========================================================================
SECTION "ChecksCpuExtra", ROMX, BANK[1]

; ---------------------------------------------------------------------------
; GB-CPU-13 — the accumulator rotates always clear Z; the prefixed ones do not.
;
; RLCA, RRCA, RLA and RRA are one byte and always leave Z clear, whatever the
; result. Their two-byte namesakes RLC A, RRC A, RL A and RR A set Z from the
; result like every other prefixed operation. It is the same rotation with two
; different flag rules, and an implementation that shares one routine between
; them gets one of the two wrong.
; ---------------------------------------------------------------------------
ChkRotateZ::
    xor a                   ; zero: rotating it can only give zero back
    rlca
    jr z, .oneByteSetZ
    xor a
    rrca
    jr z, .oneByteSetZ
    xor a
    rla
    jr z, .oneByteSetZ
    xor a
    rra
    jr z, .oneByteSetZ
    ; and now the prefixed ones, which must set it
    xor a
    rlc a
    jr nz, .prefixedClearedZ
    xor a
    rrc a
    jr nz, .prefixedClearedZ
    xor a
    rl a
    jr nz, .prefixedClearedZ
    xor a
    rr a
    jr nz, .prefixedClearedZ
    ; a non-zero result must leave Z clear in the prefixed form too
    ld a, $81
    rlc a
    jr z, .prefixedSetZ
    or a
    ret
.oneByteSetZ
    ld hl, .n1
    jp FailNote
.prefixedClearedZ
    ld hl, .n2
    jp FailNote
.prefixedSetZ
    ld hl, .n3
    jp FailNote
.n1 db "RLCA, RRCA, RLA and RRA must ALWAYS clear Z, even when the result is zero. Only their prefixed namesakes take Z from the result",0
.n2 db "RLC A, RRC A, RL A and RR A must set Z when the result is zero. They are the prefixed forms and follow the ordinary rule",0
.n3 db "a prefixed rotate set Z for a non-zero result",0

; ---------------------------------------------------------------------------
; GB-CPU-14 — INC and DEC through HL are read, modify, write.
; ---------------------------------------------------------------------------
ChkIncHl::
    ld hl, wScratch + 90
    ld a, $0F
    ld [hl], a
    scf
    inc [hl]
    push af
    pop de
    ld a, [hl]
    cp $10
    jr nz, .badValue
    ld a, e
    and $F0
    cp $30                  ; H set by the nibble carry, C kept, Z and N clear
    jr nz, .badFlags
    ld a, $01
    ld [hl], a
    dec [hl]
    ld a, [hl]
    or a
    jr nz, .badValue
    or a
    ret
.badValue
    ld b, $10
    call SetNums8
    ld hl, .nV
    jp FailNote
.badFlags
    ld b, $30
    ld a, e
    and $F0
    call SetNums8
    ld hl, .nF
    jp FailNote
.nV db "INC [HL] or DEC [HL] did not change the byte in memory",0
.nF db "INC [HL] takes its flags from the byte, not from the accumulator: Z from the result, N clear, H from the low nibble carrying, and C untouched",0

; ---------------------------------------------------------------------------
; GB-CPU-15 — the pointer forms of LD move HL as well as the byte.
; ---------------------------------------------------------------------------
ChkHlIncDec::
    ld hl, wScratch + 88
    ld a, $12
    ld [hl+], a
    ld a, $34
    ld [hl-], a
    ld a, [hl+]
    cp $12
    jr nz, .bad
    ld a, [hl-]
    cp $34
    jr nz, .bad
    ld a, l
    ld b, LOW(wScratch + 88)
    cp b
    jr nz, .bad
    or a
    ret
.bad
    ld hl, .note
    jp FailNote
.note db "LD [HL+],A and its three relatives must move the pointer by one after the access, and in the direction the mnemonic says",0

SECTION "ChecksMemExtra", ROMX, BANK[2]

; ---------------------------------------------------------------------------
; GB-MEM-06 — $FEA0-$FEFF is not a hole.
;
; The bytes above object memory are commonly emulated as open bus reading $FF.
; That is right only while the picture processor owns object memory; with the
; screen off the region answers, and *what* it answers is one of the clearest
; differences between the consoles:
;
;   DMG, MGB, SGB      $00
;   CGB revisions 0-D  a small RAM area masked with a revision-specific value
;   CGB revision E,
;   AGB, AGS, GBP      the high nibble of the low address byte, twice:
;                      $FEA0 reads $AA, $FEF0 reads $FF
;
; So this is asserted where the answer is documented and *reported* where it is
; not: a Color console cannot tell its own revision apart from inside, and a
; cartridge that guessed would be inventing a fact. Reporting is the useful
; thing a self-test can do that a wiki cannot — it says what the machine in
; your hands actually did.
; ---------------------------------------------------------------------------
ChkProhibited::
    call LcdOff
    di
    ld a, [$FEA0]
    ld [P_TMP], a
    ld a, [$FEF0]
    ld [P_TMP + 1], a

    ld a, [wConsole]
    cp CONSOLE_CGB
    jr z, .report
    cp CONSOLE_UNK
    jr z, .report
    cp CONSOLE_AGB
    jr z, .agb

    ; DMG and MGB: both bytes must read zero
    ld a, [P_TMP]
    or a
    jr nz, .badZero
    ld a, [P_TMP + 1]
    or a
    jr nz, .badZero
    ret

.agb
    ld a, [P_TMP]
    cp $AA
    jr nz, .badNibble
    ld a, [P_TMP + 1]
    cp $FF
    jr nz, .badNibble
    ret

.badZero
    ld b, $00
    call SetNums8
    ld hl, .noteZero
    jp FailNote
.badNibble
    ld b, $AA
    ld a, [P_TMP]
    call SetNums8
    ld hl, .noteNibble
    jp FailNote
.report
    ld a, [P_TMP]           ; high byte is $FEA0, low is $FEF0
    ld d, a
    ld a, [P_TMP + 1]
    ld e, a
    ld hl, $AAFF            ; what a revision E or an Advance answers
    call SetNums16
    ld hl, .noteReport
    jp SkipWith

.noteZero   db "with the screen off, $FEA0 and $FEF0 must read $00 on this console. Reading $FF means the region is being treated as a hole, which is only right while object memory is blocked",0
.noteNibble db "an Advance answers this region with the high nibble of the low address byte twice, so $FEA0 reads $AA and $FEF0 reads $FF",0
.noteReport db "reported, not judged: a Color console cannot tell its own revision from inside, and revisions 0 to D answer differently from revision E. The pair shown is what this machine gave for $FEA0 and $FEF0; a revision E or an Advance gives $AA and $FF",0
