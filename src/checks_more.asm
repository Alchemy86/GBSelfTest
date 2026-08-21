; checks_more.asm — the checks that separate a careful emulator from a rough
; one most cheaply.
;
; Every one of these is a behaviour that a from-scratch implementation will not
; have unless somebody knew to put it there, and that is observable from inside
; the machine with nothing but a register read or a cycle count. That is the
; property this cartridge exists to have: a suite everybody passes measures
; nothing.

INCLUDE "hardware.inc"

; Sections here are split by AREA, not by subject: the dispatcher maps the
; bank an area declares and leaves it mapped while the failure is reported, so
; a check and the prose explaining it have to be in the bank its area names.
SECTION "MoreTimer", ROMX, BANK[2]

DEF X_CNT  EQU wScratch + 82    ; two bytes: interrupts counted in a window
DEF X_TMP  EQU wScratch + 84
DEF X_BASE EQU wScratch + 85

; ---------------------------------------------------------------------------
; GB-TIM-06 — writing the divider can itself make the timer tick.
;
; The timer does not have a counter of its own: it watches one bit of the same
; sixteen-bit counter the divider is the top of, and it increments on that
; bit's FALLING edge. Writing the divider clears the whole counter, so if the
; watched bit happened to be set, clearing it is a falling edge and TIMA
; increments there and then.
;
; That is a real hazard and games hit it: a routine that resets the divider in
; a loop can drive the timer at a rate nothing in TAC selects. An emulator that
; models the timer as its own countdown will not reproduce it.
;
; Source: Pan Docs, "Timer Obscure Behaviour"; the Mooneye suite's div_write.
; ---------------------------------------------------------------------------
ChkDivGlitch::
    di
    ; TAC's slowest rate watches bit 9 of the counter, which is bit 1 of DIV
    ld a, TACF_START | TACF_1024T
    ldh [rTAC], a
    xor a
    ldh [rTMA], a

    ; first the control: write the divider while the watched bit is CLEAR
    ldh [rDIV], a
.waitClear
    ldh a, [rDIV]
    and $02
    jr nz, .waitClear
    xor a
    ldh [rTIMA], a
    ldh [rDIV], a
    ldh a, [rTIMA]
    or a
    jr nz, .tickedWhenClear

    ; now the case that matters: the watched bit is SET when the write lands
    xor a
    ldh [rDIV], a
.waitSet
    ldh a, [rDIV]
    and $02
    jr z, .waitSet
    xor a
    ldh [rTIMA], a
    ldh [rDIV], a
    ldh a, [rTIMA]
    ld b, a
    xor a
    ldh [rTAC], a
    ld a, b
    or a
    ret nz                  ; it ticked, which is what hardware does
    ld b, 1
    call SetNums8
    ld hl, .noteMissing
    jp FailNote
.tickedWhenClear
    ld b, 0
    call SetNums8
    xor a
    ldh [rTAC], a
    ld hl, .noteSpurious
    jp FailNote
.noteMissing  db "clearing the divider while the timer's watched bit was set did not increment TIMA. The timer counts falling edges of one bit of the divider's own counter, and a write that clears that bit IS a falling edge",0
.noteSpurious db "TIMA incremented when the divider was written while the watched bit was already clear. Only a one-to-zero transition may count",0

SECTION "MoreInt", ROMX, BANK[2]

; ---------------------------------------------------------------------------
; GB-INT-08 — IE is a whole eight-bit register, and IF is not.
;
; Only five interrupts exist, but the enable register stores all eight bits and
; gives them back; the flag register's top three are not implemented and read
; as ones. The two are asymmetric and that asymmetry is documented, tested by
; the Mooneye suite, and got wrong by implementations that mask both the same.
; ---------------------------------------------------------------------------
ChkIeBits::
    di
    ldh a, [rIE]
    ld c, a                 ; give it back afterwards
    ld a, $FF
    ldh [rIE], a
    ldh a, [rIE]
    cp $FF
    jr nz, .bad
    xor a
    ldh [rIE], a
    ldh a, [rIE]
    or a
    jr nz, .bad2
    ld a, $E0
    ldh [rIE], a
    ldh a, [rIE]
    cp $E0
    jr nz, .bad3
    ld a, c
    ldh [rIE], a
    or a
    ret
.bad
    ld b, $FF
    jr .report
