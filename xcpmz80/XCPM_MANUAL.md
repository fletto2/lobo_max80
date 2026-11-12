# xcpmz80 user's manual

xcpmz80 is a CP/M compatible operating system for the Lobo MAX-80. It
keeps its files on FAT12 and FAT16 disks, the format a PC uses, so you
can move files between the MAX-80 and a PC on a floppy. Most CP/M 2.2
and CP/M 3 programs run on it.

## Starting up

Put the boot disk in drive A and turn the machine on, or in the
emulator:

    emu/max80 -K -a xcpmz80.imd

`-D 1` boots a 5.25-inch or 720K disk instead. The screen shows

    XCP/M-Z80 v0.2 for the Lobo MAX-80, 128K, 55K TPA

    A:\>

`A:\>` is the prompt. The letter is the current drive, and after the
backslash comes the current folder: `A:\GAMES>`.

The keyboard starts with Caps Lock on, as Lobo's CP/M does. F1 turns
it off and on. The arrows send ^\ ^] ^^ and ^_ (1Ch to 1Fh), CLEAR
sends ^H and BREAK sends ^C.

## Typing a command

Type the command and press ENTER. The cursor blinks while the system
waits for a key. While typing:

| Key | Does |
| --- | --- |
| ^H, DEL, CLEAR or the back arrow | rub out the last character, and only it: the rest of the line stays as it is |
| ^X or ^U | rub out the line |
| UP, at the `A:\>` prompt | bring back the last command, to run again or change |
| ^R | type the line again |
| ^E | go on to the next screen line |
| ^P | echo everything to the printer, until the next ^P |
| ^C at the start of a line | restart the system |

A word that is not a built-in command runs the program of that name:
`ZORK` runs `ZORK.COM`, from the current folder of the current drive or
of A:, and if it is in neither, from the top folder of those drives. If
there is no `.COM` but there is a `.SUB`, it runs that as a batch file.

`B:` on its own makes B: the current drive.

## Drives and disks

There are three drives. Booted from a floppy, A: and B: are the two
floppy drives and C: is the SASI hard disk, if there is one. Booted
from the hard disk, A: is the hard disk and B: and C: are the floppy
drives.

- An 8-inch disk holds 17 sectors of 512 bytes a track, on one side
  or both.
- A 5.25-inch disk holds 360K (two sides) or 180K (one side).
- A 3.5-inch disk holds 720K on the 5-inch connector, or 1.44M on the
  8-inch connector.

The system finds out what kind of disk is in a drive the first time
you use it. 8-inch, 360K, 180K, 720K and 1.44M disks boot.

A disk written by a PC in its own layout (sectors numbered from 1)
can be read and written, but does not boot.

## Folders

A disk can hold folders, as on a PC, and folders in folders. Each
drive has a current folder, shown in the prompt, and a file name on its
own means a file in it. `B:NAME` means a file in B:'s current folder.

