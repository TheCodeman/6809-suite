#!/usr/bin/env python3
"""
Generate a KiCad 9 schematic (mini09.kicad_sch) and the project symbol
library (mini09.kicad_sym) from netlist.txt.

Standard KiCad library symbols are used where they exist; the 28-pin
SCN2681 is in the project library.
Every pin gets a short wire and a global label (or a power symbol) named
after its net, so the schematic is the netlist, drawn.

UUIDs are derived from reference designators, so the PCB can link to the
symbols (pcb.py uses the same scheme).

    python3 kicad_sch.py
"""
import copy
import uuid
import sexpr
from sexpr import Str, find, get
from pcb import PARTS, PADMAP, read_netlist, sym_uuid

SYMDIR = "/usr/share/kicad/symbols/"
NS = uuid.UUID("6a6e3c0e-8f0b-4d5b-9a8e-6809f00d6809")
ROOT = str(uuid.uuid5(NS, "mini09/root"))
G = 2.54


def uid(*parts):
    return Str(uuid.uuid5(NS, "/".join(map(str, parts))))


def snap(v):
    return round(round(v / G) * G, 2)


def font(size=1.27):
    return ["effects", ["font", ["size", size, size]]]


def hidden():
    return ["effects", ["font", ["size", 1.27, 1.27]], ["hide", "yes"]]


# ------------------------------------------------------------ libraries
_libs = {}


def lib_symbol(lib, name):
    if lib not in _libs:
        _libs[lib] = sexpr.parse(open(SYMDIR + lib + ".kicad_sym").read())
    for s in find(_libs[lib], "symbol"):
        if s[1] == name:
            ext = get(s, "extends")
            if ext:                         # alias: base drawing, own fields
                base = copy.deepcopy(lib_symbol(lib, ext[1]))
                base[1] = Str(name)
                own = {p[1]: copy.deepcopy(p) for p in find(s, "property")}
                props = [own.pop(p[1], p) for p in find(base, "property")] + list(own.values())
                base[:] = [x for x in base if not (isinstance(x, list) and x[0] == "property")]
                at = next(i for i, x in enumerate(base) if isinstance(x, list) and x[0] == "symbol")
                base[at:at] = props
                for sub in find(base, "symbol"):
                    sub[1] = Str(sub[1].replace(ext[1], name, 1))
                return base
            return copy.deepcopy(s)
    raise SystemExit(f"{lib}:{name} not found")


def pin(kind, x, y, ang, name, num, length=G, hide=False):
    p = ["pin", kind, "line", ["at", x, y, ang], ["length", length]]
    if hide:
        p.append(["hide", "yes"])
    p += [["name", Str(name), font()], ["number", Str(num), font()]]
    return p


def prop(key, val, x=0, y=0, hide=False):
    return ["property", Str(key), Str(val), ["at", x, y, 0], hidden() if hide else font()]


