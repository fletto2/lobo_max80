; The machine's setup, shared with the monitor: channel A, the
; CRTC, the fonts and how much RAM there is.

sioinit:
	ld	a,0Eh			; 9600
	ld	(BAUDA),a
	ld	hl,siotab
	ld	b,siotabn
sio1:	ld	a,(hl)
	ld	(SIOCA),a
	inc	hl
	djnz	sio1
	ret

; Lobo's channel A setup with one stop bit and no auto enables, so a
; cable with nothing on CTS and DCD still works
siotab:	db	18h,18h,14h,44h,13h,0C1h,15h,0EAh,11h,0
siotabn	equ	$-siotab

; All 16 CRTC registers, Lobo's 80 x 24 table, start address 0
crtinit:
	ld	hl,crttab
	ld	b,0
crt1:	ld	a,b
	ld	(CRTREG),a
	ld	a,(hl)
	ld	(CRTBYT),a
	inc	hl
	inc	b
	ld	a,b
	cp	16
	jr	nz,crt1
	ld	a,VL_VIDEO
	jp	setvl

crttab:	db	119,80,97,6,27,12,24,26,0,8,0,0,0,0,0,0

setvl:	ld	(vlnow),a
	ld	(VLATCH),a
	ret

; The font into both font RAMs, and the test glyphs over 80h-84h
fontload:
	call	blkmov			; F000h addresses
	ret	nz
	ld	a,VL_ROM+4		; window on font RAM 1
	ld	(VLATCH),a
	ld	hl,FONT
	ld	de,BLK
	ld	bc,400h
	ldir
	ld	a,VL_ROM+6		; font RAM 2
	ld	(VLATCH),a
	ld	de,BLK
	ld	bc,400h
	ldir
	ld	hl,gtab
	ld	de,BLK
	ld	b,NGLYPH
fl1:	push	bc
	push	de
	ld	bc,8			; rows 0-7
	ldir
	ex	(sp),hl			; HL = this glyph's rows 0-7
	push	hl
	ld	bc,200h			; rows 8-15
	add	hl,bc
	ex	de,hl
	pop	bc			; BC = rows 0-7 of this glyph
	pop	hl			; HL = the table again
	push	bc
	ld	bc,8
	ldir
	pop	de
	ex	de,hl
	ld	bc,8			; the next glyph's rows 0-7
	add	hl,bc
	ex	de,hl
	pop	bc
	djnz	fl1
	ld	a,(vlnow)
	ld	(VLATCH),a
	ret

; Test glyphs, 16 rows each. The cell shows rows 0-8.
G_SOLID	equ	80h
G_GRID	equ	81h
G_CHECK	equ	82h
G_VERT	equ	83h
G_HORZ	equ	84h
gtab:	block	16,0FFh
	db	0FFh,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h
	db	0AAh,55h,0AAh,55h,0AAh,55h,0AAh,55h,0AAh,55h,0AAh,55h,0AAh,55h,0AAh,55h
	block	16,0AAh
	db	0FFh,0,0FFh,0,0FFh,0,0FFh,0,0FFh,0,0FFh,0,0FFh,0,0FFh,0
NGLYPH	equ	($-gtab)/16

; Bank B is there if B1 keeps 55h and AAh at two addresses at once,
; then the two swapped. One byte read straight after its write, as the
; boot ROM checks, can pass on a floating bus that still holds it.
findb:	ld	a,80h			; B1 high
	ld	(B_PIODA),a
	ld	hl,8000h
	ld	de,55AAh
	call	fbpair
	jr	nz,fb1
	ld	de,0AA55h
	call	fbpair
	jr	nz,fb1
	ld	a,4
	jr	fb2
fb1:	ld	a,2
fb2:	ld	(nchunk),a
	ld	a,40h
	ld	(B_PIODA),a
	ret

; D to HL, E to HL+1, then both read back. Z if both kept.
fbpair:	ld	(hl),d
	inc	hl
	ld	(hl),e
	dec	hl
	ld	a,(hl)
	cp	d
	ret	nz
	inc	hl
	ld	a,(hl)
	dec	hl
	cp	e
	ret
