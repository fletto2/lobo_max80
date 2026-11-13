# C programs for xcpmz80

C programs for the MAX-80, built with SDCC 4.6.0 for the Z80. Their C
library stays in bank B2 as `CLIB.SYS`, so they run under xcpmz80 only,
with `CLIB.SYS` on the boot disk. Without it a program says so and
ends. How to use them is in `../XCPM_MANUAL.md`.

`make` builds them into `build/`. It needs SDCC, by default from
`/opt/cross/sdcc-4.6.0/bin` (`make SDCC_BIN=...` for another place), and
objcopy. The tests are in `../test.sh`.

The programs pass arguments in registers, SDCC 4's `--sdcccall 1`. The
library's functions, which the resident library is entered with on the
program's stack, and the assembly ones keep the stack convention:
their prototypes carry `__LIB`, `__sdcccall(0)`, from
`include/_cconv.h`. So do `page.h`'s. `lib/smemcpy.s` is `___memcpy`, which
SDCC calls for a struct copy, so that z80.lib's own `memcpy.rel`,
whose `_memcpy` takes registers, stays out of the link.

## The resident library

- `clib/`: what makes `build/CLIB.SYS`. `hdr.s` is its header at 0000h
  and the dispatcher, `marshal.c` copies the arguments under 8000h in
  and out by each function's signature, `malloc.c` is malloc on the
  program's heap, `wrap.c` the functions a signature cannot describe.
  `clib.lst` lists the functions, their numbers and signatures. The
  numbers never change, and a new function goes at the end.
- `tools/clibgen.py` makes from `clib.lst` the library's table and a
  thunk for each function, for `build/clibr.lib`.
- `clibr/`: what a program links besides the thunks. `crt0r.s` checks
  for the library and starts it, `side.c` holds errno, the buffers the
  library copies strings and a struct tm to, and stdin, stdout, stderr.
- Programs link `crt0r` and `clibr.lib`. `cpm.lib` is built too, as
  `CLIB.SYS` is made from it.
- The library runs with interrupts off, and they are as they were
  after each call.

## The library

SDCC has no CP/M library, so `lib/` is one, with its headers in
`include/`. It is built as `build/cpm.lib`, one object a function or a
few, so a program links only what it calls. It has its own versions of
what SDCC's `z80.lib` gives, so that it can be resident in bank B2.
From `z80.lib` come only the compiler's
helpers, multiply, divide and the long and float arithmetic, and
`atof`.

| Header | What |
| --- | --- |
| `stdio.h` | fopen, freopen, fdopen, fclose, fflush, fgetc, fputc, ungetc, fgets, gets, fputs, puts, fread, fwrite, feof, ferror, clearerr, fileno, fseek, ftell, rewind, fgetpos, fsetpos, setbuf, setvbuf, getline, getdelim, the printf and scanf families, perror, remove, rename, tmpnam, tmpfile |
| `string.h`, `strings.h` | the C functions, and strdup, strndup, strnlen, stpcpy, stpncpy, strlcpy, strlcat, strsep, strtok_r, strchrnul, strcasestr, strupr, strlwr, strrev, memccpy, memrchr, mempcpy, strcasecmp, strncasecmp, strerror, bzero, bcopy, bcmp, index, rindex, ffs |
| `stdlib.h` | malloc, calloc, realloc, free, exit, _exit, abort, atexit, getenv, system, abs, labs, atoi, atol, strtol, strtoul, itoa, utoa, ltoa, ultoa, qsort, bsearch, rand, srand, random, srandom |
| `ctype.h` | the C functions, ASCII, and isascii, toascii |
| `time.h` | time, clock, difftime, mktime, gmtime, localtime and their `_r` forms, asctime, ctime, strftime |
| `setjmp.h`, `assert.h`, `errno.h`, `err.h` | setjmp and longjmp, assert, errno, err, errx, warn, warnx |
| `unistd.h`, `fcntl.h` | open, creat, read, write, close, lseek, unlink, access, isatty, sleep, usleep, chdir and getcwd for the drive, getopt |
| `conio.h` | kbhit, getch, getche, putch, cputs, cprintf, cgets: the console one key at a time with no echo, by function 6 (FEh and FFh by function 2); cgets reads at most buf[0] - 1 characters, so the buffer is buf[0] + 2 bytes |
| `cpm.h` | bdos, bios (by function 50 under CP/M 3), the version, drive and user, cpm_findfirst and cpm_findnext for the directory, cpm_filesize |

A file opened with "a" or "a+" starts at its end, a text file at its
^Z, but a write after an fseek goes where the fseek put it, not to the
end as C has it.

