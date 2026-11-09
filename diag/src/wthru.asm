; Write-through test. The TRM (TS-27/28) says writes to some of
; the I/O block also go into bank A RAM, whatever the PIO selects. It
; does not say which registers do it, or which chunk takes the write
; with the block at F000h, and the test shows which. So each case seeds the cells at each
; register's offset, and at the offset plus 7000h, in all the chunks,
; writes the registers once, and shows which cells changed.
;
; The program stays in A1 in the low half, so a case is the block's place
; and the chunk in the high half. VLATCH is left out, since moving the
; block writes it, and the PIO, since a write there changes the map.
; Nothing goes to the console from the seeding to the reading, since
; the screen copy to SIODA is one of the writes looked for. The A1 cells
; are kept and put back, some are in the screen copy and the variables.

WTN	equ	13			; registers
WTSZ	equ	3			; a row of wtab

; The offset in the block, and what is written: what is there already
; for the baud rates, 9600, and 0 to the printer and the serial port
wtab:	dw	06FFh
	db	5Ah
	dw	07CFh
	db	5Ah
	dw	07D0h
	db	0Eh
	dw	07D4h
	db	0Eh
	dw	07D8h
	db	40h
	dw	07E0h
	db	5Ah
	dw	07E4h
	db	0
	dw	07E8h
	db	0
	dw	07EDh
	db	5Ah
	dw	07F0h
	db	5Ah
	dw	07F8h
	db	5Ah
	dw	0800h
	db	5Ah
	dw	0BFFh
	db	5Ah

wnames:	db	"RAM400 6FF",0
	db	"SLORAM 7CF",0
	db	"BAUDA  7D0",0
	db	"BAUDB  7D4",0
	db	"MLATCH 7D8",0
	db	"CRTREG 7E0",0
	db	"SIODA  7E4",0
	db	"PDATA  7E8",0
	db	"FTRACK 7ED",0
	db	"UDATA  7F0",0
	db	"BEEP   7F8",0
	db	"MATRIX 800",0
	db	"RAM900 BFF",0

wres:	ds	WTN*6			; the cells changed: WTN for each case
wbuf:	ds	WTN*2			; the A1 cells as they were

wttest:	ld	a,0Ch
	call	putc
	call	print
	db	"WRITE-THROUGH TEST",0
	ld	hl,wres
	ld	de,wres+1
	ld	bc,WTN*6-1
	ld	(hl),0
	ldir
	ld	iy,wres
	ld	b,0			; block at 0000h, then F000h
	call	wtall
	ld	iy,wres+WTN*3
	ld	b,1
	call	wtall
	call	wtrep
	call	print
	db	TH,"Any key for the menu.",TK,0
	call	waitkey
	jp	drawmenu

; Block place B: a case for each chunk other than A1, its results from IY
wtall:	ld	c,1
wa1:	ld	a,(nchunk)
	cp	c
	ret	z
	push	bc
	push	iy
	call	wcase
	pop	iy
	pop	bc
	ld	de,WTN
	add	iy,de
	inc	c
	jr	wa1

; Chunk C high, the block at 0000h if B is 0, else at F000h. Comes in and
; goes out with the block at F000h and A2 high.
wcase:	call	wsa1
	call	blk0
	push	bc
	ld	c,1
wc1:	ld	a,(nchunk)
	cp	c
	jr	z,wc2
	call	piohi
	call	wsx
	inc	c
	jr	wc1
wc2:	pop	bc
	call	piohi
	ld	a,b
	or	a
	ld	h,0
	jr	z,wc3
	ld	a,(vlnow)		; to F000h, the PIO left as it is
	ld	(B_VLATCH),a
	ld	h,high BLK
wc3:	call	wwrite
	ld	a,b
	or	a
	call	nz,blk0
	push	bc
	ld	c,1
wc4:	ld	a,(nchunk)
	cp	c
	jr	z,wc5
	call	piohi
	call	wrx
	inc	c
	jr	wc4
wc5:	pop	bc
	call	blkf
	jp	wra1

; Each register written, the block's high byte in H
wwrite:	push	bc
	ld	ix,wtab
	ld	b,WTN
ww1:	ld	e,h
	ld	l,(ix+0)
	ld	a,(ix+1)
	or	h
	ld	h,a
	ld	a,(ix+2)
	ld	(hl),a
	ld	h,e
	ld	de,WTSZ
	add	ix,de
	djnz	ww1
	pop	bc
	ret

; The A1 cells kept and seeded, each the complement of what is written
wsa1:	push	bc
	ld	ix,wtab
	ld	de,wbuf
	ld	b,WTN
