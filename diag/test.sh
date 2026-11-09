#!/bin/sh
# Tests for the diagnostic disk. Run from diag/ after make, with the
# emulator built in ../emu. Scratch files go to build/test/.
set -u
cd "$(dirname "$0")"
EMU=../emu/max80
DISK=build/diag.imd
FONT=../xcpmz80/src/font.bin
T=build/test
fail=0
P='Serial port A 9600-8N1 mirrors screen output.'	# the menu's last line
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

run() {		# seconds, keys, more max80 arguments
	s=$1 k=$2
	shift 2
	$EMU -T -f -a $DISK -t "$s" -e "$P" -k "$k" "$@"
}

# Keeps the screen rows of codes 20h-7Fh of the character set, the rest
# blank: the text dump shows codes 00h-1Fh as lower case letters
charrows() {
	awk 'NR >= 5 && NR <= 10 { print; next } { print "" }' "$1"
}

frame() {	# name, extra args for test_frame.py, text filter, max80 args...
	name=$1 extra=$2 filt=$3
	shift 3
	$EMU -f -a $DISK -e "$P" "$@" -p $T/f.pgm > $T/f.txt
	if [ "$filt" = chars ]; then
		charrows $T/f.txt > $T/g.txt
	else
		cp $T/f.txt $T/g.txt
	fi
	out=$(python3 ../emu/test_frame.py $T/f.pgm $T/g.txt $FONT $extra)
	check "$name" " 0 rows wrong" "$out"
}

out=$(run 4 '')
check "boots to the menu" "MAX-80 DIAGNOSTIC" "$out"
check "the menu prompt" "Select item to run:" "$out"
check "boot drive" 'Boot device: 8" floppy drive' "$out"
check "RAM found" "Detected RAM: 128K" "$out"
check "the second column of the menu" "    H  Winchester interface" "$out"

out=$($EMU -T -f -D 1 -a build/diag_525.imd -t 4)
check "5.25-inch disk boots" 'Boot device: 5.25" floppy drive' "$out"

out=$(run 4 1)
check "video RAM passes" "Video RAM (D16): PASS, 2048 bytes, March U, 4 backgrounds" "$out"
check "with no running line" "lines 0." "lines $(printf '%s\n' "$out" | grep -c 'RAM test:')."
out=$(run 4 2)
check "font RAM passes" "Font RAM (E21): PASS, 2048 bytes, March U, 4 backgrounds" "$out"

out=$(run 4 1 -F v:123:2)
check "video RAM finds a bad bit" "Video RAM (D16): FAIL, 12 errors" "$out"
check "video RAM names it" "offset 0123h, wrote FFh, read FBh. Bad bits D7-D0: 00000100" "$out"
out=$(run 4 2 -F f:5A1:7)
check "font RAM finds a bad bit" "Font RAM (E21): FAIL, 12 errors" "$out"
check "font RAM names it" "offset 05A1h, wrote FFh, read 7Fh. Bad bits D7-D0: 10000000" "$out"

out=$(run 20 6)
check "banking passes" "Banking: PASS" "$out"
check "main RAM passes" "Main RAM, March U: A1 PASS A2 PASS B1 PASS B2 PASS" "$out"
check "and says it is done" "Main RAM test: DONE" "$out"
check "retention passes" "Retention, 1 s twice: A1 NOT TESTED A2 PASS B1 PASS B2 PASS" "$out"
out=$(run 5 6)
check "main RAM shows its progress" "Main RAM test: B1, March U step 4 of 5, " "$out"
out=$(run 20 6 -F m:9123:4)
check "main RAM finds a bad bit in A2" "A2: 3 errors, first at offset 1123h, wrote FFh, read EFh." "$out"
check "and names its row" "Bad bits D7-D0: 00010000, in the bank A row of 4164s." "$out"
check "retention finds the bad bit in A2" "Retention, 1 s twice: A1 NOT TESTED A2 FAIL B1 PASS B2 PASS" "$out"
check "and counts it" "A2: 1 retention errors, bad bits D7-D0: 00010000." "$out"
out=$(run 20 6 -F m:4321:6)
check "main RAM finds a bad bit in A1" "A1: 3 errors, first at offset 4321h, wrote FFh, read BFh." "$out"
out=$(run 20 6 -F m:1FFFF:7)
check "main RAM finds a bad bit in B2" "Bad bits D7-D0: 10000000, in the bank B row of 4164s." "$out"
out=$(run 20 6 -F c:3:2)
check "banking finds B2 decoded as B1" "B1 in the high half reads B2h, not B1h." "$out"
check "and does not march them" "B1 NOT TESTED B2 NOT TESTED" "$out"
out=$(run 20 6 -F c:1:0)
check "A2 decoded as A1 does not crash" "A1 NOT TESTED A2 NOT TESTED B1 PASS B2 PASS" "$out"
out=$(run 20 6 -F m:9123:4)
check "a chunk left out of the low half check" "Banking: PASS, not every chunk checked" "$out"
check "is named" "A2 in the low half NOT CHECKED" "$out"

