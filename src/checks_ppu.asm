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
; GB-PPU-07 — fine scrolling costs the fetcher time, and twice as much once
; double speed halves how wide a machine cycle is.
;
; The original measurement is unchanged: an SCX of 4 must make mode 3 four
; dots -- one machine cycle -- longer. On Color hardware, once that passes,
; the identical four-dot penalty is measured again after switching to double
; speed (Pan Docs, "KEY1 Register": the CPU and the timer double, the LCD does
; not), where a machine cycle is only two dots wide -- so the same penalty
; must now cost two machine cycles. An emulator that scales the PPU's own
; clock with the CPU's would still show one; that is the closest a cartridge
; with no framebuffer gets to the class of bug behind this suite. It is not
; the bug itself -- see docs/double-speed.md for the one this cannot see and
; why.
; ---------------------------------------------------------------------------

; MeasureScxDelta -- the extra machine cycles an SCX of 4 costs mode 3, at
; whatever speed the CPU is currently running. Leaves SCX at zero.
MeasureScxDelta:
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
    ld hl, P_E3
    ld a, b
    sub [hl]                ; the extra machine cycles, so four dots each
    ret

ChkMode3Scx::
    call StatWorks
    ld a, [wStatWorks]
    or a
    jr z, .noStat
    call MeasureScxDelta
    ld b, 1
    ld c, 0
    call Within
    jr c, .bad
    ld a, [wConsole]
    and 2                   ; set only for CONSOLE_CGB (2) and CONSOLE_AGB (3);
    ret z                   ; AND already cleared carry, so this is a clean pass
.double
    call FlipSpeed
    call MeasureScxDelta
    ld b, a                 ; FlipSpeed below clobbers A; keep the delta safe
    call FlipSpeed
    ld a, b
    ld b, 2
    ld c, 0
    call Within
    ret nc
    call SetNums8
    ld hl, .noteDouble
    jp FailNote
.bad
    call SetNums8
    ld hl, .note
    jp FailNote
.noStat
    ld hl, .noteSkip
    jp SkipWith
.note       db "an SCX of 4 must make mode 3 four cycles longer: the first four pixels of the leftmost tile are fetched and thrown away. A mode 3 of fixed length cannot show this",0
.noteSkip   db "not run: the coincidence interrupt never fired",0
.noteDouble db "one cycle in double speed, not two: a cycle is half as wide",0

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

; ---------------------------------------------------------------------------
; GB-PPU-16 — writing STAT on a Game Boy raises a spurious interrupt.
;
; A defect in the original silicon: a write to STAT while the screen is on
; behaves for one cycle as though every condition had been selected, so if any
; of them is true at that moment the interrupt is raised -- even when the value
; written selects nothing at all.
;
; It is not a curiosity. Road Rash and Legend of Zelda: Oracle of Ages are the
; games usually named for depending on it, and an emulator without it runs them
; differently. It was fixed on the Color console, so this is asked only of a
; machine that should have it.
;
; Source: Pan Docs, "Spurious STAT interrupts"; the Mooneye suite tests it.
; ---------------------------------------------------------------------------
ChkStatWriteBug::
    ld a, [wConsole]
    cp CONSOLE_CGB
    jr z, .colour
    cp CONSOLE_AGB
    jr z, .colour
    call SceneBase
    di
    xor a
    ldh [rSTAT], a          ; nothing selected, so nothing should fire
    ld a, 200
    ldh [rLYC], a           ; a line LY never reaches, so it is not that
.toVBlank
    ldh a, [rLY]
    cp 145
    jr nz, .toVBlank
    xor a
    ldh [rIF], a
    ldh [rSTAT], a          ; write zero: still acts as though $FF for a cycle
    ldh a, [rIF]
    ld b, a
    xor a
    ldh [rIF], a
    ldh [rLYC], a
    ld a, b
    and IEF_STAT
    ret nz
    ld b, IEF_STAT
    ld a, b
    xor a
    call SetNums8
    ld hl, .note
    jp FailNote
.colour
    ld hl, .noteSkip
    jp SkipWith
.note     db "writing STAT with no condition selected did not raise the interrupt. On this machine the write acts for one cycle as though every condition were selected, and games depend on it",0
.noteSkip db "not run: this defect is in the original silicon only and was fixed on the Color console",0

