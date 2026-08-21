; checks_misc.asm — the object transfer, the sound registers, the mapper, the
; state the boot ROM handed over, and the link port.

INCLUDE "hardware.inc"

SECTION "ChecksMisc", ROMX, BANK[3]

DEF M_TMP EQU wScratch + 72
DEF M_A   EQU wScratch + 73
DEF M_B   EQU wScratch + 74

; ===========================================================================
; The object transfer.
;
; The routine that starts it has to run from high RAM: while the transfer is
; running the CPU cannot reach the bus the transfer is using, and high RAM is
; the one place that is always its own. Every game does this and so does this
; cartridge.
; ===========================================================================
SECTION "DmaHram", HRAM
hDmaStart:: ds 16
hDmaProbe:: ds 24
hDmaSeen::  db
hDmaBus::   ds 32
hDmaSaw::   ds 3
hDmaA12::   ds 24
hDmaWram::  ds 16

SECTION "DmaCode", ROMX, BANK[3]

DmaStartSrc:
    ldh [rDMA], a
    ld a, 45                ; forty-five turns of four machine cycles, which
.wait                       ; comfortably outlasts the transfer's 160
    dec a
    jr nz, .wait
    ret
DmaStartEnd:

; The read has to happen while the transfer is running, and the RETURN has to
; happen after it. The transfer's source is work RAM, so while it runs the CPU
; cannot read work RAM -- and the stack is in work RAM, so a RET taken during
; the transfer pops rubbish and the machine is gone. This cost a hang on
; SameBoy and it is exactly why the idiom is to sit in high RAM for the whole
; transfer rather than to start it and walk away.
DmaProbeSrc:
    ldh [rDMA], a
    ld a, [_OAMRAM]         ; read while it must still be running
    ldh [hDmaSeen], a       ; high RAM: the one place still ours
    ld a, 45
.wait
    dec a
    jr nz, .wait
    ldh a, [hDmaSeen]
    ret
DmaProbeEnd:

; ---------------------------------------------------------------------------
; The transfer and the processor share one set of wires.
;
; The transfer controller has no bus of its own: it drives the source address
; onto whichever bus that address lives on and reads the byte back off it. So a
; processor read of an address on that same bus, during the transfer, is
; looking at the same wires — and gets the byte the transfer is moving, not the
; byte it asked for.
;
; This reads ONE fixed cartridge address three times while a transfer sourced
; from the cartridge is running. The byte at that address never changes; the
; byte the transfer is moving changes every machine cycle. Three different
; answers is the whole proof, and it needs no cycle counting at all.
; ---------------------------------------------------------------------------
DmaBusSrc:
    ldh [rDMA], a
    ld a, [DmaRamp]
    ldh [hDmaSaw + 0], a
    ld a, [DmaRamp]
    ldh [hDmaSaw + 1], a
    ld a, [DmaRamp]
    ldh [hDmaSaw + 2], a
    ld a, 45
.wait
    dec a
    jr nz, .wait
    ret
DmaBusEnd:

; The processor's own address lines are shared with the transfer too, not just
; the data lines. See GB-DMA-05.
DmaA12Src:
    ldh [rDMA], a
    ld a, $5A
    ld [$C000], a
    ld a, 45
.wait
    dec a
    jr nz, .wait
    ret
DmaA12End:

; A transfer sourced from work RAM itself, conflicting with a write into the
; very page it is reading. See GB-DMA-07.
DmaWramSrc:
    ldh [rDMA], a
    ld a, $55
    ld [$D000], a
    ld a, 45
.wait
    dec a
    jr nz, .wait
    ret
DmaWramEnd:

InstallDmaA12:
    ld hl, DmaA12Src
    ld de, hDmaA12
    ld b, DmaA12End - DmaA12Src
    jr InstallDma.copy

