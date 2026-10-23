# CC — a C compiler for MINI09

CC is a compiler for a subset of C that runs on MINI09 as four
programs, one after the other (CPP, PARSE, SEMA, GEN), and writes 6809
assembler source for ASM. ASM turns that into an object, and LINK joins
it with the C runtime into a `.PRG`. Every pass gives the same bytes on
the PC and on MINI09.

Status: **self-hosting in emu6809 (step 4)**. The four passes, compiled
by cc09 and built into `.PRG`s, run in emu6809 on the tests, CLIB and
their own sources. Every file they write is byte for byte the same as
cc09's. ASM.PRG and LINK.PRG then build the passes from those `.ASM`
files into the same `.PRG`s as lwasm and lwlink. That needs the LINK fix
under "Known problems". What's left of step 4 is the same run on the
board.

| Step | What | Done when |
|---|---|---|
| 1 | This spec | agreed |
| 2 | Runtime: `CRT0.O`, `LIBC.O` (startup, arithmetic helpers, stdio over the syscalls), with tests in emu6809 | done |
| 3 | CC written in the subset, built with gcc on the PC; test suite of C programs run in emu6809 | the suite passes |
| 4 | Self-hosting: the passes built by the PC compiler, then by themselves | the passes compile themselves to the same files as cc09, in emu6809 (done), then on the board |
| 5 (later) | `-6309`: MULD/DIVD and the other 6309 instructions | |

## Using it

```
OS09> CC HELLO.C
OS09> HELLO
```

CC.PRG runs every step: CPP, PARSE, SEMA, GEN and ASM for each `.C`
file, then LINK, which makes `HELLO.PRG` (named after the first file)
from `CRT0.O`, the objects, `CLIB.O` and `LIBC.O`. It shows each step as
the `RUN` line it stands for, stops at the first step that writes
nothing (that step has already printed its errors), and deletes the files
in between.

```
CC FILE.C [MORE.C|LIB.O ...] [-S] [-C] [-K] [-N] [-B] [-I DIR/]
```

| Option | Does |
|---|---|
| `-S` | stop at `FILE.ASM` |
| `-C` | stop at `FILE.O`, no LINK |
| `-K` | keep `.I .A .N .T`, `.ASM` and `.O` |
| `-N` | no `CLIB.O` (`printf`, `malloc` ...), 3K less: the passes are built this way, and they don't fit with it |
| `-B` | link with `CRT0B.O`: for banked `.O` files given on the line (a `.C` file with `#pragma bank` does this by itself) |
| `-I DIR/` | CPP's folder for headers |

The programs and `CRT0.O`, `CLIB.O`, `LIBC.O` are looked for at the top
of the drive. A `.O` file on the line goes to LINK as it is. All of it
fits in ARGS (62 characters) for LINK, so a few files at most.

How CC.PRG works (`lib/ccdrv.asm`): every program loads at $1000, so it
copies itself to RAM page 2 at $8000 (the passes, ASM and LINK use
pages 3-31) and runs there. For each step it loads the program at $1000
the way RUN does, puts the arguments at `ARGS`, starts it with
`SYS_SPAWN` and waits until the task is gone from the kernel's task
table (`tcbs` at $20 in os.asm). If the table moves, `TCBS` in ccdrv.asm
must move with it.

By hand, the same steps are:

```
OS09> CPP HELLO.C
OS09> PARSE HELLO.I
OS09> SEMA HELLO.A
OS09> GEN HELLO.T
OS09> ASM HELLO.ASM
OS09> LINK HELLO.PRG CRT0.O HELLO.O CLIB.O LIBC.O
OS09> HELLO
```

Each pass writes its file beside its input, with the same name and a
new extension: `HELLO.I`, `HELLO.A` and `HELLO.N`, `HELLO.T`, then
`HELLO.ASM` (a second argument names it instead). SEMA and GEN find
`HELLO.N` beside their input, so keep the files together. A pass with
errors writes nothing and the next one says it can't open its input.
The in-between files can be deleted afterwards.

