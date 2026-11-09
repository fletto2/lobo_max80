; Keys from the matrix, scanned on each tick, and from SIO channel A.
; Interrupts stay off: the tick is polled in SYSFLG bit 7.

; On a tick: clear it, count it and scan the keyboard. Keeps every
; register.
poll:	push	af
	ld	a,(SYSFLG)
	and	80h
	jr	z,pl1
	ld	a,(SYSCLR)		; clears the tick
	push	hl
	ld	hl,(ticks)
	inc	hl
	ld	(ticks),hl
	pop	hl
	call	kscan
pl1:	pop	af
	ret

; A key counts once it is down in two scans in a row, one tick apart.
; The first new one goes in kkey if kkey is empty, and every one is
; marked in kseen. Keeps every register.
kscan:	push	af
	push	bc
	push	de
	push	hl
	ld	de,MATRIX+1
	ld	hl,k1
	ld	b,0			; row
ks1:	ld	a,(de)			; down now
	ld	c,a
	ld	a,(hl)			; down at the last scan
	ld	(hl),c
	and	c			; down in both
	push	hl
	push	bc
	ld	bc,8
	add	hl,bc			; k2, the last stable scan
	ld	c,a
	ld	a,(hl)
	ld	(hl),c
	push	af
	push	de
	ld	de,kseen-k2
	add	hl,de
	ld	a,(hl)
	or	c
	ld	(hl),a			; for the keyboard test
	pop	de
	pop	af
	cpl
	and	c			; stable now and not before
	pop	bc
	pop	hl
	call	nz,knew
	inc	hl
	sla	e			; the next row address bit
	inc	b
	ld	a,b
	cp	8
	jr	nz,ks1
	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

; A = the new keys of row B. SHIFT and CTRL alone are not keys.
knew:	push	bc
	push	hl
	ld	c,a
	ld	a,b
	cp	7
	ld	a,c
	jr	nz,kn1
	and	7Eh
	jr	z,kn3
kn1:	ld	c,0
kn2:	rra
	jr	c,kn4
	inc	c
	jr	kn2
kn4:	ld	a,b
	add	a,a
	add	a,a
	add	a,a
	add	a,c
	ld	c,a
	ld	b,0
	ld	hl,ktab
	add	hl,bc
	ld	a,(kkey)
	or	a
	jr	nz,kn3
	ld	a,(hl)
	ld	(kkey),a
kn3:	pop	hl
	pop	bc
	ret

; The key matrix, as the TRM gives it. Letters in upper case.
; CLEAR 1Fh, BREAK 03h, the arrows 80h-83h, F1-F4 84h-87h.
ktab:	db	"@ABCDEFG"
	db	"HIJKLMNO"
	db	"PQRSTUVW"
	db	"XYZ[",5Ch,"]^_"
	db	"01234567"
	db	"89:;,-./"
	db	0Dh,1Fh,03h,80h,81h,82h,83h,' '
	db	0,84h,85h,86h,87h,1Bh,0,0

; A = a key from the keyboard or SIO A, 0 if none, flags set from A.
; A NUL from the terminal, CTRL-@, comes back as @, so it is a key.
inkey:	call	poll
	ld	a,(kkey)
	or	a
	jr	z,ik1
	push	af
	xor	a
	ld	(kkey),a
	pop	af
	ret
ik1:	ld	a,(SIOCA)
	and	1
	ret	z
	ld	a,(SIODA)
	or	a
	jr	nz,ik3
	ld	a,'@'
ik3:	cp	'a'
	jr	c,ik2
	cp	'z'+1
	jr	nc,ik2
	sub	20h
ik2:	or	a
	ret

; Wait for a key
waitkey:
	call	inkey
	jr	z,waitkey
	ret

; Wait B ticks, or less if a key comes. A = the key, or 0.
pause:	ld	hl,(ticks)
	ld	e,b
	ld	d,0
	add	hl,de
	ex	de,hl
pa1:	call	inkey
	ret	nz
	ld	hl,(ticks)
	or	a
	sbc	hl,de
	jr	nz,pa1
	xor	a
	ret
