#!/usr/bin/env python3
"""
Test MC.PRG in the emulator: make a scratch drive, type keys at MC, and
check the screen it leaves, as an 80x30 VT100 terminal would show it.

    mctest.py [--show]

Each case starts the emulator afresh, runs MC, types its keys and
renders everything MC printed.  --show prints every final screen, with
the reverse-video cells in a second copy of the screen (as #).

The renderer knows only what MC sends: ESC [ r ; c H, ESC [ 2 J,
ESC [ K, ESC [ 0 m, ESC [ 7 m, CR and LF.
"""
import os
import re
import shutil
import subprocess
import sys

ROWS, COLS = 30, 80
DRIVE = "build-drive"
ENTER = "\n"                                    # the emulator turns LF into CR
UP, DOWN, PGDN, END, HOME = "\033[A", "\033[B", "\033[6~", "\033[F", "\033[H"
F1, F5, F6, F8, F10 = "\033OP", "\033[15~", "\033[17~", "\033[19~", "\033[21~"
INS = "\033[2~"
# Root entries, in MC's order: ALPHA DEMOS MANY a-very-long... BIG.DAT
# HELLO.PRG MC.PRG README.TXT.  The keys to reach the one at index n:
def at(n):
    return DOWN * n


def data(path):
    return open(f"{DRIVE}/{path}", "rb").read()


def exists(path):
    return os.path.exists(f"{DRIVE}/{path}")


