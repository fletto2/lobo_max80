; Test program: prints into a collapsed display file with RST 10h, for
; ZX81.COM's tests. ABC, then XY on the next line, then OK written
; straight at D_FILE + 7 + 3, which only holds if every move was counted,
; with the 07BDh decode of the key K on the way.

D_FILE	equ	400Ch

	org	4082h

	ld	a,26h		; A
	rst	10h
	inc	a		; A kept
	rst	10h
	inc	a
	rst	10h
	ld	a,76h
	rst	10h
	ld	a,3Dh		; X
	rst	10h
	ld	a,3Eh		; Y
	rst	10h
	ld	a,76h
	rst	10h
	ld	bc,0F7BFh	; K
	call	07BDh
	jr	nc,$
	ld	a,(hl)
	cp	30h
	jr	nz,$
	ld	a,34h		; O
	rst	10h
	ld	a,30h		; K
	rst	10h
	jr	$