ws1:	ld	l,(ix+0)
	ld	h,(ix+1)
	ld	a,(hl)
	ld	(de),a
	inc	de
	ld	a,(ix+2)
	cpl
	ld	(hl),a
	ld	a,h
	add	a,70h
	ld	h,a
	ld	a,(hl)
	ld	(de),a
	inc	de
	ld	a,(ix+2)
	cpl
	ld	(hl),a
	push	de
	ld	de,WTSZ
	add	ix,de
	pop	de
	djnz	ws1
	pop	bc
	ret

; The cells of the chunk in the high half seeded, block at 0000h
wsx:	push	bc
	ld	ix,wtab
	ld	de,WTSZ
	ld	b,WTN
wx1:	ld	l,(ix+0)
	ld	a,(ix+1)
	or	80h
	ld	h,a
	ld	a,(ix+2)
	cpl
	ld	(hl),a
	ld	a,h
	add	a,70h
	ld	h,a
	ld	a,(ix+2)
	cpl
	ld	(hl),a
	add	ix,de
	djnz	wx1
	pop	bc
	ret

; The cells of chunk C, in the high half, read into the results at IY:
; 20h and 10h for A2, 08h and 04h for B1, 02h and 01h for B2
wrx:	push	bc
	push	iy
	ld	a,c
	ld	e,20h
wr1:	dec	a
	jr	z,wr2
	srl	e
	srl	e
	jr	wr1
wr2:	ld	d,e
	srl	d			; E the offset, D the offset plus 7000h
	ld	ix,wtab
	ld	b,WTN
wr3:	ld	l,(ix+0)
	ld	a,(ix+1)
	or	80h
	ld	h,a
	ld	a,(ix+2)
	cpl
	cp	(hl)
	jr	z,wr4
	ld	a,(iy+0)
	or	e
	ld	(iy+0),a
wr4:	ld	a,h
	add	a,70h
	ld	h,a
	ld	a,(ix+2)
	cpl
	cp	(hl)
	jr	z,wr5
	ld	a,(iy+0)
	or	d
	ld	(iy+0),a
wr5:	inc	iy
	push	de
	ld	de,WTSZ
	add	ix,de
	pop	de
	djnz	wr3
	pop	iy
	pop	bc
	ret

; The A1 cells read into the results at IY, 80h and 40h, and put back
wra1:	push	bc
	push	iy
	ld	ix,wtab
	ld	de,wbuf
	ld	b,WTN
wb1:	ld	l,(ix+0)
	ld	h,(ix+1)
	ld	a,(ix+2)
	cpl
	cp	(hl)
	jr	z,wb2
	ld	a,(iy+0)
	or	80h
	ld	(iy+0),a
wb2:	ld	a,(de)
	ld	(hl),a
	inc	de
	ld	a,h
	add	a,70h
	ld	h,a
	ld	a,(ix+2)
	cpl
	cp	(hl)
	jr	z,wb3
	ld	a,(iy+0)
	or	40h
	ld	(iy+0),a
wb3:	ld	a,(de)
	ld	(hl),a
	inc	de
	inc	iy
	push	de
	ld	de,WTSZ
	add	ix,de
	pop	de
	djnz	wb1
	pop	iy
	pop	bc
	ret

; The report: a row a register, a column a case, -- for a chunk not there
wtrep:	ld	hl,2
	call	at
	call	print
	db	TH,"            Block at 0000h     Block at F000h",0Dh,0Ah
	db	"Register    High half:         High half:",0Dh,0Ah
	db	"            A2   B1   B2        A2   B1   B2",TK,0Dh,0Ah,0
	ld	hl,wnames
	ld	de,wres
	ld	b,WTN
wp1:	push	bc
	call	puts
	push	hl
	push	de
	ld	c,0			; the column
wp2:	ld	a,c
	cp	3
	jr	nz,wp3
	call	print
	db	"    ",0
wp3:	call	print
	db	"  ",0
	ld	a,c
	cp	3
	jr	c,wp4
	sub	3
wp4:	inc	a
	ld	hl,nchunk
	cp	(hl)
	jr	c,wp5
	call	print
	db	"-- ",0
	jr	wp6
wp5:	ld	a,(de)
	call	phex8
wp6:	ld	hl,WTN
	add	hl,de
	ex	de,hl
	inc	c
	ld	a,c
	cp	6
	jr	nz,wp2
	call	print
	db	0Dh,0Ah,0
	pop	de
	inc	de
	pop	hl
	pop	bc
	djnz	wp1
	call	print
	db	TH,"Which RAM took the write, added up: 80 A1, 20 A2, 08 B1, 02 B2 at the",0Dh,0Ah
	db	"offset, 40 A1, 10 A2, 04 B1, 01 B2 at the offset plus 7000h. A1 is low.",TK,0Dh,0Ah,0
	ret
