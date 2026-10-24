SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
LWASM := $(shell command -v lwasm)

all: os.s19 os-rom.bin hello.s19 vdpdemo.s19 cpu6309.s19 basic.s19 basic-rom.s19 mini09-rom32.bin emu6809 \
     hello.prg vdpdemo.prg cpu6309.prg basic.prg asm.prg link.prg edit.prg mc.prg

schematic: hw/schematic.svg

hw/schematic.svg: hw/schematic.py
	cd hw && python3 schematic.py
	inkscape hw/schematic.svg --export-type=pdf --export-filename=hw/schematic.pdf

# Console: make CONSOLE=serial (DUART only) or CONSOLE=vdc (the video
# card's HDMI screen and USB keyboard; serial if no card answers); the
# default is both.  .console remembers the last choice, so changing it
# rebuilds the kernel.
CONSOLE ?= both
CONDEF_both :=
CONDEF_serial := -D CON_SERIAL
CONDEF_vdc := -D CON_VDC
ifeq ($(filter $(CONSOLE),both serial vdc),)
$(error CONSOLE must be both, serial or vdc)
endif

.console: FORCE
	@echo $(CONSOLE) | cmp -s - $@ || echo $(CONSOLE) > $@

os.s19: os.asm syscalls.inc vdp.inc .console
	$(LWASM) --format=srec --list=os.lst $(CONDEF_$(CONSOLE)) -o $@ os.asm

# 8K EEPROM image for U3 ($E000-$FFFF, unused bytes $FF)
os-rom.bin: os.s19
	python3 hw/srec2bin.py os.s19 0xE000 8192 $@ --check

cpu6309.s19: cpu6309.asm syscalls.inc
	$(LWASM) --format=srec -o $@ cpu6309.asm

basic.s19: basic.asm syscalls.inc vdp.inc
	$(LWASM) --format=srec -o $@ basic.asm

# Program files for the flash drive (LOAD, or type the name): a header with the name,
# creator and build date, then the bytes (tools/mkprg.py)
%.prg: %.s19 tools/mkprg.py
	python3 tools/mkprg.py $< $@ --name $(shell echo $* | tr a-z A-Z).PRG

# BASIC for the ROM bank: code at $8000-$BFFF, programs from $1000
basic-rom.s19: basic.asm syscalls.inc vdp.inc
	$(LWASM) --format=srec -D ROMBASIC -o $@ basic.asm

# 32K image for a 28C256 in U3: ROM $0000-$3FFF is the BASIC bank (CPU
# $8000-$BFFF when $D803 bit 4 is set), $6000-$7FFF the kernel (CPU $E000)
mini09-rom32.bin: basic-rom.s19 os.s19
	python3 hw/srec2bin.py basic-rom.s19 0x8000 16384 rom-bank.tmp
	python3 hw/srec2bin.py os.s19 0xE000 8192 rom-os.tmp --check
	{ cat rom-bank.tmp; head -c 8192 /dev/zero | tr '\0' '\377'; cat rom-os.tmp; } > $@
	rm -f rom-bank.tmp rom-os.tmp

hello.s19: hello.asm syscalls.inc
	$(LWASM) --format=srec -o $@ hello.asm

vdpdemo.s19: vdpdemo.asm syscalls.inc vdp.inc
	$(LWASM) --format=srec -o $@ vdpdemo.asm

# ASM, the assembler that runs under MINI09 (asm.md)
asm.s19: asm.asm syscalls.inc vdp.inc
	$(LWASM) --format=srec -o $@ asm.asm

# LINK, its linker for lwasm object files (asm.md)
link.s19: link.asm syscalls.inc vdp.inc
	$(LWASM) --format=srec -o $@ link.asm

edit.s19: edit.asm syscalls.inc vdp.inc
	$(LWASM) --format=srec -o $@ edit.asm

