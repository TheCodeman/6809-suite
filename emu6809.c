/*
 * emu6809 - minimal 6809 / 6309 system emulator for MINI09
 *
 *   CPU: the 6809 instruction set, which is what an HD6309 runs in its
 *   power-up (emulation) mode.  6309-only instructions are not emulated;
 *   like a real 6309, any undefined opcode traps through the $FFF0 vector.
 *   $0000-$BFFF RAM, $C000 SCN2681 DUART (mirrored to $C7FF),
 *   $C800-$CFFF expansion select (nothing fitted: reads $FF; with -v the
 *   Pico 6809 video/sound chip), $E000-$FFFF ROM
 *   $D800-$D803 MMU (74HC670 + CPLD, write only): window n ($0000/$4000/$8000)
 *   uses 16K page mmu[n] (0-31) of a 512K SRAM.  It powers up with junk.
 *   Bit 4 of the $D803 write switches the ROM bank in at $8000-$BFFF.
 *   Console = DUART channel A; input honours RTS on OP0 (flow control).
 *
 * usage: emu6809 [-f] [-v [-k] [-T] [-d dir [-o]] [-p file.ppm]] [-r rom.s19] [-w] [-t secs] file.s19 [file.s19|file.prg ...]
 *   -f       run as fast as possible (default: paced to E = 3.6887 MHz)
 *   -v       fit the Pico 6809 video/sound chip at $C800 (registers, VRAM,
 *            60 Hz vblank interrupt; no picture or sound - the console is
 *            on stdout anyway).  Prints a summary on exit.
 *   -k       with -v: input goes to the chip's USB keyboard instead of
 *            the DUART (output still comes from the DUART)
 *   -d dir   with -v: a USB flash drive holding the files in dir (names
 *            matched without regard to case); file commands finish at once
 *   -T       with -v: stdout shows what is written to the video card's
 *            terminal (an HDMI console) instead of the DUART's output
 *   -r file  a 28C256: the S-records for $8000-$BFFF in file go into the ROM
 *            bank that $D803 bit 4 switches in (without -r it reads $FF)
 *   -p file  with -v: when it ends in a bitmap mode, save the screen there
 *            as a PPM picture (through the palette)
 *   -o       with -d: firmware from before FAPPEND (command $18 is ignored
 *            and the FCAPS byte is never set)
 *   -w       DS1232 watchdog on (JP2 1-2): reset if OP1 has no falling
 *            edge for 1.2 s
 *   -t secs  when stdin is not a terminal: keep running this many
 *            emulated seconds after input runs out (default 2)
 * Interactive: Ctrl-] quits.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <fcntl.h>
#include <time.h>
#include <setjmp.h>
#include <dirent.h>
#include <strings.h>
#include <sys/stat.h>

#define CF 0x01
#define VF 0x02
#define ZF 0x04
#define NF 0x08
#define IF 0x10
#define HF 0x20
#define FF 0x40
#define EF 0x80

static uint8_t mem[0x10000];                /* ROM ($E000-$FFFF) */
static uint8_t ram[0x80000];                /* 512K SRAM, 16K pages */
static int vterm_out;                       /* -T: stdout shows the video card's
                                               terminal, not the DUART */
static uint8_t mmu[4] = { 25, 5, 12, 19 };  /* MMU: random at power-up */
static uint8_t romb[0x4000];                /* the 28C256's first 16K, shown at
                                               $8000-$BFFF while mmu[3] bit 4
                                               (the CPLD's PG3) is set */
#define ROMBANK(a) ((a & 0xC000) == 0x8000 && (mmu[3] & 0x10))
static uint8_t A, B, DP, CC;
static uint8_t RE, RF, MD;              /* 6309: E, F (W = E:F), mode reg */
static uint16_t V6;                      /* 6309: V register */
static uint16_t X, Y, U, S, PC;
static uint64_t cycles;
static int cwai_wait, sync_wait;

#define GETD() ((uint16_t)((A << 8) | B))
#define GETW() ((uint16_t)((RE << 8) | RF))
#define SETW(v) do { uint16_t w_ = (v); RE = w_ >> 8; RF = w_ & 0xFF; } while (0)
#define SETD(v) do { uint16_t v_ = (v); A = v_ >> 8; B = v_ & 0xFF; } while (0)

/* ---------------- devices ----------------
 * SCN2681 DUART at $C000-$C00F, 3.6864 MHz crystal.
 * Modelled: channel A (3-deep receive FIFO, transmitter, MR1A/MR2A
 * pointer, command register), ISR/IMR, ACR, the counter/timer in timer
 * mode, and the output port (OP0 = RTS for channel A).  Channel B and the
 * input port are accepted but do nothing.
 */
#define XTAL_HZ 3686400.0
#define E_HZ    3688650.0           /* 14.7546 MHz / 4 */

static int wd_kick;                 /* DS1232 /ST saw a falling edge */
static uint8_t du_mr1a, du_mr2a, du_acr, du_imr, du_isr, du_opr;
static uint8_t du_ctur, du_ctlr;
static uint8_t du_fifo[3];
static int du_nfifo, du_mrptr, du_rxen, du_txen, du_ct_running;
static double du_ct_phase;          /* X1 clocks into the current period */

static uint8_t du_isr_now(void)
{
    uint8_t v = du_isr & 0x08;              /* counter ready */
    if (du_txen) v |= 0x01;                 /* TxRDYA */
    if (du_nfifo) v |= 0x02;                /* RxRDYA */
    return v;
}
static int du_irq(void) { return (du_isr_now() & du_imr) != 0; }

/* Can the "terminal" send another character to channel A? */
static int du_can_rx(void)
{
    return du_rxen && du_nfifo < 3 && (du_opr & 0x01);  /* OP0 low = RTS on */
}

static uint8_t io_read(uint16_t a)
{
    uint8_t v;
    switch (a & 0x0F) {
    case 0x0: v = du_mrptr ? du_mr2a : du_mr1a; du_mrptr = 1; return v;
    case 0x1: return (du_nfifo ? 0x01 : 0) | (du_nfifo == 3 ? 0x02 : 0)
                     | (du_txen ? 0x0C : 0);
    case 0x3: v = du_fifo[0];
              if (du_nfifo) {
                  memmove(du_fifo, du_fifo + 1, 2);
                  du_nfifo--;
              }
              return v;
    case 0x5: return du_isr_now();
    case 0xE: du_ct_running = 1; du_ct_phase = 0; return 0xFF;  /* start C/T */
    case 0xF: du_isr &= ~0x08; return 0xFF;    /* stop C/T: timer mode only
                                                  clears the ready bit */
    }
    return 0xFF;
}

