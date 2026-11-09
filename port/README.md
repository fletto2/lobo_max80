# Tetris for the MAX-80

TETRIS.COM, the Game Boy Tetris 1P A-type game for the Lobo MAX-80,
under Lobo's CP/M 2.2 or xcpmz80. The Z80 code is our own. The game's
numbers, its speeds, pieces, scores and the timing of the sideways
repeat, are not in this source: `tools/build.py` lifts them from your
own copy of the cartridge, so the program is built only by someone who
has one, and no byte of Nintendo's is in its source.

## Build

You need the Game Boy cartridge `Tetris (World) (Rev A)`, DMG-TRA-1,
dumped to a file, SHA1 `74591CC9501AF93873F9A5D3EB12DA12C0723BBC`.
`build.py` refuses any other file. Then, from the top of the repo, with
sjasmplus and Python 3 installed:

    make -C emu
    python3 port/tools/build.py path/to/Tetris.gb
    cd emu && ./max80 -a ../port/build/tetris.imd

and `TETRIS` at the prompt. `build.py` writes `src/tables.asm` from the
ROM (git ignores it; don't share it), assembles `build/TETRIS.COM`, and
puts it on xcpmz80 boot disks: `build/tetris.imd` for an 8-inch drive,
`build/tetris_525.imd` and `build/tetris_180.imd` for a 5.25-inch drive,
360K and 180K, booted with the emulator's `-D 1`.

## Play

The title, ENTER to go on, DOWN held for hard mode. The level select:
the arrows and ENTER, Z back. In the game the arrows move and drop, Z
and UP turn, ENTER pauses, SPACE shows or hides NEXT. A, S and D also
work as LEFT, DOWN and RIGHT, Q as Z and E as UP. After GAME OVER,
ENTER goes back to the level select. ESC quits.

The screen is 40 double width columns of 8-line cells, two pages of
video RAM swapped each frame, with the glyphs in font RAM.

## Files

- `src/tetris.asm`: the program, the title, the level select and the
  frame loop. Includes the others.
- `src/game.asm`: the engine, gravity, lock, line clears, the piece
  picker, scoring and levels, as the Game Boy game behaves.
- `src/video.asm`: the screen, the glyphs, the two pages and the lists
  of changed cells.
- `src/keys.asm`: the keys, read from the matrix once a frame.
- `src/hw.inc`: the MAX-80's I/O addresses.
- `tools/build.py`: checks the ROM, lifts the tables, builds the disks.

The emulator tests of the game run on Lobo's CP/M 2.2 boot disk and
read its font, which is not in this release, so they are not here
either.

## License

MIT, in `LICENSE`, for the code in this folder. Tetris and its numbers
are Nintendo's and are not covered by it.
