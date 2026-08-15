; checks_ppu.asm — the display, measured from inside the machine.
;
; A cartridge cannot see the picture. There is no framebuffer: the PPU streams
; pixels straight to the panel and keeps none of them, which is why the suites
; that judge pixels ship photographs and need a host.
;
; What a cartridge CAN see is the SHAPE OF THE WORK. Mode 3 lasts exactly as
; long as the fetcher takes, and the fetcher takes longer when there is more to
; draw: a fine scroll offset, an object on the line, the window starting. So
; the cartridge lays out a scene whose cost is documented, measures how long
; mode 3 actually took, and compares. That is a real test of rendering
; behaviour with no reference image anywhere in it.
;
; HOW MODE 3 IS TIMED. The coincidence interrupt is armed on one scanline, and
; the handler runs a variable number of NOPs before reading STAT once. Sweeping
; that delay by binary search finds the exact machine cycle at which the mode
; changes. The delay from the interrupt to the first NOP is unknown and does
; not matter: every result here is the DIFFERENCE between two such edges, so
; the unknown cancels. The floor is four dots, because a machine cycle is four
; dots and the CPU cannot look between them; the coverage note says so.

INCLUDE "hardware.inc"

SECTION "ChecksPpu", ROMX, BANK[3]

DEF P_LO   EQU wScratch + 56
DEF P_HI   EQU wScratch + 57
DEF P_MID  EQU wScratch + 58
DEF P_WANT EQU wScratch + 59    ; the mode we are searching past
DEF P_E3   EQU wScratch + 60
DEF P_E2   EQU wScratch + 61
DEF P_BASE EQU wScratch + 62
DEF P_TMP  EQU wScratch + 63
DEF P_CNT  EQU wScratch + 64    ; two bytes
DEF P_MAXLY EQU wScratch + 66
DEF P_SEEN  EQU wScratch + 67
DEF P_SCENE EQU wScratch + 68
DEF X_CNT   EQU wScratch + 70    ; two bytes
DEF X_BASE  EQU wScratch + 72    ; a scene's measurement, kept out of the
                                 ; registers because setting up the next scene
                                 ; clobbers them

DEF MEASURE_LINE EQU 60
DEF SLED_MAX     EQU 128

; ---------------------------------------------------------------------------
; Scenes. Everything is set up with the LCD off so that no write can land in a
; mode that would refuse it -- which is itself one of the things under test.
; ---------------------------------------------------------------------------
SceneBase::
    call LcdOff
    call ClearObjects
    xor a
    ldh [rSCX], a
    ldh [rSCY], a
    ldh [rWY], a
    ld a, 7
    ldh [rWX], a
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON
    ldh [rLCDC], a
    ret

ClearObjects:
    ld hl, _OAMRAM
    ld b, 40
.next
    xor a
    ld [hl+], a             ; Y = 0 puts the object entirely above the screen
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    dec b
    jr nz, .next
    ret

; Ten objects, all on the line the measurement runs on, all at the same screen
; x so that they share one background tile. Ten is the hardware limit per line.
SetupObjects:
    call ClearObjects
    ld hl, _OAMRAM
    ld b, 10
.next
    ld a, MEASURE_LINE + 16
    ld [hl+], a
    ld a, 8
    ld [hl+], a
    xor a
    ld [hl+], a
    ld [hl+], a
    dec b
    jr nz, .next
    ret

; ---------------------------------------------------------------------------
; The delay sled and its handler.
; ---------------------------------------------------------------------------
SledStart:
    REPT SLED_MAX
    nop
    ENDR
    ldh a, [rSTAT]
    and 3
    ld [P_TMP], a
    pop hl
    reti

StatSledHook:
    ld hl, wSledJump
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    jp hl

ArmSled:
    di
    ld hl, wHookStat
    ld a, LOW(StatSledHook)
    ld [hl+], a
    ld a, HIGH(StatSledHook)
    ld [hl], a
    ld a, MEASURE_LINE
    ldh [rLYC], a
    ld a, STATF_LYC
    ldh [rSTAT], a
    ld a, IEF_STAT
    ldh [rIE], a
    xor a
    ldh [rIF], a
    ret

