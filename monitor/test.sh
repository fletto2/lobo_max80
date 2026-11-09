#!/bin/sh
# Tests for the monitor. Run from monitor/ after make, with the
# emulator built in ../emu. Scratch files go to build/test/.
set -u
cd "$(dirname "$0")"
EMU=../emu/max80
DISK=build/monitor.imd
T=build/test
SREC="python3 tools/srec.py"
fail=0
P='A1>|A2>|B1>|B2>'
ASK='That is the I/O block: a read of 7E0h clears the tick. Y goes on:'
rm -rf $T
mkdir -p $T

check() {	# name, text to find, output
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		echo "ok   $1"
	else
		echo "FAIL $1: no '$2' in:"
		printf '%s\n' "$3"
		fail=1
	fi
}

nocheck() {	# name, text that must not be there, output
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		echo "FAIL $1: found '$2' in:"
		printf '%s\n' "$3"
		fail=1
	else
		echo "ok   $1"
	fi
}

run() {		# seconds, keys, more max80 arguments
	s=$1 k=$2
	shift 2
	$EMU -T -f -a $DISK -t "$s" -e "$P" -k "$k" "$@"
}

# Boots
out=$(run 4 '')
check "boots from the 8-inch disk" "MAX-80 monitor." "$out"
check "finds 128K" "RAM: A1 A2 B1 B2" "$out"
out=$($EMU -T -f -D 1 -a build/monitor_525.imd -t 5 -e "$P" -k '')
check "boots from the 5.25-inch disk" "MAX-80 monitor." "$out"

out=$(run 6 '?\r')
check "help lists RUN" "RUN chunk" "$out"
check "help warns of A1" "0400-0BFF and 7400-7BFF" "$out"

# Each chunk, across where the block sits at F000h, and the end of it
for c in A2 B1 B2; do
	out=$(run 14 "F $c:6FF0 20 5A\rD $c:6FE0 40\rK $c:6FF0 20\rF $c:7FF0 10 C3\rD $c:7FF0 10\r")
	check "F, D in $c under the block" "$c:7000  5A 5A" "$out"
	check "D in $c before the fill" "$c:6FE0  00 00" "$out"
	check "K in $c" "Sum 40h, CRC-16 94B6h" "$out"
	check "the last line of $c" "$c:7FF0  C3 C3" "$out"
done
out=$(run 10 'F A1:3800 20 77\rD A1:3800 10\rD 3800 10\r')
check "A1 by chunk" "A1:3800  77 77" "$out"
check "the same by Z80 address" "3800  77 77" "$out"
out=$(run 10 'F 8100 10 42\rD A2:100 10\r')
check "a Z80 address reaches A2 high" "A2:0100  42 42" "$out"
out=$(run 8 'D 0 10\rD\r')
check "D alone goes on" "0010  " "$out"

# Refused
out=$(run 12 'F 1800 10 0\rF A1:7F00 10 0\rF A2:7FF0 11 0\rF 3000 0 0\rD A2:8000\rX\r')
check "F over the program" "The monitor is there." "$out"
check "past a chunk" "That runs past the end." "$out"
check "length 0" "The length is 0." "$out"
check "a bad command" "What?" "$out"

# The block asks first
out=$($EMU -T -f -a $DISK -t 9 -e "$P|$ASK" -k 'D F7D0 10\rnD F7D0 10\rY')
check "D on the block asks" "$ASK" "$out"
check "and goes on with Y" "F7D0  " "$out"
out=$($EMU -T -f -a $DISK -t 7 -e "$P|$ASK" -k 'D F7D0 10\rn')
nocheck "and stops without" "F7D0  " "$out"
out=$(run 7 'D A2:7D0 10\r')
nocheck "a chunk address does not ask" "I/O block" "$out"

