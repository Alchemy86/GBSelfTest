#!/bin/sh
# Run the cartridge on SameBoy and print the report it sends over the link port.
#
# A test cartridge that has only ever run on one emulator is not a test of
# anything: its expected values would be whatever that emulator does. This is
# how the suite is checked against an implementation nobody here wrote.
#
#   tools/run-sameboy.sh [model] [frames] [screen.ppm]
#
# With a third argument the screen the cartridge left behind is written out
# too, as a binary PPM at the native 160x144. tools/screenshots.sh uses that.
#
# SameBoy is fetched and built here, never vendored: it is somebody else's
# work under somebody else's licence (Expat). Needs a C compiler, git and make.
set -eu

# SameBoy and sameboy-serial must be built by the SAME compiler, and this is
# what makes sure of it. SameBoy's own Makefile prefers clang when clang is on
# the path (`ifeq ($(origin CC),default)`), and CONF=release below builds with
# -flto -- so on a machine with clang installed, build/obj/Core/*.o are clang
# LTO bitcode, and linking them with a plain `cc` that happens to be gcc dies
# with `file format not recognized`. That is exactly what happened on GitHub's
# ubuntu-latest, which ships clang, while every laptop here has only gcc and
# never saw it. Naming CC on make's command line also defeats the clang
# override, because `$(origin CC)` is then `command line`, not `default`.
CC="${CC:-cc}"

MODEL="${1:-dmg}"
FRAMES="${2:-4000}"
SHOT="${3:-}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST="$HERE/.sameboy"
SAMEBOY_COMMIT="${SAMEBOY_COMMIT:-213a12ce93d66b105a113debd9396306066a7cfc}"
RGBDS_DIR="${RGBDS:-}"

if [ ! -x "$DEST/sameboy-serial" ] ||
   [ "$HERE/tools/sameboy-serial.c" -nt "$DEST/sameboy-serial" ]; then
    mkdir -p "$DEST"
    if [ ! -d "$DEST/SameBoy" ]; then
        git clone --quiet https://github.com/LIJI32/SameBoy "$DEST/SameBoy"
        (cd "$DEST/SameBoy" && git checkout --quiet "$SAMEBOY_COMMIT")
    fi
    # `tester` is the cheapest target that also assembles the boot ROMs, and
    # the boot ROMs matter: GB-BOOT checks the state they hand over.
    if [ -n "$RGBDS_DIR" ]; then PATH="$RGBDS_DIR:$PATH"; export PATH; fi
    make -C "$DEST/SameBoy" -j"$(nproc)" tester CONF=release CC="$CC" \
        >"$DEST/build.log" 2>&1 ||
        { tail -20 "$DEST/build.log"; echo "SameBoy build failed, see $DEST/build.log" >&2; exit 1; }
    "$CC" -O2 -std=gnu99 -flto -I"$DEST/SameBoy" -o "$DEST/sameboy-serial" \
        "$HERE/tools/sameboy-serial.c" "$DEST"/SameBoy/build/obj/Core/*.o -lm -ldl
fi

exec "$DEST/sameboy-serial" "$DEST/SameBoy/build/bin/tester" "$MODEL" \
    "$HERE/dist/gbselftest.gb" "$FRAMES" ${SHOT:+"$SHOT"}
