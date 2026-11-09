# Lode Runner physics and rules, read from the clones

Goes with the stages file, `../private/levels.txt`
(gitignored, Broderbund's), and `SOURCES.md` (sources, licenses,
method). This file states how the
original game actually behaves, read out of the code, with the sources
named. Facts marked C64 are from the commented C64 disassembly
(`piddewitt/loderunner`, `Lode Runner/asm/it.asm` and
`inc/LR_Var.asm`, cited as `it.asm:<line>`). TotalRecall is
`SimonHung/LodeRunner_TotalRecall` (JS), ng is `vchimishuk/loderunner-ng`
(C, SDL). Where the clones disagree, all three readings are given.

## Field and tiles

- The field is 28 tiles wide and 16 rows tall, row 0 at the top
  (C64 `LRZ_ScreenCol_Max` = $1b, `LRZ_ScreenRow_Max` = $0f, `LR_Var.asm:365`
  area, ng `level.h:23-24`, TotalRecall `lodeRunner.def.js`
  `NO_OF_TILES_X/Y`). Every clone agrees.
- Nine tile types, stored as codes $00-$09 (`LR_Var.asm:154-163`):
  empty, brick, solid block, ladder, bar (rope), false brick
  (trap), hidden ladder, gold, guard, runner. The tile numbering is
  the same in TotalRecall (`def.js:120-129`), which is where the
  `levels.txt` legend comes from.
- A false brick is drawn like a brick but behaves empty. On the C64
  the display substitutes a brick image for the trap tile when the
  picture is built (`it.asm:4752-4755`, `ChkTrapDoorDisplay`). Whoever
  stands on it falls through.
- Hidden ladders behave empty until the level's gold is gone, then
  they appear and are ordinary ladders.

## Disk format of a level (how `levels.txt` was decoded)

One 256-byte disk block per level: level N (0-based) lives at track
`N/16 + 3`, sector `N and 15` (`it.asm:4240-4276`), 16 blocks per
track from track 3. Byte 0 of the block is a header (all $00 in the
classic set), bytes 1-224 hold 448 tiles packed two to a byte, low
nibble first (`it.asm:3915-3941`): the game takes `byte and $0F` then
`byte >> 4`. Nibble values above 9 decode as empty
(`it.asm:3949-3952`).

The C64 game's own expansion is the source of truth used for
`levels.txt`. The Apple II-derived sets (TotalRecall, yauhahu, ng,
Roku) agree with it cell for cell except the four spots listed in
`SOURCES.md`.

## What the load step changes

The level data on disk is a template. The engine edits it at load:

- Guards: at most 5 are kept (`LR_EnemyCount_Max` = $05,
  `LR_Var.asm:365`). The load scan runs bottom-up, right to left
  (`it.asm:4606-4627`), so if a level has more, the upper/left extra
  guards are blanked to empty. The disk data has 6 guards in levels
  8, 80 and 113.
- Hidden ladders: the load scan keeps at most 45
  (`it.asm:4641-4643`, the count must stay below
  `LR_ExitLadderCount_Max - $03` = $2d). Level 89 has 48 on disk, so
  3 of them never appear.
- Gold and the runner are all kept. Every level has exactly one
  runner tile on the C64 disk.
- If a level has no runner tile at all, the game treats the disk as
  wrong and restarts at level 1, raising the difficulty counter on
  the way (`it.asm:3976-3997`). `levels.txt` level 136 only got its
  runner back because the correct decode includes row 15. Earlier
  extractions that dropped the bottom row (TotalRecall, yauhahu)
  lose the runner start in 16 levels.

## Timing

- The C64 IRQ (50 Hz PAL, 60 Hz NTSC) increments a counter. The main
  loop waits until the counter reaches `LR_GameSpeed`, then resets it
  (`it.asm:325-330`). One logic round is therefore
  `LR_GameSpeed` IRQs: 5 at normal speed (`LR_GameSpeed_Normal` = $05,
  `LR_Var.asm:360`) = 0.10 s PAL. In-game keys can set it between $03
  and $08 (`LR_Var.asm:359-361`, `it.asm:6422-6450`), 0.06-0.16 s.
