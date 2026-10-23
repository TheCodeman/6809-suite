#!/usr/bin/env python3
"""Pico 6809 video/sound card for MINI09 J4: schematic (SVG) and netlist.

One description of parts and pin nets drives both outputs, so they can't
disagree.  Connections are drawn as net labels at the pin ends.
  python3 card_schematic.py   -> pico6809-card.svg, pico6809-card-netlist.txt
"""

# Each part: ref, value, x, y (top-left), width, pins on the left and right.
# A pin is (number, name, net).  Net names starting with '/' are active low.
PARTS = []

def part(ref, value, x, y, w, left, right, note=None):
    PARTS.append(dict(ref=ref, value=value, x=x, y=y, w=w, left=left, right=right, note=note))

# J4, MINI09 expansion header (only the pins the card uses)
part("J4", "MINI09 expansion header (2x20)", 60, 90, 150,
     [(1, "GND", "GND"), (27, "GND", "GND"), (2, "+5V", "+5V"), (40, "+5V", "+5V")],
     [(3, "D0", "BD0"), (4, "D1", "BD1"), (5, "D2", "BD2"), (6, "D3", "BD3"),
      (7, "D4", "BD4"), (8, "D5", "BD5"), (9, "D6", "BD6"), (10, "D7", "BD7"),
      (11, "A0", "BA0"), (12, "A1", "BA1"), (13, "A2", "BA2"), (14, "A3", "BA3"),
      (28, "E", "BE"), (29, "Q", "BQ"), (30, "R/W", "BR/W"),
      (33, "/EXPCS1", "/BCS"), (35, "/IRQ", "/IRQ")])

# U1: data buffer. A = Pico, B = bus. DIR = R/W (high: A->B, card drives the bus)
part("U1", "74LVC245 (data)", 470, 90, 150,
     [(1, "DIR", "BR/W"), (19, "/OE", "/DOE"), (20, "VCC", "+3V3"), (10, "GND", "GND")] +
     [(2 + i, f"A{i+1}", f"GP{i}") for i in range(8)],
     [(18 - i, f"B{i+1}", f"BD{i}") for i in range(8)])

# U2: input buffer, bus -> Pico, always on
u2_in = ["BA0", "BA1", "BA2", "BA3", "BR/W", "/BCS", "BE", "BQ"]
u2_out = ["GP8", "GP9", "GP10", "GP11", "GP20", "GP21", "GP22", "GP26"]
part("U2", "74LVC245 (address/control in)", 470, 470, 150,
     [(1, "DIR", "+3V3"), (19, "/OE", "GND"), (20, "VCC", "+3V3"), (10, "GND", "GND")] +
     [(2 + i, f"A{i+1}", u2_in[i]) for i in range(8)],
     [(18 - i, f"B{i+1}", u2_out[i]) for i in range(8)])

# Pico 2 W (40-pin module), the pins in use
pico_left = [(1, "GP0", "GP0"), (2, "GP1", "GP1"), (4, "GP2", "GP2"), (5, "GP3", "GP3"),
             (6, "GP4", "GP4"), (7, "GP5", "GP5"), (9, "GP6", "GP6"), (10, "GP7", "GP7"),
             (11, "GP8", "GP8"), (12, "GP9", "GP9"), (14, "GP10", "GP10"), (15, "GP11", "GP11"),
             (26, "GP20", "GP20"), (27, "GP21", "GP21"), (29, "GP22", "GP22"), (31, "GP26", "GP26"),
             (32, "GP27", "IRQDRV"), (34, "GP28", "/DOE")]
pico_right = [(16, "GP12", "H12"), (17, "GP13", "H13"), (19, "GP14", "H14"), (20, "GP15", "H15"),
              (21, "GP16", "H16"), (22, "GP17", "H17"), (24, "GP18", "H18"), (25, "GP19", "H19"),
              (40, "VBUS", "VBUS"), (36, "3V3(OUT)", "+3V3"),
              (3, "GND", "GND"), (8, "GND", "GND"), (13, "GND", "GND"), (18, "GND", "GND"),
              (23, "GND", "GND"), (28, "GND", "GND"), (33, "GND", "GND"), (38, "GND", "GND")]
part("U3", "Raspberry Pi Pico 2 W", 880, 90, 170, pico_left, pico_right,
     note="pico6809 firmware, HDMI on GP12-19")