DisarmSled:
    di
    xor a
    ldh [rIE], a
    ldh [rIF], a
    ldh [rSTAT], a
    ld hl, wHookStat
    ld a, LOW(DefaultIsr)
    ld [hl+], a
    ld a, HIGH(DefaultIsr)
    ld [hl], a
    ret

; StatWorks — does the coincidence interrupt fire at all? Asked once, by
; polling with interrupts still disabled, so that nothing here can ever sleep
; on an event a broken machine will not deliver.
StatWorks:
    ld a, [wStatWorks]
    or a
    ret nz
    call ArmSled
    ld de, 40000
.wait
    ldh a, [rIF]
    and IEF_STAT
    jr nz, .yes
    dec de
    ld a, d
    or e
    jr nz, .wait
    xor a
    ld [wStatWorks], a
    ret
.yes
    ld a, 1
    ld [wStatWorks], a
    ret

; ProbeD — A = the delay in machine cycles; returns A = the mode STAT reported.
ProbeD:
    ld b, a
    ld a, SLED_MAX
    sub b
    ld e, a
    ld d, 0
    ld hl, SledStart
    add hl, de
    ld a, l
    ld [wSledJump], a
    ld a, h
    ld [wSledJump + 1], a
    ld a, $FF
    ld [P_TMP], a
    di
    xor a
    ldh [rIF], a
    ei
    halt
    di
    push hl
    ld hl, wFrames
    call IncWord
    pop hl
    ld a, [P_TMP]
    ret

; FindEdge — smallest delay at which STAT no longer reports P_WANT, searched
; between P_LO and SLED_MAX - 1. The predicate is monotone over that range, so
; a binary search costs eight frames rather than a hundred and twenty-eight.
FindEdge:
    ld a, SLED_MAX - 1
    ld [P_HI], a
.loop
    ld a, [P_LO]
    ld b, a
    ld a, [P_HI]
    cp b
    jr z, .done
    jr c, .done
    ; mid = (lo + hi) / 2
    add b
    rra                     ; the carry out of the add is the ninth bit
    ld [P_MID], a
    call ProbeD
    ld b, a
    ld a, [P_WANT]
    cp b
    jr z, .stillWanted
    ld a, [P_MID]
    ld [P_HI], a
    jr .loop
.stillWanted
    ld a, [P_MID]
    inc a
    ld [P_LO], a
    jr .loop
.done
    ld a, [P_LO]
    ret

; MeasureE3 — the delay at which mode 3 ends for whatever scene is set up.
MeasureE3:
    xor a
    ld [P_LO], a
    ld a, 3
    ld [P_WANT], a
    call FindEdge
    ret

; ---------------------------------------------------------------------------
; GB-PPU-01 — a frame is 70224 cycles.
;
; Counted in divider increments, which are 256 cycles each: 274.3 of them.
; Two clocks that share no logic agreeing on the length of a frame is a much
; stronger statement than either one measured on its own.
; ---------------------------------------------------------------------------
ChkFrameLen::
    call SceneBase
    call SyncToLineZero
    di
    xor a
    ldh [rDIV], a
    ld hl, 0
    ldh a, [rDIV]
    ld b, a
.onLine0
    call CountDiv
    ldh a, [rLY]
    or a
    jr z, .onLine0
.rest
    call CountDiv
    ldh a, [rLY]
    or a
    jr nz, .rest
    ; HL now holds the divider increments in exactly one frame, and 274 of
    ; them does not fit in a register, so the window is compared sixteen bits
    ; wide: 70224 cycles is 274.3 increments of 256 cycles each.
    ld d, h
    ld e, l
    ld bc, 272
    ld a, e
    sub c
    ld a, d
    sbc b
    jr c, .bad
    ld bc, 277
    ld a, e
    sub c
    ld a, d
    sbc b
    jr nc, .bad
    or a
    ret
.bad
    ld hl, 274
    call SetNums16
    ld hl, .note
    jp FailNote
.note db "the divider and the display disagree about how long a frame is. A frame is 154 lines of 456 cycles, which is 70224 cycles, which is 274.3 divider increments",0

; CountDiv — one divider increment counted into HL, with B holding the last
; reading. The loop is far shorter than the 256 cycles between increments, so
; none can be missed.
CountDiv:
    ldh a, [rDIV]
    cp b
    ret z
    ld b, a
    inc hl
    ret