.bad2
    ld b, $00
    jr .report
.bad3
    ld b, $E0
.report
    call SetNums8
    ld a, c
    ldh [rIE], a
    ld hl, .note
    jp FailNote
.note db "the interrupt enable register did not read back what was written. Unlike IF, all eight bits of IE are real storage: the top three enable nothing but they are readable and writable, and software uses them as spare bytes",0

; ---------------------------------------------------------------------------
; GB-INT-09 — RETI enables interrupts, and does it without the delay EI has.
; ---------------------------------------------------------------------------
ChkReti::
    call InstallReti
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    xor a
    ld [X_TMP], a
    ld a, IEF_TIMER
    ldh [rIF], a            ; raise it, or there is nothing to service
    ei
    nop
    ; the handler below returns with RETI, so the master enable is on again;
    ; raising the flag once more must be serviced with no further EI
    ld a, IEF_TIMER
    ldh [rIF], a
    nop
    nop
    di
    ld a, [X_TMP]
    cp 2
    jr nz, .bad
    call ClearReti
    or a
    ret
.bad
    ld b, 2
    call SetNums8
    call ClearReti
    ld hl, .note
    jp FailNote
.note db "an interrupt raised inside a handler that returned with RETI was not serviced. RETI restores the master enable as it returns, with none of the one-instruction delay EI has",0

RetiIsr:
    push af
    ld a, [X_TMP]
    inc a
    ld [X_TMP], a
    pop af
    pop hl
    reti

InstallReti:
    ld hl, wHookTimer
    ld a, LOW(RetiIsr)
    ld [hl+], a
    ld a, HIGH(RetiIsr)
    ld [hl], a
    ret

ClearReti:
    di
    xor a
    ldh [rIE], a
    ldh [rIF], a
    ld hl, wHookTimer
    ld a, LOW(DefaultIsr)
    ld [hl+], a
    ld a, HIGH(DefaultIsr)
    ld [hl], a
    ret

SECTION "MoreApu", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; GB-APU-05 — a channel whose converter is off cannot be switched on.
;
; The top five bits of NRx2 drive the channel's digital-to-analogue converter.
; With all five clear the converter is off, and a channel whose converter is
; off is off: triggering it does not set its bit in NR52, and switching the
; converter off while it plays clears that bit at once. Emulators that treat
; the trigger bit as the only switch report channels that cannot be heard.
; ---------------------------------------------------------------------------
ChkApuDac::
    ld a, $80
    ldh [rNR52], a          ; power on
    xor a
    ldh [rNR22], a          ; channel 2's converter off
    ld a, $80
    ldh [rNR24], a          ; trigger it anyway
    ldh a, [rNR52]
    and $02
    jr nz, .cameOnAnyway
    ; now with the converter on it must come on
    ld a, $F0
    ldh [rNR22], a
    ld a, $80
    ldh [rNR24], a
    ldh a, [rNR52]
    and $02
    jr z, .didNotComeOn
    ; and switching the converter off must switch the channel off with it
    xor a
    ldh [rNR22], a
    ldh a, [rNR52]
    and $02
    jr nz, .stayedOn
    or a
    ret
.cameOnAnyway
    ld hl, .n1
    jp FailNote
.didNotComeOn
    ld hl, .n2
    jp FailNote
.stayedOn
    ld hl, .n3
    jp FailNote
.n1 db "a channel with its converter off reported itself playing. The trigger bit does not switch a channel on by itself: with the top five bits of NRx2 clear there is nothing for it to drive",0
.n2 db "a channel with its converter on and freshly triggered did not report itself playing",0
.n3 db "clearing the top five bits of NRx2 while the channel played did not switch it off. Turning the converter off disables the channel immediately, and it is how a driver silences one",0

SECTION "MoreMbc", ROM0

; ---------------------------------------------------------------------------
; GB-MBC-04 — the bank number is masked to the banks that exist.
;
; The mapper latches five bits and the cartridge wires up as many of them as it
; has banks for; the rest are not connected to anything. So a bank number
; larger than the cartridge wraps rather than reading open bus, and a game with
; a bug in its bank arithmetic still runs.
; ---------------------------------------------------------------------------
ChkMbcMask::
    ld a, ROM_BANKS + 1     ; one past the end, which must wrap to bank 1
    ld [$2000], a
    ld a, [$4000]
    ld b, 1
    cp b
    jr nz, .bad
    ld a, ROM_BANKS + 2     ; and two past, which must wrap to bank 2
    ld [$2000], a
    ld b, 2
    ld a, [$4000]
    cp b
    jr nz, .bad
    ld a, 1
    ld [$2000], a
    or a
    ret
