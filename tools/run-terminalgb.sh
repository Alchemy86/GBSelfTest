#!/bin/sh
# Run the cartridge on TerminalGB, in either of its two picture modes.
#
# The third implementation in the scoreboard, and the interesting one: it has
# two renderers behind one emulator, so the same code base gives two different
# answers to this cartridge, and the difference between them is the fetcher
# model alone. That is the cleanest demonstration there is that the PPU checks
# measure what they claim to measure.
#
#   tools/run-terminalgb.sh [identical|standard] [frames] [serial-out]
#
#     identical  the per-dot renderer
#     standard   the whole-scanline renderer, which charges mode 3 a fixed
#                length and therefore cannot show a fetcher penalty
#
# TerminalGB is fetched and built here, never vendored. Needs git and a Rust
# toolchain; the build is the `conformance_adapter` example, which is that
# project's own harness for exactly this and is far smaller than the whole
# emulator.
set -eu

MODE="${1:-identical}"
FRAMES="${2:-2000}"
OUT="${3:-}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST="$HERE/.terminalgb"
# Pinned so the numbers in the README are numbers somebody else can get.
TERMINALGB_REF="${TERMINALGB_REF:-2467c65962183591e897c242e395d5e4524c3085}"
ADAPTER="$DEST/target/release/examples/conformance_adapter"

if [ ! -d "$DEST/.git" ]; then
    git clone --quiet https://github.com/Alchemy86/TerminalGB "$DEST"
    (cd "$DEST" && git checkout --quiet "$TERMINALGB_REF")
fi
if [ ! -x "$ADAPTER" ]; then
    (cd "$DEST" && cargo build --release --example conformance_adapter)
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Never run a ROM where it is kept: the cartridge has RAM, and a harness that
# ran it in place could leave something beside the artefact.
cp "$HERE/dist/gbselftest.gb" "$TMP/gbselftest.gb"

GB_PPU="$MODE" \
GBCONFORM_ROM="$TMP/gbselftest.gb" \
GBCONFORM_MODEL=dmg \
GBCONFORM_FRAMES="$FRAMES" \
GBCONFORM_SERIAL_OUT="$TMP/serial.txt" \
GBCONFORM_TIMEOUT_S=120 \
    "$ADAPTER" "$TMP/gbselftest.gb" >/dev/null

if [ -n "$OUT" ]; then
    cp "$TMP/serial.txt" "$OUT"
else
    cat "$TMP/serial.txt"
fi
