# GBSelfTest — build the cartridge.
#
#   make            build dist/gbselftest.gb
#   make clean      remove the intermediates
#   make check      build and confirm the ROM is byte-for-byte reproducible
#
# RGBDS is the assembler (https://rgbds.gbdev.io). Point RGBDS at a directory
# holding rgbasm/rgblink/rgbfix if they are not on the path:
#
#   make RGBDS=/opt/rgbds-1.0.3
#
# The exact version this cartridge is built and released with is pinned in
# tools/fetch-rgbds.sh, and CI uses that script so a release is reproducible.

RGBDS   ?=
ifeq ($(RGBDS),)
RGBASM  := rgbasm
RGBLINK := rgblink
RGBFIX  := rgbfix
else
RGBASM  := $(RGBDS)/rgbasm
RGBLINK := $(RGBDS)/rgblink
RGBFIX  := $(RGBDS)/rgbfix
endif

NAME    := gbselftest
TITLE   := GBSELFTEST
BUILD   := build
DIST    := dist
ROM     := $(DIST)/$(NAME).gb
SYM     := $(BUILD)/$(NAME).sym
MAP     := $(BUILD)/$(NAME).map

SRC := $(wildcard src/*.asm)
INC := $(wildcard src/*.inc)
OBJ := $(patsubst src/%.asm,$(BUILD)/%.o,$(SRC))

# -Wall so a truncated constant or an unknown symbol is an error in review
# rather than a mystery on hardware. -h is not passed: this cartridge writes
# its own HALT opcodes where the defect is under test.
ASFLAGS  := -Wall -Isrc
LINKFLAGS := -n $(SYM) -m $(MAP)

# Cartridge header. MBC1 with four banks and 8 KiB of RAM, no battery: the
# mapper checks need something to switch and something to enable, and nothing
# here should ever leave a save file beside the ROM.
#   -m 0x02  MBC1 + RAM          -r 0x02  8 KiB of cartridge RAM
#   -p 0xFF  pad byte            -j -v    fix both header checksums
#   -c       CGB-enhanced but DMG/MGB-compatible ($80 at $0143). Without this,
#             a real Color console runs the cartridge in DMG compatibility
#             mode, where KEY1 and double speed do not exist at all (Pan Docs,
#             "CGB Registers": KEY1 is "CGB Mode only") -- every double-speed
#             check would silently skip on real hardware. -C (CGB-only) is
#             deliberately not used: the DMG and MGB checks still need to run.
FIXFLAGS := -m 0x02 -r 0x02 -p 0xFF -c -t $(TITLE) -j -v

.PHONY: all clean check

all: $(ROM)

# Every object depends on every include. They are three small files that
# nearly every source pulls in, and the alternative -- a generated dependency
# file per object -- buys nothing but a way to get it wrong. Leaving them out
# of the prerequisites cost an afternoon: editing the memory map rebuilt
# nothing, and the half-stale ROM that came out was blamed on the emulator.
$(BUILD)/%.o: src/%.asm $(INC) | $(BUILD)
	$(RGBASM) $(ASFLAGS) -o $@ $<

$(ROM): $(OBJ) | $(DIST)
	$(RGBLINK) $(LINKFLAGS) -o $@ $(OBJ)
	$(RGBFIX) $(FIXFLAGS) $@
	@echo "built $@ ($$(stat -c%s $@) bytes)"

$(BUILD) $(DIST):
	mkdir -p $@

clean:
	rm -rf $(BUILD)

# The first build has to be kept somewhere `clean` will not delete, which is
# why this does not use $(BUILD).
check: all
	@cp $(ROM) $(DIST)/.first.gb
	@$(MAKE) --no-print-directory RGBDS=$(RGBDS) clean >/dev/null
	@$(MAKE) --no-print-directory RGBDS=$(RGBDS) $(ROM) >/dev/null
	@cmp $(DIST)/.first.gb $(ROM) && echo "reproducible: two builds are identical"
	@rm -f $(DIST)/.first.gb