.bad
    call SetNums8
    ld a, 1
    ld [$2000], a
    ld hl, .note
    jp FailNote
.note db "a bank number larger than the cartridge did not wrap. The mapper's register is five bits wide and only as many of them are connected as the cartridge has banks, so the number is taken modulo the bank count",0

SECTION "MoreSer", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; GB-SER-04 — with the external clock selected, nothing happens on its own.
;
; Bit 0 of SC chooses which console drives the shift clock. Clear it and this
; console is waiting to be clocked by the other one; with nothing plugged in,
; no clock ever arrives, the transfer never completes and bit 7 stays set for
; ever. An emulator that finishes the transfer anyway will hand a game an
; answer from a partner that is not there.
; ---------------------------------------------------------------------------
ChkSerExternal::
    di
    xor a
    ldh [rIF], a
    ld a, $2E
    ldh [rSB], a
    ld a, SCF_START         ; start, but with the EXTERNAL clock
    ldh [rSC], a
    ld de, 8000
.wait
    dec de
    ld a, d
    or e
    jr nz, .wait
    ldh a, [rSC]
    ld b, a
    ; give the port back before judging, whatever the answer
    xor a
    ldh [rSC], a
    ldh [rIF], a
    bit 7, b
    ret nz                  ; still pending, which is right
    ld a, b
    ld b, $80
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "a transfer with the external clock selected completed on its own. That transfer is driven by the OTHER console; with nothing attached it never finishes, and bit 7 of SC stays set until something clears it",0

SECTION "MoreBoot", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; GB-BOOT-05 — the boot ROM leaves its own vertical blank pending.
;
; The last thing the boot ROM does is wait for the screen, so the flag for that
; interrupt is still standing when the cartridge starts. Games have shipped
; assuming it: one that enables interrupts early takes a vertical blank
; immediately rather than up to a frame later.
; ---------------------------------------------------------------------------
ChkBootIf::
    ld a, [wBootIF]
    ld b, a
    and IEF_VBLANK
    jr z, .noVblank
    ld a, b
    and $E0
    cp $E0
    jr nz, .badTop
    or a
    ret
.noVblank
    ld a, b
    ld b, $E1
    call SetNums8
    ld hl, .noteVb
    jp FailNote
.badTop
    ld a, b
    ld b, $E1
    call SetNums8
    ld hl, .noteTop
    jp FailNote
.noteVb  db "the vertical blank flag was not set at hand-over. The boot ROM waits for the screen before it lets go, so IF reads $E1 when the cartridge starts",0
.noteTop db "IF's three unimplemented bits did not read as ones at hand-over",0

SECTION "MoreApu2", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; GB-APU-06 — powering the chip off switches every channel off with it.
; ---------------------------------------------------------------------------
ChkApuPowerOff::
    ld a, $80
    ldh [rNR52], a
    ld a, $F0
    ldh [rNR12], a
    ld a, $80
    ldh [rNR14], a          ; channel 1 playing
    ldh a, [rNR52]
    and $01
    jr z, .notOn
    xor a
    ldh [rNR52], a          ; power off
    ldh a, [rNR52]
    ld b, a
    ld a, $80
    ldh [rNR52], a          ; and back on, so the rest of the run has a chip
    ld a, b
    and $01
    jr nz, .stillOn
    or a
    ret
.notOn
    ld hl, .noteOn
    jp FailNote
.stillOn
    ld b, $70
    ld a, b
    call SetNums8
    ld hl, .noteOff
    jp FailNote
.noteOn  db "a channel with its converter on and freshly triggered did not report itself playing, so this check could not ask the question",0
.noteOff db "a channel was still reported as playing after the sound chip was switched off. Clearing bit 7 of NR52 stops everything: the status bits go with it",0

; ---------------------------------------------------------------------------
; GB-APU-07 — wave memory survives the chip being switched off.
;
; Everything else the chip holds is cleared by a power cycle. The sixteen bytes
; of wave memory are not: they are a separate little RAM and they keep their
; contents, which is why a driver can load a waveform before it powers the chip
; up. An emulator that clears them along with the registers loses the waveform.
; ---------------------------------------------------------------------------
ChkApuWaveRetained::
    ld a, $80
    ldh [rNR52], a
    xor a
    ldh [rNR30], a
    ld c, LOW(_AUD3WAVERAM)
    ld b, 16
    ld d, $5A