- `lib/crt0.s`: the start-up of a program linked with `cpm.lib`. Puts the stack under the BDOS, zeroes the
  uninitialized data, which C needs and CP/M does not give, and calls
  `main(argc, argv)`. argv comes from the command tail, in upper case,
  "quoted words" as one, and `argv[0]` is "". The Makefile links each
  program twice, the second time with the initialized variables where
  their initial values load, so they take no memory twice.
- `lib/bdos.s`: `bdos(fn, de)`, which calls the BDOS and gives back HL.
- `lib/*.s`: memcpy, memmove, memset, strlen, strcpy, strcmp, strchr,
  setjmp and longjmp in assembly.
- `lib/ctype.c`, `lib/string.c`, `lib/stdlib.c`: built once for each
  function, which `L_name` picks.
- printf has flags, widths, precision, `*`, `l`, `h`, and d i u o x X c
  s p n. scanf has widths, `*`, `l`, `hh`, `h`, and d i u o x c s `[`
  n. Neither has floating point.
- malloc is first fit, from the end of the program to 1K under the
  stack. free merges free blocks, and gives the top one back.
- time comes from function 105 under CP/M 3 and xcpmz80, seconds from
  1970. Under CP/M 2.2 it is 0.
- exit runs the atexit functions, closes the files, and gives CP/M 3
  its return code (function 108).
- There are no div and ldiv.

Files are read and written a 128-byte record at a time with the random
record calls, so fseek goes anywhere at once. A file opened without "b"
is text: CR is dropped and ^Z ends it on reading, and '\n' is written as
CR LF. CP/M keeps no byte count, so a binary file ends at the end of
its last record, and reading past the bytes written gives that
record's padding. Up to 6 files are open at once. SDCC does not
take old-style K&R function definitions.

Everything here, the library, CLIB.SYS and the programs, is built with
`--nolospre`. lospre has miscompiled a function of MicroEMACS, and
every file is smaller without it anyway.

## The programs

| Program | Source | What |
| --- | --- | --- |
| `test/ctest.c` | ours | CTEST.COM, checks the library, resident |
| `advent/` | troglobit's Colossal Cave Adventure, github.com/troglobit/adventure at 7b61687, public domain (`advent/LICENSE`) | ADVENT.COM and ADVENT1.TXT to ADVENT4.TXT |
| `base64/` | ours, MIT, from agfa9000's BASE64 v2.0, rewritten for the Z80, and its host side `host.c` | BASE64.COM, and `build/base64_host` for Linux |
| `zork/` | MojoZork by Ryan C. Gordon, zlib license (`zork/LICENSE.txt`), the copy in agfa9000's CP/M-68K port, altered | ZORK.COM, which plays Infocom's version 3 stories |
| `emacs/` | MicroEMACS 3.6 by Dave G. Conroy and Daniel Lawrence, public domain, from agfa9000's CP/M-68K port | EMACS.COM |
| `vi/` | STEVIE 3.7A, the vi clone by Tim Thompson, Tony Andrews and G. R. Walter, public domain, G. R. Walter's line as GNO keeps it (git.applefritter.com/Apple-2gs-SW/gno, `bin/vi`), altered. Henry Spencer's regexp, altered (University of Toronto notice in `regexp.c`) | VI.COM |

ADVENT reads its text from the four `.TXT` files on the current drive,
by the offsets in `advtext.h`, instead of holding it in memory as the
original's BUILTIN build does. `advent/config.h` takes the place of
autoconf's. Two changes to the source, under `CPM`: the text files'
names, and the save file, which `SUSPEND` asks for by name and writes
as `NAME.ADV`. The save file is opened in binary mode ("wb", "rb"),
which the original left out and Unix does not need. `advent -r`
restores a saved game.

