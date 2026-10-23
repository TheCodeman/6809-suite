#!/usr/bin/env python3
"""srec2bin.py file.s19 base size out.bin [--check] - S1 records -> ROM image
($FF fill).  With --check, stop with an error if a record lies outside
base..base+size (a kernel that has wrapped past $FFFF) or two records
write the same byte (code that has run into the vectors)."""
import sys

args = [a for a in sys.argv[1:] if a != "--check"]
check = "--check" in sys.argv
src, base, size, out = args[0], int(args[1], 0), int(args[2], 0), args[3]
rom = bytearray(b"\xff" * size)
seen = set()
for line in open(src):
    if not line.startswith("S1"):
        continue
    n, addr = int(line[2:4], 16), int(line[4:8], 16)
    for i, b in enumerate(bytes.fromhex(line[8:8 + 2 * (n - 3)])):
        a = (addr + i) & 0xFFFF
        if base <= a < base + size:
            if check and a in seen:
                sys.exit(f"{src}: ${a:04X} is written twice (code runs into the vectors?)")
            seen.add(a)
            rom[a - base] = b
        elif check:
            sys.exit(f"{src}: ${a:04X} is outside ${base:04X}-${base + size - 1:04X} "
                     "(the code is too big?)")
open(out, "wb").write(rom)
