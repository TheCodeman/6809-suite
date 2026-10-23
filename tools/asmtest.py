#!/usr/bin/env python3
"""
Test ASM.PRG (asm.asm) against lwasm: assemble each source both ways and
compare the program files.

    asmtest.py [--time SECS] [--keep] file.asm ...

For each file:
  1. lwasm --format=srec, then the .PRG fields mkprg.py would make
  2. a scratch flash drive with ASM.PRG and every .asm/.inc beside the
     source (names upper-cased, as the shell types them), then
     emu6809 -v -k -d drive os.s19 with "ASM.PRG FILE.ASM" typed on
     the keyboard
  3. the .PRG that ASM wrote, compared from the file size on (bytes 28..):
     size, load and entry addresses and every byte.  The name, creator
     and date are allowed to differ.

Exits non-zero if any file fails.
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

LWASM = shutil.which("lwasm") or "lwasm"


def lwasm_prg(src, tmp):
    """lwasm's output as (load, entry, data), or the error text"""
    s19 = os.path.join(tmp, "ref.s19")
    r = subprocess.run([LWASM, "--format=srec", "-o", s19, os.path.basename(src)],
                       cwd=os.path.dirname(os.path.abspath(src)),
                       capture_output=True, text=True)
    if r.returncode:
        return r.stdout + r.stderr
    load, data, entry = mkprg.read_srec(s19)
    return load, entry, data


def run_asm(src, drive, secs):
    """Run ASM on src in the emulator -> console output"""
    srcdir = os.path.dirname(os.path.abspath(src))
    for f in os.listdir(srcdir):
        if f.lower().endswith((".asm", ".inc")):
            shutil.copy(os.path.join(srcdir, f), os.path.join(drive, f.upper()))
    shutil.copy(os.path.join(ROOT, "asm.prg"), os.path.join(drive, "ASM.PRG"))
    keys = f"ASM.PRG {os.path.basename(src).upper()}\n"
    r = subprocess.run([os.path.join(ROOT, "emu6809"), "-v", "-k", "-d", drive,
                        "-f", "-t", str(secs), os.path.join(ROOT, "os.s19")],
                       input=keys, capture_output=True, text=True)
    return r.stdout


def read_prg(path):
    raw = open(path, "rb").read()
    if len(raw) < mkprg.HLEN or raw[:2] != b"M9":
        return None
    size = int.from_bytes(raw[28:30], "big")
    load = int.from_bytes(raw[30:32], "big")
    entry = int.from_bytes(raw[32:34], "big")
    return size, load, entry, raw[raw[3]:], len(raw)


def check(src, a):
    name = os.path.basename(src)
    with tempfile.TemporaryDirectory() as tmp:
        drive = os.path.join(tmp, "drive")
        os.mkdir(drive)
        ref = lwasm_prg(src, tmp)
        if isinstance(ref, str):
            return f"FAIL {name}: lwasm failed\n{ref}"
        out = run_asm(src, drive, a.time)
        if a.keep:
            print(out)
        prg = os.path.join(drive, re.sub(r"\.[^./]*$", "", name).upper() + ".PRG")
        if not os.path.exists(prg):
            tail = "\n".join(out.splitlines()[-8:])
            return f"FAIL {name}: no program file written\n{tail}"
        got = read_prg(prg)
        if got is None:
            return f"FAIL {name}: not a program file"
        size, load, entry, data, flen = got
        if size != flen:
            return f"FAIL {name}: header says {size} bytes, file has {flen}"
        rload, rentry, rdata = ref
        if (load, entry) != (rload, rentry):
            return (f"FAIL {name}: load/entry ${load:04X}/${entry:04X},"
                    f" lwasm ${rload:04X}/${rentry:04X}")
        for i, (x, y) in enumerate(zip(data, rdata)):
            if x != y:
                return (f"FAIL {name}: ${load + i:04X} is ${x:02X}, lwasm ${y:02X}")
        if len(data) != len(rdata):
            return f"FAIL {name}: {len(data)} bytes, lwasm {len(rdata)}"
        return f"ok   {name}: {len(data)} bytes at ${load:04X}, entry ${entry:04X}"


def main():
    ap = argparse.ArgumentParser(description="compare ASM.PRG with lwasm")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--time", type=int, default=120,
                    help="emulated seconds to let ASM run (default 120)")
    ap.add_argument("--keep", action="store_true", help="show the emulator's output")
    a = ap.parse_args()
    bad = 0
    for f in a.files:
        r = check(f, a)
        print(r)
        bad += r.startswith("FAIL")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
