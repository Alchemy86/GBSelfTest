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
 * Given a fifth argument it also writes the screen the cartridge left behind,
 * as a binary PPM of the emulator's own framebuffer -- the report as pixels,
 * at the native 160x144 with nothing scaled, filtered or cropped. That is what
 * docs/screenshots are made of, and making them a build step rather than a
 * hand-crop is the only way the pictures in the README stay true.
 *
 * Build with tools/run-sameboy.sh. SameBoy is Expat-licensed and is not
 * vendored here; this file is ours and calls only its public Core API.
 *
 *   sameboy-serial <bootrom-dir> <model> <rom> [frames] [screen.ppm]
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

/* The framebuffer is 32 bits a pixel and SameBoy asks us how to pack them. */
static uint32_t rgb_encode(GB_gameboy_t *gb, uint8_t r, uint8_t g, uint8_t b)
{
    return ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

/* Binary PPM: three bytes a pixel, no palette, no compression, no library.
 * Anything can read it, and `magick` turns it into the PNG the docs carry. */
static int write_ppm(const char *path, unsigned w, unsigned h)
{
    FILE *f = fopen(path, "wb");
    if (!f) return 1;
    fprintf(f, "P6\n%u %u\n255\n", w, h);
    for (unsigned i = 0; i < w * h; i++) {
        uint32_t p = pixels[i];
        fputc((p >> 16) & 0xFF, f);
        fputc((p >> 8) & 0xFF, f);
        fputc(p & 0xFF, f);
    }
    return fclose(f) != 0;
}

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
        fprintf(stderr, "usage: %s <bootrom-dir> <model> <rom> [frames] [screen.ppm]\n"
                        "  model: dmg mgb sgb cgb0 cgbB cgbC cgbD cgbE agb\n",
                argv[0]);
        return 2;
    }
    const char *bootdir = argv[1], *model = argv[2], *rom = argv[3];
    int frames = argc > 4 ? atoi(argv[4]) : 4000;
    const char *shot = argc > 5 ? argv[5] : NULL;

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
    /* Drawing costs time and nothing reads the picture unless a shot was
     * asked for. The cartridge's own verdict is identical either way: it
     * never reads back what it drew. */
    GB_set_rendering_disabled(&gb, shot == NULL);
    GB_set_rgb_encode_callback(&gb, rgb_encode);
    /* The DMG's own four shades, so the picture in the documentation is the
     * colour the console it is testing actually is. */
    GB_set_palette(&gb, &GB_PALETTE_DMG);
    GB_set_serial_transfer_bit_start_callback(&gb, bit_start);
    GB_set_serial_transfer_bit_end_callback(&gb, bit_end);

    for (int f = 0; f < frames; f++) GB_run_frame(&gb);
    fflush(stdout);

    if (shot && write_ppm(shot, GB_get_screen_width(&gb),
                          GB_get_screen_height(&gb))) {
        fprintf(stderr, "cannot write %s\n", shot);
        return 1;
    }
    return 0;
}