InstallDmaWram:
    ld hl, DmaWramSrc
    ld de, hDmaWram
    ld b, DmaWramEnd - DmaWramSrc
    jr InstallDma.copy

InstallDmaBus:
    ld hl, DmaBusSrc
    ld de, hDmaBus
    ld b, DmaBusEnd - DmaBusSrc
    jr InstallDma.copy

InstallDma:
    ld hl, DmaStartSrc
    ld de, hDmaStart
    ld b, DmaStartEnd - DmaStartSrc
    call .copy
    ld hl, DmaProbeSrc
    ld de, hDmaProbe
    ld b, DmaProbeEnd - DmaProbeSrc
.copy
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .copy
    ret

; A page of known bytes for the transfer to move.
PrepareDmaSource:
    ld hl, $D000            ; a whole page, well clear of the stack
    ld c, 160
    ld b, $40
.next
    ld a, b
    ld [hl+], a
    inc b
    dec c
    jr nz, .next
    ret

; ---------------------------------------------------------------------------
; GB-DMA-01 — the transfer moves 160 bytes.
; ---------------------------------------------------------------------------
ChkDmaCopy::
    call LcdOff
    call InstallDma
    call PrepareDmaSource
    di
    ld a, $D0
    call hDmaStart
    ; compare object memory against what was sent
    ld hl, _OAMRAM
    ld de, $D000
    ld c, 160
.next
    ld a, [de]
    ld b, a
    ld a, [hl+]
    cp b
    jr nz, .bad
    inc de
    dec c
    jr nz, .next
    or a
    ret
.bad
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "object memory does not hold what the transfer was pointed at. Writing a page number to $FF46 copies 160 bytes from that page into $FE00",0

; ---------------------------------------------------------------------------
; GB-DMA-02 — the transfer is not instantaneous.
;
; A read of object memory taken one instruction after the transfer starts must
; return $FF, because the transfer owns the bus for 160 machine cycles. Three
; outcomes are told apart here and they mean three different things: $FF is
; right, the copied byte means the transfer finished immediately, and the old
; byte means it never happened at all.
; ---------------------------------------------------------------------------
ChkDmaTime::
    call LcdOff
    call InstallDma
    call PrepareDmaSource
    di
    xor a
    ld [_OAMRAM], a         ; a value that is neither $FF nor what is sent
    ld a, $D0
    call hDmaProbe
    ld [M_TMP], a
    cp $FF
    jr nz, .notBlocked
    or a
    ret
.notBlocked
    ld b, $FF
    ld a, [M_TMP]
    call SetNums8
    or a
    jr z, .never
    ld hl, .noteInstant
    jp FailNote
.never
    ld hl, .noteNever
    jp FailNote
.noteInstant db "object memory was readable one instruction after the transfer began, and already held the new byte. The transfer takes 160 machine cycles and the CPU cannot see object memory during them",0
.noteNever   db "object memory still held its old value: the transfer did not happen",0

; ---------------------------------------------------------------------------
; GB-DMA-03 — $FF46 reads back.
; ---------------------------------------------------------------------------
ChkDmaReg::
    call LcdOff
    call InstallDma
    call PrepareDmaSource
    di
    ld a, $D0
    call hDmaStart
    ldh a, [rDMA]
    cp $D0
    ret z
    ld b, $D0
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "$FF46 must read back the last page written to it",0

; ===========================================================================
; The sound chip. Registers and the length counter only: what comes out of the
; speaker is not something a cartridge can hear.
; ===========================================================================

; Each entry is the low byte of the address and the bits that always read as
; one. Source: Pan Docs, Audio Registers -- the write-only and unused bits.
ApuMaskTable:
    db LOW(rNR10), $80
    db LOW(rNR11), $3F
    db LOW(rNR12), $00
    db LOW(rNR13), $FF
    db LOW(rNR14), $BF
    db LOW(rNR21), $3F
    db LOW(rNR22), $00
    db LOW(rNR23), $FF
    db LOW(rNR24), $BF
    db LOW(rNR30), $7F
    db LOW(rNR31), $FF
    db LOW(rNR32), $9F
    db LOW(rNR33), $FF
    db LOW(rNR34), $BF
    db LOW(rNR41), $FF
    db LOW(rNR42), $00
    db LOW(rNR43), $00
    db LOW(rNR44), $BF
    db LOW(rNR50), $00
    db LOW(rNR51), $00
    db 0, 0

