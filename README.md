# MINI09 — a multitasking OS for the 6809 / 6309

A small preemptive multitasking kernel and shell in 6809 assembly
(about 2 KB of ROM), plus a C emulator of the target board so you can
run it without hardware.

## Files

| File | What it is |
|------|------------|
| `os.asm` | Kernel, user library, shell, demo tasks, vectors |
| `edit.asm` | EDIT, the full-screen text editor: `EDIT.PRG` on the drive, which the shell's `EDIT` command runs |
| `mc.asm` | MC, a two-panel file manager after Midnight Commander: `MC.PRG` on the drive, run by typing `MC` |
| `tools/mctest.py` | Types keys at MC in the emulator and checks the screen it leaves (`make test-mc`) |
| `edit-screenshot.png` | `EDIT` on the HDMI screen (in the README) |
| `syscalls.inc` | System-call numbers and the `OS` macro, shared with user programs |
| `hello.asm` | Example user program, loaded at runtime with `L` or from the drive as `HELLO.PRG` |
| `tools/mkprg.py` | Makes a `.PRG` program file from S-records (`make` does it for the examples), or shows a `.PRG`'s header (`--info`) |
| `basic.asm` | MINI09 BASIC, a floating-point BASIC run from the flash drive (`BASIC.PRG`), or from the ROM bank (`BASIC`, built with `-D ROMBASIC` into `basic-rom.s19` and `mini09-rom32.bin`) |
| `examples/*.bas` | BASIC example programs (`make test-basic` copies them to a scratch drive) |
| `cpu6309.asm` | HD63C09E test: 6309 detection, extra instructions, divide-by-zero trap (`make test-6309`) |
| `vdp.inc` | Register numbers for the Pico 6809 video/sound chip |
| `vdpdemo.asm` | Video/sound demo program: a tune, a bouncing ball, frame timing |
| `asm.asm`, `asm.md` | ASM, a 6809/6309 macro assembler that runs under MINI09 (`ASM FILE.ASM [-L]`) and assembles itself; with sections it writes lwasm-format `.O` objects. `asm.md` is its design |
| `link.asm` | LINK, links `.O` files into a `.PRG` under MINI09 (`LINK OUT.PRG A.O B.O`), placed like lwlink; see `asm.md` |
| `tools/asmtest.py`, `asmtests/` | Compares ASM's output with lwasm's in the emulator (`make test-asm`); `allops.asm` and `ops6309.asm` have every opcode in every mode |
| `tools/objtest.py`, `tools/mini09.ld`, `asmtests/obj/` | Checks ASM's `.O` files and LINK.PRG against lwasm and lwlink (`make test-obj`, needs lwlink) |
| `tools/pylink.py` | The same linker as LINK.PRG in Python, with banked code (which lwlink can't place): `pylink.py OUT.PRG A.O B.O [--map]` |
| `emu6809.c` | 6809 CPU (6309 emulation mode, with its illegal-opcode trap) + SCN2681 DUART emulator, and the video chip with `-v` |
| `test/` | Scripted shell session used by `make test` |
| `hw/schematic.svg`, `.pdf` | Board schematic |
| `hw/netlist.txt` | Netlist, generated from the same source as the schematic |
| `hw/schematic.py` | Script that generates the schematic and netlist (`make schematic`) |
| `hw/pld/mini09.pld`, `MINI09.jed` | U5 ATF750C glue logic: CUPL source and JEDEC programming file (`make pld`) |
| `hw/mini09.kicad_sch` | KiCad 9 schematic, linked to the PCB (`make kicad-sch`) |
| `hw/mini09.kicad_sym`, `hw/sym-lib-table` | Project symbols: SCN2681AC1N28 (28-pin), ATF750C, DS1232 |
| `hw/mini09.kicad_pcb`, `.kicad_pro` | KiCad 9 PCB: 195 × 115 mm, 2 layers, all through-hole |
| `hw/mini09-gerbers.zip` | Gerbers and drill files to send to a PCB fab |
| `hw/kicad_sch.py`, `hw/pcb.py`, `hw/route.py`, `hw/finish.py` | Scripts that build the KiCad schematic and the board (`make pcb`) |

## Build and run

Needs [lwtools](http://www.lwtools.ca/) (`lwasm`) and gcc.

```bash
make run
```

Press Ctrl-] to quit the emulator. `make test` runs a scripted session.
`make run-vdp` and `make test-vdp` do the same with the video/sound chip
fitted (registers and frame interrupt only; the console stays on your
terminal).

**Console.** `CONSOLE` picks where the console goes; changing it rebuilds
the kernel and the ROM images.

| Build | Output | Input | Use |
|-------|--------|-------|-----|
| `make` (`CONSOLE=both`) | serial port and HDMI screen | both | the default |
| `make CONSOLE=serial` | serial port | serial port | a board driven from a terminal; the video card still does graphics, sound and files |
| `make CONSOLE=vdc` | HDMI screen | USB keyboard and serial port | a stand-alone computer |

- **Speed in the `vdc` build:** output doesn't wait for the 9600-baud
  DUART. Printing 200 lines of BASIC output takes about 0.9 s instead of
  about 8 s.
- **Without a card:** a `vdc` build uses the serial port if no video card
  answers at boot.
- **Testing:** `make test-console` runs both variants in the emulator.

## Hardware

The schematic is [hw/schematic.pdf](hw/schematic.pdf), and the KiCad
version is [hw/mini09.kicad_sch](hw/mini09.kicad_sch). The parts are:

- **CPU (U1):** Hitachi HD63C09E. This is the external-clock 6309, so it
  needs separate E and Q clock inputs.
- **RAM (U2):** AS6C4008 SRAM (512K), all of it reachable through the MMU.
- **MMU (U7 + U5):** a 74HC670 plus four registers inside the CPLD. Together
  they map 16K pages of the SRAM into the CPU's address space.
- **ROM (U3):** 28C256 EEPROM (32K) holding the kernel and a 16K bank
  for ROM BASIC (see "ROM bank" below). A 28C64 (8K, the kernel only)
  also fits.
- **I/O (U4):** SCN2681AC1N28 DUART.
- **Glue logic (U5):** one ATF750C PLD. It does:
  - address decoding;
  - the /RD and /WR strobes;
  - the E/Q clock generator with MRDY stretching.
- **Reset (U6):** DS1232 MicroMonitor. It does:
  - power-on reset, held for at least 250 ms;
  - a debounced reset button (SW1);
  - a watchdog.

  Its open-drain /RST output (with pull-up R10) resets the CPU and goes to
  the expansion header. Its push-pull RST output drives the DUART's
  active-high RESET directly. TOL is tied to VCC, so the trip point is
  4.37 V, which tolerates a slightly low USB supply.
- **Clock (X1):** 14.7546 MHz half-can oscillator. U5 divides it by 4 to
  give E and Q at 3.6887 MHz, with Q leading E by 90°.
  - The HD63C09EP is rated for 3 MHz, so this runs it about 23% over its
    rating.
  - Slow devices get automatic wait states (below).
  - A stock 14.7456 MHz part works the same way.
  - The DUART has its own 3.6864 MHz crystal, so baud rates and the 100 Hz
    tick don't depend on X1.
- **Unused CPU pins:** TSC is tied low. LIC, AVMA and BUSY are outputs and
  are left unconnected.

### U5: ATF750C glue logic

Source: [hw/pld/mini09.pld](hw/pld/mini09.pld). The JEDEC programming
file is [hw/pld/MINI09.jed](hw/pld/MINI09.jed); `make pld` rebuilds it
with WinCUPL under Wine.

```
Q.d     = !E                  Johnson counter on OSC (pin 1): E, Q = OSC/4
E.d     = Q # HOLD            Q leads E by 90 deg
HOLD    = E & !Q & (!MRDY # wait state needed)   W1..W0 count the waits
RD      = E & R/W             outputs active low
WR      = E & !R/W
ROMCS   = A15 & A14 & A13     $E000-$FFFF
        # A15 & !A14 & PG3    $8000-$BFFF while the ROM bank is on
DUARTCS = A15 & A14 & !A13 & !A12 & !A11   $C000-$C7FF
EXPCS1  = A15 & A14 & !A13 & !A12 & A11    $C800-$CFFF
MMUWR   = E & !R/W & A15 & A14 & !A13 & A12 & A11   $D800-$D803
RAMCS   = !A15 # !A14 & !PG3  $0000-$BFFF, but not the ROM bank
PGn.d   = D4                  clocked as Q falls in a write to $D80n
MA18    = PGn for the window picked by A15..A14
```

**MRDY** is active high and pulled up by R4; devices pull it low through
J4 pin 38 (it is open-drain). While MRDY is low, the counter holds in the state
with E high and Q low:
- E, /RD and /WR stretch in steps of one oscillator period (68 ns).
- MRDY must be low within about 100 ns of E rising.
- Keep stretches short: the 6809E family limits how long E may stay high.

**Spare:** input 13 (tied to GND).

### Banked RAM (U7 74HC670 + U5)

There are four 5-bit page registers, one for each 16K window of the CPU's
address space. A write to one of them updates two places at once:
- **U7 (74HC670)** stores page bits 0–3 (from D3–D0) and drives SRAM
  A17–A14.
- **U5 (the CPLD)** stores page bit 4 (from D4) in four buried
  registers, one per window. It outputs the one for the current window
  on MA18, which drives SRAM A18. Each register loads as Q falls during
  the write; the data and address are stable by then, and an MRDY stretch
  adds no extra clock edges.
- **Lookup:** CPU A15 and A14 pick the register. Its contents drive SRAM
  A18–A14, so each window can show any of 32 pages of 16K (the full 512K).
- **Writing:** the registers are write-only, at `$D800–$D803`. A1 and A0
  pick the register, and D4–D0 are the page.

| Register | CPU window | Set at reset | Use |
|----------|-----------|--------------|-----|
| `$D800` | `$0000–$3FFF` | page 0 | kernel, stacks, programs |
| `$D801` | `$4000–$7FFF` | page 1 | programs |
| `$D802` | `$8000–$BFFF` | page 2 | banked: one page per task |
| `$D803` | `$C000–$FFFF` | bit 4 = 0 | bit 4 (PG3) switches the ROM bank in at `$8000–$BFFF` |

The page registers power up holding random values. So the reset code writes pages
0, 1 and 2 before it touches RAM, including the stack, and clears `$D803`.

Each task has its own page for `$8000–$BFFF`, kept in its task record;
the scheduler loads it into `$D802` on every switch. A task picks its page
with the `SYS_BANK` system call, or from the shell with `BANK n`. Pages
`$03–$1F` are extra memory (29 pages, 464K). Pages 0 and 1 are refused,
because they already hold `$0000–$7FFF`.

### ROM bank (U3 28C256 + U5)

The `$C000` window is never RAM, so its page-bit-4 register in U5 (PG3) is
free. It switches a ROM bank in at `$8000–$BFFF`: while PG3 is set, U5
selects U3 there instead of the SRAM, with the same one wait state as at
`$E000`.

**Wiring:** U3's A14 (pin 1) and A13 (pin 26) go straight to the CPU's.
So:
- CPU `$8000–$BFFF` reads ROM `$0000–$3FFF`;
- CPU `$E000–$FFFF` reads ROM `$6000–$7FFF`;
- ROM `$4000–$5FFF` is unused.

**Images:** `make` builds `mini09-rom32.bin` for a 28C256, holding ROM BASIC
and the kernel. `os-rom.bin` is the kernel alone, for a 28C64. With a
28C64 the bank only mirrors the kernel, and the shell's `BASIC` command
says `No BASIC ROM`.

**Software:** the kernel treats the bank as page `$80`.
- `SYS_BANK` with B = `$80` selects it for the calling task.
- The scheduler writes bit 4 of `$D803` along with `$D802` on every task
  switch, so each task sees its own RAM page or the ROM.

### Watchdog (U6 DS1232, JP2)

The DS1232's watchdog cannot be disabled; its strobe input /ST must see a
falling edge before the timeout. TD is tied to VCC, giving 1.2 s typical
and 0.5 s minimum. JP2 picks the strobe source:

| JP2 | /ST source | Effect |
|-----|-----------|--------|
| 1–2 | DUART OP1 | Watchdog on: the kernel pulses OP1 on every 100 Hz tick |
| 2–3 | E clock | Watchdog effectively off |

With 1–2 fitted, the board resets if timer interrupts stop for more than
half a second. That happens if the kernel crashes, or if a program masks
interrupts and hangs. To try it in the emulator, run `./emu6809 -w os.s19`
and then enter `W 1000 1A 50 20 FE` and `G 1000`.

| Address | Device |
|---------|--------|
| `$0000-$BFFF` | RAM (`$8000-$BFFF`: a task's page, or the ROM bank) |
| `$C000-$C00F` (mirrored to `$C7FF`) | SCN2681 DUART (28-pin SCN2681AC1N28), 3.6864 MHz crystal |
| `$C800-$CFFF` | Expansion, /EXPCS1 (J4 pin 33): Pico 6809 video/sound chip if fitted |
| `$D000-$D7FF` | Unused |
| `$D800-$D803` | MMU page registers (U7, write only) |
| `$D804-$DFFF` | Unused |
| `$E000-$FFFF` | ROM |

The CPU runs with a 3.6887 MHz E clock: a 271 ns cycle with E high for
136 ns. Slower devices get wait states from U5, each one holding E high
for one more oscillator period (68 ns):

| Access | Wait states | E high | Reason |
|--------|-------------|--------|--------|
| RAM, MMU | 0 | 136 ns | 55 ns SRAM plus the 74HC670's delay fits easily |
| ROM (and the ROM bank) | 1 | 203 ns | a 150 ns 28C256 is marginal without it |
| /EXPCS1 | 1 | 203 ns | the Pico card's read data arrives at Q + 170 ns |
| DUART | 2 | 271 ns | the 2681 needs strobes of at least 225 ns |

The 2681 also needs 200 ns between strobes, but E is low for only 136 ns.
Every normal instruction has other bus cycles between two DUART accesses,
so this holds. Don't use 16-bit loads or stores (LDD, STD, LDQ...) on
DUART registers.

The DUART is the only on-board peripheral:

- **Channel A:** console at 9600 baud, 8N1, interrupt on received character.
- **OP0:** RTS for channel A, used for flow control.
- **Counter/timer:** timer mode, clocked from the crystal, preload `$4800`.
  This gives a 100 Hz square wave and one counter-ready interrupt per
  cycle. Reading `$C00F` (stop counter) clears the interrupt; in timer
  mode it does not stop the timer.
- **/INTR:** wired to the CPU's /IRQ input. It is open-drain, so it needs a
  pull-up.

The 2681 was designed for a 68000-style bus. The points that matter when
wiring it to a 6309:

- Its RESET input is **active high**, unlike the CPU's /RESET.
- Drive /RDN and /WRN from E and R/W.
- Leave /IACKN tied high. The 6309 doesn't run interrupt-acknowledge
  cycles; the kernel just reads the ISR.

The 28-pin package has only IP0–IP2 and OP0–OP1. MINI09 uses only OP0,
plus the internal timer.

### Expansion header (J4)

J4 is a 2×20 pin header (0.1 in pitch) along the top edge of the board.
Odd-numbered pins are on the row nearer the chips.

| Pin | Signal | Pin | Signal |
|-----|--------|-----|--------|
| 1 | GND | 2 | +5V |
| 3 | D0 | 4 | D1 |
| 5 | D2 | 6 | D3 |
| 7 | D4 | 8 | D5 |
| 9 | D6 | 10 | D7 |
| 11 | A0 | 12 | A1 |
| 13 | A2 | 14 | A3 |
| 15 | A4 | 16 | A5 |
| 17 | A6 | 18 | A7 |
| 19 | A8 | 20 | A9 |
| 21 | A10 | 22 | A11 |
| 23 | A12 | 24 | A13 |
| 25 | A14 | 26 | A15 |
| 27 | GND | 28 | E |
| 29 | Q | 30 | R/W |
| 31 | /RD | 32 | /WR |
| 33 | /EXPCS1 | 34 | (not connected) |
| 35 | /IRQ | 36 | /FIRQ |
| 37 | /NMI | 38 | MRDY |
| 39 | /RESET | 40 | +5V |

- **Chip select:** /EXPCS1 is active low and covers `$C800–$CFFF` (2K).
  It is decoded from the address alone, so combine it with /RD or /WR,
  which are already qualified by E.
- **Shared lines:** /IRQ, /FIRQ, /NMI and MRDY are open-drain with
  on-board pull-ups. Cards should only pull them low.
- **Bus loading:** the bus is unbuffered, so keep expansion cards to a few
  HC/HCT loads.

### Video/sound card (Pico 6809 on J4)

The [pico6809](../6809-pico2/pico6809) firmware turns a Pico 2 W into a
memory-mapped chip with HDMI output (640x480, text and bitmap modes) and
an AY-3-8910 style sound generator. On MINI09 it sits on /EXPCS1, so its
16 registers appear at `$C800-$C80F` (and repeat every 16 bytes up to
`$CFFF`).

Two 74LVC245s powered from the Pico's 3.3 V keep 5 V off the Pico:

| J4 pin | Signal | Through | Pico |
|--------|--------|---------|------|
| 3-10 | D0-D7 | U1 B side ↔ A side | GP0-GP7 |
| 11-14 | A0-A3 | U2 | GP8-GP11 |
| 30 | R/W | U2, and U1 DIR directly | GP20 |
| 33 | /EXPCS1 | U2 | GP21 (/CS) |
| 28 | E | U2 | GP22 |
| 29 | Q | U2 | GP26 |
| 35 | /IRQ | 2N7000/BSS138 drain (source to GND) | GP27 to the gate |
| 2 / 40 | +5V | Schottky diode (1N5817) to VBUS | pin 40 VBUS |
| 1 / 27 | GND | | any GND pin |

- **U1** (data): A side to GP0-7, B side to D0-7, DIR from R/W (high = card
  drives the bus), /OE from GP28. Add a **10k pull-up from /OE to 3.3 V**
  so U1 stays off while the Pico boots or is being reflashed.
- **U2** (inputs): DIR tied high, /OE tied to GND, VCC from the Pico's
  3V3(OUT) (pin 36), like U1.
- **/IRQ:** add a **100k pull-down on the MOSFET gate** so a booting Pico
  can't hold /IRQ low. /IRQ is shared with the DUART; the kernel checks both
  on every interrupt.
- **Power:** the diode feeds the Pico's VBUS, so the USB port can power a
  keyboard and flash drive (the Pico runs from VBUS through its own diode).
  The card draws about 100 mA from the board's 5 V, plus the USB devices.
  For flashing, unplug the OTG adapter and plug the PC in as usual; the
  diode keeps the PC's 5 V and the board's 5 V apart.
- **USB:** the Pico's micro-USB port is a USB host. Use a micro-USB OTG
  adapter and a small hub (powered if the drive draws a lot), then plug in
  a keyboard and a FAT16/FAT32 flash drive.
- **Timing at 3.6887 MHz:** /EXPCS1 comes from the address alone, which is
  what the card wants (it samples /CS about 70 ns after Q rises, before E).
  Read data is on the bus about 170 ns after Q rises. U5 gives /EXPCS1 one
  wait state, so E falls 271 ns after Q rises, not 203 ns. That leaves room
  for the 6309's set-up time; without the wait state it would be too tight.
  The card doesn't use /RD, /WR or MRDY.
- HDMI uses GP12-GP19, as in the hdmi-hstx project.

What the kernel does with it:

- **Boot:** reads the ID register (`$C80F` = `$56`) for up to 0.2 s, since
  the Pico may still be starting. If it answers, the kernel resets the chip
  (80x30 text) and turns on its vblank interrupt. Without the card nothing
  changes, apart from that 0.2 s at boot.
- **Console:** every character the kernel sends to the DUART also goes to
  the chip's terminal register (`$C80E`). The firmware handles the cursor,
  scrolling and a VT100 subset (cursor movement, erase, colours), so the
  HDMI screen shows the same session as the serial terminal. A
  `CONSOLE=vdc` build writes only to the chip, and a `CONSOLE=serial`
  build only to the DUART (see "Build and run").
- **Frame interrupt:** 60 times a second the chip pulls /IRQ. The handler
  reads STATUS (which releases /IRQ), counts frames and wakes tasks
  waiting in `SYS_VSYNC`.
- **Keyboard:** a USB keyboard on the card types into the console, next to
  the serial port (not in a `CONSOLE=serial` build). The chip interrupts
  when a key is waiting and the handler moves one key per interrupt into
  the input buffer. Keys are only taken while that interrupt is on, so
  they wait in the chip's FIFO while the input buffer is full. Arrow and
  function keys send VT100 sequences, which the shell's line editor skips.
- **Flash drive:** files on a USB flash drive through `SYS_FCMD`, and the
  shell's `DIR`, `TYPE`, `LOAD`, `SAVE` and `DEL`, and any program file
  runs by typing its name.
- **System calls:** `SYS_VSYNC`, `SYS_SOUND`, `SYS_VREG`, `SYS_VCOPY`,
  `SYS_VREAD` and `SYS_FCMD` (below). They run with interrupts masked, so
  two tasks can share the chip without corrupting each other's register
  sequences. User programs should use them and not touch `$C800` directly.

## PCB

The board is 195 × 115 mm with two layers. All parts are through-hole,
and it has M3 mounting holes in the corners.

`make pcb` rebuilds everything from `hw/netlist.txt` in these steps:
1. Generates the KiCad schematic, which must pass KiCad's electrical
   rules check.
2. Exports KiCad's netlist from the schematic.
3. Places the footprints, linked to their schematic symbols.
4. Autoroutes with Freerouting (kept in `hw/tools/`, needs Java 21). A
   result with anything left unrouted is retried.
5. Removes leftover track stubs.
6. Adds GND pours on both layers, with stitching vias.
7. Runs KiCad's design rule check, which must pass. It also checks the
   board against the schematic.
8. Exports the Gerbers and the renders.

Active-low nets are named with KiCad overbars (`~{RESET}`), where
`hw/netlist.txt` writes `/RESET`.

Routing rules:
- **Signal tracks:** 0.25 mm wide, 0.2 mm clearance.
- **Power tracks (VCC, GND):** 0.6 mm wide.

The 6 mil spacing this implies is within the standard limits of common
low-cost fabs.

## RAM use

| Address | Use |
|---------|-----|
| `$0000-$005F` | Kernel variables + 8 task control blocks (direct page) |
| `$0100-$013F` | Console input ring buffer |
| `$0200-$02EA` | Shell line buffer and variables |
| `$0300-$0347` | The command line of a program the shell runs, with `.PRG` added |
| `$0400-$0BFF` | 8 task stacks, 256 bytes each |
| `$0C00-$0DFF` | Shell file buffer (LOAD, TYPE, SAVE) |
| `$0E00-$0E40` | The arguments for a program the shell runs: `ARGMARK`, then the text (`ARGS` in syscalls.inc) |
| `$1000-$7FFF` | Free for user programs (pages 0–1, fixed) |
| `$8000-$BFFF` | Banked window: each task's own page (default page 2) |

## Testing the HD63C09E(P)

`cpu6309.asm` is a program you load and run (`L`, then `G 1000`). It
checks that the CPU really is a 6309 and that its extra instructions work
in the power-up mode the kernel uses:

| Test | What it checks |
|------|----------------|
| 6309 detect | `$10 $43` is COMD on a 6309 but COMA on a 6809 |
| LDQ / STQ / W | 32-bit Q = D:W, loaded, stored and read back |
| E and F | the extra 8-bit registers that make up W |
| MULD | signed 16 × 16 → 32 |
| DIVD | signed 16 ÷ 8 → quotient in B, remainder in A |
| DIVQ | signed 32 ÷ 16 → quotient in W, remainder in D |
| TFM | 16-byte block move; W counts down to 0 |
| ADDR / CMPR | register-to-register add and compare |

Finally it divides by zero. A 6309 traps through `$FFF0`, so the kernel
should print a trap message and kill the test task while the shell keeps
running. On a 6809 the first test reports that the CPU isn't a 6309.

`make test-6309` runs it in the emulator, which implements these 6309
instructions and the trap (illegal opcode or divide by zero, with the MD
register's flag bits). Native mode is not emulated.

## How the kernel works

**6309 mode.** After reset the 6309 runs in 6809 emulation mode. MINI09
leaves it there, so the kernel is plain 6809 code and interrupt frames
stay 12 bytes. In native mode the CPU would also push its W register,
and the frame offsets in `os.asm` would have to change.

**Traps.** The 6309 jumps through the `$FFF0` vector on an illegal
opcode or a divide by zero. MINI09 kills the task that caused it and
prints a message. If that task was the shell, a fresh shell is started.
The emulator traps the same way, so you can try it:
`W 1000 87` then `G 1000`.

**Context switching.** On the 6809, an IRQ or SWI pushes every register
(CC with E=1, A, B, DP, X, Y, U, PC) onto the stack. A task switch
therefore only needs three steps:
1. Store S in the current TCB.
2. Load S from the next TCB.
3. Execute `RTI`.

New tasks are given a stack holding a fake interrupt frame, so they start
the same way a preempted task resumes. Below that frame is the address of
`task_exit`, so a task that ends with `RTS` terminates cleanly.

**Scheduling.** Each timer tick does three things:
1. Counts down the sleeping tasks.
2. Wakes any whose count reaches zero.
3. Switches to the next READY task, round robin over tasks 1–7.

When no task is ready, task 0 (the idle task) runs `SYNC`.

**System calls** are `SWI` followed by a function-code byte, like OS-9:

```asm
        ldd     #100
        OS      SYS_SLEEP       ; expands to: swi / fcb 4
```

The handler finds the code byte through the saved PC and calls the
matching routine. Arguments and results are read and written directly in
the caller's saved register frame. Carry set means an error.

**Blocking calls are retried, not resumed.** If `GETC` finds no input,
it marks the task as INPUT and moves the saved PC back onto the `SWI`.
The receive interrupt later makes the task READY, and it simply runs the
system call again. `PUTC` uses the same trick when the transmitter is
busy. This removes the need for wait queues or per-call state.

**Console input.** The receive interrupt drains the DUART's 3-byte FIFO
into a 64-byte ring buffer.

**Flow control.** When the ring buffer fills to 48 bytes, the kernel
negates RTS on OP0 (it writes to the reset-OP-bits register at `$C00F`).
Once `GETC` has drained the buffer below 16 bytes, it asserts RTS again
(it writes to the set-OP-bits register at `$C00E`).

| # | Call | In | Out |
|---|------|----|-----|
| 0 | `SYS_EXIT` | — | — |
| 1 | `SYS_PUTC` | A = char | — |
| 2 | `SYS_GETC` | — | A = char (blocks) |
| 3 | `SYS_YIELD` | — | — |
| 4 | `SYS_SLEEP` | D = ticks | — |
| 5 | `SYS_SPAWN` | X = entry | B = pid, C=1 if no slot |
| 6 | `SYS_KILL` | B = pid | C=1 if no such task |
| 7 | `SYS_GETPID` | — | B = pid |
| 8 | `SYS_TIME` | — | D = ticks, X = seconds |
| 9 | `SYS_BANK` | B = page 2–31, `$80` for the ROM bank, or `$FF` to ask | A = previous page, C=1 if invalid |
| 10 | `SYS_VSYNC` | — | waits for the next video frame; D = frame count |
| 11 | `SYS_SOUND` | A = value, B = sound register | — |
| 12 | `SYS_VREG` | B = video register, A = value; B + `$80` reads | A = value read |
| 13 | `SYS_VCOPY` | X → block: VRAM address (3 bytes, high first), source (2), count (2) | block used up |
| 14 | `SYS_VREAD` | X → the same block, copies VRAM to RAM | block used up |
| 15 | `SYS_FCMD` | A = file command | A = result, X = byte count, C=1 if A ≠ 0 |
| 16 | `SYS_POLL` | — | A = char, C=1 if none is waiting (doesn't block) |
| 17 | `SYS_BREAK` | — | C=0 if a ^C is waiting; the input up to and including it is dropped |

Calls 10–15 drive the video/sound chip and return C=1 if it isn't fitted.
Register numbers are in `vdp.inc`. Sound registers 0–13 are the
AY-3-8910's (2 MHz clock), 14 is an 8-bit DAC and 15 the master volume.
`SYS_VREG` keeps the kernel's interrupts enabled and refuses to read
STATUS or KEY, since the kernel needs them. `SYS_VCOPY` copies 32 bytes at a time
and re-runs itself until the count reaches 0, so interrupts are served
during long copies; it advances the address and source in the block as it
goes. Screen memory for 80x30 text is 2 bytes per cell (character, then
attribute: background in bits 7–4, foreground in bits 3–0), 160 bytes
per row from VRAM address 0.

**Files.** The flash drive is driven through a mailbox in VRAM page 1
(`VF_*` in `vdp.inc`): copy the path to `VF_NAME` (NUL-terminated) and,
for a write, the data to `VF_DATA` and its length to `VF_LEN` with
`SYS_VCOPY`, then call `SYS_FCMD` with a command:

| A | Command | Does |
|---|---------|------|
| `$10` | `VCMD_FOPEN` | open for reading; size in `VF_SIZE` |
| `$11` | `VCMD_FCREATE` | create or truncate for writing |
| `$12` | `VCMD_FREAD` | read up to `VF_LEN` bytes (0 = 512) into `VF_DATA`; X = 0 at the end |
| `$13` | `VCMD_FWRITE` | write `VF_LEN` bytes from `VF_DATA` |
| `$14` | `VCMD_FCLOSE` | close the file (flushes) and any directory |
| `$15` | `VCMD_DIR` | open directory `VF_NAME` (empty = root), first entry in `VF_NAME`, `VF_SIZE`, `VF_ATTR` |
| `$16` | `VCMD_DIRNEXT` | next entry; `VF_NAME` empty at the end |
| `$17` | `VCMD_FDELETE` | delete a file or empty directory |
| `$18` | `VCMD_FAPPEND` | open for writing at the end (created if new); size in `VF_SIZE`. Needs pico6809 firmware from 2026-10-21 on |

Firmware from before `VCMD_FAPPEND` ignores command `$18`, and a `SYS_FCMD`
with it would never finish. So check first: write 0 to `VF_CAPS`, run any
other command (an `FCLOSE` does nothing harmful), and read `VF_CAPS` back.
Firmware with `FAPPEND` sets bit 0 after every command. BASIC's `OPEN ... FOR
APPEND` does this.

Read data and directory entries back with `SYS_VREAD`. Results are FatFs
codes: 0 OK, 3 no drive, 4 no such file, 5 no such path, 7 denied or disk
full, 8 exists, 9 no file open, 13 not FAT. The calling task sleeps (state
FILEIO) while the chip works and other tasks keep running. One task at a
time has the drive: from its first command until `FCLOSE`, `FDELETE` or an
error, and another task's `SYS_FCMD` waits until then. A task that ends
gives the drive back.

A new task starts with B = its own pid and DP = 0.

## Shell

```
HELP          this list
PS            list tasks
D [addr]      dump memory (repeat D to continue)
W addr bb ..  write bytes
G addr        start task at addr
K pid         kill task
L             load S-records
UP            uptime
COUNT         demo: counting task
SPIN          demo: CPU-bound task (preemption keeps the shell alive)
BANK [n]      show or set the shell's page at $8000-$BFFF (2-1F)
CLS           clear the screen (ANSI, so the serial terminal clears too)
BEEP          1 kHz beep on the video chip's sound generator
VDP           video chip status: present, and the frame counter
DIR [path]    list the USB flash drive (size, or [DIR], and name)
TYPE file     show a text file
LOAD [file]   load a program file (no name: S-records from the console)
SAVE f s e [c] save memory s..e (hex) as program file f, entry s, creator c
DEL file      delete a file
BASIC         BASIC in the ROM bank (a 28C256 in U3), wait until it ends
name [args]   run NAME.PRG from the drive (see below)
EDIT [file]   the text editor, EDIT.PRG
```

**Running programs.** Any word that isn't one of the commands above is
a program on the drive: `ASM HELLO.ASM` loads `ASM.PRG`, starts it at its
entry address and waits until it ends. A word with an extension is used
as it is (`DEMOS/VDPDEMO.PRG`), so `BASIC.PRG` runs the BASIC on the
drive while `BASIC` runs the one in the ROM. The rest of the line goes to
the program (`ARGS`, see syscalls.inc). If there is no such file the
shell says `Unknown command`.

Names are upper-cased by the line editor; FAT doesn't mind. Paths use
`/`, e.g. `GAMES/MAZE`. LOAD and running a program use `$0C00-$0DFF` as a file
buffer, so programs must load elsewhere (`$1000` up is fine).

**Program files.** Programs on the drive are `.PRG` files: a 36-byte
header, then the bytes to load (numbers big-endian):

| Offset | Bytes | Field |
|--------|-------|-------|
| 0 | 2 | `M9`, the magic |
| 2 | 1 | format version, 1 |
| 3 | 1 | header length, 36 (a loader skips anything past 36) |
| 4 | 12 | name, NUL-padded (the file name, without directory) |
| 16 | 8 | creator, NUL-padded: what made the file |
| 24 | 4 | date: year (2 bytes), month, day; all 0 if unknown |
| 28 | 2 | file size, header included |
| 30 | 2 | load address |
| 32 | 2 | entry address |
| 34 | 2 | 0 (reserved) |

How the fields get filled:
- **On the PC:** `tools/mkprg.py prog.s19 PROG.PRG` makes one from the
  assembler's S-records, dated today with creator `LWASM`
  (`--creator`, `--date` and `--name` change them).
  `tools/mkprg.py --info PROG.PRG` shows a header.
- **On the board:** `SAVE` writes the creator you give it, or `MINI09`,
  and an unknown date, since the board has no clock.
- **Loading:** `LOAD` and running a program check the magic (`Not a program`
  otherwise) and load the bytes in one block.
- **Size:** a binary file is about 40% of the size of its S-records, so
  it loads faster too.

To run your own program:
1. Assemble it with `org $1000` (or higher) and include `syscalls.inc`.
2. Type `L` and paste the `.s19` file, or copy its `.PRG` to the drive.
3. Type `G 1000`, or `PROG` for a file.

You can also preload it: `./emu6809 os.s19 hello.s19` (or `hello.prg`).

The shell waits for a program to end before it shows the prompt again, so
an interactive program gets every key; otherwise the shell's own line
editor would take some of them. To start a program in the background,
use `LOAD file` and then `G addr`.

The emulator models the USB side too: `-k` turns input into key presses
on the chip's keyboard, `-d dir` makes `dir` the flash drive, `-p
file.ppm` saves a bitmap screen as a picture when the emulator exits,
`-r rom.s19` puts a 28C256's ROM bank in (`$8000-$BFFF` records), and `-T`
shows the chip's terminal on stdout instead of the DUART, for a
`CONSOLE=vdc` build (try
`./emu6809 -v -k -d . os.s19`). `make test-usb` runs DIR, TYPE, a program, SAVE,
DEL and LOAD against a scratch drive.

`vdpdemo.asm` is a larger example for the video/sound chip: load it
the same way and run `G 1000`. It plays a short tune timed in frames,
bounces a ball along the screen with `SYS_VCOPY` and then prints how many
100 Hz ticks 240 frames took (about 400).

### EDIT: full-screen text editor

`EDIT file` opens a file on the flash drive (a new file if it doesn't
exist); `EDIT` alone starts with an empty, unnamed text. It draws with
VT100 sequences, so it works on a serial terminal and on the HDMI screen.

The editor is a program, `EDIT.PRG`, so copy `edit.prg` to the root of
the drive as `EDIT.PRG`. The shell's `EDIT [file]` is short for
`EDIT [file]`. It used to be built into the ROM, but the kernel
had outgrown its 8K.

![EDIT on the 80x30 HDMI screen, editing hello.asm](edit-screenshot.png)

| Key | Does |
|-----|------|
| Arrows, Home, End, PgUp, PgDn | move (also ^A line start, ^E line end) |
| Backspace | delete to the left, joining lines at the start of one |
| Delete or ^D | delete under the cursor |
| Enter | new line, indented like the one above |
| Tab | spaces to the next multiple of 8 |
| ^K | delete the current line |
| ^C | cut the current line; more ^C in a row add the lines below it |
| ^V | paste the cut lines at the cursor |
| ^Z | undo; press it again to go further back |
| ^Y | redo what ^Z undid (until you make a new change) |
| ^F | find (case-sensitive) after the cursor; ^F, Enter finds the same text again |
| ^S | save (asks for a name if there is none) |
| ^L | redraw the screen |
| ^X | quit (press it twice if there are unsaved changes) |
| ^C at the Find or Save-as prompt | cancel the prompt |

How it works:

- **Screen:** 30 rows, 80 columns, to fill the video chip's 80x30 text
  screen: 29 rows of text and a status line on the bottom row with the
  name, `[modified]`, line and column. A serial terminal needs at least 30
  rows too (`EDROWS` in `edit.asm` sets the height; 24 suits a VT100).
  Only the parts that change are redrawn, because every character goes
  through the 9600-baud DUART. Lines longer than 80 columns scroll
  sideways in steps of 64.
- **Memory:** the text is held in a gap buffer spread over RAM pages
  `$03` to `$1B` (25 pages), so files can be up to 400K. A position in
  the text is 3 bytes. Each read or write of the text maps the page that
  holds it at `$8000-$BFFF`, and only calls `SYS_BANK` when it crosses
  into another page. Long moves (opening a file, find, undo) shift the gap
  512 bytes at a time instead of a character at a time. At 3.69 MHz a 100K
  file opens in about 2.5 s and a 375K one in about 8.5 s; finding text at
  the end of the 375K file takes about 6 s. A file over 400K is refused
  with "File too big for EDIT (400K)".
- **Clipboard:** cut lines go to RAM page `$1E` (up to 16K), copied
  through EDIT's file buffer because only one page is mapped at a time.
  The page starts with a marker and the clipboard's length. So a cut is
  still there the next time you run `EDIT`, and you can paste it into
  another file. It lasts until another program uses page `$1E`, and it
  survives a reset.
- **Undo:** every change is logged in RAM page `$1D` (16K), so ^Z can step
  back to the file as it was opened. One step is a run of typing (until
  you press a key that isn't a character, such as an arrow or Enter), one
  Backspace or Delete, a ^K, a block of lines cut with ^C in a row, or a
  paste. When the log fills up, the older history is dropped. Undoing a
  step logs its reverse in a redo log in page `$1C`, which ^Y plays back;
  any new change empties it. Both logs start empty each time you run
  `EDIT`.
- **Pages:** `EDIT` uses pages `$03` to `$1E`: the text in `$03-$1B`,
  the redo log in `$1C`, the undo log in `$1D` and the clipboard in `$1E`.
  Programs that use those pages (ASM, LINK, a task after `BANK`) overwrite
  the clipboard, but not while EDIT is running, since the shell waits for it.
  A background task that has a page of its own with `BANK` would have it
  overwritten by a big file, so don't leave one running while you edit.
- **Files:** CR is dropped and tabs are expanded when a file is read.
  Lines are written back ending in CR LF.
- **Keyboard:** Delete sends `ESC [ 3 ~` on a serial terminal and on the
  USB keyboard (pico6809 firmware from 2026-10-21 on), and ^D does the
  same. `$7F` and `$08` both delete to the left.
- **Console:** the shell waits for `EDIT` to end, so it gets every key.
  Background tasks that print will mess up the screen; ^L redraws it.

`make test-edit` copies `EDIT.PRG` and a file to a scratch drive, edits the file and shows the result.

## MC

`mc.asm` is MC, a file manager after Midnight Commander: two panels side
by side, each listing a folder of the flash drive. Copy `mc.prg` to the
root of the drive as `MC.PRG`, then type `MC`, or `MC folder` to start
the left panel in that folder. It draws with the same VT100 subset as
`EDIT`, so it needs 30 rows on a serial terminal too.

This first version browses; copying, deleting, viewing and editing come
next (the F-key bar already names them, and pressing one says it isn't
there yet).

| Key | Does |
|-----|------|
| Up, Down, PgUp, PgDn, Home, End | move the cursor in the active panel |
| Tab | switch panels |
| Enter | open the folder under the cursor; `..` goes up, with the cursor on the folder you left |
| ^R | read the panel's folder again |
| ^L | redraw the screen |
| F1 | the keys, on the message row |
| F10 or ^X | quit |
| ESC, then a digit | the same as that function key (ESC 0 is F10), for keyboards and terminals without them |

How it works:

- **Screen:** row 1 has the panels' top borders with their folders (the
  active one in reverse), rows 2 to 27 the entries, row 28 the bottom
  borders with the entry counts, row 29 the selected entry's full name and
  exact size (or a message), and row 30 the function keys. Folders are
  shown as `/NAME`, names longer than the column end in `~`, and sizes over
  999,999,999 bytes are shown in K. Only what changes is redrawn: a cursor
  move rewrites two rows, a scroll the panel's rows.
- **Sorting:** folders first, then files, each by name ignoring case. The
  drive returns entries in directory order, so MC sorts them as they
  arrive: a binary search finds each one's place in the index.
- **Memory:** each panel's list is in a RAM page of its own, `$03` for the
  left and `$04` for the right, mapped at `$8000-$BFFF` while it is read
  or drawn. The page holds an index of 2-byte pointers at `$8000` and the
  entries from `$8400` (attribute, 4-byte size, name). That is up to 512
  entries, or fewer with long names; a folder with more shows the first
  ones it read and says `Folder too big`. `EDIT` and other programs use
  those pages too, but MC reads both folders again each time it starts.

`make test-mc` makes a scratch drive (folders, a folder of 40 files, a long
name, a sparse 1.5 GB file), types keys at MC in the emulator and checks
the screen it leaves with `tools/mctest.py`, which renders MC's output as
an 80x30 terminal would.

## MINI09 BASIC

`basic.asm` is a floating-point BASIC. With a 28C256 in U3 it is in ROM:
type `BASIC` in the shell. Otherwise it runs as a normal user program from
the flash drive. Copy `basic.prg` to the drive as `BASIC.PRG`, then:

```
OS09> BASIC.PRG
MINI09 BASIC 1.0
25033 bytes free
OK
10 FOR I=1 TO 5:PRINT I;" SQUARED IS ";I*I:NEXT
RUN
```

`BYE` goes back to the shell. The program stays in RAM, so if you
`BASIC.PRG` again it is still there (unless another program has
overwritten it). `make test-basic` copies BASIC and `examples/*.bas` to a
scratch drive and runs a scripted session.

The two versions differ in a few ways:
- **Space:** disk BASIC has 25033 bytes for programs: they start after
  its code (about `$4E40`) and run up to `$AFFF`, through the task's page
  at `$8000`, with its stack and buffers at `$B000-$BFFF`. ROM BASIC has
  24576: its code is in the bank, so programs start at `$1000` and stop at
  `$6FFF`, with the stack and buffers at `$7000-$7FFF`.
- **Speed:** ROM BASIC is about 11% slower, because every instruction
  fetch from the EEPROM takes a wait state.
- **The language** is the same in both.
- **Testing:** `make test-rombasic` runs the `BASIC` command in the
  emulator, which models the bank with `-r basic-rom.s19`.
- **Code size:** the ROM build must end below `$C000`. It ends at `$BE38`,
  so additions to BASIC have about 450 bytes left.

**Lines and editing.** A line that starts with a number is stored; a
number alone deletes that line. Anything else runs at once. Keywords can
be typed in lower case. `LIST` shows them in upper case with standard
spacing, whatever spacing you typed. `?` is short for `PRINT` and `'`
for `REM`. Entering or deleting a line clears the variables. Ctrl-C
stops a running program (`BREAK IN 120`) or an `INPUT`.

**Data.**
- **Numbers:** floating point, with about 9 significant digits, from
  about 3E-39 to 1.7E+38.
  - **Constants:** you can write `3`, `2.5`, `.5`, `1E6` or `1.5E-3`;
    `&HFF` is a hex constant.
  - **Printing:** numbers print with up to 9 digits and no trailing
    zeros (`2.5`, `0.333333333`). E notation is used from 1E9 up and below
    0.0001 (`1.23456789E+09`, `1E-05`).
  - **Errors:** a result too big to hold is `OVERFLOW`; one too small
    becomes 0.
  - **Whole numbers needed:** where a statement or function needs a whole
    number (line numbers, subscripts, `POKE`, `CHR$`, `LEFT$`...), the
    value is cut to a whole number toward 0 and must be from -32768 to
    65535; otherwise it is `ILLEGAL FUNCTION CALL`.
- **Variable names:** a letter and an optional second letter or digit
  (`A`, `AB`, `X1`). Longer names are allowed but only the first two
  characters count, so `NAME` and `NA` are the same variable.
  - A name can't contain a keyword, because the keyword is found first:
    `SCORE` reads as `SC OR E`, and `TOTAL` contains `TO`.
  - Numbers, strings and arrays with the same name are separate
    variables (`A`, `A%`, `A#`, `A$`, `A()`, `A%()`, `A#()`, `A$()`).
- **Strings:** names end in `$` (`N$`, `AB$`). A string can be up to 255
  characters.
- **Double precision:** names end in `#` (`X#`, `A#(10)`). They hold
  about 16 digits in 8 bytes.
  - **Arithmetic** is done in double precision when either value is
    double.
  - **Constants** are double when they have more than 9 digits, a `D`
    exponent (`1.5D-3`) or a `#` (`0.1#`).
  - **Printing:** up to 16 digits, with `D` in E notation.
  - **Single-precision functions:** `SQR`, `SIN`, `COS`, `TAN`, `ATN`,
    `EXP`, `LOG` and fractional powers give single precision, as in
    GW-BASIC.
  - **Converting:** `CDBL`, `CSNG` and `CINT` convert between the types.
- **Whole numbers:** names end in `%` (`N%`, `A%(10)`). They hold -32768 to
  32767 in 2 bytes instead of 5.
  - **Storing:** a value is rounded to the nearest whole number as it is
    stored, as in GW-BASIC (`A%=2.7` gives 3). One outside the range is
    `OVERFLOW`.
  - **Arithmetic** is still floating point.
  - **Where `%` works:** in `FOR`, `INPUT`, `READ`, arrays, and `DEF FN`
    parameters and results.
- **Arrays:** numbers or strings, with up to 4 dimensions, created
  with `DIM A(n), GRID(9,9), N$(3,2)`; each subscript runs from 0 to the
  number given. An array can have at most 8000 elements. One used without
  `DIM` gets 0 to 10 in each dimension it is used with. Using the wrong
  number of subscripts is `BAD SUBSCRIPT`.

| Statement | Does |
|-----------|------|
| `PRINT a; b, c` | `;` prints the next item right after, `,` moves to the next 10-column zone; a trailing `;` or `,` stays on the line. `TAB(n)` moves to column n, `SPC(n)` prints n spaces |
| `INPUT ["prompt";] v, w$` | reads numbers and strings, comma-separated; `?REDO FROM START` if a number is bad |
| `[LET] v = expr` | assignment; `LET` is optional |
| `IF c THEN stmts [ELSE stmts]` | `THEN 100` and `ELSE 100` jump to that line; `IF c GOTO 100` works too |
| `GOTO n`, `GOSUB n`, `RETURN` | n can be an expression |
| `ON x GOTO a, b, c` / `ON x GOSUB ...` | goes to the x-th line; carries on if x is out of range |
| `FOR v = a TO b [STEP s]` … `NEXT [v[, w]]` | a loop that is already past its limit is skipped |
| `DIM A(n), B(r,c), C$(n)` | arrays, up to 4 dimensions |
| `DEF FNname[(p1, ...)] = expr` | your own function, used as `FNname(...)`: up to 4 number or string parameters, which are local while it runs; `FNA$` gives a string. `DEF` must run in a program before the function is used |
| `PRINT USING fmt$; a; b ...` | formatted output. Number fields: `#` places, `.`, `,` thousands, leading `+`, trailing `+` or `-`, `$$`, `**`, `**$`. `^^^^` after the digits gives E notation (`"##.##^^^^"` prints 234.56 as ` 2.35E+02`), with one place before the point kept for the sign unless the field has a `+` or trailing `-`. String fields: `!` first character, `&` all, `\  \` fixed width. `_` prints the next character as it is; a number too wide prints with `%` in front |
| `READ v, w$`, `DATA 1, "two", three`, `RESTORE` | strings in `DATA` can be quoted or bare |
| `END`, `STOP` | `STOP` prints `BREAK IN n` |
| `REM text` | comment |
| `CLS`, `LOCATE row, col` | VT100 clear screen and cursor position (1-based) |
| `SCREEN 1` / `2` / `0` | the video card's 320x240 or 256x192 bitmap screen (cleared), or the text screen. The text screen comes back when the program ends |
| `PSET (x,y)[,c]`, `LINE [(x1,y1)]-(x2,y2)[,[c][,B\|BF]]`, `CIRCLE (x,y),r[,c]` | draw in palette colour c (0-255, default 15): a pixel; a line (from the last point if the first is left out), a box or a filled box; a circle. Off-screen parts are clipped |
| `POINT(x,y)` | a pixel's colour, -1 off the screen |
| `PRINT @pos, ...` | print from screen position pos = row * 80 + column (0 to 2399 on the 80x30 screen); `PRINT @pos` alone just moves the cursor |
| `POKE addr, byte` | write a byte |
| `SLEEP ticks` | pause, in 1/100 s |
| `SOUND reg, value` | write a sound register on the video chip (see `vdp.inc`) |
| `RANDOMIZE [n]` | seed `RND`, from the clock if n is left out |
| `CLEAR` | clear all variables and arrays |
| `NEW`, `LIST [n \| n- \| -n \| n-m]`, `RUN [n \| "file"]` | `RUN "file"` loads, then runs |
| `LOAD "file"`, `SAVE "file"` | `.BAS` is added to a name without an extension |
| `DIR ["path"]`, `KILL "file"` | list the drive, delete a file (the name exactly as given) |
| `OPEN "f" FOR OUTPUT\|INPUT\|APPEND AS #n`, `CLOSE [#n]` | a data file (one at a time, n from 1 to 15). `APPEND` writes after what the file holds, creating it if new. It is closed when the program ends or stops, and on `RUN` and `NEW` |
| `PRINT #n, ...`, `PRINT #n, USING ...` | write to it what `PRINT` would show |
| `WRITE [#n,] a, b$` | items with commas between and strings in quotes, the form `INPUT #` reads back |
| `INPUT #n, a, b$`, `LINE INPUT [#n,] a$`, `EOF(n)` | read comma-separated items (strings may be quoted), read a whole line, test for the end |
| `BYE` | back to the shell |

**Operators** (lowest precedence first): `OR`, `AND`, `NOT`, the
comparisons `= <> < > <= >=`, then `+ -`, then `* / \ MOD`, then unary
minus, then `^`.
- **Comparisons** give -1 for true and 0 for false. They also compare
  strings, character by character.
- **`AND`, `OR` and `NOT`** work bit by bit on 16-bit whole numbers.
- **`/`** divides exactly (`7/2` is 3.5). **`\`** divides and drops the
  fraction (`7\2` is 3, `-7\2` is -3).
- **`MOD`** gives the remainder with the sign of the left side
  (`-7 MOD 3` is -1, `7.5 MOD 2` is 1.5).
- **Dividing by 0** is an error.
- **`^`** is the power: `2^10`, `2^0.5`, `2^-1`. `-2^2` is -4. A whole
  power works with any number; any other power needs a positive base.
- **`+`** also joins strings.

| Function | Gives |
|----------|-------|
| `ABS(n)`, `SGN(n)` | absolute value, sign (-1, 0, 1) |
| `INT(n)`, `FIX(n)` | the whole number at or below n (`INT(-2.5)` is -3), n without its fraction (`FIX(-2.5)` is -2) |
| `SQR(n)` | square root |
| `SIN(n)`, `COS(n)`, `TAN(n)`, `ATN(n)` | trigonometry, in radians |
| `EXP(n)`, `LOG(n)` | e to the power n, natural logarithm |
| `CINT(n)`, `CSNG(n)`, `CDBL(n)` | n rounded to a whole number, in single precision, in double precision |
| `RND(n)` | a random whole number from 0 to n-1; `RND(0)` gives one from 0 up to (but not including) 1 |
| `PEEK(addr)` | the byte at addr |
| `TIMER` | the 100 Hz tick counter (wraps at 16 bits) |
| `FRE` | free bytes for program, variables and strings |
| `LEN(s$)`, `ASC(s$)`, `VAL(s$)` | length, first character's code, number at the start of s$ (0 if none) |
| `CHR$(n)`, `STR$(n)` | one-character string, number as text |
| `LEFT$(s$,n)`, `RIGHT$(s$,n)`, `MID$(s$,p[,n])` | parts of a string, p from 1 |
| `HEX$(n)` | n in hex without leading zeros (`HEX$(255)` is `FF`); a negative n as 16 bits (`HEX$(-1)` is `FFFF`) |
| `INSTR([p,] s$, t$)` | where t$ first appears in s$, looking from position p (default 1); 0 if it isn't there |
| `INKEY$` | a key if one was pressed, else `""` (doesn't wait) |

**Files.** `SAVE` writes the program as plain text, exactly as `LIST`
shows it, with CR LF line ends. So you can also write a program in
`EDIT` and `LOAD` it, or `TYPE` it from the shell. `LOAD` reads any text
file this way:
- Tabs become spaces.
- Lines without a line number are skipped.
- A line can be up to 127 characters.

The examples are:
- `examples/guess.bas`: a number guessing game.
- `examples/primes.bas`: a sieve that times itself with `TIMER`.
- `examples/tour.bas`: a short tour of the language.

**How it works.**
- **Tokens:** the interpreter tokenizes each line as it is entered.
  Keywords become single bytes from `$80` up, and spaces outside strings,
  `REM` and `DATA` are dropped. `LIST` puts the spacing back.
- **Stored lines:** each one is its line number, its length, the tokens
  and a NUL, kept in order after the interpreter's code.
- **Variables:** a table right after the program text, growing up.
  Each entry holds the 2-byte name, the entry size, and then the value: a
  number, a string descriptor (length and address), or for an array its
  element count, the number of dimensions, the size of each, and the
  elements, with the last subscript varying fastest. Variables are added the first time they are used,
  so looking one up is a search of the table.
- **Strings:** string values live in a string space that grows down
  from `$6FFF` towards the variable table. Each assignment copies the
  string there, and the old copy becomes garbage.
  - When the two meet, a collector packs the strings that are still in
    use at the top. Each pass of the collector moves one string, so it
    takes time proportional to the square of the number of strings: about
    40 ms for 50 strings.
  - `FRE` runs the collector before it counts.
- **Expressions:** evaluated by recursive descent. Numbers are in a
  floating-point accumulator (FAC), and the numbers waiting for an
  operator go on the 6809 stack, 5 bytes each. Strings in the middle of an
  expression go on a separate string stack that is emptied at the start
  of each statement.
- **Floating point:** numbers are stored in Microsoft BASIC's formats:
  an exponent byte (+128, 0 for zero), then the mantissa with the sign in
  its top bit. A single takes 5 bytes (32-bit mantissa) and a double 8
  (56-bit).
  - **Working precision:** FAC and its second operand ARG hold 56 bits
    plus a guard byte and a precision flag. Every operation works on 56
    bits, and the result is rounded to 32 bits when both operands are
    single.
  - **Multiplying:** uses the 6809's `MUL` once for each pair of non-zero
    mantissa bytes, so 16 times for two singles and 49 for two doubles.
  - **Dividing:** makes 40 quotient bits for singles or 64 for doubles,
    one at a time.
  - **Speed:** single-precision programs run about 20% slower than
    before doubles were added.
  - **`SIN`, `COS`, `EXP`, `LOG` and `ATN`:** each reduces its argument to
    a small range and then sums a short series.
  - **`SQR`:** six Newton steps.
  - **Constants in a program** are kept as text and read each time the
    line runs, as in Microsoft BASIC.
- **`DEF FN`:** a definition is a variable-table entry (its name with
  bit 5 set) holding the parameter names and a pointer to the expression
  in the program text. A call evaluates the arguments into 7-byte slots on
  the 6809 stack. While the expression runs, variable lookups check those
  slots first, so the parameters hide the program's variables of the same
  name.
- **Control stack:** `FOR` and `GOSUB` share one stack of 24 entries, so
  a `RETURN` also drops the loops that were opened inside the subroutine.
- **Ctrl-C:** before each statement BASIC calls `SYS_BREAK`. It removes a
  waiting ^C but leaves the other keys queued for `INPUT` and `INKEY$`.
  `INKEY$` uses `SYS_POLL`.

| Address | Use |
|---------|-----|
| `$1000-$4E36` | Interpreter |
| up from `$4E37` | Program text, then the variable table |
| down from `$6FFF` | String space |
| `$7000-$71FF` | BASIC's own stack |
| `$7200-$73FF` | Interpreter variables, line buffers |
| `$7400-$74FF` | Floating-point accumulators and work area, `DEF FN` |
| `$7500-$75FF` | File name and directory buffers, data file state |
| `$7600-$77FF` | File buffer |
| `$7800-$7A3F` | `FOR`/`GOSUB` stack (24 entries) |
| `$7A40-$7BFF` | Printed digits, number text, `PRINT USING` |
| `$7C00-$7FFF` | String stack |

## Limitations

The 6809 has no MMU, so there is no memory protection. All tasks share
one console. The shell is single-instance because it uses fixed RAM.
Tasks get equal time slices, with no priorities.
