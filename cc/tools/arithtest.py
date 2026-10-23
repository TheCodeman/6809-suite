#!/usr/bin/env python3
"""
Test LIBC's 16- and 32-bit arithmetic helpers in emu6809.

Writes a program that calls each helper on a table of operands and
prints every result in hex, runs it, and compares each line with what C
says the answer is (division rounds towards 0, the remainder takes the
dividend's sign, >> of a signed value keeps the sign).

    python3 tools/arithtest.py [--keep]
"""
import argparse
import os
import random

import rt

M16, M32 = 0xFFFF, 0xFFFFFFFF


def s16(v):
    v &= M16
    return v - 0x10000 if v & 0x8000 else v


def s32(v):
    v &= M32
    return v - 0x100000000 if v & 0x80000000 else v


def cdiv(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def cmod(a, b):
    return a - cdiv(a, b) * b


def cmp(a, b):
    return (a > b) - (a < b)


INT_OPS = {
    "__mul": lambda a, b: a * b,
    "__divu": lambda a, b: a // b,
    "__modu": lambda a, b: a % b,
    "__divs": lambda a, b: cdiv(s16(a), s16(b)),
    "__mods": lambda a, b: cmod(s16(a), s16(b)),
    "__shl": lambda a, b: a << b if b < 16 else 0,
    "__shru": lambda a, b: a >> b if b < 16 else 0,
    "__shrs": lambda a, b: s16(a) >> min(b, 15),
}
LONG_OPS = {
    "__ladd": lambda a, b: a + b,
    "__lsub": lambda a, b: a - b,
    "__land": lambda a, b: a & b,
    "__lor": lambda a, b: a | b,
    "__lxor": lambda a, b: a ^ b,
    "__lmul": lambda a, b: a * b,
    "__ldivu": lambda a, b: a // b,
    "__lmodu": lambda a, b: a % b,
    "__ldivs": lambda a, b: cdiv(s32(a), s32(b)),
    "__lmods": lambda a, b: cmod(s32(a), s32(b)),
    "__lcmp": lambda a, b: cmp(s32(a), s32(b)),
    "__lcmpu": lambda a, b: cmp(a, b),
}
LONG_SHIFTS = {
    "__lshl": lambda a, n: a << n if n < 32 else 0,
    "__lshru": lambda a, n: a >> n if n < 32 else 0,
    "__lshrs": lambda a, n: s32(a) >> min(n, 31),
}
DIVS = ("div", "mod")

PRINT = """
; print D as 4 hex digits, X:D as 8
phex8:      pshs    d
            tfr     x,d
            bsr     phex4n
            puls    d
phex4:      bsr     phex4n
            ldb     #10
            bra     pch
phex4n:     pshs    b
            bsr     phex2
            puls    a
phex2:      pshs    a
            lsra
            lsra
            lsra
            lsra
            bsr     phex1
            puls    a
            anda    #15
phex1:      adda    #'0
            cmpa    #'9
            bls     ph1
            adda    #7
ph1:        tfr     a,b
pch:        clra
            pshs    d
            jsr     _putchar
            leas    2,s
            rts
"""


def vectors(bits, seed):
    rnd = random.Random(seed)
    m = (1 << bits) - 1
    edge = [0, 1, 2, 3, 7, 10, 255, 256, 1000, m, m - 1, m >> 1, (m >> 1) + 1,
            (m >> 1) + 2, m >> 8, 12345 & m, 0x5A5A5A5A & m]
    vals = edge + [rnd.getrandbits(bits) for _ in range(12)] + \
        [rnd.getrandbits(rnd.randint(1, bits)) for _ in range(12)]
    pairs = [(a, b) for a in edge[::2] for b in edge[::3]]
    pairs += [(rnd.choice(vals), rnd.choice(vals)) for _ in range(20)]
    return pairs


def run_prog(name, code):
    src = ["            section code",
           "            export  _main",
           "            import  _putchar",
           "            import  " + ",".join(list(INT_OPS) + list(LONG_OPS) +
                                         list(LONG_SHIFTS) + ["__lneg"]),
           "_main:"] + code + ["            ldd     #0", "            rts", PRINT,
                               "            endsection"]
    with rt.scratch() as tmp:
        path = os.path.join(tmp, name.lower() + ".asm")
        open(path, "w").write("\n".join(src) + "\n")
        drive = os.path.join(tmp, "drive")
        os.mkdir(drive)
        rt.build([path], os.path.join(drive, name + ".PRG"), tmp)
        return rt.run(drive, f"{name}.PRG", secs=120)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="show the program's output")
    args = ap.parse_args()

    code, want = [], []
    for name, f in INT_OPS.items():
        for a, b in vectors(16, name):
            if any(d in name for d in DIVS) and b == 0:
                continue
            if name in ("__divs", "__mods") and a == 0x8000 and b == M16:
                continue
            if "sh" in name:
                b %= 20
            code.append(f"            ldx     #${a:04X}\n            ldd     #${b:04X}\n"
                        f"            jsr     {name}\n            jsr     phex4")
            want.append((f"{name} {a:04X} {b:04X}", f"{f(a, b) & M16:04X}"))
    for name, f in list(LONG_OPS.items()) + list(LONG_SHIFTS.items()):
        for a, b in vectors(32, name):
            if any(d in name for d in DIVS) and b == 0:
                continue
            if name in ("__ldivs", "__lmods") and a == 0x80000000 and b == M32:
                continue
            shift = name in LONG_SHIFTS
            if shift:
                b %= 40
            push = (f"            ldd     #${a & M16:04X}\n            pshs    d\n"
                    f"            ldx     #${a >> 16:04X}\n            pshs    x\n")
            right = (f"            ldd     #${b:04X}\n" if shift else
                     f"            ldx     #${b >> 16:04X}\n            ldd     #${b & M16:04X}\n")
            pr = "phex4" if "cmp" in name else "phex8"
            code.append(push + right + f"            jsr     {name}\n"
                        f"            leas    4,s\n            jsr     {pr}")
            r = f(a, b)
            want.append((f"{name} {a:08X} {b:08X}",
                         f"{r & M16:04X}" if "cmp" in name else f"{r & M32:08X}"))
    for v in [0, 1, 0x80000000, 0xFFFFFFFF, 0x12345678, 0x00010000]:
        code.append(f"            ldx     #${v >> 16:04X}\n            ldd     #${v & M16:04X}\n"
                    f"            jsr     __lneg\n            jsr     phex8")
        want.append((f"__lneg {v:08X}", f"{-v & M32:08X}"))

    nint = sum(1 for w in want if not w[0].startswith("__l"))
    out = run_prog("ARITH1", code[:nint]) + "\n" + run_prog("ARITH2", code[nint:])
    got = out.split("\n")
    if args.keep:
        print(out)
    bad = 0
    for i, (what, w) in enumerate(want):
        g = got[i].strip() if i < len(got) else "(nothing)"
        if g != w:
            bad += 1
            if bad <= 20:
                print(f"FAIL {what}: got {g}, want {w}")
    print(f"arith: {len(want) - bad}/{len(want)} passed")
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
