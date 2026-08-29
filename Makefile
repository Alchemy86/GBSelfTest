# GBSelfTest — build the cartridge.
#
#   make            build dist/gbselftest.gb
#   make clean      remove the intermediates
#   make check      build and confirm the ROM is byte-for-byte reproducible
#   make agent-logo build dist/gbselftest-agent-logo.gb -- filming/testing
#                   variant, see the big comment at that target. NOT the
#                   cartridge this project distributes.
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

# This project's own boot logo (the "agent-bold" design), 48 bytes in the
# input layout rgbfix's own -L option expects -- NOT the same byte layout as
# the assembled header (see AGENTS.md's boot-logo entry for why that
# distinction bit once already). It is generated, not hand-authored -- see
# the `agent-logo` target below for the exact command and the hex the built
# header must decode back to. It is NOT used by the default build -- see that
# target for why.
LOGO := src/boot_logo.bin

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
# No -L here: -v fixes the real Nintendo logo into place, which is
# deliberate and non-negotiable for the cartridge this project distributes --
# see the `agent-logo` target below for why.
FIXFLAGS := -m 0x02 -r 0x02 -p 0xFF -c -t $(TITLE) -j -v

.PHONY: all clean check agent-logo

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

# --- the agent-bold logo variant: filming and testing ONLY --------------
#
# This is NOT the cartridge gbselftest distributes, and `make`/`make all`
# never builds it. It exists so the captain can film and test with this
# project's own logo, and it must stay opt-in:
#
#   mGBA -- the captain's own designated gold-standard reference -- REFUSES
#   TO LOAD a cartridge whose header logo is not Nintendo's, outright,
#   before a single instruction runs. `retro_load_game` returns false
#   because `GBIsROM` (mGBA's src/gb/gb.c, called from `mCoreFindVF`)
#   fingerprints "is this a Game Boy ROM at all" by checking 4 bytes at
#   $0104 against Nintendo's real logo (or two known Sachen-bootleg
#   fingerprints, or a GBX footer) and rejects anything else. Verified
#   directly: the identical cartridge with the Nintendo logo loads and runs
#   cleanly in the same mGBA core; only the header logo differs. Real
#   hardware's boot ROM performs its own, separate, full 48-byte comparison
#   and refuses hand-off on a mismatch too (Pan Docs, "Power-Up Sequence")
#   -- untested here for lack of a console, but there is no reason to
#   expect it more forgiving than mGBA.
#
#   So: this variant is for a screen recording or a controlled test run on
#   an emulator that does not enforce the check (SameBoy and Peanut-GB
#   among them -- see AGENTS.md's boot-logo entry). It must never become
#   the default FIXFLAGS, never be built by a bare `make`, and never be the
#   file dist/gbselftest.gb points at.
#
# $(LOGO) is generated by AgentGB's tools/boot_logo.py (design "agent-bold",
# that file's DEFAULT_DESIGN) -- not hand-transcribed -- and the built
# header must decode back to:
#   00336f0011ddff88ee00ffcfff0f6776199dbb88ff66cc0033
#   33ff00dddd88ffeeeefcfff0ff6666d771888866660000
# Regenerate with, from a checkout of AgentGB:
#   python3 tools/boot_logo.py preview --design agent-bold --out /tmp/x
# and take the "header = ..." hex it prints; see AGENTS.md for how that
# turns into $(LOGO)'s own byte layout, which is not the same thing.
AGENT_LOGO_ROM := $(DIST)/$(NAME)-agent-logo.gb
AGENT_LOGO_FIXFLAGS := $(FIXFLAGS) -L $(LOGO)

agent-logo: $(AGENT_LOGO_ROM)

$(AGENT_LOGO_ROM): $(OBJ) $(LOGO) | $(DIST)
	$(RGBLINK) $(LINKFLAGS) -o $@ $(OBJ)
	$(RGBFIX) $(AGENT_LOGO_FIXFLAGS) $@
	@echo "built $@ ($$(stat -c%s $@) bytes) -- filming/testing only, see Makefile"

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
