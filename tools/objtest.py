#!/usr/bin/env python3
"""
Test ASM.PRG's object files (and LINK.PRG) against lwasm and lwlink.

    objtest.py [--time SECS] [--keep] [--section] GROUP ...

A GROUP is one source, or several joined with '+', linked together.
With --section, each source's "org $1000" becomes "section code" first,
so a whole program is assembled as one relocatable section.

For each group:
  1. lwasm --format=obj on each source, lwlink --format=srec with
     tools/mini09.ld (init at $1000, code, the rest, bss last)
  2. ASM.PRG in emu6809 on each source (ASM.PRG FILE.ASM), writing
     FILE.O, then the same lwlink run on ASM's objects
  3. the two links compared byte for byte: load address, entry and data
  4. if LINK.PRG is built: LINK in emu6809 on ASM's objects and on
     lwasm's, each .PRG compared with the same (no __start: lwlink's
     entry is 0, LINK's $1000)
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import mkprg  # noqa: E402
from asmtest import read_prg  # noqa: E402

LWASM = shutil.which("lwasm") or "lwasm"
LWLINK = shutil.which("lwlink") or "lwlink"
SCRIPT = os.path.join(HERE, "mini09.ld")


def stage(srcs, lwdir, drive, section):
    """Sources and everything they may include -> lwdir (as named) and
    drive (upper case)"""
    dirs = {os.path.dirname(os.path.abspath(s)) for s in srcs} | {ROOT}
    for d in dirs:
        for f in os.listdir(d):
            if f.lower().endswith((".asm", ".inc")):
                for dst in (os.path.join(lwdir, f), os.path.join(drive, f.upper())):
                    if not os.path.exists(dst):
                        shutil.copy(os.path.join(d, f), dst)
    for s in srcs:
        text = open(s).read()
        if section:
            text = re.sub(r"(?mi)^(\s+)org\s+\$1000\b", r"\1section code", text)
        name = os.path.basename(s)
        open(os.path.join(lwdir, name), "w").write(text)
        open(os.path.join(drive, name.upper()), "w").write(text)


def lwlink(objs, out):
    r = subprocess.run([LWLINK, "--format=srec", "-s", SCRIPT, "-o", out] + objs,
                       capture_output=True, text=True)
    err = "\n".join(l for l in (r.stdout + r.stderr).splitlines()
                    if not l.startswith("Adding sect"))
    if r.returncode:
        return err or "lwlink failed"
    return mkprg.read_srec(out)


def emu(drive, keys, secs):
    shutil.copy(os.path.join(ROOT, "asm.prg"), os.path.join(drive, "ASM.PRG"))
    if os.path.exists(os.path.join(ROOT, "link.prg")):
        shutil.copy(os.path.join(ROOT, "link.prg"), os.path.join(drive, "LINK.PRG"))
    r = subprocess.run([os.path.join(ROOT, "emu6809"), "-v", "-k", "-d", drive,
                        "-f", "-t", str(secs), os.path.join(ROOT, "os.s19")],
                       input=keys, capture_output=True, text=True)
    return r.stdout


def compare(what, got, ref):
    gload, gdata, gentry = got
    rload, rdata, rentry = ref
    if (gload, gentry) != (rload, rentry):
        return (f"{what}: load/entry ${gload:04X}/${gentry:04X},"
                f" lwasm+lwlink ${rload:04X}/${rentry:04X}")
    for i, (x, y) in enumerate(zip(gdata, rdata)):
        if x != y:
            return f"{what}: ${gload + i:04X} is ${x:02X}, lwasm+lwlink ${y:02X}"
    if len(gdata) != len(rdata):
        return f"{what}: {len(gdata)} bytes, lwasm+lwlink {len(rdata)}"
    return None


def check(group, a):
    srcs = group.split("+")
    name = "+".join(os.path.basename(s) for s in srcs)
    with tempfile.TemporaryDirectory() as tmp:
        lwdir = os.path.join(tmp, "lw")
        drive = os.path.join(tmp, "drive")
        os.mkdir(lwdir)
        os.mkdir(drive)
        stage(srcs, lwdir, drive, a.section)
        base = [os.path.splitext(os.path.basename(s))[0] for s in srcs]
        for b in base:
            r = subprocess.run([LWASM, "--format=obj", "-o", b + ".o", b + ".asm"],
                               cwd=lwdir, capture_output=True, text=True)
            if r.returncode:
                return f"FAIL {name}: lwasm failed\n{r.stdout}{r.stderr}"
        ref = lwlink([os.path.join(lwdir, b + ".o") for b in base], os.path.join(tmp, "ref.s19"))
        if isinstance(ref, str):
            return f"FAIL {name}: lwlink on lwasm's objects failed\n{ref}"
        keys = "".join(f"ASM.PRG {b.upper()}.ASM\n" for b in base)
        linkprg = os.path.exists(os.path.join(ROOT, "link.prg"))
        if linkprg:
            keys += "LINK.PRG OUT.PRG " + " ".join(b.upper() + ".O" for b in base) + "\n"
            for b in base:      # lwasm's objects too, as B.LWO
                shutil.copy(os.path.join(lwdir, b + ".o"), os.path.join(drive, b.upper() + ".LWO"))
            keys += "LINK.PRG LW.PRG " + " ".join(b.upper() + ".LWO" for b in base) + "\n"
        out = emu(drive, keys, a.time)
        if a.keep:
            print(out)
        objs = []
        for b in base:
            o = os.path.join(drive, b.upper() + ".O")
            if not os.path.exists(o):
                tail = "\n".join(out.splitlines()[-8:])
                return f"FAIL {name}: ASM wrote no {b.upper()}.O\n{tail}"
            objs.append(o)
        got = lwlink(objs, os.path.join(tmp, "asm.s19"))
        if isinstance(got, str):
            return f"FAIL {name}: lwlink on ASM's objects failed\n{got}"
        bad = compare("ASM+lwlink", got, ref)
        if bad:
            return f"FAIL {name}: {bad}"
        msg = f"ok   {name}: {len(ref[1])} bytes at ${ref[0]:04X}"
        if linkprg:
            prg = os.path.join(drive, "OUT.PRG")
            if not os.path.exists(prg):
                tail = "\n".join(out.splitlines()[-8:])
                return f"FAIL {name}: LINK wrote no OUT.PRG\n{tail}"
            size, load, entry, data, flen = read_prg(prg)
            # no __start: lwlink's entry is 0, LINK's the first address
            rload, rdata, rentry = ref
            bad = compare("ASM+LINK", (load, data, entry), (rload, rdata, rentry or 0x1000))
            if bad:
                return f"FAIL {name}: {bad}"
            prg = os.path.join(drive, "LW.PRG")
            if not os.path.exists(prg):
                tail = "\n".join(out.splitlines()[-8:])
                return f"FAIL {name}: LINK wrote no LW.PRG from lwasm's objects\n{tail}"
            size, load, entry, data, flen = read_prg(prg)
            bad = compare("lwasm+LINK", (load, data, entry), (rload, rdata, rentry or 0x1000))
            if bad:
                return f"FAIL {name}: {bad}"
            msg += ", LINK too (on both)"
        return msg


def main():
    ap = argparse.ArgumentParser(description="compare ASM/LINK objects with lwasm/lwlink")
    ap.add_argument("groups", nargs="+")
    ap.add_argument("--time", type=int, default=120)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--section", action="store_true",
                    help='assemble each source as one section ("org $1000" -> "section code")')
    a = ap.parse_args()
    bad = 0
    for g in a.groups:
        r = check(g, a)
        print(r)
        bad += r.startswith("FAIL")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