; ---------------------------------------------------------------------------
; GB-PPU-17 — a window past the right-hand edge costs nothing.
;
; The window only ever costs the fetcher time if it actually starts on the
; line. Enabled but placed beyond the last pixel, it never takes over, and mode
; 3 is as short as with the window switched off. An implementation that charges
; for the enable bit rather than for the takeover pays for a window nobody can
; see.
; ---------------------------------------------------------------------------
ChkWindowOffScreen::
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
    ld a, 167               ; one past the rightmost position that can appear
    ldh [rWX], a
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON | LCDCF_WINON
    ldh [rLCDC], a
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
.noStat
    ld hl, .noteSkip
    jp SkipWith
.note     db "the window was enabled beyond the right-hand edge and still lengthened mode 3. The cost is the takeover, not the enable bit, and a window at WX 167 never takes over",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-18 — an object at x = 0 draws nothing and costs the same anyway.
;
; An object is placed by the coordinate of its right-hand edge minus eight, so
; one at zero is entirely off the left of the screen. The scan still finds it,
; the fetcher still fetches its row, and mode 3 still grows. Skipping the work
; because nothing will be visible is a plausible optimisation and it is wrong;
; the Mooneye suite's object-timing table begins with exactly these rows.
; ---------------------------------------------------------------------------
ChkObjOffLeft::
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
    call ClearObjects
    ld hl, _OAMRAM
    ld b, 10
.place
    ld a, MEASURE_LINE + 16
    ld [hl+], a
    xor a
    ld [hl+], a             ; x = 0: entirely off the left edge
    ld [hl+], a
    ld [hl+], a
    dec b
    jr nz, .place
    call ObjectsOn
    call ArmSled
    call MeasureE3
    ld [P_SCENE], a
    call DisarmSled
    call SceneBase
    ld a, [P_E3]
    ld c, a
    ld a, [P_SCENE]
    sub c
    jr c, .free
    cp 12                   ; ten objects at six cycles each is fifteen; this
    jr c, .free             ; only asks that most of it was charged
    or a
    ret
.free
    ld b, 12
    call SetNums8
    ld hl, .note
    jp FailNote
.noStat
    ld hl, .noteSkip
    jp SkipWith
.note     db "ten objects placed entirely off the left of the screen cost the fetcher nothing. They are still found by the scan and their rows are still fetched; only the drawing is thrown away",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-19 — vertical scrolling costs the fetcher nothing.
;
; The negative control for GB-PPU-07. SCX delays the first pixel because the
; leftmost tile has to be fetched and part of it thrown away; SCY only chooses
; which ROW of the tile is fetched, and a row costs what a row costs. An
; implementation that charges for "the background is scrolled" rather than for
; the pixels actually discarded fails this while passing GB-PPU-07, which is
; exactly the confusion worth catching.
; ---------------------------------------------------------------------------
ChkMode3Scy::
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
    ld a, 5                 ; any offset that is not a whole tile
    ldh [rSCY], a
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
.noStat
    ld hl, .noteSkip
    jp SkipWith
.note     db "an SCY that is not a multiple of eight lengthened mode 3. Only SCX can: it discards pixels the fetcher has already fetched, whereas SCY only picks which row of the tile is read, and every row costs the same",0
.noteSkip db "not run: the coincidence interrupt never fired",0

; ---------------------------------------------------------------------------
; GB-PPU-20 — a write into video RAM while the fetcher owns it is dropped.
;
; GB-PPU-10 already asks the read half of this: during mode 3 the CPU reads
; $FF out of video RAM because the fetcher has the bus. The write half is a
; separate implementation and a separate bug, and it is the one that changes
; what a player sees: a write that hardware discards but an emulator honours
; puts tile data or a map entry on the screen mid-frame that no real console
; ever shows. An emulator can easily block one and not the other -- reads and
; writes are different functions -- so the two are asked separately.
;
; The measurement waits for mode 2 first and only then for mode 3, so the write
; lands within a few machine cycles of the START of mode 3 and cannot fall out
; of the far end of a short one. Mode 3 is at least 172 dots, which is forty
; machine cycles of room.
;
; The byte is read back with the screen off, where nothing can refuse it.
;
; Source: Pan Docs, "Accessing VRAM and OAM"; TerminalGB
; docs/conformance-notes.md, 2026-08-15, "VRAM/OAM access blocking" §1 -- "a
; program that deliberately writes into the blocked window to prove it is
; blocked reads its own value back instead of $FF".
; ---------------------------------------------------------------------------
DEF BLOCKED_PROBE EQU _VRAM + $20 * 16      ; the blank glyph's first byte
DEF BLOCKED_MARK  EQU $5A

