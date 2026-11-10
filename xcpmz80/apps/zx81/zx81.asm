; ZX81.COM: ZX81 machine code games on xcpmz80. ZX81 NAME runs NAME.P, with the character
; shapes from ZX81.ROM on the same drive. The ROM is never run. MIT
; license, as xcpmz80.
;
; Reads the files, checks the .P, finds the start, takes over the screen
; and the tick and calls the game. The tick keeps FRAMES and LAST_K and
; copies D_FILE to the screen. BREAK, or the game's return, quits and
; puts everything back. /D shows light on dark, /F runs at full speed,
; /Y skips the warning for a .P not in the game table.

	include	"hw.inc"

; The ZX81's system variables, at their own addresses
ERR_NR	equ	4000h
RAMTOP	equ	4004h
VERSN	equ	4009h
D_FILE	equ	400Ch
DF_CC	equ	400Eh
VARS	equ	4010h
E_LINE	equ	4014h
STKEND	equ	401Ch
LAST_K	equ	4025h
NXTLIN	equ	4029h
FRAMES	equ	4034h
S_POSN	equ	4039h		; 33 less the column, then 24 less the line
PROGRAM	equ	407Dh		; the first BASIC line

NEWLINE	equ	76h		; ends a line
T_REM	equ	0EAh
T_RUN	equ	0F7h
T_USR	equ	0D4h
C_ZERO	equ	1Ch		; the digit 0

ROMBUF	equ	8000h		; ZX81.ROM while loading
ROMLEN	equ	2000h
SHAPES	equ	1E00h		; in the ROM: 64 shapes, 8 bytes each
XCOL	equ	4		; the 32 columns start here, in the 40
R2EVEN	equ	61h		; CRTC R2 showing the even characters
TPS	equ	61		; ticks a second, near enough
FPS	equ	50		; the ZX81's frames a second
BRAKE	equ	38		; x 1024 T-states to hold in two ticks, less the
				; wait for the blank, for 13,300 a tick to the game

	org	100h

start:	ld	hl,ccpsp	; our memory starts as nothing
	ld	de,ccpsp+1
	ld	bc,memend-ccpsp-1
	ld	(hl),0
	ldir
	ld	(ccpsp),sp
	ld	sp,stack
	ld	a,(5Dh)		; a name?
	cp	' '
	ld	de,m_usage
	jp	z,fail
	call	options
	ld	hl,5Ch		; the game's FCB, then the ROM's on its drive
	ld	de,fcb
	ld	bc,12
	ldir
	ld	hl,romname
	ld	de,romfcb
	ld	bc,12
	ldir
	ld	a,(5Ch)
	ld	(romfcb),a
	ld	hl,ext_p
	ld	de,fcb+9
	ld	bc,3
	ldir

	ld	de,romfcb	; the ROM's shapes
	ld	hl,ROMBUF
	ld	bc,ROMBUF+ROMLEN+128
	call	readfile
	ld	de,m_norom
	jp	c,fail
	ld	de,ROMBUF+ROMLEN
	or	a
	sbc	hl,de
	ld	de,m_badrom
	jp	nz,fail
	ld	hl,ROMBUF+SHAPES
	ld	de,shapes
	ld	bc,200h
	ldir

	ld	de,fcb		; the game
	ld	hl,VERSN
	ld	bc,8000h
	call	readfile
	ld	de,m_nop
	jp	c,fail
	call	checkp
	ld	de,m_badp
	jp	c,fail
	call	findusr
	ld	de,m_nousr
	jp	c,fail
	ld	(gostart),hl
	call	patch
	call	c,unknown

	ld	a,0FFh		; the system variables a .P does not save
	ld	(ERR_NR),a
	ld	hl,8000h
	ld	a,(E_LINE+1)	; 16K, or 1K for a .P that fits it
	cp	44h
	jr	nc,st_1
	ld	hl,4400h
st_1:	ld	(RAMTOP),hl

	ld	de,m_home	; home and erase, the cursor at the start
	ld	c,9
	call	BDOS
	call	findstart
	ld	de,m_nostart
	jp	c,fail
	call	vidin
	di
	call	rstin
	call	clearall
	call	copyd		; the first picture, then the tick's
	call	flip
	ld	sp,8000h-4	; under RAMTOP as on a ZX81: Pipepanic carves
				; its buffers from below the stack it finds
	ld	hl,quit		; the game returns here
	push	hl
	ld	hl,(gostart)
	push	hl
	ld	b,h		; BC the start, HL 1520h, as the ROM's USR
	ld	c,l		; leaves them
	ld	hl,1520h
	ei
	ret			; to the game

; BREAK, seen by the tick, or the game's return
quit:	di
	ld	sp,stack
	ld	a,1		; the tick only clears itself from now on
	ld	(quitting),a
	ei