static void io_write(uint16_t a, uint8_t v)
{
    switch (a & 0x0F) {
    case 0x0: if (du_mrptr) du_mr2a = v; else { du_mr1a = v; du_mrptr = 1; } break;
    case 0x2:                                   /* CRA */
        if ((v & 0x03) == 1) du_rxen = 1;
        if ((v & 0x03) == 2) du_rxen = 0;
        if ((v & 0x0C) == 4) du_txen = 1;
        if ((v & 0x0C) == 8) du_txen = 0;
        switch ((v >> 4) & 7) {
        case 1: du_mrptr = 0; break;
        case 2: du_rxen = 0; du_nfifo = 0; break;
        case 3: du_txen = 0; break;
        }
        break;
    case 0x3: if (du_txen && !vterm_out) { putchar(v); fflush(stdout); } break;
    case 0x4: du_acr = v; break;
    case 0x5: du_imr = v; break;
    case 0x6: du_ctur = v; break;
    case 0x7: du_ctlr = v; break;
    case 0xE: if (v & ~du_opr & 0x02) wd_kick = 1;  /* OP1 falls: strobe */
              du_opr |= v; break;               /* set OP bits: pins low */
    case 0xF: du_opr &= ~v; break;              /* reset OP bits: pins high */
    }
}

/* Run the counter/timer for n E-clock cycles. */
static void du_advance(unsigned n)
{
    int mode = (du_acr >> 4) & 7;
    unsigned pre = (du_ctur << 8) | du_ctlr;
    if (!du_ct_running || mode < 6 || !pre) return;  /* timer, X1 clock only */
    double period = 2.0 * pre * (mode == 7 ? 16 : 1);
    du_ct_phase += n * (XTAL_HZ / E_HZ);
    while (du_ct_phase >= period) {
        du_ct_phase -= period;
        du_isr |= 0x08;
    }
}

/* Pico 6809 video/sound chip at $C800-$CFFF (16 registers, mirrored),
 * fitted with -v.  Modelled: the registers, the DATA port into 128K VRAM,
 * the vblank flag and its /IRQ (60 Hz from the E clock), the ID and the
 * reset command, the USB key FIFO (-k) and the file commands on a host
 * directory (-d).  Terminal characters and sound writes are counted.
 */
#define VDP_FRAME   (E_HZ / 60.0)
#define VDP_VBLANK  (VDP_FRAME * 45 / 525)      /* 45 of 525 lines */
static int vdp_on;
static uint8_t vdp_reg[16], vram[0x20000];
static uint32_t vdp_ptr;
static int vdp_vbseen;
static double vdp_phase;                   /* E cycles into the frame */
static unsigned long vdp_frames, vdp_chars, vdp_sound, vdp_fcmds;
static int kbd_on, vdp_fdone;
static uint8_t keys[64];
static int nkeys;
static const char *drive_dir;

static uint8_t vdp_pal[256];            /* RGB332, as in the firmware */
static const char *ppm_path;            /* -p: the bitmap screen at exit */

static uint8_t rgb332(int r, int g, int b) { return (r & 0xE0) | (g & 0xE0) >> 3 | b >> 6; }

static void vdp_reset(void)
{
    static const uint8_t cga[16][3] = {
        {0, 0, 0},      {0, 0, 170},    {0, 170, 0},    {0, 170, 170},
        {170, 0, 0},    {170, 0, 170},  {170, 85, 0},   {170, 170, 170},
        {85, 85, 85},   {85, 85, 255},  {85, 255, 85},  {85, 255, 255},
        {255, 85, 85},  {255, 85, 255}, {255, 255, 85}, {255, 255, 255},
    };
    for (int i = 0; i < 256; i++)
        vdp_pal[i] = i < 16 ? rgb332(cga[i][0], cga[i][1], cga[i][2]) : i;
    memset(vdp_reg, 0, sizeof vdp_reg);
    vdp_reg[4] = 1;                         /* INC */
    vdp_reg[6] = 0x02;                      /* CTRL: display on */
    vdp_ptr = 0;
    vdp_vbseen = 0;
    vdp_fdone = 0;
    nkeys = 0;
}
static int vdp_irq(void)
{
    return vdp_on && ((vdp_vbseen && (vdp_reg[6] & 1)) || (nkeys && (vdp_reg[6] & 4)) ||
                      (vdp_fdone && (vdp_reg[6] & 8)));
}

/* ---- file commands ($10-$17) on drive_dir, mailbox in VRAM ---- */
enum { FR_OK = 0, FR_NOT_READY = 3, FR_NO_FILE = 4, FR_NO_PATH = 5, FR_DENIED = 7,
       FR_INVALID_OBJECT = 9, FR_INVALID_PARAMETER = 19 };
#define MB_NAME  0x1F000
#define MB_RES   0x1F040
#define MB_COUNT 0x1F041
#define MB_SIZE  0x1F043
#define MB_ATTR  0x1F047
#define MB_LEN   0x1F048
#define MB_CAPS  0x1F04A
static int vf_old;          /* -o: firmware from before FAPPEND */
#define MB_DATA  0x1F200
static FILE *vf_file;
static struct dirent **vf_list;
static int vf_n, vf_i, vf_open_dir;
static char vf_dirpath[1024];

static void put32(uint32_t a, uint32_t v)
{
    vram[a] = v >> 24; vram[a + 1] = v >> 16; vram[a + 2] = v >> 8; vram[a + 3] = v;
}

/* path -> host path under drive_dir, each part matched ignoring case.  A
 * missing last part is kept as written when 'create' is set. */
static int vf_resolve(const char *path, char *out, size_t outsz, int create)
{
    char buf[64], *save, *part;
    size_t pn = strnlen(path, sizeof buf - 1);
    memcpy(buf, path, pn);
    buf[pn] = 0;
    snprintf(out, outsz, "%s", drive_dir);
    for (part = strtok_r(buf, "/", &save); part; part = strtok_r(NULL, "/", &save)) {
        int last = (save == NULL || *save == 0);
        if (!strcmp(part, ".") || !strcmp(part, "..")) return FR_NO_PATH;
        DIR *d = opendir(out);
        struct dirent *e;
        char found[256] = "";
        if (!d) return FR_NO_PATH;
        while ((e = readdir(d)))
            if (!strcasecmp(e->d_name, part)) { snprintf(found, sizeof found, "%s", e->d_name); break; }
        closedir(d);
        if (!found[0]) {
            if (!last) return FR_NO_PATH;
            if (!create) return FR_NO_FILE;
            snprintf(found, sizeof found, "%s", part);
        }
        size_t n = strlen(out);
        snprintf(out + n, outsz - n, "/%s", found);
    }
    return FR_OK;
}

static int vf_visible(const struct dirent *e) { return e->d_name[0] != '.'; }

static int vf_next(void)
{
    struct stat st;
    char p[1300];
    vram[MB_NAME] = 0;
    put32(MB_SIZE, 0);
    vram[MB_ATTR] = 0;
    if (vf_i >= vf_n) return FR_OK;
    const char *nm = vf_list[vf_i++]->d_name;
    size_t nn = strnlen(nm, 63);
    memcpy(&vram[MB_NAME], nm, nn);
    vram[MB_NAME + nn] = 0;
    snprintf(p, sizeof p, "%s/%s", vf_dirpath, nm);
    if (stat(p, &st) == 0) {
        if (S_ISDIR(st.st_mode)) vram[MB_ATTR] = 0x10;
        else put32(MB_SIZE, (uint32_t)st.st_size);
    }
    return FR_OK;
}

