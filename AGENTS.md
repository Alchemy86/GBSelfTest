# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge:
build, test, release, architecture, and sharp-edge notes that should travel with
the code.

## Building and running

- RGBDS is not assumed to be on the path. `tools/fetch-rgbds.sh` builds the pinned
  version into `.rgbds/`, then `make RGBDS=$PWD/.rgbds`.
- **Do not export `RGBDS` when running `tools/run-sameboy.sh`.** SameBoy's own
  Makefile reads `RGBDS` as a *path prefix* and will try to run
  `/your/dir/rgbdsrgbgfx`. Put `.rgbds` on `PATH` instead; the runner already
  handles the boot ROMs from there.
- `tools/run-sameboy.sh`, `tools/run-terminalgb.sh` and `tools/run-peanut.sh` each
  fetch, pin and build their own emulator into a gitignored directory. Nothing is
  vendored, and each pins a revision so the scoreboard is reproducible.

## The documentation is generated, and CI enforces it

Four artefacts are produced by running the thing, never by editing:

| artefact | producer | guard |
|---|---|---|
| `docs/CHECKS.md` | `tools/gen-docs.py` | `--check` in CI |
| `docs/screenshots/*` | `tools/screenshots.sh` | — |
| `docs/scoreboard.md` + the README table | `tools/scoreboard.sh --write` | `tools/check-readme.py` |
| the README's check count and failure excerpt | the build and a real run | `tools/check-readme.py` |

If a number in the README changes, it is because a run said so. Regenerate; do not
retype.

## The screen and the serial log are different products

`wSinks` masks the two independently, and they are not interchangeable:

- The **serial log** is the machine-readable one and its wording is what hosts
  grep. `Passed`/`Failed` on the last line is Blargg's convention and must stay.
- The **screen is twenty columns by eighteen rows** and wraps mid-word without
  complaining. Anything printed to both sinks has to fit in twenty columns, or it
  needs a screen-only short form (see the cost line in `FinalReport`).
- The font covers ASCII `$20..$7F` only; `ScreenChar` turns anything else into
  `?`. Adding a character outside that range to a screen-bound string prints a
  question mark rather than failing to build.
- The failure list on screen carries **codes**, not titles: three bytes an entry in
  `wFailList` (area prefix pointer, then the number). Ten slots.

## The fixed bank is full, and what may leave it

`ROM0` holds the print code, the mapper checks (which cannot sit in a bank they
switch away from), the vectors and the registry, and it is close to its 16 KiB.
Two things have already moved out and the rule for moving a third is the same:

- **A check's name and its one-line explanation may live in the area's own
  bank.** `RunCheckList` maps the area's bank before the check runs and *leaves
  it mapped through the reporting*, which is the rule that already lets a
  failure note be a pointer into that bank. The CPU area's prose is in bank 1 on
  exactly this licence. What may **not** move is an area's own name (printed
  before the bank is mapped), its code prefix or its documentation page: the
  prefix is read again at the very end of the run when the failure list is
  spelled back out, and by then the bank is whatever the last area left.
- **`FontData` is in bank 1**, so `LoadFont` takes `A` = the bank to restore on
  the way out. Forget that and a caller in a switchable bank is returned into
  somebody else's code — `GB-MEM-04` reloads the font mid-run and is the one
  that finds it. The symptom is the run stopping dead with no message.

## Measuring a timer edge: control the phase, or the run decides the verdict

`GB-CYC-07` shipped once in a form that zeroed `TIMA` and *then* wrote `$FF04`.
Three cycles separate those two writes, and whether the tapped bit falls inside
them — and whether the `$FF04` write is itself a falling edge, which is
`GB-TIM-06` — depends on the counter phase the check was entered in. That phase
is set by how much code ran above it, so the verdict was decided by which checks
failed earlier rather than by the machine: it passed on one emulator and failed
on SameBoy, and swapping the earlier failures swapped the answer.

**Restart the counter first and zero `TIMA` after it**, and sweep more than one
delay rather than sampling once. Anything that reads a timer edge and does not do
both is measuring the rest of the run.