def make_2681():
    left = [("1", "A0", "input"), ("2", "A1", "input"), ("3", "A2", "input"),
            ("4", "A3", "input"), None,
            ("19", "D0", "bidirectional"), ("10", "D1", "bidirectional"),
            ("18", "D2", "bidirectional"), ("11", "D3", "bidirectional"),
            ("17", "D4", "bidirectional"), ("12", "D5", "bidirectional"),
            ("16", "D6", "bidirectional"), ("13", "D7", "bidirectional"), None,
            ("26", "~{CEN}", "input"), ("6", "~{RDN}", "input"),
            ("5", "~{WRN}", "input"), ("25", "RESET", "input"),
            ("15", "~{INTRN}", "open_collector")]
    right = [("23", "X1/CLK", "input"), ("24", "X2", "passive"), None,
             ("22", "RxDA", "input"), ("21", "TxDA", "output"),
             ("20", "OP0/~{RTSA}", "output"), None,
             ("7", "RxDB", "input"), ("8", "TxDB", "output"), ("9", "OP1", "output"),
             ("27", "IP2", "input")]
    pins = []
    for side, plist in ((-1, left), (1, right)):
        for i, p in enumerate(plist):
            if p:
                pins.append(pin(p[2], side * 15.24, 22.86 - i * G, 0 if side < 0 else 180, p[1], p[0]))
    pins.append(pin("power_in", 0, 27.94, 270, "VCC", "28"))
    pins.append(pin("power_in", 0, -27.94, 90, "GND", "14"))
    return ["symbol", Str("SCN2681AC1N28"), ["pin_names", ["offset", 1.016]],
            ["exclude_from_sim", "no"], ["in_bom", "yes"], ["on_board", "yes"],
            prop("Reference", "U", -10.16, 26.67),
            prop("Value", "SCN2681AC1N28", 0, -30.48),
            prop("Footprint", "Package_DIP:DIP-28_W15.24mm", hide=True),
            prop("Datasheet", "https://www.nxp.com/docs/en/data-sheet/SCC2681.pdf", hide=True),
            prop("Description", "Dual UART (DUART), 28-pin DIP version: IP2 and OP0/OP1 only", hide=True),
            prop("ki_keywords", "DUART UART 2681 68681", hide=True),
            ["symbol", Str("SCN2681AC1N28_0_1"),
             ["rectangle", ["start", -12.7, 25.4], ["end", 12.7, -25.4],
              ["stroke", ["width", 0.254], ["type", "default"]], ["fill", ["type", "background"]]]],
            ["symbol", Str("SCN2681AC1N28_1_1")] + pins,
            ["embedded_fonts", "no"]]


def make_atf750c():
    left = [("1", "I1/CLK")] + [(str(n), f"I{n}") for n in range(2, 12)] + [("13", "I13")]
    right = [(str(n), f"IO{n}") for n in range(23, 13, -1)]
    pins = [pin("input", -12.7, 15.24 - i * G, 0, name, num) for i, (num, name) in enumerate(left)]
    pins += [pin("bidirectional", 12.7, 15.24 - i * G, 180, name, num) for i, (num, name) in enumerate(right)]
    pins.append(pin("power_in", 0, 20.32, 270, "VCC", "24"))
    pins.append(pin("power_in", 0, -17.78, 90, "GND", "12"))
    return ["symbol", Str("ATF750C"), ["pin_names", ["offset", 1.016]],
            ["exclude_from_sim", "no"], ["in_bom", "yes"], ["on_board", "yes"],
            prop("Reference", "U", -7.62, 19.05),
            prop("Value", "ATF750C", 0, -20.32),
            prop("Footprint", "Package_DIP:DIP-24_W7.62mm", hide=True),
            prop("Datasheet", "https://ww1.microchip.com/downloads/en/DeviceDoc/doc0776.pdf", hide=True),
            prop("Description", "Microchip ATF750C high-performance EE PLD, 10 macrocells / 20 registers, DIP-24", hide=True),
            prop("ki_keywords", "PLD CPLD GAL ATF750", hide=True),
            ["symbol", Str("ATF750C_0_1"),
             ["rectangle", ["start", -10.16, 17.78], ["end", 10.16, -15.24],
              ["stroke", ["width", 0.254], ["type", "default"]], ["fill", ["type", "background"]]]],
            ["symbol", Str("ATF750C_1_1")] + pins,
            ["embedded_fonts", "no"]]


