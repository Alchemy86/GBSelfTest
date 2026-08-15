# GBSelfTest brand

**The mark is [`gbselftest-logo.svg`](gbselftest-logo.svg), and its square icon lockup is
[`gbselftest-icon.svg`](gbselftest-icon.svg). These two files are the only ones to ship —
anywhere.**

![The GBSelfTest logo](preview/logo.png)

## The composition

GBSelfTest is a sibling of [TerminalGB](https://github.com/Alchemy86/TerminalGB) and
[AtlasGB](https://github.com/Alchemy86/AtlasGB), so it keeps everything that makes those
marks recognisable — the near-black panel with its faint border, the same heavy geometric
alphabet, the same tight tracking, the DMG LCD lit shade (`#9bbc0f`) as the single accent,
the accent full stop closing the word, and the grey wide-tracked tagline underneath.

What is GBSelfTest's own is **the pass mark**. One idea, not three: this cartridge's whole
job is to reach a verdict, and a tick is the shortest way to draw one. It is struck in the
alphabet's own hand — cap height 100, stroke 26, round caps, endpoints inset 13, exactly
the construction every letter uses — so it sits on the baseline as though it were another
letter of the wordmark rather than an icon parked beside one, and it leads the word the way
a tick leads a line on a checklist.

The icon is the tick alone. Three marks that all had to survive 16 px had to stay apart at
16 px too: TerminalGB's is one tall block and a dot, AtlasGB's is four stacked rows with a
short one at the bottom, and this one is a single diagonal stroke — no two can be confused
in a row of favicons ([`preview/icon-16.png`](preview/icon-16.png) is the real test, not a
resized illustration).

## Licence and provenance

Everything here is **hand-authored**: the letterforms are original stroked skeleton paths
drawn in [`generate.py`](generate.py); **no font is embedded, subset or traced**, so there
is no third-party licence in any of these files. The letters shared with the two sibling
generators are carried over unchanged so that all three wordmarks are visibly the same
alphabet — that is our work in every one of those places. `F` is new here, because
`GBSELFTEST` needs one and neither sibling did, and it is drawn to the same rules.

No Nintendo artwork, logotype or trade dress is used or imitated; the whole vocabulary is a
tick and a full stop.

## Regenerating

**Edit the generator, never the SVGs by hand**, and re-render the previews in the same
commit:

```bash
python3 docs/brand/generate.py
cd docs/brand
strip="-strip -define png:exclude-chunk=time"   # so two runs give identical files
magick -background none gbselftest-logo.svg $strip preview/logo.png
magick -background none gbselftest-icon.svg $strip preview/icon-128.png
magick -background none gbselftest-icon.svg -resize 16x16 $strip preview/icon-16.png
```

Every SVG paints its own panel, so it survives GitHub light mode, dark mode and a pure
black page — nothing is theme-conditional, so there is no `prefers-color-scheme` trap.

## Tagline

> **A CARTRIDGE THAT TESTS THE MACHINE**

The shortest honest description of the project. Naming the console a cartridge is written
for is nominative use, the standard practice in this corner of the world.

## Files

- [`gbselftest-logo.svg`](gbselftest-logo.svg) — **the** wordmark lockup, 1200×380
- [`gbselftest-icon.svg`](gbselftest-icon.svg) — **the** square icon lockup, 128×128
- [`preview/logo.png`](preview/logo.png), [`preview/icon-128.png`](preview/icon-128.png),
  [`preview/icon-16.png`](preview/icon-16.png) — rendered previews at hero, avatar and
  favicon size
- [`generate.py`](generate.py) — the only source of truth; edit it, never the SVGs
