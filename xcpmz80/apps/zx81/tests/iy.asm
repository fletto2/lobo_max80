; Test program: IY 4000h, as the ROM's USR leaves it, for ZX81.COM's
; tests. A trap from 408Eh if it is, 408Fh if not

	org	4082h

	push	iy
	pop	hl
	ld	a,h
	cp	40h
	jr	nz,bad
	ld	a,l
	or	a
	jr	nz,bad
	rst	28h
bad:	rst	30h