`CRT0.O` must come first so its `init` section starts at $1000;
`CLIB.O` (the library parts written in C) goes before `LIBC.O`. Headers
are looked for beside the source, then in `INCLUDE/`, or in the folder
given to CPP with `-I DIR/`.

On the PC, `cc09 [-I DIR/] [-k] FILE.C [OUT.ASM]` runs the four passes
(`cpp09`, `parse09`, `sema09`, `gen09`, the same sources built with
gcc) with the files between them in a temporary folder; `-k` keeps it.
Then `lwasm --format=obj` and `lwlink -s tools/mini09.ld`.

`make drive` fills `drive/` with what to copy to the flash drive: CC.PRG, the
four passes, ASM.PRG and LINK.PRG, `CRT0.O`, `CRT0B.O`, `LIBC.O`, `CLIB.O`,
`INCLUDE/`, the tests, and CC's own sources, so the board can compile
CC too.

## The language

C89 syntax, cut down to what a compiler written in it needs, and what
fits in the 6809's address space. The compiler source may use only this
subset.

**Types.**

| Type | Size | Notes |
|---|---|---|
| `char`, `signed char` | 1 | `char` is signed, the same as gcc on x86, so PC and board builds agree |
| `unsigned char` | 1 | |
| `int`, `short`, `signed`, `unsigned` | 2 | big-endian, as the 6809 stores D |
| `long`, `unsigned long` | 4 | big-endian; arithmetic through LIBC helpers |
| pointers | 2 | to any type, including functions |
| arrays | | any number of dimensions |
| `struct`, `union` | | member access, `&`, pointers to them, assignment (`a = b`, copied byte by byte); no struct arguments or return values (pass pointers) |
| `enum` | 2 | constants only |
| `typedef` | | |
| `void` | | return type and `void *` |

Not in the subset: `float`, `double`, bit-fields, K&R function
definitions, struct arguments and return values. `const`, `volatile` and
`register` are accepted and ignored.

**Declarations.** Globals, `static` globals and functions, `static`
locals, `extern`. Prototypes are required before a call (an undeclared
function is an error, not an implicit `int`). `...` for variable
arguments, with `va_list`, `va_start`, `va_arg`, `va_end` in `stdarg.h`.

**Initializers.** Globals and statics: constants, constant addresses
(`&x`, `"string"`, function names), and braced lists for arrays and
structs, nested. Locals: one expression for a scalar; no braced lists.

**Statements.** `if`/`else`, `while`, `do`/`while`, `for`, `switch`
(with `case`, `default`, fall-through), `break`, `continue`, `return`,
`goto` and labels, blocks with declarations at the start.

**Expressions.** Every C operator on the types above: arithmetic,
comparison, logical with short-circuit, bitwise, shifts, `++`/`--` both
ways, all compound assignments, `?:`, comma, casts, `sizeof`, address-of
and indirection, `[]`, `.`, `->`, calls through function pointers.
Constant expressions are folded. Integer promotions and the usual
arithmetic conversions follow C89 for 8, 16 and 32 bits.

**Preprocessor**, built into the lexer: `#include "file"` and
`#include <file>` (both beside the source, then `INCLUDE/` or `-I`),
`#define NAME text`, `#define NAME(a,b) text`, `#undef`, `#ifdef`,
`#ifndef`, `#if` with integer constant expressions and `defined`,
`#elif`, `#else`, `#endif`, `__LINE__`, `__FILE__`, and `__MINI09__`
(always 1). Macro calls nest (`MAX(MAX(a, b), c)`). No `#` or `##`
operators.

**Library.** A small libc, LIBC.O (assembler) and CLIB.O (C), with
headers in `include/`:

* `stdio.h`: `putchar`, `getchar`, `puts`, `fopen` ("r" or "w"),
  `fclose`, `fgetc`/`getc`, `ungetc`, `fputc`/`putc`, `fputs`, `fgets`,
  `remove`, and `printf`, `fprintf`, `sprintf` with `%d %i %u %x %X %o
  %c %s %%`, `l` for long, flags `-` and `0`, width and precision (also
  `*`); no floats.