static void vf_closedir(void)
{
    for (int i = 0; i < vf_n; i++) free(vf_list[i]);
    free(vf_list);
    vf_list = NULL;
    vf_n = vf_i = vf_open_dir = 0;
}

static void vdp_file(uint8_t cmd)
{
    char path[1024];
    unsigned len = vram[MB_LEN] << 8 | vram[MB_LEN + 1];
    size_t count = 0;
    struct stat st;
    int r = FR_OK;
    vram[MB_NAME + 63] = 0;
    const char *name = (const char *)&vram[MB_NAME];

    vdp_fcmds++;
    if (len > 512) len = 512;
    if (!drive_dir) { r = FR_NOT_READY; goto done; }
    switch (cmd) {
    case 0x10: case 0x11: case 0x18:            /* OPEN, CREATE, APPEND */
        if (vf_file) fclose(vf_file);
        vf_file = NULL;
        put32(MB_SIZE, 0);
        r = vf_resolve(name, path, sizeof path, cmd != 0x10);
        if (r) break;
        if (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) { r = cmd == 0x10 ? FR_NO_FILE : FR_DENIED; break; }
        vf_file = fopen(path, cmd == 0x10 ? "rb" : cmd == 0x11 ? "wb" : "ab");
        if (!vf_file) { r = cmd == 0x10 ? FR_NO_FILE : FR_DENIED; break; }
        if (cmd != 0x11 && stat(path, &st) == 0) put32(MB_SIZE, (uint32_t)st.st_size);
        break;
    case 0x12:                                  /* READ */
        if (!vf_file) { r = FR_INVALID_OBJECT; break; }
        count = fread(&vram[MB_DATA], 1, len ? len : 512, vf_file);
        break;
    case 0x13:                                  /* WRITE */
        if (!vf_file) { r = FR_INVALID_OBJECT; break; }
        count = fwrite(&vram[MB_DATA], 1, len, vf_file);
        break;
    case 0x14:                                  /* CLOSE */
        if (vf_file) fclose(vf_file);
        vf_file = NULL;
        vf_closedir();
        break;
    case 0x15:                                  /* DIR */
        vf_closedir();
        r = vf_resolve(name, path, sizeof path, 0);
        if (r == FR_NO_FILE) r = FR_NO_PATH;
        if (r) break;
        vf_n = scandir(path, &vf_list, vf_visible, alphasort);
        if (vf_n < 0) { vf_n = 0; vf_list = NULL; r = FR_NO_PATH; break; }
        snprintf(vf_dirpath, sizeof vf_dirpath, "%s", path);
        vf_open_dir = 1;
        r = vf_next();
        break;
    case 0x16:                                  /* NEXT */
        r = vf_open_dir ? vf_next() : FR_INVALID_OBJECT;
        break;
    case 0x17:                                  /* DELETE */
        r = vf_resolve(name, path, sizeof path, 0);
        if (r) break;
        if (stat(path, &st) == 0 && S_ISDIR(st.st_mode) ? rmdir(path) : unlink(path)) r = FR_DENIED;
        break;
    default:
        r = FR_INVALID_PARAMETER;
        break;
    }
done:
    if (!vf_old) vram[MB_CAPS] = 0x01;          /* FAPPEND exists */
    vram[MB_RES] = r;
    vram[MB_COUNT] = count >> 8;
    vram[MB_COUNT + 1] = count;
    vdp_fdone = 1;
}

static uint8_t vdp_read(uint16_t a)
{
    uint8_t v;
    if (!vdp_on) return 0xFF;
    switch (a & 0x0F) {
    case 0x0: v = vram[vdp_ptr];
              vdp_ptr = (vdp_ptr + (int8_t)vdp_reg[4]) & 0x1FFFF;
              return v;
    case 0x1: return vdp_ptr;
    case 0x2: return vdp_ptr >> 8;
    case 0x3: return vdp_ptr >> 16;
    case 0x7: v = (vdp_vbseen ? 0x80 : 0) | (vdp_phase < VDP_VBLANK ? 0x40 : 0) |
                  (nkeys ? 0x20 : 0) | (drive_dir ? 0x08 : 0) | (kbd_on ? 0x04 : 0) |
                  (vdp_fdone ? 0x01 : 0);
              vdp_vbseen = 0;
              vdp_fdone = 0;
              return v;
    case 0xE: if (!nkeys) return 0;             /* KEY */
              v = keys[0];
              memmove(keys, keys + 1, --nkeys);
              return v;
    case 0xF: return 0x56;
    }
    return vdp_reg[a & 0x0F];
}

static void vdp_write(uint16_t a, uint8_t v)
{
    if (!vdp_on) return;
    switch (a & 0x0F) {
    case 0x0: vram[vdp_ptr] = v;
              vdp_ptr = (vdp_ptr + (int8_t)vdp_reg[4]) & 0x1FFFF;
              break;
    case 0x1: vdp_ptr = (vdp_ptr & 0x1FF00) | v; break;
    case 0x2: vdp_ptr = (vdp_ptr & 0x100FF) | v << 8; break;
    case 0x3: vdp_ptr = (vdp_ptr & 0x0FFFF) | (v & 1) << 16; break;
    case 0x9: vdp_pal[vdp_reg[8]++] = v; break;   /* palette, steps IDX */
    case 0xD: vdp_sound++; vdp_reg[0xD] = v; break;
    case 0xE: vdp_chars++;                  /* terminal */
              if (vterm_out) { putchar(v); fflush(stdout); }
              break;
    case 0xF: if (v == 1) vdp_reset();
              else if (v >= 0x10 && v <= (vf_old ? 0x17 : 0x18)) vdp_file(v);
              break;
    default:  vdp_reg[a & 0x0F] = v; break;
    }
}

static void vdp_advance(unsigned n)
{
    if (!vdp_on) return;
    vdp_phase += n;
    while (vdp_phase >= VDP_FRAME) {
        vdp_phase -= VDP_FRAME;
        vdp_vbseen = 1;
        vdp_frames++;
    }
}

/* ---------------- memory ---------------- */
/* Wait states from the CPLD, in OSC periods (4 per E cycle): DUART 2,
 * ROM and /EXPCS1 1.  Whole E cycles are added as they accumulate. */
static unsigned osc_waits;
static void wait_states(uint16_t a)
{
    if ((a & 0xF800) == 0xC000) osc_waits += 2;                 /* DUART */
    else if (a >= 0xE000 || (a & 0xF800) == 0xC800 || ROMBANK(a)) osc_waits += 1;
    cycles += osc_waits / 4;
    osc_waits %= 4;
}