def bigfile():
    """A 1,000,000-byte file: three bufferfuls for MC's copy."""
    open(f"{DRIVE}/DEMOS/SUB/HUGE.BIN", "wb").write(bytes((i * 7 + i // 512) & 255 for i in range(1000000)))



def render(out):
    """The screen after the bytes out -> (text rows, reverse rows)."""
    scr = [[" "] * COLS for _ in range(ROWS)]
    rev = [[" "] * COLS for _ in range(ROWS)]
    r = c = 0
    inv = False
    i = 0
    while i < len(out):
        ch = out[i]
        if ch == "\033":
            m = re.match(r"\033\[([0-9;]*)([A-Za-z])", out[i:])
            if not m:
                i += 1
                continue
            args, cmd = m.group(1), m.group(2)
            i += m.end()
            nums = [int(a) if a else 0 for a in args.split(";")] if args else []
            if cmd == "H":
                r = (nums[0] if nums else 1) - 1
                c = (nums[1] if len(nums) > 1 else 1) - 1
            elif cmd == "J" and nums == [2]:
                scr = [[" "] * COLS for _ in range(ROWS)]
                rev = [[" "] * COLS for _ in range(ROWS)]
            elif cmd == "K":
                for x in range(c, COLS):
                    scr[r][x] = " "
                    rev[r][x] = " "
            elif cmd == "m":
                inv = 7 in nums
            continue
        i += 1
        if ch == "\r":
            c = 0
        elif ch == "\n":
            r = min(r + 1, ROWS - 1)
        elif " " <= ch <= "~" and r < ROWS and c < COLS:
            scr[r][c] = ch
            rev[r][c] = "#" if inv else " "
            c += 1
    return ["".join(x).rstrip() for x in scr], ["".join(x).rstrip() for x in rev]


def make_drive():
    shutil.rmtree(DRIVE, ignore_errors=True)
    os.makedirs(f"{DRIVE}/DEMOS/SUB")
    os.makedirs(f"{DRIVE}/MANY")
    os.makedirs(f"{DRIVE}/ALPHA")
    shutil.copy("mc.prg", f"{DRIVE}/MC.PRG")
    shutil.copy("hello.prg", f"{DRIVE}/HELLO.PRG")
    shutil.copy("vdpdemo.prg", f"{DRIVE}/DEMOS/VDPDEMO.PRG")
    open(f"{DRIVE}/README.TXT", "w").write("hello\r\n")
    open(f"{DRIVE}/DEMOS/SUB/DEEP.TXT", "w").write("x" * 1234)
    open(f"{DRIVE}/a-very-long-file-name-that-does-not-fit.txt", "w").write("y")
    with open(f"{DRIVE}/BIG.DAT", "wb") as f:      # sparse: 1.5 GB
        f.truncate(1536 * 1024 * 1024)
    for n in range(40):
        open(f"{DRIVE}/MANY/F{n:02d}.TXT", "w").write("z" * n)


def run(keys, cmd="MC", setup=None, emu=(), secs=4):
    make_drive()
    if setup:
        setup()
    p = subprocess.run(["./emu6809", "-v", "-k", "-d", DRIVE, *emu, "-f", "-t", str(secs), "os.s19"],
                       input=(cmd + "\n" + keys).encode(), capture_output=True, timeout=120)
    out = p.stdout.decode("latin-1")
    k = out.rfind("\033[2J")                       # MC's last full redraw
    return render(out[k:] if k >= 0 else out)


CASES = [
    # name, command, keys, [(row, text that row must contain)],
    # where the cursor bar is: ("L" or "R", row), or None for no panels
    ("start", "MC", "", [
        (1, "+- / ---"),
        (2, "|/ALPHA"),
        (3, "|/DEMOS"), (4, "|/MANY"),
        (5, "|a-very-long-file-name-that-~|"),
        (6, "|BIG.DAT"), (6, "1572864K|"),
        (7, "|HELLO.PRG"), (7, "116|"), (8, "|MC.PRG"),
        (9, "|README.TXT"), (9, "7|"),
        (28, "+- 8 entries ---"),
        (29, " ALPHA"),
        (30, "1Help"), (30, "10Quit"),
    ], ("L", 2)),
    ("down, into DEMOS", "MC", DOWN + ENTER, [
        (1, "+- /DEMOS ---"), (2, "|/..                         |     <UP>|"),
        (3, "|/SUB"), (4, "|VDPDEMO.PRG"), (28, "+- 2 entries ---"),
    ], ("L", 2)),
    ("into DEMOS/SUB and back up", "MC", DOWN + ENTER + DOWN + ENTER + ENTER, [
        (1, "+- /DEMOS ---"), (29, " SUB"),
    ], ("L", 3)),
    ("up from DEMOS to the root", "MC", DOWN + ENTER + ENTER, [
        (1, "+- / ---"), (2, "|/ALPHA"), (29, " DEMOS"),
    ], ("L", 3)),
    ("into MANY, scroll to the end", "MC", DOWN + DOWN + ENTER + END, [
        (1, "+- /MANY ---"), (27, "|F39.TXT"), (27, "39|"), (28, "+- 40 entries"),
    ], ("L", 27)),
    ("page down", "MC", DOWN + DOWN + ENTER + PGDN, [
        (2, "|/.."), (27, "|F24.TXT"), (29, " F24.TXT  24 bytes"),
    ], ("L", 27)),
    ("end, then home", "MC", DOWN + DOWN + ENTER + END + HOME, [
        (2, "|/.."), (3, "|F00.TXT"),
    ], ("L", 2)),
    ("up at the top stays", "MC", UP + UP, [(29, " ALPHA")], ("L", 2)),
    ("Tab: the right panel", "MC", "\t" + DOWN + DOWN + DOWN + DOWN, [
        (1, "+- / ---"), (6, "|BIG.DAT"), (29, " BIG.DAT  1610612736 bytes"),
    ], ("R", 6)),
    ("Tab and back", "MC", "\t" + DOWN + "\t", [(29, " ALPHA")], ("L", 2)),
    ("MC with a folder", "MC DEMOS/SUB", "", [
        (1, "+- /DEMOS/SUB ---"), (3, "|DEEP.TXT"), (3, "1234|"),
    ], ("L", 2)),
    ("MC with a missing folder", "MC NOPE", "", [
        (1, "+- / ---"), (29, "Folder not found"),
    ], ("L", 2)),
    ("Enter on a file", "MC", DOWN * 6 + ENTER, [(29, "files come in a later")], ("L", 8)),
    ("F1 help", "MC", F1, [(29, "Tab panel")], ("L", 2)),
    ("F3 not yet", "MC", "\033OR", [(29, "Not in this version")], ("L", 2)),
    ("ESC 3 is F3", "MC", "\0333", [(29, "Not in this version")], ("L", 2)),
    ("F10 quits", "MC", F10 + "PS\n", [(1, "PS")], None),
    ("ESC 0 quits", "MC", "\0330" + "PS\n", [(1, "PS")], None),

    # Marking, copy, move, delete.  The 6th item has more: a check of the
    # drive afterwards, files to add first, emulator options, seconds.
    ("Insert marks and moves down", "MC", at(4) + INS + INS, [
        (6, "|*BIG.DAT"), (7, "|*HELLO.PRG"), (29, " 2 marked |"),
    ], ("L", 8)),
    ("Insert again unmarks", "MC", at(4) + INS + UP + INS, [
        (6, "|BIG.DAT"), (29, " HELLO.PRG"),
    ], ("L", 7)),
    ("Insert on .. does nothing", "MC", at(1) + ENTER + INS, [(2, "|/.."), (29, " SUB")], ("L", 3)),
    ("F8 deletes a file", "MC", at(7) + F8 + "y", [
        (28, "+- 7 entries"), (8, "|MC.PRG"), (9, "|      "),
    ], ("L", 8), {"check": lambda: not exists("README.TXT")}),
    ("F8, then N keeps it", "MC", at(7) + F8 + "n", [(9, "|README.TXT")], ("L", 9),
     {"check": lambda: exists("README.TXT")}),
    ("F8 asks first", "MC", at(7) + F8, [(29, "Delete README.TXT? (Y/N)")], ("L", 9)),
    ("F8 on an empty folder", "MC", F8 + "y", [(2, "|/DEMOS")], ("L", 2),
     {"check": lambda: not exists("ALPHA")}),
    ("F8 on a folder with files", "MC", at(1) + F8 + "y", [(29, " DEMOS: Folder not empty")], ("L", 3),
     {"check": lambda: exists("DEMOS/VDPDEMO.PRG")}),
    ("F8 on marked files", "MC", at(4) + INS + INS + DOWN + INS + F8, [
        (29, "Delete 3 entries? (Y/N)"),
    ], ("L", 9)),
    ("F8 deletes the marked files", "MC", at(4) + INS + INS + DOWN + INS + F8 + "y", [
        (28, "+- 5 entries"), (6, "|MC.PRG"),
    ], ("L", 6), {"check": lambda: not exists("BIG.DAT") and not exists("HELLO.PRG")
                  and not exists("README.TXT") and exists("MC.PRG")}),
    ("F5 copies a file to the other panel", "MC",
     "\t" + at(1) + ENTER + "\t" + at(5) + F5 + "y", [
         (1, "/DEMOS"), (4, "||HELLO.PRG"),
     ], ("L", 7), {"check": lambda: data("DEMOS/HELLO.PRG") == data("HELLO.PRG")}),
    ("F5 asks where to", "MC", "\t" + at(1) + ENTER + "\t" + at(5) + F5, [
        (29, "Copy HELLO.PRG to /DEMOS? (Y/N)"),
    ], ("L", 7)),
    ("F5 a big file (3 bufferfuls)", "MC",
     at(1) + ENTER + at(1) + ENTER + "\t" + at(1) + ENTER + "\t" + at(2) + F5 + "y", [
         (29, " HUGE.BIN"),
     ], None, {"setup": bigfile, "secs": 60,
               "check": lambda: data("DEMOS/HUGE.BIN") == data("DEMOS/SUB/HUGE.BIN")}),
    ("F5 a big file, old firmware", "MC",
     at(1) + ENTER + at(1) + ENTER + "\t" + at(1) + ENTER + "\t" + at(2) + F5 + "y", [
         (29, "HUGE.BIN: Over 432K: needs pico6809 firmware"),
     ], None, {"setup": bigfile, "secs": 30, "emu": ["-o"],
               "check": lambda: not exists("DEMOS/HUGE.BIN")}),
    ("F5 over a file asks", "MC", at(1) + ENTER + at(2) + "\t" + at(1) + ENTER + at(1) + ENTER + "\t" + F5 + "y", [
        (29, "Overwrite VDPDEMO.PRG? (Y/N, A = all)"),
    ], ("L", 4), {"setup": lambda: open(f"{DRIVE}/DEMOS/SUB/VDPDEMO.PRG", "w").write("old")}),
    ("F5 over a file, N keeps it", "MC", at(1) + ENTER + at(2) + "\t" + at(1) + ENTER + at(1) + ENTER + "\t" + F5 + "yn", [
        (29, " VDPDEMO.PRG"),
    ], ("L", 4), {"setup": lambda: open(f"{DRIVE}/DEMOS/SUB/VDPDEMO.PRG", "w").write("old"),
                  "check": lambda: data("DEMOS/SUB/VDPDEMO.PRG") == b"old"}),
    ("F5 over a file, Y replaces it", "MC", at(1) + ENTER + at(2) + "\t" + at(1) + ENTER + at(1) + ENTER + "\t" + F5 + "yy", [
    ], ("L", 4), {"setup": lambda: open(f"{DRIVE}/DEMOS/SUB/VDPDEMO.PRG", "w").write("old"),
                  "check": lambda: data("DEMOS/SUB/VDPDEMO.PRG") == data("DEMOS/VDPDEMO.PRG")}),
    ("F5 skips folders", "MC", "\t" + at(1) + ENTER + "\t" + INS + DOWN * 4 + INS + F5 + "y", [
        (29, "Folders skipped"),
    ], ("L", 8), {"check": lambda: exists("DEMOS/HELLO.PRG") and not exists("DEMOS/ALPHA")}),
    ("ESC cancels a copy", "MC",
     at(1) + ENTER + at(1) + ENTER + "\t" + at(1) + ENTER + "\t" + at(2) + F5 + "y" + "\033", [
         (29, "HUGE.BIN: Cancelled"),
     ], None, {"setup": bigfile, "secs": 30, "check": lambda: not exists("DEMOS/HUGE.BIN")}),
    ("F5 to the same folder", "MC", F5, [(29, "Both panels show the same folder")], ("L", 2)),
    ("F6 moves the marked files", "MC",
     "\t" + at(2) + ENTER + "\t" + at(5) + INS + DOWN + INS + F6 + "y", [
         (28, "+- 6 entries"), (28, "+- 42 entries"),
     ], ("L", 7), {"check": lambda: not exists("HELLO.PRG") and not exists("README.TXT")
                   and data("MANY/README.TXT") == b"hello\r\n" and exists("MANY/HELLO.PRG")}),
]


def main():
    show = "--show" in sys.argv
    bad = 0
    for name, cmd, keys, want, bar, *more in CASES:
        opt = more[0] if more else {}
        scr, rev = run(keys, cmd, opt.get("setup"), opt.get("emu", ()), opt.get("secs", 4))
        errs = []
        if "check" in opt and not opt["check"]():
            errs.append("the drive isn't as it should be afterwards")
        for row, text in want:
            if text not in scr[row - 1]:
                errs.append(f"row {row} has no {text!r}: {scr[row - 1]!r}")
        if bar:                                    # the cursor bar, and no other
            for side, x in (("L", 1), ("R", 41)):
                for row in range(2, 28):
                    on = bool(rev[row - 1][x:x + 38].strip())
                    if on != (bar == (side, row)):
                        errs.append(f"{side} row {row}: reverse is {on}")
        print(("ok   " if not errs else "FAIL ") + name)
        for e in errs:
            print("     " + e)
        bad += bool(errs)
        if show or errs:
            print("\n".join(f"{i + 1:2} {l}" for i, l in enumerate(scr)))
            print("\n".join(f"{i + 1:2} {l}" for i, l in enumerate(rev) if l.strip()))
    shutil.rmtree(DRIVE, ignore_errors=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
