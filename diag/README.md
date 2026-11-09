# MAX-80 diagnostic disk

A boot disk for the Lobo MAX-80 that runs no operating system. The boot
ROM loads it, and it tests the hardware from a menu. MIT license.

Build with `make` (needs sjasmplus and Python 3), test with `make test`
(needs the emulator built in `../emu`). Run it with
`../emu/max80 -a build/diag.imd`, or `-D 1 -a build/diag_525.imd` for
the 5.25-inch disk.

## Disks

- `build/diag.imd`: 8-inch, one side, FM, 77 tracks of 8 x 512,
  sectors from 0, 3:1 interleave, 308K. Boots with DIP setting 2.
- `build/diag_525.imd`: 5.25-inch, one side, MFM, 40 tracks of 9 x
  512, sectors from 0, 2:1 interleave, 180K. Boots with DIP setting 1.

The boot ROM tries MFM, then FM, so either density boots, and the boot
sector reads the rest at the density the ROM found.

## Menu

- 1: Video RAM test. March U on all 2K of the screen RAM (D16), below.
- 2: Font RAM test. The same on the 2K font RAM (E21). The font is
  loaded again after it.
- 3: Test screens, 80 columns: solid, grid, dots, vertical lines,
  horizontal lines, H everywhere, a frame round the edge, the
  character set. A key steps to the next one, BREAK or ESC goes back.
- 4: The same in 40 columns (VLATCH bit 3), then the even cells
  (R2 = 97) and the odd cells (R2 = 98).
- 5: The character set alone.
- 6: Main RAM test, all 128K, and banking, below.
- 7: Keyboard test, below.
- A: All three RAM tests over and over, with the pass and failure
  counts. Hold a key to stop.
- 8: Beeper. Each key beeps, ESC goes back and clears it away.
- F: Disk drives, below.
- 9: Serial ports, below.
- B: Printer port, below.
- C: Expansion bus, below.
- D: Clock chip, below.
- E: DIP switches, below.
- G: Video timing, below.
- H: Winchester interface. I have not written this test, and the item
  says so.

Items I (Write-through to RAM) and J (Memory timing) are off the menu:
they measured the machine to check the emulator, and are not
diagnostics of it. The code stays in `src/wthru.asm` and
`src/memtime.asm`, the sections below describe it.

The results go on rows 15-20, a row below the prompt. The bottom three rows
show the RAM found (64K without bank B, 128K with it), the boot
device from the boot ROM's MLATCH, and the serial port setting. A
longer report runs over them a page at a time, with "More: any key."
on row 24, then "Any key for the menu." at its end. Under A, which
must not stop, a long report is cut at row 24 instead, and the whole
of it is on the serial copy.

Video RAM and font RAM get March U, the same steps as main RAM below,
once for each of four backgrounds: 00h, 55h, 33h and 0Fh as the 0 of
the march, each inverted as the 1. March U finds stuck bits, address
faults and cells that disturb each other, and the four backgrounds
between them find data bits shorted together. A failure is reported
with the error count, the first bad offset, what was written and read
there, and every data bit that was ever wrong. One bad cell gives 12
errors, three in each background. The screen or the font is unreadable
while the test runs, so nothing is shown until the result.

## Main RAM and banking

The 128K is four 32K chunks, A1, A2, B1 and B2. Each is tested while
mapped at 8000h-FFFFh, with the I/O block moved to 0000h so all 32K is
reached. It takes about 16 seconds, with a status line on the screen
and the serial port giving the chunk, the March U step and the errors
so far.

1. Bank B is looked for, as the boot ROM does. Without it only A1 and
   A2 are tested.
2. Banking, high half: each chunk gets its own tag, A1h, A2h, B1h or
   B2h, then each is read back. A chunk that shows another's tag is
   decoded wrong. Both chunks are left out of the March U test, since a
   march on a chunk that lands in A1 would wipe out the program.
3. March U on A2, B1 and B2, 13 operations a byte: up w0, up r0 w1 r1
   w0, up r0 w1, down r1 w0 r0 w1, down r1 w0. Every error is counted
   and its bits kept, so one bad bit does not hide another.
4. Banking, low half: each good chunk gets a copy of the program with
   its tag in it, then each is put in the low half in turn, the code
   going on from the copy, and the tag read.
