#!/usr/bin/env python3
"""
Test the compiler: each tests/cc/NAME.c is compiled by cc09, assembled and
linked with CRT0 and LIBC (and lib/clib.c, compiled by cc09 too) and run
in emu6809 as NAME.PRG A B C.  The output must match tests/cc/NAME.out.

    python3 tools/cctest.py [--keep] [NAME ...]
"""
import argparse
import os
import subprocess
import sys

import rt

T = os.path.join(rt.CC, "tests", "cc")
CC09 = os.path.join(rt.CC, "cc09")


def compile_c(src, out):
    r = subprocess.run([CC09, "-I", os.path.join(rt.CC, "include"), src, out],
                       capture_output=True, text=True)
    if r.returncode:
        return r.stdout + r.stderr
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="show each program's output")
    ap.add_argument("names", nargs="*")
    args = ap.parse_args()
    names = args.names or sorted(f[:-2] for f in os.listdir(T) if f.endswith(".c"))
    bad = 0
    with rt.scratch() as tmp:
        clib = []
        csrc = os.path.join(rt.LIB, "clib.c")
        if os.path.exists(csrc):
            casm = os.path.join(tmp, "clib.asm")
            err = compile_c(csrc, casm)
            if err:
                sys.exit("clib.c:\n" + err)
            clib = [casm]
        for n in names:
            drive = os.path.join(tmp, n)
            os.mkdir(drive)
            a = os.path.join(tmp, n + ".asm")
            err = compile_c(os.path.join(T, n + ".c"), a)
            if err:
                print(f"FAIL {n}: cc09\n{err}")
                bad += 1
                continue
            try:
                rt.build([a] + clib, os.path.join(drive, n.upper() + ".PRG"), tmp)
            except SystemExit as e:
                print(f"FAIL {n}: {e}")
                bad += 1
                continue
            out = rt.run(drive, f"{n.upper()}.PRG A B C", secs=120)
            if args.keep:
                print(out)
            want = open(os.path.join(T, n + ".out")).read().rstrip("\n")
            if out != want:
                g, w = out.split("\n"), want.split("\n")
                i = next((i for i in range(max(len(g), len(w)))
                          if (g[i:i + 1] or ["(nothing)"]) != (w[i:i + 1] or ["(nothing)"])), 0)
                print(f"FAIL {n} line {i + 1}: got {(g[i:i+1] or ['(nothing)'])[0]!r}, "
                      f"want {(w[i:i+1] or ['(nothing)'])[0]!r}")
                bad += 1
            else:
                print(f"ok   {n}")
    print("cctest: " + ("passed" if not bad else f"{bad} failure(s)"))
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