static uint8_t rd(uint16_t a)
{
    cycles++;
    wait_states(a);
    if ((a & 0xF800) == 0xC000) return io_read(a);    /* DUART, mirrored */
    if ((a & 0xF800) == 0xC800) return vdp_read(a);   /* /EXPCS1 */
    if ((a & 0xE000) == 0xC000) return 0xFF;          /* expansion: open bus */
    if (ROMBANK(a)) return romb[a & 0x3FFF];         /* ROM bank */
    if (a < 0xC000) return ram[((unsigned)mmu[a >> 14] << 14) | (a & 0x3FFF)];
    return mem[a];
}
static void wr(uint16_t a, uint8_t v)
{
    cycles++;
    wait_states(a);
    if ((a & 0xF800) == 0xC000) { io_write(a, v); return; }
    if ((a & 0xF800) == 0xC800) { vdp_write(a, v); return; }
    if ((a & 0xFFFC) == 0xD800) { mmu[a & 3] = v & 0x1F; return; }  /* MMU */
    if ((a & 0xE000) == 0xC000) return;               /* expansion */
    if (a >= 0xE000 || ROMBANK(a)) return;          /* ROM */
    ram[((unsigned)mmu[a >> 14] << 14) | (a & 0x3FFF)] = v;
}
static uint8_t f8(void) { return rd(PC++); }
static uint16_t f16(void) { uint16_t h = f8(); return (h << 8) | f8(); }
static uint16_t rd16(uint16_t a) { uint16_t h = rd(a); return (h << 8) | rd(a + 1); }
static void wr16(uint16_t a, uint16_t v) { wr(a, v >> 8); wr(a + 1, v & 0xFF); }

static jmp_buf trap_jmp;

/* 6309 behaviour: abandon the instruction and take the trap at $FFF0,
 * with MD bit 6 (illegal instruction) or bit 7 (division by zero) set */
static void illegal(uint8_t op)
{
    (void)op;
    MD |= 0x40;
    longjmp(trap_jmp, 1);
}
static void div_zero(void)
{
    MD |= 0x80;
    longjmp(trap_jmp, 1);
}

/* ---------------- flags & ALU ---------------- */
static void nz8(uint8_t r) { CC &= ~(NF | ZF); if (r & 0x80) CC |= NF; if (!r) CC |= ZF; }
static void nz16(uint16_t r) { CC &= ~(NF | ZF); if (r & 0x8000) CC |= NF; if (!r) CC |= ZF; }
static void ld8(uint8_t r) { nz8(r); CC &= ~VF; }
static void ld16(uint16_t r) { nz16(r); CC &= ~VF; }

static uint8_t add8(uint8_t a, uint8_t b, int c)
{
    unsigned r = a + b + c;
    CC &= ~(HF | VF | CF);
    if ((a ^ b ^ r) & 0x10) CC |= HF;
    if (r & 0x100) CC |= CF;
    if (~(a ^ b) & (a ^ r) & 0x80) CC |= VF;
    nz8(r);
    return r;
}
static uint8_t sub8(uint8_t a, uint8_t b, int c)
{
    unsigned r = a - b - c;
    CC &= ~(VF | CF);
    if (r & 0x100) CC |= CF;
    if ((a ^ b) & (a ^ r) & 0x80) CC |= VF;
    nz8(r);
    return r;
}
static uint16_t add16(uint16_t a, uint16_t b)
{
    uint32_t r = (uint32_t)a + b;
    CC &= ~(VF | CF);
    if (r & 0x10000) CC |= CF;
    if (~(a ^ b) & (a ^ r) & 0x8000) CC |= VF;
    nz16(r);
    return r;
}
static uint16_t sub16(uint16_t a, uint16_t b)
{
    uint32_t r = (uint32_t)a - b;
    CC &= ~(VF | CF);
    if (r & 0x10000) CC |= CF;
    if ((a ^ b) & (a ^ r) & 0x8000) CC |= VF;
    nz16(r);
    return r;
}

/* read-modify-write group: NEG COM LSR ROR ASR ASL ROL DEC INC TST CLR */
static uint8_t rmw(uint8_t op, uint8_t v)
{
    uint8_t r;
    int c = CC & CF;
    switch (op & 0x0F) {
    case 0x0: r = -v; CC &= ~(VF | CF); if (v) CC |= CF; if (v == 0x80) CC |= VF; break;
    case 0x3: r = ~v; CC &= ~VF; CC |= CF; break;
    case 0x4: CC &= ~CF; if (v & 1) CC |= CF; r = v >> 1; break;
    case 0x6: CC &= ~CF; if (v & 1) CC |= CF; r = (v >> 1) | (c ? 0x80 : 0); break;
    case 0x7: CC &= ~CF; if (v & 1) CC |= CF; r = (v >> 1) | (v & 0x80); break;
    case 0x8: CC &= ~(CF | VF); if (v & 0x80) CC |= CF;
              if ((v ^ (v << 1)) & 0x80) CC |= VF;
              r = v << 1; break;
    case 0x9: CC &= ~(CF | VF); if (v & 0x80) CC |= CF;
              if ((v ^ (v << 1)) & 0x80) CC |= VF;
              r = (v << 1) | c; break;
    case 0xA: r = v - 1; CC &= ~VF; if (v == 0x80) CC |= VF; break;
    case 0xC: r = v + 1; CC &= ~VF; if (v == 0x7F) CC |= VF; break;
    case 0xD: r = v; CC &= ~VF; break;
    case 0xF: r = 0; CC &= ~(VF | CF); break;
    default: illegal(op); return v;
    }
    nz8(r);
    return r;
}

static void daa(void)
{
    uint8_t cf = 0, lsn = A & 0x0F, msn = A >> 4;
    if ((CC & HF) || lsn > 9) cf |= 0x06;
    if ((CC & CF) || msn > 9 || (msn > 8 && lsn > 9)) cf |= 0x60;
    unsigned t = A + cf;
    if (t & 0x100) CC |= CF;
    A = t;
    nz8(A);
}

/* ---------------- addressing ---------------- */
static uint16_t *ixr(int n)
{
    switch (n & 3) { case 0: return &X; case 1: return &Y; case 2: return &U; }
    return &S;
}

static uint16_t indexed(void)
{
    uint8_t pb = f8();
    uint16_t *r = ixr(pb >> 5), ea;
    if (!(pb & 0x80)) {
        int off = pb & 0x1F;
        if (off & 0x10) off -= 32;
        cycles++;
        return *r + off;
    }
    switch (pb & 0x0F) {
    case 0x0: ea = *r; *r += 1; break;
    case 0x1: ea = *r; *r += 2; break;
    case 0x2: *r -= 1; ea = *r; break;
    case 0x3: *r -= 2; ea = *r; break;
    case 0x4: ea = *r; break;
    case 0x5: ea = *r + (int8_t)B; break;
    case 0x6: ea = *r + (int8_t)A; break;
    case 0x8: { int8_t o = f8(); ea = *r + o; } break;
    case 0x9: { uint16_t o = f16(); ea = *r + o; } break;
    case 0xB: ea = *r + GETD(); break;
    case 0xC: { int8_t o = f8(); ea = PC + o; } break;
    case 0xD: { uint16_t o = f16(); ea = PC + o; } break;
    case 0xF: ea = f16(); break;
    default: illegal(pb); return 0;
    }
    if (pb & 0x10) ea = rd16(ea);
    return ea;
}

