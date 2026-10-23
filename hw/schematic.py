#!/usr/bin/env python3
"""
Generate the MINI09 board schematic (schematic.svg) and a netlist
(netlist.txt) from one description, so the drawing and the connection
list can never disagree.

Connections between sheet areas are made by net name, as on most
microprocessor schematics: every pin carries a label, and pins with the
same label are connected.

    python3 schematic.py        # writes schematic.svg and netlist.txt
"""
from collections import defaultdict
from html import escape

W, H = 2000, 1620                 # sheet size
PITCH = 20                        # pin spacing
STUB = 28                         # pin line length

svg = []
nets = defaultdict(list)          # net -> [(ref, pin, pin name)]
pins_used = defaultdict(set)      # ref -> {pin numbers}


def connect(ref, pin, name, net):
    if net is None:
        return
    if str(pin) in pins_used[ref]:
        raise SystemExit(f"duplicate pin {ref}.{pin}")
    pins_used[ref].add(str(pin))
    nets[net].append((ref, str(pin), name))


# ---------------------------------------------------------------- drawing
def line(x1, y1, x2, y2, cls="w"):
    svg.append(f'<line class="{cls}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"/>')


def poly(pts, cls="w", close=False):
    tag = "polygon" if close else "polyline"
    p = " ".join(f"{x},{y}" for x, y in pts)
    svg.append(f'<{tag} class="{cls}" points="{p}"/>')


def text(x, y, s, cls="t", anchor="start", rot=None):
    tr = f' transform="rotate({rot} {x} {y})"' if rot else ""
    svg.append(f'<text class="{cls}" x="{x}" y="{y}" text-anchor="{anchor}"{tr} '
               f'xml:space="preserve">{escape(s)}</text>')


def dot(x, y):
    svg.append(f'<circle class="dot" cx="{x}" cy="{y}" r="3"/>')


def nc(x, y):
    line(x - 5, y - 5, x + 5, y + 5)
    line(x - 5, y + 5, x + 5, y - 5)


def label(x, y, net, side):
    """Net label at a wire end. side: 'l' text to the left, 'r' right."""
    if net in ("VCC", "GND") and side in ("u", "d"):
        (vcc if net == "VCC" else gnd)(x, y, side)
        return
    if net in ("VCC", "GND"):
        s = "+5V" if net == "VCC" else "GND"
        if side == "l":
            text(x - 4, y + 4, s, "pwr", "end")
        else:
            text(x + 4, y + 4, s, "pwr")
        return
    if side == "l":
        text(x - 4, y + 4, net, "net", "end")
    elif side == "r":
        text(x + 4, y + 4, net, "net")
    elif side == "d":
        text(x, y + 14, net, "net", "middle")
    else:
        text(x, y - 6, net, "net", "middle")


def vcc(x, y, side="u"):
    if side in ("l", "r"):
        dx = -14 if side == "l" else 14
        line(x, y, x + dx, y)
        x += dx
    line(x, y, x, y - 10)
    line(x - 8, y - 10, x + 8, y - 10)
    text(x, y - 14, "+5V", "pwr", "middle")


def gnd(x, y, side="d"):
    if side in ("l", "r"):
        dx = -14 if side == "l" else 14
        line(x, y, x + dx, y)
        x += dx
    if side == "u":
        line(x, y, x, y - 10)
        y -= 10
        line(x - 8, y, x + 8, y)
        line(x - 5, y - 3, x + 5, y - 3)
        line(x - 2, y - 6, x + 2, y - 6)
        return
    line(x, y, x, y + 10)
    y += 10
    line(x - 8, y, x + 8, y)
    line(x - 5, y + 3, x + 5, y + 3)
    line(x - 2, y + 6, x + 2, y + 6)


