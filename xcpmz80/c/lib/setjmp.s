; int setjmp(jmp_buf b) and void longjmp(jmp_buf b, int v).
; jmp_buf holds SP after the return, IX, the frame pointer, and the
; return address. longjmp gives v, 1 for 0.
	.module	setjmp
	.globl	_setjmp
	.globl	_longjmp
	.area	_CODE
_setjmp:
	pop	bc		; the return address
	pop	hl		; b
	push	hl
	push	bc
	ld	(hl),c
	inc	hl
	ld	(hl),b
	inc	hl
	ex	de,hl
	ld	hl,#2
	add	hl,sp
	ex	de,hl
	ld	(hl),e		; SP after the return
	inc	hl
	ld	(hl),d
	inc	hl
	push	ix
	pop	de
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ld	hl,#0
	ret

_longjmp:
	pop	bc
	pop	hl		; b
	pop	de		; v
	ld	a,d
	or	e
	jr	nz,1$
	inc	e
1$:	ld	c,(hl)
	inc	hl
	ld	b,(hl)		; the return address
	inc	hl
	ld	a,(hl)
	inc	hl
	push	af
	ld	a,(hl)
	inc	hl
	push	af
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	push	hl
	pop	ix
	pop	af
	ld	h,a
	pop	af
	ld	l,a
	ld	sp,hl		; as setjmp had it
	ex	de,hl		; HL = v
	push	bc		; back to where setjmp returned
	ret