# E, and a stuck bit found by E and C
PE="$P|A2:1234 00|A2:1235 00|A2:1234 AA|A2:1236 00"
out=$($EMU -T -f -a $DISK -t 9 -e "$PE" -k 'E A2:1234\rAA\r\r.\rD A2:1234 1\r')
check "E shows the new byte" "Now AAh" "$out"
check "E wrote it" "A2:1234  AA" "$out"
PE="$P|A2:1234 00|A2:1235 00"
out=$($EMU -T -f -a $DISK -t 8 -e "$PE" -F m:9234:4 -k 'E A2:1234\rFF\r.\r')
check "E finds a stuck bit" "Did not stick: wrote FFh, read EFh, bits 00010000" "$out"
out=$(run 14 'F A2:1200 100 FF\rF B1:1200 100 FF\rC A2:1200 B1:1200 100\r' -F m:9234:4)
check "C finds it" "A2:1234 EF  B1:1234 FF" "$out"
check "and counts it" "1 differences." "$out"
out=$(run 12 'F A2:1000 100 FF\rF B1:1000 100 FF\rC A2:1000 B1:1000 100\r')
check "C on the same" "0 differences." "$out"

# M between chunks, and over itself both ways
out=$(run 22 'F A2:100 10 11\rF A2:110 10 22\rM A2:100 B2:7F00 20\rD B2:7F00 20\rM A2:100 A2:108 20\rD A2:100 30\rM A2:108 A2:104 20\rD A2:100 30\r')
check "M between chunks" "B2:7F10  22 22" "$out"
check "M up over itself" "A2:0110  11 11 11 11 11 11 11 11 22 22" "$out"
check "M down over itself" "A2:0110  11 11 11 11 22 22" "$out"

# S
PE="$P|B1:7FF0 00|B1:7FF1 00|B1:7FF2 00|B1:7FF3 00"
out=$($EMU -T -f -a $DISK -t 26 -e "$PE" -k 'F B1:0 8000 0\rE B1:7FF0\r48\r65\r79\r.\rS B1:0 8000 "Hey"\rS B1:0 8000 48 65\rS B1:0 8000 "hey"\rS B1:7FF1 F 65 79\r')
check "S a string" "B1:7FF0" "$out"
check "S finds it once" "1 found." "$out"
check "S minds the case" "0 found." "$out"

# T
out=$(run 14 'T A2:0 8000\r')
check "T on all of a chunk" "0 errors in 5 patterns" "$out"
out=$(run 14 'T A2:1000 1000\r' -F m:9234:4)
check "T finds the bit" "bad bits 00010000" "$out"
check "T gives the address" "A2:1234 wrote 55 read 45" "$out"

# ESC stops a long command, from channel A
printf '\033' > $T/esc
out=$(run 7 'T B1:0 8000\r' -i a:$T/esc@4)
check "ESC stops T" "Stopped." "$out"
nocheck "before it ends" "patterns" "$out"

# ESC and BREAK from the keyboard, and rubbing out
LP='Send the S-records on channel A. ESC or BREAK stops.'
esc=$(printf '\033')
brk=$(printf '\003')
bs=$(printf '\010')
out=$($EMU -T -f -a $DISK -t 6 -e "$P|$LP" -k "L\r$esc")
check "ESC key stops L" "Stopped." "$out"
out=$($EMU -T -f -a $DISK -t 6 -e "$P|$LP" -k "L\r$brk")
check "BREAK key stops L" "Stopped." "$out"
out=$(run 7 "D A2:1Z${bs}00 10\r")
check "a rubbed out key" "A2:0100  " "$out"

# I and O
out=$(run 9 'O 40 5A\rI 40\rI 41\r' -x 40)
check "I reads the card" "Port 40h reads 5Ah" "$out"
check "a port with nothing" "Port 41h reads FFh" "$out"

