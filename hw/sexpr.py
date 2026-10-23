"""Minimal S-expression reader/writer for KiCad files."""
import re


class Str(str):
    """A quoted string token (as opposed to a bare atom)."""


TOKEN = re.compile(r'\s*(?:(\()|(\))|"((?:[^"\\]|\\.)*)"|([^\s()"]+))', re.S)


def parse(text):
    stack, cur = [], []
    pos = 0
    while True:
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos:
            break
        pos = m.end()
        if m.group(1):
            stack.append(cur)
            cur = []
        elif m.group(2):
            done = cur
            cur = stack.pop()
            cur.append(done)
        elif m.group(3) is not None:
            cur.append(Str(re.sub(r'\\(.)', r'\1', m.group(3))))
        else:
            cur.append(m.group(4))
    return cur[0] if len(cur) == 1 else cur


def q(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def dump(node, indent=0):
    if not isinstance(node, list):
        if isinstance(node, Str):
            return q(node)
        if isinstance(node, float):
            return f"{node:.4f}".rstrip("0").rstrip(".")
        return str(node)
    simple = all(not isinstance(x, list) for x in node)
    if simple:
        return "(" + " ".join(dump(x) for x in node) + ")"
    pad = "\t" * (indent + 1)
    head = " ".join(dump(x) for x in node if not isinstance(x, list))
    parts = []
    for x in node:
        if isinstance(x, list):
            parts.append("\n" + pad + dump(x, indent + 1))
    return "(" + head + "".join(parts) + "\n" + "\t" * indent + ")"


def find(node, key):
    """All direct children lists whose head is key."""
    return [x for x in node if isinstance(x, list) and x and x[0] == key]


def get(node, key):
    r = find(node, key)
    return r[0] if r else None
