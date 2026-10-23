#!/usr/bin/env python3
"""
Test banked code (#pragma bank, CRT0B, LINK's banks) in emu6809.

    python3 tools/banktest.py [--keep] [--no-native] [--mkbig]

  1. tests/bank/bt*.asm, by hand: assembled by lwasm, linked by the
     reference linker (tools/pylink.py) with CRT0B, and run as BT.PRG and
     as SUB/BT.PRG (CRT0B finds its file by the path the shell was given).
     LINK.PRG must make the same bytes from the same objects.
  2. tests/bank/*.c: cc09, lwasm and pylink; run, the output must be
     tests/bank/bank.out, and the same as the program built without
     #pragma bank (all in common memory, with CRT0).
  3. The same C files compiled by CC.PRG on MINI09 (the passes, ASM,
     LINK): the same .PRG bytes as 2, and it runs.

--mkbig writes tests/bank/big1.c and big2.c, the filler that makes the
program need more than one page, and stops.
"""
import argparse
import os
import shutil
import subprocess
import sys

import rt

sys.path.insert(0, os.path.join(rt.ROOT, "tools"))
import pylink  # noqa: E402

T = os.path.join(rt.CC, "tests", "bank")
CC09 = os.path.join(rt.CC, "cc09")
CSRC = ["bmain.c", "bone.c", "btwo.c", "big1.c", "big2.c"]


def mkbig():
    """big1.c: big0-39 and bigsum; big2.c: big40-79.  Every tenth calls
    one in the other file.  (Few and long: CC has room for 256
    parameters in all.)"""
    N = 40
    for f, lo in (("big1.c", 0), ("big2.c", N)):
        L = ["/* banked filler, made by tools/banktest.py --mkbig */", "#pragma bank", ""]
        for n in range(2 * N):
            L.append(f"int big{n}(int x);")
        L.append("")
        for n in range(lo, lo + N):
            L += [f"int big{n}(int x)", "{", "    int a, b, i;",
                  f"    a = x * {n % 13 + 1} + {n};", "    b = a ^ (x << 2);",
                  f"    for (i = 0; i < {n % 4 + 2}; i++) {{",
                  "        if (b & 1)", f"            b = b + {n % 5} * i;", "        else",
                  "            b = b - x + i;",
                  f"        a = (a >> 1) + (b & {n % 31 + 1});",
                  f"        b = b * 3 + a % {n % 7 + 2};",
                  "    }",
                  f"    switch (a & 3) {{",
                  f"    case 0: b = b + {n};", "        break;",
                  f"    case 1: b = b - {n};", "        break;",
                  f"    case 2: b = b ^ {n * 3};", "        break;",
                  "    default: b = ~b;", "    }"]
            if n % 10 == 3:
                L.append(f"    if (x > 0)\n        b = b + big{(n + N) % (2 * N)}(x - 1);")
            L += ["    return a + b;", "}", ""]
        if lo == 0:
            L += ["int bigsum(int x)", "{", "    int s;", "    s = 0;"]
            L += [f"    s = s + big{n}(x);" for n in range(2 * N)]
            L += ["    return s;", "}", ""]
        open(os.path.join(T, f), "w").write("\n".join(L))


def cc09(src, out):
    r = subprocess.run([CC09, "-I", os.path.join(rt.CC, "include"), src, out],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"cc09 {src}:\n{r.stdout}{r.stderr}")
    return "is banked" in r.stderr


def plink(objs, prg):
    lo, data, entry, tail, order, nbank = pylink.link(objs)
    name = os.path.basename(prg).upper()
    open(prg, "wb").write(rt.mkprg.make(name, "PYLINK", None, lo, entry, data) + tail)
    return len(data), nbank, len(tail)


def body(path):
    """a .PRG without its header, which names the program and its maker"""
    return open(path, "rb").read()[36:] if os.path.exists(path) else None


def first_diff(a, b):
    return next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))


def fail(msg, out=""):
    print("FAIL " + msg + ("\n" + out if out else ""))
    raise SystemExit(1)


def asm_test(tmp, keep):
    drive = os.path.join(tmp, "asm")
    os.makedirs(os.path.join(drive, "SUB"))
    crt0b = os.path.join(tmp, "crt0b.o")
    rt.asm(os.path.join(rt.LIB, "crt0b.asm"), crt0b)
    libc = os.path.join(tmp, "libc.o")
    rt.asm(os.path.join(rt.LIB, "libc.asm"), libc)
    objs = [crt0b]
    for b in ("btmain", "btb1", "btb2"):
        o = os.path.join(tmp, b + ".o")
        rt.asm(os.path.join(T, b + ".asm"), o)
        objs.append(o)
    objs.append(libc)
    ref = os.path.join(tmp, "BT.PRG")
    plink(objs, ref)
    shutil.copy(ref, os.path.join(drive, "BT.PRG"))
    shutil.copy(ref, os.path.join(drive, "SUB", "BT.PRG"))
    open(os.path.join(drive, "BT.TXT"), "w").write("ABC")
    shutil.copy(os.path.join(rt.ROOT, "link.prg"), os.path.join(drive, "LINK.PRG"))
    names = []
    for o in objs:
        n = os.path.basename(o).upper()
        shutil.copy(o, os.path.join(drive, n))
        names.append(n)
    want = open(os.path.join(T, "bt.out")).read().rstrip("\n")
    for line in ("BT.PRG", "SUB/BT.PRG"):
        out = rt.run(drive, line)
        if keep:
            print(out)
        if out != want:
            fail(f"{line}: not tests/bank/bt.out", out)
    out = rt.run(drive, "LINK.PRG LBT.PRG " + " ".join(names), secs=120)
    if keep:
        print(out)
    a, b = body(os.path.join(drive, "LBT.PRG")), body(ref)
    if a is None:
        fail("LINK.PRG wrote no LBT.PRG", out)
    if a != b:
        fail(f"LINK.PRG: {len(a)} bytes, pylink's {len(b)}; first difference at {first_diff(a, b)}")
    print(f"ok   bt: runs (from a folder too), LINK.PRG the same as pylink ({len(b)} bytes)")
    return crt0b, libc