# HDMI connector: series resistors from the HSTX pins
hdmi = [("H12", 7, "D0+"), ("H13", 9, "D0-"), ("H14", 10, "CK+"), ("H15", 12, "CK-"),
        ("H16", 1, "D2+"), ("H17", 3, "D2-"), ("H18", 4, "D1+"), ("H19", 6, "D1-")]
for i, (net, pin, name) in enumerate(hdmi):
    part(f"R{3+i}", "270", 1290, 90 + i * 40, 80, [(1, "", net)], [(2, "", "T" + name)])
part("J1", "HDMI type A", 1600, 90, 150,
     [(pin, name, "T" + name) for _, pin, name in hdmi] +
     [(18, "+5V", "+5V"), (19, "HPD", "HPD"), (15, "SCL", "SCL"), (16, "SDA", "SDA")],
     [(2, "D2 SH", "GND"), (5, "D1 SH", "GND"), (8, "D0 SH", "GND"), (11, "CK SH", "GND"),
      (17, "DDC GND", "GND"), (13, "CEC", "NC_CEC"), (14, "UTIL", "NC_UTIL")],
     note="HPD, SCL, SDA, CEC, UTIL not connected")

# Support parts
part("D1", "1N5817", 1290, 470, 90, [(1, "A", "+5V")], [(2, "K", "VBUS")],
     note="5 V for the USB host port")
part("R1", "10k", 1290, 560, 80, [(1, "", "/DOE")], [(2, "", "+3V3")],
     note="U1 off while the Pico boots")
part("Q1", "2N7000", 1290, 650, 90, [(2, "G", "IRQDRV"), (1, "S", "GND")], [(3, "D", "/IRQ")],
     note="IRQ drive high pulls /IRQ low")
part("R2", "100k", 1290, 770, 80, [(1, "", "IRQDRV")], [(2, "", "GND")],
     note="gate low while the Pico boots")
part("C1", "100n", 1600, 560, 80, [(1, "", "+3V3")], [(2, "", "GND")], note="at U1 VCC")
part("C2", "100n", 1600, 650, 80, [(1, "", "+3V3")], [(2, "", "GND")], note="at U2 VCC")

SINGLE_OK = {"HPD", "SCL", "SDA", "NC_CEC", "NC_UTIL"}   # deliberately unconnected

# ---------------------------------------------------------------- netlist
def nets():
    n = {}
    for p in PARTS:
        for pin, name, net in p["left"] + p["right"]:
            n.setdefault(net, []).append(f"{p['ref']}.{pin}" + (f"({name})" if name else ""))
    return n

def check(n):
    bad = [k for k, v in n.items() if len(v) < 2 and k not in SINGLE_OK]
    if bad:
        raise SystemExit("nets with one connection: " + ", ".join(bad))

# ---------------------------------------------------------------- drawing
import xml.etree.ElementTree as ET

PITCH, PINLEN = 20, 26
POWER = ("GND", "+5V", "+3V3", "VBUS")

def el(parent, tag, text=None, **attrs):
    e = ET.SubElement(parent, tag, {k.rstrip("_").replace("_", "-"): str(v) for k, v in attrs.items()})
    if text is not None:
        e.text = text
    return e

def net_text(net):
    if net.startswith("T"):
        return "HDMI " + net[1:]
    if net.startswith("H1"):
        return "GP" + net[1:]
    return net

def label(g, x, y, net, side):
    # side: -1 label to the left of the pin end, +1 to the right
    if net.startswith("NC_") or net in SINGLE_OK:
        el(g, "path", d=f"M{x-4},{y-4}L{x+4},{y+4}M{x-4},{y+4}L{x+4},{y-4}", class_="w")
        return
    el(g, "text", net_text(net), x=x + 4 * side, y=y + 4,
       text_anchor="end" if side < 0 else "start", class_="pw" if net in POWER else "nl")

