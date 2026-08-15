; banks.asm — the switchable banks announce themselves.
;
; Each bank begins with its own number, so a program that selects bank N and
; reads $4000 can tell which bank it actually got. That is the only way a
; cartridge can check its own mapper: the answer has to come out of the
; cartridge's own contents, never from anything an emulator says about itself.
;
; These sections are placed at $4000 explicitly so the number really is the
; first byte of the bank whatever else the linker puts there.

INCLUDE "hardware.inc"

FOR N, 1, ROM_BANKS
SECTION "Bank {d:N} identity", ROMX[$4000], BANK[N]
    db N
ENDR
