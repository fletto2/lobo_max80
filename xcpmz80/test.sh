#!/bin/sh
# Tests for xcpmz80. Run from xcpmz80/ after make, with the emulator
# built in ../emu. Needs mtools. The test disks go to build/test/.
set -u
cd "$(dirname "$0")"
# -K types letters for Caps Lock on, which is how xcpmz80 boots
EMU='../emu/max80 -K'
DISK=build/xcpmz80.imd
SYS=build/xcpmz80.sys
# tools/testparts.py runs each part with a folder of its own
T=${XTEST:-build/test}
fail=0
rm -rf $T
mkdir -p $T/out
# tools/session.py notes here each wait for the screen that ran out
SESSION_LOG=$T/session.log
export SESSION_LOG
: >$SESSION_LOG

check() {	# name, text to find, output
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		echo "ok   $1"
	else
		echo "FAIL $1: no '$2' in:"
		printf '%s\n' "$3"
		fail=1
	fi
}

same() {	# name, file, file
	if cmp -s "$2" "$3"; then
		echo "ok   $1"
	else
		echo "FAIL $1: $2 and $3 differ"
		fail=1
	fi
}

mkdisk() {	# out.imd, files...
	out=$1
	shift
	python3 tools/mkdisk.py $SYS "$out" --raw "${out%.imd}.img" "$@"
}

getfile() {	# image.imd, CP/M name, out file: a file from a saved image
	python3 ../tools/imd2raw.py "$1" "${1%.imd}.img" >/dev/null &&
		mcopy -o -i "${1%.imd}.img" "::$2" "$3"
}

fatok() {	# name, raw image: the FAT volume is consistent
	if r=$(python3 tools/fatcheck.py "$2"); then
		echo "ok   $1"
	else
		echo "FAIL $1:"
		printf '%s\n' "$r"
		fail=1
	fi
}

# What more than one part uses, made once here
printf 'Hello from a text file.\r\nSecond line.\r\n\032' >$T/HELLO.TXT
# the emulator without -K, for keys as typed
RAW=../emu/max80
order() {	# the sector numbers of an IMD's first track, or track $2
	python3 -c "
import sys
d=open(sys.argv[1],'rb').read(); i=d.index(26)+1
for t in range(int(sys.argv[2])):
    n,z=d[i+3],d[i+4]; i+=5+n
    for k in range(n):
        c=d[i]; i+=1
        if c: i+=1 if c%2==0 else 128<<z
print(' '.join(str(x) for x in d[i+5:i+5+d[i+3]]))" "$1" "${2:-0}"
}

#PART
out=$(mdir -i build/xcpmz80.img :: 2>&1)
check "the disk is a FAT volume mtools reads" "Serial Number is 4D58-3830" "$out"
# mkdisk.py refuses what would make a bad disk: two files of one name,
# a name DOS cannot have, --pc one sided, which does not boot
mkdir -p $T/mk1 $T/mk2
echo a >$T/mk1/same.txt
echo b >$T/mk2/SAME.TXT
echo c >$T/a.b.c
out=$(python3 tools/mkdisk.py $SYS $T/mk.imd $T/mk1/same.txt $T/mk2/SAME.TXT 2>&1)
check "mkdisk: two files of one name refused" "SAME    TXT twice" "$out"
out=$(python3 tools/mkdisk.py $SYS $T/mk.imd $T/a.b.c 2>&1)
check "mkdisk: a name with two dots refused" "not an 8.3 name" "$out"
out=$(python3 tools/mkdisk.py $SYS --pc 720 --ss $T/mk.imd 2>&1)
check "mkdisk: --pc with --ss refused" "not --pc" "$out"
python3 tools/mkdisk.py $SYS --525 360 --ss $T/mk.imd --raw $T/mk.img >/dev/null
out=$(minfo -i $T/mk.img :: 2>&1)
check "mkdisk: --525 360 --ss has the 180K BPB" "media descriptor byte: 0xfc" "$out"
sz=$(printf '\303\237')		# a German sharp s, in UTF-8
echo d >"$T/stra${sz}e.c"
out=$(python3 tools/mkdisk.py $SYS $T/mk.imd "$T/stra${sz}e.c" 2>&1)
check "mkdisk: a name not in ASCII refused, not made STRASSE.C" "not an 8.3 name" "$out"
out=$(python3 tools/mkdisk.py $SYS --ds --ss $T/mk.imd 2>&1)
check "mkdisk: --ss on an 8-inch disk refused, not made double sided" "an 8-inch disk is one sided" "$out"
out=$(python3 tools/mkdisk.py $SYS --ds --525 360 $T/mk.imd 2>&1)
check "mkdisk: --ds with --525 refused" "--525 and --pc set the sides" "$out"
out=$(python3 tools/mkdisk.py $SYS --525 360 --pc 720 $T/mk.imd 2>&1)
check "mkdisk: --525 with --pc refused" "one or the other" "$out"
out=$(python3 tools/mkdisk.py $SYS --ilv 0 $T/mk.imd 2>&1)
check "mkdisk: --ilv 0 refused" "--ilv: 1 or more" "$out"
out=$(python3 tools/mkdisk.py $SYS $T/mk.imd $T/a.b.c --in 2>&1)
check "mkdisk: --in with nothing after it refused" "a folder, or ., after it" "$out"
# fatcheck: two files whose chains end on a free cluster, not the end
echo e >$T/B.TXT
head -c 3000 /dev/urandom >$T/A.BIN
python3 tools/mkdisk.py $SYS --pc 720 $T/fc.imd --raw $T/fc.img $T/A.BIN $T/B.TXT >/dev/null
check "fatcheck: the disk clean first" "clean" "$(python3 tools/fatcheck.py $T/fc.img)"
python3 - $T/fc.img <<'PY'
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
bps, spc, res, nfat = struct.unpack_from('<HBHB', d, 11)
fsz = struct.unpack_from('<H', d, 22)[0]
def put(n, v):
    for f in range(nfat):
        o = (res + f * fsz) * bps + n * 3 // 2
        w = struct.unpack_from('<H', d, o)[0]
        w = (w & 0x000f) | v << 4 if n & 1 else (w & 0xf000) | v
        struct.pack_into('<H', d, o, w)
def get(n):
    o = res * bps + n * 3 // 2
    w = struct.unpack_from('<H', d, o)[0]
    return w >> 4 if n & 1 else w & 0xfff
for n in range(2, 16):          # the two files' chains: each one's last freed
    if get(n) >= 0xff8:
        put(n, 0)
open(sys.argv[1], 'wb').write(d)
PY
out=$(python3 tools/fatcheck.py $T/fc.img)
check "fatcheck: a chain that ends on a free cluster is a fault" "A.BIN: chain ends on a free cluster" "$out"
check "and the other file's too, the FATs alike" "=B.TXT: chain ends on a free cluster, after 5=" "=$(echo "$out" | tail -1)="

out=$($EMU -a "$DISK" -t 5)
check "boot to sign-on" "XCP/M-Z80 v0.2 for the Lobo MAX-80" "$out"
check "finds all 128K" "MAX-80, 128K, 55K TPA" "$out"
check "boot to prompt" 'A:\>' "$out"

out=$($EMU -a "$DISK" -t 15 -e 'A:\>' -k 'hello\rDir *.COM\r')
check "keys echo, unshifted letters lower case" 'A:\>hello' "$out"
check "command answered as CP/M does" "HELLO?" "$out"
check "SHIFT gives upper case" 'A:\>Dir *.COM' "$out"

out=$($EMU -a "$DISK" -t 10 -e 'A:\>' -k "$(printf 'ab\010c')\\r")
check "BS rubs out" "AC?" "$out"

# The back arrow rubs out one character, back over a wrapped row too,
# and UP at the prompt brings back the last line
long="dir$(printf 'x%.0s' $(seq 90))$(printf '\\L%.0s' $(seq 90))"
out=$($EMU -a "$DISK" -t 60 -e 'A:\>' -k "${long}\\r\\P")
check "back arrow over a wrapped row" 'XCPM     FNT : THIN     FNT' "$out"
if printf '%s\n' "$out" | grep -q 'xxx'; then
	echo "FAIL back arrow leaves the wrapped row on the screen:"
	printf '%s\n' "$out"
	fail=1
else
	echo "ok   back arrow leaves no rubbed-out text"
fi
out=$($EMU -a "$DISK" -t 15 -e 'A:\>' -k 'qwer\r\Pab\U\Lz\r\P')
check "UP brings back the last line" "QWEZ?" "$out"

# The cursor blinks while the shell waits for a key: frames 16 ticks
# apart differ, and 32 apart are the same
for t in 4.0 4.26 4.52; do
	$EMU -a "$DISK" -t $t -p $T/out/blink$t.bin >/dev/null
done
if ! cmp -s $T/out/blink4.0.bin $T/out/blink4.26.bin &&
	cmp -s $T/out/blink4.0.bin $T/out/blink4.52.bin; then
	echo "ok   the cursor blinks at the prompt"
else
	echo "FAIL the cursor blinks at the prompt"
	fail=1
fi

# ESC E and ESC R, insert and delete a line, move the screen's start
# a row, the 2K of video RAM a ring, when the rows above the cursor are
# fewer, and copy the rest a row at a time, by LDIR when the row stays in
# one 1K half. The screens are those of the console before, which
# copied each cell, at two starts of the ring.
cat >$T/scrops.asm <<'EOF'
; SCROPS n: 30 + 3n rows of text, then lines inserted, deleted and
; erased at rows across the screen, the screen's start moving between
	org	100h
	ld	a,(82h)
	sub	'0'
	ld	b,a
	add	a,a
	add	a,b
	add	a,30
	ld	b,a
fill:	push	bc
	ld	a,b
	and	0Fh
	add	a,'A'
	ld	(rowt),a
	ld	(rowt+40),a
	ld	(rowt+74),a
	ld	de,rowt
	ld	c,9
	call	5
	pop	bc
	djnz	fill
	ld	hl,ops
op:	ld	a,(hl)
	or	a
	jr	z,done
	inc	hl
	ld	b,(hl)
	inc	hl
	push	hl
	push	af
	ld	a,1Bh			; ESC = row, column 5
	call	out
	ld	a,'='
	call	out
	ld	a,b
	add	a,20h
	call	out
	ld	a,25h
	call	out
	ld	a,1Bh
	call	out
	pop	af
	call	out
	ld	a,'*'
	call	out
	pop	hl
	jr	op
done:	ld	a,1Bh			; the prompt on row 22
	call	out
	ld	a,'='
	call	out
	ld	a,20h+22
	call	out
	ld	a,20h
	jp	out
out:	push	bc			; the BDOS keeps no registers
	push	hl
	ld	e,a
	ld	c,2
	call	5
	pop	hl
	pop	bc
	ret
ops:	db	'E',0,'R',0,'E',5,'R',11,'E',12,'R',12,'E',23,'R',23
	db	'E',11,'R',1,'E',17,'R',6,'T',3,'E',2,'E',2,'R',20
	db	'E',22,'R',0,'R',0,'E',9,'R',13,'E',14,'Y',21,0
rowt:	db	'xrow abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 .,;:x'
	db	13,10,'$'
EOF
(cd $T && sjasmplus --nologo --msg=war --raw=SCROPS.COM scrops.asm >/dev/null)
mkdisk $T/scrops.imd $T/SCROPS.COM >/dev/null
cat >$T/scrops2.ok <<'EOF'
     *
     *
Erow abcdefghijklmnopqrstuvwxyz ABCDEFGHEJKLMNOPQRSTUVWXYZ 0123456789 .,;:E
Drow *
     *
Crow abcdefghijklmnopqrstuvwxyz ABCDEFGHCJKLMNOPQRSTUVWXYZ 0123456789 .,;:C
Arow *bcdefghijklmnopqrstuvwxyz ABCDEFGHAJKLMNOPQRSTUVWXYZ 0123456789 .,;:A
Prow abcdefghijklmnopqrstuvwxyz ABCDEFGHPJKLMNOPQRSTUVWXYZ 0123456789 .,;:P
Orow abcdefghijklmnopqrstuvwxyz ABCDEFGHOJKLMNOPQRSTUVWXYZ 0123456789 .,;:O
     *
     *
