; The MAX-80 under xcpmz80, I/O block at F000h, as the MAX-80 Technical
; Reference Manual gives it.

BDOS	equ	5
WINDOW	equ	0F000h		; SWAP1K, VLATCH bits 2-0 pick what shows
VLATCH	equ	0F7DCh		; write: the latch. Read: its RAM copy
CRTREG	equ	0F7E0h		; write: CRTC register index
SYSCLR	equ	0F7E0h		; read: clears the tick
CRTBYT	equ	0F7E1h		; write: CRTC register data
SYSFLG	equ	0F7E1h		; read: flags, bit 6 display timing
KEYS	equ	0F800h		; key row N at KEYS + (1 << N)
VIDLO	equ	0FC00h		; video RAM 000h-3FFh
TICKVEC	equ	0FBFEh		; xcpmz80's tick vector, IM 2, I = FBh

W_VIDEO	equ	2		; window: video RAM 400h-7FFh
W_FONT1	equ	4		; window: font RAM 1, codes 00h-7Fh
W_FONT2	equ	6		; window: font RAM 2, codes 80h-BFh
WIDE	equ	08h		; VLATCH bit 3, 40 columns

OFFRUN	equ	16		; SYSFLG bit 6 off this many readings: vertical blank
COLS	equ	80		; video RAM bytes a row
ROWS	equ	24
CURSOR	equ	7Fh		; the BIOS cursor's code in video RAM
