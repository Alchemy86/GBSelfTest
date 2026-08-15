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