out=$(run 20 6 -m 64)
check "64K: bank B not found" "Bank B not found, testing 64K." "$out"
check "and A only tested" "Main RAM, March U: A1 PASS A2 PASS" "$out"
check "and the footer says so" "Detected RAM: 64K" "$out"
out=$(run 20 6 -m 64f)
check "64K on a floating bus: bank B not found" "Bank B not found, testing 64K." "$out"

# A report longer than the results area: a page, a key, the rest, a key
# for the menu, which then comes back whole
printf '6 ' > $T/in.txt
out=$($EMU -T -f -a $DISK -t 24 -i a:$T/in.txt -o a:$T/siopg.txt -F c:3:2 -F m:9123:4)
check "a long report waits a page" "More: any key." "$(cat $T/siopg.txt)"
check "then shows the rest" "  Bad bits D7-D0: 00010000, in the bank A row of 4164s." "$(printf '%s\n' "$out" | sed -n 16p)"
check "and waits before the menu" "Any key for the menu." "$(printf '%s\n' "$out" | sed -n 24p)"
printf '6  ' > $T/in.txt
out=$($EMU -T -f -a $DISK -t 26 -i a:$T/in.txt -F c:3:2 -F m:9123:4)
check "the menu whole after a long report" "$P" "$(printf '%s\n' "$out" | sed -n 24p)"
check "and the results area clear" "lines 0." "lines $(printf '%s\n' "$out" | sed -n 15,23p | grep -c 'Bad bits\|Main RAM')."

# Run all with a failure: stopped by a key, the counts and the report stay
printf 'A ' > $T/in.txt
out=$($EMU -T -f -a $DISK -t 28 -i a:$T/in.txt -F m:9123:4)
check "run all with a failure counts it" "Pass 1, failed 1: video RAM 0, font RAM 0, main RAM 1." "$out"
check "and keeps the report" "A2: 3 errors, first at offset 1123h" "$out"
check "cut where it runs out, until a key" "More lines: see the serial copy, or run the test alone. Any key for the menu." "$out"

out=$($EMU -T -f -a $DISK -t 8 -e "$P" -k '7abc\U\1' -o a:$T/siok.txt)
check "keyboard test marks pressed keys" "801h| @      | A+     | B+     | C+     | D      |" "$out"
check "and the arrows" "840h| ENTER  | CLEAR  | BREAK  | UP+    |" "$out"
check "and the function keys" "880h| SHIFT  | F1+    |" "$out"
check "and no name where there is no key" "| ESC    |        | CTRL   |" "$out"
# 6 when the menu's 7 is still down at the test's first scan, which
# depends on where the tick falls
if printf '%s\n' "$out" | grep -qE 'Keys pressed: [56] of 63'; then
	echo "ok   and counts them"
else
	echo "FAIL and counts them"
	fail=1
fi
check "a key shown while down" "[A]" "$(cat $T/siok.txt)"
# Spaces first: keys typed while the test draws its screen are marked,
# but only the first is taken as a key
S='                                        '
out=$(run 10 "7$S\\e\\e\\e" | head -1)
check "ESC three times leaves the keyboard test" "MAX-80 DIAGNOSTIC" "$out"
out=$(run 10 "7$S\\e\\ea\\e" | head -1)
check "ESC must be three in a row" "KEYBOARD TEST" "$out"
# Two beeps from the boot ROM, then one for each key going down
$EMU -T -f -a $DISK -t 10 -e "$P" -k "7${S}abc" -s $T/kbeep.wav > /dev/null
if out=$(python3 ../emu/test_sound.py $T/kbeep.wav 5+ 2>&1); then
	echo "ok   each key beeps"
else
	echo "FAIL each key beeps: $out"
	fail=1
fi
printf 7X1 > $T/in.txt
$EMU -T -f -a $DISK -t 8 -i a:$T/in.txt -o a:$T/sio7.txt > /dev/null
check "a terminal key leaves the keyboard test" "Video RAM (D16): PASS" "$(cat $T/sio7.txt)"