SyncToLineZero:
    ldh a, [rLY]
    or a
    jr z, SyncToLineZero
.wait
    ldh a, [rLY]
    or a
    jr nz, .wait
    push hl
    ld hl, wFrames
    call IncWord
    pop hl
    ret

; ---------------------------------------------------------------------------
; GB-PPU-02 — a scanline is 456 cycles.
; ---------------------------------------------------------------------------
ChkLineLen::
    call SceneBase
    call SyncToLineZero
    di
    xor a
    ldh [rDIV], a
    ld hl, 0
    ldh a, [rDIV]
    ld b, a
    ld c, 32                ; measure across thirty-two lines
.wait
    call CountDiv
    ldh a, [rLY]
    cp c
    jr c, .wait
    ; thirty-two lines is 14592 cycles, which is 57 divider increments
    ld a, h
    or a
    jr nz, .bad
    ld a, l
    ld b, 57
    ld c, 2
    call Within
    ret nc
    ld b, 57
.bad
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "LY is not advancing once every 456 cycles. Every scanline is the same length whatever is drawn on it: mode 3 borrowing time takes it back out of mode 0",0

; ---------------------------------------------------------------------------
; GB-PPU-03 — LY counts to 153 and wraps.
; ---------------------------------------------------------------------------
ChkLyRange::
    call SceneBase
    call SyncToLineZero
    di
    xor a
    ld [P_MAXLY], a
    ld [P_SEEN], a
.leaveLine0
    ldh a, [rLY]
    or a
    jr z, .leaveLine0       ; the sweep ends when LY reads zero, so get off it
.loop
    ldh a, [rLY]
    ld b, a
    ld a, [P_MAXLY]
    cp b
    jr nc, .noMax
    ld a, b
    ld [P_MAXLY], a
.noMax
    ld a, b
    cp 144
    jr nz, .notVb
    ld a, 1
    ld [P_SEEN], a
.notVb
    ld a, b
    or a
    jr nz, .loop            ; go round until LY wraps back to zero
    ; LY 153 is real but nearly invisible: at the start of the last line the
    ; register reads 153 for four dots and then reads 0 for the remaining 452.
    ; A polling loop is thirty-six dots long, so it almost always sees 152 and
    ; then zero. Both readings are correct hardware; anything else is not.
    ld a, [P_MAXLY]
    cp 152
    jr c, .wrongMax
    cp 154
    jr nc, .wrongMax
    ld a, [P_SEEN]
    or a
    jr z, .noVb
    or a
    ret
.wrongMax
    ld b, 152
    ld a, [P_MAXLY]
    call SetNums8
    ld hl, .noteMax
    jp FailNote
.noVb
    ld hl, .noteVb
    jp FailNote
.noteMax db "the highest LY reached was not 152 or 153. A frame is 154 lines: 144 visible and ten of vertical blank. Reading 152 rather than 153 is correct, because on the last line LY reads 153 for only four dots before reading zero -- but reading anything lower means the frame is short, and anything higher means it is long",0
.noteVb  db "LY never reached 144, so the display never entered vertical blank",0

; ---------------------------------------------------------------------------
; GB-PPU-04 — the mode sequence on a line, and mode 1 in the blank.
; ---------------------------------------------------------------------------
ChkModeSeq::
    call SceneBase
    call SyncToLineZero
    di
    ; on a visible line the modes must come round in the order 2, 3, 0
    call WaitMode2
    jr c, .noMode2
    ld b, 2
    call WaitModeNot
    cp 3
    jr nz, .not3
    ld b, 3
    call WaitModeNot
    or a
    jr nz, .not0
    ; and every line of the vertical blank reports mode 1
.toVb
    ldh a, [rLY]
    cp 145
    jr nz, .toVb
    ldh a, [rSTAT]
    and 3
    cp 1
    jr nz, .notVb
    or a
    ret
.noMode2 ld hl, .n2
    jp FailNote
.not3    ld b, 3
    call SetNums8
    ld hl, .n3
    jp FailNote
.not0    ld b, 0
    call SetNums8
    ld hl, .n0
    jp FailNote
.notVb   ld hl, .n1
    jp FailNote