5. A1, which holds the program, is tested from a copy in a chunk that
   passed. Then the program goes back into A1. The screen copy to SIO
   A is off during it: a write to the I/O block also lands in A1,
   whatever the PIO maps.
6. Retention: each chunk but A1 that banking found safe gets a pattern
   from its addresses, is left alone for about 1 s with only the refresh
   to keep it, and is read back. Then again with the pattern inverted.
   A chunk that loses data here has a refresh fault, which March U,
   reading each byte soon after writing it, does not find.

A chunk that failed March U or the high half check is not used for the
low half check, and the report names it as NOT CHECKED there, with
"Banking: PASS, not every chunk checked" when the rest passed. Bank B
is found by writing two patterns to two bytes and reading both back,
so a missing bank on a bus that holds the last byte written is not
taken for RAM.

A failure gives the error count, the first bad offset in the chunk,
what was written and read there, the bad data bits, and the row of
4164s, bank A (A1, A2) or bank B (B1, B2). The 4164 for data bit n of
that row is the one to change. The schematics do not number the chips,
so they do not say which board position holds which bit.

## Keyboard

The screen shows the 8 x 8 key matrix as a grid, a row for each
address line (801h to 880h) and a column for each data bit (D0 to D7).
A key not pressed yet is in the thin face. A key in brackets, `[A]`, is
down as the matrix reads it at that moment, with no debounce, so a key
that bounces or drops out flickers. A key that has been pressed at
least once, debounced as the menu does it, turns thick and gets a `+`,
and the count of keys pressed goes up to 63. The SHIFT, CTRL, arrow and
function keys are matrix keys like the rest, and the keypad shares its
positions with the main keys. Each key beeps as it goes down. 880h D6 has
no key on it (TRM) and its cell is blank.

A key that shows down with nothing pressed is stuck. A whole row or
column that never shows points at its address line or data bit rather
than at the keys. Three keys down together can show a fourth that is
not (TRM TS-17).

ESC three times in a row goes back to the menu, or any key typed on the
terminal. The key that chose the test may show as pressed already.

## Disk drives

The screen shows the settings, what the drive sends back, and the keys:

- 1-4 select DS1-DS4 (connector pins 26-32 on 8-inch, 10, 12, 14 and
  6 on 5.25-inch), 0 selects none. C picks the 8-inch or the 5.25-inch
  connector, MLATCH bit 5, which also sets the FDC clock. S sets side 1.
- I and O step in and out, R recalibrates (restore), E seeks to track
  76 on 8-inch or 39 on 5.25-inch. None of them verify, so they work
  with no disk in the drive. Step out at track register 0 still steps
  but leaves the register at 0.
- P turns the step rate round: 3, 6, 10 and 15 ms on 8-inch, 6, 12, 20
  and 30 ms on 5.25-inch (the FDC at 2 MHz or 1 MHz). It starts at the
  slowest, as the boot ROM does.
- H loads the head, the FDC's HLD on 8-inch pin 18, kept loaded by a
  seek in place each second. M keeps the 5.25-inch motor on by writing
  MLATCH again and again. Any MLATCH write starts the 3 s motor timer,
  so selecting a 5.25-inch drive starts it too.
- A reads the ID fields under the head on the selected side with
  READ ADDRESS, up to 40 times, MFM then FM. One line: the density, the
  track and sector size the IDs carry, the sector numbers found, in
  order, any CRC errors and reads that found no ID, or NONE. Three
  misses in a row end it. It needs a drive selected, on 5.25-inch
  the motor on with M, and an index pulse within 2 s, so a disk in. A 360K PC
  disk at track 0 shows `MFM, track 0, 512 bytes, sectors 1 2 3 4 5 6
  7 8 9` on either side. A single sided disk written over an old double
  sided one keeps the old IDs on side 1.

Ready, track 0, write protect, head loaded and seek error come from the
FDC's type I status. Single sided and the 5.25-inch motors are SYSFLG
bits 4 and 5. The speed is timed over four turns between index pulses,
against the 61.035 Hz tick. NO INDEX means no pulse came in a second.
There is no head lock line on either connector, and the 8-inch one has
no motor line.

Each value is drawn again only when it changes, so a key is not kept
waiting while the whole screen goes out the serial port. Last command
shows how the last step, seek or restore ended: DONE, STOPPED when ESC
or BREAK stopped it, or TIMED OUT when the FDC stayed busy for 10 s.
Either way the FDC gets a force interrupt, and the test goes on.