# The lit dots in the cell of the prompt's cursor box, row 13 column 20
boxdots() {
	python3 -c "
import sys
sys.path.insert(0, '../emu')
from test_frame import read_pgm
w, h, px, (x0, y0, cw, ch, cols, rows) = read_pgm('$1')
print(sum(px[(y0 + 13 * ch + l) * w + x0 + 20 * cw + d] != 0
          for l in range(ch) for d in range(cw)))"
}
$EMU -f -a $DISK -t 4 -e "$P" -p $T/box.pgm > /dev/null
check "the cursor box at the prompt" "box 72." "box $(boxdots $T/box.pgm)."
$EMU -f -a $DISK -t 5 -e "$P" -k 6 -p $T/box.pgm > /dev/null
check "and gone while a test runs" "box 0." "box $(boxdots $T/box.pgm)."

out=$(run 4 H)
check "an item with no test written" "This test is not written." "$out"
$EMU -T -f -a $DISK -t 8 -e "$P" -k "8$S\\e" -s $T/beep.wav > $T/beep.txt
check "the beeper test goes back on ESC" "Select item to run:" "$(tail -13 $T/beep.txt)"
if grep -q BEEPER $T/beep.txt; then
	echo "FAIL the beeper test clears its lines on ESC"
	fail=1
else
	echo "ok   the beeper test clears its lines on ESC"
fi
# Two from the boot ROM, which beeps twice with 128K, and at least one
# key: keys typed while the screen draws are lost
if out=$(python3 ../emu/test_sound.py $T/beep.wav 3+ 2>&1); then
	echo "ok   and beeps"
else
	echo "FAIL and beeps: $out"
	fail=1
fi

D="F$S"
out=$(run 14 "${D}1RIPIPIPIP")
check "disk test selects a drive" 'Drive: DS1                 Connector: 8"' "$out"
check "and steps" "Track register: 4" "$out"
check "and turns the step rate round" "Step rate: 15 ms" "$out"
check "and reads track 0 off" "Track 0: NO" "$out"
check "and the single sided disk" "Single sided: YES" "$out"
if printf '%s\n' "$out" | grep -qE 'Speed: 3(59|60|61) RPM'; then
	echo "ok   and times the index pulse"
else
	echo "FAIL and times the index pulse"
	fail=1
fi
out=$(run 12 "${D}1RP")
check "recalibrate finds track 0" "Track 0: YES" "$out"
check "the fastest step rate" "Step rate: 3 ms" "$out"
out=$(run 12 "${D}1H")
check "the head loads" "Head loaded: YES" "$out"
out=$(run 12 "${D}1HH")
check "and unloads" "Head loaded: NO" "$out"
out=$(run 12 "${D}1E" -R a)
check "seek to the last track" "Track register: 76" "$out"
check "write protect" "Write protect: YES" "$out"
out=$(run 12 "${D}2")
check "a drive with no disk" "Speed: NO INDEX" "$out"
check "is not ready" "Ready: NO" "$out"
out=$($EMU -T -f -D 1 -a build/diag_525.imd -t 14 -e "$P" -k "${D}1M")
check "the 5.25-inch connector" 'Connector: 5.25"' "$out"
check "its step rate" "Step rate: 30 ms" "$out"
check "its motor" '5.25" motors turning: YES' "$out"
if printf '%s\n' "$out" | grep -qE 'Speed: (299|30[01]) RPM'; then
	echo "ok   and its speed"
else
	echo "FAIL and its speed"
	fail=1