def make_ds1232():
    pins = [pin("input", -10.16, 2.54, 0, "~{PBRST}", "1"),
            pin("input", -10.16, 0, 0, "TD", "2"),
            pin("input", -10.16, -2.54, 0, "TOL", "3"),
            pin("open_collector", 10.16, 2.54, 180, "~{RST}", "6"),
            pin("output", 10.16, 0, 180, "RST", "5"),
            pin("input", 10.16, -2.54, 180, "~{ST}", "7"),
            pin("power_in", 0, 7.62, 270, "VCC", "8"),
            pin("power_in", 0, -7.62, 90, "GND", "4")]
    return ["symbol", Str("DS1232"), ["pin_names", ["offset", 1.016]],
            ["exclude_from_sim", "no"], ["in_bom", "yes"], ["on_board", "yes"],
            prop("Reference", "U", -5.08, 6.35),
            prop("Value", "DS1232", 5.08, -6.35),
            prop("Footprint", "Package_DIP:DIP-8_W7.62mm", hide=True),
            prop("Datasheet", "https://www.analog.com/media/en/technical-documentation/data-sheets/DS1232.pdf", hide=True),
            prop("Description", "MicroMonitor: 5 V supervisor, debounced push-button reset, watchdog, DIP-8", hide=True),
            prop("ki_keywords", "reset supervisor watchdog pushbutton", hide=True),
            ["symbol", Str("DS1232_0_1"),
             ["rectangle", ["start", -7.62, 5.08], ["end", 7.62, -5.08],
              ["stroke", ["width", 0.254], ["type", "default"]], ["fill", ["type", "background"]]]],
            ["symbol", Str("DS1232_1_1")] + pins,
            ["embedded_fonts", "no"]]


PROJECT_SYMS = {"SCN2681AC1N28": make_2681(),
                "ATF750C": make_atf750c(), "DS1232": make_ds1232()}


def symbol_def(lib_id):
    lib, name = lib_id.split(":")
    s = copy.deepcopy(PROJECT_SYMS[name]) if lib == "mini09" else lib_symbol(lib, name)
    s[1] = Str(lib_id)
    return s


def units_of(sdef):
    """unit -> list of (number, x, y, angle, type) for body style 1."""
    units = {}
    name = sdef[1].split(":")[1]
    common = []
    for sub in find(sdef, "symbol"):
        u, style = map(int, sub[1][len(name) + 1:].split("_"))
        if style not in (0, 1):
            continue
        pins = [(get(p, "number")[1], float(get(p, "at")[1]), float(get(p, "at")[2]),
                 int(float(get(p, "at")[3])), p[1]) for p in find(sub, "pin")]
        if u == 0:
            common += pins
        else:
            units.setdefault(u, []).extend(pins)
    if not units:
        units[1] = []
    for u in units:
        units[u] += common
    return units


# ------------------------------------------------------------ the design
# ref -> lib_id, value, [(unit, x, y)]  (positions in mm, sheet A2)
PARTS_SCH = {
    "U1": ("CPU_NXP_6800:MC6809E", "HD63C09E", [(1, 63.5, 99.06)]),
    "U2": ("Memory_RAM:AS6C4008-55PCN", "AS6C4008", [(1, 160.02, 99.06)]),
    "U3": ("Memory_EEPROM:28C256", "28C256", [(1, 256.54, 99.06)]),
    "U4": ("mini09:SCN2681AC1N28", "SCN2681AC1N28", [(1, 353.06, 99.06)]),
    "U5": ("mini09:ATF750C", "ATF750C", [(1, 101.6, 198.12)]),
    "U7": ("74xx:74LS670", "74HC670", [(1, 172.72, 195.58)]),
    "X1": ("Oscillator:CXO_DIP8", "4MHz", [(1, 297.18, 160.02)]),
    "U6": ("mini09:DS1232", "DS1232", [(1, 297.18, 195.58)]),
    "JP2": ("Connector_Generic:Conn_01x03", "Watchdog", [(1, 368.3, 195.58)]),
    "SW1": ("Switch:SW_Push", "RESET", [(1, 330.2, 195.58)]),
    "Y1": ("Device:Crystal", "3.6864MHz", [(1, 309.88, 228.6)]),
    "C1": ("Device:C", "5p", [(1, 297.18, 241.3)]),
    "C2": ("Device:C", "5p", [(1, 322.58, 241.3)]),
    "J1": ("Connector_Generic:Conn_01x06", "FTDI TTL-232R-5V", [(1, 459.74, 152.4)]),
    "J2": ("Connector_Generic:Conn_01x03", "Channel B", [(1, 459.74, 185.42)]),
    "J3": ("Connector_Generic:Conn_01x02", "+5V IN", [(1, 459.74, 210.82)]),
    "JP1": ("Connector_Generic:Conn_01x02", "USB power", [(1, 459.74, 233.68)]),
    "J4": ("Connector_Generic:Conn_02x20_Odd_Even", "Expansion", [(1, 434.34, 99.06)]),
}
for i, ref in enumerate(["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R10"]):
    PARTS_SCH[ref] = ("Device:R", PARTS[ref][2], [(1, 50.8 + i * 20.32, 279.4)])