* `string.h`: `strlen`, `strcpy`, `strcat`, `strcmp`, `strncmp`,
  `strchr`, `strrchr`, `memcpy`, `memmove`, `memset`, `memcmp`.
* `stdlib.h`: `exit`, `atoi`, `atol`, `abs`, `labs`, `malloc`, `calloc`,
  `free` (first fit, over the RAM from the end of the program to $7FFF),
  `rand`, `srand`.
* `ctype.h` (ASCII), `stdarg.h`, and `mini09.h` (`bank()` and `WINDOW`).

A constant like `65535` is a `long` (it doesn't fit an `int`), so pass
`0xFFFF` or `65535u` to `%u`. Arguments are pushed right to left, so
they are worked out last first.

## How it compiles

**Four passes.** No single program with CC's code and tables fits in
28K, so CC is split where the work divides cleanly. Each pass is one C
file plus what they share (`cc.h`, `common.c`, and `lex.c` for the first
two):

| Pass | Reads | Writes | Does |
|---|---|---|---|
| CPP (`cpp.c`) | `FILE.C` | `FILE.I` | the preprocessor: plain C, one token after another, with `#line` where the file changes or lines are skipped |
| PARSE (`parse.c`) | `FILE.I` | `FILE.A`, `FILE.N` | the grammar: a binary tree file, and every name in number order. It only needs to know which names are typedefs |
| SEMA (`sema.c`) | `FILE.A` | `FILE.T` | symbols, types, conversions, constant folding, data, frames and statements: the assembler for everything except expressions, which it leaves as trees |
| GEN (`gen.c`) | `FILE.T`, `FILE.N` | `FILE.ASM` | code for the trees; copies the rest, puts the names in, adds the helper imports |

`cc.h` describes the tree file. In `FILE.T`, lines that start with `!`
are trees (`!N op kind size left right value symbol` for each node, then
`!G n` to compute it or `!C n label jump-if-true` to branch on it), and
a global is written `@n`, its name's number, for GEN to fill in. SEMA's
labels are `L1`, `L2`, ...; GEN's are `M1`, `M2`, ....

GEN reads `FILE.T` twice. The first time it writes nothing, but works
out where every label will be, with each branch long and each
instruction at its largest. The second time, a `lbra`/`lbne`/... that
reaches its label by those numbers is written short. Sizes can only
shrink, so it still reaches. That makes code about 5% smaller.
Loading an array element, `a[i]`, is `ldx #_a` or `ldx _p`, then
`ldd d,x`.

**Registers.** D is the accumulator: every expression leaves its value
in D (B for a `char` that is about to be stored). A `long` is in X:D,
X the high word and D the low word; code that reads a `long` through a
pointer uses Y for the address. X holds addresses for
indirection. Y is scratch for compiled code. U is the frame
pointer. S is the stack. DP stays 0 and is never used by compiled code,
since the kernel's variables are there.

**Calls.** Arguments are pushed right to left, each as 2 bytes (`char`
widened) or 4 for a `long`, so `va_arg` can walk them. The caller pops
them (`leas n,s`). Results come back in D, or X:D for a `long`. A
function saves and restores U; A, B, X and Y are not preserved. (LIBC's
routines keep Y as well.)

```
_add    pshs    u           ; int add(int a, int b) { int t; ... }
        tfr     s,u
        leas    -2,s        ; locals below U
        ldd     4,u         ; a
        addd    6,u         ; b
        std     -2,u        ; t
        leas    ,u
        puls    u,pc
```

Arguments are at `4,u` up, locals at `-1,u` down. Binary operators push
the left operand (`pshs d`), work out the right one in D, then combine
with `,s++` (`addd ,s++`, `subd ,s++` then negate, ...). Simple right
operands (constants, locals, globals) skip the push: `addd -2,u`.

**Helpers** in LIBC for what the 6809 doesn't do in one instruction.
They keep Y and U.

| Helper | Does |
|---|---|
| `__mul` | D = X * D (16 bits; signed and unsigned are the same) |
| `__divs`, `__divu`, `__mods`, `__modu` | D = X / D, X % D |
| `__shl`, `__shrs`, `__shru` | D = X << D, X >> D |
| `__ladd`, `__lsub`, `__lmul`, `__land`, `__lor`, `__lxor` | X:D = left op X:D |
| `__ldivs`, `__ldivu`, `__lmods`, `__lmodu` | X:D = left / X:D, left % X:D |
| `__lshl`, `__lshrs`, `__lshru` | X:D = left << D, left >> D |
| `__lcmp`, `__lcmpu` | D = -1, 0 or 1 for left against X:D, and the flags set from it, so a signed branch can follow |
| `__lneg` | X:D = -X:D |
| `__sext` | X:D = D, sign-extended |

For the 16-bit ones the code pulls the left operand into X (`puls x`).
For the `long` ones the left operand is pushed high word first (`pshs d`
then `pshs x`, so it is big-endian on the stack) and the caller pops it
(`leas 4,s`) after the call. Division rounds towards 0 and the remainder
has the dividend's sign, as in C. 16-bit compares are done inline with
`cmpd` and a signed or unsigned branch.

**Names.** C names get a leading `_` in the assembler (`main` is
`_main`), so they can't clash with registers or ASM's opcodes. Compiler
labels are `L1`, `L2`, ... and `M1`, `M2`, ... Names longer than 31 characters (ASM's limit)
are an error. CC writes no parentheses in operands, because of the ASM
problem below.

**Sections.** Each `.ASM` has `section code` for functions, `section
data` for initialized globals, `section strings` for string literals
(apart, so one in an initializer doesn't land inside the object), and
`section bss` for the rest. Non-static globals are `export`ed; everything used but not defined
is `import`ed. LINK puts `CRT0.O`'s `init` first, then code, data and
bss, as described in asm.md.

**Startup (`CRT0.O`).** `__start` is the entry. It zeroes bss (`s_bss`,
`l_bss`), sets S to the top of a 2K stack in its own bss (the kernel's
256-byte task stack is too small for C), copies RUN's arguments from
`ARGS` and clears `ARGMARK`, splits them at spaces into `argv[1]` up
(`argv[0]` is `""`, since the program's name isn't passed), calls
`main(argc, argv)` and passes the result to `exit()`. `exit()` writes a
file that is still open for writing, then ends the task. `_heap` (C's
name for `__heap`) is set to the end of bss, where `malloc` starts.

## Files and memory on MINI09

The flash drive has one file open at a time for every task, and no seek.
CC can't keep `FILE.C` open while it writes `FILE.ASM`, or read an
`#include` in the middle. So LIBC's file layer hides it:

* `fopen(name, "r")` reads the whole file into banked RAM and closes
  it. `fgetc` and `ungetc` work from memory. Files open for reading are
  allocated like a stack: closing the newest one gives its RAM back, which
  suits nested `#include`s.
* `fopen(name, "w")` collects the output in banked RAM. `fclose` (or
  `exit`) writes it to the drive in 512-byte blocks. One file can be
  open for writing at a time.
* Reading and writing share pages 7-31 (400K). Files being read fill
  from page 7 up; the file being written fills from page 31 down, a page
  at a time. So either can be big, as long as together they fit. GEN
  holds SEMA's `.T` (225K for sema.c) while it writes its `.ASM` (118K).
* `stdin` and `stdout` are the console. `putchar` sends `'\n'` as CR LF;
  `getchar` waits for a key without echo, gives CR as `'\n'` and ^D as
  `EOF`.
* `bank(page)` maps one of pages 3-6 into $8000-$BFFF for the program's
  own use and returns the previous page. LIBC puts it back after each
  file call. A program must use `bank()` rather than `SYS_BANK`, and
  must not hand LIBC's file calls a buffer in the window.

| Address | Use |
|---|---|
| `$1000-...` | the pass's code, then data and bss |
| `...-$7FFF` | the stack, about 2K |
| page 2 | the task's default page |
| page 3 | the pass's tables (`bank(3)`); pages 4-6 are free |
| pages 7-31 | LIBC: files being read (from 7 up) and the file being written (from 31 down), 400K |

**How the passes fit.** Measured from their own builds:

| Pass | Code | Strings | Bss | Ends at | Free below $8000 | Page 3 |
|---|---|---|---|---|---|---|
| CPP | 11,301 | 1,020 | 10,774 | $7C60 | 928 | names 7,000, macro text 5,000 |
| PARSE | 10,566 | 698 | 8,078 | $6DB7 | 4,681 | names 7,000 |
| SEMA | 21,383 | 1,845 | 448 | $7EA5 | 347 | all its tables, about 15.6K of 16K |
| GEN | 16,393 | 1,938 | 5,015 | $7D8F | 625 | names, where each label is, which names are functions here (14.6K) |

The bss column includes CRT0's 2K stack. SEMA is the tight one. Its
tables are pointers into page 3, handed out by `walloc()` at the start
(on the PC the same from `malloc`, so the code is the same). The limits
in `cc.h` are set to what the passes' own sources need, with room to
spare: 800 names, 512 types, 352 globals, 96 locals in scope, 128 tree
nodes. If SEMA grows, the next steps are more of its small tables into
page 3 and smaller code from GEN.

**Other tasks.** Like ASM and LINK, CC uses pages 3-31 without asking,
so nothing else that uses them can run at the same time.

## Banked code

A program's code, data and stack normally share $1000-$7FFF (28K, less
CRT0 and LIBC). `#pragma bank` in a file puts that file's functions in
16K RAM pages that LINK packs and CRT0B switches into $8000-$BFFF when
they are called, so the code can grow to 16 pages (256K). Data,
strings, bss and the stack stay in common memory.

```
/* big.c */
#pragma bank
int work(int x) { ... }
```

```
OS09> CC MAIN.C BIG.C
OS09> MAIN
```

CC.PRG notices the pragma (GEN writes an empty `BIG.B`, which CC deletes)
and links with `CRT0B.O` in place of `CRT0.O`. Give `-B` when a banked
`.O` is on the line without its `.C`. By hand: `LINK MAIN.PRG CRT0B.O
MAIN.O BIG.O CLIB.O LIBC.O`. On the PC, cc09 says `is banked:
link it with crt0b.o`, and the link is `tools/pylink.py OUT.PRG
crt0b.o ...` (lwlink can't place banks; pylink places everything else
the way lwlink and LINK do).

**What GEN does.** In a banked file the code section is `banked`, each
function's body is labelled `B_name`, and a 6-byte stub in common code
stands for it:

```
_work       jsr     __bcall         ; CRT0B: switch in the page, call, switch back
            fcb     __bank          ; this file's page, filled in by LINK
            fdb     B_work
```

Calls from other files, from common code and through pointers go to the
stub; `&work` is the stub. Calls inside the file go straight to
`B_work`. A file's functions all go in one page, so one file's code must
fit in 16K. LINK packs the files first fit into pages from 7 up, in the
order given, and says `, N banks`.

**The .PRG.** The banks follow the normal part of the file, after the
size its header gives: `"B9"`, the count, then for each page its number,
length (2 bytes) and bytes. The shell loads only the normal part.
Before `main`, CRT0B opens the program's own file again by the path the
shell was given (the shell keeps it in `fname`, $0258, while the program runs),
skips the normal part, and copies each bank into its page. A banked
program has to be started from the shell; otherwise it stops with
`Can't load the code banks`.

**A call through a stub.** `__bcall` keeps the stack the way a normal
call has it (arguments at `4,u`), saves the caller's return address and
page on its own stack of 128 entries, writes the page into the task's
`TCB_PAGE` and the MMU (`$D802`) with IRQs masked, and jumps to the
body, which returns to `__bret` to switch back. That is about 140
cycles in and 90 out, over a plain `jsr`/`rts`. Calls inside one file
cost nothing extra. Banked calls nested more than 128 deep stop the
program with `Banked calls nested too deep`.

**Rules.**

* Data, strings and bss stay in common memory: LIBC switches the window
  during file calls, so they can't be in a bank.
* `bank()` can't be called while a banked function is running (from it
  or anything it calls): it would switch the code out from under itself.
  From common code that no banked function called, it is fine, and
  pages 3-6 are still the program's.
* Banked code takes pages from 7 up, so LIBC's file RAM (read files from
  the page after the last bank, the written file from 31 down) is 16K
  less for each page.