def ic(ref, value, x, y, left, right, w=150, note=None):
    """DIP IC as a box. left/right: lists of (pin, name, net) or None (gap).
    net None = not connected."""
    n = max(len(left), len(right))
    h = n * PITCH + PITCH
    svg.append(f'<rect class="box" x="{x}" y="{y}" width="{w}" height="{h}"/>')
    text(x + w / 2, y - 22, ref, "ref", "middle")
    text(x + w / 2, y - 8, value, "val", "middle")
    if note:
        text(x + w / 2, y + h + 16, note, "small", "middle")
    for side, plist in (("l", left), ("r", right)):
        for i, p in enumerate(plist):
            if p is None:
                continue
            pin, name, net = p
            py = y + PITCH + i * PITCH
            if side == "l":
                x0, x1 = x - STUB, x
                text(x + 5, py + 4, name, "pin")
                text(x - 4, py - 3, str(pin), "pnum", "end")
            else:
                x0, x1 = x + w, x + w + STUB
                text(x + w - 5, py + 4, name, "pin", "end")
                text(x + w + 4, py - 3, str(pin), "pnum")
            line(x0, py, x1, py)
            end = x0 if side == "l" else x1
            if net is None:
                nc(end, py)
            else:
                label(end, py, net, side)
            connect(ref, pin, name, net)


def pin_end(x, y, ref, pin, name, net, side):
    """A gate pin: wire stub with label.  U6A -> package U6."""
    label(x, y, net, side)
    connect(ref[:-1], pin, name, net)


def nand(ref, x, y, a, b, out):
    """2-input NAND. a, b, out = (pin, net). (x, y) = top-left of body."""
    w, h = 50, 40
    svg.append(f'<path class="w" d="M{x},{y} h{w/2} a{h/2},{h/2} 0 0 1 0,{h} h{-w/2} z"/>')
    svg.append(f'<circle class="w" cx="{x+w/2+h/2+4}" cy="{y+h/2}" r="4"/>')
    for (pin, net), yy in ((a, y + 10), (b, y + 30)):
        line(x - 30, yy, x, yy)
        text(x - 3, yy - 3, str(pin), "pnum", "end")
        pin_end(x - 30, yy, ref, pin, "in", net, "l")
    ox = x + w / 2 + h / 2 + 8
    line(ox, y + h / 2, ox + 30, y + h / 2)
    text(ox + 3, y + h / 2 - 3, str(out[0]), "pnum")
    pin_end(ox + 30, y + h / 2, ref, out[0], "out", out[1], "r")
    text(x + 18, y + h + 14, ref, "small", "middle")


def inverter(ref, x, y, a, out, schmitt=True):
    h = 36
    poly([(x, y), (x, y + h), (x + 34, y + h / 2)], close=True)
    svg.append(f'<circle class="w" cx="{x+38}" cy="{y+h/2}" r="4"/>')
    if schmitt:
        poly([(x + 6, y + 23), (x + 13, y + 23), (x + 13, y + 13), (x + 19, y + 13)])
        poly([(x + 9, y + 23), (x + 9, y + 13), (x + 17, y + 13)])
    line(x - 30, y + h / 2, x, y + h / 2)
    text(x - 3, y + h / 2 - 3, str(a[0]), "pnum", "end")
    pin_end(x - 30, y + h / 2, ref, a[0], "in", a[1], "l")
    line(x + 42, y + h / 2, x + 72, y + h / 2)
    text(x + 45, y + h / 2 - 3, str(out[0]), "pnum")
    if out[1] is None:
        nc(x + 72, y + h / 2)
    else:
        pin_end(x + 72, y + h / 2, ref, out[0], "out", out[1], "r")
    text(x + 17, y + h + 14, ref, "small", "middle")


# Two-terminal parts, drawn vertically from (x, y1) to (x, y2) or
# horizontally from (x1, y) to (x2, y).  Each registers its two pins.
def resistor_v(ref, val, x, y1, y2, n1, n2):
    m = (y1 + y2) / 2
    line(x, y1, x, m - 18)
    line(x, m + 18, x, y2)
    svg.append(f'<rect class="box" x="{x-6}" y="{m-18}" width="12" height="36"/>')
    text(x + 10, m - 2, ref, "small")
    text(x + 10, m + 10, val, "small")
    connect(ref, 1, "", n1)
    connect(ref, 2, "", n2)


def cap_v(ref, val, x, y1, y2, n1, n2, polar=False):
    m = (y1 + y2) / 2
    line(x, y1, x, m - 4)
    line(x, m + 4, x, y2)
    line(x - 10, m - 4, x + 10, m - 4)
    if polar:
        svg.append(f'<path class="w" d="M{x-10},{m+7} q10,-6 20,0"/>')
        text(x - 14, m - 6, "+", "small", "end")
    else:
        line(x - 10, m + 4, x + 10, m + 4)
    text(x + 13, m - 2, ref, "small")
    text(x + 13, m + 10, val, "small")
    connect(ref, 1, "", n1)
    connect(ref, 2, "", n2)