/* mode: 0 immediate, 1 direct, 2 indexed, 3 extended */
static uint16_t ea_mode(int mode, int size)
{
    switch (mode) {
    case 0: { uint16_t e = PC; PC += size; return e; }
    case 1: return (DP << 8) | f8();
    case 2: return indexed();
    }
    return f16();
}

/* ---------------- stack ---------------- */
static void push8(uint16_t *sp, uint8_t v) { *sp -= 1; wr(*sp, v); }
static void push16(uint16_t *sp, uint16_t v) { push8(sp, v & 0xFF); push8(sp, v >> 8); }
static uint8_t pull8(uint16_t *sp) { return rd((*sp)++); }
static uint16_t pull16(uint16_t *sp) { uint16_t h = pull8(sp); return (h << 8) | pull8(sp); }

static void psh(uint16_t *sp, uint16_t other, uint8_t pb)
{
    if (pb & 0x80) push16(sp, PC);
    if (pb & 0x40) push16(sp, other);
    if (pb & 0x20) push16(sp, Y);
    if (pb & 0x10) push16(sp, X);
    if (pb & 0x08) push8(sp, DP);
    if (pb & 0x04) push8(sp, B);
    if (pb & 0x02) push8(sp, A);
    if (pb & 0x01) push8(sp, CC);
}
static void pul(uint16_t *sp, uint16_t *other, uint8_t pb)
{
    if (pb & 0x01) CC = pull8(sp);
    if (pb & 0x02) A = pull8(sp);
    if (pb & 0x04) B = pull8(sp);
    if (pb & 0x08) DP = pull8(sp);
    if (pb & 0x10) X = pull16(sp);
    if (pb & 0x20) Y = pull16(sp);
    if (pb & 0x40) *other = pull16(sp);
    if (pb & 0x80) PC = pull16(sp);
}
static void push_all(void) { CC |= EF; psh(&S, U, 0xFF); }

/* ---------------- TFR / EXG ---------------- */
static uint16_t getr(int r)
{
    switch (r) {
    case 0: return GETD(); case 1: return X; case 2: return Y; case 3: return U;
    case 4: return S; case 5: return PC;
    case 8: return 0xFF00 | A; case 9: return 0xFF00 | B;
    case 10: return 0xFF00 | CC; case 11: return 0xFF00 | DP;
    case 6: return GETW(); case 7: return V6;               /* 6309 */
    case 12: case 13: return 0;                             /* zero register */
    case 14: return 0xFF00 | RE; case 15: return 0xFF00 | RF;
    }
    return 0xFFFF;
}
static void setr(int r, uint16_t v)
{
    switch (r) {
    case 0: SETD(v); break; case 1: X = v; break; case 2: Y = v; break;
    case 3: U = v; break; case 4: S = v; break; case 5: PC = v; break;
    case 8: A = v; break; case 9: B = v; break;
    case 10: CC = v; break; case 11: DP = v; break;
    case 6: SETW(v); break; case 7: V6 = v; break;          /* 6309 */
    case 14: RE = v; break; case 15: RF = v; break;
    }
}
static int reg8(int r) { return r >= 8; }   /* A B CC DP 0 0 E F */
static void nzq(void)                        /* flags for 32-bit Q = D:W */
{
    CC &= ~(NF | ZF | VF);
    if (A & 0x80) CC |= NF;
    if (!GETD() && !GETW()) CC |= ZF;
}

static int cond(int c)
{
    int n = !!(CC & NF), z = !!(CC & ZF), v = !!(CC & VF), cy = !!(CC & CF);
    switch (c & 0xF) {
    case 0x0: return 1;           case 0x1: return 0;
    case 0x2: return !(cy || z);  case 0x3: return cy || z;
    case 0x4: return !cy;         case 0x5: return cy;
    case 0x6: return !z;          case 0x7: return z;
    case 0x8: return !v;          case 0x9: return v;
    case 0xA: return !n;          case 0xB: return n;
    case 0xC: return n == v;      case 0xD: return n != v;
    case 0xE: return !z && n == v;
    }
    return z || n != v;
}

