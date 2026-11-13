# xcpmz80. Needs sjasmplus and Python 3. `make test` also needs the
# emulator built in ../emu and mtools.
SJASM ?= sjasmplus
SRC = $(wildcard src/*.asm src/*.inc) build/font.bin
# make FONT=src/font_inverse.bin builds the inverse second style
FONT ?= src/font.bin

all: build/xcpmz80.imd

# Copied only when it differs, so switching FONT rebuilds
build/font.bin: FORCE
	@mkdir -p build
	@cmp -s $(FONT) $@ || cp $(FONT) $@

build/xcpmz80.sys: $(SRC)
	cd src && $(SJASM) --nologo --msg=war --lst=../build/xcpmz80.lst --raw=../build/xcpmz80.sys xcpmz80.asm

# The same system reading every floppy sector alone, with no track
# buffer, for a test on the machine
build/noruns/xcpmz80.sys: $(SRC)
	mkdir -p build/noruns
	cd src && $(SJASM) --nologo --msg=war -DNORUNS --raw=../build/noruns/xcpmz80.sys xcpmz80.asm

# The same system checking every run read against the sectors read
# alone, and printing what differed, for a test on the machine
build/runlog/xcpmz80.sys: $(SRC)
	mkdir -p build/runlog
	cd src && $(SJASM) --nologo --msg=war -DRUNLOG --raw=../build/runlog/xcpmz80.sys xcpmz80.asm

# The boot disk also carries the programs in apps/, the system's font
# as XCPM.FNT for LDFONT to load again, and both fonts as THIN.FNT and
# INVERSE.FNT
APPS = build/LDFONT.COM build/GLYPHS.COM build/CLOCK.COM build/MORE.COM build/BENCH.COM
FONTS = build/XCPM.FNT build/THIN.FNT build/INVERSE.FNT
# BOLD.FNT, the two styles swapped, goes on the apps disks and in dist,
# not on the boot disk
XFONTS = build/BOLD.FNT

build/ZX81.COM: apps/zx81/zx81.asm apps/zx81/hw.inc
	mkdir -p build
	cd apps/zx81 && $(SJASM) --nologo --msg=war --raw=../../build/ZX81.COM zx81.asm

build/LDFONT.COM: apps/ldfont.asm
	mkdir -p build
	$(SJASM) --nologo --msg=war --raw=$@ $<

build/GLYPHS.COM: apps/glyphs.asm
	mkdir -p build
	$(SJASM) --nologo --msg=war --raw=$@ $<

build/CLOCK.COM: apps/clock.asm
	mkdir -p build
	$(SJASM) --nologo --msg=war --raw=$@ $<

build/BENCH.COM: apps/bench.asm
	mkdir -p build
	$(SJASM) --nologo --msg=war --raw=$@ $<

build/MORE.COM: apps/more.asm
	mkdir -p build
	$(SJASM) --nologo --msg=war --raw=$@ $<


build/XCPM.FNT: build/font.bin
	cp build/font.bin $@

build/THIN.FNT: src/font.bin
	mkdir -p build
	cp src/font.bin $@

build/BOLD.FNT: src/font.bin tools/swapfont.py
	mkdir -p build
	python3 tools/swapfont.py src/font.bin $@

build/INVERSE.FNT: src/font_inverse.bin
	mkdir -p build
	cp src/font_inverse.bin $@

build/xcpmz80.imd: build/xcpmz80.sys tools/mkdisk.py $(APPS) $(FONTS)
	python3 tools/mkdisk.py build/xcpmz80.sys build/xcpmz80.imd --raw build/xcpmz80.img \
		$(APPS) $(FONTS)

# The same on a 5.25-inch disk, booted with -D 1
525: build/xcpmz80_525.imd build/xcpmz80_180.imd

build/xcpmz80_525.imd: build/xcpmz80.sys tools/mkdisk.py $(APPS) $(FONTS)
	python3 tools/mkdisk.py build/xcpmz80.sys --525 360 $@ $(APPS) $(FONTS)

# One side, sectors from 0, as the diagnostic's 180K disk
build/xcpmz80_180.imd: build/xcpmz80.sys tools/mkdisk.py $(APPS) $(FONTS)
	python3 tools/mkdisk.py build/xcpmz80.sys --525 180 $@ $(APPS) $(FONTS)

# The apps disk: the boot disk with CLIB.SYS, which xcpmz80 loads
# from the boot drive, the C programs (c/, needs SDCC), ADVENT's text
# and the ZX81 games. ZORK goes without a story, as the stories are
# Infocom's. 8-inch, 5.25-inch 360K for -D 1, and 720K.
C = c/build
CPROGS = $(C)/CLIB.SYS $(C)/VI.COM $(C)/EMACS.COM $(C)/ADVENT.COM \
	$(C)/ADVENT1.TXT $(C)/ADVENT2.TXT $(C)/ADVENT3.TXT $(C)/ADVENT4.TXT \
	$(C)/ZORK.COM $(C)/BASE64.COM
# ZX81 games, and ZX81.ROM for their shapes when ZX81_ROM is there
ZX81_ROM ?= zx81.rom
ZX81 = build/ZX81.COM $(wildcard apps/zx81/games/*.P) \
	$(if $(wildcard $(ZX81_ROM)),build/ZX81.ROM)
APPDISK ?= $(APPS) $(CPROGS) $(FONTS) $(ZX81) $(XFONTS) build/BENCH.DAT
# BENCH's file, 64K, and 32K where room is short, the 360K disk and the
# everything disk; its tag is set to each disk's layout
APPDISK32 = $(filter-out build/BENCH.DAT,$(APPDISK)) build/b32/BENCH.DAT

build/BENCH.DAT: tools/benchdat.py
	mkdir -p build
	python3 tools/benchdat.py $@

build/b32/BENCH.DAT: tools/benchdat.py
	mkdir -p build/b32
	python3 tools/benchdat.py $@ 32
apps: build/apps.imd build/apps_525.imd build/apps_720.imd

$(CPROGS): cprogs

build/ZX81.ROM: $(ZX81_ROM)
	cp $< $@

cprogs:
	$(MAKE) -C c

build/apps.imd: build/xcpmz80.sys tools/mkdisk.py $(APPDISK)
	python3 tools/mkdisk.py build/xcpmz80.sys $@ --raw build/apps.img $(APPDISK)

build/apps_525.imd: build/xcpmz80.sys tools/mkdisk.py $(APPDISK32)
	python3 tools/mkdisk.py build/xcpmz80.sys --525 360 $@ $(APPDISK32)

# For a 3.5-inch drive on the 5-inch connector
build/apps_720.imd: build/xcpmz80.sys tools/mkdisk.py $(APPDISK)
	python3 tools/mkdisk.py build/xcpmz80.sys --525 720 $@ $(APPDISK)


# The fonts are committed. src/font.bin is edited by hand from the
# thin face mkfont.py makes, so only the inverse one is rebuilt here.

font:
	python3 tools/mkfont.py --inverse tools/unscii-8.hex src/font_inverse.bin

# test.sh in its parts at once, each with its own folder in build/test;
# sh test.sh runs them one after another
test: all
	python3 tools/testparts.py

clean:
	rm -rf build

.PHONY: all 525 apps cprogs font test clean FORCE
FORCE:
