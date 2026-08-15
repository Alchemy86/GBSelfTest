#!/bin/sh
# Fetch and build the exact RGBDS a release is made with.
#
# The version is pinned HERE and nowhere else, so a laptop, a CI job and a
# published ROM are built by identical bytes. Bumping it can change the ROM, so
# a bump and a rebuilt `dist/gbselftest.gb` belong in the same commit.
#
#   tools/fetch-rgbds.sh          -> .rgbds/{rgbasm,rgblink,rgbfix}
#   make RGBDS=$PWD/.rgbds
#
# Needs a C++ compiler, make, and the usual RGBDS build dependencies
# (libpng-dev, bison). Nothing is vendored: RGBDS is somebody else's work under
# somebody else's licence.
set -eu

RGBDS_VERSION="${RGBDS_VERSION:-v1.0.3}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST="$HERE/.rgbds"

if [ -x "$DEST/rgbasm" ]; then
    echo "already built: $("$DEST/rgbasm" --version)"
    exit 0
fi

TMP="$HERE/.rgbds-src"
rm -rf "$TMP"
git clone --quiet --depth 1 --branch "$RGBDS_VERSION" \
    https://github.com/gbdev/rgbds "$TMP"
make -C "$TMP" -j"$(nproc)" >"$TMP/build.log" 2>&1 ||
    { tail -20 "$TMP/build.log"; echo "RGBDS build failed" >&2; exit 1; }

mkdir -p "$DEST"
for t in rgbasm rgblink rgbfix rgbgfx; do
    [ -f "$TMP/$t" ] && cp "$TMP/$t" "$DEST/"
done
rm -rf "$TMP"
echo "built $("$DEST/rgbasm" --version) in $DEST"
