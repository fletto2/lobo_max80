# C programs for xcpmz80, built with SDCC 4.6.0 for the Z80,
# arguments in registers (--sdcccall 1, its default), the library's and
# page.s's functions on the stack (__LIB, include/_cconv.h). lib/ is
# the CP/M C library, built as build/cpm.lib, one object a function or
# so. include/ its headers. From SDCC's z80.lib come only the compiler's
# own helpers (multiply, divide, the long and float arithmetic) and atof.
#
# The library runs resident in bank B2: build/CLIB.SYS, made from
# cpm.lib and clib/, which xcpmz80 loads at cold start. The programs link
# clibr/ and a thunk for each function they call, build/clibr.lib, and
# need xcpmz80 with CLIB.SYS.
SDCC_BIN ?= /opt/cross/sdcc-4.6.0/bin
CC = $(SDCC_BIN)/sdcc
AS = $(SDCC_BIN)/sdasz80
AR = $(SDCC_BIN)/sdar
# --nolospre everywhere: SDCC's lospre has miscompiled bfind() in
# MicroEMACS, and every file is smaller without it.
NOLOSPRE = --nolospre
CFLAGS = -mz80 --std-sdcc99 -Iinclude --opt-code-size $(NOLOSPRE)
LDFLAGS = -mz80 --no-std-crt0 --code-loc 0x100 --data-loc 0
B = build
L = $(B)/lib

# The modules, one object each
LIB_C = files getc putc fgets fputs fread fseek feof remove getline \
	vfmt printf sprintf vscan scanf sscanf perror strerror err \
	malloc exit args getenv time tm strftime conio unistd getopt \
	cpmdir bios assert
LIB_S = bdos memcpy smemcpy memmove memset strlen strcpy strcmp strchr setjmp
# The files built once for each function, by L_name
CTYPE_FN = isalnum isalpha isascii isblank iscntrl isdigit isgraph \
	islower isprint ispunct isspace isupper isxdigit tolower toupper \
	toascii
STRING_FN = $(shell sed -n 's/^\#ifdef L_//p' lib/string.c)
STDLIB_FN = $(shell sed -n 's/^\#ifdef L_//p' lib/stdlib.c)

LIB_OBJ = $(LIB_C:%=$(L)/%.rel) $(LIB_S:%=$(L)/%.rel) \
	$(CTYPE_FN:%=$(L)/ctype_%.rel) $(STRING_FN:%=$(L)/string_%.rel) \
	$(STDLIB_FN:%=$(L)/stdlib_%.rel)
CRT0 = $(B)/crt0.rel
CLIB = $(B)/cpm.lib

# The resident library: CLIB.SYS, and the programs' side
R = $(B)/clib
CLIB_SYS = $(B)/CLIB.SYS
CLIB_OBJ = $(R)/hdr.rel $(R)/marshal.rel $(R)/malloc.rel $(R)/wrap.rel $(R)/tab.rel
CRT0R = $(R)/crt0r.rel
RLIB = $(B)/clibr.lib
# what stays in each program: its own state, callbacks, BDOS calls, and
# strftime, asctime and ctime, as B2 is full
SIDE_OBJ = $(R)/side.rel $(L)/args.rel $(L)/bdos.rel $(L)/bios.rel $(L)/smemcpy.rel \
	$(L)/setjmp.rel $(L)/stdlib_qsort.rel $(L)/stdlib_bsearch.rel \
	$(L)/getopt.rel $(L)/getline.rel $(L)/strftime.rel

