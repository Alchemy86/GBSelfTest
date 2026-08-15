#!/usr/bin/env python3
"""Generate the GBSelfTest brand SVGs.

Every letterform is hand-drawn here as a stroked skeleton path — **no font is
embedded, subset or traced**, so there is no third-party licence in these files.
This is the same approach, the same palette and the same panel as TerminalGB's
`docs/brand/generate.py` and AtlasGB's, because the three are sibling projects
and the marks should read as a family; the *motif* is GBSelfTest's own.

Run from anywhere:  python3 docs/brand/generate.py
It rewrites `gbselftest-logo.svg` and `gbselftest-icon.svg` deterministically.
Edit this file, never the SVGs by hand.
"""

import os

OUT = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Palette — TerminalGB's, unchanged. A sibling that recoloured would read as a
# different project rather than a companion one.
BG = "#0d1117"         # near-black panel (matches GitHub dark, works on light)
EDGE = "#30363d"       # faint panel border so the card reads on pure black too
FG = "#f0f3f6"         # wordmark white
GREY = "#8b949e"       # tagline grey
DMG_LIGHT = "#9bbc0f"  # DMG LCD lit shade — the single accent

TAGLINE = "A CARTRIDGE THAT TESTS THE MACHINE"

# ---------------------------------------------------------------------------
# Stroke-skeleton capital letters. Cap height 100, stroke 26 (half-stroke 13);
# every endpoint is inset 13 so round caps land on the ink edge. The value is
# (advance width, list of path data).
#
# These are the shapes TerminalGB's and AtlasGB's generators already draw,
# carried over unchanged so all three wordmarks are visibly the same alphabet —
# that is our work in every one of those places. F is new here (GBSELFTEST needs
# it and neither sibling did) and is drawn to the same rules: E without its
# bottom bar, same cap height, same inset, same stroke.
S = 13
GLYPHS = {
    'T': (72, ["M13 13 H59", "M36 13 V87"]),
    'E': (56, ["M43 13 H13 V87 H43", "M13 50 H36"]),
    'F': (56, ["M43 13 H13 V87", "M13 50 H36"]),
    'R': (68, ["M13 87 V13 H36 A19 19 0 0 1 36 51 H13", "M37 54 L54 87"]),
    'M': (86, ["M13 87 V13 L43 57 L73 13 V87"]),
    'I': (26, ["M13 13 V87"]),
    'N': (64, ["M13 87 V13 L51 87 V13"]),
    'A': (76, ["M11 87 L38 15 L65 87", "M23 62 H53"]),
    'L': (54, ["M13 13 V87 H41"]),
    'G': (70, ["M57 13 H13 V87 H57 V56 H42"]),
    'B': (66, ["M13 13 V87", "M13 13 H35 A18 18 0 0 1 35 49 H13",
               "M13 49 H37 A19 19 0 0 1 37 87 H13"]),
    'O': (64, ["M32 13 A19 37 0 1 0 32 87 A19 37 0 1 0 32 13"]),
    'U': (64, ["M13 13 V68 A19 19 0 0 0 51 68 V13"]),
    'Y': (64, ["M13 13 L32 47 L51 13", "M32 47 V87"]),
    'S': (72, ["M57 13 H36 A23 18.5 0 0 0 36 50 A23 18.5 0 0 1 36 87 H15"]),
    'C': (60, ["M42 18 A19 37 0 1 0 42 82"]),
    'D': (68, ["M13 13 V87", "M13 13 H31 A24 37 0 0 1 31 87 H13"]),
    'P': (62, ["M13 87 V13", "M13 13 H32 A17 18 0 0 1 32 49 H13"]),
    'V': (64, ["M13 13 L32 87 L51 13"]),
    'W': (96, ["M13 13 L33 87 L48 34 L63 87 L83 13"]),
    'H': (66, ["M13 13 V87", "M53 13 V87", "M13 50 H53"]),
    ' ': (30, []),
}
TRACK = 8  # tight letter spacing


def word_width(text, track=TRACK, widths=None):
    w = 0
    for i, ch in enumerate(text):
        w += (widths.get(ch) if widths and ch in widths else GLYPHS[ch][0])
        if i < len(text) - 1:
            w += track
    return w


def draw_word(text, x, y, scale, color, track=TRACK):
    """SVG for `text` with the letter grid's top-left at (x, y)."""
    parts = []
    cx = 0.0
    for ch in text:
        w, paths = GLYPHS[ch]
        for d in paths:
            parts.append(
                f'<path transform="translate({x + cx * scale:.1f} {y:.1f}) '
                f'scale({scale:.4f})" d="{d}" fill="none" stroke="{color}" '
                f'stroke-width="26" stroke-linecap="round" '
                f'stroke-linejoin="round"/>')
        cx += w + track
    return "\n".join(parts)