ChkVramWriteBlock::
    call LcdOff
    xor a
    ld [BLOCKED_PROBE], a           ; a known byte, written where it is allowed
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON
    ldh [rLCDC], a
    di
    ld hl, BLOCKED_PROBE
    ld b, BLOCKED_MARK
    call EnterMode3
    jr c, .never
    ld [hl], b                      ; the write under test
    call LcdOff
    ld a, [BLOCKED_PROBE]
    or a
    jr nz, .landed
    ret                             ; carry is already clear
.landed
    ld b, 0
    call SetNums8
    ld hl, .note
    jp FailNote
.never
    ld hl, .noteNever
    jp FailNote
.note      db "a byte written into video RAM during mode 3 was still there afterwards. The fetcher owns that bus while it is drawing and a write there never reaches the memory, which is what lets a game write blindly and only lose the writes it placed badly",0
.noteNever db "STAT never reported mode 2 followed by mode 3 at all",0

; ---------------------------------------------------------------------------
; GB-PPU-21 — a write into object memory while the PPU is scanning it is
; dropped.
;
; The same question of the other bus, and the one games lean on hardest: every
; object update in every game is placed in the blank because the PPU refuses it
; anywhere else.
;
; The byte written is object 0's Y coordinate. Object 0 is in the first of the
; twenty rows the scan walks, and that row is the one row the Game Boy's own
; object-memory corruption defect can never reach -- it has no row above it to
; be copied from -- so this check reads back exactly what it wrote or exactly
; what was there before, and never a third thing. GB-PPU-22 is where that
; defect is asked about on purpose.
;
; Source: Pan Docs, "Accessing VRAM and OAM"; TerminalGB
; docs/conformance-notes.md, 2026-08-15, "VRAM/OAM access blocking" §1.
; ---------------------------------------------------------------------------
ChkOamWriteBlock::
    call LcdOff
    call ClearObjects
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON
    ldh [rLCDC], a
    di
    ld hl, _OAMRAM
    ld b, BLOCKED_MARK
    call EnterMode2
    jr c, .never
    ld [hl], b                      ; the write under test
    call LcdOff
    ld a, [_OAMRAM]
    or a
    jr nz, .landed
    call ClearObjects
    ret
.landed
    ld b, 0
    call SetNums8
    call ClearObjects
    ld hl, .note
    jp FailNote
.never
    call ClearObjects
    ld hl, .noteNever
    jp FailNote
.note      db "a byte written into object memory during the object scan was still there afterwards. The PPU owns that bus through modes 2 and 3, which is why every game copies its objects in during the blank instead",0
.noteNever db "STAT never reported mode 0 followed by mode 2 at all",0

; ---------------------------------------------------------------------------
; EnterMode2 / EnterMode3 — stop a few machine cycles into the named mode, having
; seen the mode before it. Waiting for the mode alone is not enough: the poll
; loop is five machine cycles, so it can catch a mode in its last twenty dots
; and hand back a window that has already closed. Seeing the previous mode
; first pins the answer to the near end of the one that is wanted.
;
; Carry set means the sequence never appeared and nothing was measured.
; ---------------------------------------------------------------------------
EnterMode3:
    ld c, 2
    call EnterMode
    ret c
    ld c, 3
    jr EnterMode

EnterMode2:
    ld c, 0
    call EnterMode
    ret c
    ld c, 2
    ; falls through

; EnterMode — C = the mode to stop on. Preserves HL and B.
EnterMode:
    push de
    ld de, 30000
.wait
    ldh a, [rSTAT]
    and 3
    cp c
    jr z, .there
    dec de
    ld a, d
    or e
    jr nz, .wait
    pop de
    scf
    ret
.there
    pop de
    or a
    ret