fi
# READ ADDRESS on both sides of a 360K disk in drive B, then no disk
X=../xcpmz80/build/xcpmz80_525.imd
make -s -C ../xcpmz80 build/xcpmz80_525.imd >/dev/null	# not in its plain make
out=$($EMU -T -f -D 1 -a build/diag_525.imd -b $X -t 20 -e "$P" -k "${D}A")
check "the ID read needs a drive" "NONE: select a drive with 1-4 first" "$out"
out=$($EMU -T -f -D 1 -a build/diag_525.imd -b $X -t 20 -e "$P" -k "${D}2A")
check "and the motor on" "NONE: turn the motor on with M first" "$out"
out=$($EMU -T -f -D 1 -a build/diag_525.imd -b $X -t 20 -e "$P" -k "${D}2MRA")
check "the ID fields of side 0" "Side 0: MFM, track 0, 512 bytes, sectors 0 1 2 3 4 5 6 7 8" "$out"
out=$($EMU -T -f -D 1 -a build/diag_525.imd -b $X -t 20 -e "$P" -k "${D}2MRSA")
check "and of side 1" "Side 1: MFM, track 0, 512 bytes, sectors 0 1 2 3 4 5 6 7 8" "$out"
out=$($EMU -T -f -D 1 -a build/diag_525.imd -t 30 -e "$P" -k "${D}2MA")
check "none with no disk" "NONE: no index pulses, no disk in or the drive not turning" "$out"
out=$(run 12 "${D}\\e" | head -1)
check "ESC leaves the disk test" "MAX-80 DIAGNOSTIC" "$out"
out=$(run 8 "${D}1R")
check "a command done" "Last command: DONE" "$out"
out=$(run 18 "$D" -F d:2:0)
check "an FDC stuck busy times out" "Last command: TIMED OUT" "$out"
out=$(run 8 "${D}\\e" -F d:2:0)
check "ESC stops a command" "Last command: STOPPED" "$out"
out=$(run 10 "${D}\\e$S\\e" -F d:2:0 | head -1)
check "and a second ESC leaves" "MAX-80 DIAGNOSTIC" "$out"

out=$(run 8 G)
check "video timing reads display enable" "Display enable, SYSFLG bit 6: TOGGLING" "$out"
check "and finds the vertical blank" "Vertical blank found: YES" "$out"
check "and counts the lines of picture" "Lines of picture: 216" "$out"
# The frame is 59.97 Hz against the 61.035 Hz tick, the CPU at
# 15.2 MHz / 3. The line count can be one turn of the polling
# loop out, about 0.1%.
for re in 'Lines a frame: 26(3\.[7-9]|4\.[0-3])' 'Frame rate: 59\.9[5-9] Hz' \
    'Line rate: 15\.8[1-5] kHz' 'Line period: 63\.[0-3] us'; do
	if printf '%s\n' "$out" | grep -qE "$re"; then
		echo "ok   video timing: $re"
	else
		echo "FAIL video timing: $re"
		fail=1
	fi
done
# A key typed while it measures is lost, so ESC comes from the terminal
printf 'G\0331' > $T/in.txt
$EMU -T -f -a $DISK -t 12 -i a:$T/in.txt -o a:$T/siog.txt > /dev/null
check "ESC leaves the video timing test" "Video RAM (D16): PASS" "$(cat $T/siog.txt)"

printf HELLO > $T/b.txt
out=$(run 6 9 -i b:$T/b.txt)
check "serial test shows both channels" "Rate:               9600                          9600" "$out"
check "and the inputs" "CTS, pin 5:         ON                            ON" "$out"
check "and counts the bytes on channel B" "Bytes received:     0                             5" "$out"
check "and shows them" "48 45 4C 4C 4F" "$out"
out=$(run 8 "9${S}BSRDTK" -o b:$T/siob.txt)
check "channel B picked" "Channel B SELECTED" "$out"
check "its rate, DTR and RTS" "9600                          19200" "$out"
check "DTR off" "DTR, pin 20:        ON                            OFF" "$out"
check "RTS off" "RTS, pin 4:         ON                            OFF" "$out"
check "break on TxD" "TxD, pin 2:         IDLE                          BREAK" "$out"
check "the test line goes out on channel B" "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789" "$(cat $T/siob.txt)"
printf '9\0331' > $T/in.txt
$EMU -T -f -a $DISK -t 10 -i a:$T/in.txt -o a:$T/sio9.txt > /dev/null
check "ESC on channel A leaves the serial test" "Video RAM (D16): PASS" "$(cat $T/sio9.txt)"
out=$(run 10 "9$S\e" | head -1)
check "and ESC on the keyboard" "MAX-80 DIAGNOSTIC" "$out"
# Channel A at 75 baud: the screen copy stops, and is back after ESC
$EMU -T -f -a $DISK -t 12 -e "$P" -k "9${S}RRR\\e${S}1" -o a:$T/sio9r.txt > /dev/null
check "the screen copy back after channel A was slow" "Video RAM (D16): PASS" "$(cat $T/sio9r.txt)"