Mrow *bcdefghijklmnopqrstuvwxyz ABCDEFGHMJKLMNOPQRSTUVWXYZ 0123456789 .,;:M
Lrow *bcdefghijklmnopqrstuvwxyz ABCDEFGHLJKLMNOPQRSTUVWXYZ 0123456789 .,;:L
Jrow *bcdefghijklmnopqrstuvwxyz ABCDEFGHJJKLMNOPQRSTUVWXYZ 0123456789 .,;:J
     *
Irow abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 .,;:I
Hrow abcdefghijklmnopqrstuvwxyz ABCDEFGHHJKLMNOPQRSTUVWXYZ 0123456789 .,;:H
     *
Grow abcdefghijklmnopqrstuvwxyz ABCDEFGHGJKLMNOPQRSTUVWXYZ 0123456789 .,;:G
Erow *bcdefghijklmnopqrstuvwxyz ABCDEFGHEJKLMNOPQRSTUVWXYZ 0123456789 .,;:E
Drow abcdefghijklmnopqrstuvwxyz ABCDEFGHDJKLMNOPQRSTUVWXYZ 0123456789 .,;:D
     *

A:\>
EOF
cat >$T/scrops7.ok <<'EOF'
     *
     *
Erow abcdefghijklmnopqrstuvwxyz ABCDEFGHEJKLMNOPQRSTUVWXYZ 0123456789 .,;:E
Drow *
     *
Crow abcdefghijklmnopqrstuvwxyz ABCDEFGHCJKLMNOPQRSTUVWXYZ 0123456789 .,;:C
Arow *bcdefghijklmnopqrstuvwxyz ABCDEFGHAJKLMNOPQRSTUVWXYZ 0123456789 .,;:A
Prow abcdefghijklmnopqrstuvwxyz ABCDEFGHPJKLMNOPQRSTUVWXYZ 0123456789 .,;:P
Orow abcdefghijklmnopqrstuvwxyz ABCDEFGHOJKLMNOPQRSTUVWXYZ 0123456789 .,;:O
     *
     *
Mrow *bcdefghijklmnopqrstuvwxyz ABCDEFGHMJKLMNOPQRSTUVWXYZ 0123456789 .,;:M
Lrow *bcdefghijklmnopqrstuvwxyz ABCDEFGHLJKLMNOPQRSTUVWXYZ 0123456789 .,;:L
Jrow *bcdefghijklmnopqrstuvwxyz ABCDEFGHJJKLMNOPQRSTUVWXYZ 0123456789 .,;:J
     *
Irow abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 .,;:I
Hrow abcdefghijklmnopqrstuvwxyz ABCDEFGHHJKLMNOPQRSTUVWXYZ 0123456789 .,;:H
     *
Grow abcdefghijklmnopqrstuvwxyz ABCDEFGHGJKLMNOPQRSTUVWXYZ 0123456789 .,;:G
Erow *bcdefghijklmnopqrstuvwxyz ABCDEFGHEJKLMNOPQRSTUVWXYZ 0123456789 .,;:E
Drow abcdefghijklmnopqrstuvwxyz ABCDEFGHDJKLMNOPQRSTUVWXYZ 0123456789 .,;:D
     *

A:\>
EOF
for n in 2 7; do
	$EMU -a $T/scrops.imd -t 8 -e 'A:\>' -k "scrops $n\\r" >$T/out/scrops$n.txt
	same "insert and delete lines, the ring at start $n" $T/scrops$n.ok $T/out/scrops$n.txt
done

keys=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do keys="${keys}cmd$i\\r"; done
out=$($EMU -a "$DISK" -t 40 -e 'A:\>' -k "${keys}Hi! (x*y)=<z>?\\r")
check "scrolls past 24 lines" "CMD14?" "$out"
check "shifted punctuation, TRS-80 layout" 'A:\>Hi! (x*y)=<z>?' "$out"
printf '%s\n' "$out" | grep -q "CMD1?" &&
	{ echo "FAIL the first lines should have scrolled off"; fail=1; }


#PART


# Lobo's console codes (a Soroc IQ-120's): ESC = row col, ESC T, ESC )
# and 0Ch, cursor right. The second style is the inverse font.
printf 'a\014b\r\nab\033=\045\050XY\r\nrow2 \033Tgone\r\n\033)dim\033(\r\n' >$T/ESC.TXT
mkdisk $T/esc.imd $T/ESC.TXT
out=$($EMU -a $T/esc.imd -T -t 10 -e 'A:\>' -k 'type esc.txt\r' -p $T/out/esc.pgm)
check "0Ch moves the cursor right" "a b" "$out"
check "ESC = puts the cursor at a row and column" "ab      XY" "$out"
check "ESC T erases to the end of the line" "row2 gone" "$out"
python3 -c "import sys; t = bytes(range(0x21, 0x7f)); sys.stdout.buffer.write(b'\x1b)' + t[:47] + b'\r\n' + t[47:] + b'\x1b(\r\n')" >$T/ESC2.TXT
mkdisk $T/esc2.imd $T/ESC2.TXT
out=$($EMU -a $T/esc2.imd -T -t 10 -e 'A:\>' -k 'type esc2.txt\r')
check "-T reads every second style character, the hand-drawn ones too" \
	'!"#$%&'"'"'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNO' "$out"
check "and the rest" 'PQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~' "$out"
printf '\033*L0\r\nL1\r\nL2\r\nL3\033=! \033ENEW\033=  \033R\033=( \033Y' >$T/EL.TXT
mkdisk $T/el.imd $T/EL.TXT
out=$($EMU -a $T/el.imd -T -t 10 -e 'A:\>' -k 'type el.txt\r' | tr '\n' '|')
check "ESC * clears, ESC E inserts a line, ESC R deletes one" "NEW|L1|L2|L3|" "$out"


#PART


#PART
# Programs typed through the emulator's key socket
if [ "$(uname)" = Linux ]; then
	# The C programs, built with SDCC when it is there: CTEST
	# checks the CP/M C library, ADVENT plays, saves and restores
	if make -s -C c >/dev/null 2>&1; then
		C=c/build
		mkdisk $T/ct.imd $C/CTEST.COM $C/CLIB.SYS
		out=$(python3 tools/session.py "-a $T/ct.imd" @10)
		check "the kernel loads CLIB.SYS into B2" "C library loaded" "$out"
		out=$(python3 tools/session.py "-a $T/ct.imd -w a:$T/out/ct.imd" \
			'ctest\r' '@?name?' 'Walrus\r' '@?A:\>')
		check "C: a line from the console, read by the library" "got Walrus" "$out"
		getfile $T/out/ct.imd CTEST.LOG $T/out/CTEST.LOG
		out=$(cat $T/out/CTEST.LOG)
		check "C: initialized and zeroed data" "init 1234 zero 0" "$out"
		check "C: printf formats" "fmt [  -42] [7   ] [00be] [123456789] [str] [abc] [Z] [65535]" "$out"
		check "C: printf flags, *, precision, %p" "fmt2 [+5] [ 5] [0xff] [010] [ab    ] [   7] [03] [1234]" "$out"
		check "C: sprintf and sscanf" "sscanf 3 17 abc -5" "$out"
		check "C: sprintf to a buffer under 8000h leaves the library's code as it was" "lowbuf 702 cc-7 0 stp 1" "$out"
		check "C: sscanf with a pointer on the stack, the one not stored keeps its string" "mixed 1 5 kept" "$out"
		check "C: sscanf %s with no width, 300 bytes" "long 2 300 7" "$out"
		check "C: strcat of 780 bytes onto a short string" "cat 782 b" "$out"
		check "C: fgets leaves the bytes after the line, and n of 1 gives an empty string" "tail X 1" "$out"
		check "C: realloc to near 64K gives NULL" "big null" "$out"
		check "C: fread with size times count past 64K" "fread2 20" "$out"
		check "C: a call with nothing to copy runs with the heap full, from deeper" "full 399" "$out"
		check "C: snprintf cuts and counts" "snprintf truncat 5" "$out"
		check "C: sscanf %i, %[, widths, %n" "scan 4 12 31 abc def 15" "$out"
		check "C: sscanf %*d and %o" "scan2 4 511" "$out"
		check "C: sscanf gives EOF when the input ends before a conversion" "scan3 -1 0 -1 1" "$out"
		check "C: a text file written and read by lines" "lines 300" "$out"
		check "C: and by fread, 50 bytes at a time" "fread 2590 0" "$out"
		check "C: fseek, a write in the middle, ftell, SEEK_END" "bin 188 85 301 1024" "$out"
		check "C: a missing file" "missing null" "$out"
		check "C: a binary read ends, append after ^Z, SEEK_END buffered, rename onto a name" "ends 1024 1 1 128 -1 1" "$out"
		check "C: the string functions" "str 6 -1 0 def /c cdef 2" "$out"
		check "C: ctype" "ctype 1011 Az" "$out"
		check "C: memmove both ways, memset, memcmp" "mem aabcfghx -1" "$out"
		check "C: atoi, atol, strtoul, strtol, abs" "num -12 100000 ff -16 5" "$out"
		check "C: qsort and bsearch" "qsort 123579 7" "$out"
		check "C: setjmp and longjmp" "longjmp 42" "$out"
		check "C: malloc reuses a freed block, realloc" "heap dup reused grown" "$out"
		check "C: malloc past a small hole, and a block freed after" "hole refit above" "$out"
		check "C: malloc after realloc grew a block, in place and at the top" "regrow apart apart" "$out"
		check "C: mktime and strftime" "time 1793536496 2026-11-01 12:34:56 Sun 305" "$out"
		check "C: gmtime and asctime" "asctime Sun Nov  1 12:34:56 2026" "$out"
		check "C: strerror" "errno No such file" "$out"
		check "C: open, write, lseek, read, access" "fd 2 fd 0" "$out"
		check "C: a file's size, the directory search" "find 5" "$out"
		check "C: rename" "rename -1 0" "$out"
		check "C: ungetc and fscanf" "fscanf l 0" "$out"
		check "C: a library call gives back the interrupts on, and off" "iff 1 1 0" "$out"
		mkdisk $T/ct0.imd $C/CTEST.COM
		out=$(python3 tools/session.py "-a $T/ct0.imd" 'ctest\r' @20)
		check "C: with no CLIB.SYS a program says so" "Needs xcpmz80 and its C library, CLIB.SYS" "$out"
		# main's result is the return code (BDOS 108): RC.COM prints it,
		# 0 before, FF00h after BASE64's usage, which returns 1
		printf '\016\154\021\377\377\315\005\000\174\021\031\001\376\377\302\024\001\021\037\001\016\011\303\005\000rc=00$rc=ff$' >$T/RC.COM
		mkdisk $T/rc.imd $T/RC.COM $C/CLIB.SYS $C/BASE64.COM
		out=$($EMU -a $T/rc.imd -T -t 30 -e 'A:\>' -k 'rc\rbase64\rrc\r' | tr -d '\r')
		check "C: what main returns is the program's return code" "=rc=00 rc=ff=" \
			"=$(printf '%s\n' "$out" | grep '^rc=' | tr '\n' ' ' | sed 's/ $//')="
		mkdisk $T/adv.imd $C/CLIB.SYS $C/ADVENT.COM $C/ADVENT1.TXT $C/ADVENT2.TXT \
			$C/ADVENT3.TXT $C/ADVENT4.TXT
		out=$(python3 tools/session.py "-a $T/adv.imd" 'advent\r' @40 'n\r' @20 \
			'in\r' @20 'take lamp\r' @20 'inventory\r' @20 'suspend\r' @20 \
			'mygame\r' @40 'advent -r\r' @40 'mygame\r' @30 'xyzzy\r' @20)
		check "ADVENT reads a room from ADVENT1.TXT" "You are inside a building, a well house for a large spring." "$out"
		check "and takes the lamp" "Brass lantern" "$out"
		check "and a game saved is restored" "Game restored from mygame.adv" "$out"
		check "where it was" "You're inside building." "$out"
		check "and XYZZY goes on from there" "It is now pitch dark." "$out"
		# ZORK: MojoZork plays a version 3 story through its page
		# cache, saves and restores. The stories are Infocom's and never
		# in this repo, so this runs only when ZORK_STORIES names a
		# folder that has them. They are copied outside the repo for the
		# disk.
		ZS=${ZORK_STORIES:-/nonexistent}
		if [ -f $ZS/mini_zork_i_the_great_underground_empire.dat ] &&
		    [ -f $ZS/zork_i_the_great_underground_empire.dat ]; then
			ZT=$(mktemp -d)
			cp $ZS/mini_zork_i_the_great_underground_empire.dat $ZT/MINIZORK.DAT
			cp $ZS/zork_i_the_great_underground_empire.dat $ZT/ZORK1.DAT
			mkdisk $T/zk.imd $C/CLIB.SYS $C/ZORK.COM $ZT/MINIZORK.DAT \
				$ZT/ZORK1.DAT >/dev/null
			rm -rf $ZT
			ZP='A:\>|>|Save file name:|Restore file name:'
			out=$($EMU -a $T/zk.imd -T -t 30 -e "$ZP" \
				-k 'zork minizork.dat\ropen mailbox\rread leaflet\r')
			check "ZORK starts mini-zork" "West of House" "$out"
			check "and opens the mailbox" "Opening the small mailbox reveals a leaflet." "$out"
			check "and reads the leaflet" '"WELCOME TO ZORK, a game of adventure' "$out"
			out=$($EMU -a $T/zk.imd -T -t 60 -e "$ZP" -w a:$T/out/zk.imd \
				-k 'zork minizork.dat\ropen mailbox\rtake leaflet\rnorth\rsave\rmygame\rdrop leaflet\rinventory\rrestore\rmygame\rinventory\rlook\r')
			check "and saves a game by name" "Save file name: mygame" "$out"
			check "and drops the leaflet after" "You are empty-handed." "$out"
			check "and restores the game" "Restore file name: mygame" "$out"
			check "with the leaflet carried" "  A leaflet" "$out"
			check "where it was" "You are facing the north side of a white house." "$out"
			getfile $T/out/zk.imd MYGAME.SAV $T/out/MYGAME.SAV
			check "and the save is MYGAME.SAV" "8704" "$(wc -c <$T/out/MYGAME.SAV)"
			out=$($EMU -a $T/zk.imd -T -t 40 -e "$ZP" \
				-k 'zork zork1.dat\ropen mailbox\rread leaflet\r')
			check "ZORK plays Zork I, 84K in a 55K TPA" "Revision 88 / Serial number 840726" "$out"
			check "and reads the leaflet from its pages" '"WELCOME TO ZORK!' "$out"
			out=$($EMU -a $T/zk.imd -T -t 40 -e "$ZP" \
				-k 'zork zork1.dat\rnorth\rinventory\r')
			check "and goes north" "You are facing the north side of a white house." "$out"
			check "and takes inventory" "You are empty-handed." "$out"
			out=$($EMU -a $T/zk.imd -T -t 60 -e "$ZP" -k 'zork zork1.dat\r$verify\r')
			check "and VERIFY reads all of the story file" "The disk is correct." "$out"
		else
			echo "skip ZORK: no stories in $ZS"
		fi
		# BASE64: a file from the host, decoded, and one encoded
		# to the screen and SIOA, decoded by the host side. A file is
		# whole records, as in CP/M: the host's 11000 bytes come back as
		# 11008, the last 8 ^Z
		python3 -c "import random; r = random.Random(64)