- The runner advances one image step per logic round. A tile is 4
  image steps (position 0-4, `LR_PosOnImage_Max` = $04), so one tile
  takes 4 rounds: 0.4 s horizontally or vertically at normal speed.
- Guards advance on a mask pattern (`it.asm:6956-7047`): the block is
  picked by `GameSpeedCtrl + guard count`, and its three byte masks
  (values $00, $01, $03, $07, $0F, $1F, $3F, $7F) let a guard move
  0-7 rounds out of every 8. At normal speed with 5 guards the masks
  give 3 or 4 rounds in 8, so guards are always visibly slower than
  the runner and never match his speed. TotalRecall plays the same
  game from a ticker of 14-35 FPS (`main.js:42`). ng fixes the frame
  rate at 23 FPS and moves the runner 8 px of a 40 px tile per frame
  (`main.c:39`, `game.h:30`), about twice the C64's tile speed.
- A guard trapped in a hole waits `TabEnemyInHoleTime[GameSpeedCtrl]`
  rounds: $26 (38) at difficulty 0 up to $4e (78) at difficulty 10
  (`it.asm:610-631`), roughly 4-8 wall-clock seconds.

## The runner

- Movement: left/right along a floor, up/down on ladders, left/right
  hanging on a bar, fall when unsupported. A bar catches a fall at
  tile top, and a ladder top catches too. Standing is supported by brick,
  solid block, ladder, bar, or a guard below. Gold does not support:
  a body falls through a gold tile. TotalRecall
  (`lodeRunner.runner.js`, the `STATE_FALLING` check) and the C64
  (`it.asm:7199-7246`) agree tile for tile.
- No fall damage anywhere: falls of any height are safe. Falling into
  an open hole captures whoever falls in.
- The runner cannot climb the walls of a hole, and he is too low to
  reach the floor beside it: a hole dug into a continuous floor traps
  him until it closes, and a closing hole kills whoever is inside
  (`it.asm:10258-10261`). He can only walk out sideways where the
  tile beside the hole, at the hole's own row, is open ground.
- Gold is picked up by standing over it (score 250,
  `LR_Score_Gold` = $0250 BCD, `LR_Var.asm:197`).
- Touching a guard kills the runner. The C64 detects it as hardware
  sprite collision (`LRZ_LodeRuEnemyCollision`, `it.asm:6782-6788`),
  suppressed during the gold-pickup moment. A guard stuck in a hole
  can be run across, because he is below the runner's sprite.
- Death: one life lost (`LR_NumLivesInit` = $05,
  `LR_Var.asm:328`), the level restarts. At 0 lives the game ends.

## Digging and holes

- The dig (the C64 port draws it as a spark "shoot" beam) opens a
  hole in the brick at foot level, one tile left or right of the
  runner (`it.asm:5710-5796`). Conditions: the target tile is soft
  brick (never solid block, ladder, bar or false brick), the tile
  beside the runner on his own row is empty, and he is not on the
  bottom row. The Apple II has no test of where he is in his tile, it
  nudges him to the exact row and column as he digs (`main.nw`,
  TRY_DIGGING_LEFT), and the model does the same.
- At most 30 open holes at once (`LR_WA_HoleMax` = $1e,
  `LR_Var.asm:269`). A dig with no free slot fails.
- A hole stays open 180 rounds (`LR_WA_HoleOpenTime_Ini` = $b4,
  `LR_Var.asm:273`), about 18 s at normal speed. When 20 rounds are
  left the tile shows the first crumble-back step, at 10 the second
  (`LR_WA_HoleOpenTimeStep_01/02` = $14/$0a, `LR_Var.asm:274-275`),
  then it refills with brick.
- On closing: a runner inside dies, inside meaning its tile is the
  hole, so one only partly in it lives. A guard inside is killed: the
  tile becomes brick and the guard is scheduled to reappear. Gold
  inside is destroyed and the level's needed-gold count is
  decremented, so a level whose last gold is buried can still be
  completed (the completion check accepts the counter at $ff,
  `it.asm:301-303`).

## The guards