for i, ref in enumerate(["C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10"]):
    lib = "Device:C_Polarized" if ref == "C3" else "Device:C"
    PARTS_SCH[ref] = (lib, PARTS[ref][2], [(1, 50.8 + i * 20.32, 330.2)])
for i in range(4):
    PARTS_SCH[f"H{i+1}"] = ("Mechanical:MountingHole", "MountingHole", [(1, 304.8 + i * 15.24, 279.4)])

FOOTPRINT = {ref: f"{v[0]}:{v[1]}" for ref, v in PARTS.items()}
for i in range(4):
    FOOTPRINT[f"H{i+1}"] = "MountingHole:MountingHole_3.2mm_M3"

NOTES = [
    (38.1, 22.86, "MINI09 - Hitachi 6309 single-board computer", 3.0),
    (38.1, 30.48, "Memory map: RAM $0000-$BFFF (U2)  DUART $C000-$C7FF (U4)  /EXPCS1 $C800-$CFFF (J4)  MMU $D800-$D803 (write)  ROM $E000-$FFFF (U3)  ROM bank $8000-$BFFF when $D803 D4 = 1", 1.8),
    (38.1, 55.88, "MMU: each 16K CPU window (A15..A14) maps to one of 32 16K pages of U2: page bits 0-3 in U7 (A17..A14), bit 4 in U5 (A18).  Reset sets 0, 1, 2.", 1.8),
    (38.1, 35.56, "Glue logic: U5 ATF750C (hw/pld/mini09.pld) decodes A15-A13 and makes /RD = E & R/W, /WR = E & !R/W (active low).", 1.8),
    (38.1, 40.64, "Reset: U6 DS1232 (>= 250 ms, debounces SW1). /RST (open drain, R10) -> CPU; RST (active high) -> SCN2681.  Watchdog 1.2 s: JP2 1-2 = OP1 (kernel), 2-3 = E (off).", 1.8),
    (38.1, 45.72, "Console: DUART channel A on J1 (FTDI 5V cable), 9600 8N1, RTS on OP0 -> cable CTS#.  C1/C2: 0-5 pF + stray (2681 datasheet).", 1.8),
    (38.1, 50.8, "CPU clock: U5 divides X1 (14.7546 MHz) by 4: E = 3.6887 MHz.  U5 holds E high for wait states (DUART 2, ROM 1, EXPCS1 1) and while MRDY is low.", 1.8),
    (38.1, 307.34, "Decoupling: C3 bulk at J3, C4-C8 = 100 nF at the VCC pin of U1-U5, C9 at X1, C10 at U7.", 1.8),
]