## Video timing

SYSFLG bit 6 is the CRTC's display enable, on only while the beam is in
the picture. The test shows whether it toggles (STUCK ON or STUCK OFF
if not), and whether an off run longer than a line, the vertical
blank, comes. Then it counts the lines of picture between two vertical
blanks and times four frames, 200 lines and four ticks with one loop of
70 T-states, which gives:

- Lines a frame, from the frame time over the line time.
- The vertical blank, those less the lines of picture, in lines and ms.
- The frame rate, the line rate and the line period, against the
  61.035 Hz tick from the 8 MHz crystal.

With Lobo's CRTC table, as the program sets it, that should be 216
lines of picture, 264 a frame, 59.97 Hz, 15.83 kHz and 63.2 us. The
timed values are good to about one turn of the loop, 0.1% on the line
time. Any key measures again, ESC goes back. Keys pressed while it
measures are lost.

## Serial ports

Both SIO channels side by side, each set up as the menu has channel A:
9600, 8 bits, one stop bit, no auto enables, DTR and RTS on. A or B
picks the channel the other keys act on. R steps through the 16
COM8116 rates, D and T turn DTR and RTS on and off, K holds TxD at
space (break), S sends a test line over and over, C clears the bytes
received. CTS, DCD and break on RxD are read live from RR0. The bytes
received are counted and the last 8 shown in hex. A byte on channel A
is also taken as a key, so a terminal there can run the test. The Z80
SIO has no loopback mode, so an output is checked with a scope or
meter, or by wiring it to an input of the same port. ESC sets channel
A back to 9600 and resets channel B, which turns its outputs off.
A change to channel A (R, D, T, K or S on it) stops the screen copy on
it, which would garble what the change is for. ESC puts the copy back.

The emulator keeps DTR, RTS and break but does nothing with them, and
reads CTS and DCD always on, so only the rates, sending and receiving
are tested there.

## Printer port

The four status inputs, read from PSTAT over and over, each shown HIGH
or LOW and marked YES under Changed once it has changed since the test
started. Below them whether Lobo's CP/M BIOS would call the printer
ready (BUSY low) and whether LDOS would (bits 7-4 are 0011). The
eight outputs are set by key: 0-7 toggle one bit, Z writes 00h, F
writes FFh, W walks a 1 across them every half second, S sends a test
line over and over, each byte once BUSY is low. The byte last written
is shown in hex and in bits, with the count of writes. Every write
strobes pin 1, so a printer prints what is written. The data latch
cannot be read back, so the outputs are checked with a meter or LEDs.
The test writes 00h at the start. ESC goes back.

The emulator's printer reads F0h with no `-l` file, and with one 30h,
or B0h for 0.5 ms after each byte, so only BUSY moves there.

## Expansion bus

Every port, 00h-FFh, read once with `IN` and shown on a 16 x 16 grid,
FFh thin and anything else thick, with the count of ports not reading
FFh. A port with no card reads the floating data lines, probably FFh.
Reading a port can change a card, so the grid is read only at the
start and on S. One port is chosen, by the arrows or by P and two hex
digits, and shown in brackets. V and two hex digits set the byte to
write. O writes it once, W writes it over and over and R reads the
port over and over, for a scope on XOUT-, XIN- and XA0-XA7. K writes
00h, FFh, 55h, AAh and a walking 1 and reads each back, PASS for a
card that latches what is written, or FAIL with the byte written and
the byte read. XINT-, XNMI- and XWAIT- are not tested. ESC goes back.

The emulator reads FFh on every port. Its `-x 40` puts a card at port
40h that reads back the last byte written to it, 00h at the start.

## Clock chip

The MSM5832's 13 registers, read through the PIO as Lobo's TIMESET
reads them, until two passes
agree. Shown as digits and decoded: the time, the hour mode, the date,
the day of the week and the leap year flag, and whether each digit is
in its range. Each new second is timed against the tick, which should
give 61. The TIME SET button on the back is checked twice a second:
under HOLD the test writes an illegal 6 to register 3, tens of
minutes, reads it back and puts the old digit back. Only a held
button lets the write through, so a 6 read back means HELD. The test
does not set the clock. ESC goes back.