.write
    ld a, d
    ldh [c], a
    inc c
    dec b
    jr nz, .write
    xor a
    ldh [rNR52], a          ; power off
    ld a, $80
    ldh [rNR52], a          ; and on again
    xor a
    ldh [rNR30], a
    ld c, LOW(_AUD3WAVERAM)
    ld b, 16
.read
    ldh a, [c]
    cp $5A
    jr nz, .lost
    inc c
    dec b
    jr nz, .read
    or a
    ret
.lost
    ld b, $5A
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "wave memory was cleared by a power cycle of the sound chip. The registers are cleared; these sixteen bytes are not, and a driver that loads a waveform before powering up depends on that",0

SECTION "MoreMbc2", ROM0

; ---------------------------------------------------------------------------
; GB-MBC-05 — the cartridge RAM enable looks at the low nibble only.
;
; Any value whose low four bits are $A enables it; anything else disables it.
; The mapper decodes four bits and no more, so $1A and $FA enable exactly as
; $0A does, and $0B does not. Games write all sorts of things there.
; ---------------------------------------------------------------------------
ChkMbcRamEnableNibble::
    ld a, $0A
    ld [$0000], a
    ld a, $C3
    ld [_SRAM], a           ; a known byte to watch
    ld a, [_SRAM]
    cp $C3
    jr nz, .noRam

    ld a, $1A               ; still a low nibble of $A, so still enabled
    ld [$0000], a
    ld a, [_SRAM]
    cp $C3
    jr nz, .highBitsMattered

    ld a, $0B               ; not $A, so disabled
    ld [$0000], a
    ld a, $77
    ld [_SRAM], a           ; must be discarded
    ld a, $0A
    ld [$0000], a
    ld a, [_SRAM]
    ld c, a
    xor a
    ld [$0000], a
    ld a, c
    cp $C3
    jr nz, .leaked
    or a
    ret
.noRam
    ld b, $C3
    call SetNums8
    xor a
    ld [$0000], a
    ld hl, .noteRam
    jp FailNote
.highBitsMattered
    ld b, $C3
    call SetNums8
    xor a
    ld [$0000], a
    ld hl, .noteHigh
    jp FailNote
.leaked
    ld b, $C3
    ld a, c
    call SetNums8
    xor a
    ld [$0000], a
    ld hl, .noteLeak
    jp FailNote
.noteRam  db "cartridge RAM did not hold a byte written to it while enabled",0
.noteHigh db "writing $1A disabled the cartridge RAM. Only the low four bits are decoded, so any value ending in $A enables it",0
.noteLeak db "a write landed in cartridge RAM after $0B was written to the enable. Anything whose low nibble is not $A locks it",0

SECTION "MoreInt2", ROMX, BANK[2]

; ---------------------------------------------------------------------------
; GB-INT-10 — a pending interrupt can be taken back before it is serviced.
;
; IF is writable, and clearing a bit before the master enable arrives cancels
; that interrupt outright. It is how a program disarms something it has already
; asked for, and it is the reason IF is a register rather than a set of edges.
; ---------------------------------------------------------------------------
ChkIfCancel::
    call InstallReti
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    xor a
    ld [X_TMP], a
    ld a, IEF_TIMER
    ldh [rIF], a            ; ask for it ...
    xor a
    ldh [rIF], a            ; ... and take the request back
    ei
    nop
    nop
    di
    ld a, [X_TMP]
    or a
    jr nz, .servicedAnyway
    call ClearReti
    or a
    ret
.servicedAnyway
    ld b, 0
    call SetNums8
    call ClearReti
    ld hl, .note
    jp FailNote
.note db "an interrupt was serviced after its flag had been cleared again. IF is a register a program can write, and clearing a bit before the interrupt is taken cancels it",0

SECTION "MoreTimer2", ROMX, BANK[2]

