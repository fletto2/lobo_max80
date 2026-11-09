; The MAX-80 under Lobo's CP/M 2.2, CP/M 3 and xcpmz80, I/O block at
; F000h.

BDOS	equ	5
WINDOW	equ	0F000h		; SWAP1K, VLATCH bits 2-0 pick what shows
VLATCH	equ	0F7DCh		; write: the latch. Read: its RAM copy
CRTREG	equ	0F7E0h		; write: CRTC register index
CRTBYT	equ	0F7E1h		; write: CRTC register data
SYSFLG	equ	0F7E1h		; read: flags, bit 6 display timing
KEYS	equ	0F800h		; key row N at KEYS + (1 << N)
BEEP	equ	0F7F8h		; write: a beep, about 2 kHz for 1/15 s
VIDLO	equ	0FC00h		; video RAM 000h-3FFh

W_VIDEO	equ	2		; window: video RAM 400h-7FFh
W_FONT1	equ	4		; window: font RAM 1, codes 00h-7Fh
W_FONT2	equ	6		; window: font RAM 2, codes 80h-BFh

OFFRUN	equ	16		; SYSFLG bit 6 off this many readings: vertical blank
COLS	equ	80		; video RAM bytes a row
ROWS	equ	24
CURSOR	equ	7Fh		; the BIOS cursor's code in video RAM
