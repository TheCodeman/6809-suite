#!/usr/bin/env python3
"""
A folder to copy to the flash drive, for CC on the board (make drive):

    CC.PRG                               runs all the steps (lib/ccdrv.asm)
    CPP.PRG PARSE.PRG SEMA.PRG GEN.PRG   the passes, built by cc09
    ASM.PRG LINK.PRG EDIT.PRG            from the folder above
    CRT0.O CRT0B.O LIBC.O CLIB.O         the runtime, to link with (CRT0B.O
                                         for banked code)
    INCLUDE/*.H                          the headers
    *.C                                  the tests (HELLO.C ...)
    CPP.C PARSE.C SEMA.C GEN.C           the passes' own sources, and
    CC.H COMMON.C LEX.C                  what they include, so the board
                                         can compile CC too

Names are in capitals, as MINI09 writes them.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys

import rt

CC09 = os.path.join(rt.CC, "cc09")
PASSES = [("CPP", "cpp.c"), ("PARSE", "parse.c"), ("SEMA", "sema.c"), ("GEN", "gen.c")]


def cc09(src, out):
    r = subprocess.run([CC09, "-I", os.path.join(rt.CC, "include"), src, out],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"cc09 {src}:\n{r.stdout}{r.stderr}")


def ccdrv(prg, tmp):
    """CC.PRG: lib/ccdrv.asm, not relocatable, so straight to S-records"""
    s19 = os.path.join(tmp, "cc.s19")
    r = subprocess.run([rt.LWASM, "--format=srec", "-I", rt.LIB, "-I", rt.ROOT, "-o", s19,
                        os.path.join(rt.LIB, "ccdrv.asm")], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"lwasm ccdrv.asm:\n{r.stdout}{r.stderr}")
    load, data, entry = rt.mkprg.read_srec(s19)
    open(prg, "wb").write(rt.mkprg.make("CC.PRG", "LWASM", None, load, entry or load, data))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", nargs="?", default=os.path.join(rt.CC, "drive"))
    args = ap.parse_args()
    d = args.dir
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(d, "INCLUDE"))
    with rt.scratch() as tmp:
        for p, src in PASSES:
            asm = os.path.join(tmp, p + ".ASM")
            cc09(os.path.join(rt.CC, src), asm)
            rt.build([asm], os.path.join(d, p + ".PRG"), tmp)
        rt.asm(os.path.join(rt.LIB, "crt0.asm"), os.path.join(d, "CRT0.O"))
        rt.asm(os.path.join(rt.LIB, "crt0b.asm"), os.path.join(d, "CRT0B.O"))
        rt.asm(os.path.join(rt.LIB, "libc.asm"), os.path.join(d, "LIBC.O"))
        cc09(os.path.join(rt.LIB, "clib.c"), os.path.join(tmp, "CLIB.ASM"))
        rt.asm(os.path.join(tmp, "CLIB.ASM"), os.path.join(d, "CLIB.O"))
        ccdrv(os.path.join(d, "CC.PRG"), tmp)
    for f in ("asm.prg", "link.prg", "edit.prg"):
        src = os.path.join(rt.ROOT, f)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(d, f.upper()))
        else:
            print(f"drive: no {f} in {rt.ROOT}, run make there first")
    for f in glob.glob(os.path.join(rt.CC, "include", "*.h")):
        shutil.copy(f, os.path.join(d, "INCLUDE", os.path.basename(f).upper()))
    for f in glob.glob(os.path.join(rt.CC, "tests", "cc", "*.c")):
        shutil.copy(f, os.path.join(d, os.path.basename(f).upper()))
    for f in [s for _, s in PASSES] + ["cc.h", "common.c", "lex.c"]:
        shutil.copy(os.path.join(rt.CC, f), os.path.join(d, f.upper()))
    print(f"drive: {len(os.listdir(d)) - 1} files and INCLUDE/ in {d}")


if __name__ == "__main__":
    main()