qu_1:	ld	a,(KEYS+0FFh)	; every row: no key held
	or	a
	jr	nz,qu_1
	call	vidout
	call	rstout
	ld	de,m_cls
	ld	c,9
	call	BDOS
	ld	hl,(trapat)	; a ROM call we do not have: say where
	ld	a,h
	or	l
	jr	z,qu_2
	ld	de,m_trap
	ld	c,9
	push	hl
	call	BDOS
	pop	hl
	ld	a,h
	call	hexout
	ld	a,l
	call	hexout
	ld	de,m_crlf
	ld	c,9
	call	BDOS
qu_2:	ld	sp,(ccpsp)
	ret

; A in hex on the console. Keeps HL.
hexout:	push	hl
	push	af
	rrca
	rrca
	rrca
	rrca
	call	ho_1
	pop	af
	call	ho_1
	pop	hl
	ret
ho_1:	and	0Fh
	add	a,'0'
	cp	'9'+1
	jr	c,ho_2
	add	a,7
ho_2:	ld	e,a
	ld	c,2
	jp	BDOS

; A message and back to the shell
fail:	ld	c,9
	call	BDOS
	ld	sp,(ccpsp)
	ret

; /D anywhere in the command tail: light on dark. /F: full speed.
options:
	ld	hl,80h
	ld	b,(hl)
	inc	b
op_1:	dec	b
	ret	z
	inc	hl
	ld	a,(hl)
	cp	'/'
	jr	nz,op_1
	inc	hl
	dec	b
	ret	z
	ld	a,(hl)
	cp	'F'
	jr	nz,op_2
	ld	(fast),a
op_2:	cp	'Y'
	jr	nz,op_3
	ld	(yes),a
op_3:	cp	'D'
	jr	nz,op_1
	ld	(dark),a
	jr	op_1

; DE an FCB, HL where to read it, BC the limit. HL = past the last record
; read. Carry if the file is not there or does not fit.
readfile:
	ld	(rf_to),hl
	ld	(rf_lim),bc
	ld	(rf_fcb),de
	ld	hl,12		; a fresh FCB past its name
	add	hl,de
	ld	b,24
rf_0:	ld	(hl),0
	inc	hl
	djnz	rf_0
	ld	c,15		; open
	call	BDOS
	inc	a
	scf
	ret	z
rf_1:	ld	de,(rf_to)
	ld	c,26		; set the DMA address
	call	BDOS
	ld	de,(rf_fcb)
	ld	c,20		; read a record
	call	BDOS
	or	a
	ld	hl,(rf_to)
	ret	nz		; the end, no carry
	ld	de,128
	add	hl,de
	ld	(rf_to),hl
	ld	de,(rf_lim)
	or	a
	sbc	hl,de
	jr	c,rf_1
	scf
	ret

; HL past the last record of the .P. Carry unless it holds what its
; system variables say: E_LINE in the last two records, a display file
; of 25 NEWLINEs, each line up to 32 characters.
checkp:	ld	de,(E_LINE)
	or	a
	sbc	hl,de		; read - E_LINE
	ret	c
	ld	a,h
	or	a
	scf
	ret	nz
	ld	a,(VERSN)
	or	a
	scf
	ret	nz
	ld	hl,(D_FILE)
	ld	a,(hl)
	cp	NEWLINE
	scf
	ret	nz
	ld	c,ROWS
cp_1:	inc	hl
	ld	b,33		; 32 characters and the NEWLINE
cp_2:	ld	a,(hl)
	cp	NEWLINE
	jr	z,cp_3
	inc	hl
	djnz	cp_2
	scf
	ret
cp_3:	dec	c
	jr	nz,cp_1
	inc	hl
	ld	de,(E_LINE)	; inside the file
	ex	de,hl
	or	a
	sbc	hl,de
	ret