def crystal_h(ref, val, x1, x2, y, n1, n2):
    m = (x1 + x2) / 2
    line(x1, y, m - 9, y)
    line(m + 9, y, x2, y)
    line(m - 9, y - 9, m - 9, y + 9)
    line(m + 9, y - 9, m + 9, y + 9)
    svg.append(f'<rect class="box" x="{m-5}" y="{y-12}" width="10" height="24"/>')
    text(m, y - 18, f"{ref}  {val}", "small", "middle")
    connect(ref, 1, "", n1)
    connect(ref, 2, "", n2)


def diode_v_up(ref, val, x, y1, y2, anode_net, cathode_net):
    """Diode from y1 (anode, bottom) up to y2 (cathode, top), y1 > y2."""
    m = (y1 + y2) / 2
    line(x, y1, x, m + 7)
    line(x, m - 7, x, y2)
    poly([(x - 7, m + 7), (x + 7, m + 7), (x, m - 7)], close=True)
    line(x - 7, m - 7, x + 7, m - 7)
    text(x + 10, m - 2, ref, "small")
    text(x + 10, m + 10, val, "small")
    connect(ref, "A", "", anode_net)
    connect(ref, "K", "", cathode_net)


def switch_v(ref, val, x, y1, y2, n1, n2):
    m = (y1 + y2) / 2
    line(x, y1, x, m - 10)
    line(x, m + 10, x, y2)
    svg.append(f'<circle class="w" cx="{x}" cy="{m-10}" r="2"/>')
    svg.append(f'<circle class="w" cx="{x}" cy="{m+10}" r="2"/>')
    line(x - 10, m - 12, x - 10, m + 12)
    line(x - 10, m, x - 16, m)
    text(x + 8, m - 2, ref, "small")
    text(x + 8, m + 10, val, "small")
    connect(ref, 1, "", n1)
    connect(ref, 2, "", n2)


def header(ref, value, x, y, pins, note=None):
    """Pin header, pins on the left side. pins: (pin, name, net)."""
    w = 90
    h = len(pins) * PITCH + PITCH
    svg.append(f'<rect class="box" x="{x}" y="{y}" width="{w}" height="{h}"/>')
    text(x + w / 2, y - 22, ref, "ref", "middle")
    text(x + w / 2, y - 8, value, "val", "middle")
    for i, (pin, name, net) in enumerate(pins):
        py = y + PITCH + i * PITCH
        line(x - STUB, py, x, py)
        text(x + 5, py + 4, f"{pin} {name}", "pin")
        if net is None:
            nc(x - STUB, py)
        else:
            label(x - STUB, py, net, "l")
        connect(ref, pin, name, net)
    if note:
        for j, s in enumerate(note):
            text(x - 40, y + h + 16 + j * 13, s, "small")


def frame(x, y, w, h, title):
    svg.append(f'<rect class="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>')
    text(x + 8, y + 16, title, "area")


# ================================================================ the board
# ---- main ICs --------------------------------------------------------
frame(20, 20, 1960, 640, "PROCESSOR, MEMORY, DUART")

ic("U1", "HD63C09E", 150, 90, [
    (37, "/RESET", "/RESET"),
    (40, "/HALT", "/HALT"),
    (2, "/NMI", "/NMI"),
    (3, "/IRQ", "/IRQ"),
    (4, "/FIRQ", "/FIRQ"),
    None,
    (34, "E", "E"),
    (35, "Q", "Q"),
    (39, "TSC", "GND"),
    None,
    (32, "R/W", "R/W"),
    (33, "BUSY", None),
    (36, "AVMA", None),
    (38, "LIC", None),
    (5, "BS", None),
    (6, "BA", None),
    None,
    (7, "VCC", "VCC"),
    (1, "VSS", "GND"),
], [(8 + i, f"A{i}", f"A{i}") for i in range(16)] + [None] +
   [(31 - i, f"D{i}", f"D{i}") for i in range(8)],
   w=130, note="E and Q clock inputs from U5")