BASE64 moves files to and from a host as text: LZSS in agfa9000's
format, then base64, 76 columns. `BASE64 FILE` writes FILE to the
screen, ended by a `.` line, `BASE64 -D FILE` takes the text typed or
pasted until a `.` alone on a line, `BASE64 -D FILE TEXT` reads it
from the file TEXT. On the host, `base64_host FILE` and
`base64_host -d FILE`, which reads only lines of base64 letters, so a
capture of the serial line may keep the command and the prompt, and
writes nothing if the text is cut short. agfa9000's
version holds the whole file in memory and tries every place in the 4K
window for each byte. This one streams both ways and follows hash
chains, 24 places a byte, so it takes a file of any size and
compresses a little less than the host does (5307 bytes for the
host's 5296 in the test). CP/M files are whole 128-byte records, so a
file comes back to the host padded with ^Z to the record's end.

ZORK is a Z-machine for version 3 stories, such as Zork I to III,
Planetfall and The Hitchhiker's Guide to the Galaxy: `ZORK STORY.DAT`.
The story files are Infocom's and are not in this repo. A story can be
up to 128K, and Zork I is 84K, so it does not fit the TPA. ZORK keeps
the story's dynamic memory resident, the bytes up to the header's
static memory base (12K for Zork I), and reads the rest from the story
file through a cache of 512-byte pages. The cache takes the memory that
is left less 2K: 45 pages for Zork I, 52 for mini-zork. A page is read
with BDOS function 33 straight into its buffer, as the library's
fread goes a byte at a time and is several times slower. The cache
evicts by the clock rule, and the pages of the program counter and of
the strings being decoded are pinned. The program is 15K of code and
3K of data, the Z-machine's 1024-word stack among it. On Zork I a
command takes about a second of emulated time, the start 5 s with the
boot.

`SAVE` and `RESTORE` ask for a file name and add `.SAV` when it has no
type. The save holds the release, serial and checksum of the story, and
a save of another story is refused. Text is wrapped at word ends to 79
columns. There is no status line, and `split_window`, `set_window`,
`input_stream` and `sound_effect` do nothing. `zork/mojozork.c` lists
the other changes from MojoZork at its top.

EMACS is MicroEMACS 3.6, written by Dave G. Conroy and greatly
modified by Daniel Lawrence, and in the public domain, as its sources
say. It comes from agfa9000's CP/M-68K port, without that port's own C
library. `EMACS FILE` edits FILE. The keys are MicroEMACS 3.6's, with
ESC as the META prefix. A search or replace string ends with ESC, not
Enter. The arrows, 1Ch to 1Fh, are ^P ^N ^B ^F. The changes:

- The sources are ANSI C, as SDCC does not take K&R definitions.
  The prototypes are in `eproto.h`, included at the end of `estruct.h`.
  The commands that ended without a return value return one, and
  calls with the wrong number of arguments are fixed. The library's
  `itoa` took the name, so MicroEMACS's is `eitoa`. `mlwrite` uses
  `stdarg.h`.
- `max80.c` drives the screen, made from the VT52 driver: ESC = row
  col moves the cursor, ESC T and ESC Y erase, ESC ) and ESC ( set the
  mode line's style. `termio.c` reads and writes the console with
  function 6.
- `estruct.h` sets CPM and MAX80. `NAMES 0` leaves out the named
  commands (M-X), key binding, help, and command files with the
  startup file. `EXTRAS 0` leaves out the case of words and regions,
  fill and kill paragraph, the paragraph moves, C mode, and the
  commands that move, size and scroll other windows. `spawn.c` says
  "[Not available under CP/M]" for ^X ! and ^X C.
- Lines grow in 8-byte steps and the kill buffer in 256-byte steps, to
  leave more memory for the text.
- A file bigger than the memory is edited through a window, by the
  page module (below), glued in by `epage.c`. Moves, page moves,
  searches and the query replace slide the window at its edges. M-<,
  M-> and M-G (goto-line, with ^U N) load the window at the line. A
  search slides the window as it reaches the edge, and when it fails goes
  back to where it started. ^X ^S writes the whole file. The mark is
  dropped when the window slides past it, with "[Mark dropped, the
  window moved]", so a region is always in the window. Only one
  buffer at a time is paged. A second big file, or one opened with too
  little memory for a window, is read as far as it fits and put in
  View mode, so that ^X ^S cannot write the part over the whole file.

EMACS.COM is about 40K. A file that fits in the window, about 4K of
text, is an ordinary buffer. A bigger one is paged with a window of
about 60 lines of 55 characters.

VI is STEVIE 3.7A, the public domain vi clone begun by Tim Thompson,
in G. R. Walter's line from Tony Andrews' code. It comes from the
copy GNO keeps for the Apple IIgs, with `gsos.c` replaced by
`max80.c`. Henry Spencer's regexp is in `regexp.c` and `regsub.c`,
altered and marked so. `vi/README` and `vi/stevie.doc` are STEVIE's.
`VI FILE` edits FILE, and `VI +N FILE` starts at line N, `VI + FILE`
at the last. The keys are vi's. The arrows, 1Ch to 1Fh, are k j h l in
command mode and beep in insert mode. The changes:

- `env.h` sets MAX80 in place of GSOS, and leaves HELP out. `term.h`
  has a MAX80 section: 1Ah clears, ESC T and ESC Y erase, ESC E and
  ESC R insert and delete a line, ESC 0 and ESC 1 hide and show the
  cursor, and ESC ) and ESC ( turn the second style of the font on and
  off, for the error messages. `max80.c` and `max80.h` take the place of `gsos.c` and
  `gsos.h`: ESC = row col moves the cursor, and the console is read
  and written with BDOS function 6.
- The sources build with SDCC: the regexp in ANSI C, prototypes
  in `regexp.h`, `smsg` with `stdarg.h`, the table in `charset.c` in
  braces, and no declarations of functions inside functions, which
  SDCC took for variables. `format.l.c` and `s.io.c` are
  `format_l.c` and `s_io.c`. The ORCA/C `segment` lines are under
  `__ORCAC__`.
- To fit, `stevie.h` and the rest under MAX80: `bool_t` is a char,
  the line numbers 16 bits with LINEINC 16, the position pointers point
  at static structs, MAX_COLUMNS is an int of 81, `charset.c` works out
  what its 1.8K table held, the internal codes UNDO_SHIFTJ and
  ENABLE_REDRAWING are 88h and 89h so that `normal()` switches by a
  jump table, and the redo and undo buffers share one function.
- Memory: a line's struct and its text are one block (`newline`,
  `freetext` in `alloc.c`). IObuff is 257 bytes, so a line can be 256
  characters. The insert, read, redo, undo and yank buffers start at
  64 bytes and grow up to the original sizes, 5200 to 5500 bytes, while
  there is memory (`growbuf`), and shrink back when emptied.