; ---------------------------------------------------------------------------
; GB-TIM-07 — switching the timer OFF can make it tick one last time.
;
; The same mechanism as GB-TIM-06 seen from the other side. What TIMA counts is
; the falling edge of (the watched bit AND the enable), so clearing the enable
; while the watched bit is set drops that expression from one to zero, and the
; timer increments on its way out. An implementation that models the timer as
; its own countdown, started and stopped by the enable, cannot produce it.
;
; Source: Pan Docs, "Timer Obscure Behaviour".
; ---------------------------------------------------------------------------
ChkTacDisableGlitch::
    di
    ld a, TACF_START | TACF_1024T   ; watches bit 9, which is bit 1 of DIV
    ldh [rTAC], a
    xor a
    ldh [rTMA], a

    ; the control: disable while the watched bit is CLEAR
    ldh [rDIV], a
.waitClear
    ldh a, [rDIV]
    and $02
    jr nz, .waitClear
    xor a
    ldh [rTIMA], a
    ldh [rTAC], a                   ; enable off
    ldh a, [rTIMA]
    or a
    jr nz, .tickedWhenClear

    ; and the case that matters: disable while it is SET
    ld a, TACF_START | TACF_1024T
    ldh [rTAC], a
    xor a
    ldh [rDIV], a
.waitSet
    ldh a, [rDIV]
    and $02
    jr z, .waitSet
    xor a
    ldh [rTIMA], a
    ldh [rTAC], a                   ; enable off, with the watched bit high
    ldh a, [rTIMA]
    ld b, a
    xor a
    ldh [rTAC], a
    ld a, b
    or a
    ret nz
    ld b, 1
    call SetNums8
    ld hl, .noteMissing
    jp FailNote
.tickedWhenClear
    ld b, 0
    call SetNums8
    xor a
    ldh [rTAC], a
    ld hl, .noteSpurious
    jp FailNote
.noteMissing  db "clearing the enable bit while the timer's watched bit was set did not increment TIMA. What is counted is the falling edge of the watched bit ANDed with the enable, so switching the enable off is itself a falling edge",0
.noteSpurious db "TIMA incremented when the enable was cleared while the watched bit was already clear",0

SECTION "MoreInt3", ROMX, BANK[2]

; ---------------------------------------------------------------------------
; GB-INT-11 — an interrupt that is no longer enabled is not taken.
;
; IE is consulted at the moment of dispatch, not when the flag went up. A
; program that raises a flag and then clears the matching enable before the
; master enable arrives gets no interrupt at all, and the flag stays standing.
; ---------------------------------------------------------------------------
ChkIeCancel::
    call InstallReti
    di
    ld a, IEF_TIMER
    ldh [rIE], a
    xor a
    ld [X_TMP], a
    ld a, IEF_TIMER
    ldh [rIF], a            ; the flag is up ...
    xor a
    ldh [rIE], a            ; ... and now nothing is enabled
    ei
    nop
    nop
    di
    ld a, [X_TMP]
    or a
    jr nz, .servicedAnyway
    ldh a, [rIF]
    and IEF_TIMER
    jr z, .flagLost
    call ClearReti
    or a
    ret
.servicedAnyway
    ld b, 0
    call SetNums8
    call ClearReti
    ld hl, .noteTaken
    jp FailNote
.flagLost
    ld b, IEF_TIMER
    ld a, 0
    call SetNums8
    call ClearReti
    ld hl, .noteLost
    jp FailNote
.noteTaken db "an interrupt was serviced whose enable bit had been cleared. IE is consulted at the moment of dispatch, not when the flag went up",0
.noteLost  db "the flag was cleared even though the interrupt was never serviced. Only dispatch clears a flag; disabling an interrupt leaves its request standing for later",0

SECTION "MoreBoot2", ROMX, BANK[3]