out=$(run 6 E -D 0xA2)
check "DIP switch test reads the switches" "Position:     UP    DOWN  UP    DOWN  DOWN  DOWN  UP    DOWN" "$out"
check "and the byte" "DIPSW: A2h" "$out"
check "and the boot device" 'Boot device, switches 6-8: 8" floppy drive' "$out"
out=$($EMU -T -f -D 0xF9 -a build/diag_525.imd -t 6 -e "$P" -k E)
check "switches up on a 5.25-inch boot" 'Boot device, switches 6-8: 5.25" floppy drive' "$out"
check "and its byte" "DIPSW: F9h" "$out"
out=$(run 10 "E$S\e" | head -1)
check "ESC leaves the DIP switch test" "MAX-80 DIAGNOSTIC" "$out"

# Write-through to RAM and memory timing (items I and J) are off the
# menu, so not checked. The checks were:
# out=$(run 12 I)
# check "write-through test, RAM900" "RAM900 BFF  80h  80h  80h      40h  40h  40h" "$out"
# check "a latch keeps a RAM copy" "MLATCH 7D8  80h  80h  80h      40h  40h  40h" "$out"
# check "a device write lands in A1" "SIODA  7E4  80h  80h  80h      40h  40h  40h" "$out"
# out=$(run 12 I -m 64)
# check "and without bank B it leaves B1 and B2 out" "RAM900 BFF  80h  --   --       40h  --   --" "$out"
# out=$(run 14 "I$S ")
# check "a key leaves the write-through test" "MAX-80 DIAGNOSTIC" "$out"
# check "the screen copy survives it" "Write-through to RAM" "$out"

pp() {		# a printer test row: label, values
	printf '%-30s%s' "$1" "$2"
}
out=$(run 6 B)
check "printer test reads the status" "$(pp 'Status, PSTAT:' F0h)" "$out"
check "and BUSY" "$(pp 'BUSY, pin 21, bit 7:' 'HIGH    NO')" "$out"
check "and FAULT" "$(pp 'FAULT, pin 28, bit 4:' 'HIGH    NO')" "$out"
check "no printer: not ready for CP/M" "$(pp 'Ready for CP/M, BUSY LOW:' NO)" "$out"
check "and writes 00h at the start" "$(pp 'Data out, PDATA:' 00h)" "$out"
out=$(run 6 B -l $T/prn.txt)
check "a printer: its status" "$(pp 'Status, PSTAT:' 30h)" "$out"
check "ready for CP/M" "$(pp 'Ready for CP/M, BUSY LOW:' YES)" "$out"
check "and for LDOS" "$(pp 'Ready for LDOS, status 3Xh:' YES)" "$out"
out=$(run 8 "B${S}S" -l $T/prn.txt)
check "the test line goes to the printer" "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789" "$(cat $T/prn.txt)"
if printf '%s\n' "$out" | grep -qE '^BUSY, pin 21, bit 7: +(HIGH|LOW) +YES'; then
	echo "ok   BUSY marked as changed while sending"
else
	echo "FAIL BUSY not marked as changed"
	fail=1
fi
check "sending" "$(pp 'Mode:' SENDING)" "$out"
out=$(run 8 "B${S}07")
check "data bits 0 and 7 set" "$(pp 'Data out, PDATA:' 81h)" "$out"
check "and their pins" "$(pp 'PD7-PD0, pins 17-3:' 10000001)" "$out"
check "and three writes" "$(pp 'Writes, each strobes pin 1:' 3)" "$out"
out=$(run 8 "B${S}W")
check "walking" "$(pp 'Mode:' WALKING)" "$out"
out=$(run 10 "B$S\e" | head -1)
check "ESC leaves the printer test" "MAX-80 DIAGNOSTIC" "$out"
out=$(run 8 D)
if printf '%s
' "$out" | grep -qE '^Time: +[0-2][0-9]:[0-5][0-9]:[0-5][0-9]$'; then
	echo "ok   clock test shows the time"
else
	echo "FAIL clock test: no time"
	fail=1
