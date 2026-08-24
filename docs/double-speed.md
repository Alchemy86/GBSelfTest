# Double speed — what a cartridge can and cannot check

This page is a survey, written before any check in it existed. It answers one
question: of everything "double speed" means on Color hardware, how much of it
can a self-checking cartridge with no framebuffer actually test?

## Why this exists

TerminalGB commit `c575bb4` fixed a real bug: on Color hardware in double
speed, the emulator's `LCDC` write-commit logic held the BG-map-select bit one
dot behind the rest of the register — a stagger calibrated entirely against
Mealybug's single-speed-only ROMs. A double-speed machine cycle is only two
dots wide (the PPU's dot clock is fixed; only the CPU's clock doubles), so the
stagger consumed the whole machine cycle and the write committed a dot too
early. It cost three outright FAILs and left seven rows measurably wrong
against two independent test suites (AGE test roms and Gambatte's own
hwtests), and it went unmeasured for as long as it did because **nothing
anywhere — not Mealybug, not this cartridge — had ever exercised double speed
at all.** `rKEY1` was defined in `hardware.inc` and that was the entire extent
of this project's own coverage.

That is exactly the class of bug this cartridge exists to catch: a hundred
checks in one session, on real or accurate hardware, finding what a suite
calibrated on a narrower slice of the state space never ran into. So the
obvious next question is whether *this* bug — or the class it belongs to —
is something a cartridge with no way to see a pixel could have found.

## The three things double speed actually changes

Pan Docs ("KEY1 Register") is specific about which parts of the machine speed
up when double speed is engaged and which do not:

* **Speeds up:** the CPU, the timer and divider registers, the serial port,
  and OAM DMA.
* **Stays at normal speed:** the LCD/PPU (both its dot clock and its
  interrupt timing), HDMA transfers to VRAM, and all sound timings and
  frequencies.

Everything below follows from that split, and from the fact that a
self-checking cartridge's only two tools are **timing** (how many machine
cycles something takes) and **readback** (what a register or a documented
model says a value should be).

## What is testable — and is now tested

### 1. The switch itself exists and works (`GB-CYC-09`)

Before this cartridge, nothing had ever written to `rKEY1` or executed the
documented `STOP` sequence for a speed change. Whether the switch engages at
all — bit 0 armed, `STOP` executed, bit 7 reporting the new speed on the way
out — is directly readable and was previously unchecked.

### 2. The CPU and the timer speed up *together* (`GB-CYC-09`)

Pan Docs lists "Timer and Divider Registers" as one of the things that speeds
up alongside the CPU, not independently of it. If an implementation doubled
the CPU but left the timer's own tick rate alone (or the reverse), a batch of
instructions timed against `TIMA` the way every other check in `checks_time.asm`
already does would read a *different* number of ticks in double speed than in
single speed. It must read the **same** number, because both clocks are
driven off the same doubled source. This is a direct, zero-tolerance
assertion, exactly as timing-table checks already work elsewhere in this
cartridge — it needed no new technique, only a machine willing to switch
speed.

### 3. The PPU's dot clock does *not* speed up with the CPU (`GB-PPU-07`)

This is the closest a cartridge with no framebuffer can get to the actual bug
class behind `c575bb4`. `GB-PPU-07` already establishes, at single speed, that
an `SCX` of 4 costs the fetcher exactly one machine cycle: four dots of
penalty, and four dots to the cycle. A double-speed machine cycle is two dots
wide, so the *same* four-dot penalty — a fact about the PPU's dot clock, which
does not speed up — must now cost **two** machine cycles, not one. That is
exactly what an emulator that scaled the PPU's own clock with the CPU's would
get wrong, and it is measured with the same STAT-interrupt delay-sled
technique every other `GB-PPU-0*` check already uses, just run once more after
switching speed.

This was verified independently before it was trusted: a standalone,
throwaway diagnostic ROM (not part of the cartridge, built only to check the
arithmetic) measured the same SCX=4 delta in both speeds on two unrelated
implementations, SameBoy and TerminalGB, and both agreed the delta doubles
from 1 machine cycle to 2. The check encodes exactly that fact.

## What is *not* testable, and why

**The specific bug in `c575bb4` — a one-dot stagger on the BG-map-select bit
of an `LCDC` write, mid-scanline, in double speed — cannot be checked by this
cartridge, and no amount of cleverness with STAT timing changes that.**

The reason is structural, not a matter of not having tried hard enough. The
bug's *only* observable effect is **which of two already-equal-cost data
sources the fetcher reads from at a given dot** — the BG tile map at $9800 vs
$9C00, or (for the sibling tile-data-select bit) $8000 vs $8800. Committing
the bit one dot late does not change:

* how long mode 3 takes (both maps cost the fetcher the same number of dots
  to read from; the bug is about *which* address is read, not how many
  cycles the read costs),
* any CPU-readable register (`LCDC` reads back the byte you wrote it,
  immediately, regardless of when the PPU internally treats it as having
  changed — there is no bus conflict on `LCDC` reads the way there is on OAM
  DMA), or
* any interrupt timing, DMA behaviour, or anything else this cartridge's
  existing timing techniques can see.

