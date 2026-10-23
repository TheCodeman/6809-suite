#!/usr/bin/env python3
"""
Build the MINI09 PCB (mini09.kicad_pcb) from netlist.txt using KiCad's
pcbnew Python API: footprints, placement, nets, outline, design rules.

    python3 pcb.py                 # -> mini09.kicad_pcb (unrouted)

Routing is done afterwards by route.sh (Freerouting), then zones are
filled and outputs are made by finish.py.
"""
import re
import uuid
import pcbnew

FP = "/usr/share/kicad/footprints"
mm = pcbnew.FromMM

BOARD_W, BOARD_H = 195.0, 115.0

# ref -> (library, footprint, value, x, y, rotation)
# Positions are of the footprint origin (pin 1 for DIPs and headers), mm.
DIP40, DIP32, DIP28 = (("Package_DIP", f"DIP-{n}_W15.24mm") for n in (40, 32, 28))
DIP24, DIP16, DIP14, DIP8 = (("Package_DIP", f"DIP-{n}_W7.62mm") for n in (24, 16, 14, 8))
RES = ("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal")
CAP = ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm")
ELCO = ("Capacitor_THT", "CP_Radial_D5.0mm_P2.00mm")
XTAL = ("Crystal", "Crystal_HC49-4H_Vertical")
OSC = ("Oscillator", "Oscillator_DIP-8")
DIODE = ("Diode_THT", "D_DO-35_SOD27_P7.62mm_Horizontal")
BUTTON = ("Button_Switch_THT", "SW_PUSH_6mm")
HDR = {n: ("Connector_PinHeader_2.54mm", f"PinHeader_1x{n:02d}_P2.54mm_Vertical")
       for n in (2, 3, 6)}
HDR2X20 = ("Connector_PinHeader_2.54mm", "PinHeader_2x20_P2.54mm_Vertical")

PARTS = {
    # big chips, pin 1 top-left, pins run down
    "U1": (*DIP40, "HD63C09E", 16, 22, 0),
    "U2": (*DIP32, "AS6C4008", 56, 22, 0),
    "U3": (*DIP28, "28C256", 96, 22, 0),
    "U4": (*DIP28, "SCN2681AC1N28", 136, 22, 0),
    # MMU page registers, under the RAM
    "U7": (*DIP16, "74HC670", 56, 76, 90),
    "C10": (*CAP, "100n", 78, 70, -90),
    # glue logic CPLD, lying along the bottom; X1 next to its pin 1 (clock)
    "U5": (*DIP24, "ATF750C", 46, 92, 90),
    "C8": (*CAP, "100n", 40, 80, -90),
    "X1": (*OSC, "14.7546MHz", 30, 108, 0),
    "C9": (*CAP, "100n", 22, 98, -90),
    # reset supervisor / watchdog, its /RESET pull-up, button, watchdog jumper
    "U6": (*DIP8, "DS1232", 112, 84, 0),
    "R10": (*RES, "10k", 108, 75.5, -90),
    "JP2": (*HDR[3], "Watchdog", 124, 84, 0),
    "SW1": (*BUTTON, "RESET", 112, 98, 0),
    # DUART crystal, right of U4 next to X1/X2 (pins 23/24)
    "Y1": (*XTAL, "3.6864MHz", 158, 28, 90),
    "C1": (*CAP, "5p", 164, 28, -90),
    "C2": (*CAP, "5p", 155, 39, 0),
    # pull-ups: CPU control lines (left), DUART/ROM lines (near U4/U3)
    "R1": (*RES, "10k", 8, 80, -90),
    "R2": (*RES, "10k", 11, 80, -90),
    "R3": (*RES, "10k", 14, 80, -90),
    "R4": (*RES, "10k", 17, 80, -90),
    "R5": (*RES, "3k3", 20, 80, -90),
    "R6": (*RES, "10k", 138, 66, 0),
    "R7": (*RES, "10k", 138, 69, 0),
    "R8": (*RES, "10k", 138, 72, 0),
    # decoupling, beside each chip's VCC pin
    "C4": (*CAP, "100n", 8, 32, 90),
    "C5": (*CAP, "100n", 63, 15, 0),
    "C6": (*CAP, "100n", 103, 15, 0),
    "C7": (*CAP, "100n", 143, 15, 0),
    "C3": (*ELCO, "10u", 172, 98, 0),
    # connectors on the right edge
    "J1": (*HDR[6], "FTDI TTL-232R-5V", 187, 42, 0),
    "JP1": (*HDR[2], "USB power", 181, 47, 0),
    "J2": (*HDR[3], "Channel B", 187, 64, 0),
    "J3": (*HDR[2], "+5V IN", 187, 92, 0),
    # expansion bus along the top edge: odd pins on the inside row
    "J4": (*HDR2X20, "Expansion", 70, 9, 90),
}