# S-records, with the host not waiting for anything (-I)
$SREC s1 $T/a.s 4000 180 1
$SREC s2 $T/b.s FFD0 60 2		# A2 under the block, on into B1
out=$(run 26 'L\rP 4000 180\r' -I a:$T/a.s@3 -o a:$T/a.out)
check "L S1" "Loaded 13 lines." "$out"
check "P S1 is the file" "0 wrong of 384" "$($SREC check $T/a.out 4000 180 1)"
out=$(run 26 'L\rP A2:7FD0 30\rP B1:0 30\r' -I a:$T/b.s@3 -o a:$T/b.out)
check "L S2" "Loaded 4 lines." "$out"
check "P S2, across chunks" "0 wrong of 96" "$($SREC check $T/b.out FFD0 60 2)"

# A long file at full speed, into a chunk through the map
$SREC s2 $T/c.s 10000 2000 3
want=$($SREC crc 10000 2000 3)
out=$(run 40 'L\rK B1:0 2000\r' -I a:$T/c.s@3)
check "L keeps up" "Loaded 257 lines." "$out"
check "and nothing was lost" "$want" "$out"

# Bad records stop the load, and the rest is not run
$SREC bad $T/d.s
out=$(run 12 'L\rD 4000 8\r' -I a:$T/d.s@3)
check "a bad checksum" "Line 2: bad record or checksum." "$out"
check "line 1 went in" "4000  11 22 00" "$out"
nocheck "the rest is not run" "0000  " "$out"
python3 - $T/e.s <<'P'
import sys
b = bytes.fromhex('05180AAABB')
open(sys.argv[1], 'w', newline='').write('S1%s%02X\r\n' % (b.hex().upper(), ~sum(b) & 255))
P
out=$(run 8 'L\r' -I a:$T/e.s@3)
check "a load over the monitor" "Line 1: the monitor is there." "$out"

# G, a program from S-records, with a RET back
python3 - $T/g.s <<'P'
import sys
def rec(t, a, d):
    b = bytes([len(d) + 3]) + a.to_bytes(2, 'big') + d
    return 'S%d%s%02X\r\n' % (t, b.hex().upper(), ~sum(b) & 255)
code = bytes.fromhex('3E423200 40C9'.replace(' ', ''))	# LD A,42h, LD (4000h),A, RET
open(sys.argv[1], 'w', newline='').write(rec(1, 0x6000, code) + rec(9, 0x6000, b''))
P
out=$(run 12 'L\rG\rD 4000 1\rG A2:0\r' -I a:$T/g.s@3)
check "L gives the start" "Start 6000." "$out"
check "G comes back" "Back in the monitor." "$out"
check "G ran" "4000  42" "$out"
check "G refuses a chunk" "A chunk address cannot run" "$out"

# RUN, then all of A1
out=$(run 22 'RUN A2\rF A1:0 8000 AA\rD A1:1000 10\rD A1:7F00 10\rT A1:0 8000\rRUN B2\rRUN A1\r')
check "RUN" "Now running in A2" "$out"
check "F over the old program" "A1:1000  AA AA" "$out"
check "and the old stack" "A1:7F00  AA AA" "$out"
check "T over all of A1" "0 errors in 5 patterns" "$out"
check "RUN on" "Now running in B2" "$out"
check "RUN back" "Now running in A1" "$out"
out=$(run 16 'RUN A2\rF A1:0 8000 AA\rS A1:0 8000 AA\rC A1:0 A2:0 1\r')
check "what the console leaves in A1" "32764 found." "$out"
out=$(run 10 'RUN A2\rRUN A2\rF 1800 10 0\rF A1:1800 10 0\r')
check "RUN to where it is" "It is running there." "$out"
check "the guard moves with it" "The monitor is there." "$out"
check "and A1 is free" "Filled." "$out"
out=$(run 8 'RUN A2\r' -F m:9234:4)
check "RUN refuses bad RAM" "A2:1234 failed, so RUN stopped." "$out"

# 64K
out=$(run 10 'D B1:0 10\rRUN B2\rF A2:0 10 1\r' -m 64)
nocheck "64K shows no bank B" "RAM: A1 A2 B1" "$out"
check "B1 refused" "This machine has no such chunk." "$out"
check "A2 still works" "Filled." "$out"

[ $fail = 0 ] && echo "all passed"
exit $fail
