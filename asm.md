# ASM — a 6809/6309 macro assembler for MINI09

ASM runs as a MINI09 program (`ASM`), reads assembler source from
the USB flash drive and writes a `.PRG` program file. The target is that it
assembles everything in this folder that lwasm builds into a `.PRG`,
byte for byte the same as lwasm, and in the end assembles itself.

Status: **6309, sections and LINK done**. ASM 0.4 also assembles every
6309 instruction, and a source with `section`, `export` or `import` gives
an lwasm-format object file (`.O`) instead of a `.PRG`. LINK.PRG, a new
program, links `.O` files into a `.PRG` under MINI09. All of it is checked
byte for byte against lwasm 4.24 and lwlink in emu6809 (`make test-asm`,
`make test-obj`). Step 3 gave a listing file, up to 20 errors per run, and
the file name on the command line. basic.asm, 194K of source, takes 14 s at
the board's 3.69 MHz.

| Step | What | Done when |
|---|---|---|
| 1 | This spec, the skeleton, the test harness | done |
| 2 | Two-pass assembler: every 6809 instruction and addressing mode, expressions, directives, include, macros, conditionals | done |
| 3 | Optional listing, more than one error per run, the file name on the command line | done |
| 4 | Self-hosting | done in emu6809; still to try on the board |
| 5 | 6309 instructions | done |
| 6 | Sections, export/import, `.O` object output, LINK.PRG | done |

Not planned: os.asm (it needs S-record/ROM output).

## Using it

```
OS09> ASM HELLO.ASM
MINI09 ASM 0.4
103 lines, 80 bytes: HELLO.PRG
OS09> ASM HELLO.ASM -L
```

It writes `HELLO.PRG` beside the source (the extension replaced by
`.PRG`), and with `-L` (or `/L`) a listing, `HELLO.LST`. Started with no
file name, ASM asks for one (`Source file:`), and an empty answer quits.

**Arguments.** The shell copies the rest of the command line, after the
program's name, to `ARGS` (`$0E00`, in syscalls.inc) behind the mark
`ARGMARK` (`$A55A`), up to `ARGMAX` (62) characters. ASM takes them and
clears the mark. Another program can do the same. (The shell reads the
program header into its line buffer, so the arguments have to be saved before the load.)

**Listing.** One line for each source line, includes and macro
expansions too: the address (of the first byte, or the value of an
`equ`), the first 5 bytes in hex, then the line as written:

```
1000 8601        start:      lda     #1
*** Undefined symbol
1002 BE0000                  ldx     nowhere
1005 0102030405              fcb     1,2,3,4,5,6,7
```

A line in error has `*** message` above it. The listing of asm.asm is
160K; the drive must have room for it.

## Source language

The subset of lwasm that the MINI09 sources use. The survey of os.asm,
edit.asm, basic.asm, vdpdemo.asm, hello.asm and the `.inc` files found
nothing outside it.