; ---------------------------------------------------------------------------
; GB-BOOT-06 — the divider is not zero at hand-over.
;
; The single most consequential number in the handover state, and the one an
; emulator written without a boot ROM is most likely to leave at zero. There is
; one sixteen-bit counter behind $FF04 and it has been running since the
; console was switched on; by the time the boot ROM lets go it has counted
; through the logo, the scroll and the chime.
;
; Games seed their randomness from it -- read $FF04 at the title screen and you
; have a number that depends on how long a human took to press a button. Hand
; over a zero and that number is the same every launch, which reaches a player
; as "the shuffle is not random" and reaches a maintainer as anything but a
; divider.
;
; WHAT THIS DOES NOT ASSERT, AND WHY. The exact value is documented per
; console -- $ABCC on a Game Boy and a Pocket, $2678 on a Color, $267C on an
; Advance, $1830 on the pre-release Game Boy, and on a Super Game Boy $D174
; plus four cycles for every zero bit in the cartridge header, because its boot
; ROM clocks that header to the SNES through an unbalanced loop. This check
; asserts none of them, and that is deliberate: what the counter holds at $0100
; is a property of the BOOT ROM, not of the console. Nintendo's is not
; redistributable, so more than one emulator ships a re-implementation that
; reproduces the register state exactly and takes its own number of cycles to
; get there -- SameBoy is one, and hands over $BD where the silicon hands over
; $AB. Asserting the published byte would be asserting which boot ROM was in
; the slot, which is not a fact about the Game Boy, and this cartridge does not
; check facts about its host.
;
; What every one of them agrees on, silicon and replacement alike, is that the
; counter has been running. Zero is the answer given only by a machine that
; never started it, and that is the one this catches.
;
; Source: TerminalGB docs/measured/boot.md, "The system counter does not start
; at zero" -- "the single most consequential number here, because games seed
; their RNG from DIV ... it is a value hardware never presents". The per-console
; table there comes from the Mooneye `boot_div` ROMs, verified by their author
; on real DMG, MGB and CGB units.
; ---------------------------------------------------------------------------
ChkBootDiv::
    ld a, [wBootDiv]
    or a
    jr z, .zero
    or a                    ; clear carry: the counter had been running
    ret
.zero
    xor a
    ld b, $AB
    call SetNums8
    ld hl, .noteZero
    jp FailNote
.noteZero db "the divider read zero at hand-over. The counter behind $FF04 has been running since power-on and every boot ROM leaves it somewhere: $AB on a Game Boy, $26 on a Color, $D1 on a Super Game Boy. Zero is what a machine hands over when it never started the counter at all, and a game seeding its randomness there plays the same game every launch",0

; This one's ENTRY lives in the fixed bank rather than bank 3 with the rest of
; BOOT -- bank 3 was already full, and `RunCheckList` maps it before jumping
; here regardless of where the routine actually lives. Its own working out is
; heavier than a report string, so it borrows MEM's bank (2, which has room)
; the way `ChkVramSize` borrows CPU's font bank through `LoadFont`: switch,
; call, switch back to BOOT's own bank before returning, so the reporting
; that follows still finds whatever it expects mapped. The two `FailNote`
; strings stay in the fixed bank precisely because reporting happens AFTER
; the switch-back -- a note pointer has to resolve under whatever bank ends
; up mapped when it is finally printed, not whichever one computed it.
SECTION "MoreBootLogo", ROM0

