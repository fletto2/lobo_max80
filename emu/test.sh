#!/bin/sh
# Tests for the MAX-80 emulator. Run from emu/ after make.
# ZEXDOC runs when ZEXDOC=/path/to/zexdoc.com is set. It is not in the
# repo, being GPL.
set -u
cd "$(dirname "$0")"
fail=0

check() {	# name, text to find, output
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		echo "ok   $1"
	else
		echo "FAIL $1: no '$2' in:"
		printf '%s\n' "$3"
		fail=1
	fi
}


# SASI hard disk: the protocol of Lobo's driver XWINI.MAC, and the ROM boots it
if ./test_sasi > /dev/null; then
	echo "ok   SASI hard disk, and the boot ROM boots from it (test_sasi)"
else
	echo "FAIL SASI unit test:"; ./test_sasi; fail=1
fi

# The window's keys (test_keys is built only with SDL2)
if [ -x test_keys ]; then
	if ./test_keys > /dev/null; then
		echo "ok   window keys held in the matrix, host repeats left out (test_keys)"
	else
		echo "FAIL window keys unit test:"; ./test_keys; fail=1
	fi
fi

if ./test_iff > /dev/null; then
	echo "ok   an interrupt right after LD A,I clears P/V, iffget copes (test_iff)"
else
	echo "FAIL iffget unit test:"; ./test_iff; fail=1
fi

# xcpmz80, built in ../xcpmz80, boots to its prompt and lists its disk
X=../xcpmz80/build/xcpmz80.imd
if [ -f "$X" ]; then
	out=$(./max80 -K -a "$X" -t 15 -e 'A:\>' -k 'DIR\r')
	check "xcpmz80 boots to its sign-on" "XCP/M-Z80" "$out"
	check "and DIR lists its files" "LDFONT   COM" "$out"
else
	echo "skip xcpmz80 boot (make it in ../xcpmz80 first)"
fi

if ./test_track > /dev/null; then
	echo "ok   write track and read track round trip (test_track)"
else
	echo "FAIL track unit test:"; ./test_track; fail=1
fi

if [ -n "${ZEXDOC:-}" ]; then
	out=$(./cpmtest "$ZEXDOC")
	if printf '%s\n' "$out" | grep -q ERROR; then
		echo "FAIL ZEXDOC"; printf '%s\n' "$out" | grep ERROR; fail=1
	else
		check "ZEXDOC" "Tests complete" "$out"
	fi
else
	echo "skip ZEXDOC (set ZEXDOC=path/to/zexdoc.com)"
fi
exit $fail
