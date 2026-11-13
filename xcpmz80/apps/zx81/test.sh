#!/bin/sh
# ZX81.COM's tests. Nothing here needs the user's ROM or games but
# the last part, which skips with a message when they are missing.
cd "$(dirname "$0")" || exit 1
R=../../..
RAW="${EMU:-$R/emu/max80} -r $R/reference/rom/max80.e12"
# Loading ZX81.COM and its ROM ends at 4.6 s with the drives' mechanics,
# the emulator's default now, where it did at 2.4 s: each key
# script waits 3 s more after its Enter (\E\P\P\P) and each -t is 3 s
# longer
emu() {
	n=$#
	while [ $n -gt 0 ]; do
		a=$1
		shift
		n=$((n - 1))
		if [ "$a" = -t ] && [ $n -gt 0 ]; then
			set -- "$@" -t $(($1 + 3))
			shift
			n=$((n - 1))
		else
			set -- "$@" "$a"
		fi
	done
	$RAW "$@"
}
EMU=emu
XC=$R/xcpmz80
SJ=${SJASMPLUS:-sjasmplus}
command -v $SJ >/dev/null || SJ=$HOME/.local/bin/sjasmplus
T=build/t
ROM=${ZX81_FILES:-.}/sz81/data/zx81.rom
fail=0
sh build.sh || exit 1
rm -rf $T
mkdir -p $T

check() {	# name, text to find, output
	if [ -z "$2" ]; then	# a failed $(...): nothing to look for
		echo "FAIL $1: no text to look for"
		fail=1
		return
	fi
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		echo "ok   $1"
	else
		echo "FAIL $1: no '$2' in:"
		printf '%s\n' "$3" | cut -c1-80 | tail -30
		fail=1
	fi
}

no() {		# name, text that must not be there, output
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		echo "FAIL $1: found '$2'"
		fail=1
	else
		echo "ok   $1"
	fi
}

P="python3 $R/tools/zx81p.py"
printf '\311' > $T/ret.bin		# RET
printf '\030\376' > $T/spin.bin		# JR to itself
$SJ --nologo --msg=war --raw=$T/watch.bin tests/watch.asm || exit 1
$P --rom $T/ZX81.ROM
$P $T/RET.P $T/ret.bin
$P $T/EXP.P $T/spin.bin --text '0:A' --text '23:Z'
$P $T/COL.P $T/spin.bin --collapsed --text '2:B' --text '12:C'
$P $T/WATCH.P $T/watch.bin
head -c 100 $T/RET.P > $T/SHORT.P
(cd $XC && make -s build/xcpmz80.sys) || exit 1
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/a.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/ZX81.ROM apps/zx81/$T/RET.P \
	apps/zx81/$T/EXP.P apps/zx81/$T/COL.P apps/zx81/$T/WATCH.P \
	apps/zx81/$T/SHORT.P)
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/norom.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/RET.P)

run() {		# seconds, keys, more options
	s=$1
	k=$2
	shift 2
	$EMU -f -K -T -a $T/a.imd -e 'A:\>' -k "$k" -t $s "$@" 2>&1
}

out=$(run 6 'ZX81\r')
check "no name: how to use it" "ZX81 NAME" "$out"
out=$(run 6 'ZX81 NONE\r')
check "no such .P" "No such .P" "$out"
out=$(run 6 'ZX81 SHORT\r')
check "a .P cut short" "Not a good .P" "$out"
out=$($EMU -f -K -T -a $T/norom.imd -e 'A:\>' -k 'ZX81 RET\r' -t 6 2>&1)
check "no ROM" "No ZX81.ROM" "$out"

out=$(run 8 'ZX81 RET /Y\rDIR\r')
check "the game's return comes back to the shell" "ZX81     COM" "$out"

# A display file code shows in both pages, from video RAM offset 8. A is
# 26h, &, Z is 3Fh, ?, B ', C (
out=$(run 7 'ZX81 EXP /Y\E\P\P\P\P\P')
check "expanded: the first line" "@@@@@@@@&&@" "$out"
check "and the last" "@@@@@@@@??@" "$out"
out=$(run 7 'ZX81 COL /Y\E\P\P\P\P\P')
check "collapsed: a short line" "@@@@@@@@''@" "$out"
check "and a later one" "@@@@@@@@((@" "$out"

