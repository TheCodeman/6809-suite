#!/usr/bin/env python3
"""
Build tests/rt/iotest.asm on MINI09 itself, in emu6809: ASM.PRG assembles
CRT0, LIBC and the test, LINK.PRG links them.  The .PRG must have the same
bytes as the one lwasm and lwlink make on the PC.  Needs ../asm.prg and
../link.prg (make asm.prg link.prg in 6809-os).

    python3 tools/nativetest.py [--keep]
"""
import argparse
import os
import shutil

import rt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="show the emulator's output")
    args = ap.parse_args()

    srcs = [os.path.join(rt.LIB, f) for f in sorted(os.listdir(rt.LIB)) if f.endswith(".asm")]
    srcs += [os.path.join(rt.CC, "tests", "rt", "iotest.asm"),
             os.path.join(rt.ROOT, "syscalls.inc"), os.path.join(rt.ROOT, "vdp.inc")]
    with rt.scratch() as tmp:
        drive = os.path.join(tmp, "drive")
        os.mkdir(drive)
        for s in srcs:
            shutil.copy(s, os.path.join(drive, os.path.basename(s).upper()))
        shutil.copy(os.path.join(rt.ROOT, "asm.prg"), os.path.join(drive, "ASM.PRG"))
        shutil.copy(os.path.join(rt.ROOT, "link.prg"), os.path.join(drive, "LINK.PRG"))
        lines = ["ASM.PRG CRT0.ASM", "ASM.PRG LIBC.ASM", "ASM.PRG IOTEST.ASM",
                 "LINK.PRG IOTEST.PRG CRT0.O IOTEST.O LIBC.O"]
        out = rt.run(drive, "\n".join(lines), secs=300)
        if args.keep:
            print(out)
        rt.build([os.path.join(rt.CC, "tests", "rt", "iotest.asm")],
                 os.path.join(tmp, "REF.PRG"), tmp)
        got = os.path.join(drive, "IOTEST.PRG")
        a = open(got, "rb").read()[36:] if os.path.exists(got) else None
        b = open(os.path.join(tmp, "REF.PRG"), "rb").read()[36:]
    if a is None:
        print("FAIL: no IOTEST.PRG\n" + out)
        raise SystemExit(1)
    if a != b:
        d = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
        print(f"FAIL: {len(a)} bytes, lwlink's {len(b)}; first difference at ${0x1000 + d:04X}")
        raise SystemExit(1)
    print(f"nativetest: passed ({len(a)} bytes, the same as lwasm + lwlink)")


if __name__ == "__main__":
    main()