; ---------------------------------------------------------------------------
; GB-PPU-22 — the object-memory corruption defect, and the two machines that
; disagree about it.
;
; A fault in the original silicon, and one of the few places where conformance
; means reproducing damage rather than avoiding it. The processor's sixteen-bit
; increment unit is wired straight to the address bus and asserts its operand
; as an address whether or not any read or write is behind it. So while the PPU
; is walking object memory -- mode 2, the first eighty dots of every visible
; line -- an `inc de` whose DE happens to hold a value in $FE00-$FEFF reaches
; the same bus the scan is using, and a whole eight-byte row is copied from its
; neighbour with one word mangled.
;
; It matters twice over. A game that trips it on hardware and not on an
; emulator shows garbled sprites the emulator draws cleanly, which is a bug
; report nobody can reproduce; and the Color console FIXED it, so an emulator
; that models the defect unconditionally is emulating a machine that has never
; existed. Both directions are asserted here, which is why this check reads the
; console first and why it is a real check on a Color machine rather than a
; skip: "nothing was corrupted" is the answer, not the absence of one.
;
; What is NOT asked is which row was corrupted or how. That is a function of
; the exact dot the offending cycle landed on, and the suites that pin it --
; Blargg's `oam_bug`, sub-tests 4, 7 and 8 -- do it far better than a
; first-response cartridge should try to. This asks only the question those
; suites call `2-causes`: does the address bus reach the scan at all.
;
; Row 0 is deliberately not exempted from the comparison even though the
; hardware never corrupts it -- it has no row above it to be copied from -- and
; that costs nothing: any of the other nineteen changing is enough.
;
; Source: Pan Docs, "OAM Corruption Bug"; TerminalGB
; docs/conformance-notes.md, 2026-08-14, "the DMG OAM-corruption bug: a defect
; that had to be *added*", and docs/measured/ppu.md, which records that Pan
; Docs is explicit the Color and Advance consoles are unaffected "even running
; monochrome software".
; ---------------------------------------------------------------------------
DEF OAMBUG_ROUNDS EQU 4

ChkOamBug::
    ld a, [wConsole]
    cp CONSOLE_DMG
    jr z, .mono
    cp CONSOLE_MGB
    jr z, .mono
    cp CONSOLE_CGB
    jr z, .colour
    cp CONSOLE_AGB
    jr z, .colour
    ld hl, .noteUnknown
    jp SkipWith

.mono
    call OamBugRun
    or a
    jr z, .noneMono
    call ClearObjects
    or a
    ret
.colour
    call OamBugRun
    or a
    jr nz, .someColour
    call ClearObjects
    or a
    ret

.noneMono
    ld b, 1                 ; got none, wanted at least one
    call SetNums8
    call ClearObjects
    ld hl, .noteMono
    jp FailNote
.someColour
    ld b, 0
    call SetNums8
    call ClearObjects
    ld hl, .noteColour
    jp FailNote
.noteMono   db "not one byte of object memory changed. On this console the increment unit's operand reaches the bus the object scan is using, and a sixteen-bit increment through $FE00-$FEFF during mode 2 corrupts a row of it. Hooking the read and the write paths and stopping there is the usual way to miss this: no read and no write is involved",0
.noteColour db "object memory was corrupted. The increment unit's reach into the object scan is a defect of the original silicon and the Color console does not have it, even running monochrome software, so a machine identifying itself as a Color one must come through this untouched",0
.noteUnknown db "the console could not be identified, and this defect exists on some of them and not others",0

; ---------------------------------------------------------------------------
; OamBugRun — fill object memory with a pattern no two neighbouring bytes
; share, run a burst of sixteen-bit increments through the object-memory
; address range with the screen on, and return A = how many of the 160 bytes
; came back different.
;
; The burst is a loop rather than a straight run of instructions because it has
; to cover whole scanlines: the scan is eighty dots of every 456, so the only
; way to be sure of meeting it is to keep going for longer than a line. Four
; rounds of 256 iterations is a little over a hundred lines, which meets the
; scan a hundred times. Nothing here needs to know WHEN it met it.
; ---------------------------------------------------------------------------
OamBugRun:
    call LcdOff
    ld hl, _OAMRAM
    ld c, 160
    ld b, 1
.fill
    ld a, b
    ld [hl+], a
    inc b
    dec c
    jr nz, .fill

    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON
    ldh [rLCDC], a
    di
    ld c, OAMBUG_ROUNDS
.round
    ld de, _OAMRAM
    ld b, 0
.burst
    inc de                  ; each of these asserts an address in $FE00-$FEFF
    dec de                  ; and none of them reads or writes anything
    inc de
    dec de
    dec b
    jr nz, .burst
    dec c
    jr nz, .round

    call LcdOff
    ld hl, _OAMRAM
    ld c, 160
    ld d, 1
    ld e, 0
.count
    ld a, [hl+]
    cp d
    jr z, .same
    inc e
