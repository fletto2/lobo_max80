# Clone Runner

CLONERUN.COM, a dig-and-climb platform game for the MAX-80 under
xcpmz80 only. It's a port of Lode Runner, with its 150 stages and its
rules. The code, the glyphs and the name are new.

The stages are Broderbund's and don't come with the source. `build.sh`
reads them from the file `LODERUNNER_LEVELS` names, by default
`private/levels.txt`: the C64's stages decoded as text, each one a
`=== NNN ===` line and 16 rows of 28 characters. Without that file it
makes only the test builds.

## The game

- The title comes first: CLONE RUNNER in big letters of brick, a little
  scene of the tiles and figures, a line on the stages, the high score
  of this run and the keys. ENTER plays from stage 1, S shows the
  stages, ESC quits. The viewer's ESC and the end of a game come back
  to it.
- The viewer (S on the title) shows stage 1 in columns 12-67, rows 4-19, a tile 2 cells
  wide, with LEVEL nnn and GOLD nnn on row 22 and the keys on row 23.
  N or RIGHT shows the next stage, P or LEFT the one before, UP and
  DOWN go 10 on or back, round past either end. The hidden ladders,
  the false bricks (a brick with hollow faces) and the starts show, so a
  stage can be read whole.
- ENTER plays the stage shown, with 5 lives. The hidden ladders and
  starts are hidden, a false brick is drawn as a brick, and the runner
  and the guards stand at their starts. Nothing moves until a key moves
  the runner. Row 22 shows SCORE, MEN (the lives), LEVEL and GOLD. P
  pauses and goes on, F1 gives up a life. ESC goes back to the viewer,
  ESC there to the title, and ESC on the title quits, putting font RAM,
  the CRTC, VLATCH and the screen back.
- The runner moves by Lode Runner's rules, in rounds (below). The
  arrows run, climb ladders, hang and move along bars, and drop off a
  bar or a ladder. The first of UP, DOWN, LEFT and RIGHT held that it
  can go is taken, every round, not only on a whole tile. It is held up
  by brick, solid block, a ladder, or a guard below, and on a ladder, or
  on a bar at the bar's height. Gold, a false brick, a bar and a hidden
  ladder below hold nothing up. A fall of any height is safe, a bar
  catches it at its height and a ladder at once.
- Z digs left and X digs right, X first when both are held, and CLEAR
  is DOWN too. ENTER and SHIFT also dig left, and ~ and _/DEL dig right,
  the keys around the arrows. The machine has one matrix bit for
  both SHIFT keys, so the left one digs left as well. The ENTER that
  starts a stage counts only once it has come up. A tap between rounds
  still counts, and of two directions held the one pressed last goes
  first. A dig takes the brick
  one row down and one column across. The runner must be held up, not on
  the bottom row, with the tile beside it empty to the rules, no gold or
  guard there, and the target brick. It may dig from a ladder or a bar.
  It then stands in the middle of its tile in its digging figure while
  the brick crumbles open in 4 steps, and goes back to standing,
  climbing or hanging.
- A hole is open, then fills back in 4 steps, then is brick again. A
  runner on its tile then is caught. At most 30 holes, the C64's.
- Up to 5 guards chase the runner (`guards.asm`), a few moving each
  round by TotalRecall's table for the number of guards, so with 5 each
  moves 2 rounds in 5. A guard falls and is held up as the runner is,
  and other guards stop it. On the runner's row it walks straight at
  it when nothing between is a wall or a gap. Otherwise it rates each
  place it could fall or climb to from the columns it can reach: on the
  runner's row by the columns between, above it 100 and the rows, below
  it 200 and the rows, the least first. A guard whose middle reaches a
  hole is held in it 76 rounds, 3.0 s, scoring 75, then climbs out to
  the rim and steps off, towards the runner if it can. A hole closing
  on a guard kills it, and 40 rounds later it comes back on the first
  empty tile from row 1, from a column that steps on each time, scoring
  75. The runner stands on a guard as on brick.
- A guard less than 6 eighths from the runner both ways catches it.
  Caught, by a guard or a hole, the runner loses a life: two beeps, the
  field still a second, and the stage from its start. With no lives
  left GAME OVER shows on row 23 until ENTER or ESC, and the title,
  which keeps the score if it is the best of the run.