.n2 db "STAT never reported mode 2 on a visible line: the object scan is the first eighty cycles of every one of them",0
.n3 db "mode 2 was not followed by mode 3. The order is fixed: scan objects, draw, then rest",0
.n0 db "mode 3 was not followed by mode 0. Whatever is left of the 456 cycles after drawing is horizontal blank",0
.n1 db "STAT must report mode 1 for the whole of the vertical blank",0

WaitMode2:
    ld de, 30000
.loop
    ldh a, [rSTAT]
    and 3
    cp 2
    ret z
    dec de
    ld a, d
    or e
    jr nz, .loop
    scf
    ret

; WaitModeNot — B is the mode we are known to be in; wait for it to end and
; return the one that follows. The mode is NOT re-read here to find out where
; we are: between the caller noticing mode 2 and calling this, mode 3 may
; already have begun, and re-reading would then wait for mode 3 to end and
; report mode 0 as though it had followed mode 2 directly.
WaitModeNot:
    ld de, 30000
.loop
    ldh a, [rSTAT]
    and 3
    cp b
    ret nz
    dec de
    ld a, d
    or e
    jr nz, .loop
    ld a, $FF
    ret

; ---------------------------------------------------------------------------
; GB-PPU-05 — the coincidence flag and its interrupt.
; ---------------------------------------------------------------------------
ChkLyc::
    call SceneBase
    di
    ld a, 80
    ldh [rLYC], a
    xor a
    ldh [rSTAT], a
.wait80
    ldh a, [rLY]
    cp 80
    jr nz, .wait80
    ldh a, [rSTAT]
    and STATF_LYCF
    jr z, .noFlag
    ; a value LY can never take must leave the flag clear
    ld a, 200
    ldh [rLYC], a
    call SyncToLineZero
    ldh a, [rSTAT]
    and STATF_LYCF
    jr nz, .stuck
    ; and the interrupt must be raised, which is checked by polling rather
    ; than by sleeping on it
    ld a, 100
    ldh [rLYC], a
    ld a, STATF_LYC
    ldh [rSTAT], a
    xor a
    ldh [rIF], a
    ld de, 30000
.waitIrq
    ldh a, [rIF]
    and IEF_STAT
    jr nz, .gotIrq
    dec de
    ld a, d
    or e
    jr nz, .waitIrq
    xor a
    ldh [rSTAT], a
    ldh [rIF], a
    ld hl, .noteIrq
    jp FailNote
.gotIrq
    xor a
    ldh [rSTAT], a
    ldh [rIF], a
    or a
    ret
.noFlag
    ld hl, .noteFlag
    jp FailNote
.stuck
    ld hl, .noteStuck
    jp FailNote
.noteFlag  db "bit 2 of STAT was clear while LY equalled LYC. It is a latched comparison, updated as each line begins",0
.noteStuck db "bit 2 of STAT stayed set for an LYC that LY never reaches",0
.noteIrq   db "with the coincidence source selected, bit 1 of IF must be raised when the lines match",0

; ---------------------------------------------------------------------------
; GB-PPU-06 — the shortest mode 3 is 172 cycles.
;
; Derived from two measured edges and two documented constants: the line is
; 456 cycles and the object scan is 80 of them, so what is left over after
; mode 3 ends is horizontal blank, and mode 3 is what remains.
; ---------------------------------------------------------------------------
ChkMode3Base::
    call StatWorks
    ld a, [wStatWorks]
    or a
    jr z, .noStat
    call SceneBase
    call ArmSled
    call MeasureE3
    ld [P_E3], a
    ; and on from there to the moment the next line's object scan begins
    ld [P_LO], a
    xor a
    ld [P_WANT], a
    call FindEdge
    ld [P_E2], a
    call DisarmSled

    ; mode 3 = 456 - 80 - four cycles per machine cycle of horizontal blank
    ld a, [P_E2]
    ld b, a
    ld a, [P_E3]
    ld c, a
    ld a, b
    sub c                   ; horizontal blank, in machine cycles
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl              ; four dots to the machine cycle
    ld de, 376              ; 456 in the line, less the 80 of the object scan
    ld a, e
    sub l
    ld c, a
    ld a, d
    sbc h
    or a
    jr nz, .wild
    ld a, c
    ld [P_BASE], a
    ld b, 172
    ld c, 4
    call Within
    ret nc
    ld b, 172
    call SetNums8
    ld hl, .note
    jp FailNote
