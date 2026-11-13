#!/bin/sh
# Tests for the MAX-80 emulator. Run from emu/ after make.
# ZEXDOC runs when ZEXDOC=/path/to/zexdoc.com is set. It is not in the
# repo, being GPL.
set -u
cd "$(dirname "$0")"
fail=0

check() {	# name, text to find, output
	if [ -z "$2" ]; then	# a failed $(...): nothing to look for (I288)
		echo "FAIL $1: no text to look for"
		fail=1
		return
	fi
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

# The clock across a HOLD pulse, the SIO taken out (I301)
if ./test_dev > /dev/null; then
	echo "ok   the clock keeps its seconds across HOLD, -F u:0 takes no writes (test_dev)"
else
	echo "FAIL devices unit test:"; ./test_dev; fail=1
fi

# Options read as their help says (I301): -F d's second in decimal,
# -t 0 and an -i time that is not a number refused
opts=""
./max80 -T -t 0.01 -F d:800:0 >/dev/null 2>&1 && opts="${opts}d800 "
./max80 -T -t 0.01 -F d:1a:0 >/dev/null 2>&1 || opts="${opts}no1a "
timeout 20 ./max80 -T -t 0 >/dev/null 2>&1 </dev/null; [ $? = 2 ] && opts="${opts}not0 "
./max80 -T -t 0.01 -i a:/dev/null@nan >/dev/null 2>&1 || opts="${opts}nonan "
check "-F d:800 taken, d:1a, -t 0 and -i @nan refused" \
	"d800 no1a not0 nonan " "$opts"

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