fi
check "and the hour mode" "$(pp 'Hour mode, register 5:' 24-HOUR)" "$out"
check "and its digits in range" "$(pp 'Digits in range:' YES)" "$out"
check "and the seconds counting" "$(pp 'Seconds counting:' YES)" "$out"
check "61 ticks a second" "$(pp 'Ticks a second:' 61)" "$out"
check "the button not held" "$(pp 'TIME SET button:' 'NOT HELD')" "$out"
out=$(run 8 D -C)
check "with -C the button held" "$(pp 'TIME SET button:' 'HELD')" "$out"
check "  and the digits still in range" "$(pp 'Digits in range:' YES)" "$out"
# Memory timing is off the menu with write-through. The checks
# were, no stretch with no -V, n/2 T an access with -V n, a pass on
# plain RAM 149 T:
# out=$(run 40 J)
# check "memory timing: video RAM reads cost nothing extra" "Video RAM, reads:    0.00 to 0.00 T" "$out"
# check "  nor SLORAM writes" "SLORAM, writes:      0.00 to 0.00 T" "$out"
# check "  plain RAM makes 4457 passes in 8 ticks" "Plain RAM: 4457 passes of 149 T" "$out"
# out=$(run 40 J -V 4)
# if printf '%s\n' "$out" | grep -qE 'Video RAM, writes: +(1\.9[89]|2\.0[0-2]) to (1\.9[89]|2\.0[0-2]) T'; then
# 	echo "ok     with -V 4 a video RAM write costs 2 T"
# else
# 	echo "FAIL memory timing with -V 4:"; printf '%s\n' "$out"; fail=1
# fi
out=$(run 10 "D$S\e" | head -1)
check "ESC leaves the clock test" "MAX-80 DIAGNOSTIC" "$out"

bx() {		# a bus test row at the right: label, value
	printf '%-15s%s' "$1" "$2"
}
out=$(run 6 C)
check "bus test: no card, every port FFh" "$(bx 'Ports not FFh:' 0)" "$out"
check "port 00h chosen" "00[FF]FF FF" "$out"
check "and its read" "$(bx 'Reads:' FFh)" "$out"
out=$(run 6 C -x 40)
check "a card at 40h found" "$(bx 'Ports not FFh:' 1)" "$out"
check "and shown on the grid" "40 00 FF FF" "$out"
out=$(run 8 "C${S}\\R\\D")
check "arrows move the port" "10 FF[FF]FF" "$out"
check "and the port shown" "$(bx 'Port:' 11h)" "$out"
out=$(run 8 "C${S}P40K" -x 40)
check "a latch reads back" "$(bx 'Read back:' PASS)" "$out"
check "and twelve writes" "$(bx 'Writes:' 12)" "$out"
check "the last read on the grid" "40[80]FF" "$out"
out=$(run 8 "C${S}P41K" -x 40)
check "no card fails the read-back" "$(bx 'Read back:' FAIL)" "$out"
check "and says what came back" "Wrote 00h, read FFh" "$out"
out=$(run 8 "C${S}P40V5AOR" -x 40)
check "a byte typed" "$(bx 'Byte to write:' 5Ah)" "$out"
check "written and read" "$(bx 'Reads:' 5Ah)" "$out"
check "reading" "$(bx 'Mode:' READING)" "$out"
out=$(run 8 "C${S}W")
check "writing" "$(bx 'Mode:' WRITING)" "$out"
out=$(run 10 "C$S\e" | head -1)
check "ESC leaves the bus test" "MAX-80 DIAGNOSTIC" "$out"

printf 61 > $T/in.txt
$EMU -T -f -a $DISK -t 24 -i a:$T/in.txt -o a:$T/sio6.txt > /dev/null
check "the menu works after the main RAM test" "Video RAM (D16): PASS" "$(cat $T/sio6.txt)"

$EMU -T -f -a $DISK -t 72 -e "$P" -k A -o a:$T/sioa.txt > /dev/null
check "run all counts passes" "Pass 3, failed 0: video RAM 0, font RAM 0, main RAM 0." "$(cat $T/sioa.txt)"
check "serial copy of the menu" "$P" "$(cat $T/sioa.txt)"

printf 1 > $T/in.txt
$EMU -T -f -a $DISK -t 6 -i a:$T/in.txt -o a:$T/sio1.txt > /dev/null
check "a key from the serial port" "Video RAM (D16): PASS" "$(cat $T/sio1.txt)"

frame "menu after the font RAM test" thin none -t 6 -k 2
frame "keyboard test" thin none -t 8 -k 7abc
frame "character set" "" chars -t 4 -k 5
frame "character set, 40 columns" wide chars -t 6 -k '4       '
# The odd cells screen draws both texts itself, the cells interleaved
out=$(run 10 '4         ' | sed -n 12p)
check "the odd cells screen has its text" "EOVDEDN  CCEELLLLSS,,  RR22  ==  9987" "$out"

# A NUL from the terminal, CTRL-@, is a key: it leaves the keyboard test
printf '7\0001' > $T/in.txt
$EMU -T -f -a $DISK -t 8 -i a:$T/in.txt -o a:$T/sio0.txt > /dev/null
check "a NUL from the terminal is a key" "Video RAM (D16): PASS" "$(cat $T/sio0.txt)"

[ $fail = 0 ] && echo "all passed"
exit $fail