.wild
    ld hl, .note
    jp FailNote
.noStat
    ld hl, .noteSkip
    jp SkipWith
.note     db "with no objects, no window and no fine scroll, mode 3 is 172 cycles. That is the fetcher drawing twenty tiles with nothing to interrupt it",0
.noteSkip db "not run: the coincidence interrupt never fired, so there is no way to stand on a known cycle of a known scanline",0

; ---------------------------------------------------------------------------
; GB-PPU-07 — fine scrolling costs the fetcher time.
; ---------------------------------------------------------------------------
ChkMode3Scx::
    call StatWorks
    ld a, [wStatWorks]
    or a
    jr z, .noStat
    call SceneBase
    call ArmSled
    call MeasureE3
    ld [P_E3], a
    call DisarmSled
    call SceneBase
    ld a, 4                 ; four is the one offset a cartridge can resolve
    ldh [rSCX], a
    call ArmSled
    call MeasureE3
    ld b, a
    call DisarmSled
    xor a
    ldh [rSCX], a
    ld a, [P_E3]
    ld c, a
    ld a, b
    sub c                   ; the extra machine cycles, so four dots each
    ld b, 1
    ld c, 0
    call Within
    ret nc
    ld b, 1
    call SetNums8
    ld hl, .note
    jp FailNote
.noStat
    ld hl, .noteSkip
    jp SkipWith
.note     db "an SCX of 4 must make mode 3 four cycles longer: the first four pixels of the leftmost tile are fetched and thrown away. A mode 3 of fixed length cannot show this",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-08 — objects cost the fetcher time.
; ---------------------------------------------------------------------------
ChkMode3Obj::
    call StatWorks
    ld a, [wStatWorks]
    or a
    jr z, .noStat
    call SceneBase
    call ArmSled
    call MeasureE3
    ld [P_E3], a
    call DisarmSled
    call LcdOff
    call SetupObjects
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON | LCDCF_OBJON
    ldh [rLCDC], a
    call ArmSled
    call MeasureE3
    ld [P_SCENE], a         ; not a register: SceneBase below clobbers them
    call DisarmSled
    call SceneBase
    ld a, [P_E3]
    ld c, a
    ld a, [P_SCENE]
    sub c
    jr c, .tooFew
    ; ten objects cost at least sixty dots, which is fifteen machine cycles,
    ; and no more than about eighty-eight, which is twenty-two
    cp 15
    jr c, .tooFew
    cp 23
    jr nc, .tooMany
    or a
    ret
.tooFew
    ld b, 15
    call SetNums8
    ld hl, .noteFew
    jp FailNote
.tooMany
    ld b, 15
    call SetNums8
    ld hl, .noteMany
    jp FailNote
.noStat
    ld hl, .noteSkip
    jp SkipWith
.noteFew  db "ten objects on a line did not lengthen mode 3. Each one stops the background fetcher for at least six cycles while its own row is fetched; a renderer that draws the line in one go and charges a fixed 172 cycles reports no penalty at all",0
.noteMany db "ten objects lengthened mode 3 by much more than the fetcher should have to pay",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-09 — the window costs the fetcher time.
; ---------------------------------------------------------------------------
ChkMode3Win::
    call StatWorks
    ld a, [wStatWorks]
    or a
    jr z, .noStat
    call SceneBase
    call ArmSled
    call MeasureE3
    ld [P_E3], a
    call DisarmSled
    call LcdOff
    xor a
    ldh [rWY], a
    ld a, 7
    ldh [rWX], a
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON | LCDCF_WINON
    ldh [rLCDC], a
    call ArmSled
    call MeasureE3
    ld [P_SCENE], a         ; not a register: SceneBase below clobbers them
    call DisarmSled
    call SceneBase
    ld a, [P_E3]
    ld c, a
    ld a, [P_SCENE]
    sub c
    jr c, .none
    or a
    jr z, .none
    cp 6
    jr nc, .tooMuch
    or a
    ret
.none
    ld b, 2
    call SetNums8
    ld hl, .noteNone
    jp FailNote
