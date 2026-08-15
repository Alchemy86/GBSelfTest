# GBSelfTest

**A Game Boy cartridge that tests the machine it is running on and tells you
what is wrong.**

One file. Boot it anywhere a ROM boots — an emulator on a phone, a browser
build, a homebrew port, a real console with a flash cart — and it runs a suite
unattended and reports the verdict two ways: as text on the screen, and as the
same text over the link port so a host can capture it with nobody watching.

```
GBSelfTest v1
console: DMG

--- CPU: instruction behaviour and flags
GB-CPU-01 ok   ADD and ADC, against a counter-built adder
...
--- PPU: timing and the rendering fingerprint
GB-PPU-08 FAIL objects on a line lengthen mode 3
      got $0000  want $000F
      -> ten objects on a line did not lengthen mode 3. Each one stops the
         background fetcher for at least six cycles while its own row is
         fetched; a renderer that draws the line in one go and charges a fixed
         172 cycles reports no penalty at all
      -> https://github.com/Alchemy86/TerminalGB/blob/main/docs/gbselftest.md#gb-ppu-08

TOTAL 71/76 checks
cost 98 frames, sent 7191 B
Failed
```

Every check has a **stable code**. It prints with the failure, it is the anchor
on a documentation page, and it never changes meaning. That is the part nothing
else in the ecosystem does: other suites tell you a number, this one tells you
which behaviour is missing and where to read about it.
See [`docs/CHECKS.md`](docs/CHECKS.md) for all of them.

## Why this exists

Testing a Game Boy emulator today means assembling a pile of other people's
work — Blargg's ROMs (and `cpu_instrs` alone is eleven separate cartridges),
Mooneye's suite, SameSuite, Mealybug's reference images — each with its own
conventions and each needing a host to interpret it. That is the right way to
get depth, and this cartridge is not a replacement for any of it.

What did not exist was the **first thing you run**: one file that boots, sweeps
broadly, and explains itself. This is that.

## The rule that makes the verdict worth anything

> **No check's expected value may be a number measured from an emulator.**

Every expectation here is either

* **computed a second, independent way on the machine itself** — the adder is
  checked against a counter built from `INC HL`, which sets no flags at all and
  goes through a different unit; the logic operations are checked against De
  Morgan's law; the rotates are checked by the fact that eight of them are the
  identity; `DAA` is checked against decimal arithmetic done a digit at a
  time; or
* **a documented constant that is a fact about the hardware** — a register's
  read-back mask, the published cycle count of an instruction, the 456 cycles
  in a scanline.

A behaviour that cannot be checked either way does not go in. It is listed as
untested instead, with the reason, in the coverage statement the cartridge
prints at the end of every run.

The other half of that rule is that the cartridge is **validated against
implementations nobody here wrote**. It is developed against three at once, and
a disagreement is investigated before anything ships — two of the checks in
this repository were wrong and were found that way, not by reasoning.

| implementation | result |
|---|---:|
| SameBoy (DMG, MGB) | 87 / 87 |
| SameBoy (CGB-E, AGB) | 84 / 87, 3 skipped |
| TerminalGB, per-dot renderer | 86 / 87 |
| TerminalGB, whole-scanline renderer | 80 / 87 |
| Peanut-GB | 64 / 87 |

That spread is the property this cartridge exists to have. A suite everybody
passes measures nothing.

## How long it takes

Under **ten seconds** on a Game Boy, measured end to end, and the checks are
not what costs it: the run waits on the display for 118 frames (2.0 s) and
spends the rest shifting the report out of the link port, which on a Game Boy
runs at 8192 bits per second. The report prints its own cost on the
last line but one:

```
cost 118 frames, sent 6760 B
```

A host that only wants the verdict can stop as soon as it sees `Passed` or
`Failed`, which is what the reference adapter does. A host that wants the
report has to pay for it, and that is the right trade: the explanations are
the product.

## What it checks

Eleven areas, 87 checks. The full list with explanations is
[`docs/CHECKS.md`](docs/CHECKS.md).