## A hundred checks in one session is a shape no single test ROM has

`GB-DMA-06` found a real bug in TerminalGB on the day it was written, and the
bug was invisible to every public suite the emulator gates on — thousands of
rows across Gambatte, Mooneye, Mealybug, SameSuite and the c-sp aggregation
were byte-identical either way. It was a flag the PPU kept about a running
object transfer, cleared on one of the two paths that can notice the transfer
has ended and not the other; once it latched, the object scan never read object
memory again for the rest of the run.

A suite of short ROMs cannot see that. Each one boots, measures one thing and
stops, so a latch that needs a transfer to end on an instruction boundary and a
scan to follow it never gets the chance. This cartridge runs a hundred checks
back to back on one machine, and that is the shape that catches it.

**So when a check is written, run the whole cartridge and read the total, not
just that check's line.** A new check that passes in isolation and moves an
unrelated area's verdict has found something.

## SameBoy's boot ROMs here are SameBoy's own

`tools/run-sameboy.sh` builds SameBoy's `BootROMs/`, which are open-source
*re-implementations*, not Nintendo's. They reproduce the register state exactly
and take their own number of cycles to get there, so anything whose value is a
function of how long the boot ROM ran is not the silicon's figure: the system
counter hands over `$BD` where hardware hands over `$AB`. `GB-BOOT-06`
deliberately asserts only that the counter is not zero for this reason. Any
future check tempted to assert a published boot constant should ask first
whether it is a fact about the console or about the boot ROM.

## Bank 3 is as tight as ROM0, and the linker's error names an arbitrary victim

Adding one moderate check to bank 3 (PPU, DMA, APU, BOOT, SER) overflows the
bank, and rgblink's `Unable to place "X" in bank $03` names whichever *later*
section happened to lose the fitting race — trimming content and relinking
made the named victim change (`MoreBoot2`, then `MoreSer`) with no reliable
relationship to how close the fix was. Almost all of the added weight was
`FailNote` string text, not code; keep a new bank-3 check's failure prose in
the ~100-150 character range the shortest existing ones already use, and
expect to iterate by shrinking and relinking rather than by computing a byte
budget in advance.

## A loosely-timed conflict check finds the drop, not the AND

`GB-DMA-07`'s own comment states this, but it is worth repeating here: Pan
Docs and Gambatte's own hwtest ROMs establish that a monochrome console's
work-RAM-sourced OAM DMA conflict can be a bitwise AND of the primed and
written bytes, given the exact cycle alignment Gambatte's `push` at a chosen
`SP` produces. A cartridge check that primes a byte, starts the transfer and
writes a plain store *sometime* during its 640 T-cycle window — the only kind
of timing a self-test cartridge can produce without replicating that exact
alignment — gets the write **dropped** (the primed byte survives) on every
console, confirmed against SameBoy on every model it runs. `GB-DMA-07` checks
that alignment-independent half only. Do not read a check that finds "dropped"
rather than "ANDed" as contradicting the AND finding; it is testing a coarser
question, honestly, rather than a finer one on weak evidence.

## `tools/run-terminalgb.sh`'s pin will read as regressions it did not cause

`TERMINALGB_REF` in that script is old enough to predate a fair amount of
accuracy work on the other side (its own OAM-DMA bus-sharing model among it),
so the scoreboard's TerminalGB rows will keep scoring below SameBoy's on
checks a current TerminalGB build passes outright. That is the pin, not a
finding about TerminalGB; re-pinning is a deliberate action (it moves every
row in the scoreboard, not just the ones a given change touched) and should
land as its own commit with a fresh `tools/scoreboard.sh --write` run, not as
a side effect of adding a check.

## The brand

`docs/brand/generate.py` is the only source of truth for the logo and icon. Edit
the generator, never the SVGs, and re-render `docs/brand/preview/*` in the same
commit. Every letterform is an original stroked skeleton path — no font is
embedded, subset or traced — which is what keeps the files free of any third-party
licence. It is deliberately the same alphabet, palette and panel as TerminalGB's
and AtlasGB's marks; only the motif differs. See `docs/brand/README.md`.
