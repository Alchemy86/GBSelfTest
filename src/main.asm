; ===========================================================================
; GBSelfTest — a Game Boy cartridge that tests the machine it is running on.
;
; It runs a suite unattended and reports the verdict two ways: as text on the
; screen, and as the same text over the serial port so a host can capture it
; with nobody watching. One file, boot it, read the answer.
;
; THE INDEPENDENCE RULE, which is the whole reason the verdict is worth
; anything:
;
;   No check's expected value may be a number measured from an emulator.
;   Every expectation here is either (a) computed a second, independent way on
;   the machine itself -- a software model of the same arithmetic, an algebraic
;   invariant, a ratio between two clocks that share no logic -- or (b) a
;   documented constant that is a fact about the hardware (Pan Docs, the
;   published opcode table). A behaviour that cannot be checked either way does
;   not go in; it is listed as untested instead, with the reason.
;
; See ../README.md for the contract and the coverage statement, and
; ../docs/CHECKS.md for what every check code means.
; ===========================================================================

INCLUDE "hardware.inc"

; ---------------------------------------------------------------------------
; Cartridge header
; ---------------------------------------------------------------------------
SECTION "Entry", ROM0[$0100]
    nop
    jp Start
    ds $150 - @, 0          ; rgbfix writes the header here

; ---------------------------------------------------------------------------
; Interrupt vectors.
;
; Every vector goes through a hook pointer in WRAM so a check can install its
; own handler and take it away again. A hook is entered with the interrupted
; code's HL already on the stack and AF live; it must finish with `pop hl`
; followed by `reti`.
; ---------------------------------------------------------------------------
SECTION "IntVBlank", ROM0[$0040]
    push hl
    ld hl, wHookVBlank
    jr IntCommon

SECTION "IntStat", ROM0[$0048]
    push hl
    ld hl, wHookStat
    jr IntCommon

SECTION "IntTimer", ROM0[$0050]
    push hl
    ld hl, wHookTimer
    jr IntCommon

SECTION "IntSerial", ROM0[$0058]
    push hl
    ld hl, wHookSerial
    jr IntCommon

SECTION "IntJoypad", ROM0[$0060]
    push hl
    ld hl, wHookJoypad
    ; falls through into IntCommon

SECTION "IntCommon", ROM0[$0068]
IntCommon:
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    jp hl

DefaultIsr::
    pop hl
    reti

; ===========================================================================
SECTION "Main", ROM0[$0200]

Start:
    ; ---- capture the handover state before anything can disturb it --------
    ; `ld [nn],sp` touches no register, so the stack pointer can be recorded
    ; first; then every register pair goes on the stack and is copied off in
    ; one loop. This has to be the first thing the cartridge does.
    ld [wBootSP], sp
    push hl
    push de
    push bc
    push af
    ld hl, sp+0
    ld de, wBootRegs
    ld c, 8
.copyRegs
    ld a, [hl+]
    ld [de], a
    inc de
    dec c
    jr nz, .copyRegs
    ldh a, [rIF]
    ld [wBootIF], a

    ; ---- a known machine -------------------------------------------------
    di
    ld sp, $DFFF
    call LcdOff
    call ClearHooks
    call ClearWram
    call LoadFont
    call ClearScreen
    call DetectConsole

    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    ld a, 1
    ld [wSerialOK], a

    call Banner
    call RunAllAreas
    call FinalReport
    call ShowScreen

.forever
    jr .forever

; ---------------------------------------------------------------------------
ClearHooks:
    ld hl, wHookVBlank
    ld b, 5
.next
    ld a, LOW(DefaultIsr)
    ld [hl+], a
    ld a, HIGH(DefaultIsr)
    ld [hl+], a
    dec b
    jr nz, .next
    ret

ClearWram:
    ; everything from the text buffer down; the boot capture and hooks stay
    ld hl, wTextBuf
    ld bc, wModel + 32 - wTextBuf
.next
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .next
    ret

; ---------------------------------------------------------------------------
; The LCD is only ever switched off during VBlank: doing it mid-frame is
; documented as able to damage real hardware (Pan Docs, LCDC bit 7), and this
; cartridge is meant to be run on real hardware.
; ---------------------------------------------------------------------------
LcdOff::
    ldh a, [rLCDC]
    and LCDCF_ON
    ret z
.wait
    ldh a, [rLY]
    cp 145
    jr nz, .wait
    xor a
    ldh [rLCDC], a
    ret

LcdOn::
    ld a, LCDCF_ON | LCDCF_BLK01 | LCDCF_BGON
    ldh [rLCDC], a
    ret

