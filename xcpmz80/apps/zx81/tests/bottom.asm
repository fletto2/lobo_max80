; Test program: RST 10h past the last line, for ZX81.COM's tests. 30
; NEWLINEs, then XY: on a ZX81 report 5, here the last line keeps them,
; and the byte at VARS must still be 80h, or RST 28h, a trap.

VARS	equ	4010h

	org	4082h

	ld	b,30
nl:	ld	a,76h
	rst	10h
	djnz	nl
	ld	a,3Dh		; X
	rst	10h
	ld	a,3Eh		; Y
	rst	10h
	ld	hl,(VARS)
	ld	a,(hl)
	cp	80h
	jr	z,$
	rst	28h
