# CC, the C compiler for MINI09: its four passes built with gcc (cpp09,
# parse09, sema09, gen09) and cc09, which runs them; the runtime (lib/);
# and their tests.
# Needs lwasm and lwlink (lwtools 4.24) on PATH, and the emulator, os.s19,
# asm.prg and link.prg built in the folder above (make, make asm.prg
# link.prg there).

LWASM   ?= lwasm
LIBSRC  = lib/arith.asm lib/long.asm lib/string.asm lib/stdio.asm

CC      ?= gcc

PASSES  = cpp09 parse09 sema09 gen09

all: cc09 $(PASSES) crt0.o crt0b.o libc.o

cc09: cc09.c $(PASSES)
	$(CC) -O2 -Wall -o $@ cc09.c

cpp09: cpp.c lex.c common.c cc.h
	$(CC) -O2 -Wall -Wno-unused -o $@ cpp.c

parse09: parse.c lex.c common.c cc.h
	$(CC) -O2 -Wall -Wno-unused -o $@ parse.c

sema09: sema.c common.c cc.h
	$(CC) -O2 -Wall -Wno-unused -o $@ sema.c

gen09: gen.c common.c cc.h
	$(CC) -O2 -Wall -Wno-unused -o $@ gen.c

crt0.o: lib/crt0.asm ../syscalls.inc
	$(LWASM) --format=obj -I lib -I .. -o $@ $<

crt0b.o: lib/crt0b.asm lib/crt0.asm ../syscalls.inc
	$(LWASM) --format=obj -I lib -I .. -o $@ $<

libc.o: lib/libc.asm $(LIBSRC) ../syscalls.inc ../vdp.inc
	$(LWASM) --format=obj -I lib -I .. -o $@ $<

../emu6809 ../os.s19 ../asm.prg ../link.prg:
	$(MAKE) -C .. $(notdir $@)

# The runtime in emu6809: arithmetic against Python's answers, then
# arguments, strings and files, then the same program built by ASM and
# LINK on MINI09.  Then the compiler: tests/cc/*.c built by cc09 and run,
# and one of them assembled and linked on MINI09.
test: test-arith test-io test-native test-cc test-ccnative test-self test-bank

test-arith: ../emu6809 ../os.s19
	python3 tools/arithtest.py

test-io: ../emu6809 ../os.s19
	python3 tools/iotest.py

test-native: ../emu6809 ../os.s19 ../asm.prg ../link.prg
	python3 tools/nativetest.py

test-cc: cc09 ../emu6809 ../os.s19
	python3 tools/cctest.py

test-ccnative: cc09 ../emu6809 ../os.s19 ../asm.prg ../link.prg
	python3 tools/ccnative.py

# Banked code (#pragma bank): by hand in assembler, then C built on the
# PC and by CC.PRG on MINI09, each run; LINK.PRG against tools/pylink.py.
test-bank: cc09 crt0b.o ../emu6809 ../os.s19 ../link.prg
	python3 tools/banktest.py

clean:
	rm -f *.o cc09 $(PASSES)
	rm -rf drive

# CC on MINI09: the passes compile the tests and themselves in emu6809,
# the same bytes as cc09, then ASM and LINK build them, the same as lwasm
# and lwlink.  (Needs LINK with the synsym fix: see cc.md.)
test-self: cc09 ../emu6809 ../os.s19 ../asm.prg ../link.prg
	python3 tools/selftest.py

# drive/: the passes, ASM, LINK, the runtime, headers, tests and CC's own
# sources, to copy to the flash drive for the board
drive: cc09 ../asm.prg ../link.prg
	python3 tools/mkdrive.py

.PHONY: all test test-arith test-io test-native test-cc test-ccnative test-self test-bank drive clean
