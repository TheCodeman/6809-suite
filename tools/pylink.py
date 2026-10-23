#!/usr/bin/env python3
"""
A linker for lwasm's LWOBJ16 objects, written to be read: the reference
LINK.PRG is tested against for banked code, which lwlink can't place.

    pylink.py OUT.PRG A.O B.O ...  [--map]

Without banked sections it gives the same bytes as lwlink with
tools/mini09.ld (objtest checks that), and the same as LINK.PRG:

  * from $1000: every "init" section in file order, then every "code"
    section, then the other sections that aren't bss (the first object's
    first; each name gathers every object's sections of that name), then
    the bss ones
  * s_NAME / l_NAME: where the sections called NAME start, and their
    total length
  * an import is looked up in those, then in the same object's exports,
    then in every object's exports in file order; a local symbol in its
    own section, then in the object's other sections
  * the entry is __start if an object exports it, else $1000

Banked code (cc/cc.md): each object's section "banked" goes into a 16K
RAM page at $8000-$BFFF instead, packed first fit from page FIRSTBANK in
file order.  In that object, the import "__bank" is its page.
"__nbank" is the number of pages used.  The pages follow the program's
normal part in the .PRG, after its header's file size:

    "B9", count, then for each page: page number, length (2), the bytes
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkprg  # noqa: E402

LOAD = 0x1000
WINDOW = 0x8000
BANKSIZE = 0x4000
FIRSTBANK = 7
MAXBANK = 16


class LinkError(Exception):
    pass


class Section:
    def __init__(self, obj, name, flags):
        self.obj, self.name, self.flags = obj, name, flags
        self.locals, self.exports, self.relocs = {}, {}, []
        self.code, self.size, self.addr, self.page = b"", 0, None, None

    @property
    def bss(self):
        return bool(self.flags & 1)


def cstr(b, i):
    j = b.index(0, i)
    return b[i:j].decode("latin-1"), j + 1


def read_obj(path):
    b = open(path, "rb").read()
    if b[:8] != b"LWOBJ16\0":
        raise LinkError(f"Not an object file: {path}")
    obj = {"path": path, "sections": []}
    i = 8
    while b[i]:
        name, i = cstr(b, i)
        flags = 0
        while b[i]:
            flags |= b[i]
            i += 1
        i += 1
        s = Section(obj, name, flags)
        if name.lower() in ("bss", ".bss"):
            s.flags |= 1
        for table in (s.locals, s.exports):
            while b[i]:
                sym, i = cstr(b, i)
                table[sym] = b[i] << 8 | b[i + 1]
                i += 2
            i += 1
        while b[i]:
            terms, size = [], 2
            while b[i]:
                t = b[i]
                if t == 1:
                    terms.append(("int", b[i + 1] << 8 | b[i + 2]))
                    i += 3
                elif t in (2, 3):
                    sym, i = cstr(b, i + 1)
                    terms.append(("imp" if t == 2 else "loc", sym))
                elif t == 4:
                    terms.append(("op", b[i + 1]))
                    i += 2
                elif t == 0xFF:
                    if b[i + 1] == 1:
                        size = 1
                    i += 2
                else:
                    raise LinkError(f"{path}: bad expression term {t}")
            i += 1
            s.relocs.append((b[i] << 8 | b[i + 1], size, terms))
            i += 2
        i += 1
        s.size = b[i] << 8 | b[i + 1]
        i += 2
        if not s.bss:
            s.code = b[i:i + s.size]
            i += s.size
        obj["sections"].append(s)
    return obj


def place(objs):
    """Addresses for the common sections, pages for the banked ones"""
    secs = [s for o in objs for s in o["sections"]]
    common = [s for s in secs if s.name != "banked"]
    order = []
    for name in ("init", "code"):
        order += [s for s in common if s.name == name]
    for want_bss in (False, True):
        for s in common:
            if s not in order and s.bss == want_bss:
                order += [t for t in common if t.name == s.name and t not in order]
    addr = LOAD
    for s in order:
        s.addr = addr
        addr += s.size
    if addr > WINDOW:
        raise LinkError(f"Program too big: ends at ${addr:04X}")
    used = []                   # bytes used in each page
    for s in secs:
        if s.name != "banked" or s.size == 0:
            continue
        if s.size > BANKSIZE:
            raise LinkError(f"Bank too big: {s.obj['path']} ({s.size} bytes)")
        for n, u in enumerate(used):
            if u + s.size <= BANKSIZE:
                break
        else:
            if len(used) == MAXBANK:
                raise LinkError("Too many banks")
            used.append(0)
            n = len(used) - 1
        s.page, s.addr = FIRSTBANK + n, WINDOW + used[n]
        used[n] += s.size
    return order, len(used)


def link(paths):
    objs = [read_obj(p) for p in paths]
    order, nbank = place(objs)
    syn = {}
    for s in order:
        if "s_" + s.name not in syn:
            syn["s_" + s.name] = s.addr
            syn["l_" + s.name] = 0
        syn["l_" + s.name] += s.size

    def ext(sym, obj):
        if sym == "__nbank":
            return nbank
        if sym == "__bank":
            pages = [s.page for s in obj["sections"] if s.page is not None]
            if not pages:
                raise LinkError(f"__bank in {obj['path']}, which has no banked code")
            return pages[0]
        if sym in syn:
            return syn[sym]
        for o in [obj] + objs:
            for s in o["sections"]:
                if sym in s.exports:
                    return s.addr + s.exports[sym]
        raise LinkError(f"Undefined symbol: {sym} ({obj['path']})")

    def loc(sym, sec):
        for s in [sec] + sec.obj["sections"]:
            if sym in s.locals:
                return s.addr + s.locals[sym]
        raise LinkError(f"Undefined local symbol: {sym} ({sec.obj['path']})")

    def oper(op, st):
        if op >= 12:
            v = st.pop()
            st.append({12: -v, 13: ~v, 14: ~v & 0xFF}[op] & 0xFFFF)
            return
        r, l_ = st.pop(), st.pop()
        if op in (4, 5, 6) and r == 0:
            raise LinkError("Division by zero in a relocation")
        v = {1: l_ + r, 2: l_ - r, 3: l_ * r, 4: l_ // (r or 1), 5: l_ % (r or 1),
             6: l_ // (r or 1), 7: l_ & r, 8: l_ | r, 9: l_ ^ r,
             10: int(bool(l_) and bool(r)), 11: int(bool(l_) or bool(r))}.get(op)
        if v is None:
            raise LinkError(f"Bad expression operator {op}")
        st.append(v & 0xFFFF)

    image = {}
    banks = {}
    for s in [s for o in objs for s in o["sections"]]:
        if s.bss or s.addr is None:
            continue
        code = bytearray(s.code)
        for off, size, terms in s.relocs:
            st = []
            for kind, v in terms:
                if kind == "int":
                    st.append(v)
                elif kind == "imp":
                    st.append(ext(v, s.obj))
                elif kind == "loc":
                    st.append(loc(v, s))
                else:
                    oper(v, st)
            v = st[-1] & 0xFFFF
            if size == 1:
                code[off] = v & 0xFF
            else:
                code[off:off + 2] = bytes((v >> 8, v & 0xFF))
        if s.page is None:
            for i, x in enumerate(code):
                image[s.addr + i] = x
        else:
            page = banks.setdefault(s.page, {})
            for i, x in enumerate(code):
                page[s.addr - WINDOW + i] = x
    entry = LOAD
    for o in objs:
        for s in o["sections"]:
            if "__start" in s.exports:
                entry = s.addr + s.exports["__start"]
                break
        else:
            continue
        break
    if image:
        lo, hi = min(image), max(image)
        data = bytes(image.get(a, 0) for a in range(lo, hi + 1))
    else:
        lo, data = LOAD, b""
    tail = b""
    if banks:
        tail = b"B9" + bytes([len(banks)])
        for p in sorted(banks):
            n = max(banks[p]) + 1
            tail += bytes([p]) + struct.pack(">H", n)
            tail += bytes(banks[p].get(a, 0) for a in range(n))
    return lo, data, entry, tail, order, nbank


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        sys.exit(__doc__)
    try:
        lo, data, entry, tail, order, nbank = link(args[1:])
    except LinkError as e:
        sys.exit(str(e))
    name = os.path.basename(args[0]).upper()
    open(args[0], "wb").write(mkprg.make(name, "PYLINK", None, lo, entry, data) + tail)
    if "--map" in sys.argv:
        for s in order:
            print(f"${s.addr:04X} {s.size:5} {s.name:10} {s.obj['path']}")
        print(f"{nbank} bank(s)")


if __name__ == "__main__":
    main()