# Light on dark: the same screen, inverted
run 7 'ZX81 EXP /Y\E\P\P\P\P\P' -p $T/w.pgm >/dev/null
run 7 'ZX81 EXP /D /Y\E\P\P\P\P\P' -p $T/d.pgm >/dev/null
out=$(python3 - $T/w.pgm $T/d.pgm <<'PY'
import sys
m = [sum(open(f, 'rb').read()[-200000:]) for f in sys.argv[1:]]
print('lighter' if m[0] > 3 * m[1] else 'same')
PY
)
check "white background by default, /D dark" "lighter" "$out"

# FRAMES counts down at 50 a second
frames() {
	python3 - "$1" <<'PY'
import sys
for l in sys.argv[1].split('\n'):
    l = l.rstrip()
    cells = l[8:72]
    for c in (cells[0::2], cells[1::2]):
        if len(c) >= 4 and all(0x26 <= ord(x) <= 0x35 for x in c[:4]):
            print(int(''.join('%x' % (ord(x) - 0x26) for x in c[:4]), 16))
            sys.exit()
PY
}
a=$(frames "$(run 6 'ZX81 WATCH /Y\E\P\P\P')")
b=$(frames "$(run 16 'ZX81 WATCH /Y\E\P\P\P')")
out=$(python3 -c "d=(${a:-0}-${b:-0})&0x7fff; print('near 500' if 490<=d<=510 else 'off %d'%d)")
check "FRAMES: 10 seconds, 500 frames" "near 500" "$out"

# LAST_K: K is F7BFh, with SHIFT F6BFh, in codes from 26h. No -K here,
# so a small letter is the key alone
hexz() { python3 -c "print(''.join(chr(0x26+int(c,16))+'@' for c in '$1'))"; }
out=$($EMU -f -T -a $T/a.imd -e 'A:\>' -k 'ZX81 WATCH /Y\E\P\P\P\P\P\P\Pk' -t 9 2>&1 | tr -d '\000')
key=$(printf '%s\n' "$out" | python3 -c "
import sys
for l in sys.stdin:
    for c in (l[8:16:2], l[9:17:2]):
        if c == ''.join(chr(0x26+int(x,16)) for x in 'f7bf'):
            print('K seen'); sys.exit()")
check "LAST_K for a key" "K seen" "$key"

# BREAK puts everything back: the same picture as CLS and DIR
run 12 'ZX81 EXP /Y\E\P\P\P\P\P\P\P\B\P\P\PDIR\r' -p $T/x.pgm >/dev/null
run 12 'CLS\rDIR\r' -p $T/y.pgm >/dev/null
out=$(python3 - $T/x.pgm $T/y.pgm <<'PY'
import sys
a, b = (open(f, 'rb').read() for f in sys.argv[1:])
def rows(d):	# the header and the pixel lines down to text row 5
	h = d.split(b'\n', 4)	# P5, "# cells left top w h ...", W H, 255
	top, ch = int(h[1].split()[3]), int(h[1].split()[5])
	w, n = map(int, h[2].split())
	return d[:len(d) - w * n + w * (top + 5 * ch)]
# the DIR, rows 0-4, not row 5 with the prompt and its blinking cursor
print('same' if len(a) == len(b) and rows(a) == rows(b) else 'differ')
PY
)
check "BREAK: rows, fonts and screen as before" "same" "$out"

# ZX81 text as the emulator's -T shows it, both pages: each code twice
zt() { python3 -c "
import sys
sys.path.insert(0, '$R/tools')
import zx81p
print(''.join(chr(c) * 2 for c in zx81p.zx('$1')))"; }

# RST 10h into a collapsed file, a trap and the decode, without the games
$SJ --nologo --msg=war --raw=$T/rst.bin tests/rst.asm || exit 1
$P $T/RST.P $T/rst.bin --collapsed
$SJ --nologo --msg=war --raw=$T/trap.bin tests/trap.asm || exit 1
$P $T/TRAP.P $T/trap.bin
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/b.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/ZX81.ROM apps/zx81/$T/RST.P \
	apps/zx81/$T/TRAP.P)
out=$($EMU -f -K -T -a $T/b.imd -e 'A:\>' -k 'ZX81 RST /F /Y\E\P\P\P' -t 7 2>&1)
check "RST 10h: room made in a collapsed line" "@@@@@@@@$(zt ABC)" "$out"
check "and NEWLINE goes to the next line" "@@@@@@@@$(zt XY)" "$out"
check "and the variables moved: the line after" "@@@@@@@@$(zt OK)" "$out"
out=$($EMU -f -K -T -a $T/b.imd -e 'A:\>' -k 'ZX81 TRAP /Y\r' -t 7 2>&1)
check "an RST we lack quits and says from where" "ROM call not there, from 4082" "$out"
# RST 0, a ZX81's reset; RST 8 in a game not patched, a ZX81's error;
# IY as the ROM leaves it; a CALL to a ROM entry past our code
for t in trap0 trap8 iy fast; do
	$SJ --nologo --msg=war --raw=$T/$t.bin tests/$t.asm || exit 1
	$P $T/$(echo $t | tr a-z A-Z).P $T/$t.bin
done
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/c.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/ZX81.ROM apps/zx81/$T/TRAP0.P \
	apps/zx81/$T/TRAP8.P apps/zx81/$T/IY.P apps/zx81/$T/FAST.P)