/* ---------------- instruction execution ---------------- */
static void page2(void)
{
    uint8_t op = f8();
    uint16_t ea, t;
    int mode = (op >> 4) & 3;
    if (op >= 0x21 && op <= 0x2F) { uint16_t o = f16(); if (cond(op)) PC += o; return; }
    if (op == 0x3F) { push_all(); PC = rd16(0xFFF4); return; }       /* SWI2 */
    if (op >= 0x30 && op <= 0x37) {                 /* 6309 ADDR..CMPR r0,r1 */
        uint8_t pb = f8();
        int r0 = pb >> 4, r1 = pb & 0xF, c = CC & CF;
        uint16_t a = getr(r1), b = getr(r0), r;
        if (reg8(r1)) {
            uint8_t a8 = a, b8 = b, r8 = 0;
            switch (op) {
            case 0x30: r8 = add8(a8, b8, 0); break;  case 0x31: r8 = add8(a8, b8, c); break;
            case 0x32: r8 = sub8(a8, b8, 0); break;  case 0x33: r8 = sub8(a8, b8, c); break;
            case 0x34: r8 = a8 & b8; ld8(r8); break; case 0x35: r8 = a8 | b8; ld8(r8); break;
            case 0x36: r8 = a8 ^ b8; ld8(r8); break; case 0x37: sub8(a8, b8, 0); return;
            }
            setr(r1, r8);
        } else {
            switch (op) {
            case 0x30: r = add16(a, b); break;       case 0x31: r = add16(a, b + c); break;
            case 0x32: r = sub16(a, b); break;       case 0x33: r = sub16(a, b + c); break;
            case 0x34: r = a & b; ld16(r); break;    case 0x35: r = a | b; ld16(r); break;
            case 0x36: r = a ^ b; ld16(r); break;
            default:   sub16(a, b); return;                          /* CMPR */
            }
            setr(r1, r);
        }
        return;
    }
    switch (op) {                                   /* 6309 D and W inherent */
    case 0x38: push16(&S, GETW()); return;                          /* PSHSW */
    case 0x39: SETW(pull16(&S)); return;                            /* PULSW */
    case 0x3A: push16(&U, GETW()); return;                          /* PSHUW */
    case 0x3B: SETW(pull16(&U)); return;                            /* PULUW */
    case 0x40: SETD(sub16(0, GETD())); return;                      /* NEGD */
    case 0x43: SETD(~GETD()); ld16(GETD()); CC |= CF; return;       /* COMD */
    case 0x4A: SETD(GETD() - 1); ld16(GETD()); return;              /* DECD */
    case 0x4C: SETD(GETD() + 1); ld16(GETD()); return;              /* INCD */
    case 0x4D: ld16(GETD()); return;                                /* TSTD */
    case 0x4F: SETD(0); ld16(0); CC &= ~CF; return;                 /* CLRD */
    case 0x53: SETW(~GETW()); ld16(GETW()); CC |= CF; return;       /* COMW */
    case 0x5A: SETW(GETW() - 1); ld16(GETW()); return;              /* DECW */
    case 0x5C: SETW(GETW() + 1); ld16(GETW()); return;              /* INCW */
    case 0x5D: ld16(GETW()); return;                                /* TSTW */
    case 0x5F: SETW(0); ld16(0); CC &= ~CF; return;                 /* CLRW */
    }
    switch (op & 0xCF) {
    case 0x80: ea = ea_mode(mode, 2); SETW(sub16(GETW(), rd16(ea))); return;  /* SUBW */
    case 0x81: ea = ea_mode(mode, 2); sub16(GETW(), rd16(ea)); return;        /* CMPW */
    case 0x86: ea = ea_mode(mode, 2); SETW(rd16(ea)); ld16(GETW()); return;   /* LDW */
    case 0x87: if (!mode) break;
               ea = ea_mode(mode, 2); wr16(ea, GETW()); ld16(GETW()); return; /* STW */
    case 0x8B: ea = ea_mode(mode, 2); SETW(add16(GETW(), rd16(ea))); return;  /* ADDW */
    case 0xCC: if (!mode) break;                                              /* LDQ */
               ea = ea_mode(mode, 4); SETD(rd16(ea)); SETW(rd16(ea + 2));
               nzq(); return;
    case 0xCD: if (!mode) break;                                              /* STQ */
               ea = ea_mode(mode, 4); wr16(ea, GETD()); wr16(ea + 2, GETW());
               nzq(); return;
    case 0x83: ea = ea_mode(mode, 2); sub16(GETD(), rd16(ea)); return;  /* CMPD */
    case 0x8C: ea = ea_mode(mode, 2); sub16(Y, rd16(ea)); return;       /* CMPY */
    case 0x8E: ea = ea_mode(mode, 2); Y = rd16(ea); ld16(Y); return;    /* LDY */
    case 0x8F: if (!mode) break;
               ea = ea_mode(mode, 2); wr16(ea, Y); ld16(Y); return;     /* STY */
    case 0xCE: ea = ea_mode(mode, 2); S = rd16(ea); ld16(S); return;    /* LDS */
    case 0xCF: if (!mode) break;
               ea = ea_mode(mode, 2); wr16(ea, S); ld16(S); return;     /* STS */
    }
    (void)t;
    illegal(op);
}

static void page3(void)
{
    uint8_t op = f8();
    uint16_t ea;
    int mode = (op >> 4) & 3;
    if (op == 0x3F) { push_all(); PC = rd16(0xFFF2); return; }       /* SWI3 */
    if (op >= 0x38 && op <= 0x3B) {                 /* 6309 TFM r0,r1 */
        uint8_t pb = f8();
        int r0 = pb >> 4, r1 = pb & 0xF;
        if (r0 > 4 || r1 > 4) illegal(op);
        int d0 = (op == 0x38 || op == 0x3A) ? 1 : (op == 0x39 ? -1 : 0);
        int d1 = (op == 0x38 || op == 0x3B) ? 1 : (op == 0x39 ? -1 : 0);
        while (GETW()) {
            uint16_t s0 = getr(r0), s1 = getr(r1);
            wr(s1, rd(s0));
            setr(r0, s0 + d0);
            setr(r1, s1 + d1);
            SETW(GETW() - 1);
            cycles += 1;
        }
        return;
    }
    if (op == 0x3C) {                               /* BITMD #imm */
        uint8_t m = f8() & MD & 0xC0;
        CC &= ~ZF; if (!m) CC |= ZF;
        MD &= ~m;                                   /* reading clears them */
        return;
    }
    if (op == 0x3D) {                               /* LDMD #imm */
        static int warned;
        MD = (MD & 0xC0) | (f8() & 0x03);
        if ((MD & 1) && !warned++)
            fprintf(stderr, "\n[emu] LDMD: native mode is not emulated\n");
        return;
    }
    switch (op & 0xCF) {
    case 0x83: ea = ea_mode(mode, 2); sub16(U, rd16(ea)); return;       /* CMPU */
    case 0x8C: ea = ea_mode(mode, 2); sub16(S, rd16(ea)); return;       /* CMPS */
    case 0x86: ea = ea_mode(mode, 1); RE = rd(ea); ld8(RE); return;     /* LDE */
    case 0xC6: ea = ea_mode(mode, 1); RF = rd(ea); ld8(RF); return;     /* LDF */
    case 0x87: if (!mode) break;
               ea = ea_mode(mode, 1); wr(ea, RE); ld8(RE); return;      /* STE */
    case 0xC7: if (!mode) break;
               ea = ea_mode(mode, 1); wr(ea, RF); ld8(RF); return;      /* STF */
    case 0x81: ea = ea_mode(mode, 1); sub8(RE, rd(ea), 0); return;      /* CMPE */
    case 0xC1: ea = ea_mode(mode, 1); sub8(RF, rd(ea), 0); return;      /* CMPF */
    case 0x8D: {                                                        /* DIVD */
        ea = ea_mode(mode, 1);
        int dv = (int8_t)rd(ea), dd = (int16_t)GETD();
        if (!dv) div_zero();
        int q = dd / dv, r = dd % dv;
        CC &= ~(NF | ZF | VF | CF);
        if (q < -256 || q > 255) { CC |= VF; return; }   /* range overflow */
        if (q < -128 || q > 127) CC |= VF;               /* 2's complement */
        A = r; B = q;
        nz8(B); if (B & 1) CC |= CF;
        return;
    }
    case 0x8E: {                                                        /* DIVQ */
        ea = ea_mode(mode, 2);
        int32_t dv = (int16_t)rd16(ea);
        int32_t dd = (int32_t)(((uint32_t)GETD() << 16) | GETW());
        if (!dv) div_zero();
        int32_t q = dd / dv, r = dd % dv;
        CC &= ~(NF | ZF | VF | CF);
        if (q < -65536 || q > 65535) { CC |= VF; return; }
        if (q < -32768 || q > 32767) CC |= VF;
        SETD(r); SETW(q);
        nz16(GETW()); if (GETW() & 1) CC |= CF;
        return;
    }
    case 0x8F: {                                                        /* MULD */
        ea = ea_mode(mode, 2);
        int32_t p = (int32_t)(int16_t)GETD() * (int16_t)rd16(ea);
        SETD((uint32_t)p >> 16); SETW(p & 0xFFFF);
        CC &= ~(NF | ZF); if (p < 0) CC |= NF; if (!p) CC |= ZF;
        return;
    }
    }
    illegal(op);
}

