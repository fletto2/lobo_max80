; Test program: what ZX81.COM's scan reports, for its tests. Not
; run, or only as far as its first line.

	org	4082h

	in	a,(0FEh)
	out	(0FFh),a
	halt
	ld	i,a
	in	a,(c)
	call	0100h
	call	07BDh
	ret
