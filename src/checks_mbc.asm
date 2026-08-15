; checks_mbc.asm — the mapper.
;
; These three checks live in bank 0 and nowhere else, and that is not a
; preference: they switch banks, so any code doing the switching from a
; switchable bank would unmap itself in the middle of an instruction. Bank 0 is
; always present, which is exactly why the mapper cannot put anything else
; there.

INCLUDE "hardware.inc"

SECTION "ChecksMbc", ROM0

; ===========================================================================
; The mapper.
; ===========================================================================

; ---------------------------------------------------------------------------
; GB-MBC-01 — the bank selected is the bank that appears.
; ---------------------------------------------------------------------------
ChkMbcBanks::
    ld c, 1
.next
    ld a, c
    ld [$2000], a
    ld a, [$4000]
    cp c
    jr nz, .bad
    inc c
    ld a, c
    cp ROM_BANKS
    jr c, .next
    ld a, 1
    ld [$2000], a
    or a
    ret
.bad
    ld b, c
    call SetNums8
    ld a, 1
    ld [$2000], a
    ld hl, .note
    jp FailNote
.note db "the bank at $4000 is not the one selected by the write to $2000. Every bank of this cartridge begins with its own number, so the byte read back names the bank actually mapped",0

; ---------------------------------------------------------------------------
; GB-MBC-02 — bank zero is translated to bank one.
; ---------------------------------------------------------------------------
ChkMbcZero::
    xor a
    ld [$2000], a
    ld a, [$4000]
    ld b, 1
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
.note db "writing a bank number of zero selected bank zero. The mapper cannot place bank zero at $4000 -- it is already at $0000 -- so a zero is translated to one, and games rely on that to reach bank one",0

; ---------------------------------------------------------------------------
; GB-MBC-03 — cartridge RAM only answers when it has been enabled.
; ---------------------------------------------------------------------------
ChkMbcRam::
    ld a, $0A
    ld [$0000], a           ; enable
    ld a, $11
    ld [_SRAM], a
    ld a, [_SRAM]
    cp $11
    jr nz, .noRam
    xor a
    ld [$0000], a           ; disable
    ld a, $5A
    ld [_SRAM], a           ; must be discarded
    ld a, $0A
    ld [$0000], a           ; enable again
    ld a, [_SRAM]
    ld c, a
    xor a
    ld [$0000], a
    ld a, c
    cp $11
    jr nz, .leaked
    or a
    ret
.noRam
    ld b, $11
    call SetNums8
    xor a
    ld [$0000], a
    ld hl, .noteRam
    jp FailNote
.leaked
    ld b, $11
    ld a, c
    call SetNums8
    ld hl, .noteLeak
    jp FailNote
.noteRam  db "cartridge RAM did not hold a byte written to it after $0A was written to $0000",0
.noteLeak db "a write to cartridge RAM landed while the RAM was disabled. The enable is what protects a save from a program that has lost its way",0