static void step(void)
{
    uint8_t op = f8(), t;
    uint16_t ea, w;

    switch (op) {
    case 0x10: page2(); return;
    case 0x11: page3(); return;
    case 0x12: return;                                          /* NOP */
    case 0x13: sync_wait = 1; return;                           /* SYNC */
    case 0x16: w = f16(); PC += w; return;                      /* LBRA */
    case 0x17: w = f16(); push16(&S, PC); PC += w; return;      /* LBSR */
    case 0x19: daa(); return;
    case 0x1A: CC |= f8(); return;                              /* ORCC */
    case 0x1C: CC &= f8(); return;                              /* ANDCC */
    case 0x1D: A = (B & 0x80) ? 0xFF : 0; nz16(GETD()); return; /* SEX */
    case 0x1E: t = f8(); w = getr(t >> 4);                      /* EXG */
               setr(t >> 4, getr(t & 0xF)); setr(t & 0xF, w); return;
    case 0x1F: t = f8(); setr(t & 0xF, getr(t >> 4)); return;   /* TFR */
    case 0x30: X = indexed(); CC &= ~ZF; if (!X) CC |= ZF; return;
    case 0x31: Y = indexed(); CC &= ~ZF; if (!Y) CC |= ZF; return;
    case 0x32: S = indexed(); return;
    case 0x33: U = indexed(); return;
    case 0x34: psh(&S, U, f8()); return;
    case 0x35: pul(&S, &U, f8()); return;
    case 0x36: psh(&U, S, f8()); return;
    case 0x37: pul(&U, &S, f8()); return;
    case 0x39: PC = pull16(&S); return;                         /* RTS */
    case 0x3A: X += B; return;                                  /* ABX */
    case 0x3B: CC = pull8(&S);                                  /* RTI */
               if (CC & EF) pul(&S, &U, 0xFE); else PC = pull16(&S);
               return;
    case 0x3C: CC &= f8(); push_all(); cwai_wait = 1; return;   /* CWAI */
    case 0x3D: w = A * B; SETD(w);                              /* MUL */
               CC &= ~(ZF | CF); if (!w) CC |= ZF; if (w & 0x80) CC |= CF;
               return;
    case 0x3F: push_all(); CC |= IF | FF; PC = rd16(0xFFFA); return; /* SWI */
    }

    if (op >= 0x20 && op <= 0x2F) {                             /* Bcc */
        int8_t o = f8();
        if (cond(op)) PC += o;
        return;
    }

    if (op <= 0x0F || (op >= 0x40 && op <= 0x7F)) {             /* RMW group */
        int hi = op >> 4, col = op & 0x0F;
        if (hi == 4) { A = rmw(op, A); return; }
        if (hi == 5) { B = rmw(op, B); return; }
        ea = hi == 0 ? (uint16_t)((DP << 8) | f8()) : hi == 6 ? indexed() : f16();
        if (col == 0xE) { PC = ea; return; }                    /* JMP */
        if (col == 0xF) { rmw(op, 0); wr(ea, 0); return; }      /* CLR */
        t = rmw(op, rd(ea));
        if (col != 0xD) wr(ea, t);
        return;
    }

    if (op >= 0x80) {
        int isb = op & 0x40, mode = (op >> 4) & 3, col = op & 0x0F;
        uint8_t *R = isb ? &B : &A;
        if (op == 0x8D) { int8_t o = f8(); push16(&S, PC); PC += o; return; } /* BSR */
        if (op == 0xCD) {                                       /* 6309 LDQ # */
            SETD(f16()); SETW(f16());
            nzq();
            return;
        }
        switch (col) {
        case 0x3: ea = ea_mode(mode, 2); w = rd16(ea);          /* SUBD / ADDD */
                  SETD(isb ? add16(GETD(), w) : sub16(GETD(), w)); return;
        case 0xC: ea = ea_mode(mode, 2); w = rd16(ea);          /* CMPX / LDD */
                  if (isb) { SETD(w); ld16(w); } else sub16(X, w); return;
        case 0xD: if (isb) {                                    /* STD */
                      if (!mode) illegal(op);
                      ea = ea_mode(mode, 2); wr16(ea, GETD()); ld16(GETD());
                  } else {                                      /* JSR */
                      ea = ea_mode(mode, 2); push16(&S, PC); PC = ea;
                  }
                  return;
        case 0xE: ea = ea_mode(mode, 2); w = rd16(ea); ld16(w); /* LDX / LDU */
                  if (isb) U = w; else X = w; return;
        case 0xF: if (!mode) illegal(op);                       /* STX / STU */
                  ea = ea_mode(mode, 2); w = isb ? U : X; wr16(ea, w); ld16(w); return;
        case 0x7: if (!mode) illegal(op);                       /* STA / STB */
                  ea = ea_mode(mode, 1); wr(ea, *R); ld8(*R); return;
        }
        ea = ea_mode(mode, 1);
        t = rd(ea);
        switch (col) {
        case 0x0: *R = sub8(*R, t, 0); return;                  /* SUB */
        case 0x1: sub8(*R, t, 0); return;                       /* CMP */
        case 0x2: *R = sub8(*R, t, CC & CF); return;            /* SBC */
        case 0x4: *R &= t; ld8(*R); return;                     /* AND */
        case 0x5: ld8(*R & t); return;                          /* BIT */
        case 0x6: *R = t; ld8(t); return;                       /* LD */
        case 0x8: *R ^= t; ld8(*R); return;                     /* EOR */
        case 0x9: *R = add8(*R, t, CC & CF); return;            /* ADC */
        case 0xA: *R |= t; ld8(*R); return;                     /* OR */
        case 0xB: *R = add8(*R, t, 0); return;                  /* ADD */
        }
    }
    illegal(op);
}

/* ---------------- host side ---------------- */
static int hexv(const char *p, int n)
{
    int v = 0;
    while (n--) {
        char c = *p++;
        v = v * 16 + (c <= '9' ? c - '0' : (c & ~0x20) - 'A' + 10);
    }
    return v;
}

static void load_srec(const char *fn, int rombank)
{
    FILE *f = fopen(fn, "r");
    char line[600];
    if (!f) { perror(fn); exit(1); }
    if (getc(f) == 'M' && getc(f) == '9') {     /* a MINI09 .PRG file */
        uint8_t h[36];
        rewind(f);
        if (fread(h, 1, 36, f) == 36) {
            unsigned load = h[30] << 8 | h[31];
            int c;
            fseek(f, h[3], SEEK_SET);           /* past the header */
            for (unsigned a = load; (c = getc(f)) != EOF; a++) {
                a &= 0xFFFF;
                if (rombank) { if ((a & 0xC000) == 0x8000) romb[a & 0x3FFF] = c; }
                else if (a < 0xC000) ram[a] = c; else mem[a] = c;
            }
        }
        fclose(f);
        return;
    }
    rewind(f);
    while (fgets(line, sizeof line, f)) {
        if (line[0] != 'S' || line[1] != '1') continue;
        int n = hexv(line + 2, 2), addr = hexv(line + 4, 4);
        for (int i = 0; i < n - 3; i++) {
            unsigned a = (addr + i) & 0xFFFF;       /* RAM preloads go to the */
            uint8_t v = hexv(line + 8 + 2 * i, 2);  /* identity map (pages 0-2) */
            if (rombank) { if ((a & 0xC000) == 0x8000) romb[a & 0x3FFF] = v; }
            else if (a < 0xC000) ram[a] = v; else mem[a] = v;
        }
    }
    fclose(f);
}