ApuPowerOn:
    ld a, $80
    ldh [rNR52], a
    ret

; ---------------------------------------------------------------------------
; GB-APU-01 — every register reads back its documented bits.
; ---------------------------------------------------------------------------
ChkApuMasks::
    call ApuPowerOn
    ld hl, ApuMaskTable
.next
    ld a, [hl+]
    or a
    jr z, .doneTable
    ld c, a
    ld a, [hl+]
    ld b, a                 ; b = the mask
    xor a
    ldh [c], a              ; write zero, so only the mask can come back
    ldh a, [c]
    cp b
    jr nz, .bad
    jr .next
.doneTable
    ; NR52 reports the power in bit 7 and the channels in the low four; with
    ; every digital-to-analogue converter switched off, nothing is playing.
    ldh a, [rNR52]
    ld b, $F0
    cp b
    jr nz, .badStatus
    or a
    ret
.bad
    call SetNums8
    ld hl, .note
    jp FailNote
.badStatus
    call SetNums8
    ld hl, .noteStatus
    jp FailNote
.note       db "a sound register did not read back its documented bits. Write-only and unused bits read as ones: the reported value is what was written OR the mask, and a register that returns exactly what was written is wrong",0
.noteStatus db "with the chip powered and every channel's converter off, NR52 must read $F0: bit 7 for the power, three unused bits set, and no channel playing",0

; ---------------------------------------------------------------------------
; GB-APU-02 — powering off clears the registers and locks them.
; ---------------------------------------------------------------------------
ChkApuPower::
    call ApuPowerOn
    ld a, $F3
    ldh [rNR50], a
    xor a
    ldh [rNR52], a          ; power off
    ldh a, [rNR50]
    or a
    jr nz, .notCleared
    ld a, $FF
    ldh [rNR12], a          ; a write that must be ignored
    ldh a, [rNR12]
    or a
    jr nz, .notLocked
    ldh a, [rNR52]
    cp $70
    jr nz, .badStatus
    call ApuPowerOn
    or a
    ret
.notCleared
    ld b, 0
    call SetNums8
    call ApuPowerOn
    ld hl, .noteClr
    jp FailNote
.notLocked
    ld b, 0
    call SetNums8
    call ApuPowerOn
    ld hl, .noteLock
    jp FailNote
.badStatus
    ld b, $70
    call SetNums8
    call ApuPowerOn
    ld hl, .noteStat
    jp FailNote
.noteClr  db "clearing bit 7 of NR52 must zero NR10 through NR51",0
.noteLock db "while the chip is powered off, writes to the channel registers must be discarded",0
.noteStat db "a powered-off chip reads $70 from NR52: the three unused bits and nothing else",0

; ---------------------------------------------------------------------------
; GB-APU-03 — NR52 reports which channels are on, and a length counter that
; runs out switches its channel off without anything else happening.
; ---------------------------------------------------------------------------
ChkApuStatus::
    call ApuPowerOn
    ld a, $F0               ; full volume, no envelope, so the converter is on
    ldh [rNR12], a
    ld a, $80
    ldh [rNR14], a          ; trigger, with no length enable
    ldh a, [rNR52]
    and $01
    jr z, .notOn
    ; now the same channel with one step of length left
    ld a, $3F               ; length 63, which is one step short of the end
    ldh [rNR11], a
    ld a, $F0
    ldh [rNR12], a
    ld a, $C0
    ldh [rNR14], a          ; trigger with the length counter enabled
    ; Wait long enough for the WORST case, not the expected one. A step is
    ; 3.9 milliseconds and the counter has one step left, so this usually
    ; happens at once -- but enabling the length counter part-way through a
    ; length period clocks it once immediately, and if that immediate clock is
    ; what takes the counter to zero on a write that also triggers, the counter
    ; reloads to its full 64 steps. That is documented hardware and it is a
    ; coin toss which side of the period the trigger lands on, so anything
    ; shorter than 64 steps here is a check that passes or fails by luck.
    ; Sixty-four steps is 250 milliseconds; this waits for 390.
    ld c, 200
