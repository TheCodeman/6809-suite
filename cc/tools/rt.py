"""
Build and run MINI09 C-runtime programs on the PC: lwasm and lwlink make a
.PRG from assembler sources with CRT0.O first and LIBC.O last, and emu6809
runs it from a scratch flash drive with RUN.  Shared by the test scripts.
"""
import os
import shutil
import subprocess
import sys
import tempfile

CC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(CC)                  # 6809-os
LIB = os.path.join(CC, "lib")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import mkprg  # noqa: E402

LWASM = shutil.which("lwasm") or "lwasm"
LWLINK = shutil.which("lwlink") or "lwlink"
SCRIPT = os.path.join(ROOT, "tools", "mini09.ld")


def asm(src, obj):
    r = subprocess.run([LWASM, "--format=obj", "-I", LIB, "-I", ROOT, "-o", obj, src],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"lwasm {src}:\n{r.stdout}{r.stderr}")


def build(srcs, prg, tmp):
    """Assemble srcs, link them between CRT0 and LIBC into prg."""
    objs = []
    for src in [os.path.join(LIB, "crt0.asm")] + srcs + [os.path.join(LIB, "libc.asm")]:
        obj = os.path.join(tmp, os.path.splitext(os.path.basename(src))[0] + ".o")
        asm(src, obj)
        objs.append(obj)
    s19 = os.path.join(tmp, "out.s19")
    r = subprocess.run([LWLINK, "--format=srec", "-s", SCRIPT, "-o", s19] + objs,
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"lwlink:\n{r.stdout}{r.stderr}")
    load, data, entry = mkprg.read_srec(s19)
    entry = entry or load                   # CRT0's __start is first, at load
    name = os.path.basename(prg).upper()
    open(prg, "wb").write(mkprg.make(name, "LWLINK", None, load, entry, data))
    return load + len(data)


def run(drive, line, secs=60):
    """Type line at the MINI09 shell with drive as the flash drive -> what
    the program printed (the console output after the RUN line)."""
    r = subprocess.run([os.path.join(ROOT, "emu6809"), "-v", "-k", "-d", drive,
                        "-f", "-t", str(secs), os.path.join(ROOT, "os.s19")],
                       input=line + "\n", capture_output=True, text=True,
                       errors="replace")
    out = r.stdout.replace("\r\n", "\n").replace("\r", "\n")
    i = out.find(line)
    out = out[i + len(line):] if i >= 0 else out
    j = out.rfind("OS09>")                  # the prompt after the program
    out = out[:j] if j >= 0 else out
    lines = out.strip("\n").split("\n")
    if lines and lines[0].startswith("Loaded, entry"):
        lines = lines[1:]
    return "\n".join(lines)


def scratch():
    return tempfile.TemporaryDirectory()