# ------------------------------------------------------------ build
def main():
    nets = read_netlist()
    pin_net = {}
    for net, conns in nets.items():
        for ref, p in conns:
            pin_net[(ref, PADMAP.get(ref, {}).get(p, p))] = net

    items, libsyms, used_pins = [], {}, set()
    pwr_n = [0]

    def wire(x1, y1, x2, y2):
        items.append(["wire", ["pts", ["xy", x1, y1], ["xy", x2, y2]],
                      ["stroke", ["width", 0], ["type", "default"]], ["uuid", uid("w", x1, y1, x2, y2)]])

    def value_field(kind, x, y, rot, vy):
        """Rotated power symbols would turn their name sideways, so hide it
        and put a plain text note beside the symbol instead."""
        if rot == 0:
            return ["property", Str("Value"), Str(kind), ["at", x, y + vy, 0], font()]
        out = {0: (0, -1), 90: (-1, 0), 180: (0, 1), 270: (1, 0)}[rot]
        if kind == "GND":
            out = (-out[0], -out[1])
        tx, ty = x + out[0] * 3.3, y + out[1] * 5.6
        just = {(-1, 0): "right", (1, 0): "left"}.get(out)
        eff = ["effects", ["font", ["size", 1.27, 1.27]]] + ([["justify", just]] if just else [])
        items.append(["text", Str(kind), ["exclude_from_sim", "yes"], ["at", tx, ty, 0], eff,
                      ["uuid", uid("pwrtext", x, y)]])
        return ["property", Str("Value"), Str(kind), ["at", x, y, 0], hidden()]

    def power(kind, x, y, rot):
        lib_id = f"power:{kind}"
        if lib_id not in libsyms:
            libsyms[lib_id] = symbol_def(lib_id)
        pwr_n[0] += 1
        ref = f"#PWR{pwr_n[0]:03d}" if kind != "PWR_FLAG" else f"#FLG{pwr_n[0]:03d}"
        u = uid("pwr", ref)
        vy = -3.81 if kind == "VCC" else 5.08
        if kind == "PWR_FLAG":
            vy = -5.08
        items.append(["symbol", ["lib_id", Str(lib_id)], ["at", x, y, rot], ["unit", 1],
                      ["exclude_from_sim", "no"], ["in_bom", "yes"], ["on_board", "yes"],
                      ["dnp", "no"], ["fields_autoplaced", "yes"], ["uuid", u],
                      ["property", Str("Reference"), Str(ref), ["at", x, y, 0], hidden()],
                      value_field(kind, x, y, rot, vy),
                      ["property", Str("Footprint"), Str(""), ["at", x, y, 0], hidden()],
                      ["property", Str("Datasheet"), Str(""), ["at", x, y, 0], hidden()],
                      ["pin", Str("1"), ["uuid", uid("pwrpin", ref)]],
                      ["instances", ["project", Str("mini09"),
                                     ["path", Str("/" + ROOT), ["reference", Str(ref)], ["unit", 1]]]]])

    for ref, (lib_id, value, placements) in PARTS_SCH.items():
        value = PARTS[ref][2] if ref in PARTS else value     # one source for values
        if lib_id not in libsyms:
            libsyms[lib_id] = symbol_def(lib_id)
        sdef = libsyms[lib_id]
        units = units_of(sdef)
        props = {p[1]: p for p in find(sdef, "property")}
        for unit, sx, sy in placements:
            sx, sy = snap(sx), snap(sy)
            u = Str(sym_uuid(ref)) if unit == placements[0][0] else uid("sym", ref, unit)
            node = ["symbol", ["lib_id", Str(lib_id)], ["at", sx, sy, 0], ["unit", unit],
                    ["exclude_from_sim", "no"], ["in_bom", "no" if ref[0] == "H" else "yes"],
                    ["on_board", "yes"],
                    ["dnp", "no"], ["uuid", u]]
            for key, val in (("Reference", ref), ("Value", value),
                             ("Footprint", FOOTPRINT.get(ref, "")),
                             ("Datasheet", props["Datasheet"][2] if "Datasheet" in props else ""),
                             ("Description", props["Description"][2] if "Description" in props else "")):
                lp = props.get(key)
                if lp is not None:
                    at = get(lp, "at")
                    px, py, pa = sx + float(at[1]), sy - float(at[2]), at[3]
                    eff = copy.deepcopy(get(lp, "effects"))
                else:
                    px, py, pa, eff = sx, sy, 0, hidden()
                if key in ("Footprint", "Datasheet", "Description"):
                    eff = hidden()
                if lib_id == "74xx:74HC14" and unit <= 6 and key in ("Reference", "Value"):
                    px, py = sx, sy + (-5.08 if key == "Reference" else 5.08)   # clear of the gate
                    eff = font()
                node.append(["property", Str(key), Str(val), ["at", px, py, pa], eff])
            for num, *_ in units[unit]:
                node.append(["pin", Str(num), ["uuid", uid("pin", ref, unit, num)]])
            node.append(["instances", ["project", Str("mini09"),
                                       ["path", Str("/" + ROOT), ["reference", Str(ref)], ["unit", unit]]]])
            items.append(node)

            # pins: stub + label / power symbol / no-connect
            for num, px, py, ang, kind in units[unit]:
                x, y = round(sx + px, 2), round(sy - py, 2)
                dx, dy = {0: (-1, 0), 180: (1, 0), 90: (0, 1), 270: (0, -1)}[ang]
                net = pin_net.get((ref, num))
                used_pins.add((ref, num))
                if net is None:
                    items.append(["no_connect", ["at", x, y], ["uuid", uid("nc", ref, num)]])
                    continue
                ex, ey = round(x + dx * G, 2), round(y + dy * G, 2)
                wire(x, y, ex, ey)
                if net in ("VCC", "GND"):
                    out = (dx, dy)
                    if net == "VCC":
                        rot = {(0, -1): 0, (-1, 0): 90, (0, 1): 180, (1, 0): 270}[out]
                    else:
                        rot = {(0, 1): 0, (1, 0): 90, (0, -1): 180, (-1, 0): 270}[out]
                    power(net, ex, ey, rot)
                    continue
                lang = {(-1, 0): 180, (1, 0): 0, (0, 1): 270, (0, -1): 90}[(dx, dy)]
                just = "right" if lang in (180, 270) else "left"
                items.append(["global_label", Str(net), ["shape", "passive"], ["at", ex, ey, lang],
                              ["fields_autoplaced", "yes"],
                              ["effects", ["font", ["size", 1.27, 1.27]], ["justify", just]],
                              ["uuid", uid("gl", ref, unit, num)],
                              ["property", Str("Intersheetrefs"), Str("${INTERSHEET_REFS}"),
                               ["at", ex, ey, 0], hidden()]])

    # every netlist connection must have been drawn
    missing = [k for k in pin_net if k not in used_pins]
    if missing:
        raise SystemExit(f"pins in netlist but not on any symbol: {missing}")

    # supply flags at the power input
    for net, x in (("VCC", 482.6), ("GND", 497.84)):
        y = 213.36
        wire(x, y, x, y + G)
        power("PWR_FLAG", x, y, 0)
        if net == "VCC":
            power("VCC", x, y + G, 180)
        else:
            power("GND", x, y + G, 0)

    for x, y, s, size in NOTES:
        items.append(["text", Str(s), ["exclude_from_sim", "no"], ["at", x, y, 0],
                      ["effects", ["font", ["size", size, size]], ["justify", "left"]],
                      ["uuid", uid("text", s)]])

    sch = ["kicad_sch", ["version", 20250114], ["generator", Str("mini09_kicad_sch.py")],
           ["generator_version", Str("9.0")], ["uuid", Str(ROOT)], ["paper", Str("A2")],
           ["title_block", ["title", Str("MINI09 - 6309 single-board computer")],
            ["rev", Str("K")], ["company", Str("")],
            ["comment", 1, Str("CPU HD63C09E - RAM AS6C4008 - ROM 28C256 - DUART SCN2681AC1N28")],
            ["comment", 2, Str("Generated by hw/kicad_sch.py from hw/netlist.txt")]],
           ["lib_symbols"] + list(libsyms.values())] + items + [
           ["sheet_instances", ["path", Str("/"), ["page", Str("1")]]],
           ["embedded_fonts", "no"]]
    with open("mini09.kicad_sch", "w") as f:
        f.write(sexpr.dump(sch) + "\n")

    lib = ["kicad_symbol_lib", ["version", 20241209], ["generator", Str("mini09_kicad_sch.py")],
           ["generator_version", Str("9.0")]] + [copy.deepcopy(s) for s in PROJECT_SYMS.values()]
    with open("mini09.kicad_sym", "w") as f:
        f.write(sexpr.dump(lib) + "\n")
    with open("sym-lib-table", "w") as f:
        f.write('(sym_lib_table\n\t(version 7)\n\t(lib (name "mini09")(type "KiCad")'
                '(uri "${KIPRJMOD}/mini09.kicad_sym")(options "")(descr "MINI09 project symbols"))\n)\n')
    print(f"{len(PARTS_SCH)} parts, {len(nets)} nets -> mini09.kicad_sch, mini09.kicad_sym")


if __name__ == "__main__":
    main()