.settle
    ldh a, [rNR52]
    and $01
    jr z, .expired
    push bc
    ld a, 2
    call DelayA             ; roughly two milliseconds
    pop bc
    dec c
    jr nz, .settle
    jr .stillOn
.expired
    or a
    ret
.notOn
    ldh a, [rNR52]
    ld b, $F1
    call SetNums8
    ld hl, .noteOn
    jp FailNote
.stillOn
    ldh a, [rNR52]
    ld b, $F0
    call SetNums8
    ld hl, .noteOff
    jp FailNote
.noteOn  db "triggering a channel whose converter is on must set its bit in NR52",0
.noteOff db "the length counter ran out and the channel is still reported as playing. Length is clocked at 256 Hz and clears the channel's enable when it reaches zero",0

; ---------------------------------------------------------------------------
; GB-APU-04 — wave memory is ordinary memory while channel 3 is silent.
; ---------------------------------------------------------------------------
ChkApuWave::
    call ApuPowerOn
    xor a
    ldh [rNR30], a          ; channel 3's converter off, so it cannot be playing
    ld c, LOW(_AUD3WAVERAM)
    ld b, 16
    ld d, $A0
.write
    ld a, d
    ldh [c], a
    inc d
    inc c
    dec b
    jr nz, .write
    ld c, LOW(_AUD3WAVERAM)
    ld b, 16
    ld d, $A0
.read
    ldh a, [c]
    cp d
    jr nz, .bad
    inc d
    inc c
    dec b
    jr nz, .read
    or a
    ret
.bad
    ld b, d
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "the sixteen bytes at $FF30 did not read back what was written. With channel 3 switched off they are plain memory; only while it is playing does the channel own them",0

; ===========================================================================
; The state the boot ROM handed over.
; ===========================================================================

; ---------------------------------------------------------------------------
; GB-BOOT-01 — the stack pointer starts at the top of high RAM.
; ---------------------------------------------------------------------------
ChkBootSp::
    ld a, [wBootSP]
    ld e, a
    ld a, [wBootSP + 1]
    ld d, a
    ld hl, $FFFE
    ld a, e
    cp l
    jr nz, .bad
    ld a, d
    cp h
    jr nz, .bad
    or a
    ret
.bad
    call SetNums16
    ld hl, .note
    jp FailNote
.note db "every console's boot ROM leaves the stack pointer at $FFFE, and a cartridge that never sets one of its own depends on it",0

; ---------------------------------------------------------------------------
; GB-BOOT-02 — A names the console.
; ---------------------------------------------------------------------------
ChkBootA::
    ld a, [wConsole]
    cp CONSOLE_UNK
    jr z, .unknown
    or a
    ret
.unknown
    ld a, [BOOT_A]
    ld b, $01
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "A held a value no console leaves behind. It is $01 on a Game Boy, $FF on a Pocket and $11 on a Color, and software has told the machines apart that way since the Pocket shipped",0

