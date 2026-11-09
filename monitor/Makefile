# MAX-80 boot disk monitor. Needs sjasmplus and Python 3. `make
# test` also needs the emulator built in ../emu. The boot sector, console,
# keys and disk tool are the diag's.
SJASM ?= sjasmplus
SRC = $(wildcard src/*.asm src/*.inc) ../diag/src/boot.asm ../diag/src/cons.asm \
      ../diag/src/keys.asm ../diag/src/setup.asm ../diag/src/vars.inc \
      ../xcpmz80/src/hw.inc ../xcpmz80/src/font.bin
MKDISK = ../diag/tools/mkdisk.py

all: build/monitor.imd build/monitor_525.imd

build/monitor.sys: $(SRC)
	@mkdir -p build
	cd src && $(SJASM) --nologo --msg=war --lst=../build/monitor.lst --raw=../build/monitor.sys mon.asm

build/monitor.imd: build/monitor.sys $(MKDISK)
	python3 $(MKDISK) build/monitor.sys $@

build/monitor_525.imd: build/monitor.sys $(MKDISK)
	python3 $(MKDISK) build/monitor.sys $@ --525

test: all
	sh test.sh

clean:
	rm -rf build

.PHONY: all test clean