# MC, the two-panel file manager
mc.s19: mc.asm syscalls.inc vdp.inc
	$(LWASM) --format=srec -o $@ mc.asm

emu6809: emu6809.c
	gcc -O2 -Wall -o $@ $<

run: all
	./emu6809 os.s19

test: all
	{ cat test/session1.txt; cat hello.s19; cat test/session2.txt; } | ./emu6809 -f -t 7 os.s19

# HD63C09E instruction test: load cpu6309.s19 with L, run it with G 1000
test-6309: all
	{ printf 'L\n'; cat cpu6309.s19; printf 'G 1000\n'; } | ./emu6809 -f -t 1 os.s19

# Same OS with the video/sound chip fitted (-v): shell commands, then the demo
run-vdp: all
	./emu6809 -v os.s19

test-vdp: all
	{ cat test/vdp1.txt; cat vdpdemo.s19; cat test/vdp2.txt; } | ./emu6809 -v -f -t 8 os.s19

# USB keyboard (-k: input arrives as key presses) and flash drive (-d)
test-usb: all
	rm -rf build-drive && mkdir -p build-drive/DEMOS
	cp hello.prg build-drive/HELLO.PRG
	cp vdpdemo.prg build-drive/DEMOS/VDPDEMO.PRG
	cp test/readme.txt build-drive/README.TXT
	./emu6809 -v -k -d build-drive -f -t 8 os.s19 < test/usb1.txt
	@echo "--- build-drive after the run:"; ls -l build-drive
	python3 tools/mkprg.py --info build-drive/COPY.PRG

# EDIT: open a file, change it, save, quit, then show it
test-edit: all
	rm -rf build-drive && mkdir -p build-drive
	cp edit.prg build-drive/EDIT.PRG
	printf 'first line\r\n\tsecond line\r\nthird line\r\n' > build-drive/T.TXT
	printf 'EDIT T.TXT\n\033[B\033[FX\nnew line\023\030TYPE T.TXT\n' \
		| ./emu6809 -v -k -d build-drive -f -t 3 os.s19 > /dev/null
	@echo "--- build-drive/T.TXT after the edit:"; cat build-drive/T.TXT

# MC: key presses on a scratch drive, checked against the screen they leave
test-mc: all
	python3 tools/mctest.py

# ASM: assemble each file with ASM in the emulator and with lwasm, and
# compare the program files byte for byte (asm.asm is ASM itself)
ASMTESTS := hello.asm vdpdemo.asm basic.asm cpu6309.asm asm.asm link.asm asmtests/allops.asm asmtests/ops6309.asm asmtests/expr.asm
test-asm: all
	python3 tools/asmtest.py $(ASMTESTS)

# ASM's object files and LINK against lwasm + lwlink (needs lwlink too)
OBJTESTS := asmtests/obj/main.asm+asmtests/obj/lib.asm asmtests/obj/six.asm+asmtests/obj/six2.asm
SECTTESTS := hello.asm vdpdemo.asm cpu6309.asm asm.asm link.asm basic.asm asmtests/allops.asm asmtests/ops6309.asm asmtests/expr.asm
test-obj: all
	python3 tools/objtest.py $(OBJTESTS)
	python3 tools/objtest.py --time 300 --section $(SECTTESTS)