.same
    inc d
    dec c
    jr nz, .count
    ld a, e
    ret

; ---------------------------------------------------------------------------
; GB-DMA-06 — an object transfer takes the object scan's bus away.
;
; The transfer controller has no address bus of its own either. GB-DMA-04
; shows the DATA lines are shared with whatever else is on that bus; the
; ADDRESS lines are shared too, and object memory is where that shows. While a
; transfer runs the controller drives the object-memory address lines, and the
; PPU is on the other end of them: for the eighty dots of the scan it cannot
; read a single entry. Its Y and X latch keeps whatever it last held, and all
; forty slots are judged against that one stale pair.
;
; A cartridge cannot see which objects were found. What it CAN see is how long
; mode 3 took, and ten objects on a line cost the fetcher at least sixty dots
; — GB-PPU-08 measures exactly that. So: leave object memory empty, put the
; visible objects in the transfer's SOURCE, and start the transfer so that it
; covers the measured line's scan. A machine whose scan reads object memory
; straight through the transfer finds the ten the transfer has already written
; and is still drawing; hardware finds none and is in horizontal blank.
;
; Object memory is left entirely empty on purpose, and that is what makes the
; stale latch harmless: whatever slot the scan last managed to read, it read a
; zero, so the frozen Y puts the phantom object above the screen. A check that
; pre-loaded the objects would depend on where the freeze landed.
;
; The transfer is sourced from VIDEO memory, and that is not decoration. The
; delay loop and the interrupt handler run from the cartridge, and on a
; monochrome console work memory is on the cartridge's own bus — a transfer out
; of it would feed the processor its own bytes instead of instructions, which
; is why every game's transfer routine lives in high RAM. Video memory has a
; bus of its own on every console, so no high-RAM routine is needed here.
;
; The processor is deliberately NOT halted while the transfer runs: whether a
; halted transfer advances at all is its own question (Gambatte has ROMs for
; it) and this check must not depend on the answer.
; ---------------------------------------------------------------------------
DEF DMA_SCAN_SRC    EQU $9F     ; the tail of the second map: never tile data,
                                ; and no scene here selects that map
DEF DMA_SCAN_MARGIN EQU 6       ; machine cycles past the empty-line edge

ChkDmaScan::
    call StatWorks
    ld a, [wStatWorks]
    or a
    jp z, .noStat

    ; where mode 3 ends with nothing on the line at all
    call SceneBase
    call ArmSled
    call MeasureE3
    ld [P_E3], a
    call DisarmSled

    ; and where it ends with ten objects genuinely in object memory. If this
    ; machine charges nothing for an object at all -- GB-PPU-08 is the check
    ; for that -- then the probe below cannot tell the two answers apart and a
    ; pass here would mean nothing. Say so rather than claim one.
    call LcdOff
    call SetupObjects
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON | LCDCF_OBJON
    ldh [rLCDC], a
    call ArmSled
    call MeasureE3
    ld [P_SCENE], a
    call DisarmSled
    ld a, [P_E3]
    ld b, a
    ld a, [P_SCENE]
    sub b
    jr c, .noPenalty
    cp DMA_SCAN_MARGIN + 2
    jr c, .noPenalty

    ; a page whose every byte is "an object on the measured line": Y and X both
    ; become MEASURE_LINE + 16, which is on the line and on the screen. Object
    ; memory is emptied again, so the ten the scan may find are the transfer's.
    call LcdOff
    call ClearObjects
    ld hl, DMA_SCAN_SRC << 8
    ld c, 160
    ld a, MEASURE_LINE + 16
.fill
    ld [hl+], a
    dec c
    jr nz, .fill
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON | LCDCF_OBJON
    ldh [rLCDC], a
    call ArmSled

    ld a, [P_E3]
    add DMA_SCAN_MARGIN
    call ProbeDmaScan
    ld [P_SCENE], a
    call DisarmSled
    call SceneBase
    ld a, [P_SCENE]
    cp 3
    jr z, .stillDrawing
    or a
    ret
.stillDrawing
    ld b, 0                 ; got mode 3, wanted mode 0
    call SetNums8
    ld hl, .noteDrawing
    jp FailNote
.noPenalty
    ; the report carries what an object was worth here, because that number
    ; is the reason the check could not run
    ld b, DMA_SCAN_MARGIN + 2
    call SetNums8
    ld hl, .notePenalty
    jp SkipWith