; ---------------------------------------------------------------------------
; DetectConsole — the boot ROM leaves a different A on every console, and that
; is how software has always told them apart:
;   A = $01 DMG      A = $FF MGB (Pocket)     A = $11 Color
; and on a Color machine bit 0 of B separates an AGB from a CGB, because the
; AGB boot ROM ends with an extra `inc b`.
; Source: Pan Docs, "Power-Up Sequence" (CPU registers after boot).
; ---------------------------------------------------------------------------

DetectConsole:
    ld a, [BOOT_A]
    cp $01
    jr z, .dmg
    cp $FF
    jr z, .mgb
    cp $11
    jr z, .colour
    ld a, CONSOLE_UNK
    jr .store
.dmg
    ld a, CONSOLE_DMG
    jr .store
.mgb
    ld a, CONSOLE_MGB
    jr .store
.colour
    ; A Color console can shift the link port 32 times faster; the report is
    ; thousands of bytes and on a DMG the serial clock is what the run costs.
    ld a, %00000010
    ld [wSerialFast], a
    ld a, [BOOT_B]
    and $01
    ld a, CONSOLE_CGB
    jr z, .store
    ld a, CONSOLE_AGB
.store
    ld [wConsole], a
    ret

ConsoleName::
    ld a, [wConsole]
    add a
    ld e, a
    ld d, 0
    ld hl, .table
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ret
.table
    dw .dmg, .mgb, .cgb, .agb, .unk
.dmg db "DMG",0
.mgb db "MGB",0
.cgb db "CGB",0
.agb db "AGB",0
.unk db "UNKNOWN",0

; ---------------------------------------------------------------------------
Banner:
    ld hl, .screen
    call PrintLine
    ld a, SINK_SERIAL
    ld [wSinks], a
    ld hl, .rule1
    call PrintLine
    ld hl, .rule2
    call PrintLine
    ld hl, .docs
    call PrintStr
    ld hl, DocsBase
    call PrintStr
    ld hl, .docsPage
    call PrintLine
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    ld hl, .console
    call PrintStr
    call ConsoleName
    call PrintStr
    call PrintNewline
    ; The handover state, in the log rather than only in a verdict: it is what
    ; GB-BOOT judges, and a reader who disagrees with the judgement needs to
    ; see the evidence rather than take the cartridge's word for it.
    ld a, SINK_SERIAL
    ld [wSinks], a
    ld hl, .boot
    call PrintStr
    ld hl, .af
    call PrintStr
    ld a, [BOOT_A]
    call SerialByteHex
    ld a, [BOOT_F]
    call SerialByteHex
    ld hl, .bc
    call PrintStr
    ld a, [BOOT_B]
    call SerialByteHex
    ld a, [BOOT_C]
    call SerialByteHex
    ld hl, .de
    call PrintStr
    ld a, [BOOT_D]
    call SerialByteHex
    ld a, [BOOT_E]
    call SerialByteHex
    ld hl, .hlr
    call PrintStr
    ld a, [BOOT_H]
    call SerialByteHex
    ld a, [BOOT_L]
    call SerialByteHex
    ld hl, .sp
    call PrintStr
    ld hl, wBootSP
    call SerialWordHex
    ld hl, .iff
    call PrintStr
    ld a, [wBootIF]
    call SerialByteHex
    call PrintNewline
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    call PrintNewline
    ret
.screen db "GBSelfTest v1",0
.rule1  db "Every expectation below is either computed a second way on this",0
.rule2  db "machine or is a documented hardware constant. None came from an emulator.",0
.docs     db "Every code below is a heading on ",0
.docsPage db "gbselftest.md",0
.console db "console: ",0
.boot db "handover:",0
.af   db " AF=",0
.bc   db " BC=",0
.de   db " DE=",0
.hlr  db " HL=",0
.sp   db " SP=",0
.iff  db " IF=",0

; ===========================================================================
; The run
; ===========================================================================
; Each area entry is: dw name, dw code prefix, dw check list, dw docs page.
; The cursor lives in WRAM rather than on the stack so that a check routine
; cannot upset the walk however badly it misbehaves.
RunAllAreas:
    ld hl, AreaTable
    ld a, l
    ld [wAreaCur], a
    ld a, h
    ld [wAreaCur + 1], a
