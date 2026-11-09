; Test program: counts passes of a 100 T-state loop in a word shown on
; line 0 as hex, for ZX81.COM's speed check. The count goes up
; 256 a tick of low byte, so it is shown in the high byte and the next.

D_FILE	equ	400Ch

	org	4082h

	ld	bc,0		; the passes
	ld	de,0		; and above them
loop:	inc	bc		; 6
	ld	a,b		; 4
	or	c		; 4
	jr	nz,l2		; 12
	inc	de
l2:	ld	a,0		; 7
	ld	a,0		; 7
	ld	a,0		; 7
	ld	hl,(D_FILE)	; 16
	inc	hl		; 6
	ld	a,b		; 4
	rrca			; 4
	rrca			; 4
	rrca			; 4
	rrca			; 4
	and	0Fh		; 7
	add	a,26h		; 7
	ld	(hl),a		; 7
	inc	hl		; 6
	ld	a,b		; 4
	and	0Fh		; 7
	add	a,26h		; 7
	ld	(hl),a		; 7
	inc	hl		; 6
	ld	a,c		; 4
	rrca			; 4
	rrca			; 4
	rrca			; 4
	rrca			; 4
	and	0Fh		; 7
	add	a,26h		; 7
	ld	(hl),a		; 7
	inc	hl		; 6
	ld	a,c		; 4
	and	0Fh		; 7
	add	a,26h		; 7
	ld	(hl),a		; 7
	jp	loop		; 10