A path names a file or folder in another folder. Parts are split by `\`
or `/`. A path that starts with `\` starts at the top folder, `..` is
the folder above, and a drive letter can come first:

    GAMES\ZORK.COM        ZORK.COM in the folder GAMES, here
    \CLOCK.COM            CLOCK.COM in the top folder
    ..\NOTES.TXT          NOTES.TXT in the folder above
    B:\GAMES\INFOCOM      the folder INFOCOM in GAMES on B:

| Command | Does |
| --- | --- |
| `CD path`, `CHDIR` | make it the current folder of its drive. `CD \` goes to the top, `CD ..` up one |
| `CD`, `PWD` | show the current folder |
| `MD path`, `MKDIR` | make a folder |
| `RD path`, `RMDIR` | remove a folder, which must be empty and not the current one |

DIR, LS, TYPE, ERA, SAVE, FREE and COPY take paths:

    COPY \CLOCK.COM GAMES\
    COPY GAMES\*.COM B:\
    TYPE ..\README.TXT
    ERA OLD\*.*

COPY or MV to a folder's name, `COPY CLOCK.COM GAMES`, puts the file
in that folder, as `GAMES\` does. MV moves a file to another folder on
the same drive without copying its data. REN renames within one
folder. DIR shows a folder as `NAME\`, LS as `NAME\` with `<DIR>`. A
folder's path is at most 46 characters, so folders go 3 or 4 deep.

The current folder stays when a program ends. If the disk in the drive
is changed, the drive goes back to the top folder. Programs see the
files of the current folder, so a CP/M program run in a folder reads
and writes there.

Programs can use the folders through the BDOS, with
DE the address of a path ended by a 0 byte. Each returns A = 0, or FFh
on an error.

| Function | Does |
| --- | --- |
| 118 | make the folder DE names |
| 119 | remove the empty folder DE names |
| 124 | change the current folder to DE's |
| 125 | write the current drive's folder to DE, as `\GAMES`, 0 ended, up to 48 bytes |

## Built-in commands

| Command | Does |
| --- | --- |
| `DIR [d:][name]`, `LS` | list files. `*` and `?` work as in CP/M: `DIR *.COM` |
| `TYPE name`, `CAT` | show a text file |
| `ERA name`, `RM`, `DEL` | delete files. With `*.*` it asks `ALL (Y/N)?` first. Folders are left alone |
| `REN new=old` | rename a file in its folder |
| `MV old new` | rename a file, or move it: `MV GAME.COM GAMES` into a folder, `MV GAMES\GAME.COM \` out of one, `MV *.TXT DOCS` several, `MV GAME.COM B:` to another drive, which copies it and then erases it |
| `COPY from to`, `CP` | copy a file, byte for byte. `COPY A:GAME.COM B:` keeps the name |
| `SAVE n name` | save n pages (256 bytes each) of memory from 0100h as a file |
| `USER n` | set the user number. FAT has no user areas, so every file shows in every one |
| `FREE [d:]` | show the free space on a disk |
| `CLS` or `CLEAR` | clear the screen |
| `VER` | show the version |
| `FORMAT d: [size] [PC]` | format a floppy and make it a boot disk. See below |
| `FORMAT d: MB` | make an empty FAT volume of MB megabytes on the hard disk |
| `SYS d:` | put the system on a disk that is already formatted |
| `SUBMIT name [args]` | run `NAME.SUB` as a batch file |
| `CD`, `MD`, `RD`, `PWD` | folders, above |
| `HELP [topic]` | list the built-in commands. With a topic, run CP/M 3's `HELP.COM` |

A built-in command followed by `[options]`, such as `DIR [FULL]`, runs
the `.COM` of that name instead, so CP/M 3's own DIR, ERASE and so on
still work if they are on the disk. A drive before the name, as `A:RD`,
runs the program too, never the built-in.

COPY reads as much as fits in memory before it writes, so copying
from one floppy to another moves the heads as little as it can.

### FORMAT

    FORMAT B:            8-inch, one side
    FORMAT B: DS         8-inch, both sides
    FORMAT B: 360        5.25-inch, two sides
    FORMAT B: 180        5.25-inch, one side
    FORMAT B: 720        3.5-inch on the 5-inch connector
    FORMAT B: 1440       3.5-inch on the 8-inch connector
    FORMAT B: 360 PC     a PC's layout, which a PC reads but which does not boot

Without a size, a drive on the 5-inch connector gets 360K. FORMAT
writes every track, then an empty FAT volume with the system on it.
You can format A:, the drive you booted from: the system is read into
memory first.

### Batch files

A `.SUB` file holds one command per line. `$1` to `$9` are replaced
by the words after the name:

    A:\>SUBMIT BUILD HELLO

runs `BUILD.SUB` with `$1` as `HELLO`. Typing `BUILD HELLO` does the
same. CP/M's own SUBMIT.COM and XSUB also work.

## Programs on the boot disk

### LDFONT

    LDFONT name

loads a font into font RAM. The file is `name.FNT`, or `name` with
the type you give. A font file is 1K (characters 00h to 7Fh) or 2K
(00h to BFh). The boot disk has three:

- `XCPM.FNT`: the system's own font. `LDFONT XCPM` puts it back.
- `THIN.FNT`: the same, with a thin second style.
- `INVERSE.FNT`: the same, with an inverse second style.

The font stays until you restart.

### GLYPHS

    GLYPHS

shows every character the font holds, 00h to BFh, in a table.

### CLOCK

    CLOCK

prints the date and time from the clock chip, such as
`10/30/26 21:44:50`. The clock is set with the TIME SET button on the
back of the machine held down.

### MORE

    MORE name

shows a text file a screen at a time. At `--More--`, SPACE shows the
next screen, ENTER the next line, and Q or ^C stops.

## Programs on the apps disk

The apps disk is the boot disk with these programs added. The C
programs need `CLIB.SYS`, the C library, which the system loads from
the boot disk at start-up. Without it they say so and stop.

### EMACS

    EMACS name

MicroEMACS 3.6, a small Emacs. ESC is the Meta key: ESC V means ESC,
then V. The arrows move the cursor.

| Keys | Does |
| --- | --- |
| ^F ^B ^N ^P, or the arrows | right, left, down, up |
| ^A, ^E | start, end of the line |
| ^V, ESC V | next, previous screen |
| ESC <, ESC > | start, end of the file |
| ESC G | go to a line |
| ^D | delete the character under the cursor |
| DEL, ^H or CLEAR | delete the character before it |
| ^K | delete to the end of the line |
| ESC . | set the mark |
| ^W, ESC W, ^Y | cut, copy, paste the text from the mark |
| ^S, ^R | search forward, back. End the text with ESC |
| ESC R | replace all |
| ESC ^R | replace, asking each time |
| ^X ^S | save |
| ^X ^W | save as |
| ^X ^F | open another file |
| ^X ^C | quit. It asks if there are unsaved changes |
| ^G | cancel a command |

A file bigger than memory is edited through a window that moves as you
move, so files of any size can be edited.

### VI

    VI name
    VI +10 name      start at line 10
    VI + name        start at the last line

STEVIE, a vi clone. The keys are vi's: `i` and `a` insert, ESC goes
back to command mode, `x` deletes a character, `dd` a line, `u` undoes,
`/text` searches, `:w` saves, `:q` quits, `:wq` or `ZZ` saves and
quits, `:q!` quits without saving. In command mode the arrows move the
cursor. The back arrow rubs out in insert mode and on the `:` line.

A file bigger than memory is edited through a window, as in EMACS.
`:set bk` keeps the old file as `.BAK` when you save.

Not there: `:sh`, `:!`, tags, several files at once and `:g`.

### ADVENT

    ADVENT
    ADVENT -r        go on with a saved game

Colossal Cave Adventure. Type commands of one or two words: `GO
NORTH`, `TAKE LAMP`. `SUSPEND` saves the game to a file you name, as
`NAME.ADV`. The four `ADVENTn.TXT` files must be on the same drive.

### ZORK

    ZORK story.dat

plays an Infocom version 3 story, such as Zork I to III, Planetfall or
The Hitchhiker's Guide to the Galaxy. The stories are Infocom's and do
not come with it. `SAVE` and `RESTORE` ask for a file name, and add
`.SAV` if it has no type. There is no status line.

### BASE64

Moves files between the MAX-80 and a PC as text, through the serial
port or a terminal's copy and paste.

    BASE64 FILE              write FILE to the screen as text
    BASE64 -D FILE           read the text typed or pasted, up to a
                             line holding only `.`, into FILE
    BASE64 -D FILE TEXT      read the text from the file TEXT

On the PC, `base64_host FILE` makes the text and
`base64_host -d FILE` reads it back. `base64_host` is built in
`xcpmz80/c` with `make`. The text is compressed, so it is shorter than
plain base64.

### ZX81

    ZX81 GAME

runs the ZX81 machine code game `GAME.P`. It needs the ZX81's ROM as
`ZX81.ROM` on the same drive, for the character shapes. BREAK quits.

| Option | Does |
| --- | --- |
| `/D` | light on dark. The default is a white background |
| `/F` | full speed. The default is the ZX81's speed |
| `/Y` | run a `.P` it does not know without asking first |

| Game | Keys |
| --- | --- |
| `TETRIS`, `TETRIS1K` | S rotates, K and L move, D drops |
| `MINE81` | H J K L or S X E D move, V or SPACE tread, 1 or M mark, 3 or U unmark |
| `PIPEPANI` | Q A O P move, K selects |


## How it differs from CP/M

- Disks are FAT volumes. A program that reads disk sectors through the
  BIOS, such as a disk editor, finds no drive. Programs that use files
  are fine.
- A disk can hold folders, as on a PC. A program sees only the files
  of the current folder.
- There are no user areas. `USER` keeps the number for programs that
  ask, but every file is in every one.
- File names are kept in upper case. A file's R/O attribute is FAT's
  read-only flag, SYS is FAT's system flag.
- A file holds up to 8 MB.
- A program can end with RET, as on CP/M 2.2.