.nextArea
    ld a, [wAreaCur]
    ld l, a
    ld a, [wAreaCur + 1]
    ld h, a
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a
    or e
    ret z                   ; a null name pointer ends the table
    ld a, [hl+]
    ld [wPrefix], a
    ld a, [hl+]
    ld [wPrefix + 1], a
    ld a, [hl+]
    ld [wCursor], a
    ld a, [hl+]
    ld [wCursor + 1], a
    ld a, [hl+]
    ld [wDocPage], a
    ld a, [hl+]
    ld [wDocPage + 1], a
    ld a, [hl+]
    ld [wAreaBank], a
    ld a, l
    ld [wAreaCur], a
    ld a, h
    ld [wAreaCur + 1], a
    ld h, d
    ld l, e
    call RunAreaBody
    jr .nextArea

; ---------------------------------------------------------------------------
; Reporting an area and its checks.
; ---------------------------------------------------------------------------
RunAreaBody::
    ; HL = area name string
    push hl
    ld a, SINK_SERIAL
    ld [wSinks], a
    ld hl, .dashes
    call PrintStr
    pop hl
    call PrintLine
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    xor a
    ld [wAreaPass], a
    ld [wAreaFail], a
    ld [wAreaSkip], a
    call RunCheckList
    call AreaSummary
    ret
.dashes db "--- ",0

RunCheckList:
.next
    ld a, [wCursor]
    ld l, a
    ld a, [wCursor + 1]
    ld h, a
    ld a, [hl+]
    ld [wRt], a
    ld e, a
    ld a, [hl+]
    ld [wRt + 1], a
    or e
    ret z                   ; a null routine ends the list
    ld a, [hl+]
    ld [wNum], a
    ld a, [hl+]
    ld [wName], a
    ld a, [hl+]
    ld [wName + 1], a
    ld a, [hl+]
    ld [wExpl], a
    ld a, [hl+]
    ld [wExpl + 1], a
    ld a, l
    ld [wCursor], a
    ld a, h
    ld [wCursor + 1], a

    xor a
    ld [wHaveNums], a
    ld [wSkipFlag], a
    ld [wDetail], a
    ld [wDetail + 1], a

    ; Map the bank the check and its explanations live in, and leave it
    ; mapped through the reporting: a failure note is a pointer INTO that bank.
    ; Bank 0 in the table means the check is in the fixed bank and does its own
    ; switching, which is what the mapper checks have to do.
    ld a, [wAreaBank]
    or a
    jr z, .noBank
    ld [$2000], a
.noBank
    ld a, [wRt]
    ld l, a
    ld a, [wRt + 1]
    ld h, a
    ld de, .back
    push de
    jp hl
.back
    jr c, .failed
    ld a, [wSkipFlag]
    or a
    jr nz, .skipped
    ld a, [wAreaPass]
    inc a
    ld [wAreaPass], a
    ld hl, wPassed
    call IncWord
    call ReportOk
    jp .next
.failed
    ld a, [wAreaFail]
    inc a
    ld [wAreaFail], a
    ld hl, wFailed
    call IncWord
    call ReportFail
    jp .next
.skipped
    ld a, [wAreaSkip]
    inc a
    ld [wAreaSkip], a
    ld hl, wSkipped
    call IncWord
    call ReportSkip
    jp .next

IncWord::
    ld a, [hl]
    inc a
    ld [hl+], a
    ret nz
    ld a, [hl]
    inc a
    ld [hl], a
    ret

; ---------------------------------------------------------------------------
PrintCode:
    ; "GB-CPU-04" — the stable identifier, and the anchor on the docs page
    ld hl, .gb
    call PrintStr
    ld a, [wPrefix]
    ld l, a
    ld a, [wPrefix + 1]
    ld h, a
    call PrintStr
    ld a, '-'
    call PrintChar
    ld a, [wNum]
    call SerialDec2
    ret
.gb db "GB-",0

ReportOk:
    ld a, SINK_SERIAL
    ld [wSinks], a
    call PrintCode
    ld hl, .ok
    call PrintStr
    ld a, [wName]
    ld l, a
    ld a, [wName + 1]
    ld h, a
    call PrintLine
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    ret
.ok db " ok   ",0

ReportSkip:
    ld a, SINK_SERIAL
    ld [wSinks], a
    call PrintCode
    ld hl, .skip
    call PrintStr
    ld a, [wName]
    ld l, a
    ld a, [wName + 1]
    ld h, a
    call PrintLine
    ; A check that reports rather than judges has an observation to print, and
    ; a report with the observation missing is no use to the reader.
    ld a, [wHaveNums]
    or a
    jr z, .noNums2
    ld hl, .saw
    call PrintStr
    ld hl, wGot
    call SerialWordHex
    ld hl, .versus
    call PrintStr
    ld hl, wWant
    call SerialWordHex
    call PrintNewline