; ---------------------------------------------------------------------------
; GB-BOOT-03 — the whole register set, on the consoles whose table is
; documented for a cartridge with no Color flag.
; ---------------------------------------------------------------------------
; Offset into the captured set, then the value this console's boot ROM leaves.
; A is checked on its own above. Source: Pan Docs, "Power-Up Sequence".
BootDmgTable:
    db BOOT_F - wBootRegs, $B0
    db BOOT_B - wBootRegs, $00
    db BOOT_C - wBootRegs, $13
    db BOOT_D - wBootRegs, $00
    db BOOT_E - wBootRegs, $D8
    db BOOT_H - wBootRegs, $01
    db BOOT_L - wBootRegs, $4D
    db $FF, $00

ChkBootRegs::
    ld a, [wConsole]
    cp CONSOLE_CGB
    jr z, .colour
    cp CONSOLE_AGB
    jr z, .colour
    cp CONSOLE_UNK
    jr z, .colour
    ld hl, BootDmgTable
.next
    ld a, [hl+]
    cp $FF
    jr z, .allOk
    ld [M_A], a             ; remember which register this is
    ld e, a
    ld d, 0
    ld a, [hl+]
    ld c, a                 ; what this register should hold
    push hl
    ld hl, wBootRegs
    add hl, de
    ld a, [hl]
    pop hl
    ld b, c
    cp b
    jr nz, .bad
    jr .next
.allOk
    or a
    ret
.bad
    call SetNums8
    ld a, [M_A]
    ld [wGot + 1], a        ; the offset into the captured set, for diagnosis
    ld hl, .note
    jp FailNote
.colour
    ld hl, .noteSkip
    jp SkipWith
.note     db "a register did not hold the value this console's boot ROM leaves. The set is F $B0, B $00, C $13, D $00, E $D8, H $01, L $4D, and games have shipped depending on all of it",0
.noteSkip db "not run: this cartridge carries no Color flag, so a Color console runs it in compatibility mode, and no published table covers the handover state for that combination",0

; ---------------------------------------------------------------------------
; GB-BOOT-04 — addresses with no register behind them read as ones.
; ---------------------------------------------------------------------------
UnusedIoTable:
    db $03, $08, $09, $0A, $0B, $0C, $0D, $0E, $15, $1F, $27, $28, $29, $00

ChkBootIo::
    ld hl, UnusedIoTable
.next
    ld a, [hl+]
    or a
    jr z, .done
    ld c, a
    ldh a, [c]
    cp $FF
    jr nz, .bad
    jr .next
.done
    or a
    ret
.bad
    ld b, $FF
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "an address in the register page with nothing behind it returned something other than $FF. Nothing drives the bus there, so it floats high",0

; ===========================================================================
; The link port. Run last, because the report itself goes out of it.
; ===========================================================================

; ---------------------------------------------------------------------------
; GB-SER-01 — SB is a plain register while nothing is being shifted.
; ---------------------------------------------------------------------------
ChkSerSb::
    di
    xor a
    ldh [rSC], a
    ld a, $A5
    ldh [rSB], a
    ldh a, [rSB]
    cp $A5
    jr nz, .bad
    ld a, $5A
    ldh [rSB], a
    ldh a, [rSB]
    cp $5A
    jr nz, .bad
    or a
    ret
.bad
    ld b, $A5
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "$FF01 did not hold what was written to it. It is the shift register, and between transfers it is ordinary storage",0

; ---------------------------------------------------------------------------
; GB-SER-02 — SC's unused bits read as ones.
;
; Bit 1 is left out of this on purpose: it selects the fast clock on a Color
; console and does not exist on the others, so its reading is not one number.
; ---------------------------------------------------------------------------
ChkSerUnused::
    di
    xor a
    ldh [rSC], a
    ldh a, [rSC]
    ld b, a
    or $83                  ; ignore bits 7, 1 and 0, which do exist
    cp $FF
    jr nz, .bad
    or a
    ret
.bad
    ld a, b
    ld b, $7C
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "bits 2 to 6 of SC were never implemented and must read back as ones",0

