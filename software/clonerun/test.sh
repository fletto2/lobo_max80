#!/bin/sh
# Tests for CLONERUN.COM under xcpmz80 in the emulator, on a disk
# made in a temporary directory. Clone Runner is for xcpmz80 only.
# Needs `make` run in emu/ and xcpmz80/ first.
#
# levels.py turns down broken levels. The test build CRT.COM plays our
# test levels (tests/levels_test.txt) with key scripts (test.asm) and
# shows the runner's place on row 23: running, into brick and into
# solid, up a ladder and not past its top, down again, along a bar, off
# a bar, off a ledge, through a false brick and through gold, a hidden
# ladder not there in play, and frames mid-move dot for dot
# (tests/check_frame.py). CRT2.COM builds and copies the runner twice,
# which gives the times. Digging: holes dug left and right, crumbling,
# open, filling and brick again at their rounds, dot for dot, the
# runner in a hole, through one, caught in one, digs from a ladder and
# a bar, and digs refused.
#
# With Lode Runner's stages there (build.sh, LODERUNNER_LEVELS), the
# title (tests/check_title.py), the viewer and play are checked on them
# too: stage 1 and stage 150 dot for dot, N, P and the arrows, ENTER,
# ESC. ESC from play, the viewer and the title leaves the prompt on a
# clean screen with 9-line rows, and font RAM and VLATCH as before
# (tests/fontsum.asm).
cd "$(dirname "$0")" || exit 1
sh build.sh || exit 1
R=../..
EMU="$R/emu/max80 -r $R/reference/rom/max80.e12"
[ -x $R/emu/max80 ] || { echo "build the emulator first: make in emu/"; exit 1; }
[ -f $R/xcpmz80/build/xcpmz80.sys ] || { echo "build xcpmz80 first: make in xcpmz80/"; exit 1; }
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
B=$(pwd)/build
LEVELS=${LODERUNNER_LEVELS:-private/levels.txt}
# The game's last lines, the key help from column 12, as -e must see them
msg() {
	echo "            $(sed -n "s/^$1:[[:space:]]*db[[:space:]]*\"\(.*\)\",0\$/\1/p" clonerun.asm)"
}
HELP=$(msg m_help)
PHELP=$(msg m_phelp)
OVER=$(msg m_over)
THELP="            $(sed -n 's/^	db	23,FCOL,"\(.*\)",0$/\1/p' clonerun.asm)"
P='A:\>'
pass=0
fail=0

ok() {
	echo "ok   $1"
	pass=$((pass + 1))
}
# bad NAME [FILE]: a failed check, and the file that shows why
bad() {
	echo "FAIL $1"
	[ -n "$2" ] && sed 's/^/    | /' "$2"
	fail=$((fail + 1))
}