# BASIC: run the example programs from a scratch drive, enter and save one
test-basic: all
	rm -rf build-drive && mkdir -p build-drive
	cp basic.prg build-drive/BASIC.PRG
	for f in examples/*.bas; do b=$$(basename $$f .bas); cp $$f build-drive/$${b^^}.BAS; done
	./emu6809 -v -k -d build-drive -f -t 6 os.s19 < test/basic1.txt

# ROM BASIC: the shell's BASIC command with the ROM bank (-r), and without
test-rombasic: all
	rm -rf build-drive && mkdir -p build-drive
	printf 'BASIC\n10 PRINT "FROM ROM";FRE\nRUN\nBYE\nPS\n' \
		| ./emu6809 -v -k -d build-drive -r basic-rom.s19 -f -t 3 os.s19
	printf 'BASIC\nPS\n' | ./emu6809 -f -t 2 os.s19

# The console builds, assembled on the side (os.s19 is left alone):
# vdc with the card (-T shows its terminal), vdc without one (serial),
# and serial with the card (nothing mirrored: 0 terminal chars)
test-console: all
	$(LWASM) --format=srec -D CON_VDC -o con-vdc.s19 os.asm
	$(LWASM) --format=srec -D CON_SERIAL -o con-serial.s19 os.asm
	@echo "--- vdc, card fitted:"
	printf 'UP\n' | ./emu6809 -v -k -T -f -t 1 con-vdc.s19
	@echo "--- vdc, no card:"
	printf 'UP\n' | ./emu6809 -f -t 1 con-vdc.s19
	@echo "--- serial, card fitted:"
	printf 'UP\n' | ./emu6809 -v -f -t 1 con-serial.s19
	rm -f con-vdc.s19 con-serial.s19

# PCB: place from the netlist, autoroute with Freerouting, pour, check, export
# CPLD (U5 ATF750C): compile CUPL to JEDEC with WinCUPL under Wine
WINCUPL := C:\Wincupl\Shared

pld: hw/pld/MINI09.jed

hw/pld/MINI09.jed: hw/pld/mini09.pld
	cd hw/pld && WINEDEBUG=-all wine '$(WINCUPL)\cupl.exe' -jaxfl -u '$(WINCUPL)\cupl.dl' mini09.pld \
		| grep -q "Error Code = 0"

# KiCad schematic + project symbol library, checked with ERC
kicad-sch: hw/schematic.svg
	cd hw && python3 kicad_sch.py
	kicad-cli sch erc --exit-code-violations -o hw/erc.rpt hw/mini09.kicad_sch
	kicad-cli sch export pdf -o hw/mini09-kicad-schematic.pdf hw/mini09.kicad_sch
	kicad-cli sch export netlist --format kicadsexpr -o hw/mini09.net hw/mini09.kicad_sch

pcb: kicad-sch
	cd hw && python3 pcb.py
	cd hw && python3 route.py 2>&1 | grep -v swig/python
	cd hw && python3 finish.py 2>&1 | grep -v swig/python
	kicad-cli pcb drc --schematic-parity --exit-code-violations -o hw/drc.rpt hw/mini09.kicad_pcb
	rm -rf hw/fab hw/mini09-gerbers.zip && mkdir -p hw/fab
	kicad-cli pcb export gerbers -l F.Cu,B.Cu,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts \
		-o hw/fab/ hw/mini09.kicad_pcb
	kicad-cli pcb export drill --format excellon --excellon-separate-th -o hw/fab/ hw/mini09.kicad_pcb
	cd hw/fab && zip -q ../mini09-gerbers.zip *
	kicad-cli pcb render --side top --quality high --width 1600 --height 1000 \
		-o hw/render-top.png hw/mini09.kicad_pcb
	kicad-cli pcb render --side top --rotate "-40,0,-25" --perspective --quality high \
		--width 1600 --height 1000 -o hw/render-3d.png hw/mini09.kicad_pcb

.PHONY: FORCE all run test test-6309 run-vdp test-vdp test-usb test-edit test-mc test-asm test-obj test-basic test-rombasic test-console schematic kicad-sch pcb pld clean

clean:
	rm -f os.s19 os-rom.bin os.lst hello.s19 vdpdemo.s19 cpu6309.s19 basic.s19 basic-rom.s19 mini09-rom32.bin emu6809
	rm -f hello.prg vdpdemo.prg cpu6309.prg basic.prg asm.s19 asm.prg link.s19 link.prg edit.s19 edit.prg mc.s19 mc.prg
	rm -rf build-drive .console
