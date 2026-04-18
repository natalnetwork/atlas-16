/*
 * hps_load.c — Atlas 16 ROM Loader (HPS-Seite)
 *
 * Lädt ein .hack-Binärfile via Lightweight HPS-to-FPGA Bridge in den
 * Hack-ROM. Läuft auf Angstrom Linux (HPS ARM).
 *
 * Aufruf:  hps_load <datei.hack>
 *
 * Register-Map (LW-Bridge-Basis 0xFF200000 + Offset 0x8000):
 *   0x8000  CTRL      bit0 = cpu_resetN  (0=Reset, 1=Run)
 *   0x8004  LOAD_ADDR bits[14:0] = Startadresse (setzt internen Zähler)
 *   0x8008  LOAD_DATA bits[15:0] = Instruktion (schreibt + Adresse++)
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>
#include <string.h>

#define LW_BRIDGE_BASE   0xFF200000UL
#define LW_BRIDGE_SPAN   0x00200000UL

#define ROM_LOADER_BASE  0x00008000UL
#define REG_CTRL         0x00
#define REG_LOAD_ADDR    0x04
#define REG_LOAD_DATA    0x08

#define ROM_WORDS        32768

static volatile uint32_t *reg(void *base, uint32_t offset)
{
    return (volatile uint32_t *)((uint8_t *)base + ROM_LOADER_BASE + offset);
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "Aufruf: %s <datei.hack>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        fprintf(stderr, "Kann '%s' nicht öffnen: %s\n", argv[1], strerror(errno));
        return 1;
    }

    /* Dateigröße prüfen */
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    rewind(f);

    if (size % 2 != 0) {
        fprintf(stderr, "Ungültige Dateigröße %ld (muss gerade sein)\n", size);
        fclose(f);
        return 1;
    }

    int words = (int)(size / 2);
    if (words > ROM_WORDS) {
        fprintf(stderr, "Zu groß: %d Wörter (max %d)\n", words, ROM_WORDS);
        fclose(f);
        return 1;
    }

    uint16_t *buf = malloc(size);
    if (!buf) {
        fprintf(stderr, "Kein Speicher\n");
        fclose(f);
        return 1;
    }

    if ((int)fread(buf, 2, words, f) != words) {
        fprintf(stderr, "Lesefehler\n");
        free(buf);
        fclose(f);
        return 1;
    }
    fclose(f);

    /* /dev/mem öffnen */
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "Kann /dev/mem nicht öffnen: %s\n", strerror(errno));
        free(buf);
        return 1;
    }

    void *lw = mmap(NULL, LW_BRIDGE_SPAN, PROT_READ | PROT_WRITE,
                    MAP_SHARED, fd, LW_BRIDGE_BASE);
    close(fd);

    if (lw == MAP_FAILED) {
        fprintf(stderr, "mmap fehlgeschlagen: %s\n", strerror(errno));
        free(buf);
        return 1;
    }

    /* CPU in Reset halten */
    *reg(lw, REG_CTRL) = 0x00000000;

    /* Startadresse setzen (Wort 0) */
    *reg(lw, REG_LOAD_ADDR) = 0x00000000;

    /* Instruktionen schreiben */
    printf("Lade %d Wörter...\n", words);
    for (int i = 0; i < words; i++) {
        /* Big-Endian .hack → 16-bit Host-Order */
        uint16_t instr = (uint16_t)(((buf[i] & 0xFF) << 8) | ((buf[i] >> 8) & 0xFF));
        *reg(lw, REG_LOAD_DATA) = (uint32_t)instr;
    }

    free(buf);

    /* CPU freigeben */
    *reg(lw, REG_CTRL) = 0x00000001;

    munmap(lw, LW_BRIDGE_SPAN);

    printf("Fertig. CPU läuft.\n");
    return 0;
}