.tooMuch
    ld b, 2
    call SetNums8
    ld hl, .noteMuch
    jp FailNote
.noStat
    ld hl, .noteSkip
    jp SkipWith
.noteNone db "starting the window did not lengthen mode 3. Taking it over costs at least six cycles: the fetcher throws away what it had and begins again from the window's own map",0
.noteMuch db "starting the window lengthened mode 3 by far more than the documented six cycles",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-10 — video RAM belongs to the fetcher during mode 3.
; ---------------------------------------------------------------------------
ChkVramBlock::
    call SceneBase
    di
    ; the space glyph is blank, so this address holds zero when readable
    ld hl, _VRAM + $20 * 16
    ld de, 30000
.wait
    ldh a, [rSTAT]
    and 3
    cp 3
    jr z, .inMode3
    dec de
    ld a, d
    or e
    jr nz, .wait
    ld hl, .noteNever
    jp FailNote
.inMode3
    ld a, [hl]
    cp $FF
    jr nz, .readable
    or a
    ret
.readable
    ld b, $FF
    call SetNums8
    ld hl, .note
    jp FailNote
.note      db "the CPU read real data out of video RAM while the fetcher owned the bus. During mode 3 a read must return $FF; a game that writes there mid-line is relying on it being ignored",0
.noteNever db "STAT never reported mode 3 at all",0

; ---------------------------------------------------------------------------
; GB-PPU-11 — object memory belongs to the PPU during the scan and the draw.
; ---------------------------------------------------------------------------
ChkOamBlock::
    call LcdOff
    ld a, $12
    ld [_OAMRAM], a
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON
    ldh [rLCDC], a
    di
    ld de, 30000
.wait
    ldh a, [rSTAT]
    and 3
    cp 2
    jr z, .inMode2
    dec de
    ld a, d
    or e
    jr nz, .wait
    ld hl, .noteNever
    jp FailNote
.inMode2
    ld a, [_OAMRAM]
    cp $FF
    jr nz, .readable
    call ClearObjects
    or a
    ret
.readable
    ld b, $FF
    call SetNums8
    call ClearObjects
    ld hl, .note
    jp FailNote
.note      db "the CPU read object memory while the PPU was scanning it. During modes 2 and 3 a read must return $FF, which is why every game copies its objects in during the blank",0
.noteNever db "STAT never reported mode 2 at all",0

; ---------------------------------------------------------------------------
; SetupObjectsN — C objects, all on the measured line and all at the same
; screen x so that they share one background tile.
; ---------------------------------------------------------------------------
SetupObjectsN:
    call ClearObjects
    ld hl, _OAMRAM
    ld b, c
.next
    ld a, MEASURE_LINE + 16
    ld [hl+], a
    ld a, 8
    ld [hl+], a
    xor a
    ld [hl+], a
    ld [hl+], a
    dec b
    jr nz, .next
    ret

ObjectsOn:
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON | LCDCF_OBJON
    ldh [rLCDC], a
    ret

; ---------------------------------------------------------------------------
; GB-PPU-12 — only ten objects are drawn on a line, however many are there.
;
; The scan of object memory keeps the first ten entries whose row covers this
; line and stops looking at the rest, so twenty objects on a line cost exactly
; what ten cost. It is a hardware limit games design around -- flickering a
; sprite on alternate frames is what a programmer does about it -- and an
; emulator without the limit draws a scene no console can show, AND charges
; the fetcher for work hardware never does.
; ---------------------------------------------------------------------------
ChkObjLimit::
    call StatWorks
    ld a, [wStatWorks]
    or a
    jr z, .noStat
    call LcdOff
    ld c, 10
    call SetupObjectsN
    call ObjectsOn
    call ArmSled
    call MeasureE3
    ld [P_E3], a
    call DisarmSled
    call LcdOff
    ld c, 40                ; every entry there is, all on the same line
    call SetupObjectsN
    call ObjectsOn
    call ArmSled
    call MeasureE3
    ld [P_SCENE], a
    call DisarmSled
    call SceneBase
    ld a, [P_E3]
    ld b, a
    ld a, [P_SCENE]
    cp b
    jr nz, .different
    or a
    ret
