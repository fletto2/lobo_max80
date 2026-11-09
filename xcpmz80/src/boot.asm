; xcpmz80 boot sector. Sector 0 of track 0, loaded by the boot ROM
; to 0400h and run there, with the I/O block at 0000h, the PIO at 40h (A1
; low, A2 high), IY = MLATCH and AF' set by the ROM for its READ.
;
; It does what Lobo's CP/M 3 boot sector does: copy itself into A2, map
; A2 low and A1 high (PIO 10h), load the system with the ROM's READ,
; then move the I/O block to F000h. Our system image is loaded to A2 at
; 1000h. The kernel stays there, and the common part and the font are
; copied out of it. The same sector boots a floppy or a SASI disk (DIP
; setting 7): the ROM's AF' says which.
;
; The sector is also a FAT12 boot sector, so the whole disk is a FAT
; volume a PC can read. The BPB is the one place the format is defined.

	org	0400h
boot:	jr	bstart
	nop
	db	"XCPMZ80 "		; OEM name
	FLOPPYBPB			; bpb.inc
	assert	$-boot == 3Eh

bstart:	di
	ld	hl,0400h		; copy this sector into A2, and the
	ld	de,8400h		; RAM copy of MLATCH at 07D8h with it:
	ld	bc,3E0h			; the ROM's READ reads the latch back
	ldir				; from there. Not 07E0h up: reading
					; the I/O there takes an SIO byte, the
					; tick flag and a SASI handshake

	ld	a,BANK_SYS		; ...and map A2 low: we run on in the copy
	ld	(B_PIODA),a

	ex	af,af'			; the ROM's flag: Z floppy, NZ a hard
	push	af			; disk (A = 0 for SASI)
	ex	af,af'
	pop	af
	jr	z,bflop
	; SASI: blocks 1 to SYSSEC, one a call: block = A:DE + B
	ld	hl,1000h
	ld	b,1
bsas:	push	bc
	ld	c,b
	xor	a
	ld	d,a
	ld	e,a
	call	ROMREAD
	pop	bc
	inc	b
	ld	a,b
	cp	SYSSEC+1
	jr	c,bsas
	ld	a,1
	jr	bdone

	; Floppy: one sector a call, as Lobo's boot sectors do: READ does not
	; keep the head in A from one sector to the next, so a run of sectors
	; can go to side 1. Sectors per track and heads come from the BPB.
	; 17 a track, or one side, or BPB byte 25h set, is Lobo's layout,
	; sectors from 0. Any other is a PC's, from 1, with this sector again
	; at side 1 sector 1, which the ROM reads when there is no sector 0,
	; and the system after it.
bflop:	ld	a,(boot+1Ah)		; heads
	dec	a
	jr	z,bf0
	ld	a,(boot+25h)		; set by mkdisk.py --525 360 or 720
	or	a
	ld	a,0
	jr	nz,bf0
	ld	a,(boot+18h)
	cp	SPT
	ld	a,0
	jr	z,bf0
	inc	a
bf0:	ld	(bbase),a
	ld	hl,boot+18h		; past the last sector: base + SPT
	add	a,(hl)
	ld	(bend),a
	ld	a,(bbase)		; Lobo's: from sector 1. A PC's: from
	ld	(bhead),a		; side 1 sector 2, past the copy
	inc	a
	ld	b,a
	ld	c,SYSSEC		; sectors left
	ld	hl,1000h		; load address in A2
	ld	de,0			; track
bload:	ld	(bleft),bc
	ld	(btrk),de
	ld	c,b			; sectors B-B
	ld	a,(bhead)
	call	ROMREAD			; HL comes back past the sector
	ld	de,(btrk)
	ld	bc,(bleft)
	inc	b
	ld	a,(bend)
	cp	b
	jr	nz,bl1
	ld	a,(bbase)		; next side, or next track
	ld	b,a
	ld	a,(boot+1Ah)		; heads
	dec	a
	jr	z,bl0
	ld	a,(bhead)
	xor	1
	ld	(bhead),a
	jr	nz,bl1
bl0:	inc	de
bl1:	dec	c
	jr	nz,bload
	ld	a,(MLCOPY)		; 0 the 8-inch connector, 2 the 5-inch
	and	20h
	ld	a,2
	jr	z,bdone
	xor	a

bdone:	ld	(BOOTDEV),a		; 0 8-inch, 2 5-inch, 1 SASI, for the kernel
	ld	hl,COMMON_LOAD		; the common part into A1, mapped high
	ld	de,COMMON_ORG
	ld	bc,COMMON_LEN
	ldir
	ld	hl,FONT_LOAD
	ld	a,4			; font RAM 1, characters 00h-7Fh
	call	bfont
	ld	a,6			; font RAM 2, 80h-BFh
	call	bfont
	ld	a,VL_ROM		; the I/O block to F000h
	ld	(B_VLATCH),a
	ld	(VLATCH),a		; and again at its new place
	jp	cold

bfont:	ld	(B_VLATCH),a		; window on font RAM, block at 0000h
	ld	de,0
	ld	bc,400h
	ldir
	ret

bleft:	dw	0			; C: sectors left, B: next sector
btrk:	dw	0
bhead:	db	0
bbase:	db	0			; the first sector number
bend:	db	0			; and one past the last

	assert	$ <= 05FEh
	block	05FEh-$,0
	db	55h,0AAh		; FAT boot sector signature