echo "=== levels.py"
for t in "bad_players.txt:2 runner starts" "bad_width.txt:29 tiles wide"; do
	f=${t%%:*}
	msg=${t#*:}
	if python3 tools/levels.py tests/$f 2>$T/err.txt; then
		bad "levels.py takes tests/$f"
	elif grep -qF "$msg" $T/err.txt; then
		ok "turns down tests/$f: $(cat $T/err.txt)"
	else
		bad "levels.py on tests/$f" $T/err.txt
	fi
done
if python3 tools/levels.py tests/levels_test.txt; then
	ok "takes tests/levels_test.txt"
else
	bad "tests/levels_test.txt"
fi

COMS="$B/CRT.COM $B/CRT2.COM $B/FONTSUM.COM"
[ -f $B/CLONERUN.COM ] && COMS="$B/CLONERUN.COM $COMS"
(cd $R/xcpmz80 && python3 tools/mkdisk.py build/xcpmz80.sys $T/xc.imd $COMS) >/dev/null || exit 1

# run NAME KEYS SECONDS: the screen in $T/NAME.txt, the frame in $T/NAME.pgm
run() {
	$EMU -a $T/xc.imd -t $3 -e "$P|$HELP|$PHELP|$THELP|$OVER" -k "$2" -p $T/$1.pgm > $T/$1.txt
}
# frame NAME LEVEL [play] [test] [holes]: the frame shows the level, dot for dot
frame() {
	n=$1
	shift
	python3 tests/check_frame.py $T/$n.pgm $T/$n.txt "$@" > $T/chk.txt 2>&1
}
# row22 NAME: the level number on row 22
row22() {
	sed -n 23p $T/$1.txt | sed 's/^ *LEVEL \([0-9][0-9][0-9]\) .*/\1/'
}
# row23 NAME: the test build's X, U, Y, W, M and T
row23() {
	sed -n 24p $T/$1.txt | awk '{ print $2, $4, $6, $8, $10, $14 }'
}

echo "=== the runner"
run before 'FONTSUM\r' 10
BEFORE=$(grep '^VL ' $T/before.txt)

# CRT L S: test level L, script S (test.asm), then X, U (the offset
# across), Y, W (down) and M (0 standing, 1 running, 2 climbing, 3
# hanging, 4 falling, 5 digging) as row 23 should show them, and T, the
# rounds, for a script that freezes, - for one that does not
while read l s x u y w m t what; do
	run s$s "CRT $l $s\\r" 14
	got=$(row23 s$s)
	want="$x $u $y $w $m $t"
	[ $t = - ] && got="${got% *} -"
	if [ "$got" = "$want" ]; then
		ok "script $s, $what: $got"
	else
		bad "script $s, $what: $got, not $want" $T/s$s.txt
	fi
done <<EOF
1 1 04 FD 0E 00 01 000D RIGHT 13 rounds: 13 eighths from column 2, frozen mid-tile
1 2 07 00 0E 00 00 - RIGHT held, stopped by the brick in column 8
1 3 01 00 0E 00 00 - LEFT held, stopped by the solid block in column 0
2 4 05 00 07 00 02 - to the ladder and UP, on its top and no further
2 5 05 00 0E 00 02 - up the ladder and DOWN to its foot
3 6 0C 00 09 00 03 - off the ledge onto the bar and along it
3 7 0C 00 0E 00 00 - along the bar and DOWN, falling to the floor
4 8 07 00 0E 00 00 - off a ledge, falling to the floor
4 9 07 00 08 00 04 003C off a ledge, frozen in the fall 24 lines down
8 20 08 00 0E 00 00 - over gold in a ledge: gold holds nothing up, through it to the floor, taking it
8 21 01 00 0E 00 00 - over a false brick: through it to the floor
9 22 14 00 0E 00 00 - onto a hidden ladder and UP: not there in play, no climb
EOF

# The pace: 4 seconds of play make about 102 rounds, 12/5 ticks each.
# Row 23 changes every 16 frames, so give or take 14.
run pa 'CRT 1 2\r' 8
run pb 'CRT 1 2\r' 12
ta=$(row23 pa); tb=$(row23 pb)
n=$(( 0x${tb##* } - 0x${ta##* } ))
if [ $n -ge 88 ] && [ $n -le 116 ]; then
	ok "4 s of play are $n rounds, about 102"
else
	bad "the pace: $n rounds in 4 s, from '$ta' to '$tb'" $T/pb.txt
fi

# script:level:extra checks, script 1 taking the gold at 4,14
for t in "1:1:score=250;gold=0;4,14=open" 9:4:- 21:8:-; do
	s=${t%%:*}
	l=${t#*:}
	x=${l#*:}
	l=${l%%:*}
	[ "$x" = - ] && x=
	if frame s$s $l play test $(echo $x | tr ';' ' '); then
		ok "script $s, the frame: $(cat $T/chk.txt)"
	else
		bad "script $s, the frame" $T/chk.txt
	fi
done

# The times: the fewest passes left in the picture (37 T-states each) and
# in the blank (30 each), once and with the build and copy done twice
run once 'CRT 1 10\r' 16
run twice 'CRT2 1 10\r' 16
set -- $(sed -n 24p $T/once.txt | awk '{ print $16, $18 }') \
    $(sed -n 24p $T/twice.txt | awk '{ print $16, $18 }')
if [ $# = 4 ]; then
	i1=$(printf %d 0x$1) v1=$(printf %d 0x$2) i2=$(printf %d 0x$3) v2=$(printf %d 0x$4)
	build=$((37 * (i1 - i2)))
	copy=$((30 * (v1 - v2)))
	echo "     a figure build takes $build T-states, a copy $copy"
	echo "     left in the worst frame: $((37 * i1)) T-states of the picture, $((30 * v1)) of the blank"
	if [ $i2 -gt 0 ] && [ $v2 -gt 0 ] && [ $build -gt 0 ] && [ $copy -gt 0 ]; then
		ok "every frame fits, even with the figure built and copied twice"
	else
		bad "the times: $*" $T/twice.txt
	fi
else
	bad "the times" $T/once.txt
fi

echo "=== digging"
# dig23 NAME: row 23's X, Y, M, H (holes in the table), F (the first
# hole's phase: 0-3 crumbling, 4 open, 5-8 filling, FF free) and R (the
# times the level started again)
dig23() {
	sed -n 24p $T/$1.txt | awk '{ print $2, $6, $10, $20, $22, $24 }'
}
# NAME LEVEL SCRIPT FREEZE (- for the script's own) SECONDS X Y M H F R,
# then the holes for a frame check (- for none, . for no frame check),
# then what it shows
while read n l s f sec x y m h ph r holes what; do
	[ $f = - ] && f=
	run $n "CRT $l $s $f\\r" $sec
	got=$(dig23 $n)
	want="$x $y $m $h $ph $r"
	if [ "$got" = "$want" ]; then
		ok "$what: $got"
	else
		bad "$what: $got, not $want" $T/$n.txt
		continue
	fi
	[ "$holes" = . ] && continue
	[ "$holes" = - ] && holes=
	if frame $n $l play test $(echo $holes | tr ';' ' '); then
		ok "    the frame: $(cat $T/chk.txt)"
	else
		bad "    the frame" $T/chk.txt
	fi
done <<EOF
d1 5 11 9 14 0A 0D 05 01 02 00 11,14=crumble3 X digs right, round 9: the brick crumbling, step 3 of 4
d2 5 11 40 14 0A 0D 00 01 04 00 11,14=open X digs right, round 40: the hole open, the runner standing
d3 5 12 12 14 0A 0D 05 01 03 00 9,14=crumble4 Z digs left, round 12: step 4 of 4, facing left
d4 5 12 40 14 0A 0D 00 01 04 00 9,14=open Z digs left, round 40: the hole open
d5 5 12 345 22 0A 0D 00 01 06 00 9,14=fill2 round 345: the hole filling, step 2 of 4
d6 5 11 380 22 0A 0D 00 00 FF 00 - round 380: brick again, the level as it was
d7 5 13 200 14 0B 0E 00 01 04 00 11,14=open into the hole, standing in it on the solid, UP held: no way up its walls
d8 5 13 - 24 0A 0D 00 00 FF 01 men=4 caught in the hole as it filled: the level from its start again, a life gone
d9 5 14 200 14 0B 0E 00 02 04 00 10,14=open;11,14=open two holes side by side: into one, out sideways into the other, stopped by brick
d10 4 16 - 14 03 0E 00 01 04 00 3,6=open over a hole in a ledge one brick thick: through it to the floor
d11 4 17 - 14 07 08 04 00 FF 00 . Z held off a ledge's edge: no dig in the air, falling
d12 7 18 - 14 0B 0D 02 01 04 00 12,14=open X on a ladder: digs, and back to climbing
d18 7 29 - 14 0B 0D 02 01 04 00 12,14=open X partway up a ladder: digs all the same, in the middle of its tile
d13 3 19 - 14 06 09 03 01 04 00 5,10=open Z hanging from a bar: digs the ledge's end, and back to hanging
d14 6 12 - 14 0A 0D 00 00 FF 00 . Z refused: brick beside the runner
d15 6 11 - 14 0A 0D 00 00 FF 00 . X refused: a solid block to dig
d16 7 12 - 14 0A 0D 00 00 FF 00 . Z refused: a ladder to dig
d17 7 11 - 14 0A 0D 00 00 FF 00 . X refused: a ladder beside the runner
EOF

# The hole's times: the first hole's phase frozen at each side of each
# change. Script 11 digs in round 0, and each round runs the holes before
# the runner, so a phase that starts in round r shows when frozen at r+1.
edges=ok
for e in 3:00 4:01 12:03 13:04 332:04 333:05 372:08 373:FF; do
	f=${e%:*}
	if [ $f -gt 300 ]; then sec=22; else sec=14; fi
	run edge "CRT 5 11 $f\\r" $sec
	set -- $(dig23 edge)
	if [ "$5" != ${e#*:} ]; then
		edges="frozen at round $f, phase $5, not ${e#*:}"
		break
	fi
done
if [ "$edges" = ok ]; then
	ok "the hole's times: dug in round 0, open in 12 (0.47 s), filling in 332 (320 rounds, 12.6 s), brick in 372 (40, 1.97 s), open and filling 360 rounds, 17.7 s, the C64's 180"
else
	bad "the hole's times: $edges" $T/edge.txt
fi

# The times with holes: a row dug as the runner goes left (script 15)
run hones 'CRT 5 15\r' 16
run htwice 'CRT2 5 15\r' 16
set -- $(sed -n 24p $T/hones.txt | awk '{ print $16, $18, $20 }') \
    $(sed -n 24p $T/htwice.txt | awk '{ print $16, $18 }')
if [ $# = 5 ] && [ $(printf %d 0x$3) -gt 5 ] && [ $(printf %d 0x$4) -gt 0 ] && [ $(printf %d 0x$5) -gt 0 ]; then
	echo "     with $(printf %d 0x$3) holes, left in the worst frame: $((37 * 0x$1)) T-states of the picture, $((30 * 0x$2)) of the blank"
	echo "     and with the figure built and copied twice: $((37 * 0x$4)) and $((30 * 0x$5))"
	ok "every frame with holes fits, even with the figure built and copied twice"
else
	bad "the times with holes: $*" $T/htwice.txt
fi

echo "=== the keys"
# On the keyboard row 23 stays the help line until a key moves the
# runner, then shows the dig's way in D, FF left, 01 right, and H holes.
run knone 'CRT 5 0\r' 14
if [ "$(sed -n 24p $T/knone.txt)" = "$PHELP" ]; then
	ok "the ENTER that starts a stage does not dig or start the guards"
else
	bad "the ENTER that started the stage counted" $T/knone.txt
fi
for t in 'z:FF:Z' 'x:01:X' '^:01:the ~ key' '_:01:the _/DEL key' 'A:FF:SHIFT' '\r:FF:ENTER'; do
	k=${t%%:*}
	rest=${t#*:}
	want=${rest%%:*}
	what=${rest#*:}
	run kdig "CRT 5 0\\r$k" 14
	got=$(sed -n 24p $T/kdig.txt | awk '{ print $12, $20 }')
	if [ "$got" = "$want 01" ]; then
		ok "$what digs: $got"
	else
		bad "$what: $got, not $want 01" $T/kdig.txt
	fi
done
run knew 'CRT 17 28\r' 14
if [ "$(row23 knew | awk '{ print $1 }')" = 06 ]; then
	ok "the direction pressed last goes first: DOWN held, RIGHT off the ladder"
else
	bad "DOWN then RIGHT: column $(row23 knew | awk '{ print $1 }')" $T/knew.txt
fi
run kclear "CRT 17 0\\r$(printf '\010')" 14
if [ "$(row23 kclear | awk '{ print $3, $5 }')" = "05 02" ] &&
	[ "$(sed -n 24p $T/kclear.txt | awk '{ print $8 }')" != 00 ]; then
	ok "CLEAR is DOWN: down the ladder from its top"
else
	bad "CLEAR" $T/kclear.txt
fi

echo "=== the guards"
# guard NAME: the first guard's column, offset across, row, offset down,
# pose and state, from column 66 of row 23
guard() {
	sed -n 24p $T/$1.txt | cut -c69-80 | sed 's/\(..\)/\1 /g; s/ $//'
}
# score NAME: the score and the lives on row 22
score() {
	sed -n 23p $T/$1.txt | awk '{ print $2, $4 }'
}
# NAME LEVEL SCRIPT FREEZE SECONDS GUARD RUNNER R SCORE MEN TILES WHAT:
# the first guard as guard prints it, the runner's X and Y, R, the score
# and the lives, then the frame with the tiles given (- none)
while read n l s f sec g1 g2 g3 g4 g5 g6 x y r sc men holes what; do
	[ $f = - ] && f=
	run $n "CRT $l $s $f\\r" $sec
	got="$(guard $n) $(row23 $n | awk '{ print $1, $3 }') $(dig23 $n | awk '{ print $6 }') $(score $n)"
	want="$g1 $g2 $g3 $g4 $g5 $g6 $x $y $r $sc $men"
	if [ "$got" != "$want" ]; then
		bad "$what: $got, not $want" $T/$n.txt
		continue
	fi
	[ "$holes" = - ] && holes=
	if frame $n $l play test men=$((10#$men)) score=$((10#$sc)) $(echo $holes | tr ';' ' '); then
		ok "$what: $got"
	else
		bad "$what, the frame" $T/chk.txt
	fi
done <<EOF
g1 10 23 100 12 0C FE 0D 00 81 00 04 0D 00 0000000 005 - the guard runs left at the runner, 8 tiles in 100 rounds
g2 10 23 - 25 14 00 0D 00 00 00 04 0D 01 0000000 004 - it touches the runner: a life gone, both back at their starts
g3 11 24 120 14 03 00 0E 00 84 01 00 0D 00 0000075 005 3,14=open into the hole the runner dug: held in it, 75 points
g4 11 24 200 14 03 00 0D 02 82 02 00 0D 00 0000075 005 3,14=open held 76 rounds, then climbing out
g5 12 25 380 26 03 00 0E FF 82 03 02 0D 00 0000075 005 - the hole closed on it in round 372: dead, not drawn
g6 12 25 420 26 00 00 02 FE 84 00 02 0D 00 0000150 005 - back 40 rounds later at row 1, column 0, falling, 75 more
g7 15 23 100 12 06 00 0D 00 00 00 12 0D 00 0000000 005 - on the runner's row a wall does not stop the chase: up to it, and it waits there
EOF

# A hole between a guard and the runner, a ladder behind the guard. The
# chase sees no hole: it walks on and falls in, it does not turn away to
# the ladder at column 1.
run g9 'CRT 18 30 100\r' 12
if [ "$(guard g9)" = "0B 00 0E FE 04 00" ]; then
	ok "a hole just dug: the guard runs at the runner and falls in, it does not run away"
else
	bad "the guard and the hole: $(guard g9)" $T/g9.txt
fi

# The first guard is the one behind: it follows the guard ahead up the
# near ladder, and does not take it for a wall.
run g8 'CRT 16 23 100\r' 12
if [ "$(guard g8)" = "05 00 0B 00 82 00" ]; then
	ok "behind another guard it follows it up the near ladder, it does not turn to the far one"
else
	bad "the guard behind: $(guard g8)" $T/g8.txt
fi

run gover 'CRT 14 26\r' 40
if sed -n 24p $T/gover.txt | grep -q "^ *GAME OVER" && [ "$(score gover)" = "0001250 000" ]; then
	ok "over gold into the guard 5 times, 1250 points: $(sed -n 24p $T/gover.txt | sed 's/^ *//')"
else
	bad "into the guard 5 times" $T/gover.txt
fi
# only GAME OVER may take the ENTER: the test build draws the play keys
# on row 23 for a moment at each start
# ENTER at once stays on GAME OVER, it may be a dig, and the
# letters give it time, GAME OVER ignoring them
$EMU -a $T/xc.imd -t 34 -e "$P|$OVER" -k 'CRT 14 26\r\r' > $T/gstay.txt
if grep -q 'GAME OVER' $T/gstay.txt; then
	ok "ENTER at once on GAME OVER does nothing"
else
	bad "ENTER at once left GAME OVER" $T/gstay.txt
fi
$EMU -a $T/xc.imd -t 45 -e "$P|$OVER" -k 'CRT 14 26\rqqqqqqqqqqqqqqqqqqqqqqqqqqqq\r' -p $T/gtitle.pgm > $T/gtitle.txt
if python3 tests/check_title.py $T/gtitle.pgm $T/gtitle.txt 1250 > $T/chk.txt; then
	ok "ENTER after GAME OVER: the title, HIGH SCORE 0001250: $(cat $T/chk.txt)"
else
	bad "ENTER after GAME OVER" $T/chk.txt
fi

# 6 figures: the runner and 5 guards closing in on it
run five 'CRT 13 23\r' 20
set -- $(sed -n 24p $T/five.txt | awk '{ print $16, $18, $24 }')
echo "     with 5 guards, left in the worst frame: $((0x$1 * 37)) T-states of the picture, $((0x$2 * 30)) of the blank"
if [ $((0x$1)) -gt 0 ] && [ $((0x$2)) -gt 1 ] && [ "$3" = 01 ]; then
	ok "every frame with 6 figures fits, and the guards catch the runner"
else
	bad "6 figures: I $1 V $2 R $3" $T/five.txt
fi

echo "=== gold and the end of a stage"
while read n f sec g1 g2 g3 g4 g5 g6 sc gold holes what; do
	run $n "CRT 14 24 $f\\r" $sec
	got="$(guard $n) $(score $n | awk '{ print $1 }') $(sed -n 23p $T/$n.txt | awk '{ print $8 }')"
	want="$g1 $g2 $g3 $g4 $g5 $g6 $sc $gold"
	if [ "$got" != "$want" ]; then
		bad "$what: $got, not $want" $T/$n.txt
	elif frame $n 14 play test score=$((10#$sc)) $(echo $holes | tr ';' ' '); then
		ok "$what: $got"
	else
		bad "$what, the frame" $T/chk.txt
	fi
done <<EOF
c1 100 14 04 FE 0D 00 81 00 0000000 001 4,13=open;3,14=open a guard over gold: carrying it, still counted
c2 140 14 03 00 0E 00 84 01 0000075 001 4,13=open;3,14=open;3,13=gold held in a hole: its gold dropped on the rim
EOF

run reveal 'CRT 19 27 40\r' 12
if [ "$(row23 reveal | awk '{ print $1, $3, $5 }') $(score reveal)" = "06 0C 02 0000250 005" ] &&
	frame reveal 19 play test revealed score=250 gold=0 4,13=open; then
	ok "the last gold taken, 250 points: the hidden ladders show, and the runner climbs one"
else
	bad "the last gold taken" $T/reveal.txt
	cat $T/chk.txt
fi
run stage 'CRT 19 27\r' 25
if [ "$(sed -n 23p $T/stage.txt | awk '{ print $2, $4, $6 }')" = "0001750 006 001" ]; then
	ok "up the ladder to row 0: 1500 points, a life more, and after the last test level, level 1 again"
else
	bad "the stage done" $T/stage.txt
fi

if [ ! -f $B/CLONERUN.COM ]; then
	echo "=== no $LEVELS: the viewer, play and ESC on Lode Runner's stages not checked"
	echo "$pass passed, $fail failed"
	[ $fail = 0 ]
	exit
fi

echo "=== the title"
run title 'CLONERUN\r' 10
if python3 tests/check_title.py $T/title.pgm $T/title.txt > $T/chk.txt; then
	ok "CLONERUN: $(cat $T/chk.txt)"
else
	bad "the title" $T/chk.txt
fi
run tidle 'CLONERUN\r' 40
if python3 tests/check_title.py $T/tidle.pgm $T/tidle.txt > $T/chk.txt; then
	ok "left alone 40 s on the title: still there"
else
	bad "the title left alone" $T/chk.txt
fi

echo "=== the viewer, on Lode Runner's stages"
NLEV=$(grep -c '^=== ' $LEVELS)
run l1 'CLONERUN\rs' 10
if frame l1 1; then ok "S on the title, stage 1: $(cat $T/chk.txt)"; else bad "stage 1" $T/chk.txt; fi

run last 'CLONERUN\rsp' 10
if frame last $NLEV; then
	ok "P from stage 1, stage $NLEV: $(cat $T/chk.txt)"
else
	bad "P from stage 1" $T/chk.txt
fi

for t in 'nnnp:003:N, N, N, P' '\R\R\L\R\R:004:RIGHT, RIGHT, LEFT, RIGHT, RIGHT' \
    '\U\U\D:011:UP, UP, DOWN' '\D:141:DOWN from 1'; do
	k=${t%%:*}
	rest=${t#*:}
	want=${rest%%:*}
	what=${rest#*:}
	run keys "CLONERUN\\rs$k" 10
	if [ "$(row22 keys)" = $want ]; then
		ok "$what: stage $want"
	else
		bad "$what: stage $(row22 keys), not $want" $T/keys.txt
	fi
done

# F1 in the game does not reach the prompt as Caps Lock: dir comes
# back in capitals, with -T's own text, as at boot. A second's pause
# first, as keys typed while the game ends are lost
if [ -f $B/CLONERUN.COM ]; then
	out=$($EMU -a $T/xc.imd -T -t 30 -e "$P|$HELP|$PHELP|$THELP|$OVER" -k 'CLONERUN\rs\1\e\e\Pdir\r' | grep -v '^ *$' | tail -3)
	case "$out" in
	*'A:\>DIR'*) ok "F1 in the game leaves Caps Lock as it was" ;;
	*) bad "Caps Lock after F1 in the game: $out" /dev/null ;;
	esac
fi

echo "=== play, on Lode Runner's stages"
run play 'CLONERUN\rsnn\r' 10
if frame play 3 play; then
	ok "ENTER on stage 3: played, the runner at its start: $(cat $T/chk.txt)"
else
	bad "ENTER on stage 3" $T/chk.txt
fi

# Left alone a while: no key comes from the tick stub, so nothing
# moves
run idle 'CLONERUN\rs' 40
if [ "$(row22 idle)" = 001 ] && [ "$(sed -n 24p $T/idle.txt)" = "$HELP" ]; then
	ok "left alone 40 s in the viewer: stage 001, still running"
else
	bad "left alone in the viewer: stage $(row22 idle)" $T/idle.txt
fi
run idleplay 'CLONERUN\r\r' 40
if frame idleplay 1 play; then
	ok "ENTER on the title, then left alone 40 s in play on stage 1: the runner at its start: $(cat $T/chk.txt)"
else
	bad "left alone in play" $T/chk.txt
fi

run back 'CLONERUN\rsnn\r\e' 10
if [ "$(sed -n 24p $T/back.txt)" = "$HELP" ] && [ "$(row22 back)" = 003 ]; then
	ok "ESC in play: the viewer again, on stage 003"
else
	bad "ESC in play" $T/back.txt
fi
run giveup 'CLONERUN\r\r\1' 12
if sed -n 23p $T/giveup.txt | grep -q "MEN 004"; then
	ok "F1 in play: a life given up, $(sed -n 23p $T/giveup.txt | sed 's/^ *//; s/  */ /g')"
else
	bad "F1 in play" $T/giveup.txt
fi
run pause 'CLONERUN\r\rP' 12
if [ "$(sed -n 24p $T/pause.txt)" = "$(msg m_paused)" ] && frame pause 1 play paused; then
	ok "P in play: $(sed -n 24p $T/pause.txt | sed 's/^ *//'), the runner at its start"
else
	bad "P in play" $T/pause.txt
fi

echo "=== ESC"
# Another key between the ESCs: the game waits for a key to be let go, and
# ESCs typed back to back can read as one held key
run esc 'CLONERUN\r\r\R\R\U\en\ex\e\rfontsum\r' 15
AFTER=$(grep '^VL ' $T/esc.txt)
if [ -n "$BEFORE" ] && [ "$AFTER" = "$BEFORE" ]; then
	ok "ESC from play, from the viewer and from the title: font RAM and VLATCH as before, $AFTER"
else
	bad "ESC: font RAM and VLATCH, before '$BEFORE', after '$AFTER'" $T/esc.txt
fi
# the lines with text: the command, its line and the prompt, nothing else
grep -v '^[[:space:]]*$' $T/esc.txt | sed 's/[[:space:]]*$//' > $T/lines.txt
printf '%sFONTSUM\n%s\n%s\n' "$P" "$AFTER" "$P" > $T/want.txt
if cmp -s $T/lines.txt $T/want.txt; then
	ok "ESC: the prompt on a clean screen"
else
	bad "ESC: the screen" $T/esc.txt
fi
ch=$(sed -n 2p $T/esc.pgm | cut -d' ' -f6)
if [ "$ch" = 9 ]; then ok "ESC: 9-line rows again"; else bad "ESC: $ch-line rows"; fi
echo "$pass passed, $fail failed"
[ $fail = 0 ]