def c_test(tmp, keep, crt0b, libc):
    drive = os.path.join(tmp, "c")
    os.mkdir(drive)
    clib = os.path.join(tmp, "clib.asm")
    cc09(os.path.join(rt.LIB, "clib.c"), clib)
    clibo = os.path.join(tmp, "clib.o")
    rt.asm(clib, clibo)
    objs, asms, flat = [], [], []
    for c in CSRC:
        b = c[:-2]
        a = os.path.join(tmp, b + ".asm")
        banked = cc09(os.path.join(T, c), a)
        if banked != (c != "bmain.c"):
            fail(f"{c}: cc09 says banked is {banked}")
        o = os.path.join(tmp, b + ".o")
        rt.asm(a, o)
        objs.append(o)
        asms.append(a)
        # the same without #pragma bank
        fc = os.path.join(tmp, "flat_" + c)
        open(fc, "w").write(open(os.path.join(T, c)).read().replace("#pragma bank", ""))
        fa = os.path.join(tmp, "flat_" + b + ".asm")
        cc09(fc, fa)
        flat.append(fa)
    prg = os.path.join(tmp, "BMAIN.PRG")
    size, nbank, tail = plink([crt0b] + objs + [clibo, libc], prg)
    if nbank < 2:
        fail(f"only {nbank} bank(s): the test wants the code in two or more")
    shutil.copy(prg, os.path.join(drive, "BMAIN.PRG"))
    out = rt.run(drive, "BMAIN.PRG", secs=120)
    if keep:
        print(out)
    want = open(os.path.join(T, "bank.out")).read().rstrip("\n")
    if out != want:
        fail("BMAIN.PRG: not tests/bank/bank.out", out)
    fdrive = os.path.join(tmp, "flat")
    os.mkdir(fdrive)
    fdir = os.path.join(tmp, "flatobj")
    os.mkdir(fdir)
    rt.build(flat + [clib], os.path.join(fdrive, "BMAIN.PRG"), fdir)
    fo = [os.path.join(fdir, n) for n in ["crt0.o"] + [os.path.basename(a)[:-4] + ".o"
                                                      for a in flat + [clib]] + ["libc.o"]]
    order = pylink.link(fo)[4]
    end = order[-1].addr + order[-1].size
    if end > 0x8000:
        fail(f"without #pragma bank the program would end at ${end:04X}: make big*.c smaller")
    fout = rt.run(fdrive, "BMAIN.PRG", secs=120)
    if fout != out:
        fail("not the same output without #pragma bank", fout)
    flatsize = len(body(os.path.join(fdrive, "BMAIN.PRG")))
    print(f"ok   bank.c: {size} bytes common and {nbank} banks ({tail} bytes),"
          f" the same output as all in common ({flatsize} bytes)")
    return prg


def native_test(tmp, keep, ref):
    import mkdrive
    drive = os.path.join(tmp, "native")
    sys.argv = ["mkdrive.py", drive]
    mkdrive.main()
    # short names: LINK's arguments must fit in 64 characters
    short = ["BM.C", "B1.C", "B2.C", "G1.C", "G2.C"]
    for c, n in zip(CSRC, short):
        shutil.copy(os.path.join(T, c), os.path.join(drive, n))
    line = "CC.PRG " + " ".join(short)
    out = rt.run(drive, line + "\nBM.PRG", secs=3600)
    if keep:
        print(out)
    a, b = body(os.path.join(drive, "BM.PRG")), body(ref)
    if a is None:
        fail("CC.PRG wrote no BM.PRG", out)
    if a != b:
        fail(f"CC.PRG: {len(a)} bytes, cc09+lwasm+pylink's {len(b)};"
             f" first difference at {first_diff(a, b)}", out)
    want = open(os.path.join(T, "bank.out")).read().rstrip("\n")
    if want not in out:
        fail("CC.PRG's BMAIN.PRG: not tests/bank/bank.out", out)
    left = [f for f in os.listdir(drive) if f.endswith((".B", ".I", ".T", ".ASM"))]
    if left:
        fail("CC.PRG left " + " ".join(left))
    print("ok   CC.PRG on MINI09: the same bytes, and it runs")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="show the programs' output")
    ap.add_argument("--no-native", action="store_true", help="skip CC.PRG on MINI09 (slow)")
    ap.add_argument("--mkbig", action="store_true")
    args = ap.parse_args()
    if args.mkbig:
        mkbig()
        return
    with rt.scratch() as tmp:
        crt0b, libc = asm_test(tmp, args.keep)
        prg = c_test(tmp, args.keep, crt0b, libc)
        if not args.no_native:
            native_test(tmp, args.keep, prg)
    print("banktest: passed")


if __name__ == "__main__":
    main()