| area | what it is about |
|---|---|
| `CPU` | instruction results and every flag, by model and by identity |
| `CYC` | instruction and memory timing against the published cycle counts |
| `TIM` | the divider and the timer, including the write that clocks the timer |
| `INT` | the flags, `EI`'s delay, priority, the `HALT` defect, dispatch cost |
| `MEM` | the memory map: echo RAM, high RAM, ROM writes, sizes |
| `PPU` | display timing, and the **rendering fingerprint** — see below |
| `DMA` | the object transfer: what it copies and how long it takes |
| `APU` | sound registers, the length counter, the converters |
| `MBC` | banking, the bank-zero translation, cartridge RAM gating |
| `BOOT` | the state the boot ROM handed over at `$0100` |
| `SER` | the link port's own registers and transfers |

### The rendering fingerprint

A cartridge cannot see the picture: the display streams pixels to the panel and
keeps none of them, which is why the suites that judge pixels ship photographs
and need a host.

But rendering leaves a measurable trace. **Mode 3 lasts exactly as long as the
fetcher takes**, and the fetcher takes longer when there is more to draw — a
fine scroll offset, an object on the line, the window starting. So the
cartridge lays out a scene whose cost is documented and measures how long mode 3
actually took. That is a real test of rendering behaviour with no reference
image anywhere in it, and in practice it is the most discriminating thing here:
it is what separates a renderer that draws a whole line at once from one that
models the fetcher.

The measurement works like this. The coincidence interrupt is armed on one
scanline, and the handler runs a variable number of `NOP`s before reading
`STAT` once; a binary search over that delay finds the exact machine cycle at
which the mode changes. The delay from the interrupt to the first `NOP` is
unknown and does not matter, because every result is the **difference** between
two such edges and the unknown cancels. The floor is four dots, because a
machine cycle is four dots and the processor cannot look between them.

## Building

Needs [RGBDS](https://rgbds.gbdev.io) and nothing else.

```sh
make                          # -> dist/gbselftest.gb
make RGBDS=/opt/rgbds-1.0.3   # if the tools are not on the path
make check                    # build twice and confirm the ROM is identical
```

The exact version releases are built with is pinned in
[`tools/fetch-rgbds.sh`](tools/fetch-rgbds.sh), and CI uses that script, so a
release is reproducible from source.

The built ROM is committed to [`dist/`](dist/) so that using it needs no
toolchain at all.

## Running it

Anywhere. On a real console, put it on a flash cart and read the screen. In an
emulator, load it. For a host that wants the text, capture the link port —
which is what every Game Boy test-ROM runner already does for Blargg's ROMs.

Against an implementation you did not write:

```sh
tools/run-sameboy.sh dmg          # fetches and builds SameBoy, prints the report
```

## The cartridge

MBC1, four ROM banks, 8 KiB of cartridge RAM and **no battery** — so it can
check its own mapper and its own cartridge RAM, and it can never leave a save
file beside itself. Each switchable bank begins with its own number, which is
how the mapper checks tell which bank they actually got: the answer comes out
of the cartridge's own contents rather than from anything an emulator says
about itself.

## Licence and contents

MIT — see [`LICENSE`](LICENSE). Everything here is original: the font is drawn
for this cartridge, the register definitions are written out from Pan Docs
(which is public domain), and there is no third-party source, no boot-ROM
extract and no game data of any kind. That is deliberate: the point is that
anybody can take it, ship it, and modify it.

## Contributing a check

A check earns its place by being all four of these:

1. **Self-verifying.** Its expected value is computed on the machine or is a
   documented hardware constant. If you had to measure it on an emulator to
   find out what it should be, it does not go in.
2. **Discriminating.** A careful implementation and a rough one give different
   answers. Everything passing it is a check that measures nothing.
3. **Explained.** One line saying what behaviour is missing, in hardware terms,
   that an author can act on. A check that only says `FAIL` is half a check.
4. **Bounded.** It cannot hang. Anything that waits for an event waits with a
   limit, and anything that waits for an event a broken machine might never
   deliver checks first that the machine can deliver it, and skips if not.

Then run it against at least one implementation nobody here wrote, and if it
disagrees, find out who is right before shipping.
