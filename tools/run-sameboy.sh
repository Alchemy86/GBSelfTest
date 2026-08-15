#!/bin/sh
# Run the cartridge on SameBoy and print the report it sends over the link port.
#
# A test cartridge that has only ever run on one emulator is not a test of
# anything: its expected values would be whatever that emulator does. This is
# how the suite is checked against an implementation nobody here wrote.
#
#   tools/run-sameboy.sh [model] [frames]
#
# SameBoy is fetched and built here, never vendored: it is somebody else's
# work under somebody else's licence (Expat). Needs a C compiler, git and make.
set -eu

MODEL="${1:-dmg}"
FRAMES="${2:-4000}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST="$HERE/.sameboy"
SAMEBOY_COMMIT="${SAMEBOY_COMMIT:-213a12ce93d66b105a113debd9396306066a7cfc}"
RGBDS_DIR="${RGBDS:-}"

if [ ! -x "$DEST/sameboy-serial" ]; then
    mkdir -p "$DEST"
    if [ ! -d "$DEST/SameBoy" ]; then
        git clone --quiet https://github.com/LIJI32/SameBoy "$DEST/SameBoy"
        (cd "$DEST/SameBoy" && git checkout --quiet "$SAMEBOY_COMMIT")
    fi
    # `tester` is the cheapest target that also assembles the boot ROMs, and
    # the boot ROMs matter: GB-BOOT checks the state they hand over.
    if [ -n "$RGBDS_DIR" ]; then PATH="$RGBDS_DIR:$PATH"; export PATH; fi
    make -C "$DEST/SameBoy" -j"$(nproc)" tester CONF=release >"$DEST/build.log" 2>&1 ||
        { tail -20 "$DEST/build.log"; echo "SameBoy build failed, see $DEST/build.log" >&2; exit 1; }
    cc -O2 -std=gnu99 -I"$DEST/SameBoy" -o "$DEST/sameboy-serial" \
        "$HERE/tools/sameboy-serial.c" "$DEST"/SameBoy/build/obj/Core/*.o -lm -ldl
fi

exec "$DEST/sameboy-serial" "$DEST/SameBoy/build/bin/tester" "$MODEL" \
    "$HERE/dist/gbselftest.gb" "$FRAMES"