ram_a = [12, 11, 10, 9, 8, 7, 6, 5, 27, 26, 23, 25, 4, 28, 3, 31]
ic("U2", "AS6C4008 SRAM 512Kx8", 560, 90,
   [(ram_a[i], f"A{i}", f"A{i}") for i in range(14)] +
   [(3, "A14", "MA14"), (31, "A15", "MA15"), (2, "A16", "MA16"), (30, "A17", "MA17"),
    (1, "A18", "MA18")],
   [(p, f"DQ{i}", f"D{i}") for i, p in enumerate([13, 14, 15, 17, 18, 19, 20, 21])] +
   [None, (22, "/CE", "/RAMCS"), (24, "/OE", "/RD"),
    (29, "/WE", "/WR"), None, (32, "VCC", "VCC"), (16, "GND", "GND")],
   w=140, note="$0000-$BFFF, A14-A17 from U7, A18 from U5")

rom_a = [10, 9, 8, 7, 6, 5, 4, 3, 25, 24, 21, 23, 2, 26, 1]
ic("U3", "28C256 EEPROM 32Kx8", 960, 90,
   [(rom_a[i], f"A{i}", f"A{i}") for i in range(15)],
   [(p, f"D{i}", f"D{i}") for i, p in enumerate([11, 12, 13, 15, 16, 17, 18, 19])] +
   [None, (20, "/CE", "/ROMCS"), (22, "/OE", "/RD"), (27, "/WE", "VCC"),
    None, (28, "VCC", "VCC"), (14, "GND", "GND")],
   w=140, note="$E000-$FFFF = ROM $6000; $8000 bank = ROM $0000 (28C64 fits)")

ic("U4", "SCN2681AC1N28 DUART", 1390, 90, [
    (1, "A0", "A0"), (2, "A1", "A1"), (3, "A2", "A2"), (4, "A3", "A3"),
    None,
    (19, "D0", "D0"), (10, "D1", "D1"), (18, "D2", "D2"), (11, "D3", "D3"),
    (17, "D4", "D4"), (12, "D5", "D5"), (16, "D6", "D6"), (13, "D7", "D7"),
    None,
    (26, "/CEN", "/DUARTCS"), (6, "/RDN", "/RD"), (5, "/WRN", "/WR"),
    (25, "RESET", "RESET"), (15, "/INTRN", "/IRQ"),
], [
    (23, "X1/CLK", "XD1"), (24, "X2", "XD2"),
    None,
    (22, "RxDA", "RXDA"), (21, "TxDA", "TXDA"), (20, "OP0 /RTSA", "/RTSA"),
    None,
    (7, "RxDB", "RXDB"), (8, "TxDB", "TXDB"), (9, "OP1", "WDOG"),
    (27, "IP2", "IP2"),
    None,
    (28, "VCC", "VCC"), (14, "GND", "GND"),
], w=160, note="$C000-$C00F, mirrored to $C7FF")

# ---- expansion header ---------------------------------------------------
EXP = [
    (1, "GND", "GND"), (2, "VCC", "VCC"),
    (3, "D0", "D0"), (4, "D1", "D1"), (5, "D2", "D2"), (6, "D3", "D3"),
    (7, "D4", "D4"), (8, "D5", "D5"), (9, "D6", "D6"), (10, "D7", "D7"),
] + [(11 + i, f"A{i}", f"A{i}") for i in range(16)] + [
    (27, "GND", "GND"), (28, "E", "E"), (29, "Q", "Q"), (30, "R/W", "R/W"),
    (31, "/RD", "/RD"), (32, "/WR", "/WR"),
    (33, "/EXPCS1", "/EXPCS1"), (34, "NC", None),
    (35, "/IRQ", "/IRQ"), (36, "/FIRQ", "/FIRQ"), (37, "/NMI", "/NMI"),
    (38, "MRDY", "MRDY"), (39, "/RESET", "/RESET"), (40, "VCC", "VCC"),
]
ic("J4", "Expansion 2x20", 1765, 90, [p for p in EXP if p[0] % 2],
   [p for p in EXP if p[0] % 2 == 0], w=110,
   note="/EXPCS1 = $C800-$CFFF (2K)")