; ---------------------------------------------------------------------------
; GB-BOOT-07 -- the cartridge's own header logo decompresses into $8010-$818F.
;
; Every bootable cartridge carries a copy of this bitmap at $0104-$0133 --
; hardware refuses to run one whose copy does not match, so it is present in
; every ROM this cartridge has ever been tested against, this one included --
; and the monochrome boot ROMs turn it into the 24 tiles at $8010-$818F by a
; documented, public algorithm (Pan Docs, "0104-0133 -- Nintendo logo"): each
; PAIR of header bytes is one tile, split into four nibbles (one nibble per
; pair of output rows, MSB = the leftmost of the nibble's four source pixels),
; each nibble horizontally doubled and written TWICE (vertical doubling) into
; the tile's LOW bitplane only -- the high plane is left holding whatever VRAM
; already read, which on a freshly cleared screen is zero.
;
; This recomputes that decompression from the header THIS CARTRIDGE ITSELF
; carries and compares it against what the boot ROM actually left in VRAM,
; captured at Start before a single other byte of VRAM was touched (see
; main.asm, wram.inc). It is a fact about the cartridge's own bytes, checked a
; second, independent way on the machine itself -- nothing here reads, embeds,
; or depends on the boot ROM's own content, and nothing here asserts what a
; Color console's differently-shaped boot sequence leaves behind, so it does
; not run on one. The glyph at tile $19 is deliberately NOT part of this --
; that content is boot-ROM-only, with nothing in the cartridge to derive it
; from, and this cartridge neither reads it nor guesses at it. GB-PPU-23
; checks what CAN be said about that tile without touching its content.
;
; Source: TerminalGB docs/mealybug.md Sec 8.6 records the same distinction and
; the reasoning behind it; Pan Docs' "0104-0133 -- Nintendo logo" and
; "Power-Up Sequence -- Monochrome models" give the algorithm in full.
; ---------------------------------------------------------------------------
ChkBootLogoTiles::
    ld a, [wConsole]
    cp CONSOLE_CGB
    jr z, .skip
    cp CONSOLE_AGB
    jr z, .skip
    cp CONSOLE_UNK
    jr z, .skip

    ld a, 2                 ; borrow MEM's bank, which has the room
    ld [$2000], a
    call BootLogoDecompress
    push af
    ld a, 3                 ; BOOT's own bank, mapped through the reporting
    ld [$2000], a
    pop af
    ret nc
    ld hl, .note
    jp FailNote
.skip
    ld hl, .noteSkip
    jp SkipWith
.note db "video RAM did not hold the tile this cartridge's own header decompresses to. Either the boot ROM did not do the documented unpack, or something wrote to $8010-$818F before this cartridge's own snapshot could reach it",0
.noteSkip db "not run: a Color console's boot ROM decompresses the header logo by a differently-shaped sequence this cartridge does not have a documented, public description of -- see docs/mealybug.md Sec 8.6",0

; ---------------------------------------------------------------------------
; The decompression itself, and its table, live in MEM's bank (2) -- the part
; ChkBootLogoTiles above borrows it for. Nothing here calls FailNote/SkipWith
; (their string pointers would not survive the switch back); a mismatch is
; reported through SetNums8 (numbers only, no pointer) and a plain carry flag,
; which the fixed-bank entry point above turns into a report once its own
; bank is back.
; ---------------------------------------------------------------------------
SECTION "BootLogoDecompress", ROMX, BANK[2]

; BootLogoDecompress -- recompute the header-logo decompression fresh from
; this cartridge's own $0104-$0133 and compare it against the snapshot
; GB-BOOT-07 captured at hand-over (wBootLogoTiles). Carry clear on a full
; match; carry set, with A/B loaded for SetNums8, on the first mismatch.
BootLogoDecompress:
    ld hl, $0104            ; the header: fixed bank 0, reachable whatever is
                            ; mapped at $4000-$7FFF
    ld de, wBootLogoTiles
    ld a, 48                ; header bytes -- two per tile, 24 tiles
    ld [wScratch], a
.byte
    ld a, [hl+]
    ld [wScratch + 1], a    ; this byte's two nibbles, held across the calls
                            ; below (which do not touch wScratch)
    swap a
    and $0F
    call DoubleAndCheckRowPair
    ret c
    ld a, [wScratch + 1]
    and $0F
    call DoubleAndCheckRowPair
    ret c
    ld a, [wScratch]
    dec a
    ld [wScratch], a
    jr nz, .byte
    or a
    ret

DoubleNibbleTable:
    db $00, $03, $0C, $0F, $30, $33, $3C, $3F, $C0, $C3, $CC, $CF, $F0, $F3, $FC, $FF

; DoubleAndCheckRowPair -- A = a 4-bit nibble (top nibble already masked to
; zero). Doubles it (the "chunky pixel" horizontal doubling every monochrome
; boot ROM applies to the header logo) and compares the result against
; [DE..DE+3], which must read (doubled, 0, doubled, 0) -- TWO tile rows, low
; and high bitplane each, because vertical doubling writes the same doubled
; byte to both. Leaves DE advanced four bytes past them either way. Returns
; carry set and A/B loaded for SetNums8 on the first mismatch; HL (the
; caller's header pointer) is preserved.
DoubleAndCheckRowPair:
    ld c, a
    ld b, 0
    push hl
    ld hl, DoubleNibbleTable
    add hl, bc
    ld a, [hl]
    pop hl
    ld c, a                 ; C = the wanted low-plane byte, both rows
    ld a, [de]
    cp c
    jr nz, .lowBad
    inc de
    ld a, [de]
    inc de
    or a
    jr nz, .highBad
    ld a, [de]
    cp c
    jr nz, .lowBad
    inc de
    ld a, [de]
    inc de
    or a
    ret z                   ; both rows' high planes are zero, as they must
                            ; be -- pass
.highBad
    ld b, 0
    call SetNums8
    scf
    ret
.lowBad
    ld b, c
    call SetNums8
    scf
    ret