out=$($EMU -f -K -T -a $T/c.imd -e 'A:\>' -k 'ZX81 TRAP0 /Y\r' -t 7 2>&1)
check "RST 0 is a trap, not CP/M's warm boot" "ROM call not there, from 4082" "$out"
out=$($EMU -f -K -T -a $T/c.imd -e 'A:\>' -k 'ZX81 TRAP8 /Y\r' -t 7 2>&1)
check "RST 8 in a game not patched is a trap" "ROM call not there, from 4082" "$out"
out=$($EMU -f -K -T -a $T/c.imd -e 'A:\>' -k 'ZX81 IY /Y\r' -t 7 2>&1)
check "the game starts with IY 4000h" "ROM call not there, from 408E" "$out"
out=$($EMU -f -K -T -a $T/c.imd -e 'A:\>' -k 'ZX81 FAST /Y\r' -t 7 2>&1)
check "a CALL to FAST is a trap" "ROM call not there, from 0F23" "$out"

# An unknown .P: a warning and what the scan sees, a key goes on
$SJ --nologo --msg=war --raw=$T/scan.bin tests/scan.asm || exit 1
$P $T/SCAN.P $T/scan.bin
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/d.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/ZX81.ROM apps/zx81/$T/SCAN.P)
out=$($EMU -f -K -T -a $T/d.imd -e 'A:\>' -k 'ZX81 SCAN\E\P\P\P' -t 7 2>&1)
check "an unknown .P is warned of" "Not a game this knows" "$out"
check "the scan sees an IN" "  IN at 4082" "$out"
check "an OUT" "  OUT at 4084" "$out"
check "a HALT" "  HALT at 4086" "$out"
check "LD I,A" "  LD I,A at 4087" "$out"
check "IN A,(C)" "  IN at 4089" "$out"
check "a ROM call" "  ROM call at 408B" "$out"
no "but not the kept decode" "at 408E" "$out"
out=$($EMU -f -K -T -a $T/d.imd -e 'A:\>' -k 'ZX81 SCAN\E\P\P\P\Px\P\P' -t 8 2>&1)
no "and a key goes on" "Any key goes on" "$out"