open('$T/R2K.BIN', 'wb').write(bytes(r.randrange(256) for _ in range(2000)))"
		{ head -c 6000 $C/ADVENT1.TXT; cat $T/R2K.BIN
			head -c 3000 /dev/zero; } >$T/T.BIN
		{ cat $T/T.BIN; printf '\032\032\032\032\032\032\032\032'; } >$T/T.PAD
		$C/base64_host $T/T.BIN >$T/T.TXT 2>/dev/null
		# CP/M 3's DEVICE copies the console to SIOA for the encode
		mkdisk $T/b64.imd $C/CLIB.SYS $C/BASE64.COM ${B64X:-} $T/T.TXT \
			$T/T.BIN >/dev/null
		out=$($EMU -a $T/b64.imd -T -t 300 -e 'A:\>' -o a:$T/out/b64ser.txt \
			-k "base64 -d u.bin t.txt\\r${B64K:-}" \
			-w a:$T/out/b64.imd)
		getfile $T/out/b64.imd U.BIN $T/out/U.BIN
		n=$(cmp $T/out/U.BIN $T/T.PAD && echo same)
		check "BASE64 -D decodes the host's text" "same" "$n"
		# The host side: the echoed command and the prompt around the
		# text are passed over, a text cut short is an error with no
		# file. BASE64 -D refuses to read the file it would make, and
		# keyed in, takes the '.' line and its Enter after padding
		{ echo 'A:\>BASE64 T.BIN'; cat $T/T.TXT; echo 'A:\>'; } |
			$C/base64_host -d $T/out/H.BIN >/dev/null 2>&1
		n=$(cmp $T/out/H.BIN $T/T.BIN && echo same)
		check "base64_host -d passes over a command line and a prompt" "same" "$n"
		rm -f $T/out/H2.BIN
		head -n 20 $T/T.TXT | $C/base64_host -d $T/out/H2.BIN >/dev/null 2>&1
		n="rc=$? $(test -e $T/out/H2.BIN && echo file || echo none)"
		check "and a text cut short fails, with no file" "rc=1 none" "$n"
		# a line of 4095 characters, as long as the host's buffer less one
		sed '$d' $T/T.TXT | tr -d '\n' | python3 -c "import sys; t = sys.stdin.read()
print(t[:4095]); print(t[4095:])" | $C/base64_host -d $T/out/H3.BIN >/dev/null 2>&1
		n=$(cmp $T/out/H3.BIN $T/T.BIN && echo same)
		check "base64_host -d takes a line of 4095 characters" "same" "$n"
		printf 'AAAAAwAAAA==\r\n' >$T/BAD.TXT
		printf abc >$T/S.BIN
		$C/base64_host $T/S.BIN 2>/dev/null | head -n 1 >$T/S.TXT
		mkdisk $T/b64k.imd $C/CLIB.SYS $C/BASE64.COM $T/T.TXT $T/BAD.TXT >/dev/null
		out=$($EMU -a $T/b64k.imd -T -t 30 -e 'A:\>' \
			-k "base64 -d bad.out bad.txt\\rbase64 -d t.txt t.txt\\rbase64 -d s.bin\\E\\P\\P$(cat $T/S.TXT)\\E\\P.\\E\\P\\Pdir\\r" |
			tr -d '\r')
		check "BASE64 -D refuses a match from before the start" "not a BASE64 text, or damaged: no BAD.OUT" "$out"
		check "BASE64 -D X X refuses" "would be erased before it is read" "$out"
		check "BASE64 -D takes keys from the C library's getch" "3 bytes to" "$out"
		n="=$(echo "$out" | grep -c '^A:\\>\.\?$')="
		# only the last prompt is a bare one
		check "and leaves no '.' or empty line to the shell" "=1=" "$n"
		# A damaged hard disk: a file whose first cluster is 1, which
		# would put its record 0 on the root directory's last sector,
		# and a folder whose one cluster points to itself with no end
		# entry, which a search that finds nothing went round for ever
		cat >$T/dmg.py <<'DMGEOF'
# Damage a FAT image for the tests: dmg.py IMG root FILE.EXT CLUS sets a
# root entry's first cluster; dmg.py IMG loop FOLDER makes a folder's
# one cluster point to itself, its free entries deleted ones, no end;
# dmg.py IMG bpb OFFSET HEX writes bytes into the boot sector
import sys, struct
img, what = sys.argv[1], sys.argv[2]
b = bytearray(open(img, 'rb').read())
bps, spc, rsv, nf, rent, tot, spf = (struct.unpack_from('<H', b, 11)[0], b[13],
    struct.unpack_from('<H', b, 14)[0], b[16], struct.unpack_from('<H', b, 17)[0],
    struct.unpack_from('<H', b, 19)[0], struct.unpack_from('<H', b, 22)[0])
root = (rsv + nf * spf) * bps
data = root + rent * 32
ncl = (tot * bps - data) // (spc * bps)
f16 = ncl >= 4085
def ent(name):
    n = name.split('.')
    key = (n[0].ljust(8) + (n[1] if len(n) > 1 else '').ljust(3)).encode()
    for i in range(rent):
        if b[root + i * 32:root + i * 32 + 11] == key:
            return root + i * 32
    raise SystemExit('no ' + name)
def setfat(c, v):
    for k in range(nf):
        f = (rsv + k * spf) * bps
        if f16:
            struct.pack_into('<H', b, f + c * 2, v)
        else:
            o = f + c * 3 // 2
            w = struct.unpack_from('<H', b, o)[0]
            w = (w & 0x000F) | (v << 4) if c & 1 else (w & 0xF000) | v
            struct.pack_into('<H', b, o, w)
if what == 'bpb':
    o = int(sys.argv[3], 0)
    b[o:o + len(bytes.fromhex(sys.argv[4]))] = bytes.fromhex(sys.argv[4])
elif what == 'root':
    struct.pack_into('<H', b, ent(sys.argv[3]) + 26, int(sys.argv[4]))
