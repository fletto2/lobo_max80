# Where Lode Runner's stages and rules came from

Clone Runner uses Lode
Runner's original stages and rules. The stages are the 150-stage
Classic set, in `../private/levels.txt`, Broderbund's data, gitignored
and never committed. `PHYSICS.md` is the rules. This file says where
both came from and what agrees with what. They came with the
JavaScript model.

## Sources

The sources read, at these commits.

| Repo | Commit | Date | License | Used for |
| --- | --- | --- | --- | --- |
| piddewitt/loderunner | 964ad0e | 2024-04-14 | none in repo | The C64 original: disk image and commented disassembly. The source of truth for `levels.txt` and most of `PHYSICS.md` |
| SimonHung/LodeRunner_TotalRecall | cceca5d | 2025-04-13 | none in repo (README names no license) | The Apple II 1983 disk extraction of the classic set, AI versions, a JS re-implementation |
| vchimishuk/loderunner-ng | cac5614 | 2026-09-19 | GPLv3+ (`COPYING`) | An independent C re-implementation, 150 text levels, cross-check |
| lvcabral/Lode-Runner-Roku | e614902 | 2019-11-16 | none in repo. The author asks to approve any reuse and forbids commercial use (Roku developer forum post, 2019) | An independent `classic.json` of all 150 levels in 28 x 16, cross-check |
| yauhahu/LodeRunner | c647c24 | 2020-04-09 | none in repo | A TotalRecall fork with its own level edits, cross-check |
| jbordalo/LodeRunner | a2be004 | 2020-05-23 | none in repo | A small browser clone, 16 levels, C64-style tile legend, cross-check |
| hishamhm/xlode | 2dba0b5 | 2013-10-08 | GPL2 (`LICENSE`) | An X11 clone with its own levels and format (40-column maps), not a source of the original data |

The C64 disk image used is `Lode Runner.d64` (174848 bytes, no error
bytes) from piddewitt's repo, beside the untouched originals
`Lode Runner (USA, Europe).g64/.nib` in its `original/` directory.
The disassembly claims a byte-for-byte rebuild of the game and
documents the disk layout, the level packing and every timing constant
cited in `PHYSICS.md`.

A later source, not copied here, its
license unclear: `XekriRedmane/lode_runner_reveng` on GitHub, a
literate disassembly of the Apple II game. Its Guard AI chapter
(`main.nw`) agrees with the C64 code on the chase.

## Method

`levels.txt` was made by decoding the C64 disk directly. Level N
(0-based) is at track `N/16 + 3`, sector `N and 15`. Byte 0 of the
block is a header (all 00h in the classic set), bytes 1-224 hold 448
tiles, two a byte, low nibble first. Tile codes 00h-09h map to the
legend at the top of `levels.txt`. Every decode was checked against the
game's own expansion code (`it.asm`, `GameLevelDataExpand`) and
against four independent extractions:

- TotalRecall `lodeRunner.v.classic.js` (Apple II 1983 disk, 150
  levels, stored as 28 x 15). It drops the bottom row, which is why 16
  of its levels lost their runner start. loderunner-ng and Roku carry
  the full 28 x 16.
- loderunner-ng `share/loderunner-ng/levels/001..150` (28 x 16 text).
- Roku `assets/maps/classic.json` (28 x 16).
- yauhahu `lodeRunner.baseLevel.js` (28 x 15, TotalRecall's with
  edits).

What the cross-check found, with the C64 disk as the reference:

- loderunner-ng: 4 rows differ out of 2400, in levels 1, 6 and 25 (the
  Apple II tile values, below) and level 113 (it blanks the sixth
  guard).
- Roku: 2 levels differ, 6 and 25 (Apple II values). Level 1 and the
  guards of 113 match the C64.
- TotalRecall: 23 cells differ, all in levels 1, 6 and 25, and the
  bottom row is missing everywhere.
- yauhahu: levels 11, 13, 14, 16, 19, 24, 31 and 34 are edited
  against both the C64 and the Apple II (guards removed, tiles
  changed, level 24 rearranged). The rest is TotalRecall's data.
- jbordalo (16 levels only): 10 of its 16 match the C64 disk exactly,
  the brick and solid alternation of level 1 included, an independent
  confirmation of the C64 decode.

## Tiles that differ between the C64 and Apple II originals

The 150 designs are the same on both. Only these cells differ (C64
first, Apple II second). TotalRecall, yauhahu and ng carry the Apple
II value, Roku the first two:

- Level 1, row 2: seven cells at the left that the C64 disk has as
  brick and solid block in turn, the Apple II all brick.
- Level 6, row 0: the cells at columns 0-15 and 22-24, solid block on
  the C64 disk, brick on the Apple II.
- Level 25, row 2: one cell at column 5, brick on the C64 disk, a false
  brick on the Apple II.

And level 113, row 3, col 4: the C64 disk and TotalRecall put a guard
there (6 in all). loderunner-ng ships the level without it, as an
engine that keeps 5 guards would play it.

Both sets are retail original data. `levels.txt` has the C64 disk's
values, decoded here from the disk itself by the game's own code. The
Apple II reading of those three spots is the list above.

## The classic set in numbers (C64 decode)

- 150 levels, 28 x 16.
- Gold: 2671 pieces, 4 (level 9) to 52 (level 87).
- Guard starts: 518 in all, 2 to 6 a level. Levels 8, 80 and 113 have
  6, one more than the C64 engine keeps.
- Hidden ladders: at most 48 in one level (89). The C64 engine's load
  scan keeps at most 45, so 3 of them never appear.
- False bricks are in 85 levels.
- Every level has exactly one runner start.

## In Clone Runner

The stages sit on the original's 28 x 16 field, columns 12-67 and rows
4-19 of the screen, and `../tools/levels.py` keeps at most 5 guards and
45 hidden ladders as the C64 does at load.