- The runner takes gold when its middle is within 3 eighths of the
  tile's, 250 points and a beep. A guard picks gold up the same way when
  it carries none and 24 moves have passed since it last dropped some,
  carries it 24 to 75 moves, then drops it where it stands on an empty
  tile held up from below. Held in a hole it drops it on the rim, or as
  it climbs out and steps off. A guard killed with gold loses it. GOLD
  counts the gold on the field and carried.
- With no gold left the hidden ladders show, at once on a stage with
  no gold at all. The runner standing on row
  0 then ends the stage: a life more (up to 255), 1500 points counted
  up in 100s with a beep each, and the next stage. After stage 150
  comes stage 1 at the next difficulty, up to 10: the guards move more
  often (TotalRecall's table for the number of guards plus the
  difficulty) and are held in holes 8 rounds longer a step.
- A tile changed in play (gold taken or dropped, a ladder shown) goes
  into a queue, and up to 8 of them are copied into video RAM a blank.

### Rounds and times

The game runs in rounds of 2.4 ticks of the system's 61.035 Hz tick,
39 ms, 25% faster than the C64's pace. In a
round a figure moves an eighth of a tile, 2 dots across or 1 line down,
half the C64's quarter tile, so it crosses a tile in 8 rounds, 0.31 s,
the C64's 0.40. Every time is in `tune.inc`, the C64's doubled:

| Constant | Value | Means |
|---|---|---|
| `ROUNDSTEP`, `ROUNDQ` | 5, 12 | 12/5 ticks a round, 2.4 |
| `DIGSTEP` | 3 | a crumbling step, the dig 12 rounds, 0.47 s, ours |
| `HOLEOPEN` | 320 | then open 12.6 s |
| `FILLSTEP` | 10 | then a filling step, 40 rounds, 1.6 s |
| `NHOLES` | 30 | holes at once |
| `TRAPHOLD` | 76 | rounds a guard is held in a hole, 3.0 s, 8 more each difficulty step |
| `BIRTHTIME` | 40 | rounds before a killed guard comes back, 1.6 s |
| `LIVES` | 5 | at the start of a game |
| `SC_TRAP`, `SC_REBIRTH` | 75 | points, a guard into a hole, a guard back |
| `CARRYMIN` | 24 | moves a guard carries gold, at least, up to 51 more |
| `GOLDCOOL` | 24 | moves after a drop before a guard takes gold again |
| `SC_GOLD` | 250 | points, gold taken |
| `SC_LEVEL` | 15 | hundreds of points at the end of a stage |
| `MAXDIFF` | 10 | the highest difficulty |

Open and filling, 360 rounds, the C64's 180.

A figure stands on a tile with an offset of -4 to 3 eighths across and
down. Past 3 it goes on to the next tile at -4. The game counts the
ticks with a 10-byte stub in front of xcpmz80's tick handler, at DE00h,
common memory below xcpmz80's code at DF00h, since the program with
the stages runs past 8000h. The stub saves AF: the handler saves the
flags as it finds them, so a flag the stub changed would reach the
game's code wherever the tick broke in.

### Figures

The runner and up to 5 guards are actors (`actors.asm`), each with 6
glyphs from 92h in font RAM 2. A guard's shapes are the runner's with a
hat. A figure is built again only when it moved or a tile under it
changed, at most 2 a frame (`FIGFRAME`), one fewer for each guard's
move made in the frame: the tiles under its 3 x 2
cells, from the font tables in the program, with its shape shifted by
its dot offset and laid over them through its mask. The build also
works out each of its cells' address in video RAM and in `scrbuf`. In
the next vertical blank, with interrupts off, its glyphs go into font
RAM, the cells it left get their tiles back, and its codes go into its
new cells. A figure's codes are written again only where cells under
it were written that blank, by another figure leaving or a hole
changing, in the order they move, so a cell two share shows the later
one.

The running step comes from where the figure is, every 4 dots, a hand
over hand every 8, a climbing step every 4 lines, so a frame check can
work it out from row 23.

### Speed

