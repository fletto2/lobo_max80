# MAX-80 emulator

An emulator of the Lobo MAX-80 in C: the Z80 (`z80.c`), the machine
(`max80.c`), its floppy controller and drives, SASI hard disk, video,
keyboard, beeper, serial and printer ports, clock chip and expansion
bus. It draws in an SDL2 window, or in the terminal as text.

## Build and test

```sh
make            # make SDL=0 for the terminal-only build
make test
```

SDL2 is found with pkg-config. Without it the emulator has the
terminal only. `make test` runs `test.sh`: the CP/M CPU tests
(`cpmtest.c`), write track and read track, the clock chip and the
drive connectors (`test_track.c`), the SASI disk (`test_sasi.c`), an
interrupt right after `LD A,I` (`test_iff.c`), the window's keys
(`test_keys.c`, with SDL2), and, when `../xcpmz80` has been built, a
boot of xcpmz80. `test_sound.py` checks beeps recorded with `-s`, and
`test_frame.py` a frame saved with `-p`. `frame2png.py frame.pgm
out.png` turns such a frame into a PNG, as `../screenshots/make.sh`
does.

## Run

```sh
./max80 -K -a ../xcpmz80/build/xcpmz80.imd
```

Ctrl-] quits. The boot ROM is read from `../reference/rom/max80.e12`.
Disk images are IMD files, and a loaded image is never written to.

## Options

| Option | What it does |
| --- | --- |
| `-r rom` | The boot ROM, default `../reference/rom/max80.e12`. |
| `-a`, `-b`, `-c`, `-d disk.imd` | The disk in drive A to D. |
| `-h hard.img` | A SASI hard disk, a raw image of 512-byte blocks. |
| `-n drive` | A blank, unformatted disk in this drive, for FORMAT. |
| `-R drive` | Write-protect this drive's disk. |
| `-3 drive` | Make this drive a 3.5-inch one at 300 rpm. |
| `-w drive:file` | At exit, save the drive's disk to a new file, such as `b:new.imd` or `h:new.img`. Never over or beside a loaded image. |
| `-D dips` | The DIP switch byte, default 2, an 8-inch floppy boot. 1 boots a 5-inch floppy, 7 the SASI disk, 0 makes the ROM beep. |
| `-f` | Run as fast as the host allows. |
| `-T` | Draw in the terminal, not a window. |
| `-k keys` | Type these keys at the prompt. `\r` is Enter, `\e` ESC, `\U \D \L \R` the arrows, `\1` to `\4` F1 to F4, `\B` BREAK, `\E` an Enter with no wait, `\P` a second's pause. |
| `-e text` | The prompt `-k` waits for, default `A>`, or several as `A>\|B>`. |
| `-K` | Type letters for an OS that boots with Caps Lock on, as xcpmz80 does, so scripts keep their case. |
| `-t seconds` | Run this many emulated seconds with no window, print the screen and exit. |
| `-p frame.pgm` | With `-t`, also save the last frame as a PGM image. |
| `-s sound.wav` | Record the beeps to a WAV file. |
| `-l printer.txt` | A printer on the parallel port, saving what it prints. |
| `-o ch:file` | Save what serial channel `a` or `b` sends. |
| `-i ch:file[@secs]` | Feed a file to a serial channel, from `secs` emulated seconds on. The sender waits while the SIO's FIFO is full. |
| `-I ch:file[@secs]` | The same, but the sender never waits, so unread bytes are lost. |
| `-S ch` | Nothing plugged into this channel: CTS and DCD read off. |
| `-F v:off:bit` | Hold a bit of video RAM (`v`), font RAM (`f`) or main RAM (`m`, offsets 0-1FFFF) at 0 when read. `c:3:2` makes chunk 3 decode as chunk 2, `d:2:0` keeps the FDC busy from second 2. For the diagnostic. `s:3:0` hangs the SASI drive on its 3rd command (hex), BSY kept and no REQ, until a bus reset. |
| `-x port` | A card on the expansion bus at this port, in hex, that reads back the last byte written. |
| `-m 128\|64\|64f` | The RAM fitted. 64 leaves out bank B, which reads FFh; 64f reads back the last byte written. |
| `-C` | Hold the clock chip's TIME SET button down. |
| `-B` | Draw each character as the beam passes it. |
| `-V T` | Stretch each video and font RAM access by 0 to T T-states, at random. |
| `-L` | At exit, print how many FDC commands had Lost Data. |
| `-M` | Give the drives their mechanics: a turning track, the data rate, step, settle and spin-up times, with a summary at exit. |
| `-G fdc.log` | Log each FDC command with its emulated time. |
| `-g` | Debug sockets, Linux only, described at the top of `max80.c`. |
| `-N name` | With `-g`, appends `_name` to each socket's name, `/tmp/max80_name.sock` and so on, so two emulators with `-g` can run at once. |

The comment at the top of `max80.c` has each option in full.

## License

MIT, in `LICENSE`.