# ---- glue logic: one ATF750C --------------------------------------------
svg.append('<g transform="translate(0,80)">')    # lower half of the sheet
frame(20, 600, 760, 540, "GLUE LOGIC: U5 ATF750C (hw/pld/mini09.pld)")

ic("U5", "ATF750C", 190, 660, [
    (1, "I1/CLK", "OSC"), (2, "I2", "A15"), (3, "I3", "A14"), (4, "I4", "A13"),
    (5, "I5", "R/W"), (6, "I6", "MRDY"), (7, "I7", "A0"),
    None,
    (8, "I8", "A12"), (9, "I9", "A11"),
    (10, "I10", "A1"), (11, "I11", "D4"), (13, "I13", "GND"),
], [
    (23, "IO23", "Q"), (22, "IO22", "E"), (21, "IO21", "/RD"), (20, "IO20", "/WR"),
    (19, "IO19", "/ROMCS"), (18, "IO18", "/RAMCS"), (17, "IO17", "/DUARTCS"),
    (16, "IO16", "/MMUWR"), (15, "IO15", "/EXPCS1"), (14, "IO14", "MA18"),
    None,
    (24, "VCC", "VCC"), (12, "GND", "GND"),
], w=110, note="DIP-24, 0.3 in")

# MMU: 4 x 4-bit page registers.  CPU A15..A14 pick the register, its
# contents become SRAM A17..A14, so each 16K window maps to any 16K page.
ic("U7", "74HC670", 560, 660, [
    (5, "RA", "A14"), (4, "RB", "A15"),
    (14, "WA", "A0"), (13, "WB", "A1"),
    (15, "D1", "D0"), (1, "D2", "D1"), (2, "D3", "D2"), (3, "D4", "D3"),
    (12, "/GW", "/MMUWR"), (11, "/GR", "GND"),
], [
    (10, "Q1", "MA14"), (9, "Q2", "MA15"), (7, "Q3", "MA16"), (6, "Q4", "MA17"),
    None, None, None, None,
    (16, "VCC", "VCC"), (8, "GND", "GND"),
], w=100, note="MMU: page bits 0-3; bit 4 is in U5")


eqs = [
    ("Q.d = !E,  E.d = Q # HOLD    Johnson counter on OSC (pin 1)", "area2"),
    ("E, Q = OSC / 4 = 3.6887 MHz, Q leads E by 90 deg", "small"),
    ("RD    = E & R/W             /RD, /WR active only while E is high", "small"),
    ("WR    = E & !R/W", "small"),
    ("ROMCS   = A15 & A14 & A13   $E000-$FFFF", "small"),
    ("DUARTCS = A15 & A14 & !A13 & !A12 & !A11   $C000-$C7FF", "small"),
    ("EXPCS1  = A15 & A14 & !A13 & !A12 & A11    $C800-$CFFF (J4)", "small"),
    ("MMUWR   = E & !R/W & A15 & A14 & !A13 & A12 & A11   $D800-$D803", "small"),
    ("RAMCS   = !(A15 & A14)      $0000-$BFFF", "small"),
    ("HOLD (E high, Q low): MRDY low, or wait states DUART 2, ROM 1, EXPCS1 1", "small"),
    ("PGn.d = D4, clocked as Q falls in a write to $D80n (n = A1..A0)", "small"),
    ("MA18  = PGn for the window selected by A15..A14 (page bit 4)", "small"),
    ("Spare: input 13 (tied to GND).", "small"),
]
for i, (t, cls) in enumerate(eqs):
    text(40, 968 + i * 13, t, "small")

# ---- clock, reset, pull-ups --------------------------------------------
frame(800, 600, 600, 540, "CLOCKS, RESET, PULL-UPS")

text(830, 634, "CPU clock: 14.7546 MHz to U5 pin 1 (E = OSC/4)", "area2")
ic("X1", "14.7546 MHz half-can osc", 900, 680, [
    (1, "EN", "VCC"), (8, "VCC", "VCC"),
], [
    (5, "OUT", "OSC"), (4, "GND", "GND"),
], w=90)

