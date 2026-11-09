#!/bin/sh
# Makes the screenshots in this folder from the emulator, so they can be
# made again after a change: the diagnostic's menu, xcpmz80 with its
# programs, and Clone Runner's title and its first stage in play. Clone
# Runner needs Lode Runner's stages, which are not included: it is built
# from the file LODERUNNER_LEVELS names, by default
# ../software/clonerun/private/levels.txt, and without it its two
# pictures are left as they are. Needs what the builds need (a C
# compiler, sjasmplus, SDCC for the C programs, Python 3).
cd "$(dirname "$0")" || exit 1
H=$(pwd)
R=$(cd .. && pwd)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

make -C "$R/emu" >/dev/null || exit 1
make -C "$R/diag" >/dev/null || exit 1
make -C "$R/xcpmz80" all cprogs build/ZX81.COM >/dev/null || exit 1

cd "$R/emu" || exit 1
EMU=./max80
shot() {	# NAME, then the emulator's options: a frame after the run
	n=$1
	shift
	$EMU -T "$@" -p "$T/$n.pgm" > "$T/$n.txt" || exit 1
	python3 frame2png.py "$T/$n.pgm" "$H/$n.png" || exit 1
	echo "$n.png"
}

shot diag -a "$R/diag/build/diag.imd" -t 6

# xcpmz80 on a disk of its programs, with no ROM or story of anyone's
X=$R/xcpmz80
C=$X/c/build
(cd "$X" && python3 tools/mkdisk.py build/xcpmz80.sys "$T/x.imd" \
	build/LDFONT.COM build/GLYPHS.COM build/CLOCK.COM build/MORE.COM \
	$C/CLIB.SYS $C/VI.COM $C/EMACS.COM $C/ADVENT.COM $C/ZORK.COM \
	$C/BASE64.COM build/ZX81.COM apps/zx81/games/*.P \
	build/XCPM.FNT) >/dev/null || exit 1
shot xcpmz80 -a "$T/x.imd" -t 30 -e 'A:\>' \
	-k 'dir\rmd games\rcd games\r'

# Clone Runner, built in a copy of its folder from the stages
L=${LODERUNNER_LEVELS:-$R/software/clonerun/private/levels.txt}
if [ ! -f "$L" ]; then
	echo "no $L, Lode Runner's stages, so no Clone Runner pictures (set LODERUNNER_LEVELS)"
	exit 0
fi
cp -r "$R/software/clonerun" "$T/cr" || exit 1
rm -rf "$T/cr/build" "$T/cr/private"
LODERUNNER_LEVELS=$L sh "$T/cr/build.sh" >/dev/null || exit 1
(cd "$X" && python3 tools/mkdisk.py build/xcpmz80.sys "$T/cr.imd" \
	"$T/cr/build/CLONERUN.COM") >/dev/null || exit 1
shot clonerun_title -a "$T/cr.imd" -t 12 -e 'A:\>' -k 'CLONERUN\E'
shot clonerun_play -a "$T/cr.imd" -t 16 -e 'A:\>' \
	-k 'CLONERUN\E\P\P\P\E\P\P\P'