.different
    ld a, [P_SCENE]
    ld b, 0
    ld a, [P_E3]
    call SetNums8
    ld hl, .note
    jp FailNote
.noStat
    ld hl, .noteSkip
    jp SkipWith
.note     db "forty objects on one line cost the fetcher more than ten did. The scan keeps the first ten that cover the line and ignores the rest, so beyond ten the cost stops rising",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-13 — objects switched off in LCDC cost nothing.
;
; The enable bit is read by the scan, not merely by whatever draws the pixels.
; With it clear the scan finds nothing however full object memory is, and mode
; 3 is as short as it would be with the memory empty.
; ---------------------------------------------------------------------------
ChkObjDisabled::
    ; Measured on a Color console this comes out the other way: the scan still
    ; charges the fetcher for its ten objects with the enable bit clear, and
    ; only the drawing is suppressed. Two accurate emulators agree on the DMG
    ; rule and on there being a difference; this cartridge has one independent
    ; source for the Color rule and one is not enough to assert it, so it says
    ; so instead of guessing.
    ld a, [wConsole]
    cp CONSOLE_CGB
    jr z, .colour
    cp CONSOLE_AGB
    jr z, .colour
    call StatWorks
    ld a, [wStatWorks]
    or a
    jr z, .noStat
    call SceneBase
    call ArmSled
    call MeasureE3
    ld [P_E3], a
    call DisarmSled
    call LcdOff
    ld c, 10
    call SetupObjectsN      ; the objects are there ...
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON
    ldh [rLCDC], a          ; ... and the enable bit is not
    call ArmSled
    call MeasureE3
    ld [P_SCENE], a
    call DisarmSled
    call SceneBase
    ld a, [P_E3]
    ld b, a
    ld a, [P_SCENE]
    cp b
    jr nz, .costly
    or a
    ret
.costly
    ld a, [P_E3]
    ld b, a
    ld a, [P_SCENE]
    call SetNums8
    ld hl, .note
    jp FailNote
.colour
    ld hl, .noteColour
    jp SkipWith
.noStat
    ld hl, .noteSkip
    jp SkipWith
.noteColour db "not run on a Color console: the object scan there charges the fetcher whether or not bit 1 of LCDC is set, and this cartridge has only one independent measurement of that rule",0
.note     db "object memory full but bit 1 of LCDC clear still lengthened mode 3. The enable is read by the scan: with it clear there is nothing on the line to fetch",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-14 — with the LCD off, LY reads zero and STAT reports mode 0.
;
; Switching the LCD off stops the whole timing chain and resets it: the line
; counter reads zero and stays there, and STAT's mode bits read zero because
; there is no mode. A game that waits for a particular LY with the screen off
; waits for ever, and an emulator that keeps the counter running lets it
; through -- which hides the bug on that emulator and nowhere else.
; ---------------------------------------------------------------------------
ChkLcdOff::
    call SceneBase          ; on, so that turning it off is a transition
    call LcdOff
    ldh a, [rLY]
    or a
    jr nz, .lyRunning
    ; and it stays there rather than merely starting there
    ld a, 2
    call DelayA
    ldh a, [rLY]
    or a
    jr nz, .lyRunning
    ldh a, [rSTAT]
    and 3
    jr nz, .modeRunning
    call LcdOn
    or a
    ret
.lyRunning
    ld b, 0
    call SetNums8
    call LcdOn
    ld hl, .noteLy
    jp FailNote
.modeRunning
    ld b, 0
    call SetNums8
    call LcdOn
    ld hl, .noteMode
    jp FailNote
.noteLy   db "LY did not read zero with the LCD switched off. Clearing bit 7 of LCDC stops the timing chain and resets the line counter",0
.noteMode db "STAT's mode bits did not read zero with the LCD switched off",0