# DUART crystal
dx, dy = 1150, 690
text(dx - 20, dy - 36, "DUART clock", "area2")
label(dx, dy, "XD1", "l")
dot(dx + 20, dy)
line(dx, dy, dx + 20, dy)
crystal_h("Y1", "3.6864 MHz", dx + 20, dx + 100, dy, "XD1", "XD2")
dot(dx + 100, dy)
line(dx + 100, dy, dx + 120, dy)
label(dx + 120, dy, "XD2", "r")
cap_v("C1", "5p", dx + 20, dy, dy + 50, "XD1", "GND")
gnd(dx + 20, dy + 50)
cap_v("C2", "5p", dx + 100, dy, dy + 50, "XD2", "GND")
gnd(dx + 100, dy + 50)
text(dx - 20, dy + 74, "C1/C2: 0-5 pF + stray (2681 Fig. 5)", "small")
text(dx - 20, dy + 87, "crystal ESR < 180 ohm", "small")

# Reset supervisor + watchdog + button
text(830, 804, "Reset: DS1232, >= 250 ms pulse, debounced button, watchdog", "area2")
ic("U6", "DS1232", 900, 840, [
    (8, "VCC", "VCC"), (2, "TD", "VCC"), (3, "TOL", "VCC"), (4, "GND", "GND"),
    (1, "/PBRST", "PBRST_N"),
], [
    (6, "/RST", "/RESET"), (5, "RST", "RESET"), (7, "/ST", "WDST"),
], w=90)
sx, sy = 1140, 870
label(sx, sy, "PBRST_N", "u")
switch_v("SW1", "RESET", sx, sy, sy + 60, "PBRST_N", "GND")
gnd(sx, sy + 60)
header("JP2", "Watchdog", 1260, 840, [
    (1, "OP1", "WDOG"),
    (2, "/ST", "WDST"),
    (3, "E", "E"),
], note=["1-2: on, kernel strobes OP1", "2-3: off, E strobes /ST"])
text(830, 985, "TD = VCC: watchdog 1.2 s (0.5 s min).  TOL = VCC: trips at 4.37 V.", "small")
text(830, 998, "/RST is open drain (R10).  RST, active high, resets the 2681.", "small")

# Pull-ups
px, py = 850, 1035
pull = [("R1", "10k", "/HALT"), ("R2", "10k", "/NMI"), ("R3", "10k", "/FIRQ"),
        ("R4", "10k", "MRDY"), ("R5", "3k3", "/IRQ"),
        ("R6", "10k", "RXDA"), ("R7", "10k", "RXDB"), ("R8", "10k", "IP2"),
        ("R10", "10k", "/RESET")]
line(px, py, px + 55 * (len(pull) - 1), py)
vcc(px, py)
for i, (ref, val, net) in enumerate(pull):
    x = px + 55 * i
    if i:
        dot(x, py)
    resistor_v(ref, val, x, py, py + 60, "VCC", net)
    label(x, py + 60, net, "d")
text(px - 30, py + 92, "R5: /INTRN is open drain.", "small")

# ---- connectors, power --------------------------------------------------
frame(1420, 600, 560, 540, "SERIAL, POWER")

header("J1", "FTDI TTL-232R-5V", 1560, 660, [
    (1, "GND", "GND"),
    (2, "CTS#", "/RTSA"),
    (3, "VCC", "VUSB"),
    (4, "TXD", "RXDA"),
    (5, "RXD", "TXDA"),
    (6, "RTS#", None),
], note=["console: DUART channel A, 9600 8N1",
         "board RTS (OP0) -> cable CTS#",
         "J1.3 powers the board via JP1"])

header("J2", "Channel B", 1820, 660, [
    (1, "GND", "GND"),
    (2, "TxDB", "TXDB"),
    (3, "RxDB", "RXDB"),
], note=["spare TTL port"])

header("J3", "+5V in", 1820, 800, [
    (1, "+5V", "VCC"),
    (2, "GND", "GND"),
])

header("JP1", "USB power", 1560, 900, [
    (1, "", "VUSB"),
    (2, "", "VCC"),
], note=["fit to run from FTDI cable"])

# ---- decoupling ---------------------------------------------------------
frame(20, 1160, 1960, 180, "DECOUPLING (one 100 nF per IC, at its VCC pin) AND BULK")
bx, by = 120, 1215
caps = [("C3", "10u", "bulk", True)] + [
    (f"C{4+i}", "100n", u, False) for i, u in enumerate(
        ["U1", "U2", "U3", "U4", "U5", "X1", "U7"])]
