; Test program: shows FRAMES on line 0 and the last LAST_K with a key
; down on line 1, in hex, for ZX81.COM's tests. Digits are codes
; 26h on, which the emulator's -T prints as & ' ( and so on.

D_FILE	equ	400Ch
LAST_K	equ	4025h
FRAMES	equ	4034h

	org	4082h

loop:	ld	hl,(D_FILE)
	inc	hl
	ld	de,(FRAMES)
	call	hex4
	ld	hl,(D_FILE)
	ld	de,34		; line 1
	add	hl,de
	ex	de,hl
	ld	hl,(LAST_K)
	ld	a,h
	and	l
	inc	a		; FFFFh: no key, keep what is shown
	jr	nz,lk
	ld	a,h		; SHIFT alone is not a key here either
	jr	loop
lk:	ex	de,hl
	call	hex4x
	jr	loop

hex4x:	ld	a,d		; HL to, DE the word
	jr	hx
hex4:	ld	a,d
hx:	call	hex2
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