- `fileio.c`: `readfile` reads 128 bytes at a time with `fread` in text
  mode, and `writeit` writes with `fputs`, CR LF ending each line. A
  file with a line too long is read as far as it goes, 1K is kept free
  for the editing, and `:w`, `:wq`, `:x` and `ZZ` refuse to write over
  it. `:q!` leaves. The old .BAK is removed before the file is renamed
  to it.
- A file bigger than the memory is edited through a window, by the
  page module (below), glued in by `vpage.s`, in Z80 code. Line
  and page moves, scrolling and searches slide the window at its
  edges. `G`, `:N`, `$` in an address and a search that wraps load the
  window at the line, and line numbers count the lines above the
  window. A search that fails goes back to where it started. Undo
  still works after the window moved, since it goes by line numbers.
  The lines of an operator's motion or of an ex range are held in the
  window while the command runs, and a range bigger than the window
  says "Range bigger than the window" and does nothing. `:w` writes
  the whole file, and with `:set bk` keeps the old one as .BAK, as
  STEVIE always did. `:e` goes from a paged file to any other. `:r`
  puts in a file that fits in memory, about 2K beside a paged file, and
  one that does not fit is not read at all and leaves the text as it
  was.
- Left out to fit: help, tags (`:ta`, ^], `-t`), several files on the
  command line (`:n`, `:p`, `:rew`), the alternate file (`:e #`, ^^),
  `:g`, `[[` and `]]`, number mode (`:set nu`), `+/pat` on the command
  line, EXINIT, and the counts of nulls and non-ASCII bytes on reading.
  `:sh` and `:!` say "Not available under CP/M". CP/M gives the command
  tail in upper case, so `+/pat` could not work.

VI.COM is about 46K. A file that fits in its memory is read whole. A
bigger one is paged with a window of about 6K, 85 lines of 55
characters. Each line costs 13 bytes of header
besides its text. `vpage.s` calls VI's functions and `page.s` with
their arguments on the stack, so those functions are marked `VI_ASM`
in `stevie.h`, `__sdcccall(0)` under SDCC 4.

## The page module

`page/` keeps a window over a file bigger than memory, for the
editors. The editor keeps a
window of whole lines in its own list. The rest of the file is pieces,
runs of whole lines in the file or in the work file `NAME.$$W`, in a
list above the window and a list below it. The window is loaded in
parts of about 512 bytes of the file, and each line carries the tag of
its part. A part with a change is written to the end of the work file
when it leaves the window. A part without one goes back as the piece
it came from, so reading through a file writes nothing. The file and
the work file are read and written a record at a time with BDOS
functions 33 and 34. A save writes the pieces, the window's parts and
the pieces below to `NAME.$$S`, renames it, and the pieces then point
into the new file. Unchanged parts are copied byte for byte, so their
lines keep LF or CR LF as they were. Changed lines are written with
CR LF. When the 48 pieces run out, the side with more of them is
copied to the work file as one piece.

- `page.h`: the interface, the tables, and the `ed_` functions each
  editor gives.
- `page.s`: the module in Z80 code, the one the editors link. 3.7K of
  code and 1.4K of data.
- `page.c`: the same module in C, line for line, the model for the
  host test. Compiled, it's 5.8K of code, too much for the editors.
- `host.c`: the host test, with a BDOS on the host's files and a small
  editor. Down and up a file with no work file made, 20 jumps, 3000
  random edits, moves, jumps and saves, each step checked against a
  model of the file, and a file of LF lines with a 700-character line
  and no last LF saved as it was. `build/page_host DIR [LINES [SEED
  [MEMORY]]]` runs it on `page.c`. With `PGTRACE` set it prints the
  tables after each step.
- `z80host.c`: runs `host.c`'s test on `page.s` on the emulator's Z80
  core (`emu/z80.c`), as `build/page_z80host`. The calls out go to
  fixed addresses it answers, every register but the result is
  clobbered on each, and IX and the stack are checked on each call in.
  Its PGTRACE output is the same as `page_host`'s.
