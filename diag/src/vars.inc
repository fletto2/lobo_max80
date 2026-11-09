; Diagnostic memory plan. The PIO is at 40h, as the boot ROM
; set it: A1 low, A2 high. The program runs in A1 from 1000h, and the
; I/O block sits at F000h over A2. The main RAM test changes both while
; it runs, mainram.asm.

SHADOW		equ	7000h		; the 80 x 24 screen, 1920 bytes
VARS		equ	7800h
STACK		equ	8000h

crow		equ	VARS+00h	; cursor row, then column
ccol		equ	VARS+01h
scrout		equ	VARS+02h	; nonzero: putc writes the screen
sioon		equ	VARS+03h	; nonzero: putc copies to SIO A
kkey		equ	VARS+04h	; the last key pressed, 0 when taken
bootml		equ	VARS+05h	; the boot ROM's MLATCH, 20h set for 8-inch
vlnow		equ	VARS+06h	; VLATCH as set, window on video RAM
stride		equ	VARS+07h	; video cells a column, 1 or 2 (40 columns)
ticks		equ	VARS+08h	; ticks counted by poll, 2 bytes
merr		equ	VARS+0Ah	; memory test: errors, 2 bytes
mbits		equ	VARS+0Ch	; bits that were wrong, ORed
mfirst		equ	VARS+0Dh	; first error: offset, 2 bytes
mwrote		equ	VARS+0Fh	; and what was written
mread		equ	VARS+10h	; and what came back
mdir		equ	VARS+11h	; memory test: 0 marching up, 1 down
mdelta		equ	VARS+12h	; and the piece's offset less its address, 2 bytes