; ---------------------------------------------------------------------------
; GB-PPU-15 — the STAT interrupt is ONE line, not four separate triggers.
;
; The four selected conditions are ORed into a single signal and the interrupt
; is raised on that signal's rising edge alone. So a second condition becoming
; true while the first still holds raises nothing: the coincidence flag is
; already high for the whole of its line, and the object scan on that same line
; adds no second interrupt.
;
; This is measured DIFFERENTIALLY -- the same window counted with the
; coincidence source off and then on -- so it needs no constant at all and
; cannot be thrown off by how many lines a particular console strobes on.
; Getting it wrong makes a raster effect driven from two sources run at twice
; the rate it should, which is a real symptom in real games.
; ---------------------------------------------------------------------------
ChkStatBlocking::
    ; Both runs select BOTH conditions and differ only in whether the
    ; coincidence can ever happen: 200 is a line LY never reaches. So the two
    ; windows execute identical code and the difference between the counts is
    ; the coincidence and nothing else.
    ld c, 200
    call CountStat
    ld a, [X_CNT]
    ld [X_BASE], a
    ld a, [X_CNT + 1]
    ld [X_BASE + 1], a
    ld c, MEASURE_LINE
    call CountStat
    ld a, [X_CNT]
    ld e, a
    ld a, [X_CNT + 1]
    ld d, a
    ld a, [X_BASE]
    ld c, a
    ld a, [X_BASE + 1]
    ld b, a
    ld a, e
    sub c
    ld l, a
    ld a, d
    sbc b
    ld h, a                 ; hl = the change the coincidence made, signed

    ; The window has to have counted something, or the comparison is vacuous.
    ld a, b
    or a
    jr nz, .enough
    ld a, c
    cp 100
    jr c, .nothingHappened
.enough
    ; Adding a condition can only MERGE edges, never make new ones: the
    ; coincidence holds for the whole of its line and the object scan on that
    ; same line finds the signal already high. So the count may fall -- by one
    ; a frame, which is what hardware does -- and may not rise. An
    ; implementation that raises an interrupt per source instead of per edge
    ; gains one a frame, and that is the failure this catches.
    ld a, h
    or a
    jr nz, .fell           ; negative, so fewer: the edges merged
    ld a, l
    or a
    jr z, .same
    ld d, h
    ld e, l
    ld hl, 0
    call SetNums16
    ld hl, .note
    jp FailNote
.fell
.same
    or a
    ret
.nothingHappened
    ld d, b
    ld e, c
    ld hl, 100
    call SetNums16
    ld hl, .noteNone
    jp FailNote
.noteNone db "the window counted almost no STAT interrupts at all, so there was nothing to compare. With the object-scan condition selected one is raised at the start of every line",0
.note db "selecting a second STAT condition produced MORE interrupts. The conditions are ORed into one signal and only its rising edge raises anything, so a condition that becomes true while another already holds is invisible",0

; CountStat — C = the line to put LYC on; counts STAT interrupts into X_CNT
; over a window delimited BY THE TIMER.
;
; The window cannot be delimited by watching LY: the handler runs at the start
; of every line, so the moment LY reads zero can be inside a handler and the
; window can come out a whole frame long or short -- which is 144 interrupts of
; error either way. The timer keeps counting through the handler, so a window
; ending at a fixed TIMA is the same length in both runs to within one turn of
; a polling loop.
CountStat:
    push bc
    di
    ld hl, wHookStat
    ld a, LOW(StatCountIsr)
    ld [hl+], a
    ld a, HIGH(StatCountIsr)
    ld [hl], a
    call SceneBase
    pop bc
    ld a, c
    ldh [rLYC], a
    ld a, STATF_MODE10 | STATF_LYC
    ldh [rSTAT], a
    ld a, IEF_STAT
    ldh [rIE], a
    call SyncToLineZero
    di
    xor a
    ldh [rTAC], a
    ldh [rTIMA], a
    ldh [rTMA], a
    ld [X_CNT], a
    ld [X_CNT + 1], a
    ldh [rIF], a
    ld a, TACF_START | TACF_1024T
    ldh [rTAC], a
    xor a
    ldh [rDIV], a
    ei
.window
    ldh a, [rTIMA]
    cp 200                  ; 200 * 1024 cycles, which is about three frames
    jr c, .window
    di
    xor a
    ldh [rTAC], a
    ldh [rIE], a
    ldh [rIF], a
    ldh [rSTAT], a
    ld hl, wHookStat
    ld a, LOW(DefaultIsr)
    ld [hl+], a
    ld a, HIGH(DefaultIsr)
    ld [hl], a
    ret

StatCountIsr:
    push af
    push hl
    ld hl, X_CNT
    call IncWord
    pop hl
    pop af
    pop hl
    reti