.noNums2
    ld hl, .arrow2
    call PrintStr
    ld a, [wDetail]
    ld l, a
    ld a, [wDetail + 1]
    ld h, a
    call PrintLine
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    ret
.skip db " skip ",0
.arrow2 db "      -> ",0
.saw    db "      saw ",0
.versus db "  against ",0

ReportFail:
    ld a, SINK_SERIAL
    ld [wSinks], a
    call PrintCode
    ld hl, .bad
    call PrintStr
    ld a, [wName]
    ld l, a
    ld a, [wName + 1]
    ld h, a
    call PrintLine
    call RememberFailure

    ld a, [wHaveNums]
    or a
    jr z, .noNums
    ld hl, .got
    call PrintStr
    ld hl, wGot
    call SerialWordHex
    ld hl, .want
    call PrintStr
    ld hl, wWant
    call SerialWordHex
    call PrintNewline
.noNums

    ld hl, .arrow
    call PrintStr
    ld a, [wDetail]
    ld l, a
    ld a, [wDetail + 1]
    ld h, a
    or l
    jr nz, .haveNote
    ld a, [wExpl]
    ld l, a
    ld a, [wExpl + 1]
    ld h, a
.haveNote
    call PrintLine

    ; where to read about it: the check's own code is the anchor
    ld hl, .arrow
    call PrintStr
    ld hl, DocsBase
    call PrintStr
    ld a, [wDocPage]
    ld l, a
    ld a, [wDocPage + 1]
    ld h, a
    call PrintStr
    ld a, '#'
    call PrintChar
    call PrintCodeLower
    call PrintNewline

    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    ret
.bad  db " FAIL ",0
.got  db "      got $",0
.want db "  want $",0
.arrow db "      -> ",0

; Markdown heading anchors are lowercase, so the printed URL has to be too.
PrintCodeLower:
    ld hl, .gb
    call PrintStr
    ld a, [wPrefix]
    ld l, a
    ld a, [wPrefix + 1]
    ld h, a
.next
    ld a, [hl+]
    or a
    jr z, .done
    add $20                 ; the letters here are all uppercase ASCII
    call PrintChar
    jr .next
.done
    ld a, '-'
    call PrintChar
    ld a, [wNum]
    call SerialDec2
    ret
.gb db "gb-",0

DocsBase::
    db "https://github.com/Alchemy86/TerminalGB/blob/main/docs/",0

; Remember the CODE of a failing check -- the area prefix and the number --
; so the screen can list them at the end. Ten slots: the screen is eighteen
; rows and a machine broken enough to fail more than ten checks is not going to
; be diagnosed from a list anyway, it is going to be diagnosed from the log.
DEF FAIL_SLOTS EQU 10

RememberFailure:
    ld a, [wFailCount]
    cp FAIL_SLOTS
    ret nc
    ld e, a
    ld d, 0
    ld hl, wFailList
    add hl, de
    add hl, de
    add hl, de              ; three bytes an entry
    ld a, [wPrefix]
    ld [hl+], a
    ld a, [wPrefix + 1]
    ld [hl+], a
    ld a, [wNum]
    ld [hl], a
    ld a, [wFailCount]
    inc a
    ld [wFailCount], a
    ret

; ---------------------------------------------------------------------------
AreaSummary:
    ld a, SINK_SCREEN
    ld [wSinks], a
    ld a, [wPrefix]
    ld l, a
    ld a, [wPrefix + 1]
    ld h, a
    call PrintStr
    ld hl, .pad
    call PrintStr
    ld a, [wAreaPass]
    call PrintDec3
    ld a, '/'
    call PrintChar
    ld a, [wAreaPass]
    ld b, a
    ld a, [wAreaFail]
    add b
    call PrintDec3
    ld a, [wAreaFail]
    or a
    jr nz, .bad
    ld hl, .ok
    jr .tail
.bad
    ld hl, .fail
.tail
    call PrintStr
    call PrintNewline
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    call ShowScreen
    ret
.pad  db " ",0
.ok   db " ok",0
.fail db " FAIL",0

; ---------------------------------------------------------------------------
FinalReport:
    ld a, SINK_SERIAL
    ld [wSinks], a
    call PrintNewline
    ld hl, .cov
    call PrintLine
    ld a, 1
    ld [$2000], a           ; the coverage statement lives in bank 1
    ld hl, CoverageText
    call PrintStr
    call PrintNewline

    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    call PrintNewline
    ld hl, .total
    call PrintStr
    ld hl, wPassed
    call PrintWordDec
    ld a, '/'
    call PrintChar
    call TotalChecks
    ld hl, wScratch
    call PrintWordDec
    ld hl, .checks
    call PrintStr
    ld a, [wSkipped]
    ld b, a
    ld a, [wSkipped + 1]
    or b
    jr z, .noSkips
    ld hl, .skipped
    call PrintStr
    ld hl, wSkipped
    call PrintWordDec
    ld hl, .skippedTail
    call PrintStr