- At most 5 exist. They fall like the runner, climb ladders, hang on
  bars, and cannot walk into each other (a guard tile blocks another
  guard's path, `it.asm:7215-7216`, 7681-7682).
- Chase AI (`EnemyMoveGetDirProposal`, `it.asm:8291-8599`), the
  classic three-step heuristic, no randomness in it:
  1. A guard whose trapped time has run out proposes "up" to climb
     out of the hole.
  2. On the runner's row: walk straight toward him, but refuse to
     step over a gap (a tile whose below is empty or a false brick)
     unless the tile itself is a ladder or bar (`it.asm:8394-8469`).
     The check runs from the next column to the runner's, his own
     included. Only a gap ends it: not a wall, not a falling runner, not
     another guard, and gold under a tile is not a gap (and the
     Apple II's `DETERMINE_GUARD_MOVE`). Nor is a hole. Digging clears
     the active tile only, the background stays brick, and the chase
     reads the background below a tile. So a guard does not see a hole
     under its path, walks at the runner and falls in.
  3. On other rows: find the left and right "wings" the guard could
     reach along his row (stopped by bricks and solid blocks, never
     by other guards,
     `EnemyMoveGetMaxColLeRi`), scan each wing for a fall path onto
     the runner's row, and take the direction with the shortest free
     path (`EnemyMoveScanGoal/WingLeft/WingRight`,
     `EnemyMoveGetDistance`, `EnemyMoveGetMaxRowBot`). Each wing is
     scanned from its far end in, which settles ties.
  TotalRecall's `lodeRunner.guard.js` is a structured re-implementation
  of the same rules with named AI versions, and ng's `ai.c` follows the
  same shape.
- Guards pick up gold on a random timer, raster-seed random on the
  C64 (`it.asm:9926` area), 11-36 s in ng (`ai.c:99-101`). A guard
  carrying gold shows it. The runner cannot collect that piece until
  it is dropped. A trapped guard drops his gold at the hole rim when
  he climbs out (`it.asm:7712`, `EnemyMoveDropGold`).
- A guard killed by a closing hole reappears after about 20 rounds
  (`LR_WA_EnemyBirthStep_Ini` = $14, marks at $13 and $0a): the scan
  for a free spot starts at row 1 (never row 0) at a column that
  cycles 0-27 across rebirths (`LR_EnemyBirthCol_Min/Max` = $00/$1c,
  `it.asm:10323-10362`), stepping right and down until an empty tile
  is found. Rebirth scores 75 (`LR_Score_EnemyRebirth`).

## Level end, score, progression

- Collecting every needed gold reveals the hidden ladders. The level
  ends when the runner stands on row 0, image position centered
  (`it.asm:289-303`).
- Completion scores 1500, counted up in 100-point steps with a rising
  tone (`LR_Score_FinishLevel` = 1500, `LR_Var.asm:198`,
  `it.asm:360-394`), and adds one life, capped at 255
  (`it.asm:353-358`).
- Score values (BCD): gold 250, guard trapped in a dug hole 75
  (`LR_Score_EnemyDigIn`), guard reborn 75, level complete 1500. ng
  uses the same four values (`level.h:26-29`).
- After level 150 the game wraps to level 1 and the difficulty
  counter `LR_GameSpeedCtrl` rises by one, up to 10
  (`LR_GameSpeedCtrl_Max`, `LR_Var.asm:326`), which speeds the guard
  masks and lengthens hole-trap times. TotalRecall's Championship
  set and ng's loop do the same by hand.
- The classic set has between 4 (level 9) and 52 (level 87) pieces of
  gold, 2-6 guard spawns, and 85 of the 150 levels use false bricks.

## C64 port extras, not in the Apple II original

- A built-in attract demo: three recorded games with their move data
  in memory (`it.asm:4120-4156`), replayed from level data at
  $b500-$b7ff.
- A ten-entry leaderboard stored on the game disk itself (level
  number 151 at track 12, sector 7), entries of 3-character ID, level
  and BCD score, a name as the disk ID (`LR_Var.asm:104`).
- An in-game level editor mode and user level disks, gated by a
  checksum (seed $DB, result $C8, `LR_Var.asm:203-206`), the copy
  protection the disassembly documents.
- Cheat keys (extra lives, speed, jump-to-level) that set a "cheated"
  flag (`it.asm:6326-6352`).