; ---------------------------------------------------------------------------
; GB-SER-03 — an internally clocked transfer finishes on its own.
;
; The console generates the clock, so eight bits are shifted whether or not
; anything is listening; the transfer ends, bit 7 clears and the interrupt is
; raised. What comes back is not checked, because that depends on what is
; plugged in.
; ---------------------------------------------------------------------------
ChkSerXfer::
    di
    xor a
    ldh [rIF], a
    ; Whatever is shifted out lands in the captured log, because the log IS
    ; the link port. A full stop is sent so the one stray byte a host sees is
    ; obviously deliberate and cannot be mistaken for part of a verdict.
    ld a, '.'
    ldh [rSB], a
    ld a, SCF_START | SCF_INTERNAL
    ldh [rSC], a
    ld de, 20000
.wait
    ldh a, [rSC]
    bit 7, a
    jr z, .finished
    dec de
    ld a, d
    or e
    jr nz, .wait
    ld hl, .noteHang
    jp FailNote
.finished
    ldh a, [rIF]
    and IEF_SERIAL
    jr z, .noIrq
    xor a
    ldh [rIF], a
    ; The byte just shifted out has landed in the middle of the log, because
    ; the log IS the link port. Close the line so the next check's verdict
    ; starts at a column a host's parser expects.
    call SerialNewline
    or a
    ret
.noIrq
    ld hl, .noteIrq
    jp FailNote
.noteHang db "bit 7 of SC never cleared. With the internal clock selected the console shifts eight bits by itself and the transfer ends",0
.noteIrq  db "the transfer ended without raising bit 3 of IF",0

; ---------------------------------------------------------------------------
; GB-DMA-04 — the transfer and the processor share the cartridge bus.
; ---------------------------------------------------------------------------
ChkDmaBus::
    call LcdOff
    call InstallDmaBus
    di
    ld a, HIGH(DmaRamp)
    call hDmaBus

    ldh a, [hDmaSaw + 0]
    ld b, a
    ldh a, [hDmaSaw + 1]
    cp b
    jr nz, .shared
    ldh a, [hDmaSaw + 2]
    cp b
    jr nz, .shared

    ; every read gave the same byte: tell the two ways that can happen apart
    ld a, [DmaRamp]
    cp b
    jr z, .notShared
    ld hl, .noteFixed
    jp FailNote
.notShared
    ld hl, .noteOwn
    jp FailNote
.shared
    or a
    ret

.noteOwn   db "three reads of one fixed cartridge address, taken while a transfer sourced from the cartridge was running, all returned that address's own byte. The transfer controller has no bus of its own: it drives the source address onto the cartridge bus, so a read on that bus during the transfer sees the byte the transfer is moving",0
.noteFixed db "three reads during the transfer all returned the same byte, and it was not the one at the address asked for. The processor is being given one fixed value rather than the byte the transfer is moving at that machine cycle",0

; A page of bytes that all differ, aligned so it can be a transfer source.
; Bank 3 — the bank this area's checks already run from, so the read inside
; the high-RAM routine reaches it. ROM0 has no room for an aligned page.
SECTION "DmaRamp", ROMX, BANK[3], ALIGN[8]
DmaRamp::
    FOR i, 160
    db (i * 7 + 1) & $FF
    ENDR