else:
    c = struct.unpack_from('<H', b, ent(sys.argv[3]) + 26)[0]
    setfat(c, c)
    d = data + (c - 2) * spc * bps
    for i in range(spc * bps // 32):
        if b[d + i * 32] == 0:
            b[d + i * 32] = 0xE5
open(img, 'wb').write(b)
DMGEOF
		printf 'aaa\r\n' >$T/DA.TXT
		printf 'bbb\r\n' >$T/DB.TXT
		printf 'fff\r\n' >$T/FF.TXT
		printf 'ggg\r\n' >$T/GG.TXT
		# W.COM: open the FCB at 5Ch, write record 0 at random, close
		printf '\021\134\000\016\017\315\005\000\041\000\000\042\175\000\257\062\177\000\021\134\000\016\042\315\005\000\021\134\000\016\020\315\005\000\311' >$T/W.COM
		python3 tools/mkdisk.py $SYS --hd 1 $T/dm.img $T/DA.TXT $T/DB.TXT \
			--in F $T/FF.TXT --in G $T/GG.TXT >/dev/null
		python3 $T/dmg.py $T/dm.img root DB.TXT 1
		python3 $T/dmg.py $T/dm.img root G 1
		python3 $T/dmg.py $T/dm.img loop F
		cp $T/dm.img $T/dm0.img
		mkdisk $T/wf.imd $T/W.COM >/dev/null
		rm -f $T/out/dm.img
		out=$($EMU -a $T/wf.imd -h $T/dm.img -w h:$T/out/dm.img -T -t 120 \
			-e 'A:\>' -k 'w c:db.txt\rdir c:\\f\\zz.*\rmd c:\\g\\x\rdir c:\r' | tr -d '\r')
		check "a write to a first cluster out of range fails" "Function 34" "$out"
		n=$(cmp $T/dm0.img $T/out/dm.img && echo same)
		check "and the disk is left as it was" "same" "$n"
		check "a search in a folder that goes round ends" "No file" "$out"
		check "and the disk is there after it" "C: DA       TXT : DB       TXT" "$out"
		check "a folder whose first cluster is 1, on the root, is not entered" "No folder" "$out"
		# A BPB that does not add up is not mounted: 3 sectors a
		# cluster, 500 root entries, 1 sector a FAT for 2000 clusters
		for bpb in "0x0d 03" "0x11 f401" "0x16 0100"; do
			cp $T/dm0.img $T/bp.img
			python3 $T/dmg.py $T/bp.img bpb $bpb
			out=$($EMU -a $T/wf.imd -h $T/bp.img -T -t 30 -e 'A:\>' \
				-k 'dir c:\r' | tr -d '\r' | grep -v '^$' | grep -iA1 'dir c:' | tail -1)
			check "a BPB with $bpb is not mounted" "Disk I/O" "$out"
		done
		# ERA of a file whose first cluster is free already frees
		# nothing more, ERA and RD take the long names mtools made
		# before the entry, CD ..X is a bad name, not CD ..
		python3 tools/mkdisk.py $SYS --hd 1 $T/ln.img $T/DA.TXT $T/DB.TXT \
			--in F $T/FF.TXT >/dev/null
		mcopy -i $T/ln.img $T/DA.TXT "::A long file name.txt"
		mmd -i $T/ln.img "::Long folder name"
		python3 $T/dmg.py $T/ln.img root DB.TXT 300
		python3 - $T/ln.img <<'EOF'
import sys
b = bytearray(open(sys.argv[1], 'rb').read())
i = b.find(b'LONGFO~1   ')	# a short name the keys can type
b[i:i + 11] = b'LONGFOLD   '
open(sys.argv[1], 'wb').write(b)
EOF
		rm -f $T/out/ln.img
		out=$($EMU -a $T/wf.imd -h $T/ln.img -w h:$T/out/ln.img -T -t 120 \
			-e 'A:\>|C:\>|C:\F>' -k 'c:\rfree\rera db.txt\rfree\rera along*.txt\rrd longfold\rfree\rcd f\rcd ..x\r' |
			tr -d '\r' | grep -v '^$' | tr '\n' '|')
		check "ERA of a file on a free cluster frees no more" "C: 960K free|C:\\>era db.txt|C:\\>free|C: 960K free" "$out"
		check "and the others free theirs" "C: 964K free" "$out"
		check "CD ..X is a bad name" "C:\\F>cd ..x|Bad name|C:\\F>" "$out"
		n=$(python3 - $T/out/ln.img <<'EOF'
import sys, struct
b = open(sys.argv[1], 'rb').read()
root = (struct.unpack_from('<H', b, 14)[0] + b[16] * struct.unpack_from('<H', b, 22)[0]) * 512
print(sum(1 for i in range(struct.unpack_from('<H', b, 17)[0])
          if b[root + i * 32 + 11] == 0x0F and b[root + i * 32] not in (0, 0xE5)))
EOF
)
		check "ERA and RD take the long names before the entry" "0" "$n"
		# MD in a full root: 16 root entries, 15 taken
		python3 tools/mkdisk.py $SYS --hd 1 $T/rf.img $T/DA.TXT >/dev/null
		python3 $T/dmg.py $T/rf.img bpb 0x11 1000
		for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do mmd -i $T/rf.img ::D$i; done
		out=$($EMU -a $T/wf.imd -h $T/rf.img -T -t 60 -e 'A:\>' \
			-k 'md c:x\rmd c:y\r' | tr -d '\r' | grep -v '^$' | tr '\n' '|')
		check "MD in a full root says so" "md c:y|Root full" "$out"
		# The page module on the host, page.c and page.s on the
		# Z80 core: down and up, jumps, 3000 random edits and saves
		# checked against a model, and a file of LF lines saved as it was
		mkdir -p $T/pg $T/pz
		out=$($C/page_host $T/pg 1000 1 2>&1 && echo passed)
		check "the page module in C passes its host test" "passed" "$out"
		out=$($C/page_z80host $T/pz 1000 1 2>&1 && echo passed)
		check "and in Z80 code on the emulator's core" "passed" "$out"
		# EMACS: the arrows (ESC [ C, B, A on the socket) and
		# ^D, a search ended by ESC, ^K ^K and ^Y, ^P ^E and backspace,
		# ^X ^S saves. Then ^X ^C on a changed buffer asks first
		printf 'The first line of text.\nA second line, with a word to find.\nThe third and last line.\n' >$T/EM.TXT
		mkdisk $T/em.imd $C/CLIB.SYS $C/EMACS.COM $T/EM.TXT >/dev/null
		out=$(python3 tools/session.py "-a $T/em.imd -w a:$T/out/em.imd" \
			'emacs em.txt\r' @40 '\x1b[C' '\x1b[C' '\x1b[C' 'X' '\x1b[B' \
			'\x04' '\x13word\x1b' 'Y' '\x1b[B' '\x01\x0b\x0b' '\x1b[A' '\x19' \
			'\x10\x05' '\x08' @10 '\x18\x13' @30)
		check "EMACS shows the mode line" "== MicroEMACS 3.6 () == EM.TXT == File: EM.TXT ==" "$out"
		check "and the text, edited" "A seond line, with a wordY to find." "$out"
		check "and saves it" "[Wrote 3 lines]" "$out"
		getfile $T/out/em.imd EM.TXT $T/out/EM.TXT
		printf 'TheX first line of text.\nThe third and last line\nA seond line, with a wordY to find.\n' >$T/EM.OK
		tr -d '\r\032' <$T/out/EM.TXT >$T/out/EM.LF
		same "and the file has the moves, insert, delete, search, kill and yank" $T/EM.OK $T/out/EM.LF
		out=$(python3 tools/session.py "-a $T/em.imd" 'emacs em.txt\r' @40 \
			'more' '\x18\x03' @10)
		check "EMACS asks before it quits with a change" "Modified buffers exist. Leave anyway [y/n]?" "$out"
		out=$(python3 tools/session.py "-a $T/em.imd" 'emacs em.txt\r' @40 \
			'more' '\x18\x03' @10 'y' @20 'dir em.txt\r' @10)
		check "and on y goes back to the shell" "A: EM       TXT" "$out"
		# The back arrow rubs out in a prompt, as at A:\>:
		# ^X^W NEWX, back, .TXT writes NEW.TXT
		out=$(python3 tools/session.py "-a $T/em.imd" 'emacs em.txt\r' @40 \
			'\x18\x17' @5 'newx' '\x1b[D' '.txt\r' @20 '\x18\x03' @20 'dir new.txt\r' @10)
		check "EMACS: the back arrow rubs out in a prompt" "A: NEW      TXT" "$out"
		# A file bigger than the memory, paged through a window:
		# 1000 lines, 55K. Its end and back, a read through writes no
		# work file, a search and M-G far below the window, the mark
		# dropped, a change left in the work file, and edits at the top,
		# middle and end saved byte for byte
		awk 'BEGIN { for (i = 0; i < 1000; i++)
			printf "Line %04d of the big file, some words to fill it out.\r\n", i }' >$T/EMBIG.TXT
		mkdisk $T/emb.imd $C/CLIB.SYS $C/EMACS.COM $T/EMBIG.TXT >/dev/null
		out=$(python3 tools/session.py "-a $T/emb.imd" 'emacs embig.txt\r' @80)
		check "EMACS pages a big file" "lines, the rest paged from disk]" "$out"
		out=$(python3 tools/session.py "-a $T/emb.imd" 'emacs embig.txt\r' @80 \
			'\x1b>' @200)
		check "and goes to its end" "Line 0999 of the big file" "$out"
		out=$(python3 tools/session.py "-a $T/emb.imd -w a:$T/out/emb1.imd" \
			'emacs embig.txt\r' @80 '\x1b>' @200 '\x1b<' @200)
		check "and back" "Line 0001 of the big file" "$out"
		python3 ../tools/imd2raw.py $T/out/emb1.imd $T/out/emb1.img >/dev/null
		out=$(mdir -i $T/out/emb1.img :: 2>&1)
		check "the read through leaves the file" "EMBIG    TXT     55000" "$out"
		case "$out" in
		*'$$W'*) echo "FAIL and makes no work file:"; printf '%s\n' "$out"; fail=1 ;;
		*) echo "ok   and makes no work file" ;;
		esac
		out=$(python3 tools/session.py "-a $T/emb.imd -w a:$T/out/emb3.imd" \
			'emacs embig.txt\r' @80 '\x0e\x05 X' '\x1b>' @200)
		python3 ../tools/imd2raw.py $T/out/emb3.imd $T/out/emb3.img >/dev/null
		out=$(mdir -i $T/out/emb3.img :: 2>&1)
		check "a change the window leaves goes to the work file" 'EMBIG    $$W' "$out"
		out=$(python3 tools/session.py "-a $T/emb.imd" 'emacs embig.txt\r' @80 \
			'\x13Line 0900\x1b' @300)
		check "a search finds text far below the window" "Line 0901 of the big file" "$out"
		out=$(python3 tools/session.py "-a $T/emb.imd" 'emacs embig.txt\r' @80 \
			'\x15700\x1bg' @300)
		check "M-G goes to a line far below" "ine 0699 of the big file" "$out"
		out=$(python3 tools/session.py "-a $T/emb.imd" 'emacs embig.txt\r' @80 \
			'\x1b ' '\x1b>' @300)
		check "the mark is dropped when the window moves" "[Mark dropped, the window moved]" "$out"
		out=$(python3 tools/session.py "-a $T/emb.imd -w a:$T/out/emb2.imd" \
			'emacs embig.txt\r' @80 '\x0e\x0e\x05 TOP' '\x15500\x1bg' @300 \
			'\x05 MID' '\x1b>' @300 '\x10\x05 END' '\x18\x13' @300)
		check "edits at the top, middle and end are saved" "[Wrote 1000 lines]" "$out"
		getfile $T/out/emb2.imd EMBIG.TXT $T/out/EMBIG.TXT
		awk 'BEGIN { for (i = 0; i < 1000; i++) {
			printf "Line %04d of the big file, some words to fill it out.", i
			if (i == 2) printf " TOP"
			if (i == 499) printf " MID"
			if (i == 999) printf " END"
			printf "\r\n" } }' >$T/EMBIG.OK
		n=$(wc -c <$T/EMBIG.OK)
		printf '%0*d' $(( (128 - n % 128) % 128 )) 0 | tr 0 '\032' >>$T/EMBIG.OK
		same "byte for byte" $T/EMBIG.OK $T/out/EMBIG.TXT
		python3 ../tools/imd2raw.py $T/out/emb2.imd $T/out/emb2.img >/dev/null
		out=$(mdir -i $T/out/emb2.img :: 2>&1)
		case "$out" in
		*'$$'*) echo "FAIL and leaves no work or temporary file:"; printf '%s\n' "$out"; fail=1 ;;
		*) echo "ok   and leaves no work or temporary file" ;;
		esac
		# VI: STEVIE. w x, j and i, $ and a, 0 k l l x, the arrows
		# (ESC [ B, C, D, A on the socket) and x and i, G dd, 1G p, o
		# then u, a search by a regexp then x, :w
		printf 'one two three\nfour five six\nseven eight nine\nten eleven twelve\n' >$T/VI.TXT
		mkdisk $T/vi.imd $C/CLIB.SYS $C/VI.COM $T/VI.TXT >/dev/null
		out=$(python3 tools/session.py "-a $T/vi.imd -w a:$T/out/vi.imd" \
			'vi vi.txt\r' @40 'w' 'x' 'j' 'iA\x1b' '$' 'aB\x1b' '0' 'k' 'l' 'l' \
			'x' '\x1b[B' '\x1b[C' 'x' '\x1b[D' '\x1b[A' 'iC\x1b' 'G' 'dd' '1G' \
			'p' 'oNEW\x1b' 'u' '/e.g\r' 'x' ':w\r' @20)
		check "VI shows the text, edited" "fouA five sixB" "$out"
		check "and saves it" '"VI.TXT" 4 lines, 62 characters' "$out"
		getfile $T/out/vi.imd VI.TXT $T/out/VI.TXT
		{ printf 'onC wo three\r\nten eleven twelve\r\nfouA five sixB\r\nseven ight nine\r\n'
			printf '%062d' 0 | tr 0 '\032'; } >$T/VI.OK
		same "and the file has the moves, insert, delete, put, undo and search" \
			$T/VI.OK $T/out/VI.TXT
		out=$(python3 tools/session.py "-a $T/vi.imd" 'vi vi.txt\r' @40 ':q\r' @20 \
			'dir vi.txt\r' @10)
		check "VI quits on :q with no change" "A: VI       TXT" "$out"
		out=$(python3 tools/session.py "-a $T/vi.imd" 'vi vi.txt\r' @40 'x' ':q\r' @20)
		check "and on a change refuses" "No write since last change (use ! to override)" "$out"
		out=$(python3 tools/session.py "-a $T/vi.imd -w a:$T/out/vi2.imd" \
			'vi vi.txt\r' @40 'x' ':q!\r' @20 'dir vi.txt\r' @10)
		check "and :q! quits all the same" "A: VI       TXT" "$out"
		getfile $T/out/vi2.imd VI.TXT $T/out/VI2.TXT
		same "without writing the file" $T/VI.TXT $T/out/VI2.TXT
		# The back arrow rubs out while typing and on the : line, as at
		# A:\>: XYZ, two back, Q, then :wqx, one back
		out=$(python3 tools/session.py "-a $T/vi.imd -w a:$T/out/vi3.imd" \
			'vi vi.txt\r' @40 'iXYZ' '\x1b[D' '\x1b[D' 'Q\x1b' ':wqx' '\x1b[D' '\r' @20 \
			'dir vi.txt\r' @10)
		check "VI: the back arrow rubs out on the : line" "A: VI       TXT" "$out"
		getfile $T/out/vi3.imd VI.TXT $T/out/VI3.TXT
		check "and while typing" "XQone two three" "$(head -1 $T/out/VI3.TXT)"
		# A file bigger than the memory, paged through a window:
		# 1000 lines, 55K. Its end and back, a read through writes no
		# work file, a change left in the work file, a search, G and :N
		# far below the window, undo after the window moved, ranges
		# bigger than the window refused, and edits at the top, middle
		# and end and a :s over a range saved byte for byte, the old
		# file kept as .BAK with :set bk
		awk 'BEGIN { for (i = 0; i < 1000; i++)
			printf "Line %04d of the big file, some words to fill it out.\r\n", i }' >$T/VIBIG.TXT
		mkdisk $T/vib.imd $C/CLIB.SYS $C/VI.COM $T/VIBIG.TXT >/dev/null
		out=$(python3 tools/session.py "-a $T/vib.imd" 'vi vibig.txt\r' @80 'G' @200 \
			'\x07' @10)
		check "VI pages a big file, and goes to its end" "ine 0999 of the big file" "$out"
		check "and counts its lines" '"VIBIG.TXT" line 1000 of 1000 -- 100 % --' "$out"
		out=$(python3 tools/session.py "-a $T/vib.imd -w a:$T/out/vib1.imd" \
			'vi vibig.txt\r' @80 'G' @200 '1G' @200 '\x07' @10)
		check "and back" '"VIBIG.TXT" line 1 of 1000 -- 0 % --' "$out"
		python3 ../tools/imd2raw.py $T/out/vib1.imd $T/out/vib1.img >/dev/null
		out=$(mdir -i $T/out/vib1.img :: 2>&1)
		check "the read through leaves the file" "VIBIG    TXT     55000" "$out"
		case "$out" in
		*'$$W'*) echo "FAIL and makes no work file:"; printf '%s\n' "$out"; fail=1 ;;
		*) echo "ok   and makes no work file" ;;
		esac
		out=$(python3 tools/session.py "-a $T/vib.imd -w a:$T/out/vib2.imd" \
			'vi vibig.txt\r' @80 'jA X\x1b' 'G' @200)
		python3 ../tools/imd2raw.py $T/out/vib2.imd $T/out/vib2.img >/dev/null
		out=$(mdir -i $T/out/vib2.img :: 2>&1)
		check "a change the window leaves goes to the work file" 'VIBIG    $$W' "$out"
		out=$(python3 tools/session.py "-a $T/vib.imd" 'vi vibig.txt\r' @80 \
			'/Line 0900\r' '@/ine 0900 of the big' '\x07' @10)
		check "a search finds text far below the window" '"VIBIG.TXT" line 901 of 1000' "$out"
		out=$(python3 tools/session.py "-a $T/vib.imd" 'vi vibig.txt\r' @80 \
			':700\r' @200 '\x07' @10)
		check ":N goes to a line far below" '"VIBIG.TXT" line 700 of 1000' "$out"
		out=$(python3 tools/session.py "-a $T/vib.imd -w a:$T/out/vib3.imd" \
			'vi vibig.txt\r' @80 '3G' 'dd' 'G' @200 'u' @200 ':w\r' @300)
		check "undo works after the window moved" '"VIBIG.TXT" 1000 lines' "$out"
		getfile $T/out/vib3.imd VIBIG.TXT $T/out/VIBIG3.TXT
		cp $T/VIBIG.TXT $T/VIBIG3.OK
		n=$(wc -c <$T/VIBIG3.OK)
		printf '%0*d' $(( (128 - n % 128) % 128 )) 0 | tr 0 '\032' >>$T/VIBIG3.OK
		same "and puts the line back" $T/VIBIG3.OK $T/out/VIBIG3.TXT
		# :r and :e with a file paged: a file read into a paged one
		# frees parts of the window, one too big for the memory goes in
		# not at all and leaves the text unchanged, and :e goes from a
		# paged file to a small or a paged one and back
		awk 'BEGIN { for (i = 0; i < 30; i++)
			printf "Medium %04d of a file read into the big one.\r\n", i }' >$T/VIMED.TXT
		awk 'BEGIN { for (i = 0; i < 800; i++)
			printf "Other %04d of the second big file, more words to fill.\r\n", i }' >$T/VIOTH.TXT
		printf 'small one\r\nsmall two\r\nsmall three\r\n' >$T/VISML.TXT
		mkdisk $T/vie.imd $C/CLIB.SYS $C/VI.COM $T/VIBIG.TXT $T/VIMED.TXT \
			$T/VIOTH.TXT $T/VISML.TXT >/dev/null
		out=$(python3 tools/session.py "-a $T/vie.imd -w a:$T/out/vie1.imd" \
			'vi vibig.txt\r' @80 '500G' @100 ':r vimed.txt\r' @150 ':w\r' @300)
		check ":r reads a file into a paged one" '"VIBIG.TXT" 1030 lines' "$out"
		getfile $T/out/vie1.imd VIBIG.TXT $T/out/VIBIGR.TXT
		{ head -n 500 $T/VIBIG.TXT; cat $T/VIMED.TXT; tail -n 500 $T/VIBIG.TXT; } >$T/VIBIGR.OK
		n=$(wc -c <$T/VIBIGR.OK)
		printf '%0*d' $(( (128 - n % 128) % 128 )) 0 | tr 0 '\032' >>$T/VIBIGR.OK
		same "and saves it in its place" $T/VIBIGR.OK $T/out/VIBIGR.TXT
		out=$(python3 tools/session.py "-a $T/vie.imd" 'vi vibig.txt\r' @80 \
			'3G' ':r vioth.txt\r' @300)
		check ":r of a big file into a paged one is refused" '"vioth.txt" Out of memory, not read' "$out"
		out=$(python3 tools/session.py "-a $T/vie.imd" 'vi vibig.txt\r' @80 \
			'3G' ':r vioth.txt\r' @300 '\x07' @10)
		check "and leaves the text unchanged" '"VIBIG.TXT" line 3 of 1000 -- 0 % --' "$out"
		out=$(python3 tools/session.py "-a $T/vie.imd" 'vi visml.txt\r' @40 \
			':r vibig.txt\r' @200)
		check ":r of a big file into a small one is refused" '"vibig.txt" Out of memory, not read' "$out"
		out=$(python3 tools/session.py "-a $T/vie.imd" 'vi visml.txt\r' @40 \
			':r vibig.txt\r' @200 '\x07' @10)
		check "and leaves it unchanged" '"VISML.TXT" line 1 of 3 -- 33 % --' "$out"
		out=$(python3 tools/session.py "-a $T/vie.imd -w a:$T/out/vie2.imd" \
			'vi vibig.txt\r' @80 'jA X\x1b' 'G' @200 ':e! visml.txt\r' @100 '\x07' @10)
		check ":e! leaves a changed paged file for a small one" '"visml.txt" line 1 of 3' "$out"
		python3 ../tools/imd2raw.py $T/out/vie2.imd $T/out/vie2.img >/dev/null
		out=$(mdir -i $T/out/vie2.img :: 2>&1)
		check "the paged file is as it was" "VIBIG    TXT     55000" "$out"
		case "$out" in
		*'$$W'*) echo "FAIL and its work file goes:"; printf '%s\n' "$out"; fail=1 ;;
		*) echo "ok   and its work file goes" ;;
		esac
		out=$(python3 tools/session.py "-a $T/vie.imd" 'vi vibig.txt\r' @80 \
			':e vioth.txt\r' @100 'G' @200 '\x07' @10)
		check ":e goes from a paged file to another" '"vioth.txt" line 800 of 800' "$out"
		out=$(python3 tools/session.py "-a $T/vie.imd" 'vi visml.txt\r' @40 \
			':e vibig.txt\r' @100 'G' @200 '\x07' @10)
		check ":e goes from a small file to a paged one" '"vibig.txt" line 1000 of 1000' "$out"
		out=$(python3 tools/session.py "-a $T/vib.imd" 'vi vibig.txt\r' @80 \
			':1,$d\r' @100)
		check "a range bigger than the window is refused" "Range bigger than the window" "$out"
		out=$(python3 tools/session.py "-a $T/vib.imd" 'vi vibig.txt\r' @80 \
			'dG' @100)
		check "and so is a motion past it" "Range bigger than the window" "$out"
		out=$(python3 tools/session.py "-a $T/vib.imd -w a:$T/out/vib4.imd" \
			'vi vibig.txt\r' @80 'jj' 'A TOP\x1b' ':5,6s/Line/Row/\r' @50 \
			':500\r' @200 'A MID\x1b' 'G' @200 'A END\x1b' @50 ':set bk\r' @20 ':w\r' @600)
		check "edits at the top, middle and end are saved" '"VIBIG.TXT" 1000 lines' "$out"
		getfile $T/out/vib4.imd VIBIG.TXT $T/out/VIBIG.TXT
		awk 'BEGIN { for (i = 0; i < 1000; i++) {
			printf "%s %04d of the big file, some words to fill it out.",
				(i == 4 || i == 5) ? "Row" : "Line", i
			if (i == 2) printf " TOP"
			if (i == 499) printf " MID"
			if (i == 999) printf " END"
			printf "\r\n" } }' >$T/VIBIG.OK
		n=$(wc -c <$T/VIBIG.OK)
		printf '%0*d' $(( (128 - n % 128) % 128 )) 0 | tr 0 '\032' >>$T/VIBIG.OK
		same "byte for byte" $T/VIBIG.OK $T/out/VIBIG.TXT
		python3 ../tools/imd2raw.py $T/out/vib4.imd $T/out/vib4.img >/dev/null
		out=$(mdir -i $T/out/vib4.img :: 2>&1)
		check "and the old file is kept as .BAK" "VIBIG    BAK     55000" "$out"
		case "$out" in
		*'$$'*) echo "FAIL and leaves no work or temporary file:"; printf '%s\n' "$out"; fail=1 ;;
		*) echo "ok   and leaves no work or temporary file" ;;
		esac
		# The apps disk: boots, loads CLIB.SYS, and runs the programs on
		# it, on 8-inch and 5.25-inch
		make -s apps >/dev/null 2>&1
		out=$(python3 tools/session.py "-a build/apps.imd" @10 'dir\r' @20 'zork\r' @20)
		check "the apps disk loads CLIB.SYS" "C library loaded" "$out"
		check "and has the C programs" "CLIB     SYS : VI       COM" "$out"
		check "and ZORK, with no story" "Usage: ZORK STORY.DAT, a Z-machine version 3 story" "$out"
		out=$($EMU -a build/apps.imd -T -t 60 -e 'A:\>|instructions?' -k 'advent\r')
		check "and ADVENT, with its text" "Would you like instructions?" "$out"
		out=$(python3 tools/session.py "-D 1 -a build/apps_525.imd" @10 'clock\r' @20)
		check "the 5.25-inch apps disk loads CLIB.SYS" "C library loaded" "$out"
		check "and runs CLOCK" "$(date +%m/%d/%y) " "$out"
		out=$(python3 tools/session.py "-D 1 -a build/apps_525.imd" @10 'vi x.txt\r' @40)
		check "and VI" '"X.TXT" [New File]' "$out"
	else
		echo "skip the C programs: no SDCC"
	fi