* A banked function's name can be 29 characters at most (`B_` and the
  name must fit ASM's 31).
* Each function gets a stub, `static` ones too: 6 bytes of common memory
  each.
* `CRT0B.O` is about 600 bytes of code and 2.9K of bss more than
  `CRT0.O` (the bank stack and a read buffer).

**Testing.** `tools/banktest.py` (`make test-bank`): `tests/bank/bt*.asm`
by hand in assembler, run as `BT.PRG` and `SUB/BT.PRG`, LINK.PRG's
bytes against pylink's; then `tests/bank/*.c` (`bmain.c` common,
`bone.c`, `btwo.c`, `big1.c`, `big2.c` banked: calls across pages and
back, recursion through two pages, pointers to banked functions,
callbacks into common code, `printf` and files from a bank, a `switch`)
built on the PC, run, and checked against `bank.out` and against the
same files built without the pragma; then the same files compiled by
CC.PRG in emu6809, which must give the same bytes. `big1.c` and `big2.c`
are filler made by `banktest.py --mkbig`: 6.9K of common memory and 2
pages, against 24.7K all in common.

## Errors

`FILE:LINE: message`, from whichever pass finds it: CPP for the
preprocessor, PARSE for syntax, SEMA for types and names. A pass goes on
after an error, up to 20, then writes nothing. A missing file, running
out of memory or a table, or nesting too deep stops it at once.