# schematic pin name -> footprint pad number, where they differ
PADMAP = {}       # schematic pin name -> pad number, where they differ

# reference text moved off neighbouring silkscreen (absolute mm)
REF_POS = {"C10": (78, 67.6)}

HOLES = [(4, 4), (BOARD_W - 4, 4), (4, BOARD_H - 4), (BOARD_W - 4, BOARD_H - 4)]


# Schematic symbols get UUIDs derived from their reference, so footprints
# can be linked to them (kicad_sch.py uses the same function).
NS = uuid.UUID("6a6e3c0e-8f0b-4d5b-9a8e-6809f00d6809")


def sym_uuid(ref):
    return str(uuid.uuid5(NS, f"mini09/sym/{ref}"))


def kicad_net(name):
    """netlist.txt uses /X for active-low; KiCad uses an overbar, ~{X}
    ('/' separates sheet paths in KiCad net names)."""
    if name == "R/W":
        return "R~{W}"
    if name.startswith("/"):
        return "~{" + name[1:] + "}"
    return name


def read_netlist(path="netlist.txt"):
    nets = {}
    for line in open(path):
        m = re.match(r"^(\S+)\s+(\S+\.\S+.*)$", line.strip())
        if not m:
            continue
        nets[kicad_net(m.group(1))] = [tuple(c.split(".", 1)) for c in m.group(2).split()]
    return nets


def read_kicad_netlist(path="mini09.net"):
    """Nets exported by KiCad from mini09.kicad_sch (pins by pad number)."""
    import sexpr
    root = sexpr.parse(open(path).read())
    return {sexpr.get(n, "name")[1]:
            [(sexpr.get(x, "ref")[1], sexpr.get(x, "pin")[1]) for x in sexpr.find(n, "node")]
            for n in sexpr.find(sexpr.get(root, "nets"), "net")}


