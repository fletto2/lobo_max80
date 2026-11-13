; Test program: the ROM's KEYBOARD at 02BBh, then DECODE at 07BDh, for
; ZX81.COM's tests. With a key down: its scan in hex on line 0, the
; character DECODE finds on line 1, DECODE's index in hex on line 2.
; Digits are codes 26h on.

D_FILE	equ	400Ch

	org	4082h

loop:	call	02BBh
	ld	a,h
	and	l
	inc	a		; FFFFh: no key
	jr	z,loop
	ld	a,l		; SHIFT alone: no half-row
	inc	a
	jr	z,loop
	push	hl
	ex	de,hl
	ld	hl,(D_FILE)
	inc	hl
	call	hex4
	pop	bc
	call	07BDh
	jr	nc,loop
	push	af
	ld	a,(hl)
	ld	hl,(D_FILE)
	ld	de,34		; line 1
	add	hl,de
	ld	(hl),a
	pop	af
	ld	de,33		; line 2
	add	hl,de
	call	hex2
	jr	loop

hex4:	ld	a,d		; HL to, DE the word
	call	hex2
	ld	a,e
hex2:	push	af
	rrca
	rrca
	rrca
	rrca
	call	hex1
	pop	af
hex1:	and	0Fh
	add	a,26h
	ld	(hl),a
	inc	hl
	ret