**Lines.** `label  opcode  operand  comment`. A label starts in column 1
and may end with `:`. A line starting with `;` or `*` is a comment, and
so is anything after the operand. Opcodes and register names are not
case sensitive; symbols are (lwasm's default). Lines end in LF or CR LF
(EDIT writes CR LF).

**Symbols.** Letters, digits, `_`, `.`, `$`, `@`, `?` and no leading
digit, as long as lwasm allows. The longest in basic.asm is 12
characters; ASM keeps 31.

**Expressions.** Numbers in decimal, `$hex`, `%binary`, `@octal` and
`'c` (one character). `*` is the address of the line. Operators `+ - * /
& |` with lwasm's precedence (`*` `/` before `+` `-` before `&` `|`),
unary `-`, and parentheses. 16-bit arithmetic.

**Directives.**

| Directive | Meaning |
|---|---|
| `equ` | define the label |
| `org` | set the address |
| `fcb`, `fdb` | bytes, words (lists of expressions) |
| `fcc` | string between any delimiter, e.g. `"..."` or `/.../` |
| `fcn` | `fcc` plus a NUL |
| `fcs` | `fcc` with bit 7 set on the last character |
| `rmb` | reserve bytes (not written, see Output) |
| `end [expr]` | end of source, optional entry address |
| `include "file"` | relative to the source's directory |
| `macro` / `endm` | arguments `\1`..`\9`, split at commas |
| `ifdef`, `ifndef`, `else`, `endc` | nest; a symbol counts if it is defined above the line |

**Instructions.** The whole 6809 set, with lwasm's choice of size:

* Direct or extended: direct when the address is known on pass 1 and its
  high byte is 0 (DP is assumed 0); extended otherwise, which includes
  every forward reference. `<` forces direct, `>` extended.
* Indexed offsets: 0 gives `,R`; then 5-bit, 8-bit, 16-bit by value when
  known on pass 1, 16-bit for forward references. `,pcr` the same way
  (8-bit only when the target is behind and close).
* Branches are never lengthened: `bra` out of range is an error, as in
  lwasm.

Checked against lwasm 4.24 (`lda fwd` → `B6 0030` when `fwd equ $30`
comes later; `lda bck` → `96 20` when it came before).

### 6309

ASM takes every 6309 instruction lwasm 4.24 does, with no `pragma` needed
(lwasm's default too):

* Registers E, F, W, V and `0` in `tfr`/`exg` and the inter-register
  ops (`addr`, `subr`, `cmpr` ...), and Q in `ldq`/`stq`.
* `ldq #n` takes a 32-bit number; a symbol gives its 16-bit value, sign
  extended.
* `E,R`, `F,R`, `W,R` accumulator offsets; `,W`, `n,W`, `,W++`, `,--W`
  and their `[...]` forms (`n,W` is always 16-bit).
* `tfm r+,r+`, `r-,r-`, `r+,r`, `r,r+` (D, X, Y, U, S).
* `oim`/`aim`/`eim`/`tim #n,addr` (`;` works as the separator too).
* `band`, `biand`, `bor`, `bior`, `beor`, `bieor`, `ldbt`, `stbt`
  `reg,bit,bit,addr` with CC, A or B.
* `divd`, `divq`, `muld`, `sexw`, `pshsw` and the rest.

Since `w`, `e`, `f`, `v` and `md` are register names, `lda w,x` is the
6309 `W,X` mode, the same as lwasm. `asmtests/ops6309.asm` has every 6309
opcode in every mode.

## Sections and object files

A source that uses `section`, `export` or `import` anywhere is an object:
ASM writes `NAME.O` in lwasm's LWOBJ16 format instead of `NAME.PRG`.
lwlink and LINK.PRG both read it.

| Directive | Meaning |
|---|---|
| `section name[,bss]` (or `sect`) | start, or go back to, a section (up to 16) |
| `endsection` (or `endsect`) | leave it |
| `export a,b` or `a export` (or `.globl`) | make symbols visible to other objects |
| `import a,b` or `a import` (or `extern`, `external`) | use another object's symbols |

* Each section counts from 0. A section named `bss` or `.bss` (any case),
  or given `,bss`, holds only `rmb` and is not in the file.
* Code outside any section is dropped, as lwasm does; `org` inside a
  section is an error.
* Inside a section ASM never picks direct addressing by itself (the
  address isn't known yet); `<` still forces it. An address in a section
  is always 16-bit. `,pcr` to a known label in the same section can be
  8-bit; anything else is 16-bit with a relocation.
* A value that depends on a section or an import gets a relocation, 8 or
  16 bits: `+ - * / % & | ^`, unary `-` and `~` all work, the same
  expressions lwlink takes.
* `equ` of a label in a section stays in that section; `equ` of an
  import, `ldq #`, and the immediate of `oim` and friends must be
  absolute.

Errors: `Not relocatable`, `ORG inside a section`, `Too many sections`,
`Expression too complex` (a relocation longer than 128 bytes), and
`Undefined export: NAME` at the end.

## LINK

```
OS09> LINK OUT.PRG MAIN.O LIB.O
```

Without arguments it asks `Output and objects:`. The output name comes
first, then the objects. It prints the number of objects and bytes.

**Placement**, the same as lwlink with `tools/mini09.ld`: from $1000,
every `init` section in file order, then every `code` section, then the
other sections that aren't bss (the first object's first, each name
gathering every object's sections of that name), then the bss ones.

* `s_NAME` and `l_NAME` are the start address and total length of the
  sections called NAME.
* An import is looked for in those, then in the same object's exports,
  then in every object's exports in order. A section-local name is found
  in the same object.
* The entry is `__start` when some object exports it, else $1000.
* bss sections aren't in the file; the `.PRG` ends at the last byte with
  data, like ASM's own `rmb` rule. The creator is `MINI09LK`.

**Banked code** (LINK 0.2; `cc/cc.md`, "Banked code", has the whole
design). Each object's section `banked` goes into a 16K RAM page to run
at $8000-$BFFF, not into the program at $1000. They are packed first fit
into pages 7, 8, ... in the order the objects are given, up to 16 pages,
and LINK says `, N banks`.

* In an object with a `banked` section, the import `__bank` is its page
  (a byte: `fcb __bank`). `__nbank` is the number of pages, for CRT0B.
* The pages follow the program's normal part in the `.PRG`, after the
  size its header gives: `"B9"`, the count, then for each page its
  number, a 2-byte length and the bytes. The shell loads only the normal part;
  CRT0B (C's startup for banked code) loads the rest.
* The normal part must end below $8000 when there are banks.
* `tools/pylink.py` is the same linker in Python, for the PC: lwlink
  can't place banks. It gives the same bytes as LINK and as lwlink.

**Memory.** LINK is about 3.6K at $1000. Pages 3-6 hold the 64K image; the
objects are read whole into pages 7-31 (400K), each starting on a 512-byte
boundary.

**Errors**: `Undefined symbol: NAME (FILE)` for each one (no `.PRG` is
written then), `Not an object file: FILE`, `Too many files`,
`Too many sections`, `Bad expression in an object`, `Out of memory for
the objects`, and the file errors. With banks: `Bank too big: FILE`
(one object's banked code is over 16K), `Too many banks`, and `Program
too big for banked code`.

**Speed.** In emu6809, linking asm.asm built in sections (16K) takes
3-6 s; ASM takes 10-20 s to write its `.O`.

## Memory

| Address | Use |
|---|---|
| `$1000-$5193` | ASM: 11.5K of code and tables, then buffers and its own stack |
| `$8000-$BFFF` | banked window, switched with `SYS_BANK` |
| page 2 | the task's default page, given back on exit |
| pages 3-6 | output image: the 64K address space, 16K per page |
| pages 7-8 | symbols and macro bodies, 32K |
| pages 9-31 | source cache, 368K; an object's relocations from page 31 down |

**Source cache.** The flash drive has one file open at a time, for every
task, and no seek. So each file is read whole into the cache the first
time it is needed and closed again; pass 2 and every later `include` of
it read from memory. A file starts on a 512-byte boundary, so the 512-byte
reads never cross `$BFFF`, and ends with a NUL. basic.asm (194K) takes 12
pages.

**Symbols.** 256 hash chains, the heads in low memory and the entries
in pages 7-8: next (page and address), value, flags, the line that
defined it, and the name. About 16 bytes each, so basic.asm's 1387 take
22K of the 32K. Macro bodies go in the same pages.

**Sizes on pass 1.** A symbol is "known" on pass 1 if it was defined
above the line. Pass 2 uses the line number each symbol was defined at
to make the same choice, so both passes agree on every instruction's
size, and that is lwasm's choice too.

**Output.** Pass 2 puts each byte in the output image at its address and
keeps the lowest and highest address written. `rmb` writes nothing, so a
trailing `rmb` area isn't in the file, the same as lwasm's S-records. At
the end ASM writes the `.PRG`: the header, then the image from the lowest
to the highest address, with gaps as 0 (the same as `tools/mkprg.py`).
The creator is `MINI09AS` and the date unknown.

**Other tasks.** MINI09 doesn't allocate pages, so a task that is
running at the same time and uses pages 3-31 would be overwritten.

## Errors

`FILE:LINE: message`, and the line. For a macro, the line is the
expanded one and LINE is where the macro was used.

ASM reports an error and goes on with the next line, up to 20 errors
(`Too many errors`), then says `N error(s), no program file written`
and writes no `.PRG` (a listing, if asked for, is still written).

* Pass 1 reports only duplicate symbols (the first value stays). Every
  other error is reported on pass 2, once.
* An undefined symbol counts as 0 and a branch out of range keeps its 2
  or 4 bytes, so the addresses after it don't move. Other errors drop the
  line on both passes.
* A phase error (a label with a different address on pass 2) is only
  reported when there was no error before it, since a dropped line moves
  everything after it.
* Running out of memory, nesting deeper than 8, too many files, a
  missing `endm` or `endc`, and file errors stop ASM at once.

## Testing

`tools/asmtest.py` assembles each file with lwasm (`--format=srec`, then
the bytes mkprg.py would put in a `.PRG`) and with ASM.PRG in emu6809 on
a scratch flash drive holding ASM.PRG and every `.asm` and `.inc` beside
the source (`ASM FILE.ASM`, so it needs the os.s19 that passes
arguments). It compares the size, load and entry addresses and every
byte, and prints the first difference. The name, creator and date may
differ.

```sh
make test-asm         # ASM against lwasm: hello, vdpdemo, basic, cpu6309, asm, link, allops, ops6309
make test-obj         # objects: ASM's .O vs lwasm's, linked by lwlink and by LINK.PRG
python3 tools/asmtest.py --keep file.asm    # one file, with the emulator's output
```

`tools/objtest.py` assembles a group of sources (`a.asm+b.asm`) with
`lwasm --format=obj` and links them with `lwlink -s tools/mini09.ld` for
the reference. Then ASM in emu6809 writes the `.O` files, lwlink links
those too, and LINK.PRG links both ASM's and lwasm's `.O` files; every
result must be the same `.PRG` bytes. `--section` turns `org $1000` into
`section code`, which is how whole programs (asm.asm, basic.asm ...) are
tested as objects. It needs lwlink on PATH, built from lwtools 4.24.
