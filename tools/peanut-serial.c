/* A third opinion, from an implementation that is not trying to be exact.
 *
 * SameBoy is the reference this cartridge is developed against. Peanut-GB is
 * the opposite end of the range on purpose: a single-header emulator written
 * to be small and fast enough for a microcontroller, which draws a scanline in
 * one go and charges mode 3 a fixed length. Running the same cartridge on both
 * is how the claim that it DISCRIMINATES is checked, rather than asserted -- a
 * suite everything passes measures nothing.
 *
 * Nothing here is a criticism of Peanut-GB. It is doing exactly what it set
 * out to do, and its own documentation says so; the checks it loses are the
 * price of that design, which is the point being illustrated.
 *
 * Peanut-GB is MIT-licensed and is NOT vendored here: tools/run-peanut.sh
 * fetches it. This file is ours and uses only its public API.
 *
 *   peanut-serial <rom> [frames] [screen.ppm]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ENABLE_LCD 1
#define ENABLE_SOUND 0
#include "peanut_gb.h"

struct priv {
    uint8_t *rom;
    uint8_t *ram;
};

static uint8_t rom_read(struct gb_s *gb, const uint_fast32_t addr)
{
    return ((const struct priv *)gb->direct.priv)->rom[addr];
}

static uint8_t ram_read(struct gb_s *gb, const uint_fast32_t addr)
{
    return ((const struct priv *)gb->direct.priv)->ram[addr];
}

static void ram_write(struct gb_s *gb, const uint_fast32_t addr, const uint8_t v)
{
    ((const struct priv *)gb->direct.priv)->ram[addr] = v;
}

/* The cartridge is meant to survive a machine that is wrong about things, so
 * an emulator error is reported and the run continues rather than aborting:
 * the report it has already sent is the interesting part. */
static void on_error(struct gb_s *gb, const enum gb_error_e err, const uint16_t addr)
{
    fprintf(stderr, "peanut-gb: error %u at %04x\n", (unsigned)err, addr);
}

/* The link port is the log. Peanut-GB hands over whole bytes rather than bits,
 * which is the one place its harness is simpler than SameBoy's. */
static void serial_tx(struct gb_s *gb, const uint8_t byte) { putchar(byte); }

/* Nothing is plugged into the other end. */
static enum gb_serial_rx_ret_e serial_rx(struct gb_s *gb, uint8_t *out)
{
    return GB_SERIAL_RX_NO_CONNECTION;
}

static uint8_t frame[LCD_HEIGHT][LCD_WIDTH];

static void draw_line(struct gb_s *gb, const uint8_t *pixels,
                      const uint_fast8_t line)
{
    if (line < LCD_HEIGHT)
        for (unsigned x = 0; x < LCD_WIDTH; x++)
            frame[line][x] = pixels[x] & LCD_COLOUR;
}

/* The DMG's four shades, the same ones the SameBoy shot uses, so the two
 * pictures in the documentation differ only where the emulators do. */
static const uint8_t SHADES[4][3] = {
    {0xE0, 0xF8, 0xD0}, {0x88, 0xC0, 0x70},
    {0x34, 0x68, 0x56}, {0x08, 0x18, 0x20},
};

static int write_ppm(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) return 1;
    fprintf(f, "P6\n%d %d\n255\n", LCD_WIDTH, LCD_HEIGHT);
    for (unsigned y = 0; y < LCD_HEIGHT; y++)
        for (unsigned x = 0; x < LCD_WIDTH; x++)
            fwrite(SHADES[frame[y][x] & 3], 1, 3, f);
    return fclose(f) != 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <rom> [frames] [screen.ppm]\n", argv[0]);
        return 2;
    }
    int frames = argc > 2 ? atoi(argv[2]) : 4000;
    const char *shot = argc > 3 ? argv[3] : NULL;

    FILE *f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    rewind(f);
    struct priv p;
    p.rom = malloc(size);
    p.ram = calloc(1, 32 * 1024);
    if (!p.rom || !p.ram || fread(p.rom, 1, size, f) != (size_t)size) {
        fprintf(stderr, "cannot load %s\n", argv[1]);
        return 2;
    }
    fclose(f);

    struct gb_s gb;
    if (gb_init(&gb, rom_read, ram_read, ram_write, on_error, &p) != GB_INIT_NO_ERROR) {
        fprintf(stderr, "gb_init failed\n");
        return 2;
    }
    gb_init_serial(&gb, serial_tx, serial_rx);
    gb_init_lcd(&gb, draw_line);

    for (int i = 0; i < frames; i++) gb_run_frame(&gb);
    fflush(stdout);

    if (shot && write_ppm(shot)) {
        fprintf(stderr, "cannot write %s\n", shot);
        return 1;
    }
    return 0;
}