line(bx, by, bx + 130 * (len(caps) - 1), by)
line(bx, by + 70, bx + 130 * (len(caps) - 1), by + 70)
vcc(bx, by)
gnd(bx, by + 70)
for i, (ref, val, what, pol) in enumerate(caps):
    x = bx + 130 * i
    if i:
        dot(x, by)
        dot(x, by + 70)
    cap_v(ref, val, x, by, by + 70, "VCC", "GND", polar=pol)
    text(x, by + 98, what, "small", "middle")

# ---- notes / title -------------------------------------------------------
frame(20, 1360, 1400, 154, "NOTES")
notes = [
    "1. Pins with the same net label are connected. +5V / GND symbols are the supply nets. X = no connection.",
    "2. E = 3.6887 MHz: E high 136 ns; U5 adds wait states (68 ns each): DUART 2 (strobe ~260 ns, 2681 needs 225), ROM 1, /EXPCS1 1.",
    "3. HD63C09E(P): 3 MHz part run at 3.6887 MHz (14.7546 MHz / 4). E and Q from U5, Q leads E by 90 deg. Runs 6809 code after reset.",
    "4. TSC must stay low. Dead cycles put $FFFF on the bus (a ROM read), so DUART registers with read side effects are never touched by accident.",
    "5. Firmware: os.s19 programmed at $E000-$FFFF. Memory map and register use: see README.md and os.asm.",
    "6. Add a 100 nF cap at every VCC pin and keep the crystal traces short; C1/C2 may be omitted if board stray is ~5 pF.",
]
for i, s in enumerate(notes):
    text(36, 1398 + i * 18, s, "note")

svg.append(f'<rect class="frame" x="1440" y="1360" width="540" height="154"/>')
text(1460, 1400, "MINI09 - 6309 single-board computer", "title")
text(1460, 1426, "CPU HD63C09E · RAM AS6C4008 · ROM 28C256 · DUART SCN2681AC1N28", "val")
text(1460, 1450, "Generated by hw/schematic.py - netlist in hw/netlist.txt", "small")
text(1460, 1470, "Sheet 1 of 1    Rev K", "small")
text(1460, 1490, "Unverified design - check against datasheets before building", "small")

svg.append("</g>")

# ---------------------------------------------------------------- output
style = """
.w, .box, .frame { fill: none; stroke: #222; stroke-width: 1.5; }
.box { fill: #fffbea; }
.frame { stroke: #9aa; stroke-width: 1; stroke-dasharray: 6 4; }
polygon.w { fill: #fff; }
.dot { fill: #222; }
text { font-family: 'DejaVu Sans Mono', Menlo, Consolas, monospace; fill: #222; }
.ref { font-size: 15px; font-weight: bold; }
.val { font-size: 12px; fill: #444; }
.pin { font-size: 11px; }
.pnum { font-size: 9px; fill: #777; }
.net { font-size: 11px; fill: #0a5a9c; font-weight: bold; }
.pwr { font-size: 10px; fill: #b22; font-weight: bold; }
.small { font-size: 10px; fill: #444; }
.note { font-size: 12px; }
.area { font-size: 12px; fill: #799; font-weight: bold; letter-spacing: 1px; }
.area2 { font-size: 11px; fill: #555; font-weight: bold; }
.title { font-size: 20px; font-weight: bold; }
"""
with open("schematic.svg", "w") as f:
    f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
            f'viewBox="0 0 {W} {H}">\n<style>{style}</style>\n')
    f.write(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#fff"/>\n')
    f.write("\n".join(svg))
    f.write("\n</svg>\n")

# netlist + sanity checks
problems = []
with open("netlist.txt", "w") as f:
    f.write("MINI09 netlist (generated by schematic.py)\n\n")
    for net in sorted(nets, key=lambda n: (n not in ("VCC", "GND"), n)):
        conns = nets[net]
        f.write(f"{net:<10} " + " ".join(f"{r}.{p}" for r, p, _ in sorted(conns)) + "\n")
        if len(conns) < 2:
            problems.append(f"net {net} has only {conns}")
for p in problems:
    print("WARNING:", p)
print(f"{len(nets)} nets, {sum(len(v) for v in nets.values())} connections")