else
	echo "skip the tests through the key socket: Linux only"
fi
#PART


#PART

# emu/test_iff.c runs iffget's bytes against the NMOS quirk: these
# must be the ones assembled, the jump aside
if python3 -c "
import re, sys
sys.exit(not re.search(rb'\xed\x57\xea..\xed\x57\xf3\x3e\x00\xe0\x3d\xc9',
                       open('$SYS', 'rb').read(), re.S))"; then
	echo "ok   iffget is what emu/test_iff.c tests"
else
	echo "FAIL iffget differs from emu/test_iff.c"
	fail=1
fi

# CLOCK reads the clock chip. The emulator's
# clock starts at the host's time.
mkdisk $T/clk.imd build/CLOCK.COM
out=$($EMU -a $T/clk.imd -T -t 15 -e 'A:\>' -k 'clock\r')
check "CLOCK reads the date from the clock chip" "$(date +%m/%d/%y) " "$out"
n=$(printf '%s\n' "$out" | grep -aEc '^[0-9]{2}/[0-9]{2}/[0-9]{2} [0-2][0-9]:[0-5][0-9]:[0-5][0-9]$')
check "and the time, every digit" "1" "$n"

# BENCH reads BENCH.DAT over and over for 30 clock seconds.
# With the drives' mechanics (-M) a pass of 40000 bytes takes seconds.
head -c 40000 /dev/zero | tr '\000' 'x' >$T/BENCH.DAT
mkdisk $T/bn.imd build/BENCH.COM $T/BENCH.DAT >/dev/null
out=$($EMU -a $T/bn.imd -T -M -t 60 -e 'A:\>' -k 'dir\rbench\E\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P')
n=$(printf '%s
' "$out" | grep -aEc '^x{16} [1-9][0-9]* [1-9][0-9]* (3[0-9]|[4-9][0-9])$')
check "BENCH prints the tag, passes, records and seconds, 30 or more" "1" "$n"
mkdisk $T/nb.imd build/BENCH.COM >/dev/null
out=$($EMU -a $T/nb.imd -T -t 20 -e 'A:\>' -k 'dir\rbench\E\P\P\P')
check "BENCH says No file" "No file" "$out"

# A read on a disk at interleave 1 takes the whole track in one FDC
# command, from the next sector to come round, into a track buffer:
# faster than a sector a command at any interleave. Other disks read a
# sector at a time, as fast as before. 1.44M as a PC lays it out, with
# no skew, its 18 sectors read 17 and 1, the last a turn later, as the
# track buffer holds 17 (I260). Records a second, at least:
benchrate() {	# image, emulator options: BENCH's records a second
	$EMU $2 -a $1 -T -M -L -t 60 -e 'A:\>' -k 'bench\E\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P\P' |
		awk '/^xxxxxxxxxxxxxxxx / { r = int($3 / $4) } /^Lost Data: / { l = $3 } END { print r, l }'
}
for b in "720 1 70 --525 720" "720 2 55 --525 720" "8in 1 120" "8in 3 85" \
	"1440 1 75 --pc 1440 --skew 0 --hskew 0"; do
	set -- $b
	name=$1 ilv=$2 floor=$3
	shift 3
	python3 tools/mkdisk.py $SYS "$@" --ilv $ilv $T/tb.imd build/BENCH.COM $T/BENCH.DAT >/dev/null
	D=; [ $name = 720 ] && D="-D 1"
	set -- $(benchrate $T/tb.imd "$D")
	fast=no; [ "${1:-0}" -ge $floor ] && fast=yes
	check "BENCH on $name at interleave $ilv reads $floor records a second or more" "yes" "$fast ($1)"
	check "with no Lost Data" "0" "${2:-x}"
done

# The track buffer never gives what a write has replaced. TBW.COM reads
# TBX.TXT's last record, for the FAT, and its first, which reads the
# track into the buffer, writes its first sector, reads six more from
# the buffer, so that the cache writes the first one out, then reads the
# first again. TBX.TXT starts a track on this disk.
cat >$T/tbw.asm <<'ASM'
	org	100h
	ld	c,15			; open
	ld	de,fcb
	call	5
	inc	a
	jp	z,fail
	ld	hl,31			; the last record: the FAT into the cache
	ld	(fcb+33),hl
	ld	c,33
	ld	de,fcb
	call	5
	ld	hl,0			; the first: the track into the buffer
	ld	(fcb+33),hl
	ld	c,33
	ld	de,fcb
	call	5
	ld	hl,0
wl:	ld	(fcb+33),hl		; 'b' over the first sector's records
	push	hl
	ld	hl,80h
	ld	de,81h
	ld	bc,127
	ld	(hl),'b'
	ldir
	ld	c,34
	ld	de,fcb
	call	5
	pop	hl
	or	a
	jp	nz,fail
	inc	hl
	ld	a,l
	cp	4
	jr	nz,wl
rl:	ld	(fcb+33),hl		; six sectors more, for the cache
	push	hl
	ld	c,33
	ld	de,fcb
	call	5
	pop	hl
	or	a
	jp	nz,fail
	ld	de,4
	add	hl,de
	ld	a,l
	cp	28
	jr	nz,rl
	ld	hl,0			; the first again
	ld	(fcb+33),hl
	ld	c,33
	ld	de,fcb
	call	5
	or	a
	jp	nz,fail
	ld	de,80h
	ld	b,128
cl:	ld	a,(de)
	cp	'b'
	jr	nz,stale
	inc	de
	djnz	cl
	ld	de,okm
	jr	pr
stale:	ld	de,stm
	jr	pr
fail:	ld	de,flm
pr:	ld	c,9
	call	5
	ld	c,16
	ld	de,fcb
	call	5
	rst	0
okm:	db	"TB NEW",13,10,"$"
stm:	db	"TB STALE",13,10,"$"
flm:	db	"TB FAIL",13,10,"$"
fcb:	db	0,"TBX     TXT"
	ds	24,0
ASM
rm -f $T/TBW.COM
(cd $T && sjasmplus --nologo --msg=war --raw=TBW.COM tbw.asm >/dev/null)
head -c 4096 /dev/zero | tr '\000' 'a' >$T/TBX.TXT
python3 tools/mkdisk.py $SYS --525 720 --ilv 1 $T/tb.imd $T/TBW.COM $T/TBX.TXT >/dev/null
for m in -M ""; do	# with the drives' mechanics, and with none, where the
	# emulator ends a run at the end of the track at once
	out=$($EMU -D 1 -a $T/tb.imd -T $m -t 40 -e 'A:\>' -k 'tbw\r')
	check "a sector written over is read back new, not from the track buffer ($m)" "TB NEW" "$out"
done

# A sector the FDC can not read later on the track does not fail a read
# of a good one before it: the run fails, and the sector is read alone.
# tbad.py marks the last sector of TBZ.TXT's track bad (IMD type 05h).
printf 'the good sector\r\n\032' >$T/TBZ.TXT
python3 tools/mkdisk.py $SYS --525 720 --ilv 1 $T/tb.imd --raw $T/tb.img $T/TBZ.TXT >/dev/null
cat >$T/tbad.py <<'PY'
import struct, sys
imd, img, name = sys.argv[1:]
r = open(img, 'rb').read()
res, nf, rootn, _, _, spf, spt, heads = struct.unpack_from('<HBHHBHHH', r, 14)
rootsec = res + nf * spf
datasec = rootsec + (rootn * 32 + 511) // 512
spc = r[13]
for o in range(rootsec * 512, datasec * 512, 32):
    if r[o:o + 11] == name.encode():
        lba = datasec + (struct.unpack_from('<H', r, o + 26)[0] - 2) * spc
        break
trk, pos = divmod(lba, spt)
assert pos < spt - 1, 'the file is the last on its track'
b = bytearray(open(imd, 'rb').read())
i = b.index(0x1A) + 1
t = 0
while i < len(b):
    head, n, size = b[i + 2], b[i + 3], b[i + 4]
    i += 5
    ids = b[i:i + n]
    i += n * (1 + (head >> 7 & 1) + (head >> 6 & 1))
    for k in range(n):
        ty = b[i]
        if t == trk and ids[k] == max(ids):
            b[i] = {1: 5, 2: 6}[ty]
        i += 1 + ((128 << size) if ty in (1, 3, 5, 7) else 1 if ty else -1)
    t += 1
open(imd, 'wb').write(b)
print(trk, pos)
PY
python3 $T/tbad.py $T/tb.imd $T/tb.img 'TBZ     TXT' >/dev/null
for m in -M ""; do
	out=$($EMU -D 1 -a $T/tb.imd -T $m -t 30 -e 'A:\>' -k 'type tbz.txt\r')
	check "a bad sector later on the track does not fail a read before it ($m)" "the good sector" "$out"
	n=$(printf '%s\n' "$out" | grep -aciE 'error|I/O')
	check "and gives no error" "0" "$n"
done

# MORE: a screen of 23 lines, Space the next, Enter one more, Q
# stops. A tab goes to the next 8 columns, a long line wraps.
for i in $(seq 1 60); do printf 'line %d\r\n' $i; done >$T/MT.TXT
printf '\tx\t%0100d\r\nlast\r\n\032' 0 >>$T/MT.TXT
mkdisk $T/more.imd build/MORE.COM $T/MT.TXT >/dev/null
last2() {	# the last two lines with text on them, on one line
	printf '%s\n' "$1" | grep -v '^ *$' | tail -2 | tr '\n' ' '
}
out=$(python3 tools/session.py "-a $T/more.imd" 'more mt.txt\r' @20 ' ' @20 '\r' @20)
check "MORE stops at --More--, Space a screen, Enter a line" "line 47 --More-- " "$(last2 "$out")"
out=$(python3 tools/session.py "-a $T/more.imd" 'more mt.txt\r' @20 ' ' @20 ' ' @20)
check "and shows tabs and the end" "        x       0000" "$out"
check "and ends at the end" "last A:\> " "$(last2 "$out")"
out=$(python3 tools/session.py "-a $T/more.imd" 'more mt.txt\r' @20 'q' @20)
check "and Q stops it" "line 23 A:\> " "$(last2 "$out")"


#PART

# BOLD.FNT, the system's font with its styles swapped: thin text
make -s build/BOLD.FNT
mkdisk $T/bf.imd build/LDFONT.COM build/BOLD.FNT >/dev/null
out=$($EMU -a $T/bf.imd -T -t 20 -p $T/out/bf.pgm -e 'A:\>' -k 'ldfont bold\rdir\r')
check "LDFONT loads BOLD.FNT" "Font loaded" "$out"
printf '%s\n' "$out" >$T/out/bf.txt
r=$(python3 ../emu/test_frame.py $T/out/bf.pgm $T/out/bf.txt build/BOLD.FNT)
check "and the screen shows its thin main style" ", 0 rows wrong" "$r"


#PART

# 5-inch steps: 6 ms, the FDC's rate 0, with DIP switch 1 down, 30 ms,
# rate 3, with it up. The boot ROM's own seeks are 1Bh either way.
[ -f build/xcpmz80_525.imd ] || make -s 525 >/dev/null
$EMU -T -D 1 -a build/xcpmz80_525.imd -G $T/st6.log -e 'A:\>' -k 'DIR\r' -t 8 >/dev/null 2>&1
$EMU -T -D 0x81 -a build/xcpmz80_525.imd -G $T/st30.log -e 'A:\>' -k 'DIR\r' -t 8 >/dev/null 2>&1
check "5-inch: the kernel restores at 6 ms" "cmd 08" "$(cat $T/st6.log)"
check "and seeks at 6 ms" "cmd 18" "$(cat $T/st6.log)"
check "with DIP switch 1 up, none at 6 ms" "count 0" "count $(grep -c 'cmd 08\|cmd 18' $T/st30.log)"
check "but restores at 30" "cmd 0b drive 0 cyl 2" "$(cat $T/st30.log)"

# A system older than its source makes no disk
mkdir -p $T/st/src $T/st/build
cp $SYS $T/st/build/xcpmz80.sys
touch -d 2000-01-01 $T/st/build/xcpmz80.sys
touch $T/st/src/xcpmz80.asm
out=$(python3 tools/mkdisk.py $T/st/build/xcpmz80.sys $T/st/a.imd 2>&1)
check "mkdisk.py refuses a system older than src/" "older than src/" "$out"
check "and writes no disk" "none" "$(test -e $T/st/a.imd && echo made || echo none)"
touch $T/st/build/xcpmz80.sys
python3 tools/mkdisk.py $T/st/build/xcpmz80.sys $T/st/a.imd
check "and takes it once built" "made" "$(test -s $T/st/a.imd && echo made)"

# COPY fills the TPA from the source, then writes it all, so between
# floppies the heads move once a fill: 150001 bytes, three
# fills, to B: and to a new name on A:, byte exact and the FATs clean.
python3 -c "import random; r = random.Random(191); open('$T/HUGE.DAT', 'wb').write(bytes(r.randrange(256) for _ in range(150001)))"
head -c 61440 $T/HUGE.DAT >$T/MID.DAT
python3 tools/mkdisk.py $SYS --525 720 $T/cpa.imd $T/HUGE.DAT $T/MID.DAT >/dev/null
python3 tools/mkdisk.py $SYS --525 720 $T/cpb.imd >/dev/null
rm -f $T/out/cpa.imd $T/out/cpb.imd
$EMU -T -D 1 -a $T/cpa.imd -b $T/cpb.imd -w a:$T/out/cpa.imd -w b:$T/out/cpb.imd -t 600 \
	-e 'A:\>' -k 'COPY HUGE.DAT B:\rCOPY HUGE.DAT COPY2.DAT\r' >/dev/null 2>&1
getfile $T/out/cpb.imd HUGE.DAT $T/out/HUGE.B
getfile $T/out/cpa.imd COPY2.DAT $T/out/HUGE.A
same "COPY of 150001 bytes to B: is byte exact" $T/HUGE.DAT $T/out/HUGE.B
same "and to a new name on A:" $T/HUGE.DAT $T/out/HUGE.A
fatok "and B: is clean" $T/out/cpb.img
fatok "and A: is clean" $T/out/cpa.img
out=$($EMU -T -D 1 -M -a $T/cpa.imd -b $T/cpb.imd -t 300 -e 'A:\>' -k 'COPY MID.DAT B:\r' 2>&1)
n=$(echo "$out" | sed -n 's/.*sectors, \([0-9]*\) steps.*/\1/p')
check "and 60K from A: to B: takes under 300 steps" "under" "$( [ "${n:-9999}" -lt 300 ] && echo under || echo "$n steps")"

# Folders: MD, CD, PWD and RD, the prompt, DIR and LS, paths in
mkdir -p $T/o2
# COPY, TYPE and ERA, programs from the root, a folder past its first
# cluster, the errors, and what mtools sees
out=$($EMU -a "$DISK" -t 60 -e 'A:\>|A:\GAMES>|A:\GAMES\OLD>' -w a:$T/out/fd1.imd \
	-k 'md games\rcopy more.com games\\m.com\rcd games\rmd old\rcd old\rpwd\rcd ..\rdir\rls\r')
check "MD and CD: the prompt shows the folder" 'A:\GAMES>md old' "$out"
check "CD into a folder in a folder" 'A:\GAMES\OLD>pwd' "$out"
check "CD .. goes up" 'A:\GAMES>dir' "$out"
check "DIR shows a folder as NAME\\" "A: M        COM : OLD\\" "$out"
check "LS shows <DIR>" "OLD\\         <DIR>" "$out"
out=$($EMU -a $T/out/fd1.imd -t 60 -e 'A:\>|A:\GAMES>' -w a:$T/o2/fd.imd \
	-k 'cd games\rcopy \\clock.com c.com\rcd \\\rdir\rtype games\\nothere.txt\rcd nothere\rmd games\rmd x*\rrd games\r')
check "the root's DIR shows the folder" "A: GAMES\\" "$out"
check "a path to no file" "No file" "$out"
check "CD to no folder" "No folder" "$out"
check "MD of a name taken" "Exists" "$out"
check "MD of a wildcard" "Bad name" "$out"
check "RD of a folder with files" "Not empty" "$out"
python3 ../tools/imd2raw.py $T/o2/fd.imd $T/o2/fd.img >/dev/null
fatok "the folders are a clean FAT volume" $T/o2/fd.img
out=$(mdir -/ -i $T/o2/fd.img ::GAMES 2>&1)
check "mtools reads the folder and the folder in it" "Directory for ::/GAMES/OLD" "$out"
check "and the copies in it" "C        COM       131" "$out"
mcopy -o -i $T/o2/fd.img ::GAMES/M.COM $T/out/M.COM
same "COPY into a folder is byte exact" build/MORE.COM $T/out/M.COM
out=$($EMU -a $T/o2/fd.imd -t 30 -e 'A:\>|A:\GAMES>' -k 'cd games\rc\rclock\r')
check "COPY \\NAME from the root, and it and CLOCK, not in the folder, run" "2" \
	"$(printf '%s\n' "$out" | grep -c '^[0-9][0-9]/[0-9][0-9]/[0-9][0-9] ')"
check "the folder stays through the warm boots" 'A:\GAMES>clock' "$out"
out=$($EMU -a $T/o2/fd.imd -t 30 -e 'A:\>' -k 'save 1 games\rren games=more.com\rdir\r')
check "SAVE to a folder's name makes no file" "No file" "$out"
check "nor does REN" "No file, or the new name is taken" "$out"
check "and the folder is still alone" "A: GAMES\\" "$out"
out=$($EMU -a $T/o2/fd.imd -t 30 -e 'A:\>|A:\GAMES>' \
	-k 'copy clock.com games\rcopy *.fnt \\games\rcd games\rdir\r')
check "COPY to a folder's name puts the file in it" "A: M        COM : OLD\\         : C        COM : CLOCK    COM" "$out"
check "and wildcards to one" "A: XCPM     FNT : THIN     FNT : INVERSE  FNT" "$out"

# MV into a folder and out again moves the entry, in one folder it
# renames, and to another drive it copies and erases
cp "$DISK" $T/mvb.imd
out=$($EMU -a "$DISK" -b $T/mvb.imd -t 60 -e 'A:\>' -w a:$T/out/mv.imd -w b:$T/out/mvb.imd \
	-k 'md games\rmv more.com games\rmv clock.com games\\c.com\rmv games\\c.com \\\rmv glyphs.com gl.com\rmv xcpm.fnt b:x.fnt\rdir\rdir games\\\rdir b:\r')
check "MV into a folder" "A: MORE     COM" "$out"
check "MV in one folder renames, out of a folder to the top" "A: LDFONT   COM : GL       COM : C        COM : BENCH    COM" "$out"
check "MV to another drive, and the source goes" "A: THIN     FNT : INVERSE  FNT : GAMES\\" "$out"
check "and it is there" "B: X        FNT" "$out"
python3 ../tools/imd2raw.py $T/out/mv.imd $T/out/mv.img >/dev/null
fatok "the moves leave a clean FAT volume" $T/out/mv.img
mcopy -o -i $T/out/mv.img ::GAMES/MORE.COM $T/out/MV.COM
same "and the moved file is byte exact" build/MORE.COM $T/out/MV.COM
# MV to another drive refuses a name taken there, as on one drive
out=$($EMU -a $T/out/mv.imd -b $T/out/mvb.imd -T -t 30 -e 'A:\>' \
	-k 'mv thin.fnt b:x.fnt\rdir thin.fnt\r')
check "MV to another drive refuses a name taken there" "No file, or the new name is taken" "$out"
check "and leaves the source" "A: THIN     FNT" "$out"
python3 ../tools/imd2raw.py $T/out/mvb.imd $T/out/mvb.img >/dev/null
mcopy -o -i $T/out/mvb.img ::X.FNT $T/out/MVX.FNT
same "and the file there as it was" build/XCPM.FNT $T/out/MVX.FNT

# AUTOEXEC.BAT runs at a cold boot, and NAME.BAT by its name
printf 'dir *.fnt\r\nver\r\n' >$T/AUTOEXEC.BAT
mkdisk $T/ae.imd build/XCPM.FNT $T/AUTOEXEC.BAT >/dev/null
out=$($EMU -a $T/ae.imd -T -t 20 -e 'A:\>' -k 'autoexec\r')
check "AUTOEXEC.BAT runs at boot" "A:\>DIR *.FNT" "$out"
check "and by its name" "A:\>autoexec" "$out"
check "twice in all" "2" "$(printf '%s\n' "$out" | grep -c 'A: XCPM     FNT')"

# On a write-protected A: there is no A:$$$.SUB: AUTOEXEC.BAT runs from
# memory, first line first, through the warm boot of a program
printf 'dir *.fnt\r\nclock\r\nver\r\n' >$T/AUTOEXEC.BAT
mkdisk $T/aw.imd build/XCPM.FNT build/CLOCK.COM $T/AUTOEXEC.BAT >/dev/null
out=$($EMU -a $T/aw.imd -R a -T -t 20 -e 'A:\>' -k 'dir\r' | tr -d '\r')
check "AUTOEXEC.BAT on a write-protected A: runs every line, in order" \
	"=DIR *.FNT CLOCK VER=" \
	"=$(printf '%s\n' "$out" | sed -n 's/^A:\\>\([A-Z].*\)/\1/p' | tr '\n' ' ' | sed 's/ $//')="

# A COPY that fills the disk erases the part it wrote
head -c 500000 /dev/zero | tr '\000' 'q' >$T/HALF.DAT
mkdisk $T/ha.imd $T/HALF.DAT >/dev/null
mkdisk $T/hb.imd >/dev/null
out=$($EMU -a $T/ha.imd -b $T/hb.imd -T -t 120 -e 'A:\>' -w b:$T/out/hb.imd \
	-k 'copy half.dat b:\rcopy half.dat b:c.dat\rdir b:\r')
check "COPY onto a full disk says so" "Disk Full" "$out"
if printf '%s\n' "$out" | grep -q 'C        DAT'; then
	echo "FAIL and leaves no part of the file:"
	printf '%s\n' "$out"
	fail=1
else
	echo "ok   and leaves no part of the file"
fi
python3 ../tools/imd2raw.py $T/out/hb.imd $T/out/hb.img >/dev/null
fatok "and the disk's FAT is clean" $T/out/hb.img

# A ? in COPY's new name takes the source's letter: the copy is never
# named by the pattern, and one that fills the disk erases only itself
echo x >$T/X.DAT
echo y >$T/Y.DAT
mkdisk $T/hw.imd $T/X.DAT $T/Y.DAT >/dev/null
out=$($EMU -a $T/ha.imd -b $T/hw.imd -T -t 120 -e 'A:\>' \
	-k 'copy half.dat b:*.dat\rcopy half.dat b:c*.dat\rdir b:\r')
check "COPY to B:*.DAT keeps the source's name" "B: X        DAT : Y        DAT : HALF     DAT" "$out"
check "and one to B:C*.DAT that fills the disk says so" "Disk Full" "$out"
# The line editor on a line that wraps: ^X and UP redraw it in place,
# and the back arrow at a wrapped row sends no cursor moves to the printer
L=$(printf 'a%.0s' $(seq 90))
out=$($EMU -a $T/ha.imd -T -t 20 -e 'A:\>' -k "${L}$(printf '\030')free\r")
check "^X on a wrapped line wipes both rows" "=0=" "=$(printf '%s\n' "$out" | grep -ic 'aaaaaaaaaa')="
out=$($EMU -a $T/ha.imd -T -t 20 -e 'A:\>' -k "${L}\r\\U\\U$(printf '\030')free\r")
check "UP twice on a wrapped line draws it in place" "=2=" "=$(printf '%s\n' "$out" | grep -ic 'aaaaaaaaaa')="
rm -f $T/out/lst.txt
$EMU -a $T/ha.imd -T -t 20 -l $T/out/lst.txt -e 'A:\>' \
	-k "$(printf '\020')$(printf 'a%.0s' $(seq 76))\\L$(printf '\030')\r" >/dev/null
check "the back arrow at a wrapped row prints no form feed" "=0=" "=$(tr -cd '\014' <$T/out/lst.txt | wc -c | tr -d ' ')="
# The shell's commands: _ in a name, no SAVE, TYPE or REN without a
# whole name, SAVE past 127 pages, DIR of a folder shows its folders,
# REN on the old name's drive, a batch file too long for the buffer
echo hello >$T/READ_ME.TXT
echo x >$T/A.TXT
echo old >$T/OLD.TXT
mkdisk $T/sh1.imd $T/A.TXT $T/READ_ME.TXT >/dev/null
mkdisk $T/sh2.imd $T/OLD.TXT >/dev/null
out=$($EMU -a $T/sh1.imd -T -t 30 -e 'A:\>' -k 'type read_me.txt\r')
check "TYPE takes a name with _ in it" "hello" "$out"
out=$($EMU -a $T/sh1.imd -b $T/sh2.imd -T -t 60 -e 'A:\>' -k 'save 2\rsave 2 *.txt\rtype\rsave 200 big.com\rls\rmd games\rmd games\\sub\rdir games\\\rren new.txt=b:old.txt\rdir b:\r')
check "SAVE with no name is refused" "SAVE?" "$out"
check "and TYPE with none" "TYPE?" "$out"
check "SAVE 2 left A.TXT as it was" "A.TXT        2" "$out"
check "SAVE 200 saves 200 pages" "BIG.COM      51200" "$out"
check "DIR of a folder shows the folders in it" "A: SUB\\" "$out"
check "REN works on the old name's drive" "B: NEW      TXT" "$out"
awk 'BEGIN { for (i = 0; i < 300; i++) print "rem line " i }' | sed 's/$/\r/' >$T/LONG.SUB
mkdisk $T/sh3.imd $T/LONG.SUB >/dev/null
out=$($EMU -a $T/sh3.imd -T -t 30 -e 'A:\>' -k 'long\r')
check "a batch file over 2K is refused whole" "Batch file too long" "$out"
# A batch file of exactly 2K fills its buffer: it runs when it has a ^Z
# of its own, and is too long without one
python3 -c "
import sys
t = b'dir\r\n' * 4
open(sys.argv[1], 'wb').write(t + b'\x1a' * (2048 - len(t)))
t = b'dir\r\n' * 409 + b'rem'
open(sys.argv[2], 'wb').write(t)" $T/FULL.SUB $T/NOEND.SUB
mkdisk $T/sh4.imd $T/FULL.SUB $T/NOEND.SUB >/dev/null
out=$($EMU -a $T/sh4.imd -T -t 30 -e 'A:\>' -k 'full\r')
check "a batch file of 2K that ends in ^Z runs" "A: FULL     SUB : NOEND    SUB" "$out"
out=$($EMU -a $T/sh4.imd -T -t 30 -e 'A:\>' -k 'noend\r')
check "and one with no ^Z is too long" "Batch file too long" "$out"
# The search tries each drive once: on A: the current drive and A: are
# one. A .COM, a .SUB and a .BAT on A: run from A: and from B:, and a
# name in none of them is asked about.
printf 'type a:read_me.txt\r\n' >$T/HI.SUB
printf 'ver\r\n' >$T/BYE.BAT
mkdisk $T/pa.imd $T/HI.SUB $T/BYE.BAT $T/READ_ME.TXT build/MORE.COM >/dev/null
mkdisk $T/pb.imd $T/OLD.TXT >/dev/null
out=$($EMU -a $T/pa.imd -b $T/pb.imd -T -t 60 -e 'A:\>|B:\>' -k 'hi\rnosuch\rb:\rhi\rbye\rmore a:read_me.txt\r')
n=$(printf '%s\n' "$out" | grep -c '^hello')
check "a .SUB on A: runs from A: and B:, and a .COM" "=3=" "=$n="
check "a .BAT on A: from B:" "=1=" "=$(printf '%s\n' "$out" | grep -c 'MAX-80, 128K$')="
check "a name on no drive is asked about" "NOSUCH?" "$out"
# Wildcards in 23 and 30 take every match, as CP/M 2.2 (the user's
# choice): WREN.COM renames *.TXT to *.BAK, B.TXT left as B.BAK is
# there, and makes every .BAK R/O
cat >$T/ren.asm <<'EOW'
	org	100h
	ld	de,rn
	ld	c,23
	call	5
	ld	(r1),a
	ld	de,at
	ld	c,30
	call	5
	ld	(r2),a
	ld	a,(r1)
	call	hx
	ld	e,' '
	ld	c,2
	call	5
	ld	a,(r2)
	call	hx
	jp	0
hx:	push	af
	rrca
	rrca
	rrca
	rrca
	call	h1
	pop	af
h1:	and	0Fh
	add	a,'0'
	cp	'9'+1
	jr	c,h2
	add	a,7
h2:	ld	e,a
	ld	c,2
	jp	5
r1:	db	0
r2:	db	0
rn:	db	0,'????????TXT',0,0,0,0
	db	0,'????????BAK',0,0,0,0
	ds	4
at:	db	0,'????????',0C2h,'AK'
	ds	24
EOW
(cd $T && sjasmplus --nologo --msg=war --raw=WREN.COM ren.asm >/dev/null)
for f in A B C; do echo $f >$T/$f.TXT; done
echo old >$T/B.BAK
mkdisk $T/ren.imd $T/WREN.COM $T/A.TXT $T/B.TXT $T/C.TXT $T/B.BAK >/dev/null
out=$($EMU -a $T/ren.imd -T -t 30 -e 'A:\>' -k 'wren\rdir\r' -w a:$T/out/ren.imd)
check "23 renames every match but one whose new name is taken: FF" "FF 00" "$out"
python3 ../tools/imd2raw.py $T/out/ren.imd $T/out/ren.img >/dev/null
out=$(mdir -b -i $T/out/ren.img :: | sort | tr '\n' ' ')
check "A.TXT and C.TXT are now .BAK, B.TXT stays" "::/A.BAK ::/B.BAK ::/B.TXT ::/C.BAK" "$out"
out=$(mattrib -i $T/out/ren.img ::*.BAK | grep -c '^ *R')
check "30 made every .BAK R/O" "3" "$out"
same "and B.BAK is the old one" $T/B.BAK $(mcopy -o -i $T/out/ren.img ::B.BAK $T/out/B.BAK && echo $T/out/B.BAK)
# FREE counts the clusters once a mount and keeps the count as files
# come and go: the same as a count after a reboot, and as mtools'
python3 tools/mkdisk.py $SYS $T/fr.imd --pc 1440 >/dev/null
out=$($EMU -a $T/fr.imd -T -t 40 -w a:$T/out/fr.imd -e 'A:\>' \
	-k 'free\rsave 10 a.com\rsave 20 b.com\rera a.com\rmd x\rmd y\rrd x\rsave 7 y\\c.com\rfree\r')
k1=$(printf '%s\n' "$out" | grep -a 'K free' | tail -1)
out=$($EMU -a $T/out/fr.imd -T -t 20 -e 'A:\>' -k 'free\r')
check "FREE's kept count is a fresh count's" "$k1" "$out"
python3 ../tools/imd2raw.py $T/out/fr.imd $T/out/fr.img >/dev/null
k2=$(mdir -i $T/out/fr.img :: | grep -a 'bytes free' | tr -d ' ' | sed 's/bytesfree//')
check "and mtools'" "A: $((k2 / 1024))K free" "$k1"
# A folder of 300 entries, 19 clusters: the walk along its chain goes on
# from where the last one ended. Files made, found and erased far
# along it, a second folder, and one removed, leave the volume clean.
for i in $(seq 1 300); do echo $i >$T/F$i.TXT; done
python3 tools/mkdisk.py $SYS $T/fo.imd --pc 1440 --in SUB $(for i in $(seq 1 300); do echo $T/F$i.TXT; done) >/dev/null
out=$($EMU -a $T/fo.imd -T -t 300 -w a:$T/out/fo.imd -e 'A:\>' \
	-k 'save 1 sub\\zz.com\rmd sub\\in\rsave 1 sub\\in\\y.com\rera sub\\f150.txt\rrd sub\\in\rera sub\\in\\y.com\rrd sub\\in\rtype sub\\f299.txt\rls sub\\zz.com\r')
check "a file made at the end of a long folder is found" "ZZ.COM       256" "$out"
check "and one far along it is read" "299" "$out"
out=$($EMU -a $T/out/fo.imd -T -t 300 -e 'A:\>' -k 'ls sub\\f1*.txt\r')
check "and its files are counted, F150 gone" "110 files" "$out"
python3 ../tools/imd2raw.py $T/out/fo.imd $T/out/fo.img >/dev/null
fatok "and the volume is clean" $T/out/fo.img

# A folder grows past its first cluster, ERA a path empties it, RD
# removes it, and RD of the current folder is refused
k='md big\rcd big\r'
for i in $(seq 1 40); do k="${k}save 1 f$i.com\\r"; done
out=$($EMU -a "$DISK" -t 200 -e 'A:\>|A:\BIG>|ALL (Y/N)?' -w a:$T/out/fb.imd \
	-k "${k}rd \\\\big\\rcd ..\\rls big\\\\f4*.*\\rera big\\\\*.*\\ry\\E\\Prd big\\rdir\\r")
check "40 files in a folder" "A:\\BIG>save 1 f40.com" "$out"
check "RD of the current folder" "In use" "$out"
check "LS of a path" "F40.COM      256" "$out"
check "ERA of a path, RD, and the folder is gone" "XCPM     FNT : THIN     FNT : INVERSE  FNT" "$(printf '%s\n' "$out" | tail -3)"
printf '%s\n' "$out" | tail -3 | grep -q 'BIG\\' &&
	{ echo "FAIL BIG\\ should be gone"; fail=1; }
python3 ../tools/imd2raw.py $T/out/fb.imd $T/out/fb.img >/dev/null
fatok "and the volume is clean, every cluster back" $T/out/fb.img

# A drive in a folder whose disk changes, here by FORMAT, goes back to
# the root
mkdisk $T/fdb.imd >/dev/null
out=$($EMU -a "$DISK" -b $T/fdb.imd -t 300 -e 'A:\>|B:\X>|B:\>|Format B: and lose its files (Y/N)?' \
	-k 'md b:x\rcd b:x\rb:\rformat b:\ry')
check "a drive in a folder" 'B:\X>format b:' "$out"
check "back to the root when its disk changes" 'B:\>' "$(printf '%s\n' "$out" | grep -A1 '^Formatted' | tail -1)"

# Folders made by mtools on a hard disk, read here. The BDOS calls 118
# MKDIR, 119 RMDIR, 124 CHDIR and 125 GETCWD from a program, whose CD
# stays after it, and the file a program makes in its folder.
python3 tools/mkdisk.py $SYS --hd 2 $T/fh.img $T/HELLO.TXT >/dev/null
mmd -i $T/fh.img ::PC ::PC/DEEP
mcopy -i $T/fh.img $T/HELLO.TXT ::PC/DEEP/HI.TXT
cat >$T/fd.asm <<'EOF'
	org	100h
	ld	c,118
	ld	de,p1
	call	bdos
	ld	c,118
	ld	de,p2
	call	bdos
	ld	c,124
	ld	de,p2
	call	bdos
	ld	c,125
	ld	de,buf
	call	5
	ld	hl,buf
pr:	ld	a,(hl)
	or	a
	jr	z,pd
	push	hl
	ld	e,a
	ld	c,2
	call	5
	pop	hl
	inc	hl
	jr	pr
pd:	ld	c,22			; a file here
	ld	de,fcb
	call	bdos
	ld	c,16
	ld	de,fcb
	call	bdos
	ld	c,124
	ld	de,up
	call	bdos
	ld	c,119			; SUB has a file
	ld	de,sub
	call	bdos
	ld	c,119			; and NOPE is not there
	ld	de,nope
	call	bdos
	ret
bdos:	call	5			; then A in hex and a space
	push	af
	rrca
	rrca
	rrca
	rrca
	call	nib
	pop	af
	call	nib
	ld	e,' '
	ld	c,2
	jp	5
nib:	and	0Fh
	add	a,90h
	daa
	adc	a,40h
	daa
	ld	e,a
	ld	c,2
	jp	5
p1:	db	"TOOLS",0
p2:	db	"tools/sub",0
up:	db	"..",0
sub:	db	"SUB",0
nope:	db	"NOPE",0
fcb:	db	0,"MADE    DAT"
	ds	24
buf:	ds	64
EOF
(cd $T && sjasmplus --nologo --msg=war --raw=FD.COM fd.asm >/dev/null)
mcopy -i $T/fh.img $T/FD.COM ::FD.COM
out=$($EMU -D 7 -h $T/fh.img -t 60 -e 'A:\>|A:\TOOLS>|A:\TOOLS\SUB>|A:\PC\DEEP>' -w h:$T/out/fh.img \
	-k 'dir\rcd pc\\deep\rtype hi.txt\rcd \\\rfd\rdir\rcd sub\rdir\r')
check "DIR shows mtools's folder" "PC\\" "$out"
check "CD and TYPE in mtools's folders" "Second line." "$out"
check "BDOS 118, 124 and 125 from a program" '00 00 00 \TOOLS\SUB00 00 00 FF FF' "$out"
check "and its CD stays after it" 'A:\TOOLS>dir' "$out"
check "the file it made is in the folder" "A: MADE     DAT" "$out"
out=$(mdir -/ -i $T/out/fh.img ::TOOLS 2>&1)
check "mtools reads the folders BDOS 118 made" "Directory for ::/TOOLS/SUB" "$out"
check "and the file in them" "MADE     DAT" "$out"
fatok "and the hard disk is clean" $T/out/fh.img


#PARTS-END
check "no session.py wait for the screen ran out" "=0=" "=$(wc -l <$SESSION_LOG | tr -d ' ')="
[ -s $SESSION_LOG ] && cat $SESSION_LOG
exit $fail
