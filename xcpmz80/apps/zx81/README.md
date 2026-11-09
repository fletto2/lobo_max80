# ZX81.COM

Runs ZX81 machine code games on xcpmz80. `ZX81 NAME` runs `NAME.P`.
It takes the character shapes from `ZX81.ROM` on the same drive, which
you supply. The ROM is never run, and there's no BASIC, so only games
in machine code work. MIT license, as xcpmz80.

- `/D` shows light on dark, the default is a white background.
- `/F` runs at full speed, the default is ZX81 speed.
- `/Y` skips the warning for a `.P` not in the game table, which lists
  what its code seems to need and waits for a key.
- BREAK quits. The games keep their own keys.

| Game | Keys | License |
| --- | --- | --- |
| `TETRIS.P`, Russell Marks | S rotates, K and L move, D drops | Public domain, `games/tetris.txt` |
| `TETRIS1K.P`, Russell Marks | The same, any key at the `?` | Public domain, `games/tetris.txt` |
| `MINE81.P`, Russell Marks | H J K L or S X E D move, V or SPACE tread, 1 or M mark, 3 or U unmark | Public domain, `games/mine81.txt` |
| `PIPEPANI.P` (Pipepanic), Thunor | Q A O P move, K selects | GPL 3, `games/PIPEPANI.COPYING`, source `games/pipepanic.asm` |

## Building

`build.sh` makes `build/ZX81.COM` (needs sjasmplus). `test.sh` runs the
tests in the emulator, on test files made by `tools/zx81p.py`. The
tests of the games read the ROM from `$ZX81_FILES/sz81/data/zx81.rom`,
and are skipped without it.

ZX81.COM and the games are on the apps disks. `make apps` in `xcpmz80/`
puts the ROM on them as `ZX81.ROM` when the file `ZX81_ROM` names
(default `zx81.rom` in `xcpmz80/`) is there, and without it ZX81.COM
says `No ZX81.ROM`.

To play in the emulator, from the top of the repo, with your ROM:

    python3 xcpmz80/tools/mkdisk.py xcpmz80/build/xcpmz80.sys z.imd \
        xcpmz80/apps/zx81/build/ZX81.COM ZX81.ROM xcpmz80/apps/zx81/games/*.P
    emu/max80 -a z.imd

