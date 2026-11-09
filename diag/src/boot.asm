; Diagnostic boot sector. Track 0 sector 0, loaded by the boot ROM
; to 0400h and run there with the I/O block at 0000h and the PIO at 40h
; (A1 low, A2 high), IY = MLATCH and AF' as the ROM's READ wants them.
;
; It loads the program to 1000h in A1 with the ROM's READ, one sector a
; call as Lobo's boot sectors do, moves the I/O block to F000h and jumps
; in. tools/mkdisk.py sets the sectors a track at offset 2.

	org	0400h
boot:	jr	bstart
bspt:	db	17			; sectors a track
	assert	bspt == 0402h

bstart:	di
	ld	hl,1000h		; load address
	ld	de,0			; track
	ld	b,1			; sector
	ld	c,PROGSEC		; sectors left
bload:	push	bc
	push	de
	ld	c,b			; first and last sector the same
	xor	a			; head 0
	call	ROMREAD			; HL comes back past the sector
	pop	de
	pop	bc
	inc	b
	ld	a,(bspt)
	cp	b
	jr	nz,bnext
	ld	b,0			; next track, from sector 0
	inc	de
bnext:	dec	c
	jr	nz,bload

	ld	a,VL_ROM		; the I/O block to F000h
	ld	(B_VLATCH),a
	ld	(VLATCH),a		; and its RAM copy at the new place
	jp	main

	assert	$ <= 0600h
	block	0600h-$,0