passes		equ	VARS+14h	; run all: passes, 2 bytes
fails		equ	VARS+16h	; run all: passes with an error, 2 bytes
vfails		equ	VARS+18h	; run all: video RAM failures, 2 bytes
ffails		equ	VARS+1Ah	; run all: font RAM failures, 2 bytes
sodd		equ	VARS+1Ch	; 40 columns: 1 puts text in the odd cells
rmode		equ	VARS+1Dh	; results area: 0 off, 1 a page at a time, 2 cut at row 23
ovrun		equ	VARS+1Eh	; nonzero: results ran past row 20, over the footer
rclip		equ	VARS+1Fh	; nonzero: results cut, nothing more on the screen
k1		equ	VARS+20h	; keyboard: the last scan, 8 rows
k2		equ	VARS+28h	; keyboard: the last stable scan, 8 rows
res		equ	VARS+30h	; main RAM: a result for each chunk, RESZ bytes
nchunk		equ	VARS+50h	; chunks found, 2 or 4
bhigh		equ	VARS+51h	; banking: each chunk's tag as read in the high half
blow		equ	VARS+55h	; and in the low half
mmfails		equ	VARS+59h	; run all: main RAM failures, 2 bytes
rabad		equ	VARS+5Bh	; run all: nonzero if this pass failed
bunsafe		equ	VARS+5Ch	; banking: chunks not safe to march, bit 0 A1
blkhi		equ	VARS+5Dh	; the I/O block's high byte, F0h, 00h in the main RAM test
pstat		equ	VARS+5Eh	; main RAM: the status line, row then column
mtag		equ	VARS+60h	; main RAM: the tag of the chunk under test
blchk		equ	VARS+61h	; banking: chunks the low half check read, bit 0 A1
kcur		equ	VARS+64h	; keyboard test: each row as last drawn, 8 bytes
kseen		equ	VARS+6Ch	; and the keys pressed so far, 8 bytes
kdrawn		equ	VARS+74h	; and the keys pressed as last drawn, 8 bytes
kesc		equ	VARS+7Ch	; and ESC presses in a row
kchg		equ	VARS+7Dh	; and the cells of a row still to draw
kpoll		equ	VARS+7Eh	; nonzero: putc scans the keyboard
thin		equ	VARS+7Fh	; nonzero: putc writes the thin second style
dsel		equ	VARS+80h	; disk test: drive 1-4, 0 none
dside		equ	VARS+81h	; and the side
deight		equ	VARS+82h	; and 20h for the 8-inch connector
dmotor		equ	VARS+83h	; and nonzero to keep the 5.25-inch motor on
dhead		equ	VARS+84h	; and nonzero to keep the head loaded
drate		equ	VARS+85h	; and the step rate bits
dlatch		equ	VARS+86h	; and MLATCH as written
ddirty		equ	VARS+87h	; and nonzero to draw every value again
dstat		equ	VARS+88h	; and the FDC status, complemented
dsysf		equ	VARS+89h	; and SYSFLG
drpm		equ	VARS+8Ah	; and the speed, 0 for no index, 2 bytes
drpmsh		equ	VARS+8Ch	; and the speed as drawn, 2 bytes
dhtick		equ	VARS+8Eh	; and the tick of the last head load, 2 bytes
dt0		equ	VARS+90h	; speed: the tick it started, 2 bytes
dfirst		equ	VARS+92h	; and the loop count at the first tick, 3 bytes
dlast		equ	VARS+95h	; and at the last tick, 3 bytes
dvd		equ	VARS+98h	; and a dividend, 4 bytes
dvs		equ	VARS+9Ch	; and a divisor, 4 bytes
drem		equ	VARS+0A0h	; and a remainder, 4 bytes
direv		equ	VARS+0A4h	; and the loop count over the turns, 4 bytes
dshsel		equ	VARS+0A8h	; disk test: the drive as drawn
dsheight	equ	VARS+0A9h	; and the connector
dshside		equ	VARS+0AAh	; and the side
dshrate		equ	VARS+0ABh	; and the step rate with the connector
dshtrk		equ	VARS+0ACh	; and the track register
dres		equ	VARS+0ADh	; disk test: the last command, 0 none, 1 done, 2 stopped, 3 timed out
dshres		equ	VARS+0AEh	; and as drawn
dfm		equ	VARS+0AFh	; disk test: 0 MFM, 40h FM
vpic		equ	VARS+0B0h	; video timing: lines of picture, 2 bytes
vif		equ	VARS+0B2h	; and the loop's turns over VFN frames, 2 bytes
vil		equ	VARS+0B4h	; and over VLN lines, 2 bytes
vit		equ	VARS+0B6h	; and over VTN ticks, 2 bytes
vlf		equ	VARS+0B8h	; and lines a frame x 10, 2 bytes
vt01		equ	VARS+0BAh	; and the line period in 0.1 us, 2 bytes
vres		equ	VARS+0BCh	; and 0, or what stopped the measuring
did		equ	VARS+0B0h	; disk test: an ID field, 6 bytes, over vpic-vil
dmap		equ	VARS+0B6h	; and the sectors seen, a bit each, 4 bytes, over vit-vlf
dmiss		equ	VARS+0BAh	; and the reads that found no ID, over vt01
drun		equ	VARS+0BBh	; and those in a row
dpfirst		equ	VARS+0BDh	; DIP switches: as read at the start
dpshown		equ	VARS+0BEh	; and as drawn
dpmoved		equ	VARS+0BFh	; and the ones that have moved, set
spa		equ	VARS+0C0h	; serial test: channel A, 24 bytes, serial.asm
spb		equ	VARS+0D8h	; and channel B, 24 bytes
spsel		equ	VARS+0F0h	; and the channel keys act on, 0 A, 1 B
ppdata		equ	VARS+0F8h	; printer test: the byte last written
ppmode		equ	VARS+0F9h	; and 0 idle, 1 sending, 2 walking
ppidx		equ	VARS+0FAh	; and the next byte of the test line
ppcnt		equ	VARS+0FBh	; and the writes, 2 bytes
ppfirst		equ	VARS+0FDh	; and the status as read at the start
ppchg		equ	VARS+0FEh	; and the status bits that have changed, set
ppwt		equ	VARS+0FFh	; and the tick of the last walk step, 2 bytes
ppdt		equ	VARS+101h	; and the tick of the last redraw, 2 bytes
ppdst		equ	VARS+103h	; and as drawn: the status
ppdchg		equ	VARS+104h	; the changed bits
ppddata		equ	VARS+105h	; the byte written
ppdcnt		equ	VARS+106h	; the writes, 2 bytes
ppdmode		equ	VARS+108h	; the mode
rtregs		equ	VARS+110h	; clock test: the 13 registers as read
rtdreg		equ	VARS+11Dh	; and as drawn, 13 bytes
rtsec		equ	VARS+12Ah	; and the seconds digit last seen
rtseen		equ	VARS+12Bh	; and 1 once a second has changed
rtlast		equ	VARS+12Ch	; and the tick it changed, 2 bytes
rtint		equ	VARS+12Eh	; and the ticks of the last whole second, 2 bytes
rtdint		equ	VARS+130h	; and as drawn, 2 bytes
rtbt		equ	VARS+132h	; and the tick of the last button check, 2 bytes
rtbtn		equ	VARS+134h	; and 1 if the button is held
rtdbtn		equ	VARS+135h	; and as drawn
rtdcnt		equ	VARS+136h	; and counting as drawn
bxport		equ	VARS+140h	; bus test: the port chosen
bxbyte		equ	VARS+141h	; and the byte to write
bxmode		equ	VARS+142h	; and 0 idle, 1 writing, 2 reading
bxcnt		equ	VARS+143h	; and the writes, 2 bytes
bxrd		equ	VARS+145h	; and the port's last read
bxent		equ	VARS+146h	; and the field being typed, 1 port, 2 byte
bxhex		equ	VARS+147h	; and its digits so far
bxhn		equ	VARS+148h	; and how many
bxck		equ	VARS+149h	; and the read-back: 0 not tested, 1 pass, 2 fail
bxckw		equ	VARS+14Ah	; and the byte it wrote last
bxckr		equ	VARS+14Bh	; and read back
bxdt		equ	VARS+14Ch	; and the tick of the last redraw, 2 bytes
bxdport		equ	VARS+14Eh	; and as drawn: the port
bxdbyte		equ	VARS+14Fh	; the byte
bxdcnt		equ	VARS+150h	; the writes, 2 bytes
bxdmode		equ	VARS+152h	; the mode
bxdrd		equ	VARS+153h	; the last read
bxdck		equ	VARS+154h	; the read-back
rterr		equ	VARS+155h	; main RAM retention: errors per chunk, to 255, 4 bytes
rtbits		equ	VARS+159h	; and the bad bits per chunk, 4 bytes
bxval		equ	VARS+160h	; and the 256 ports as scanned
VARSZ		equ	260h

; The low half check reads SIG in each chunk's copy of the program
SIG		equ	6700h