; HL = the address the game starts at, from the USR in the line at
; NXTLIN. A line that is RUN starts from the first line (Pipepanic's).
; Carry if there is none, or BASIC would have to run first.
findusr:
	ld	hl,(NXTLIN)
	push	hl
	inc	hl		; past the number and the length
	inc	hl
	inc	hl
	inc	hl
	ld	a,(hl)
	pop	hl
	cp	T_RUN
	jr	z,fu_all
	jr	usrline
fu_all:	ld	hl,PROGRAM
fu_1:	ld	de,(D_FILE)
	push	hl
	or	a
	sbc	hl,de
	pop	hl
	ccf
	ret	c		; the end of the program
	push	hl
	inc	hl
	inc	hl
	ld	e,(hl)		; the length
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	pop	hl
	cp	T_REM
	jr	z,fu_2
	push	hl
	push	de
	call	usrline
	pop	de
	pop	bc
	ret	nc
	ld	h,b
	ld	l,c
fu_2:	add	hl,de		; on to the next line
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	jr	fu_1

; HL a BASIC line: HL = the number after its USR. Carry if it has none
usrline:
	inc	hl
	inc	hl
	ld	c,(hl)		; the length, under 256 for a starting line
	inc	hl
	ld	b,(hl)
	inc	hl
ul_1:	ld	a,(hl)
	inc	hl
	cp	T_USR
	jr	z,ul_2
	cp	NEWLINE
	jr	nz,ul_1
	scf
	ret
ul_2:	ld	de,0		; the digits
ul_3:	ld	a,(hl)
	sub	C_ZERO
	jr	c,ul_4
	cp	10
	jr	nc,ul_4
	inc	hl
	push	hl
	ld	h,d
	ld	l,e
	add	hl,hl		; x 10
	add	hl,hl
	add	hl,de
	add	hl,hl
	ld	e,a
	ld	d,0
	add	hl,de
	ex	de,hl
	pop	hl
	jr	ul_3
ul_4:	ld	a,d
	or	e
	scf
	ret	z		; no digits
	ex	de,hl
	or	a
	ret

; The game table: a .P known by its length and CRC-16 gets its patches.
; Pipepanic reads the keys with IN A,(C), so that becomes RST 8 and a NOP.
; Carry if it is not in the table.
patch:	call	crc		; HL = the CRC
	ex	de,hl
	ld	hl,games
pa_1:	ld	a,(hl)		; the table's length, CRC, address
	inc	hl
	ld	c,a
	ld	b,(hl)
	inc	hl
	or	b
	scf
	ret	z
	push	hl
	ld	hl,(E_LINE)	; length
	push	de
	ld	de,-VERSN
	add	hl,de
	pop	de
	or	a
	sbc	hl,bc
	pop	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	jr	nz,pa_2
	ld	a,c
	cp	e
	jr	nz,pa_2
	ld	a,b
	cp	d
	jr	nz,pa_2
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ex	de,hl
	ld	a,h
	or	l
	ret	z		; no patch, no carry
	ld	(hl),0CFh	; RST 8
	inc	hl
	ld	(hl),0
	or	a
	ret
pa_2:	inc	hl
	inc	hl
	jr	pa_1

games:	dw	8038,3294h,4C84h	; Pipepanic: its one IN
	dw	4402,9494h,0		; Tetris
	dw	6693,0E29Bh,0		; Mine81
	dw	715,63C1h,0		; Tetris1k
	dw	0

; A .P not in the table: what the REM line's code seems to need, for a
; report only, as data can look like any of it. A key goes on.
unknown:
	ld	a,(yes)
	or	a
	ret	nz
	ld	de,m_unk
	ld	c,9
	call	BDOS
	call	scan
	ld	de,m_key
	ld	c,9
	call	BDOS
	ld	c,1		; a key
	jp	BDOS

scan:	ld	hl,PROGRAM+4
	ld	a,(hl)
	cp	T_REM
	ret	nz
	ld	de,(PROGRAM+2)	; the REM's length, the token and NEWLINE in it
	dec	de
	dec	de
	inc	hl
	ld	a,8		; lines at most
	ld	(sc_n),a
sc_1:	ld	a,d
	or	e
	ret	z
	ld	a,(hl)
	ld	bc,m_sin
	cp	0DBh		; IN A,(n)
	jr	z,sc_hit
	ld	bc,m_sout
	cp	0D3h		; OUT (n),A
	jr	z,sc_hit
	ld	bc,m_shalt
	cp	76h
	jr	z,sc_hit
	cp	0EDh
	jr	z,sc_ed
	cp	0CDh		; CALL nn
	jr	z,sc_jp
	cp	0C3h		; JP nn
	jr	nz,sc_2
sc_jp:	push	hl
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	bc,07BDh	; the one entry we keep
	or	a
	sbc	hl,bc
	ld	a,h
	or	l
	add	hl,bc
	ld	c,a
	ld	a,h
	pop	hl
	cp	40h
	jr	nc,sc_2		; RAM
	inc	c
	dec	c
	jr	z,sc_2		; 07BDh
	ld	bc,m_srom
	jr	sc_hit
sc_ed:	push	hl
	inc	hl
	ld	a,(hl)
	pop	hl
	ld	bc,m_si
	cp	47h		; LD I,A
	jr	z,sc_hit
	and	0C7h
	ld	bc,m_sin
	cp	40h		; IN r,(C)
	jr	z,sc_hit
	ld	bc,m_sout
	cp	41h		; OUT (C),r
	jr	nz,sc_2
sc_hit:	push	de
	push	hl
	ld	d,b
	ld	e,c
	ld	c,9
	call	BDOS
	pop	hl
	ld	a,h
	call	hexout
	ld	a,l
	call	hexout
	push	hl
	ld	de,m_crlf
	ld	c,9
	call	BDOS
	pop	hl
	pop	de
	ld	a,(sc_n)
	dec	a
	ld	(sc_n),a
	ret	z
sc_2:	inc	hl
	dec	de
	jp	sc_1

; HL = the CRC-16 (CCITT, from FFFFh) of VERSN to E_LINE
crc:	ld	de,VERSN
	ld	hl,0FFFFh
cr_1:	push	hl
	ld	hl,(E_LINE)
	or	a
	sbc	hl,de
	pop	hl
	ret	z
	ld	a,(de)
	inc	de
	xor	h
	ld	h,a
	ld	b,8
cr_2:	add	hl,hl
	jr	nc,cr_3
	ld	a,h
	xor	10h
	ld	h,a
	ld	a,l
	xor	21h
	ld	l,a
cr_3:	djnz	cr_2
	jr	cr_1

; Finds the screen start from the BIOS cursor, the one 7Fh in video RAM
; after 1Eh and ESC Y. Carry set when there is not exactly one.
findstart:
	ld	b,0		; hits, stops at 2
	ld	hl,VIDLO
fs_1:	ld	a,(hl)
	cp	CURSOR
	call	z,fs_hit
	inc	hl
	ld	a,h
	or	l
	jr	nz,fs_1		; to FFFFh
	di
	ld	a,(VLATCH)
	ld	c,a
	and	0F8h
	or	W_VIDEO
	ld	(VLATCH),a
	ld	hl,WINDOW
fs_2:	ld	a,(hl)
	cp	CURSOR
	call	z,fs_hit
	inc	hl
	ld	a,h
	cp	0F4h		; to F3FFh
	jr	nz,fs_2
	ld	a,c
	ld	(VLATCH),a
	ei
	ld	a,b
	cp	1
	scf
	ret	nz
	or	a
	ret

; HL a CPU address in video RAM: count it and keep its ring address
fs_hit:	ld	a,b
	cp	2
	ret	z
	inc	b
	push	hl
	ld	de,0400h	; FC00h-FFFFh to 000h-3FFh, F000h-F3FFh to 400h-7FFh
	add	hl,de
	ld	a,h
	and	07h
	ld	h,a
	ld	(vstart),hl
	pop	hl
	ret

; DE a ring offset from the screen start: HL its CPU address. Keeps BC, DE
cellptr:
	ld	hl,(vstart)
	add	hl,de
	ld	a,h		; ring 000h-3FFh at FC00h, 400h-7FFh at F000h
	and	07h
	add	a,0Ch
	and	0Fh
	or	0F0h
	ld	h,a
	ret

; Waits for the start of the next vertical blank: the picture, then
; SYSFLG bit 6 off for longer than a line. Returns with interrupts off.
waitvb:	di
	ld	hl,SYSFLG
wv_1:	bit	6,(hl)
	jr	z,wv_1
wv_2:	ld	b,OFFRUN
wv_3:	bit	6,(hl)
	jr	nz,wv_2
	djnz	wv_3
	ret

; waitvb, counting: DE = passes, about 30 T-states each
waitvc:	ld	hl,SYSFLG
	ld	de,0
wc_1:	inc	de
	bit	6,(hl)
	jr	z,wc_1
wc_2:	ld	b,OFFRUN
wc_3:	inc	de
	bit	6,(hl)
	jr	nz,wc_2
	djnz	wc_3
	ret

; Waits for the picture's first line
dwait:	ld	hl,SYSFLG
dw_1:	bit	6,(hl)
	jr	z,dw_1
	ret

; Into 8-line rows. This
; BIOS frame gets R5 = 22, so it is 274 lines with its sync still at line
; 234, and the sync of the first 8-line frame, at line 224, comes 264
; lines on.
linein:	call	waitvb
	ld	a,5
	ld	c,22
	call	crtw
	call	dwait
	ld	hl,crt8
	jr	crtset

; Back to the BIOS's 9-line rows. This 8-line frame gets R4 = 30 and
; R5 = 6, so it is 254 lines with its sync still at line 224, and the
; BIOS frame's sync at line 234 comes 264 lines on.
lineout:
	call	waitvb
	ld	a,4
	ld	c,30
	call	crtw
	ld	a,5
	ld	c,6
	call	crtw
	call	dwait
	ld	hl,crt9

; HL register and value pairs ending in FFh, written. Interrupts back on.
crtset:	ld	a,(hl)
	cp	0FFh
	jr	z,ct_1
	inc	hl
	ld	c,(hl)
	inc	hl
	call	crtw
	jr	crtset
ct_1:	ei
	ret

; R9, R4, R7, R5 for 8-line rows, 33 rows of 8, and the BIOS's
crt8:	db	9,7, 4,32, 7,28, 5,0, 0FFh
crt9:	db	9,8, 4,27, 7,26, 5,12, 0FFh

; CRTC register A = C
crtw:	ld	(CRTREG),a
	ld	a,c
	ld	(CRTBYT),a
	ret

; RST 10h gets the print, every other RST a trap, so a ROM call we do
; not have is seen, not run into garbage
rstin:	ld	hl,8
	ld	b,6
ri_1:	ld	(hl),0C3h	; JP trap
	inc	hl
	ld	(hl),trap&0FFh
	inc	hl
	ld	(hl),trap>>8
	ld	de,6
	add	hl,de
	ld	a,l
	cp	10h
	jr	nz,ri_2
	ld	de,8		; 10h's comes below
	add	hl,de
ri_2:	djnz	ri_1
	ld	a,0C3h
	ld	(10h),a
	ld	hl,print
	ld	(11h),hl
	ld	hl,inport	; RST 8: a patched IN
	ld	(9),hl
	ld	hl,ktable	; Pipepanic reads the ROM's key table at 007Dh,
	ld	de,007Dh	; a byte before Z, E9h, then the keys in this order
	ld	bc,40
	ldir
	ret

; Page zero's RST entries back to nothing
rstout:	ld	hl,8
	ld	de,9
	ld	bc,2Fh
	ld	(hl),0
	ldir
	ret

; An RST we do not have, or a jump to one: quit, showing from where
trap:	pop	hl
	dec	hl
	ld	(trapat),hl
	jp	quit

; Sets the window to A, the rest of VLATCH as saved
setwin:	ld	c,a
	ld	a,(vlsave)
	and	0F0h
	or	c
	ld	(VLATCH),a
	ret

; Takes the tick, saves the fonts' first 512 bytes, writes the ZX81's
; shapes, goes to double width and 8-line rows. Video RAM holds ZX81
; codes as they are: 00h-3Fh from font RAM 1, 80h-BFh from font RAM 2,
; one the shapes and the other inverted, by the color scheme.
vidin:	di
	ld	hl,(TICKVEC)
	ld	(vecsave),hl
	ld	hl,tick
	ld	(TICKVEC),hl
	ld	a,(VLATCH)
	ld	(vlsave),a
	ld	a,W_FONT1
	call	setwin
	ld	hl,WINDOW
	ld	de,font1
	ld	bc,200h
	ldir
	ld	a,(dark)
	or	a
	ld	a,0FFh		; white background: 00h-3Fh inverted
	jr	z,vi_1
	xor	a
vi_1:	call	putfont
	ld	a,W_FONT2
	call	setwin
	ld	hl,WINDOW
	ld	de,font2
	ld	bc,200h
	ldir
	ld	a,(dark)
	or	a
	ld	a,0
	jr	z,vi_2
	cpl
vi_2:	call	putfont
	ld	a,WIDE|W_VIDEO
	call	setwin
	ei
	jp	linein

; The 64 shapes into the window, each byte XOR A
putfont:
	ld	hl,shapes
	ld	de,WINDOW
	ld	bc,200h
	ld	(pf_x),a
pf_1:	ld	a,(pf_x)
	xor	(hl)
	ld	(de),a
	inc	hl
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,pf_1
	ret

; Puts back the rows, the fonts, VLATCH and the tick
vidout:	call	waitvb
	xor	a
	ld	(shown),a
	call	setr2
	call	lineout
	di
	ld	a,W_FONT1
	call	setwin
	ld	hl,font1
	ld	de,WINDOW
	ld	bc,200h
	ldir
	ld	a,W_FONT2
	call	setwin
	ld	hl,font2
	ld	de,WINDOW
	ld	bc,200h
	ldir
	ld	a,(vlsave)
	ld	(VLATCH),a
	ld	hl,(vecsave)
	ld	(TICKVEC),hl
	ei
	ret

; The tick, on its own stack: FRAMES, the keys, every second tick the
; picture. BREAK leaves from here, as the games' loops never return.
tick:	ld	(gamesp),sp
	ld	sp,istack
	push	af
	push	bc
	push	de
	push	hl
	ld	a,(SYSCLR)
	ld	a,(quitting)
	or	a
	jr	nz,tk_2
	ld	a,(ftick)	; 50 frames in 61 ticks
	add	a,FPS
	cp	TPS
	jr	c,tk_1
	sub	TPS
	ld	(ftick),a
	ld	hl,(FRAMES)	; bit 15 stays, bits 0-14 count down
	ld	a,h
	and	80h
	ld	b,a
	dec	hl
	ld	a,h
	and	7Fh
	or	b
	ld	h,a
	ld	(FRAMES),hl
	jr	tk_1b
tk_1:	ld	(ftick),a
tk_1b:	call	keyscan
	ld	a,(KEYS+40h)	; row 6: BREAK at bit 2
	bit	2,a
	jp	nz,quit
	ld	hl,tphase	; a copy and the wait for the blank take more
	inc	(hl)		; than a tick, so every second one
	bit	0,(hl)
	jr	z,tk_2b
	call	copyd
	call	waitvc
	call	flip
	ld	a,e		; the wait, 32 passes of about 30 T a count
	rlca			; DE / 32, DE under 4000
	rlca
	rlca
	and	7
	ld	e,a
	ld	a,d
	add	a,a
	add	a,a
	add	a,a
	or	e
	ld	e,a
	ld	a,BRAKE
	sub	e
	jr	nc,tk_b
	xor	a
tk_b:	ld	(brake),a
	jr	tk_3
tk_2b:	ld	a,(fast)	; ZX81 speed: the game gets its share and no
	or	a		; more, held in the tick after a copy
	jr	nz,tk_3
	ld	a,(brake)
	or	a
	jr	z,tk_3
	ld	b,a		; 1024 T-states a count
tk_h1:	push	bc
	ld	b,78		; 13 T a pass
tk_h2:	djnz	tk_h2
	pop	bc
	djnz	tk_h1
tk_3:
tk_2:	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp,(gamesp)
	ei
	reti

; The MAX-80's rows into the ZX81's half-rows, and those into LAST_K: the
; low byte the half-rows with a key down, each one's select line low, the
; high byte the columns held, active low, and SHIFT in bit 0.
keyscan:
	ld	a,hrows&0FFh
	ld	(ks_p),a
	ld	a,hrows>>8
	ld	(ks_p+1),a
	ld	hl,kmap
	ld	de,0FFFFh	; E the half-rows, D the columns
	ld	bc,0FE00h	; B the select line, C this half-row's columns
ks_1:	ld	a,5
	ld	(ks_n),a
	ld	c,0
ks_2:	push	de
	ld	e,(hl)		; the MAX-80's row address, low byte
	inc	hl
	ld	d,KEYS>>8
	ld	a,(de)
	pop	de
	and	(hl)
	inc	hl
	add	a,0FFh		; carry if held
	rr	c
	ld	a,(ks_n)
	dec	a
	ld	(ks_n),a
	jr	nz,ks_2
	ld	a,c		; D7-D3 of C are the five columns, last at D7
	rrca
	rrca
	rrca
	and	1Fh
	ld	c,a
	push	hl		; kept for IN: a held key 0
	ld	hl,(ks_p)
	cpl
	and	1Fh
	ld	(hl),a
	inc	hl
	ld	(ks_p),hl
	pop	hl
	ld	a,b
	cp	0FEh		; SHIFT is D0 of the first half-row
	jr	nz,ks_3
	ld	a,c
	and	1
	ld	(ks_sh),a
	ld	a,c
	and	1Eh
	ld	c,a
ks_3:	ld	a,c
	or	a
	jr	z,ks_4		; no key on this half-row
	ld	a,e
	and	b
	ld	e,a
	ld	a,c
	cpl
	and	d
	ld	d,a
ks_4:	rlc	b
	ld	a,b
	cp	0FEh
	jr	nz,ks_1
	ld	a,d		; three top bits stay set, then SHIFT at bit 0
	or	0E0h
	add	a,a
	ld	d,a
	ld	a,(ks_sh)
	xor	1
	or	d
	ld	d,a
	ld	(LAST_K),de
	ret

	assert	$ <= 07BDh	; the ROM's decode has its entry at its address
	block	07BDh-$,0
	jp	decode

; 07BDh: BC a key scan as in LAST_K. Carry and HL at the key's character
; in ktable, or no carry for no key or two half-rows
decode:	push	de
	ld	a,b		; the columns, active low, past SHIFT
	cpl
	rrca
	and	1Fh
	ld	e,0		; E the column
	jr	z,de_x
de_1:	srl	a
	jr	c,de_2
	inc	e
	jr	de_1
de_2:	or	a
	jr	nz,de_x		; two columns
	ld	a,c		; the half-row, active low
	cpl
	or	a
	jr	z,de_x
	ld	d,0		; D the half-row
de_3:	srl	a
	jr	c,de_4
	inc	d
	jr	de_3
de_4:	or	a
	jr	nz,de_x		; two half-rows
	ld	a,d		; x 5 + the column
	add	a,a
	add	a,a
	add	a,d
	add	a,e
	ld	e,a
	ld	d,0
	ld	hl,ktable
	add	hl,de
	pop	de
	scf
	ret
de_x:	pop	de
	or	a
	ret

; The characters of the keyboard, half-row by half-row as kmap
ktable:	db	0E9h,3Fh,3Dh,28h,3Bh		; SHIFT Z X C V
	db	26h,38h,29h,2Bh,2Ch		; A S D F G
	db	36h,3Ch,2Ah,37h,39h		; Q W E R T
	db	1Dh,1Eh,1Fh,20h,21h		; 1 2 3 4 5
	db	1Ch,25h,24h,23h,22h		; 0 9 8 7 6
	db	35h,34h,2Eh,3Ah,3Eh		; P O I U Y
	db	76h,31h,30h,2Fh,2Dh		; NEWLINE L K J H
	db	0,1Bh,32h,33h,27h		; SPACE . M N B

; RST 8, for IN A,(C) with C = FEh: A = the half-rows selected low in B,
; a held key 0, the top three bits set. Keeps the rest, flags aside.
inport:	push	hl
	push	bc
	ld	hl,hrows
	ld	c,8
	ld	a,1Fh		; the columns, AND of those selected
	ld	(in_a),a
in_1:	rrc	b
	jr	c,in_2
	ld	a,(in_a)
	and	(hl)
	ld	(in_a),a
in_2:	inc	hl
	dec	c
	jr	nz,in_1
	ld	a,(in_a)
	or	0E0h
	pop	bc
	pop	hl
	ret

; RST 10h: the character in A at DF_CC, moving on. Keeps every register,
; A too: Tetris1k prints a row from one LD A. NEWLINE goes to the start of the next line. At a line's NEWLINE
; a collapsed line gets room: everything up to E_LINE moves up a byte and
; the variables above it with it (the manual's display file).
print:	push	af
	push	hl
	push	de
	push	bc
	ld	hl,(DF_CC)
	cp	NEWLINE
	jr	z,pr_nl
	ld	c,a
	ld	a,(S_POSN)	; past the 32nd: the next line first
	cp	1
	jr	nz,pr_1
	ld	a,NEWLINE
	call	pr_line
	ld	hl,(DF_CC)
pr_1:	ld	a,(hl)
	cp	NEWLINE
	call	z,pr_room
	ld	(hl),c
	inc	hl
	ld	(DF_CC),hl
	ld	hl,S_POSN
	dec	(hl)
	jr	pr_x
pr_nl:	call	pr_line
pr_x:	pop	bc
	pop	de
	pop	hl
	pop	af
	ret

; DF_CC to the start of the next line
pr_line:
	ld	hl,(DF_CC)
pl_1:	ld	a,(hl)
	inc	hl
	cp	NEWLINE
	jr	nz,pl_1
	ld	(DF_CC),hl
	ld	hl,S_POSN
	ld	(hl),33
	inc	hl
	dec	(hl)
	ret

; HL = DF_CC: moves everything from there to E_LINE up a byte. Keeps HL, C
pr_room:
	push	hl
	push	bc
	ex	de,hl		; DE = DF_CC
	ld	hl,(E_LINE)
	push	hl
	or	a
	sbc	hl,de
	inc	hl
	ld	b,h
	ld	c,l		; the bytes
	pop	hl
	ld	d,h
	ld	e,l
	inc	de
	lddr
	ld	hl,VARS		; VARS to STKEND, those above us
	ld	b,(STKEND-VARS)/2+1
pm_1:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ex	de,hl		; HL the variable, DE its place + 1
	inc	hl
	ex	de,hl
	ld	(hl),d
	dec	hl
	ld	(hl),e
	inc	hl
	inc	hl
	djnz	pm_1
	pop	bc
	pop	hl
	ret

; ZX81 key to MAX-80 key, half-row by half-row, D0 first: the low byte of
; the row's address and the key's bit
kmap:	db	80h,01h, 08h,04h, 08h,01h, 01h,08h, 04h,40h	; SHIFT Z X C V
	db	01h,02h, 04h,08h, 01h,10h, 01h,40h, 01h,80h	; A S D F G
	db	04h,02h, 04h,80h, 01h,20h, 04h,04h, 04h,10h	; Q W E R T
	db	10h,02h, 10h,04h, 10h,08h, 10h,10h, 10h,20h	; 1 2 3 4 5
	db	10h,01h, 20h,02h, 20h,01h, 10h,80h, 10h,40h	; 0 9 8 7 6
	db	04h,01h, 02h,80h, 02h,02h, 04h,20h, 08h,02h	; P O I U Y
	db	40h,01h, 02h,10h, 02h,08h, 02h,04h, 02h,01h	; NEWLINE L K J H
	db	40h,80h, 20h,40h, 02h,20h, 02h,40h, 01h,04h	; SPACE . M N B

; Shows the page just written. Call in the vertical blank.
flip:	ld	a,(shown)
	xor	1
	ld	(shown),a
setr2:	ld	a,2
	ld	(CRTREG),a
	ld	a,(shown)
	add	a,R2EVEN
	ld	(CRTBYT),a
	ret

; The background in every character of the 24 rows, both pages
clearall:
	ld	de,0
	ld	bc,ROWS*COLS
ca_1:	call	cellptr
	ld	(hl),0
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,ca_1
	ret

; D_FILE into the hidden page, line by line up to each NEWLINE. A short
; line is filled out with spaces on the screen, never in the file. A row
; that crosses from one 1K of video RAM to the other goes cell by cell.
copyd:	ld	a,(shown)
	xor	1
	add	a,2*XCOL
	ld	e,a
	ld	d,0
	ld	hl,(D_FILE)
	inc	hl
	ld	b,ROWS
cd_1:	push	bc
	push	de
	push	hl
	call	cellptr
	ex	de,hl		; DE = the cell, the source back in HL
	pop	hl
	ld	a,d
	and	3
	cp	3
	jr	nz,cd_2
	ld	a,e
	cp	0C0h
	jr	nc,cd_6
cd_2:	ld	b,32
cd_3:	ld	a,(hl)
	cp	NEWLINE
	jr	z,cd_5
	inc	hl
	bit	6,a		; 40h-7Fh and C0h-FFh show as a space
	jr	z,cd_4
	xor	a
cd_4:	ld	(de),a
	inc	de
	inc	de
	djnz	cd_3
	jr	cd_9
cd_5:	xor	a
	ld	(de),a
	inc	de
	inc	de
	djnz	cd_5
	jr	cd_9
cd_6:	pop	de		; the slow row: DE the offset again
	push	de
	ld	b,32
cd_7:	ld	a,(hl)
	cp	NEWLINE
	jr	z,cd_8
	inc	hl
	bit	6,a
	jr	z,cd_8b
cd_8:	xor	a
cd_8b:	ld	c,a
	push	hl
	call	cellptr
	ld	(hl),c
	pop	hl
	inc	de
	inc	de
	djnz	cd_7
cd_9:	inc	hl		; past the NEWLINE
	pop	de
	pop	bc
	ex	de,hl
	push	bc
	ld	bc,COLS
	add	hl,bc
	pop	bc
	ex	de,hl
	djnz	cd_1
	ret

ext_p:	db	"P  "
romname: db	0,"ZX81    ROM"
m_usage: db	"ZX81 NAME [/D] [/F] [/Y] runs NAME.P",13,10,'$'
m_norom: db	"No ZX81.ROM",13,10,'$'
m_badrom: db	"ZX81.ROM is not 8192 bytes",13,10,'$'
m_nop:	db	"No such .P file, or too big",13,10,'$'
m_badp:	db	"Not a good .P file",13,10,'$'
m_nousr: db	"No USR to start, this .P needs BASIC",13,10,'$'
m_nostart: db	"Cannot find the screen start",13,10,'$'
m_home:	db	1Ah,1Eh,1Bh,'Y','$'
m_cls:	db	1Ah,'$'
m_trap:	db	"ROM call not there, from $"
m_unk:	db	"Not a game this knows. It may not run",13,10,'$'
m_key:	db	"Any key goes on$"
m_sin:	db	"  IN at $"
m_sout:	db	"  OUT at $"
m_shalt: db	"  HALT at $"
m_si:	db	"  LD I,A at $"
m_srom:	db	"  ROM call at $"
m_crlf:	db	13,10,'$'

; Memory with nothing in the file, above the decode entry
ccpsp	equ	1000h
gostart	equ	ccpsp+2		; the game's start
vstart	equ	gostart+2		; the screen start's place in video RAM
vlsave	equ	vstart+2
vecsave	equ	vlsave+1
dark	equ	vecsave+2		; not 0: light on dark
fast	equ	dark+1		; not 0: full speed
yes	equ	fast+1		; not 0: no warning for an unknown .P
sc_n	equ	yes+1		; the scan's lines left
trapat	equ	sc_n+1		; where a trap came from
pf_x	equ	trapat+2
rf_to	equ	pf_x+1
rf_lim	equ	rf_to+2
rf_fcb	equ	rf_lim+2
fcb	equ	rf_fcb+2
romfcb	equ	fcb+36
shapes	equ	romfcb+36
font1	equ	shapes+200h
font2	equ	font1+200h
	; 100h for the game's and the shell's calls
stack	equ	font2+200h+100h
istack	equ	stack+80h	; the tick's
gamesp	equ	istack
ftick	equ	gamesp+2	; adds 50 a tick, 61 is a frame
tphase	equ	ftick+1
shown	equ	tphase+1	; 0 the even page, 1 the odd
ks_n	equ	shown+1
ks_sh	equ	ks_n+1
quitting equ	ks_sh+1
brake	equ	quitting+1	; the hold, 1024 T-states a count
ks_p	equ	brake+1		; where keyscan keeps the next half-row
hrows	equ	ks_p+2		; the 8 half-rows, a held key 0
in_a	equ	hrows+8
memend	equ	in_a+1