.noStat
    ld hl, .noteSkip
    jp SkipWith
.notePenalty db "not run: an object on the line did not lengthen mode 3 on this machine, so nothing here could tell whether the scan found the transfer's objects or not. GB-PPU-08 is the check that says so",0
.noteDrawing db "mode 3 was still running past the point it ends on an empty line, so the ten objects the transfer had just written into object memory were found. The scan cannot read object memory while a transfer is running: the controller is driving those address lines and the PPU is on the other end of them",0
.noteSkip    db "not run: the coincidence interrupt never fired",0

; ProbeDmaScan — one sled probe at delay A, with an object transfer covering
; the measured line's scan.
;
; The transfer is started early in the line BEFORE the measured one. It moves a
; byte every machine cycle for 160 of them, which is more than a line and a
; third, so it is running for the whole of the measured line's scan whatever
; part of the previous line it began in.
;
; The wait is a spin rather than a halt for the reason in the header above. It
; costs a couple of machine cycles of jitter against the halt the baseline was
; measured with, which is an eighth of the margin either side.
ProbeDmaScan:
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
    ; catch the start of the line before the measured one, so the transfer
    ; begins at a known place rather than wherever the last check left us
    ld b, MEASURE_LINE - 2
    call WaitLine
    ld b, MEASURE_LINE - 1
    call WaitLine
    xor a
    ldh [rIF], a
    ei
    ld a, DMA_SCAN_SRC
    ldh [rDMA], a
.wait
    ld a, [P_TMP]
    inc a                   ; $FF, the "nothing yet" value, becomes zero
    jr z, .wait
    di
    ld hl, wFrames
    call IncWord
    ld a, [P_TMP]
    ret

; WaitLine — spin until LY reads B, having first seen it read something else,
; so the caller lands at the top of that line rather than part-way down one it
; was already on.
WaitLine:
    ldh a, [rLY]
    cp b
    jr z, WaitLine
.arrive
    ldh a, [rLY]
    cp b
    jr nz, .arrive
    ret

; ---------------------------------------------------------------------------
; GB-PPU-23 -- tile id $19 is unsigned-addressed to $8190, sixteen bytes past
; tile $18 and sixteen before tile $1A.
;
; Every one of the nine Mealybug rows this cartridge's boot-VRAM checks are
; aimed at identifies a tile by NUMBER -- an OAM entry naming tile $19, a BG
; tilemap byte of $19 under unsigned ($8000) addressing -- and depends on
; nothing but this arithmetic to turn that number into an address. This
; proves the arithmetic and the independence of neighbouring tiles with a
; pattern this cartridge draws itself; it asserts nothing about what
; boot-ROM-supplied content, if any, a real console leaves at $8190 before
; this cartridge's own code runs -- that is a different question, answered
; separately (and only where it CAN be, from the cartridge's own header) by
; GB-BOOT-07. See TerminalGB docs/mealybug.md Sec 8.6 for why the two are kept
; apart.
; ---------------------------------------------------------------------------
ChkTileAddressing::
    call LcdOff
    ld hl, $8180            ; tile $18
    ld b, $88
    call FillTile16
    ld hl, $8190            ; tile $19
    ld b, $99
    call FillTile16
    ld hl, $81A0            ; tile $1A
    ld b, $AA
    call FillTile16

    ld a, [$8180]
    cp $88
    jr nz, .bad18
    ld a, [$818F]           ; tile $18's last byte -- not only its first
    cp $88
    jr nz, .bad18
    ld a, [$8190]
    cp $99
    jr nz, .bad19
    ld a, [$819F]
    cp $99
    jr nz, .bad19
    ld a, [$81A0]
    cp $AA
    jr nz, .bad1a
    or a
    ret
.bad18
    ld b, $88
    call SetNums8
    ld hl, .note
    jp FailNote
.bad19
    ld b, $99
    call SetNums8
    ld hl, .note
    jp FailNote
.bad1a
    ld b, $AA
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "tile id $19 did not read back as sixteen bytes of its own, sitting exactly between tiles $18 and $1A. Unsigned tile addressing is $8000 + 16*id; get the base or the stride wrong and $19 is not the address a tile of that number claims to be",0

; FillTile16 -- HL = tile address, B = the byte to fill all sixteen bytes
; with. Trashes A, C.
FillTile16:
    ld c, 16
.next
    ld a, b
    ld [hl+], a
    dec c
    jr nz, .next
    ret
