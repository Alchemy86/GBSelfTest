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

## The brand

`docs/brand/generate.py` is the only source of truth for the logo and icon. Edit
the generator, never the SVGs, and re-render `docs/brand/preview/*` in the same
commit. Every letterform is an original stroked skeleton path — no font is
embedded, subset or traced — which is what keeps the files free of any third-party
licence. It is deliberately the same alphabet, palette and panel as TerminalGB's
and AtlasGB's marks; only the motif differs. See `docs/brand/README.md`.