def main():
    nets = read_kicad_netlist()
    board = pcbnew.BOARD()

    # ---- design rules
    ds = board.GetDesignSettings()
    ds.SetCopperLayerCount(2)
    ns = ds.m_NetSettings
    dflt = ns.GetDefaultNetclass()
    dflt.SetTrackWidth(mm(0.25))
    dflt.SetClearance(mm(0.2))
    dflt.SetViaDiameter(mm(0.8))
    dflt.SetViaDrill(mm(0.4))
    power = pcbnew.NETCLASS("Power")
    power.SetTrackWidth(mm(0.6))
    power.SetClearance(mm(0.25))
    power.SetViaDiameter(mm(1.0))
    power.SetViaDrill(mm(0.5))
    ns.SetNetclass("Power", power)
    for n in ("VCC", "GND", "VUSB"):
        ns.SetNetclassPatternAssignment(n, "Power")
    ds.m_TrackMinWidth = mm(0.2)
    ds.m_ViasMinSize = mm(0.6)

    # ---- footprints
    fps = {}
    for ref, (lib, name, value, x, y, rot) in PARTS.items():
        fp = pcbnew.FootprintLoad(f"{FP}/{lib}.pretty", name)
        if fp is None:
            raise SystemExit(f"footprint {lib}:{name} not found")
        fp.SetFPID(pcbnew.LIB_ID(lib, name))
        fp.SetReference(ref)
        fp.SetValue(value)
        fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        fp.SetOrientationDegrees(rot)
        if ref in REF_POS:
            rx, ry = REF_POS[ref]
            fp.Reference().SetPosition(pcbnew.VECTOR2I(mm(rx), mm(ry)))
            fp.Reference().SetTextAngleDegrees(0)
        fp.SetPath(pcbnew.KIID_PATH("/" + sym_uuid(ref)))
        fp.SetSheetfile("mini09.kicad_sch")
        fp.SetSheetname("/")
        board.Add(fp)
        fps[ref] = fp

    for i, (x, y) in enumerate(HOLES):
        fp = pcbnew.FootprintLoad(f"{FP}/MountingHole.pretty", "MountingHole_3.2mm_M3")
        fp.SetFPID(pcbnew.LIB_ID("MountingHole", "MountingHole_3.2mm_M3"))
        fp.SetReference(f"H{i+1}")
        fp.SetValue("MountingHole")
        fp.Reference().SetVisible(False)
        fp.SetPath(pcbnew.KIID_PATH("/" + sym_uuid(f"H{i+1}")))
        fp.SetSheetfile("mini09.kicad_sch")
        fp.SetSheetname("/")
        fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        board.Add(fp)

    # ---- nets
    missing = set(PARTS)
    nets = {n: [c for c in conns if not c[0].startswith("H")] for n, conns in nets.items()}
    for netname, conns in nets.items():
        net = pcbnew.NETINFO_ITEM(board, netname)
        board.Add(net)
        for ref, pin in conns:
            if ref not in fps:
                raise SystemExit(f"{ref} in netlist but not placed")
            missing.discard(ref)
            pads = [p for p in fps[ref].Pads() if p.GetNumber() == pin]
            if not pads:
                raise SystemExit(f"{ref} has no pad {pin}")
            for p in pads:
                p.SetNet(net)
    if missing:
        raise SystemExit(f"placed but not in netlist: {sorted(missing)}")

    # ---- outline with rounded corners
    r = 3.0
    edges = [((r, 0), (BOARD_W - r, 0)), ((BOARD_W, r), (BOARD_W, BOARD_H - r)),
             ((BOARD_W - r, BOARD_H), (r, BOARD_H)), ((0, BOARD_H - r), (0, r))]
    for (x1, y1), (x2, y2) in edges:
        s = pcbnew.PCB_SHAPE(board, pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(pcbnew.VECTOR2I(mm(x1), mm(y1)))
        s.SetEnd(pcbnew.VECTOR2I(mm(x2), mm(y2)))
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(mm(0.1))
        board.Add(s)
    for cx, cy, sx, sy in ((r, r, 0, r), (BOARD_W - r, r, BOARD_W - r, 0),
                           (BOARD_W - r, BOARD_H - r, BOARD_W, BOARD_H - r),
                           (r, BOARD_H - r, r, BOARD_H)):
        a = pcbnew.PCB_SHAPE(board, pcbnew.SHAPE_T_ARC)
        a.SetCenter(pcbnew.VECTOR2I(mm(cx), mm(cy)))
        a.SetStart(pcbnew.VECTOR2I(mm(sx), mm(sy)))
        a.SetArcAngleAndEnd(pcbnew.EDA_ANGLE(90, pcbnew.DEGREES_T), True)
        a.SetLayer(pcbnew.Edge_Cuts)
        a.SetWidth(mm(0.1))
        board.Add(a)

    # ---- silkscreen title
    t = pcbnew.PCB_TEXT(board)
    t.SetText("MINI09  6309 SBC  rev L")
    t.SetPosition(pcbnew.VECTOR2I(mm(150), mm(108)))
    t.SetLayer(pcbnew.F_SilkS)
    t.SetTextSize(pcbnew.VECTOR2I(mm(1.5), mm(1.5)))
    t.SetTextThickness(mm(0.25))
    board.Add(t)

    board.SetFileName("mini09.kicad_pcb")
    pcbnew.SaveBoard("mini09.kicad_pcb", board)
    print(f"{len(fps)} parts, {len(nets)} nets -> mini09.kicad_pcb")


if __name__ == "__main__":
    main()
