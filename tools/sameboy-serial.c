/* A second opinion on GBSelfTest's own verdict.
 *
 * A test cartridge that only ever runs on one emulator is worth nothing: the
 * expected values in it would be whatever that emulator happens to do. This
 * runs the cartridge on SameBoy -- an independent implementation nobody here
 * wrote -- and prints the report it produces over the link port, so the two
 * can be compared row by row.
 *
 * SameBoy's serial interface is one bit at a time, which is what the hardware
 * does; eight of them, most significant first, make the byte the cartridge
 * wrote to $FF01. Nothing is sent back: the far end of the cable is not
 * connected, and the cartridge's own GB-SER checks are written knowing that.
 *
 * Build with tools/run-sameboy.sh. SameBoy is Expat-licensed and is not
 * vendored here; this file is ours and calls only its public Core API.
 *
 *   sameboy-serial <bootrom-dir> <model> <rom> [frames]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <Core/gb.h>

static uint32_t pixels[256 * 224];

static unsigned bit_count = 0;
static unsigned byte_so_far = 0;

static void bit_start(GB_gameboy_t *gb, bool bit)
{
    byte_so_far = (byte_so_far << 1) | (bit ? 1 : 0);
    if (++bit_count == 8) {
        putchar(byte_so_far & 0xFF);
        bit_count = 0;
        byte_so_far = 0;
    }
}

/* Nothing is plugged into the other end, and an unconnected line reads high. */
static bool bit_end(GB_gameboy_t *gb) { return true; }

static char *no_input(GB_gameboy_t *gb) { return NULL; }
static void no_vblank(GB_gameboy_t *gb, GB_vblank_type_t kind) { }

struct console { const char *name; GB_model_t model; const char *boot; };

static const struct console CONSOLES[] = {
    { "dmg",  GB_MODEL_DMG_B, "dmg_boot.bin" },
    { "mgb",  GB_MODEL_MGB,   "dmg_boot.bin" },
    { "sgb",  GB_MODEL_SGB,   "sgb_boot.bin" },
    { "cgb0", GB_MODEL_CGB_0, "cgb_boot.bin" },
    { "cgbB", GB_MODEL_CGB_B, "cgb_boot.bin" },
    { "cgbC", GB_MODEL_CGB_C, "cgb_boot.bin" },
    { "cgbD", GB_MODEL_CGB_D, "cgb_boot.bin" },
    { "cgbE", GB_MODEL_CGB_E, "cgb_boot.bin" },
    { "agb",  GB_MODEL_AGB_A, "agb_boot.bin" },
};

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr, "usage: %s <bootrom-dir> <model> <rom> [frames]\n"
                        "  model: dmg mgb sgb cgb0 cgbB cgbC cgbD cgbE agb\n",
                argv[0]);
        return 2;
    }
    const char *bootdir = argv[1], *model = argv[2], *rom = argv[3];
    int frames = argc > 4 ? atoi(argv[4]) : 4000;

    const struct console *c = NULL;
    for (size_t i = 0; i < sizeof CONSOLES / sizeof *CONSOLES; i++)
        if (!strcmp(model, CONSOLES[i].name)) c = &CONSOLES[i];
    if (!c) { fprintf(stderr, "unknown model '%s'\n", model); return 2; }

    GB_gameboy_t gb;
    GB_init(&gb, c->model);

    char path[4096];
    snprintf(path, sizeof path, "%s/%s", bootdir, c->boot);
    if (GB_load_boot_rom(&gb, path)) { fprintf(stderr, "cannot read %s\n", path); return 2; }
    if (GB_load_rom(&gb, rom))       { fprintf(stderr, "cannot read %s\n", rom);  return 2; }

    GB_set_pixels_output(&gb, pixels);
    GB_set_vblank_callback(&gb, no_vblank);
    GB_set_async_input_callback(&gb, no_input);
    GB_set_rendering_disabled(&gb, true);
    GB_set_serial_transfer_bit_start_callback(&gb, bit_start);
    GB_set_serial_transfer_bit_end_callback(&gb, bit_end);

    for (int f = 0; f < frames; f++) GB_run_frame(&gb);
    fflush(stdout);
    return 0;
}
