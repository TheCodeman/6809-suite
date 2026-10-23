#!/usr/bin/env python3
"""
Autoroute mini09.kicad_pcb with Freerouting and keep only a clean result.

Freerouting 2.1 sometimes finishes by "restoring an earlier board" that
still has unrouted connections, and sometimes leaves tracks that short or
violate clearance.  Each result is imported into a scratch copy of the
board and checked with KiCad's DRC; anything but dangling stubs (which
finish.py removes) means another attempt.

    python3 route.py               # -> mini09.ses (fully routed)
"""
import json
import os
import subprocess
import sys
import pcbnew

JAR = "tools/freerouting-2.1.0.jar"
TRIES = 8

pcbnew.ExportSpecctraDSN(pcbnew.LoadBoard("mini09.kicad_pcb"), "mini09.dsn")

for attempt in range(1, TRIES + 1):
    subprocess.run(["java", "-Djava.awt.headless=true", "-jar", JAR,
                    "-de", "mini09.dsn", "-do", "mini09.ses", "-mp", "50",
                    "--gui.enabled=false"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    board = pcbnew.LoadBoard("mini09.kicad_pcb")
    if not pcbnew.ImportSpecctraSES(board, "mini09.ses"):
        sys.exit("could not import mini09.ses")
    board.BuildConnectivity()
    left = board.GetConnectivity().GetUnconnectedCount(False)
    pcbnew.SaveBoard("route-check.kicad_pcb", board)
    subprocess.run(["kicad-cli", "pcb", "drc", "--format", "json", "-o", "route-check.json",
                    "route-check.kicad_pcb"], check=True, capture_output=True)
    report = json.load(open("route-check.json"))
    bad = [v["type"] for v in report["violations"]
           if v["type"] not in ("track_dangling", "via_dangling")]
    for f in ("route-check.kicad_pcb", "route-check.json", "route-check.kicad_prl",
              "route-check.kicad_pro"):
        if os.path.exists(f):
            os.remove(f)
    print(f"route attempt {attempt}: {left} unconnected, {len(bad)} DRC errors")
    if left == 0 and not bad:
        sys.exit(0)
sys.exit(f"no complete route after {TRIES} attempts")
