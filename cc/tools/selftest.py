#!/usr/bin/env python3
"""
CC on MINI09, in emu6809: the four passes are compiled by cc09 and built
into CPP.PRG, PARSE.PRG, SEMA.PRG and GEN.PRG; MINI09 runs them on the
tests, lib/clib.c and their own sources; every file they write (.I, .A,
.N, .T, .ASM) must be the same bytes as cc09's.  Then ASM.PRG and
LINK.PRG on MINI09 assemble and link the passes from those .ASM files,
and the .PRGs must be the same as lwasm and lwlink's.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import time

import rt

CC09 = os.path.join(rt.CC, "cc09")
PASSES = [("CPP", "cpp.c"), ("PARSE", "parse.c"), ("SEMA", "sema.c"), ("GEN", "gen.c")]
SHARED = ["cc.h", "common.c", "lex.c"]      # what the passes' sources include


def cc09(args, cwd=None, keep=False):
    r = subprocess.run([CC09] + (["-k"] if keep else []) + args, cwd=cwd,
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"cc09 {' '.join(args)}:\n{r.stdout}{r.stderr}")
    return r.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="show the emulator's output")
    ap.add_argument("--no-link", action="store_true", help="skip ASM and LINK")
    args = ap.parse_args()
    srcs = ([os.path.join(rt.CC, s) for _, s in PASSES] +
            sorted(glob.glob(os.path.join(rt.CC, "tests", "cc", "*.c"))) +
            [os.path.join(rt.LIB, "clib.c")])
    bad = 0
    with rt.scratch() as tmp:
        # the passes, built on the PC
        prgs = {}
        for p, src in PASSES:
            asm = os.path.join(tmp, p + ".ASM")
            cc09(["-I", os.path.join(rt.CC, "include"), os.path.join(rt.CC, src), asm])
            prgs[p] = os.path.join(tmp, p + ".PRG")
            rt.build([asm], prgs[p], tmp)

        # a drive with them, the headers and the sources
        drive = os.path.join(tmp, "drive")
        os.makedirs(os.path.join(drive, "INCLUDE"))
        for f in glob.glob(os.path.join(rt.CC, "include", "*.h")):
            shutil.copy(f, os.path.join(drive, "INCLUDE", os.path.basename(f).upper()))
        for p in prgs:
            shutil.copy(prgs[p], os.path.join(drive, p + ".PRG"))
        for f in SHARED:
            shutil.copy(os.path.join(rt.CC, f), os.path.join(drive, f.upper()))
        lines, names = [], []
        for s in srcs:
            b = os.path.splitext(os.path.basename(s))[0].upper()
            names.append((s, b))
            shutil.copy(s, os.path.join(drive, b + ".C"))
            lines += [f"CPP.PRG {b}.C", f"PARSE.PRG {b}.I", f"SEMA.PRG {b}.A",
                      f"GEN.PRG {b}.T"]
        t0 = time.time()
        out = rt.run(drive, "\n".join(lines), secs=7200)
        if args.keep:
            print(out)
        print(f"selftest: {len(srcs)} files compiled on MINI09 ({time.time() - t0:.0f}s)")

        # cc09 on the same files, under the same names
        for s, b in names:
            ref = os.path.join(tmp, "ref", b)
            shutil.copytree(os.path.join(rt.CC, "include"), os.path.join(ref, "INCLUDE"))
            for f in SHARED:
                shutil.copy(os.path.join(rt.CC, f), ref)
            shutil.copy(s, os.path.join(ref, b + ".C"))
            err = cc09(["-I", "INCLUDE/", b + ".C", "X.ASM"], cwd=ref, keep=True)
            kept = err.split("kept in ")[-1].strip()
            for ext in ("I", "A", "N", "T", "ASM"):
                want = os.path.join(ref, "X.ASM") if ext == "ASM" else \
                    os.path.join(kept, "x." + ext.lower())
                got = os.path.join(drive, f"{b}.{ext}")
                if not os.path.exists(got):
                    print(f"FAIL {b}.{ext}: not written")
                    bad += 1
                    continue
                g, w = open(got, "rb").read(), open(want, "rb").read()
                if g != w:
                    d = next((i for i in range(min(len(g), len(w))) if g[i] != w[i]),
                             min(len(g), len(w)))
                    print(f"FAIL {b}.{ext}: {len(g)} bytes, cc09's {len(w)}; "
                          f"first difference at {d}")
                    bad += 1
            shutil.rmtree(kept)
        if bad:
            if not args.keep:
                print(out)
            raise SystemExit(1)
        print("selftest: every .I .A .N .T .ASM the same as cc09's")
        if args.no_link:
            return

        # ASM and LINK on MINI09 build the passes from MINI09's .ASM files
        for f in os.listdir(rt.LIB):
            if f.endswith(".asm"):
                shutil.copy(os.path.join(rt.LIB, f), os.path.join(drive, f.upper()))
        for f in ("syscalls.inc", "vdp.inc"):
            shutil.copy(os.path.join(rt.ROOT, f), os.path.join(drive, f.upper()))
        shutil.copy(os.path.join(rt.ROOT, "asm.prg"), os.path.join(drive, "ASM.PRG"))
        shutil.copy(os.path.join(rt.ROOT, "link.prg"), os.path.join(drive, "LINK.PRG"))
        lines = ["ASM.PRG CRT0.ASM", "ASM.PRG LIBC.ASM"]
        for p in prgs:
            lines += [f"ASM.PRG {p}.ASM", f"LINK.PRG {p}2.PRG CRT0.O {p}.O LIBC.O"]
        out = rt.run(drive, "\n".join(lines), secs=7200)
        if args.keep:
            print(out)
        for p in prgs:
            got = os.path.join(drive, p + "2.PRG")
            a = open(got, "rb").read()[36:] if os.path.exists(got) else None
            b = open(prgs[p], "rb").read()[36:]
            if a != b:
                print(f"FAIL {p}.PRG: built by ASM and LINK, not the same as lwasm + lwlink's")
                bad += 1
        if bad:
            raise SystemExit(1)
        print("selftest: passed (the passes built on MINI09 are the same as on the PC)")


if __name__ == "__main__":
    main()
