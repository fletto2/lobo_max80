# xcpmz80

A CP/M compatible OS for the Lobo MAX-80 that keeps its files on FAT12
and FAT16 disks, so a PC can read and write them. It's written in Z80
assembly for this machine only. None of it is copied from Lobo's or
Digital Research's code.

How to use it, every command and every program on its disks, is in
[XCPM_MANUAL.md](XCPM_MANUAL.md).

## What runs

Most CP/M 2.2 and CP/M 3 programs. These have been run on it:

- Lobo's CP/M 2.2 tools: STAT, PIP, ASM, LOAD, DUMP, ED, SUBMIT and
  XSUB, and Lobo's XTIME, XCOPY and CP/M 3 COPIER.
- Digital Research's CP/M 3 tools: DIR, SHOW, DATE, PIP, RENAME, ERASE,
  TYPE, SET, SETDEF, HELP, SID, ED, MAC, RMAC, LINK, HEXCOM, XREF,
  DEVICE, SUBMIT, GET and PUT. RSXs load as on CP/M 3.
- dBASE II, MBASIC, WordStar and Multiplan as installed for the MAX-80.
- SWEEP, CRCK and D.
- HI-TECH C 3.09, which compiles and runs C programs under xcpmz80.

The console takes the same codes as Lobo's BIOS, those of a Soroc
IQ-120, so programs installed for the MAX-80 draw their screens right.

It boots from 8-inch floppies, 5.25-inch 360K floppies, 3.5-inch 720K
and 1.44M floppies, and a SASI hard disk of up to 32 MB.

## Building

You need sjasmplus and Python 3. The C programs on the apps disk need
SDCC 4.6.0. `make test` also needs the emulator built in `../emu`, and
mtools.

    make
    make test
    ../emu/max80 -K -a build/xcpmz80.imd

| Target | Makes |
| --- | --- |
| `make` | `build/xcpmz80.imd`, the 8-inch boot disk |
| `make 525` | `build/xcpmz80_525.imd` (360K) and `build/xcpmz80_180.imd` (180K), booted with `-D 1` |
| `make apps` | `build/apps.imd`, `build/apps_525.imd` and `build/apps_720.imd`: the boot disk with the C library and every program |
| `make test` | runs the tests in the emulator |

The boot disk is one FAT12 volume. Tracks 0 to 3 hold the boot sector
and the system. `make` also writes the raw image `build/xcpmz80.img`,
which mtools reads:

    mdir -i build/xcpmz80.img ::

A floppy written by FORMAT reads the same way after
`../tools/imd2raw.py`.

## Files

- `src/xcpmz80.asm`: the top file, which puts the parts together.
- `src/hw.inc`: hardware addresses, banks and the memory map.
- `src/boot.asm`: the boot sector and the FAT boot parameter block.
- `src/kernel.asm`: the part in bank A2: start-up, warm boot and the
  program loader. It includes the files below.
- `src/ccp.asm`: the shell, its built-in commands, and SUBMIT.
- `src/bdos.asm`: the BDOS functions, the line editor, disk errors.
- `src/file.asm`: CP/M files on FAT: open, make, close, read and write
  records, delete, rename, attributes.
- `src/dir.asm`: folders: the current folder of each drive, paths, CD,
  MD and RD, and BDOS 118, 119, 124 and 125.
- `src/fat.asm`: mounting a FAT12 or FAT16 volume, and the FAT itself.
- `src/disk.asm`: the drive table, the FDC and SASI drivers and the
  sector cache.
- `src/format.asm`: FORMAT and SYS.
- `src/bpb.inc`: the floppy's BPB, the one definition of its format.
- `src/clock.asm`: the MSM5832 clock, and FAT and CP/M 3 dates.
- `src/util.asm`: console output, numbers, file names, wildcards.
- `src/vars.inc`: the kernel's variables.
- `src/common.asm`: the part in common memory, A1 from DF00h: the BDOS
  entry, which writes the characters of functions 2 and 6 without the
  kernel, the BIOS jump table, start-up, the RAM test, the screen, the
  keyboard and the tick interrupt. ESC E and ESC R move the CRTC's
  start address a row when the rows above the cursor are fewer, so
  the 2K of video RAM is a ring, and copy the others by LDIR.
- `src/font.bin`: the console font, made by `tools/mkfont.py` from
  unscii-8, with a thin second style after ESC ). 7Fh is the cursor.
  `src/font_inverse.bin` has an inverse second style instead:
  `make FONT=src/font_inverse.bin`.
- `apps/ldfont.asm`, `apps/glyphs.asm`, `apps/clock.asm`,
  `apps/more.asm`: LDFONT, GLYPHS, CLOCK and MORE.
- `apps/zx81/`: ZX81.COM, which runs ZX81 machine code games.
- `c/`: the C programs (EMACS, VI, ADVENT, ZORK, BASE64), their C
  library and `CLIB.SYS`, which keeps the library in the upper 64K.
  Its own `README.md` lists them.
- `tools/mkdisk.py`: makes a boot disk, as IMD for the emulator and as
  a raw image for mtools, with files copied onto it. `--pc KB` (360,
  720 or 1440) makes a floppy in a PC's layout, sectors from 1, `--525
  KB` (180, 360 or 720) one in Lobo's layout, sectors from 0, which
  boots, `--ds` a double sided 8-inch one, `--hd
  MB` a hard disk image for the emulator's `-h`.
- `tools/mkfont.py`: makes the fonts from `tools/unscii-8.hex`.
- `tools/swapfont.py`: makes `BOLD.FNT`, `src/font.bin` with its two
  styles swapped, for the apps disks.
- `tools/fatcheck.py`: checks a FAT volume as fsck does, folders
  included, for the tests.
- `tools/session.py`: types keys into the emulator through its key
  socket (`-g`, Linux only), for programs that show no prompt between
  keys. Its waits are the machine's time, and `@?TEXT` waits for a
  prompt, `@/TEXT` for text anywhere on the screen, so a test costs
  the host little.
- `test.sh`: the tests, in parts cut at its `#PART` lines.
- `tools/testparts.py`: runs the parts at once, each with a test folder
  of its own, and prints their output in order, for `make test`.

## License

MIT, in `LICENSE`. The console font is public domain
(`tools/unscii-8-LICENSE.txt`). The programs in `c/` and
`apps/zx81/games/` keep their own licenses, listed in their READMEs.