; ---------------------------------------------------------------------------
; GB-DMA-05 — an OAM DMA transfer overrides address bit 12 of a work-RAM
; access.
;
; The data lines are shared (GB-DMA-04). The address lines are shared too: on
; a Color console, while a transfer runs out of a page on the EXTERNAL bus
; (the cartridge, or video memory), a processor access to $C000-$DFFF has bit
; 12 of its own address replaced by bit 12 of the address the transfer is
; driving. Bits 0-11 stay the processor's, and SVBK still decides which bank
; answers at $D000 -- only which HALF of the window answers moves.
;
; So a write meant for $C000, made while a transfer is sourced from a page
; whose bit 12 is set, lands at $D000 instead. This check writes $5A to
; $C000 during a transfer out of page $70 (address $7000, bit 12 set) and
; reads both halves back: an unaffected address bus leaves $C000 = $5A and
; $D000 untouched; a shared one leaves $C000 untouched and $D000 = $5A.
;
; This used to be reported rather than judged, because no published reference
; documented it. It is documented now: derived from a probe cartridge run
; through TerminalGB's own emulator and through SameBoy side by side, and the
; two independent implementations agree (TerminalGB,
; docs/measured/oam-dma-work-ram.md).
;
; A Color console only, because work RAM on a monochrome console is on the
; SAME bus as the cartridge, so a write during the transfer is an ordinary
; bus conflict (GB-DMA-04) and this address question does not arise there.
; See GB-DMA-07 for the ordinary conflict that DOES arise there instead.
; ---------------------------------------------------------------------------
ChkDmaA12::
    ld a, [wConsole]
    cp CONSOLE_CGB
    jr z, .go
    cp CONSOLE_AGB
    jr z, .go
    ld hl, .noteMono
    jp SkipWith
.go
    call LcdOff
    call InstallDmaA12
    di
    xor a
    ld [$C000], a
    ld [$D000], a
    ld a, $70               ; a cartridge page with address line 12 set
    call hDmaA12

    ld a, [$C000]           ; D = what $C000 holds, E = what $D000 holds
    ld d, a
    ld a, [$D000]
    ld e, a
    ld a, e
    cp $5A                  ; the write, redirected, landing at $D000
    jr nz, .bad
    ld a, d
    or a                    ; and nothing landing where it was addressed
    jr nz, .bad
    or a
    ret
.bad
    ld hl, $005A            ; want: $C000 = $00, $D000 = $5A
    call SetNums16
    ld hl, .note
    jp FailNote

.noteMono db "work RAM shares the cartridge bus on this console, so a write during the transfer is an ordinary bus conflict and there is no address question to ask",0
.note     db "the byte from $C000 did not turn up alone at $D000. A work-RAM access made while the source has bit 12 set should take that bit from the transfer, landing the write at $D000 instead",0

; ---------------------------------------------------------------------------
; GB-DMA-07 — a write that conflicts with the transfer's OWN source bus does
; not land, on any console.
;
; GB-DMA-04 shows a transfer sourced from the cartridge shares that bus with
; the processor, and every DMA routine is copied to high RAM before it runs
; because work RAM sits on the SAME bus as the cartridge on a DMG or Pocket.
; Source a transfer from work RAM itself and the same rule applies to the
; transfer's own source: whichever byte the controller is driving onto that
; bus is what answers a processor access sharing the cycle, not the byte the
; processor asked to write.
;
; This reuses GB-DMA-01's own known page ($D000 = $40, the first byte
; PrepareDmaSource writes) as the transfer's source, rather than priming a
; page of its own, so the write is checked against exactly one known byte.
;
; A finer question -- whether the byte that lands on a monochrome console is
; the primed byte untouched or a bitwise mix of it with what was written --
; needs cycle-exact alignment with the transfer's own counter that this
; check does not attempt; TerminalGB and SameBoy agree, independently, that
; the primed byte survives at this granularity (TerminalGB,
; docs/measured/oam-dma-work-ram.md, which cites Gambatte's own hwtest ROMs).
; ---------------------------------------------------------------------------
ChkDmaWram::
    call LcdOff
    call PrepareDmaSource   ; $D000 = $40, the same known page GB-DMA-01 uses
    call InstallDmaWram
    di
    ld a, $D0               ; work RAM itself is the transfer's own source
    call hDmaWram
    ld a, [$D000]
    cp $40
    ret z
    ld b, $40
    call SetNums8
    ld hl, .note
    jp FailNote
.note db "$40 was primed at $D000, a page a work-RAM-sourced transfer was reading, and $55 written there while the transfer ran. The write should not have landed",0
