#!/usr/bin/env python3
"""
Test LIBC's arguments, string.h and files in emu6809: builds
tests/rt/iotest.asm, runs it from a scratch drive holding IN.TXT, INC.TXT
and a 40K BIG.TXT, and checks the console output against
tests/rt/iotest.out and the files it wrote.

    python3 tools/iotest.py [--keep]
"""
import argparse
import os

import rt

T = os.path.join(rt.CC, "tests", "rt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="show the program's output")
    args = ap.parse_args()

    big = b"".join(b"line %05d of the big file\n" % i for i in range(1600))  # 40K
    with rt.scratch() as tmp:
        drive = os.path.join(tmp, "drive")
        os.mkdir(drive)
        open(os.path.join(drive, "IN.TXT"), "wb").write(b"Hello, files.\n#Back to IN.\n")
        open(os.path.join(drive, "INC.TXT"), "wb").write(b"[included text]\n")
        open(os.path.join(drive, "BIG.TXT"), "wb").write(big)
        rt.build([os.path.join(T, "iotest.asm")], os.path.join(drive, "IOTEST.PRG"), tmp)
        out = rt.run(drive, "IOTEST.PRG ONE TWO  THREE", secs=60)
        big2 = open(os.path.join(drive, "BIG2.TXT"), "rb").read() \
            if os.path.exists(os.path.join(drive, "BIG2.TXT")) else b""
    if args.keep:
        print(out)
    want = open(os.path.join(T, "iotest.out")).read().rstrip("\n")
    bad = 0
    g, w = out.split("\n"), want.split("\n")
    for i in range(max(len(g), len(w))):
        a = g[i] if i < len(g) else "(nothing)"
        b = w[i] if i < len(w) else "(nothing)"
        if a != b:
            print(f"FAIL line {i + 1}: got {a!r}, want {b!r}")
            bad += 1
    if big2 != big:
        print(f"FAIL BIG2.TXT: {len(big2)} bytes, want a copy of BIG.TXT ({len(big)})")
        bad += 1
    print("iotest: " + ("passed" if not bad else f"{bad} failure(s)"))
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