The guards' chase is the costly part of the game. A guard on a row
other than the runner's scans the columns it can reach and each place
it could fall or climb to from them, so on an open stage one chase
takes up to about 50,000 T-states, more than half the frame's 84,500.
Three things keep a frame inside the picture:

- `tiles` is the field with a border, rows of 64 bytes on a page
  boundary: a solid column, the 28 tiles, solid columns to 32, then the
  stand bytes. A tile's place comes from shifts, and the border is
  solid at the sides and below and empty above, so nothing checks the
  field's edges. `rulet` and `flagt`, a page each, give a tile's kind
  as the rules see it and as flags. During its scan a guard marks the
  other guards' tiles with bit 7, so the scan needs no list of guards,
  and reads tiles through IX. Each tile's stand byte says whether a body
  there is held up or on a bar, made again for a tile and the one above
  it when a tile changes, so a step off a ladder or a bar is two loads.
- A round's guard moves are made one a frame: the first in the round's
  frame, the rest in the frames after it, and a guard touching the
  runner and the stage done after the last. Between rounds only the
  guards move, so play is the same as with every move at once. A round
  that comes before the last one's moves are done makes them first.
- A frame builds one figure fewer for each guard's move in it.

The hidden ladders are listed when a stage starts, so showing them
visits only those. The tables and the border are made once, when the
program starts, and the hidden ladders and the stand bytes only for
play, so the viewer steps through the stages quickly.

Measured with the test builds, CRT.COM and CRT2.COM: a build of the
runner's glyphs takes about 8,000 T-states. The worst frame of the back
and forth script left about 17,700 T-states of the picture and 12,500
of the blank, with 11 holes dug 22,800 and 14,600, and with 5 guards
closing in on the runner 7,600 and 12,500. Measured on all 150 stages
with the guards chasing, the frame's work from the start of the blank
at most about 67,000 T-states of the 84,500 at difficulty 0. At
difficulty 10, past ten times round the stages, an open stage can
still run a frame over when a round has to finish the last one's moves:
the frame shows late, and the rounds, counted in ticks, keep the pace.

## Build and run

First run `make` in `emu/` and `xcpmz80/`, then:

    sh build.sh
    cd ../../xcpmz80
    python3 tools/mkdisk.py build/xcpmz80.sys /tmp/cr.imd ../software/clonerun/build/CLONERUN.COM
    ../emu/max80 -a /tmp/cr.imd

and `CLONERUN` at `A:\>`. `build.sh` needs sjasmplus and python3. It
runs `tools/glyphs.py` and `tools/levels.py`, which check their files
and write `build/glyphs.inc`, `build/testlevels.inc` and, from the
stages, `build/levels.inc`, then assembles `build/CLONERUN.COM`, the
test builds `build/CRT.COM` and `build/CRT2.COM`, and
`build/FONTSUM.COM`, the test helper. `build/levels.inc` and
`CLONERUN.COM` carry the stages, so neither leaves the machine.

`sh test.sh` runs the tests. It needs `make` run in `emu/` and
`xcpmz80/` first.

## Files

- `clonerun.asm`: The program, the viewer, the play loop and the
  rounds. Includes `screen.asm`, `keys.asm`, `hw.inc`, `actors.asm`, `figures.asm`, `holes.asm`, `guards.asm`,
  `gold.asm` and `tune.inc`.
- `actors.asm`: The tiles as the rules see them, the moves every
  figure shares, the runner and its dig.
- `figures.asm`: Each actor's glyphs built, the copy in the blank, and
  the tick stub.
- `holes.asm`: The hole table, each hole's phases a round at a time, a
  runner caught, and the changed cells copied in the blank.
- `guards.asm`: The guards: their turns, the chase, held in a hole,
  climbing out, killed and back, and a guard catching the runner.
- `gold.asm`: Gold taken, carried and dropped, the tile queue, the
  hidden ladders shown, and the end of a stage.
- `tune.inc`: Every speed and time.
- `test.asm`: The test build's command line, key scripts and row 23.
- `glyphs.txt`: The glyphs and the figures as dot pictures. Its header
  gives the format.