# KEYBOARD at 02BBh and DECODE with SHIFT; CLS at 0A2Ah; RST 10h past
# the last line; a .P with no line to go on with, one that ends in the
# record at the limit, one past it; an 8K file that is not a ZX81 ROM
hexd() { python3 -c "print(''.join(chr(0x26+int(c,16))*2 for c in '$1'))"; }
$SJ --nologo --msg=war --raw=$T/keys.bin tests/keys.asm || exit 1
$P $T/KEYS.P $T/keys.bin
$SJ --nologo --msg=war --raw=$T/cls.bin tests/cls.asm || exit 1
$SJ --nologo --msg=war -DBIG --raw=$T/clsb.bin tests/cls.asm || exit 1
$P $T/CLS.P $T/cls.bin --collapsed --text '3:CC'
$P $T/CLSE.P $T/clsb.bin --text '3:CC'
$P $T/CLSC.P $T/clsb.bin --collapsed --text '3:CC'
$SJ --nologo --msg=war --raw=$T/bottom.bin tests/bottom.asm || exit 1
$P $T/BOTTOM.P $T/bottom.bin
python3 - $T <<'PY'
import sys
t = sys.argv[1]
p = bytearray(open(t + '/RET.P', 'rb').read())
p[0x4029 - 0x4009:0x4029 - 0x4009 + 2] = p[3:5]	# NXTLIN at D_FILE
open(t + '/NX.P', 'wb').write(p)
open(t + '/pad.bin', 'wb').write(b'\xc9' + bytes(15365))
open(t + '/too.bin', 'wb').write(b'\xc9' + bytes(15365 + 212))
PY
$P $T/BIG.P $T/pad.bin
$P $T/TOO.P $T/too.bin
mkdir -p $T/bad
head -c 8192 /dev/zero > $T/bad/ZX81.ROM
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/e.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/ZX81.ROM apps/zx81/$T/KEYS.P \
	apps/zx81/$T/CLS.P apps/zx81/$T/CLSE.P apps/zx81/$T/CLSC.P \
	apps/zx81/$T/BOTTOM.P apps/zx81/$T/NX.P apps/zx81/$T/BIG.P \
	apps/zx81/$T/TOO.P)
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/badrom.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/bad/ZX81.ROM apps/zx81/$T/RET.P)
out=$($EMU -f -T -a $T/e.imd -e 'A:\>' -k 'ZX81 KEYS /F /Y\E\P\P\P\P\P\Pk\P' -t 9 2>&1)
check "KEYBOARD at 02BBh: K" "@@@@@@@@$(hexd f7bf)" "$out"
check "DECODE of it: K" "@@@@@@@@$(zt K)@@" "$out"
check "and its index" "@@@@@@@@$(hexd 20)@@" "$out"
out=$($EMU -f -T -a $T/e.imd -e 'A:\>' -k 'ZX81 KEYS /F /Y\E\P\P\P\P\P\P\PK\P\P' -t 11 2>&1)
check "KEYBOARD: SHIFT K" "@@@@@@@@$(hexd f6bf)" "$out"
check "DECODE takes the ROM's table with SHIFT" "@@@@@@@@$(zt F)@@" "$out"
check "and its index" "@@@@@@@@$(hexd 47)@@" "$out"
for f in CLS CLSE CLSC; do
	out=$($EMU -f -K -T -a $T/e.imd -e 'A:\>' -k "ZX81 $f /F /Y\\E\\P\\P\\P" -t 9 2>&1)
	check "CLS ($f): printing starts at the top" "@@@@@@@@$(zt OK)@@" "$out"
	check "and goes on below" "@@@@@@@@$(zt AB)@@" "$out"
	no "and what was there is gone" "$(zt QQ)" "$out"
	no "the file's own text too" "$(zt CC)" "$out"
	no "and the variables are where they were" "ROM call not there" "$out"
done
out=$($EMU -f -K -T -a $T/e.imd -e 'A:\>' -k 'ZX81 BOTTOM /F /Y\E\P\P\P' -t 8 2>&1)
check "RST 10h past the last line: kept on it" "@@@@@@@@$(zt XY)@@" "$out"
no "and nothing written past the display file" "ROM call not there" "$out"
out=$($EMU -f -K -T -a $T/e.imd -e 'A:\>' -k 'ZX81 NX /Y\rDIR\r' -t 9 2>&1)
no "NXTLIN at the display file: the USR found as RUN" "No USR" "$out"
check "and the game ran and returned" "ZX81     COM" "$out"
out=$($EMU -f -K -T -a $T/e.imd -e 'A:\>' -k 'ZX81 BIG /Y\rDIR\r' -t 12 2>&1)
no "a .P ending in the record at the limit loads" "too big" "$out"
check "and runs" "ZX81     COM" "$out"
out=$($EMU -f -K -T -a $T/e.imd -e 'A:\>' -k 'ZX81 TOO /Y\r' -t 10 2>&1)
check "one record more is too big" "too big" "$out"
out=$($EMU -f -K -T -a $T/badrom.imd -e 'A:\>' -k 'ZX81 RET /Y\r' -t 7 2>&1)
check "an 8K file not a ZX81 ROM is refused" "is not a ZX81 ROM" "$out"

