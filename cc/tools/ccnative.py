#!/usr/bin/env python3
"""
Assemble and link compiled C on MINI09 itself, in emu6809: cc09 compiles
tests/cc/ptr.c and lib/clib.c on the PC, then ASM.PRG assembles them with
CRT0 and LIBC and LINK.PRG links them.  The .PRG must have the same bytes
as the one lwasm and lwlink make, and must run.

    python3 tools/ccnative.py [--keep]
"""
import argparse
import os
import shutil
import subprocess

import rt

CC09 = os.path.join(rt.CC, "cc09")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="show the emulator's output")
    args = ap.parse_args()

    with rt.scratch() as tmp:
        drive = os.path.join(tmp, "drive")
        os.mkdir(drive)
        for src, name in [(os.path.join(rt.CC, "tests", "cc", "ptr.c"), "PTR.ASM"),
                          (os.path.join(rt.LIB, "clib.c"), "CLIB.ASM")]:
            subprocess.run([CC09, "-I", os.path.join(rt.CC, "include"), src,
                            os.path.join(tmp, name)], check=True, capture_output=True)
            shutil.copy(os.path.join(tmp, name), os.path.join(drive, name))
        for f in os.listdir(rt.LIB):
            if f.endswith(".asm"):
                shutil.copy(os.path.join(rt.LIB, f), os.path.join(drive, f.upper()))
        for f in ("syscalls.inc", "vdp.inc"):
            shutil.copy(os.path.join(rt.ROOT, f), os.path.join(drive, f.upper()))
        shutil.copy(os.path.join(rt.ROOT, "asm.prg"), os.path.join(drive, "ASM.PRG"))
        shutil.copy(os.path.join(rt.ROOT, "link.prg"), os.path.join(drive, "LINK.PRG"))
        lines = ["ASM.PRG CRT0.ASM", "ASM.PRG LIBC.ASM", "ASM.PRG PTR.ASM",
                 "ASM.PRG CLIB.ASM", "LINK.PRG PTR.PRG CRT0.O PTR.O CLIB.O LIBC.O",
                 "PTR.PRG"]
        out = rt.run(drive, "\n".join(lines), secs=600)
        if args.keep:
            print(out)
        rt.build([os.path.join(tmp, "PTR.ASM"), os.path.join(tmp, "CLIB.ASM")],
                 os.path.join(tmp, "REF.PRG"), tmp)
        got = os.path.join(drive, "PTR.PRG")
        a = open(got, "rb").read()[36:] if os.path.exists(got) else None
        b = open(os.path.join(tmp, "REF.PRG"), "rb").read()[36:]
    want = open(os.path.join(rt.CC, "tests", "cc", "ptr.out")).read().rstrip("\n")
    if a is None:
        print("FAIL: no PTR.PRG\n" + out)
        raise SystemExit(1)
    if a != b:
        d = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
        print(f"FAIL: {len(a)} bytes, lwlink's {len(b)}; first difference at ${0x1000 + d:04X}")
        raise SystemExit(1)
    if want not in out:
        print("FAIL: PTR.PRG's output isn't tests/cc/ptr.out\n" + out)
        raise SystemExit(1)
    print(f"ccnative: passed ({len(a)} bytes, the same as lwasm + lwlink, and it runs)")


if __name__ == "__main__":
    main()
