#!/usr/bin/env python3
"""
Finish the routed board: import Freerouting's session (mini09.ses),
add GND pours on both copper layers, fill them and save.

    python3 finish.py
"""
import json
import os
import math
import subprocess
import pcbnew

mm = pcbnew.FromMM
W, H, INSET = 195.0, 115.0, 0.5

board = pcbnew.LoadBoard("mini09.kicad_pcb")
if not pcbnew.ImportSpecctraSES(board, "mini09.ses"):
    raise SystemExit("could not import mini09.ses")

for z in list(board.Zones()):
    board.Remove(z)

# Freerouting leaves a few redundant stubs: delete tracks with a loose end,
# but put a track back if deleting it would break a connection.
def unconnected():
    board.BuildConnectivity()
    return board.GetConnectivity().GetUnconnectedCount(False)


removed = 0
kept = set()
base = unconnected()
while True:
    conn = board.GetConnectivity()
    loose = [t for t in board.GetTracks()
             if t.GetClass() == "PCB_TRACK" and conn.TestTrackEndpointDangling(t, False)]
    loose = [t for t in loose
             if (t.GetLayer(), t.GetStart().x, t.GetStart().y, t.GetEnd().x, t.GetEnd().y) not in kept]
    if not loose:
        break
    t = loose[0]
    key = (t.GetLayer(), t.GetStart().x, t.GetStart().y, t.GetEnd().x, t.GetEnd().y)
    saved = (t.GetStart(), t.GetEnd(), t.GetWidth(), t.GetLayer(), t.GetNet())
    board.Delete(t)
    if unconnected() > base:
        n = pcbnew.PCB_TRACK(board)
        n.SetStart(saved[0])
        n.SetEnd(saved[1])
        n.SetWidth(saved[2])
        n.SetLayer(saved[3])
        n.SetNet(saved[4])
        board.Add(n)
        kept.add(key)
        unconnected()
    else:
        removed += 1

gnd = board.FindNet("GND")
for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNet(gnd)
    z.SetLocalClearance(mm(0.3))
    z.SetMinThickness(mm(0.25))
    z.SetThermalReliefGap(mm(0.4))
    z.SetThermalReliefSpokeWidth(mm(0.5))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    o = z.Outline()
    o.NewOutline()
    for x, y in ((INSET, INSET), (W - INSET, INSET), (W - INSET, H - INSET), (INSET, H - INSET)):
        o.Append(mm(x), mm(y))
    board.Add(z)

pcbnew.ZONE_FILLER(board).Fill(board.Zones())

# GND stitching vias wherever both pours have room for one
VIA_D, VIA_DRILL, KEEP = 0.8, 0.4, 0.4 + 0.3
zones = list(board.Zones())
stitched = 0


def try_via(x, y):
    """Place a GND via at (x, y) mm if both pours fully surround it."""
    global stitched
    here = pcbnew.VECTOR2I(mm(x), mm(y))
    for t in board.GetTracks():
        if t.GetClass() == "PCB_VIA" and (t.GetPosition() - here).EuclideanNorm() < mm(1.6):
            return False
    pts = [pcbnew.VECTOR2I(mm(x + dx * KEEP), mm(y + dy * KEEP))
           for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1),
                          (.7, .7), (.7, -.7), (-.7, .7), (-.7, -.7))]
    if not all(z.HitTestFilledArea(z.GetLayer(), p, 0) for z in zones for p in pts):
        return False
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    v.SetWidth(mm(VIA_D))
    v.SetDrill(mm(VIA_DRILL))
    v.SetNet(gnd)
    board.Add(v)
    stitched += 1
    return True


y = 3.0
while y < H - 3:
    x = 3.0
    while x < W - 3:
        try_via(x, y)
        x += 7.62
    y += 7.62
pcbnew.ZONE_FILLER(board).Fill(board.Zones())

def report_text(report, item):
    """The violation description that mentions this item (has the layer)."""
    for v in report["violations"]:
        if item in v["items"]:
            return v["description"]
    return ""


def fix_island(px, py, layer):
    """Find the small piece of pour on `layer` that the pad at (px, py)
    connects to, and put a GND via inside it, joining it to the other
    layer's pour."""
    zone = next(z for z in zones if z.GetLayer() == layer)
    other = next(z for z in zones if z.GetLayer() != layer)
    polys = zone.GetFilledPolysList(layer)
    biggest = max(range(polys.OutlineCount()),
                  key=lambda i: polys.COutline(i).BBox().GetArea())
    ring = [pcbnew.VECTOR2I(mm(px + r * dx), mm(py + r * dy))
            for r in (1.2, 1.6, 2.0) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
    islands = {i for i in range(polys.OutlineCount()) if i != biggest
               for p in ring if polys.Contains(p, i)}
    for i in islands:
        box = polys.COutline(i).BBox()
        x0, y0 = pcbnew.ToMM(box.GetX()), pcbnew.ToMM(box.GetY())
        x1, y1 = x0 + pcbnew.ToMM(box.GetWidth()), y0 + pcbnew.ToMM(box.GetHeight())
        y = y0
        while y <= y1:
            x = x0
            while x <= x1:
                pts = [pcbnew.VECTOR2I(mm(x + dx * KEEP), mm(y + dy * KEEP))
                       for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1),
                                      (.7, .7), (.7, -.7), (-.7, .7), (-.7, -.7))]
                if all(polys.Contains(p, i) for p in pts) and \
                        all(other.HitTestFilledArea(other.GetLayer(), p, 0) for p in pts) and \
                        try_via(x, y):
                    return True
                x += 0.25
            y += 0.25
    return False


# Pads whose thermal spokes only reach an isolated piece of pour: put a
# via into the nearest spot that joins that piece to the other layer.
tried = set()
for attempt in range(8):
    pcbnew.SaveBoard("mini09.kicad_pcb", board)
    subprocess.run(["kicad-cli", "pcb", "drc", "--format", "json", "-o", "drc.json",
                    "mini09.kicad_pcb"], check=True, capture_output=True)
    report = json.load(open("drc.json"))
    starved = [i for v in report["violations"] if v["type"] == "starved_thermal"
               for i in v["items"] if "pad" in i["description"].lower()]
    if not starved:
        break
    for item in starved:
        px, py = item["pos"]["x"], item["pos"]["y"]
        why = report_text(report, item)
        layer = pcbnew.B_Cu if "B.Cu" in why else pcbnew.F_Cu
        # An isolated island gets a stitching via (once).  Too few spokes,
        # or a via that did not help: the pad keeps its routed GND track
        # and stops joining the pour.
        if "island" in why and (px, py) not in tried and fix_island(px, py, layer):
            tried.add((px, py))
            continue
        here = pcbnew.VECTOR2I(mm(px), mm(py))
        for pad in board.GetPads():
            if pad.GetPosition() == here and pad.GetNetname() == "GND":
                pad.SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_NONE)
                print(f"{pad.GetParentFootprint().GetReference()} pad {pad.GetNumber()}: "
                      "thermal relief blocked, connected by track only")
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())

pcbnew.SaveBoard("mini09.kicad_pcb", board)
os.remove("drc.json")

tracks = [t for t in board.GetTracks() if t.GetClass() == "PCB_TRACK"]
vias = [t for t in board.GetTracks() if t.GetClass() == "PCB_VIA"]
length = sum(pcbnew.ToMM(t.GetLength()) for t in tracks)
print(f"{len(tracks)} track segments ({length:.0f} mm), {len(vias) - stitched} signal vias, "
      f"{stitched} GND stitching vias, {removed} stubs removed")