## Known problems in ASM and LINK

Found while testing the runtime. Both are fixed now (ASM by
`asm-parenfix`, LINK by the patch below); the notes stay for anyone with
an older ASM.PRG or LINK.PRG.

* **ASM: a parenthesised subexpression loses its high byte.** In
  `ex_un` (asm.asm, label `eu3`), `lda ,x+` reads the `)` into A, which
  is the high byte of the value `exprb` just returned in D. So
  `fdb 2*(16+1)` gives $5222 and `fdb -(1)` gives $D6FF; lwasm gives
  $0022 and $FFFF. A fix is to save A around the check:
  `pshs a` / `lda ,x+` / `cmpa #')` / `puls a` / `lbne err_syntax`.
  Fixed in ASM 0.4 (`asmtests/expr.asm` tests it). The runtime and CC's
  output still use no parentheses in expressions, so they assemble with
  an older ASM too.
* **LINK: `synsym` uses B as its loop counter and then overwrites it.**
  After a section name matches, `ldd tmpw` and `ldd SI_ADDR,y` replace B,
  so the loop runs on past the table for a count taken from an address.
  It gave the right `l_bss` in the earlier tests by luck, but linking
  GEN gives `s_bss` $1926 and `l_bss` $997D, so CRT0 clears the wrong
  RAM. The fix, `link-synsym.patch` beside this file, keeps B across the
  match with `pshs b` / `puls b`. `make test-self` needs it.

