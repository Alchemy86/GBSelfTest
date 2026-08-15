#!/bin/sh
# Run the cartridge on Peanut-GB and print the report it sends over the link
# port.
#
# The other end of the range from tools/run-sameboy.sh. SameBoy is the careful
# implementation this cartridge is developed against; Peanut-GB is a small,
# fast one with documented approximations. Running the same ROM on both is what
# turns "this suite discriminates" from a claim into a measurement.
#
#   tools/run-peanut.sh [frames] [screen.ppm]
#
# Peanut-GB is fetched and built here, never vendored: it is somebody else's
# work under somebody else's licence (MIT). Needs a C compiler and git.
set -eu

FRAMES="${1:-4000}"
SHOT="${2:-}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST="$HERE/.peanut"
# Pinned so the number in the README is a number somebody else can get.
PEANUT_REF="${PEANUT_REF:-8e656982f08663785794b84823d3e27f856fdb7f}"

if [ ! -d "$DEST/src" ]; then
    mkdir -p "$DEST"
    git clone --quiet https://github.com/deltabeard/Peanut-GB "$DEST/src"
    (cd "$DEST/src" && git checkout --quiet "$PEANUT_REF")
fi

if [ ! -x "$DEST/peanut-serial" ] ||
   [ "$HERE/tools/peanut-serial.c" -nt "$DEST/peanut-serial" ]; then
    # -Wno-unused-parameter: the callback signatures are Peanut-GB's, and a
    # harness that ignores an argument is not a defect worth an error.
    cc -O2 -std=gnu99 -Wall -Wno-unused-parameter -I"$DEST/src" \
        -o "$DEST/peanut-serial" "$HERE/tools/peanut-serial.c"
fi

exec "$DEST/peanut-serial" "$HERE/dist/gbselftest.gb" "$FRAMES" ${SHOT:+"$SHOT"}