# Speed: 0.81 MHz worth, a 229 T-state loop, about 3540 passes a second
$SJ --nologo --msg=war --raw=$T/speed.bin tests/speed.asm || exit 1
$P $T/SPEED.P $T/speed.bin
(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/c.imd \
	apps/zx81/build/ZX81.COM apps/zx81/$T/ZX81.ROM apps/zx81/$T/SPEED.P)
cnt() {
	$EMU -f -K -T -a $T/c.imd -e 'A:\>' -k "ZX81 SPEED$2 /Y\E\P\P\P" -t $1 2>&1 | python3 -c "
import sys
for l in sys.stdin:
    for c in (l[8:16:2], l[9:17:2]):
        if len(c) == 4 and all(0x26 <= ord(x) <= 0x35 for x in c):
            print(int(''.join('%x' % (ord(x) - 0x26) for x in c), 16))
            sys.exit()"
}
a=$(cnt 5 '')
b=$(cnt 9 '')
out=$(python3 -c "r=(${b:-0}-${a:-0})/4; print('near %d' % r if 3200<r<3900 else 'off %d' % r)")
check "ZX81 speed: about 0.81 MHz for the game" "near" "$out"
echo "     $out passes a second, 3540 wanted"
a=$(cnt 5 ' /F')
b=$(cnt 7 ' /F')
out=$(python3 -c "r=((${b:-0}-${a:-0})&65535)/2; print('faster' if r>4500 else 'off %d'%r)")
check "/F: faster" "faster" "$out"

if [ -f "$ROM" ]; then
	cp "$ROM" $T/ZX81R.ROM
	mkdir -p $T/g
	cp "$ROM" $T/g/ZX81.ROM
	(cd $XC && python3 tools/mkdisk.py build/xcpmz80.sys apps/zx81/$T/g.imd \
		apps/zx81/build/ZX81.COM apps/zx81/$T/g/ZX81.ROM apps/zx81/games/*.P)
	game() {	# seconds, keys
		$EMU -f -T -a $T/g.imd -e 'A:\>' -k "$2" -t $1 2>&1
	}
	# s at 6 s: around 4 s the title lets a key go by, and when that
	# comes depends on how fast the system starts the game
	out=$(game 18 'ZX81 TETRIS /F\E\P\P\P\P\P\P\P\P\Ps\P\P\Pk\Pk\P')
	check "Tetris: a key starts a game" "$(zt LINES)" "$out"
	out=$(game 26 'ZX81 MINE81 /F\E\P\P\P\P\P\P\P\P\Ps\P\P\P\P\P1\P\P\P\P\P\P\P\P')
	check "Mine81: a level starts a game" "$(zt MINES)" "$out"
	w='\P\P\P\P\P\P\P\P\P\P\P'
	out=$(game 26 "ZX81 PIPEPANI /F\\E\\P\\P\\P$w\\Pk\\P\\P\\P\\P\\P\\Pa\\Pa\\P\\P")
	check "Pipepanic: the menu, through the patched IN" "$(zt CONTROLS)" "$out"
	out=$(game 34 "ZX81 PIPEPANI /F\\E\\P\\P\\P$w\\Pk\\P\\P\\P\\P\\P\\Pk\\P\\P\\P\\P\\P\\P\\P\\P")
	no "and Play leaves it" "$(zt CONTROLS)" "$out"
	$EMU -f -T -a $T/g.imd -e 'A:\>' -k 'ZX81 TETRIS1K /F\E\P\P\P\P\P\P\P\Pm\P\P\P' -t 13 -p $T/k1.pgm >/dev/null 2>&1
	$EMU -f -T -a $T/g.imd -e 'A:\>' -k 'ZX81 TETRIS1K /F\E\P\P\P\P\P\P\P\P\P\P\P' -t 13 -p $T/k0.pgm >/dev/null 2>&1
	out=$(cmp -s $T/k0.pgm $T/k1.pgm && echo same || echo differ)
	check "Tetris1k: a key through 07BDh starts a game" "differ" "$out"
else
	echo "skip the games: no $ROM"
fi
exit $fail
