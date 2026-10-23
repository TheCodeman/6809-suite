#!/usr/bin/env python3
"""
MINI09 program files (.PRG): make one from S-records, or show a header.

    mkprg.py prog.s19 PROG.PRG [--name NAME] [--creator LWASM] [--date YYYY-MM-DD]
    mkprg.py --info PROG.PRG

The file is a 36-byte header and then the bytes to load at one address
(numbers big-endian, as on the 6809):

    0  "M9"         magic
    2  1            format version
    3  36           header length (a loader skips anything past 36)
    4  name         12 bytes, NUL-padded (the file name, without directory)
    16 creator      8 bytes, NUL-padded (what made the file)
    24 date         year (2 bytes), month, day; all 0 if unknown
    28 file size    header included
    30 load address
    32 entry address
    34 0, 0         reserved

The S-records' lowest to highest address become the data (gaps are filled
with 0); the S9 record gives the entry address.  The date defaults to
today, the name to the output file's, the creator to "LWASM".
"""
import argparse
import datetime
import os
import struct
import sys

HLEN = 36


def read_srec(path):
    mem, entry = {}, None
    for line in open(path):
        line = line.strip()
        if line.startswith("S1"):
            n, addr = int(line[2:4], 16), int(line[4:8], 16)
            for i, b in enumerate(bytes.fromhex(line[8:8 + 2 * (n - 3)])):
                mem[(addr + i) & 0xFFFF] = b
        elif line.startswith("S9"):
            entry = int(line[4:8], 16)
    if not mem:
        sys.exit(f"{path}: no S1 records")
    lo, hi = min(mem), max(mem)
    data = bytes(mem.get(a, 0) for a in range(lo, hi + 1))
    return lo, data, lo if entry is None else entry


def make(name, creator, date, load, entry, data):
    size = HLEN + len(data)
    if size > 0xFFFF:
        sys.exit("program too big for a 16-bit file size")
    hdr = struct.pack(">2sBB12s8sHBBHHHH", b"M9", 1, HLEN,
                      name.encode()[:12], creator.encode()[:8],
                      date.year if date else 0, date.month if date else 0,
                      date.day if date else 0, size, load, entry, 0)
    assert len(hdr) == HLEN
    return hdr + data


def info(path):
    raw = open(path, "rb").read()
    if raw[:2] != b"M9":
        sys.exit(f"{path}: not a MINI09 program file")
    (magic, ver, hlen, name, creator, year, month, day, size, load, entry,
     _) = struct.unpack(">2sBB12s8sHBBHHHH", raw[:HLEN])
    s = lambda b: b.rstrip(b"\0").decode(errors="replace")
    date = f"{year:04d}-{month:02d}-{day:02d}" if year else "unknown"
    n = size - hlen
    print(f"{path}: {s(name)}, version {ver}, made by {s(creator)}, date {date}")
    print(f"  {size} bytes: header {hlen}, {n} to load at ${load:04X}-${load + n - 1:04X},"
          f" entry ${entry:04X}")
    if size != len(raw):
        print(f"  warning: the file is {len(raw)} bytes")


def main():
    ap = argparse.ArgumentParser(description="make or show a MINI09 .PRG program file")
    ap.add_argument("src", help="S-record file, or the .PRG with --info")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--info", action="store_true", help="show a .PRG's header")
    ap.add_argument("--name", help="name in the header (default: the output file's)")
    ap.add_argument("--creator", default="LWASM")
    ap.add_argument("--date", help="YYYY-MM-DD, 'none' for unknown (default: today)")
    a = ap.parse_args()
    if a.info:
        return info(a.src)
    if not a.out:
        ap.error("an output file is needed")
    if a.date == "none":
        date = None
    elif a.date:
        date = datetime.date.fromisoformat(a.date)
    else:
        date = datetime.date.today()
    load, data, entry = read_srec(a.src)
    name = (a.name or os.path.basename(a.out)).upper()
    open(a.out, "wb").write(make(name, a.creator, date, load, entry, data))


if __name__ == "__main__":
    main()