def draw_part(g, p):
    rows = max(len(p["left"]), len(p["right"]))
    x, y, w = p["x"], p["y"], p["w"]
    h = rows * PITCH + 10
    small = w <= 80                         # two-pin parts: ref and value inside
    el(g, "rect", x=x, y=y, width=w, height=h, class_="body")
    if small:
        el(g, "text", p["ref"], x=x + 6, y=y + 19, class_="ref2")
        el(g, "text", p["value"], x=x + w - 6, y=y + 19, text_anchor="end", class_="sm")
    else:
        el(g, "text", p["ref"], x=x + w / 2, y=y - 18, text_anchor="middle", class_="ref")
        el(g, "text", p["value"], x=x + w / 2, y=y - 5, text_anchor="middle", class_="val")
    if p["note"]:
        el(g, "text", p["note"], x=x + w / 2, y=y + h + 14, text_anchor="middle", class_="note")
    for side, pins in ((-1, p["left"]), (1, p["right"])):
        outer, inner = ("end", "start") if side < 0 else ("start", "end")
        for i, (num, name, net) in enumerate(pins):
            py = y + 15 + i * PITCH
            px = x if side < 0 else x + w
            ex = px + side * PINLEN
            el(g, "line", x1=px, y1=py, x2=ex, y2=py, class_="w")
            el(g, "text", str(num), x=px + side * 4, y=py - 3, text_anchor=outer, class_="num")
            if name and not small:
                el(g, "text", name, x=px - side * 5, y=py + 4, text_anchor=inner, class_="pin")
            label(g, ex, py, net, side)

STYLE = """
  text{font-family:'DejaVu Sans Mono',monospace}
  .body{fill:#fffbea;stroke:#7a2e2e;stroke-width:1.6}
  .w{stroke:#1f5f1f;stroke-width:1.3;fill:none}
  .ref{font-size:14px;font-weight:bold;fill:#7a2e2e}
  .val{font-size:11px;fill:#333}
  .sm{font-size:11px;fill:#333}
  .ref2{font-size:11px;font-weight:bold;fill:#7a2e2e}
  .note{font-size:10px;fill:#666;font-style:italic}
  .num{font-size:9px;fill:#7a2e2e}
  .pin{font-size:11px;fill:#000}
  .nl{font-size:11px;fill:#1a3fa0}
  .pw{font-size:11px;fill:#b00000;font-weight:bold}
  .title{font-size:20px;font-weight:bold}
  .txt{font-size:11.5px;fill:#222}
"""

NOTES = [
    "Pico 6809 video/sound card for MINI09 (J4).  Chip select /EXPCS1: registers at $C800-$C80F, mirrored to $CFFF.",
    "Names in blue are nets: pins with the same name are connected.  Bus-side nets: BD0-7, BA0-3, BE, BQ, BR/W, /BCS (= J4 /EXPCS1).",
    "U1 and U2 run at 3.3 V from the Pico (5 V-tolerant inputs), so no 5 V reaches the Pico.  U1 DIR = R/W: high (CPU read) drives the 6809 bus.",
    "/IRQ is open drain, shared with the DUART; MINI09 already has the pull-up.  HDMI pair order matches hdmi-hstx (Pico DVI Sock order).",
    "Firmware pins: src/bus6809.pio (.define) and src/bus6809.h; HDMI lanes: lane_to_bit[] in src/hstx_hdmi.c.  Unused J4 pins: leave open.",
    "USB host: keyboard + FAT32 flash drive on the Pico's own micro-USB port (OTG adapter + hub).  D1 feeds VBUS (~4.6 V); the Pico runs from VBUS via its internal diode.",
]

def svg():
    W, H = 1820, 900
    root = ET.Element("svg", xmlns="http://www.w3.org/2000/svg", width=str(W), height=str(H),
                      viewBox=f"0 0 {W} {H}")
    el(root, "style", STYLE)
    el(root, "rect", width=W, height=H, fill="white")
    for p in PARTS:
        draw_part(root, p)
    el(root, "text", "Pico 6809 video/sound card for MINI09", x=60, y=40, class_="title")
    for i, t in enumerate(NOTES):
        el(root, "text", t, x=60, y=800 + i * 17, class_="txt")
    ET.indent(root)
    return ET.tostring(root, encoding="unicode")

if __name__ == "__main__":
    n = nets()
    check(n)
    with open("pico6809-card.svg", "w") as f:
        f.write(svg())
    with open("pico6809-card-netlist.txt", "w") as f:
        f.write("# Pico 6809 video/sound card for MINI09 J4 - netlist (generated by card_schematic.py)\n\n")
        f.write("# Parts\n")
        for p in PARTS:
            f.write(f"{p['ref']:4} {p['value']}\n")
        f.write("\n# Nets\n")
        for k in sorted(n):
            f.write(f"{k:10} {' '.join(n[k])}\n")
    print(f"{len(PARTS)} parts, {len(n)} nets")
