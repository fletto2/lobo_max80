; Test program: the ROM's CLS at 0A2Ah, for ZX81.COM's tests. Prints
; ZZ, five NEWLINEs and QQ, clears, then prints OK, two NEWLINEs and
; AB. The byte at VARS must still be the 80h that ends the variables,
; or RST 28h, a trap. With BIG, RAMTOP 8000h first: a 16K machine.

D_FILE	equ	400Ch
RAMTOP	equ	4004h
VARS	equ	4010h

	org	4082h

	ifdef	BIG
	ld	hl,8000h
	ld	(RAMTOP),hl
	endif
	ld	a,3Fh		; Z
	rst	10h
	rst	10h
	ld	b,5
nl:	ld	a,76h
	rst	10h
	djnz	nl
	ld	a,36h		; Q
	rst	10h
	rst	10h
	call	0A2Ah
	ld	a,34h		; O
	rst	10h
	ld	a,30h		; K
	rst	10h
	ld	a,76h
	rst	10h
	rst	10h
	ld	a,26h		; A
	rst	10h
	ld	a,27h		; B
	rst	10h
	ld	hl,(VARS)
	ld	a,(hl)
	cp	80h
	jr	z,$
	rst	28h
