# MAX-80 diagnostic disk. Needs sjasmplus and Python 3. `make test`
# also needs the emulator built in ../emu.
SJASM ?= sjasmplus
SRC = $(wildcard src/*.asm src/*.inc) ../xcpmz80/src/hw.inc ../xcpmz80/src/font.bin

all: build/diag.imd build/diag_525.imd

build/diag.sys: $(SRC)
	@mkdir -p build
	cd src && $(SJASM) --nologo --msg=war --lst=../build/diag.lst --raw=../build/diag.sys diag.asm

build/diag.imd: build/diag.sys tools/mkdisk.py
	python3 tools/mkdisk.py build/diag.sys $@

build/diag_525.imd: build/diag.sys tools/mkdisk.py
	python3 tools/mkdisk.py build/diag.sys $@ --525

test: all
	sh test.sh

clean:
	rm -rf build

.PHONY: all test clean