def svg(width, height, body, comment):
    return (f"<!-- {comment}\n"
            "     Hand-authored for GBSelfTest (MIT). No font embedded, subset "
            "or traced;\n     letterforms are original stroked paths. "
            "Regenerate with docs/brand/generate.py -->\n"
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} '
            f'{height}" width="{width}" height="{height}" role="img">\n'
            f"{body}\n</svg>\n")


def panel(w, h, rx=24):
    return (f'<rect x="1" y="1" width="{w - 2}" height="{h - 2}" rx="{rx}" '
            f'fill="{BG}" stroke="{EDGE}" stroke-width="2"/>')


def write(name, content):
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(content)
    print(f"wrote {name} ({len(content)} bytes)")


# ---------------------------------------------------------------------------
# THE MARK.
#
# TerminalGB's motif is a solid block cursor standing where a letter would be;
# AtlasGB's is a four-segment region bar under the wordmark. GBSelfTest keeps
# the panel, the alphabet, the palette, the tight tracking and the accent full
# stop — that is the family — and brings its own motif: **the pass mark**.
#
# One idea, not three. This cartridge's whole job is to reach a verdict, and a
# tick is the shortest way to draw a verdict. It is struck in the alphabet's own
# hand — cap height 100, stroke 26, round caps, endpoints inset 13 — so it sits
# on the baseline as if it were another letter of the wordmark rather than an
# icon dropped beside one, and it leads the word the way a tick leads a line on
# a checklist.
#
# Nothing here resembles any Nintendo mark, logotype or trade dress; the whole
# vocabulary is a tick and a full stop.

# The tick, to the alphabet's construction. The short arm falls to the ink
# floor (74 + half-stroke 13 = 87) and the long arm rises to the ink ceiling
# (26 - 13 = 13), so it occupies exactly the cap height the letters do.
TICK = (96, ["M13 48 L36 74 L83 26"])
TICK_GAP = 30   # a little more air than TRACK: the tick is a mark, not a letter


def draw_tick(x, y, scale, colour=DMG_LIGHT):
    return (f'<path transform="translate({x:.1f} {y:.1f}) '
            f'scale({scale:.4f})" d="{TICK[1][0]}" fill="none" '
            f'stroke="{colour}" stroke-width="26" stroke-linecap="round" '
            f'stroke-linejoin="round"/>')


def logo():
    W, H = 1200, 380
    text = "GBSELFTEST"
    DOT_R = 16          # the full stop, bottom-aligned with the letter ink
    units = TICK[0] + TICK_GAP + word_width(text) + TRACK + 2 * DOT_R
    scale = 1050 / units   # the content width the sibling marks settle at
    x0 = (W - units * scale) / 2
    y0 = 108
    parts = [panel(W, H)]
    parts.append(draw_tick(x0, y0, scale))
    wx = x0 + (TICK[0] + TICK_GAP) * scale
    parts.append(draw_word(text, wx, y0, scale, FG))
    cx = word_width(text) + TRACK
    parts.append(
        f'<circle cx="{wx + (cx + DOT_R) * scale:.1f}" '
        f'cy="{y0 + (100 - DOT_R) * scale:.1f}" r="{DOT_R * scale:.1f}" '
        f'fill="{DMG_LIGHT}"/>')
    tw = word_width(TAGLINE, track=14) * 0.30
    parts.append(draw_word(TAGLINE, (W - tw) / 2, 288, 0.30, GREY, track=14))
    write("gbselftest-logo.svg",
          svg(W, H, "\n".join(parts),
              "GBSelfTest logo — the pass mark, the wordmark, the full stop"))


def icon():
    """The pass mark alone, at avatar and favicon size.

    Sized so the whole tick spans the box with a stroke wide enough to survive
    16 px: at that size the two arms are one and two device pixels of ink, which
    still reads as a tick, where the sibling icons read as one tall block
    (TerminalGB) and four stacked rows (AtlasGB). No two of the three can be
    mistaken for each other in a favicon.
    """
    IW = 128
    scale = 1.02
    tw = TICK[0] * scale
    x = (IW - tw) / 2
    y = (IW - 100 * scale) / 2
    body = [panel(IW, IW, rx=28), draw_tick(x, y, scale)]
    write("gbselftest-icon.svg",
          svg(IW, IW, "\n".join(body), "GBSelfTest icon — the pass mark"))


if __name__ == "__main__":
    logo()
    icon()