## Testing

* **Runtime (step 2):** `make test` in `cc/`. `tools/arithtest.py`
  calls every arithmetic helper on 1,624 operand pairs and compares with
  C's answers worked out in Python. `tools/iotest.py` runs
  `tests/rt/iotest.asm` with arguments, checks `string.h`, copies a file
  with an `#include`-like second file opened in the middle, and copies a
  40K file across banked pages byte for byte. `tools/nativetest.py`
  builds the same program with ASM.PRG and LINK.PRG in emu6809 and checks
  it has the same bytes as the lwasm and lwlink build.
* **Compiler (step 3):** `tests/cc/*.c`, each printing its results.
  For each one `tools/cctest.py` has cc09 write `.asm`, lwasm and lwlink
  build the `.PRG` with CLIB, emu6809 runs it as `NAME A B C`,
  and the output must match `NAME.out`. (The expected outputs are worked
  out by hand for 16-bit `int`, since gcc's are 32-bit.) `make test-cc`.
  `tools/ccnative.py` (`make test-ccnative`) assembles and links one of
  them, with CLIB, on MINI09 with ASM.PRG and LINK.PRG, checks the bytes
  against lwasm and lwlink, and runs it.
* **Self-hosting (step 4):** `tools/selftest.py` (`make test-self`).
  cc09 compiles the four passes into CPP.PRG, PARSE.PRG, SEMA.PRG and
  GEN.PRG. In emu6809 they compile the tests, CLIB and their own
  sources, and every `.I`, `.A`, `.N`, `.T` and `.ASM` must be the same
  bytes as cc09's (run on the same file names). Then ASM.PRG and LINK.PRG
  build the passes from those `.ASM` files, and each `.PRG` must be the
  same as lwasm and lwlink's. The whole run takes about a minute.
  Still to do: the same on the board.

## Decisions

* `char` is signed, the same as gcc on x86.
* `long` is in from the start (32 bits).
* The compiler, runtime and tests live in their own folder, `cc/`, in
  6809-os.
* Four passes on MINI09 (CPP, PARSE, SEMA, GEN), since three didn't fit,
  and cc09 stays as the PC cross compiler, running the same passes.
* Banked code is chosen per file with `#pragma bank`; the switch writes
  the MMU directly rather than calling `SYS_BANK`; CRT0B finds its own
  file from the shell's `fname`, with no change to the ROM.

## Files

| File | What it is |
|---|---|
| `cc.md` | This design |
| `cc.h` | What the passes share: limits, tokens, types, tree nodes, the tree file's format |
| `common.c` | Shared code: messages, output files, names, reading and writing numbers, assembler output |
| `lex.c` | The lexer, with the preprocessor in it for CPP (`WANT_PP`) |
| `cpp.c`, `parse.c`, `sema.c`, `gen.c` | The four passes |
| `cc09.c` | cc09: runs the four passes on the PC |
| `lib/ccdrv.asm` | CC.PRG: runs all the steps on MINI09 (built by `make drive`) |
| `link-synsym.patch` | The LINK fix (see "Known problems") |
| `Makefile` | `make` builds `cc09`, the passes, `crt0.o`, `crt0b.o` and `libc.o`; `make test` runs every test |
| `include/*.h` | `stdio.h`, `stdlib.h`, `string.h`, `ctype.h`, `stdarg.h`, `mini09.h` |
| `lib/clib.c` | The library parts written in C: `printf` family, `fgets`, `atoi`, `malloc`, `ctype.h`, `rand` |
| `lib/crt0.asm` | C startup; with `BANKED`, also loads the code banks and has `__bcall`/`__bret` |
| `lib/crt0b.asm` | `crt0.asm` with `BANKED`: `CRT0B.O`, for banked code |
| `lib/libc.asm` | LIBC: includes the four below as one object |
| `lib/arith.asm`, `lib/long.asm` | 16- and 32-bit helpers |
| `lib/string.asm` | `string.h` |
| `lib/stdio.asm` | console, files over the flash drive, `exit`, `bank` |
| `tools/rt.py` | Builds and runs a program in emu6809, for the tests |
| `tools/arithtest.py`, `tools/iotest.py`, `tools/nativetest.py` | The runtime tests |
| `tools/cctest.py`, `tools/ccnative.py` | The compiler tests |
| `tools/selftest.py` | The self-hosting test |
| `tools/banktest.py` | The banked-code test (`--mkbig` writes the filler) |
| `tools/mkdrive.py` | `make drive`: a folder for the flash drive |
| `tests/rt/iotest.asm`, `iotest.out` | The I/O test and its expected output |
| `tests/cc/*.c`, `*.out` | C test programs and their expected output |
| `tests/bank/` | Banked-code tests: `bt*.asm` and `bt.out` by hand, `*.c` and `bank.out` |