The only way to observe it is to look at which tile actually got drawn — a
pixel comparison against a reference image, which is precisely the class of
test this project has never done and does not do here (see the cartridge's
own printed coverage statement: "the composited picture... needs a host
holding a reference image"). Mealybug's own ROMs are built for exactly this,
and Mealybug is the correct tool for this specific bug; the fact that it
missed this one is because none of its ROMs run in double speed, not because
pixel comparison itself is the wrong approach.

**This generalizes.** Any future bug in this family — a commit-timing
constant for *any* PPU register, in *either* speed, that only changes which
already-equally-expensive data source a dot samples from — is invisible to a
serial-log cartridge for the same reason. What this cartridge *can* catch is
the coarser, but real, class of bug where the PPU's dot clock is wrongly
coupled to the CPU's clock at all (checked here), and whether the speed
switch mechanism itself works (checked here). It cannot discriminate a
correct one-dot-late commit from a correct one-dot-early one, because neither
one costs a cycle or changes a byte anywhere a cartridge can read.

## Other double-speed facts, deliberately left untested

A few more things speed up or don't in double speed and were considered and
set aside, to be honest about the boundary rather than silently missing them:

* **OAM DMA** is listed as running at double speed. It transfers a fixed 160
  bytes over a fixed 640 T-cycle window regardless of CPU speed in either
  case (the transfer's own duration is what "speeds up" — half as many
  *real-time* microseconds, not a different byte count), so the existing
  `GB-DMA-0*` checks' constants do not change and there is nothing new here
  worth a dedicated double-speed variant without also building a whole
  parallel timing harness for DMA. Not attempted.
* **HDMA (general-purpose/HBlank VRAM DMA)** is documented as staying at
  *normal* speed even while everything else doubles — the interesting
  opposite case to OAM DMA. This cartridge has no HDMA registers defined at
  all (`hardware.inc` has never carried `$FF51`-`$FF55`) and adding a whole
  new checked subsystem was out of scope for this pass. A genuinely valuable
  future check: measure an HDMA block's cost in machine cycles at both
  speeds and confirm it does *not* halve, unlike an OAM DMA's would. Flagged
  for whoever picks it up next.
* **Serial** speeding up with the CPU is already partially reflected in this
  cartridge's own design: `wSerialFast` already distinguishes a Color
  console's faster serial clock from a DMG's, though that is about the
  Color-vs-DMG difference in general, not specifically about double speed.
  Not extended here.

## Verification

Both new/changed checks were confirmed to actually discriminate, not just to
report a plausible-looking pass, by deliberately breaking the behaviour they
claim to test in TerminalGB (a local, uncommitted, reverted edit) and
confirming the check FAILs with the expected message:

* **`GB-CYC-09`** — forcing `switch_speed()` to never toggle `gbspeed` (so
  `STOP` with `KEY1` bit 0 set has no effect) makes the check FAIL with "STOP
  with KEY1 bit 0 set did not switch to double speed: bit 7 still read single
  afterwards". Reverted afterwards; the real switch works and the check
  passes on SameBoy (DMG through AGB, correctly skipping below Color), on
  TerminalGB (both picture modes), and correctly skips on Peanut-GB and every
  monochrome console.
* **`GB-PPU-07`**'s double-speed half — forcing the PPU's per-dot step to stay
  at 4 dots per machine cycle in double speed instead of halving to 2 (the
  general shape of the bug class this check targets, not the specific
  `c575bb4` stagger, which as explained above cannot be targeted this way at
  all) makes the check FAIL with "one cycle in double speed, not two: a cycle
  is half as wide". Reverted afterwards.

A bug in the cartridge's own first draft was also found this way, not by
reasoning: the double-speed branch of `GB-PPU-07` originally called
`FlipSpeed` to return to single speed *before* comparing the measured delta,
and `FlipSpeed` clobbers the accumulator on its way through the documented
`STOP` sequence — so the check was silently comparing a leftover register
value instead of the measurement, and always reported the same wrong number
regardless of what was actually true. It was caught because the check FAILed
in a way that didn't match the independently-measured expectation on two
unrelated emulators, which is exactly the kind of cross-check this project's
independence rule exists for. Fixed by saving the delta in a register `Flip
Speed` does not touch before calling it again.

## A build-time finding, unrelated to any check's logic

Investigating this also surfaced that the cartridge's ROM header did **not**
set the CGB-compatibility flag (`rgbfix -c`). Without it, real Color hardware
(and any accurate emulator) runs the cartridge in DMG-compatibility mode,
where `KEY1` and double speed do not exist at all — every check in this file
would have silently skipped on every console, forever, having never actually
run. `Makefile`'s `FIXFLAGS` now passes `-c` (backward-compatible, not `-C`
CGB-only, since the DMG and MGB checks still have to run). Confirmed by
rebuilding with and without the flag and observing `GB-CYC-09` and
`GB-PPU-07` go from permanently skipping to actually running on every
Color-capable console tested (SameBoy CGB-E and AGB, TerminalGB both picture
modes), with zero change to any other check's pass/fail/skip status on any
console.
