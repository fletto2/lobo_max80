; The monitor's variables, after the diag's, which cons.asm and keys.asm
; use. All of it is in 7000h-7FFFh of the chunk in the low half, with
; the program at 1000h. RUN copies both.

MV		equ	VARS+VARSZ
lp		equ	MV+00h		; the parser's place in LINE, 2 bytes
lowch		equ	MV+02h		; the chunk in the low half, the monitor's
curmap		equ	MV+03h		; the chunk shown high, FFh for the normal map
pionow		equ	MV+04h		; the PIO in the normal map
rlen		equ	MV+05h		; bytes left, 2 bytes
refa		equ	MV+07h		; an address: chunk or FFh, then 2 bytes
refb		equ	MV+0Ah		; and a second
refc		equ	MV+0Dh		; and where the first started
refd		equ	MV+10h		; and where the second started
dnext		equ	MV+13h		; where D goes on
rtmp		equ	MV+16h		; a hit's address, to print
coff		equ	MV+19h		; offset from the start, 2 bytes
hcount		equ	MV+1Bh		; hits, 2 bytes, stops at FFFFh
hn		equ	MV+1Dh		; hits kept in HITS
pn		equ	MV+1Eh		; bytes in this piece, 2 bytes
inq		equ	MV+20h		; nonzero: the line is inside quotes
lesc		equ	MV+21h		; nonzero: the line ended with ESC or BREAK
ebyte		equ	MV+22h		; E: the byte as it was
ewrote		equ	MV+23h		; and as written
ksum		equ	MV+24h		; K: the 8-bit sum
kcrc		equ	MV+25h		; and the CRC, 2 bytes
plen		equ	MV+27h		; S: the pattern's length, 2 bytes
np		equ	MV+29h		; and the places to try in this piece, 2 bytes
tlen		equ	MV+2Bh		; T: the length
tpat		equ	MV+2Dh		; and the pattern's number
tbits		equ	MV+2Eh		; and the failing bits, ORed
goaddr		equ	MV+2Fh		; G with no address: 2 bytes
gochunk		equ	MV+31h		; and its chunk, FFh for a Z80 address
gohas		equ	MV+32h		; and nonzero if there is one
dlines		equ	MV+33h		; D: lines on this screen
lcount		equ	MV+34h		; L: lines read, 2 bytes
ltype		equ	MV+36h		; and this record's type digit
lsum		equ	MV+37h		; and its sum
lnum		equ	MV+38h		; and its data bytes left, 2 bytes
lptr		equ	MV+3Ah		; and where they are, 2 bytes
inload		equ	MV+3Ch		; nonzero: a stop has a file to wait out
psum		equ	MV+3Dh		; P: the record's sum
rtgt		equ	MV+3Eh		; RUN: the chunk to go to
MVEND		equ	MV+40h

LINEMAX		equ	72
LINE		equ	7B00h		; the line typed
BUF		equ	7B80h		; a piece of memory, 288 bytes
BUF2		equ	7CA0h		; and a second, 256 bytes
PAT		equ	7DA0h		; S: the pattern, 32 bytes
PATMAX		equ	32
HITS		equ	7DC0h		; 16 hits of 4 bytes: offset, two bytes
NHIT		equ	16

	assert	MVEND <= LINE
