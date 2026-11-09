#!/bin/sh
# Builds CLONERUN.COM, and for the tests CRT.COM (the TEST build, on the
# test levels), CRT2.COM (the same building and copying the runner twice
# a frame) and FONTSUM.COM, into build/. Checks the levels and glyphs
# first. Needs sjasmplus and python3.
#
# CLONERUN.COM carries Lode Runner's stages, Broderbund's data, kept out
# of git: read from $LODERUNNER_LEVELS, by default private/levels.txt.
# Without that file only the test builds are made.
cd "$(dirname "$0")" || exit 1
SJ=${SJASMPLUS:-sjasmplus}
command -v $SJ >/dev/null || SJ=$HOME/.local/bin/sjasmplus
LEVELS=${LODERUNNER_LEVELS:-private/levels.txt}
mkdir -p build
python3 tools/glyphs.py glyphs.txt build/glyphs.inc || exit 1
python3 tools/levels.py tests/levels_test.txt build/testlevels.inc || exit 1
$SJ --nologo --msg=war -Ibuild -DTEST --lst=build/crt.lst --raw=build/CRT.COM clonerun.asm || exit 1
$SJ --nologo --msg=war -Ibuild -DTEST -DTWICE --raw=build/CRT2.COM clonerun.asm || exit 1
$SJ --nologo --msg=war -I. --raw=build/FONTSUM.COM tests/fontsum.asm || exit 1
rm -f build/CLONERUN.COM build/levels.inc
if [ -f "$LEVELS" ]; then
	python3 tools/levels.py "$LEVELS" build/levels.inc || exit 1
	$SJ --nologo --msg=war -Ibuild --lst=build/clonerun.lst --raw=build/CLONERUN.COM clonerun.asm || exit 1
else
	echo "build.sh: no $LEVELS, Lode Runner's stages, so no CLONERUN.COM (set LODERUNNER_LEVELS)"
fi
