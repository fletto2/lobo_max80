#!/bin/sh
# Tests for the MAX-80 emulator. Run from emu/ after make.
# ZEXDOC runs when ZEXDOC=/path/to/zexdoc.com is set. It is not in the
# repo, being GPL.
set -u
cd "$(dirname "$0")"
fail=0

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
		printf '%s\n' "$3"
		fail=1
	fi
}

t20() {		# GNU timeout where there is one; macOS has none
	if command -v timeout >/dev/null 2>&1; then
		timeout 20 "$@"
	else
		"$@"
	fi
}

sha1() {	# sha1sum, or shasum as macOS has it
	if command -v sha1sum >/dev/null 2>&1; then
		sha1sum "$@"
	else
		shasum "$@"
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

# The clock across a HOLD pulse, the SIO taken out
if ./test_dev > /dev/null; then
	echo "ok   the clock keeps its seconds across HOLD, -F u:0 takes no writes (test_dev)"
else
	echo "FAIL devices unit test:"; ./test_dev; fail=1
fi

# Options read as their help says: -F d's second in decimal,
# -t 0 and an -i time that is not a number refused
opts=""
./max80 -T -t 0.01 -F d:800:0 >/dev/null 2>&1 && opts="${opts}d800 "
./max80 -T -t 0.01 -F d:1a:0 >/dev/null 2>&1 || opts="${opts}no1a "
t20 ./max80 -T -t 0 >/dev/null 2>&1 </dev/null; [ $? = 2 ] && opts="${opts}not0 "
./max80 -T -t 0.01 -i a:/dev/null@nan >/dev/null 2>&1 || opts="${opts}nonan "
check "-F d:800 taken, d:1a, -t 0 and -i @nan refused" \
	"d800 no1a not0 nonan " "$opts"

# xcpmz80, built in XCPMZ80, boots to its prompt and lists its disk
: "${XCPMZ80:=../../max80_xcpmz80}"
X=$XCPMZ80/build/xcpmz80.imd
if [ -f "$X" ]; then
	out=$(./max80 -K -a "$X" -t 15 -e 'A:\>' -k 'DIR\r')
	check "xcpmz80 boots to its sign-on" "XCP/M-Z80" "$out"
	check "and DIR lists its files" "LDFONT   COM" "$out"
else
	echo "skip xcpmz80 boot (make it in $XCPMZ80 first)"
fi

if ./test_track > /dev/null; then
	echo "ok   write track and read track round trip (test_track)"
else
	echo "FAIL track unit test:"; ./test_track; fail=1
fi

# Run from another folder with no -r, the ROM is the one beside the
# program's own folder; a -r that is not there is still an error
here=$(pwd)
out=$(cd / && "$here/max80" -q -T -t 1 2>&1 >/dev/null && echo started)
check "with no -r, the ROM beside the program, run from elsewhere" "started" "$out"
out=$(cd / && "$here/max80" -r /no/such.e12 -q -T -t 1 2>&1 >/dev/null || echo refused)
check "and a -r that is not there is refused" "cannot read the 512-byte boot ROM" "$out"

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