.noSkips
    call PrintNewline

    ; The cost line, twice, because the two sinks are not the same width. The
    ; serial wording is what a host greps and does not change; the screen is
    ; twenty columns, and the long form wrapped mid-word -- "sen" on one row
    ; and "t 6949 B" on the next -- which is the first thing anybody sees.
    ;
    ; Both lines quote the same number, snapshotted here: the counter is live,
    ; and printing the serial line moves it on by the length of its own
    ; wording, which would leave the screen and the log disagreeing about the
    ; same run by twenty-two bytes.
    ld a, [wSerialSent]
    ld [wScratch + 90], a
    ld a, [wSerialSent + 1]
    ld [wScratch + 91], a

    ld a, SINK_SCREEN
    ld [wSinks], a
    ld hl, wFrames
    call PrintWordDec
    ld hl, .framesShort
    call PrintStr
    ld hl, wScratch + 90
    call PrintWordDec
    ld hl, .sentTail
    call PrintStr
    call PrintNewline

    ld a, SINK_SERIAL
    ld [wSinks], a
    ld hl, .frames
    call PrintStr
    ld hl, wFrames
    call PrintWordDec
    ld hl, .framesTail
    call PrintStr
    ld hl, wScratch + 90
    call PrintWordDec
    ld hl, .sentTail
    call PrintStr
    call PrintNewline
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a

    ld a, [wFailed]
    ld b, a
    ld a, [wFailed + 1]
    or b
    jr nz, .failed
    ld hl, .pass
    call PrintLine
    ret
.failed
    call ScreenFailures
    ld hl, .fail
    call PrintLine
    ret
.cov    db "--- coverage",0
.total  db "TOTAL ",0
.checks db " checks",0
.skipped db ", ",0
.skippedTail db " skipped",0
.frames db "cost ",0
.framesTail db " frames, sent ",0
.framesShort db " frames ",0
.sentTail   db " B",0
; The last line is what a host greps for. Blargg's convention, deliberately:
; every existing Game Boy test runner already understands these two words.
.pass   db "Passed",0
.fail   db "Failed",0

TotalChecks:
    ld a, [wPassed]
    ld c, a
    ld a, [wPassed + 1]
    ld b, a
    ld a, [wFailed]
    add c
    ld c, a
    ld a, [wFailed + 1]
    adc b
    ld b, a
    ld a, [wSkipped]
    add c
    ld [wScratch], a
    ld a, [wSkipped + 1]
    adc b
    ld [wScratch + 1], a
    ret

; ScreenFailures — the codes, on the screen, two to a row, and where to read
; about them. The serial log already carries the full explanation and a URL per
; failure; twenty columns cannot, and a code somebody can look up is far more
; use there than half a sentence of prose.
ScreenFailures:
    ld a, SINK_SCREEN
    ld [wSinks], a
    ld hl, .hdr
    call PrintLine
    ld a, [wFailCount]
    or a
    jr z, .done
    ld b, a
    ld c, 0                 ; how many codes are already on this row
    ld hl, wFailList
.next
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a
    ld a, [hl+]
    push hl
    push bc
    ld [wScratch + 94], a
    ld hl, .gb
    call PrintStr
    ld h, d
    ld l, e
    call PrintStr
    ld a, '-'
    call PrintChar
    ld a, [wScratch + 94]
    call PrintDec2
    pop bc
    ; Two nine-character codes and a space is nineteen columns; a third would
    ; wrap and split a code across two rows, which is the one thing a code
    ; must never do.
    inc c
    ld a, c
    cp 2
    jr c, .space
    ld c, 0
    call PrintNewline
    jr .row
.space
    ld a, ' '
    call PrintChar
.row
    pop hl
    dec b
    jr nz, .next
    ld a, c
    or a
    jr z, .listed
    call PrintNewline
.listed
    ld hl, .where
    call PrintLine
.done
    ld a, SINK_SCREEN | SINK_SERIAL
    ld [wSinks], a
    ret
.hdr   db "failed:",0
.gb    db "GB-",0
.where db "-> docs/CHECKS.md",0

; ---------------------------------------------------------------------------
; The restart vector the timing check calls. It is only here so that `RST $38`
; has somewhere to go and come back from, which is what lets its cost be
; measured against the published four machine cycles.
; ---------------------------------------------------------------------------
SECTION "Rst38", ROM0[$0038]
    ret
