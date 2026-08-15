#!/bin/sh
# Regenerate every picture and every transcript the documentation carries.
#
# The pictures in the README are not screen grabs. Each one is the emulator's
# own framebuffer, written straight out at the native 160x144 and enlarged by
# a whole number with nearest-neighbour sampling, so every pixel in the file is
# a pixel the console drew and nothing has been cropped, filtered or retouched.
# A picture of a test tool that had been touched up would be an odd thing to
# ask anybody to trust.
#
#   tools/screenshots.sh
#
# Needs ImageMagick (`magick`) for the PPM-to-PNG step, and whatever each
# runner needs: a C compiler for SameBoy and Peanut-GB, a Rust toolchain for
# TerminalGB. Everything else it does itself.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$HERE/docs/screenshots"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SCALE="${SCALE:-3}"     # 160x144 -> 480x432, integer, no resampling blur

if ! command -v magick >/dev/null 2>&1; then
    echo "screenshots.sh needs ImageMagick (magick)" >&2
    exit 2
fi
if [ ! -f "$HERE/dist/gbselftest.gb" ]; then
    echo "dist/gbselftest.gb is missing; run make first" >&2
    exit 2
fi
mkdir -p "$OUT"

png() {  # png <in.ppm> <out.png>
    # -strip and no time chunk: the emulators are deterministic, so two runs of
    # this script should produce byte-identical files. Without it every run
    # rewrites the timestamp inside the PNG and the pictures show up in `git
    # status` as changed when nothing about them has.
    magick "$1" -filter point -resize "$((SCALE * 100))%" \
        -strip -define png:exclude-chunk=time "$2"
    echo "  $2"
}

echo "SameBoy, DMG -- the passing report"
"$HERE/tools/run-sameboy.sh" dmg 4000 "$TMP/sameboy.ppm" > "$TMP/sameboy.txt"
png "$TMP/sameboy.ppm" "$OUT/report-sameboy-dmg.png"
cp "$TMP/sameboy.txt" "$OUT/report-sameboy-dmg.txt"
echo "  $OUT/report-sameboy-dmg.txt"

echo "Peanut-GB -- a failing report, and the codes to look up"
"$HERE/tools/run-peanut.sh" 4000 "$TMP/peanut.ppm" > "$TMP/peanut.txt"
png "$TMP/peanut.ppm" "$OUT/report-peanut.png"
cp "$TMP/peanut.txt" "$OUT/report-peanut.txt"
echo "  $OUT/report-peanut.txt"

# The excerpt the README quotes: the first failure in full, with its measured
# value, its explanation and its documentation link. Cut here rather than by
# hand so that it cannot drift from what the cartridge actually says.
awk '/ FAIL /{f=1} f{print; if (++n==4) exit}' "$TMP/peanut.txt" \
    | tr -d '\r' > "$OUT/failure-excerpt.txt"
echo "  $OUT/failure-excerpt.txt"

echo "done"