The emulator's clock starts at the host's time and counts emulated
seconds. It ignores writes, so the button always reads NOT HELD
there.

## DIP switches

The eight switches, read from DIPSW over and over, each shown UP or
DOWN and marked YES under Moved once it has changed since the test
started. Below them the byte and the boot device switches 6-8 pick,
from the boot ROM's table. ESC goes back. The emulator sets the
switches with `-D` and cannot move them while it runs, so Moved is not
tested there.

## Write-through to RAM

Item I answers which I/O block writes also land in RAM, and in
which chunk. For the block at 0000h and at F000h, and with A2, B1 and
B2 in the high half, it seeds the cells at each register's offset and
at the offset plus 7000h in all four chunks, writes each register
once, and shows which cells changed as a sum of the values on the
screen. The program stays in A1 in the low half. VLATCH and the PIO are
left out, since writing them moves the block or the map. The test beeps
once a case and sends a NUL to the printer and SIO channel A.

The emulator follows the schematics: 80h in every row with the block at
0000h, 40h with it at F000h.

## Memory timing

Item J answers how many T-states a video RAM access costs over
plain RAM, which the TRM says stretches the clock by a small but
unpredictable amount, and the same for font RAM (through the window)
and SLORAM, which it says runs slowly. Each is timed as passes of 16
reads, or 16 writes of the byte already there, counted over 8 ticks,
against the same passes on plain RAM at A000h just before. A pass on
plain RAM is 149 T-states, so the cost of an access is 149 x (plain
passes - its passes) / (its passes x 16), a ratio of counts that does
not depend on the clock. Four runs each, the lowest and highest shown.

The emulator gives 0.00 with no `-V`, and about n/2 with `-V n` for
video and font RAM.

## Screen

Headings, choices, results and numbers are in the font's normal face,
the rest of the text in its thin second style (ESC ) in xcpmz80). The
strings switch between them with TH and TK, which `cons.asm` keeps off
the serial port.

## Serial port

Everything on the screen also goes out SIO channel A at 9600 8N1, with
VT100 cursor moves, and keys typed on a terminal there work as the
keyboard does. The program does not use the SIO's auto enables, so a
cable with nothing on CTS and DCD works. If the transmitter never
empties, the copy turns itself off.

## Memory

The PIO is at 40h, as the boot ROM left it: A1 at 0000h-7FFFh, A2 at
8000h-FFFFh, the I/O block at F000h, except while the main RAM test
runs. The program runs in A1 from 1000h,
the stack, the screen copy and the variables are
in A1 below 8000h. Interrupts stay off, and the tick is polled.

## Files

- `src/diag.asm`: The top file, the program's layout.
- `src/boot.asm`: The boot sector. It loads the program with the boot
  ROM's READ and moves the I/O block to F000h.
- `src/vars.inc`: The memory plan and the variables.
- `src/main.asm`: Start, the menu, run all.
- `src/setup.asm`: The CRTC, SIO and font setup and the RAM size, shared with `monitor/`.
- `src/cons.asm`: The screen and its serial copy.
- `src/keys.asm`: The tick, the keyboard scan and the serial input.
- `src/memtest.asm`: The video RAM and font RAM tests.
- `src/mainram.asm`: The main RAM and banking tests.
- `src/screens.asm`: The test screens.
- `src/keytest.asm`: The keyboard test.
- `src/disktest.asm`: The disk drive test.
- `src/vtime.asm`: The video timing test.
- `src/dipsw.asm`: The DIP switch test.
- `src/serial.asm`: The serial port test.
- `src/printer.asm`: The printer port test.
- `src/rtc.asm`: The clock chip test.
- `src/bus.asm`: The expansion bus test.
- `src/wthru.asm`: Which I/O block writes reach RAM.
- `src/memtime.asm`: What a video RAM, font RAM or SLORAM access costs.
- `tools/mkdisk.py`: Makes the IMD disks from the assembled program.
- `test.sh`: The tests, in the emulator. `-F` there sticks a bit of
  video, font or main RAM at 0, or makes one RAM chunk decode as
  another, or keeps the FDC busy, to check that the tests find it.
  `-m 64` leaves bank B out, `-m 64f` on a bus that holds the last
  byte written. `-x` puts a card on the expansion bus.

The hardware addresses come from `../xcpmz80/src/hw.inc` and the font
from `../xcpmz80/src/font.bin`.