- `tools/glyphs.py`, `tools/levels.py`: Check and pack them.
- `tests/check_frame.py`: Checks a frame saved by `max80 -p` against
  the levels and `glyphs.txt`, dot for dot, with the figures in play.
- `tests/levels_test.txt`: Nineteen small levels of our own for the key
  scripts, in the stages' form.
- `tests/check_title.py`: Checks a frame of the title dot for dot, from
  the tables in `clonerun.asm`.
- `tests/fontsum.asm`: FONTSUM.COM, prints VLATCH and a sum of each 1K
  of font RAM.
- `tests/bad_*.txt`: Broken levels `levels.py` must turn down.
- `private/levels.txt`: Lode Runner's stages, which you supply, never in
  git. `build.sh` makes `build/CLONERUN.COM` from them.
- `model/`: The JavaScript model of Lode Runner the Z80 code follows,
  rule for rule (`engine.js`, the rules with no screen, `main.js`, a
  page to play it in a browser), with `PHYSICS.md`, the rules read from
  the C64 disassembly, and `SOURCES.md`, where the stages and the rules
  came from. `node model/test_engine.js` checks the engine on the
  stages. `python3 model/build.py` writes `model/build/loderunner.html`,
  which carries the stages, so it never leaves the machine.

## The glyphs

74 drawn shapes and 6 built for each figure:

| Use | Codes | Glyphs |
|---|---|---|
| Text: space, 0-9, A-Z, `:`, `-`, `/` | their ASCII codes, font RAM 1 | 40 |
| A hole crumbling, 4 steps, and filling, 4 steps | 60h-6Fh, font RAM 1 | 16 |
| Tiles: brick, solid block, ladder, bar, gold, hidden ladder, false brick | 80h-8Dh, font RAM 2 | 14 |
| Starts: runner, guard | 8Eh-91h, font RAM 2 | 4 |
| The actors, built as they move, 6 each | 92h-B5h, font RAM 2 | 36 |

A letter is 5 x 7 dots in an 8 x 8 cell. A tile is 16 x 8 dots, its
left half at an even code and its right half at the next. The empty
tile is two spaces, and so is an open hole. Font RAM 1 is written from
20h to 6Fh, the codes between the letters and the holes blank.

The runner has 16 figures of 16 x 8 dots, 512 bytes with their masks:
standing, running 4 each way, climbing 2, hanging 2, falling and
digging each way. `glyphs.py` makes the left running frames, the
second climbing frame and the left digging frame as mirrors, each mask
by widening the figure a dot on each side, so the figure has a dark
edge over the tiles, and a guard's shape for each, its top row widened
2 dots each side into a hat.

## The level file

Lode Runner's form, read by `levels.py`: lines starting with `#`, then
for each level `=== NNN ===` and 16 rows of 28 characters, a short row
filled out with empty tiles.

| Char | Tile |
|---|---|
| space or `.` | empty |
| `#` | brick, can be dug |
| `@` | solid block |
| `H` | ladder |
| `-` | bar, hand over hand |
| `X` | false brick: drawn as brick, empty to the rules |
| `S` | hidden ladder, shown when the gold is all taken |
| `$` | gold |
| `0` | a guard's start, on an empty tile |
| `&` | the runner's start, on an empty tile |

`levels.py` turns down a level unless it has 16 rows of at most 28
tiles and one runner start. As the C64 does at load it keeps at most 5
guards and 45 hidden ladders, scanning bottom-up and right to left, and
blanks the rest: 3 guards on the disk (stages 8, 80 and 113) and 3
hidden ladders (stage 89) never show.

A level packs into 4 bytes (the gold, the runner's column and row, the
number of guards), a column and row for each guard, and the 448 tiles
at 3 bits each, 8 tiles in 3 bytes, the first tile in the top bits: 168
bytes. The 150 stages take about 26K.

## The test build

