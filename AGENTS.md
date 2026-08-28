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

## Double speed needs the CGB header flag, or every double-speed check silently skips forever

`FIXFLAGS` did not pass `rgbfix -c` until GB-CYC-09/GB-PPU-07 needed it. Without
it, the ROM's header byte at `$0143` is `$00`, and a real Color console (or an
accurate emulator) boots a cartridge with no CGB flag into **DMG compatibility
mode**, where `KEY1` and double speed do not exist at all (Pan Docs, "CGB
Registers": KEY1 is "CGB Mode only"). `wConsole` still correctly reports CGB —
`DetectConsole` reads the boot handover registers, which don't care about the
cartridge's own header — so a double-speed check written the usual way
(`cp CONSOLE_CGB` / `cp CONSOLE_AGB`) builds, links, and *skips on every run,
on every console, forever*, and nothing about that looks wrong until you
specifically check whether it ever ran. `-c` (not `-C`) is what fixes it:
backward-compatible, since the DMG and MGB checks still have to run on the
same ROM. Confirmed by building both ways and watching GB-CYC-09/GB-PPU-07
go from permanently-skip to actually-run with zero change to any other
check's verdict on any console.

## `FlipSpeed` clobbers `A`; save what you're comparing before calling it again

`checkutil.asm`'s `FlipSpeed` runs the documented STOP-based speed-switch
sequence and, like every subroutine in this file, makes no promise about
which registers survive it — it loads `A` repeatedly on the way through
`LcdOff` and the `KEY1` write. A check that measures something into `A`, then
calls `FlipSpeed` to return to the starting speed, then compares against `A`
is comparing `FlipSpeed`'s own leftover value, not the measurement — and it
does so silently, producing a plausible, *constant* wrong number instead of a
crash. This shipped once in GB-PPU-07's double-speed half and was only caught
because the wrong number ($1) disagreed with an independent measurement on
two unrelated emulators (SameBoy and TerminalGB) that had already established
the right one ($2). Save into a register `FlipSpeed` doesn't touch (`B`, `C`,
`D`, `E`, `H`, `L` are all safe) before calling it a second time.

## A PPU write-commit timing bug can be a pure pixel, and this cartridge cannot see it

Not every PPU inaccuracy leaves a measurable trace. TerminalGB's `c575bb4`
(a CGB `LCDC` write-commit stagger that didn't fit inside a double-speed
machine cycle) changes *which* VRAM data source the fetcher reads from at a
given dot — not how long anything takes, not any readable register, nothing
DMA or interrupt related. The existing STAT-sled technique that every
`GB-PPU-0*` check uses measures *durations*; it has nothing to say about
*content*. GB-PPU-07's double-speed half checks the general fact this bug
depended on (the PPU's dot clock doesn't speed up with the CPU) but cannot
and does not check the specific bug, and no rewording of a timing check ever
will. See `docs/double-speed.md` for the full survey; the short version is in
`checks_ppu.asm`'s own comment beside GB-PPU-07. When a PPU bug's only effect
is which of two already-equal-cost sources gets read, it needs Mealybug or a
screenshot, not this cartridge.

## A local `.terminalgb` checkout used for investigation must be restored to its pin before it's trusted again

Checking out a different commit in `.terminalgb` to read a fix or reproduce a
bug (this repo's own investigative habit, and a good one) leaves that
checkout sitting on whatever you last visited. `tools/run-terminalgb.sh` only
clones-and-pins on first use (`if [ ! -d "$DEST/.git" ]`); if `.terminalgb`
already exists, it runs whatever commit is currently checked out, silently,
with no complaint that it isn't the pinned `TERMINALGB_REF`. This produced a
scoreboard row that looked like a huge, exciting accuracy jump (a stale
committed baseline of 94/101 against a freshly measured 99/102) that was
actually nothing to do with this session's changes — the checkout had been
left on a much newer commit from an unrelated fix investigation earlier in
the same session. `git checkout --quiet "$TERMINALGB_REF"` (the exact ref
`tools/run-terminalgb.sh` defines) before trusting any scoreboard or
screenshot regeneration that touches TerminalGB, every time you've touched
that checkout for any other reason first.

## The brand

`docs/brand/generate.py` is the only source of truth for the logo and icon. Edit
the generator, never the SVGs, and re-render `docs/brand/preview/*` in the same
commit. Every letterform is an original stroked skeleton path — no font is
embedded, subset or traced — which is what keeps the files free of any third-party
licence. It is deliberately the same alphabet, palette and panel as TerminalGB's
and AtlasGB's marks; only the motif differs. See `docs/brand/README.md`.

## A red build badge here had two independent causes — check both

`build`'s SameBoy step (`run it on SameBoy, which nobody here wrote`) failed
for a real reason on every one of this repo's first three CI runs
(2026-08-15): the workflow built RGBDS but never put it on `PATH`, so
`tools/run-sameboy.sh`'s own `make -C SameBoy tester` cannot find `rgbgfx` to
assemble the boot-ROM logo and dies in about nine seconds with `rgbgfx: No
such file or directory`. It only ever worked on a laptop because a prior
local `.rgbds` build happened to already be on `PATH`; a clean shell with
`.sameboy` cleared and no `.rgbds` on `PATH` reproduces the exact failure
every time, and adding `.rgbds` to `PATH` before calling the script fixes it
(both DMG and Pocket runs then pass). Fixed in `build.yml` by appending
`$PWD/.rgbds` to `$GITHUB_PATH` right after `fetch-rgbds.sh` runs — never
`export RGBDS=...` for this, that name collides with SameBoy's own Makefile
variable of the same name (see "Building and running" above).

Separately, starting a few days after this repo's first CI runs (2026-08-20
here), every job on this private repo has failed in 2-4 seconds with
`runner_id: 0`, `runner_name: ""`, `steps: []` — the job never reaches a
runner. The check-run annotation gives the reason: *"The job was not started
because recent account payments have failed or your spending limit needs to
be increased."* This is an account-level GitHub Actions billing gate, not
anything in this repo, and it also affects TerminalGB and AtlasGB (same
account) — the account's one public repo, `devlog`, is unaffected, because
public repos get free Actions minutes.

**The two stack.** Because the billing gate started only days after the
PATH bug shipped, this repo's badge has never once been green, and clearing
the billing gate alone will not fix that — the PATH fix above is also
required. Before debugging a red badge here: check a failing job's
`created_at`/`started_at` delta and its check-run annotations first. A
few-second job with no steps and that annotation is the billing gate; a job
that actually ran steps and failed is a real regression, and the billing
gate can be hiding one even now — a green run after billing clears is not
proof of anything that failed silently underneath it before.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