ADV_SRC = $(wildcard advent/*.c)
ADV_REL = $(patsubst advent/%.c,$(B)/adv/%.rel,$(ADV_SRC))
ADV_TXT = $(B)/ADVENT1.TXT $(B)/ADVENT2.TXT $(B)/ADVENT3.TXT $(B)/ADVENT4.TXT

all: $(CLIB_SYS) $(B)/CTEST.COM $(B)/ADVENT.COM $(ADV_TXT) $(B)/BASE64.COM \
	$(B)/base64_host $(B)/page_host $(B)/page_z80host $(B)/ZORK.COM \
	$(B)/EMACS.COM $(B)/VI.COM

$(CRT0): lib/crt0.s
	@mkdir -p $(B)
	$(AS) -plosgff -o $@ $<

$(L)/%.rel: lib/%.s
	@mkdir -p $(L)
	$(AS) -plosgff -o $@ $<

$(L)/%.rel: lib/%.c lib/cpmint.h include/*.h
	@mkdir -p $(L)
	$(CC) $(CFLAGS) -c -o $@ $<

# One source file a function: its own module name, its L_ set
$(L)/ctype_%.rel: lib/ctype.c include/*.h
	@mkdir -p $(L)/gen
	printf '#define L_%s\n#include "../../../lib/ctype.c"\n' $* > $(L)/gen/ctype_$*.c
	$(CC) $(CFLAGS) -c -o $@ $(L)/gen/ctype_$*.c
$(L)/string_%.rel: lib/string.c include/*.h
	@mkdir -p $(L)/gen
	printf '#define L_%s\n#include "../../../lib/string.c"\n' $* > $(L)/gen/string_$*.c
	$(CC) $(CFLAGS) -c -o $@ $(L)/gen/string_$*.c
$(L)/stdlib_%.rel: lib/stdlib.c include/*.h
	@mkdir -p $(L)/gen
	printf '#define L_%s\n#include "../../../lib/stdlib.c"\n' $* > $(L)/gen/stdlib_$*.c
	$(CC) $(CFLAGS) -c -o $@ $(L)/gen/stdlib_$*.c

$(CLIB): $(LIB_OBJ)
	rm -f $@
	$(AR) rcs $@ $(LIB_OBJ)

# ---- The resident library ----
$(R)/tab.c: clib/clib.lst tools/clibgen.py
	@mkdir -p $(R)
	python3 tools/clibgen.py clib/clib.lst $@ $(R)/thunks

$(R)/%.rel: clib/%.s
	@mkdir -p $(R)
	$(AS) -plosgff -o $@ $<
$(R)/%.rel: clib/%.c clib/clib.h lib/cpmint.h include/*.h
	@mkdir -p $(R)
	$(CC) $(CFLAGS) -Iclib -c -o $@ $<
$(R)/tab.rel: $(R)/tab.c clib/clib.h
	$(CC) $(CFLAGS) -Iclib -c -o $@ $<
$(R)/crt0r.rel: clibr/crt0r.s
	@mkdir -p $(R)
	$(AS) -plosgff -o $@ $<
$(R)/side.rel: clibr/side.c include/*.h
	@mkdir -p $(R)
	$(CC) $(CFLAGS) -c -o $@ $<

# Linked at 0000h, the header first. All of it, its variables and the
# arena included, must end under 8000h, where A1 starts.
$(CLIB_SYS): $(CLIB_OBJ) $(CLIB)
	$(CC) -mz80 --no-std-crt0 --code-loc 0 --data-loc 0 -o $(R)/clib.ihx \
		$(CLIB_OBJ) $(CLIB)
	objcopy -I ihex -O binary $(R)/clib.ihx $@
	@end=$$(sed -n 's/^DEF s__HEAP //p' $(R)/clib.noi); \
	echo "CLIB.SYS: $$(stat -c %s $@) bytes, ends at $$end"; \
	[ $$(( end )) -le $$(( 0x8000 )) ] || { echo "CLIB.SYS is past 8000h"; rm -f $@; exit 1; }

$(RLIB): $(R)/tab.c $(SIDE_OBJ)
	rm -f $@
	for f in $(R)/thunks/*.s; do \
		$(AS) -o $${f%.s}.rel $$f || exit 1; done
	$(AR) rcs $@ $(SIDE_OBJ) $(R)/thunks/*.rel

$(B)/ctest.rel: test/ctest.c include/*.h
	@mkdir -p $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

# $(call link,name,objects): the .COM is the image from 0100h, out of
# the linker's Intel hex. Linked twice, the second time with the
# initialized variables at their initial values, which the first link
# placed (lib/crt0.s).
link = $(CC) $(LDFLAGS) -o $(B)/$(1).ihx $(2) && \
	$(CC) $(LDFLAGS) -Wl-b_INITIALIZED=$$(sed -n 's/^DEF s__INITIALIZER //p' $(B)/$(1).noi) \
		-o $(B)/$(1).ihx $(2) && \
	objcopy -I ihex -O binary $(B)/$(1).ihx $@

$(B)/CTEST.COM: $(CRT0R) $(RLIB) $(B)/ctest.rel
	$(call link,ctest,$(CRT0R) $(B)/ctest.rel $(RLIB))

# Colossal Cave Adventure, troglobit's, reading its text from disk
$(B)/adv/%.rel: advent/%.c advent/*.h include/*.h
	@mkdir -p $(B)/adv
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/ADVENT.COM: $(CRT0R) $(RLIB) $(ADV_REL)
	$(call link,advent,$(CRT0R) $(ADV_REL) $(RLIB))

$(B)/ADVENT%.TXT: advent/advent%.txt
	cp $< $@

# BASE64, agfa9000's file transfer, and its host side
$(B)/base64.rel: base64/base64.c include/*.h
	@mkdir -p $(B)
	$(CC) $(CFLAGS) -c -o $@ $<

$(B)/BASE64.COM: $(CRT0R) $(RLIB) $(B)/base64.rel
	$(call link,base64,$(CRT0R) $(B)/base64.rel $(RLIB))

$(B)/base64_host: base64/host.c
	@mkdir -p $(B)
	cc -O2 -o $@ $<

# The page module: page.s in the editors, page.c its model in C.
# page_host runs the host test on page.c, with a BDOS on the host's
# files. page_z80host runs it on page.s, linked alone at 0100h, on the
# emulator's Z80 core.
$(B)/page/page.rel: page/page.s
	@mkdir -p $(B)/page
	$(AS) -plosgff -o $@ $<

$(B)/page/pz.ihx: $(B)/page/page.rel
	$(SDCC_BIN)/sdldz80 -n -m -w -i $(B)/page/pz -b _CODE=0x0100 \
		-b _DATA=0x9000 -g _ed_end=0x10 -g _ed_step=0x11 -g _ed_tag=0x12 \
		-g _ed_text=0x13 -g _ed_begin=0x14 -g _ed_add=0x15 \
		-g _ed_drop=0x16 -g _remove=0x17 -g _rename=0x18 $<

$(B)/page_host: page/host.c page/page.c page/page.h
	@mkdir -p $(B)
	cc -O2 -Wall -DPG_HOST -o $@ page/host.c page/page.c

$(B)/page_z80host: page/host.c page/z80host.c page/page.h ../../emu/z80.c \
		$(B)/page/pz.ihx
	cc -O2 -Wall -DPG_HOST -DPZ='"$(abspath $(B)/page/pz)"' -o $@ \
		page/host.c page/z80host.c ../../emu/z80.c

# ZORK, MojoZork for Z-machine version 3 stories, the story read
# through a page cache. Built for speed, not size.
$(B)/zork.rel: zork/mojozork.c include/*.h
	@mkdir -p $(B)
	$(CC) -mz80 --std-sdcc99 -Iinclude $(NOLOSPRE) -c -o $@ $<

$(B)/ZORK.COM: $(CRT0R) $(RLIB) $(B)/zork.rel
	$(call link,zork,$(CRT0R) $(B)/zork.rel $(RLIB))

# MicroEMACS 3.6, agfa9000's CP/M-68K port, in ANSI C. The
# register allocator's longer search makes it 1K smaller, for the text.
# SDCC's lospre has miscompiled bfind() (buffer.c): it stored the old
# list head in place of the new buffer.
EMACS_SRC = $(wildcard emacs/*.c)
EMACS_REL = $(patsubst emacs/%.c,$(B)/emacs/%.rel,$(EMACS_SRC))

$(B)/emacs/%.rel: emacs/%.c emacs/*.h page/page.h include/*.h
	@mkdir -p $(B)/emacs
	$(CC) $(CFLAGS) --max-allocs-per-node 30000 -c -o $@ $<

# The window over a file bigger than memory, page/page.s
$(B)/EMACS.COM: $(CRT0R) $(RLIB) $(EMACS_REL) $(B)/page/page.rel
	$(call link,emacs,$(CRT0R) $(EMACS_REL) $(B)/page/page.rel $(RLIB))

# STEVIE 3.7A, the vi clone, G.R. Walter's line as GNO keeps it,
# with a MAX-80 system file. vi/vpage.s is its side of the window over a
# file bigger than memory, page/page.s, in Z80 code as that is.
VI_SRC = $(wildcard vi/*.c)
VI_REL = $(patsubst vi/%.c,$(B)/vi/%.rel,$(VI_SRC)) $(B)/vi/vpage.rel

$(B)/vi/%.rel: vi/%.c vi/*.h page/page.h include/*.h
	@mkdir -p $(B)/vi
	$(CC) $(CFLAGS) --max-allocs-per-node 30000 -c -o $@ $<

$(B)/vi/vpage.rel: vi/vpage.s
	@mkdir -p $(B)/vi
	$(AS) -plosgff -o $@ $<

$(B)/VI.COM: $(CRT0R) $(RLIB) $(VI_REL) $(B)/page/page.rel
	$(call link,vi,$(CRT0R) $(VI_REL) $(B)/page/page.rel $(RLIB))

clean:
	rm -rf $(B)

.PHONY: all clean