static struct termios saved_tio;
static int tty;
static void restore_tty(void) { if (tty) tcsetattr(0, TCSANOW, &saved_tio); }

static double now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
    int fast = 0, watchdog = 0, opt;
    const char *rombank_path = NULL;
    memset(romb, 0xFF, sizeof romb);                /* an erased EEPROM */
    double linger = 2.0;
    while ((opt = getopt(argc, argv, "fvkd:wt:op:r:T")) != -1) {
        if (opt == 'f') fast = 1;
        else if (opt == 'v') vdp_on = 1;
        else if (opt == 'k') kbd_on = 1;
        else if (opt == 'd') drive_dir = optarg;
        else if (opt == 'w') watchdog = 1;
        else if (opt == 't') linger = atof(optarg);
        else if (opt == 'o') vf_old = 1;
        else if (opt == 'p') ppm_path = optarg;
        else if (opt == 'r') rombank_path = optarg;
        else if (opt == 'T') vterm_out = 1;
        else { fprintf(stderr, "usage: %s [-f] [-v [-k] [-T] [-d dir [-o]] [-p file.ppm]] [-r rom.s19] [-w] [-t secs] file.s19 ...\n", argv[0]); return 1; }
    }
    if (optind >= argc) { fprintf(stderr, "usage: %s [-f] [-v [-k] [-T] [-d dir [-o]] [-p file.ppm]] [-r rom.s19] [-w] [-t secs] file.s19 ...\n", argv[0]); return 1; }
    for (int i = optind; i < argc; i++) load_srec(argv[i], 0);
    if (rombank_path) load_srec(rombank_path, 1);

    tty = isatty(0);
    if (tty) {
        struct termios t;
        tcgetattr(0, &saved_tio);
        t = saved_tio;
        t.c_lflag &= ~(ICANON | ECHO | ISIG);
        t.c_iflag &= ~(ICRNL | IXON);
        t.c_cc[VMIN] = 0;
        t.c_cc[VTIME] = 0;
        tcsetattr(0, TCSANOW, &t);
        atexit(restore_tty);
        fprintf(stderr, "[emu] 6309 @ 3.6887 MHz - press Ctrl-] to quit\r\n");
    }

    fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);

    vdp_reset();
    CC = IF | FF;
    DP = 0;
    PC = rd16(0xFFFE);

    uint64_t last = cycles, next_io = 0, next_pace = 10000, eof_at = 0, wd_at = 0;
    int in_eof = 0;
    double t0 = now();

    for (;;) {
        int irq = du_irq() || vdp_irq();
        if (sync_wait) {
            if (irq) sync_wait = 0;
            else { cycles += 10; goto devices; }
        }
        if (irq && !(CC & IF)) {
            if (!cwai_wait) push_all();
            cwai_wait = 0;
            CC |= IF;
            PC = rd16(0xFFF8);
        } else if (cwai_wait) {
            cycles += 10;
        } else {
            if (setjmp(trap_jmp)) {             /* 6309 trap */
                push_all();
                CC |= IF | FF;
                PC = rd16(0xFFF0);
            } else {
                step();
            }
        }
devices:
        du_advance(cycles - last);
        vdp_advance(cycles - last);
        last = cycles;
        if (wd_kick) { wd_kick = 0; wd_at = cycles; }
        if (watchdog && cycles - wd_at > 1.2 * E_HZ) {   /* DS1232, TD = VCC */
            fprintf(stderr, "\n[emu] DS1232 watchdog timeout - reset\n");
            memset(du_fifo, 0, sizeof du_fifo);
            du_nfifo = du_rxen = du_txen = du_ct_running = du_mrptr = 0;
            du_isr = du_imr = du_opr = du_acr = 0;
            cwai_wait = sync_wait = 0;
            CC = IF | FF;
            DP = 0;
            PC = rd16(0xFFFE);
            wd_at = cycles;
        }

        if (cycles >= next_io) {                    /* ~1000 chars/s, like 9600 baud */
            next_io = cycles + (uint64_t)(E_HZ / 960);   /* 9600 baud */
            /* feed input while the receiver is on and RTS is asserted, or
               to the USB keyboard once the kernel takes key interrupts */
            int kbd = kbd_on && vdp_on;
            if (kbd ? (vdp_reg[6] & 4) && nkeys < (int)sizeof keys : du_can_rx()) {
                unsigned char c;
                ssize_t n = in_eof ? -1 : read(0, &c, 1);
                if (n == 1) {
                    if (tty && c == 0x1D) break;            /* Ctrl-] quits */
                    if (!tty && c == '\r') continue;       /* CRLF files */
                    if (c == '\n') c = '\r';
                    if (kbd) keys[nkeys++] = c; else du_fifo[du_nfifo++] = c;
                } else if (n == 0 && !tty) {
                    in_eof = 1;                             /* end of script */
                    eof_at = cycles;
                }
            }
            if (in_eof && cycles - eof_at > (uint64_t)(linger * E_HZ)) break;
        }
        if (!fast && cycles >= next_pace) {
            next_pace += 10000;
            double ahead = cycles / E_HZ - (now() - t0);
            if (ahead > 0.002) usleep((useconds_t)(ahead * 1e6));
        }
    }
    printf("\n");
    if (vdp_on && ppm_path && (vdp_reg[5] == 1 || vdp_reg[5] == 4)) {
        int w = vdp_reg[5] == 1 ? 320 : 256, h = vdp_reg[5] == 1 ? 240 : 192;
        unsigned base = (vdp_reg[0xA] | (vdp_reg[0xB] & 0x1F) << 8) * 16;
        FILE *f = fopen(ppm_path, "wb");
        if (f) {
            fprintf(f, "P6\n%d %d\n255\n", w, h);
            for (int i = 0; i < w * h; i++) {
                uint8_t c = vdp_pal[vram[(base + i) & 0x1FFFF]];
                putc((c >> 5) * 255 / 7, f);
                putc((c >> 2 & 7) * 255 / 7, f);
                putc((c & 3) * 255 / 3, f);
            }
            fclose(f);
        }
    }
    if (vdp_on)
        fprintf(stderr, "[emu] video chip: %lu frames, %lu terminal chars, %lu sound writes, "
                "%lu file commands\n", vdp_frames, vdp_chars, vdp_sound, vdp_fcmds);
    return 0;
}