CRT.COM is the game built with `-DTEST`. `CRT L S F` plays level L of
`tests/levels_test.txt` with key script S of `test.asm`, a list of
rounds and the keys held from each. A script can freeze the game at a
round, and F, if given, is a round to freeze at in its place. Row 23
shows from column 0, in hex, `X` and `Y`, the runner's tile, `U` and
`W`, its offset across and down in eighths, `M`, what it does (0
standing, 1 running, 2 climbing, 3 hanging, 4 falling, 5 digging), `D`,
the way it faces, `T`, the rounds, the fewest passes left in the
picture, `I`, 37 T-states each, and in the blank after the copies,
`V`, 30 each, then `H`, the holes in the table, `F`, the first entry's
phase (0-3 crumbling, 4 open, 5-8 filling, FF free), and `R`, the times
the level started again. From column 66, when the level has a guard,
`G` and the first guard's column, offset across, row, offset down, what
it does (80h on when it faces left) and its state (0 free, 1 held in a
hole, 2 climbing out, 3 dead), packed with no spaces. CRT2.COM, built also with `-DTWICE`, builds
and copies the runner twice a frame, and the difference gives the times
above.

## Tests

`test.sh`, under xcpmz80 in the emulator, 104 checks with the stages and
86 without them (the viewer, play on the stages and ESC from them are
left out):

- `levels.py` turns down a level with two runner starts and one with a
  row 29 tiles wide, and takes the test levels.
- Twelve key scripts on the test levels: running 13 eighths, stopped
  mid-tile, running into brick and into a solid block, up a ladder and
  not past its top, down it again, off a ledge onto a bar and along it,
  DOWN off the bar to the floor, off a ledge to the floor, frozen in a
  fall, through gold in a ledge, taking it, and through a false brick,
  and a hidden ladder that is not there to climb. Three of their frames
  dot for dot, the first with the gold it took gone.
- The times: every frame leaves time in the picture and the blank,
  even with the runner built and copied twice. In the test build a
  frame's work starts with the picture, so a frame whose work runs into
  the next blank counts as none left, and the frame that writes row 23,
  the test's own work, is not counted.
- Digging, 17 runs with row 23 checked and 12 of their frames dot for
  dot: X and Z mid-crumble and open, a hole filling and brick again,
  the runner in a hole and not climbing out with UP, caught as it fills
  and back at the start, not moved by LEFT held in the round it fills, out of one hole sideways into the next,
  through a hole in a ledge to the floor, no dig in the air, digs from
  a ladder and from a bar, and digs refused with brick beside the
  runner, solid to dig, a ladder to dig and a ladder beside.
- The hole's times: its phase frozen at each side of each change, the
  dig 12 rounds, open 320, filling 40.
- The times with a row of holes: every frame fits, even with the
  runner built and copied twice.
- The guards, 6 runs with the first guard, the runner, the score and
  the lives checked and each frame dot for dot: a guard running at the
  runner, catching it and both back at their starts with a life gone,
  held in a hole for 75 points, climbing out, killed as the hole closes
  and not drawn, and back at row 1 for 75 more. Into a guard 5 times:
  GAME OVER, with 1250 points from the gold, and ENTER then shows the
  title with HIGH SCORE 0001250, dot for dot. With 5 guards every frame
  fits.
- Gold: a guard carrying gold it walked over, still counted, and
  dropping it on the rim of the hole it is held in, both frames dot for
  dot. The last gold taken for 250 points, the hidden ladders shown,
  dot for dot, and up one to row 0: 1500 points, a life more, and the next
  level. A level with no gold, its hidden ladders there from the start:
  up one to row 0, and level 1 again after the last test level.
- The viewer on a build with 3 test levels (`CR3.COM`): UP and DOWN by
  10 come round past either end as often as it takes, P the last,
  RIGHT past the last to 1, LEFT past 1 to the last.
- On Lode Runner's stages, when the file is there: the title dot for
  dot and left alone 40 s, S to the viewer, stage 1 and stage 150 dot
  for dot, N, P, the arrows and UP and DOWN by 10, ENTER on
  stage 3 dot for dot, the viewer and play left alone 40 s with nothing
  moved, ESC back to the viewer, F1 giving up a life, and P pausing.
- After ESC from play, the viewer and the title, FONTSUM prints the same
  line as before the game, the screen holds only the prompt, the
  command and its line, and the rows are 9 lines again.

## Status

The game is done in the emulator. It has not run on a real MAX-80. The
beeper gives one fixed tone, so there is no sound beyond the beeps.
