; void *memmove(void *d, const void *s, size_t n): LDIR, or LDDR
; from the end when d is above s
	.module	memmove
	.globl	_memmove
	.area	_CODE
_memmove:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	push	de
	push	hl
	ld	h,b
	ld	l,c		; HL = s, DE = d
	pop	bc		; BC = n
	ld	a,b
	or	c
	jr	z,2$
	ld	a,e
	sub	l
	ld	a,d
	sbc	a,h
	jr	c,1$		; d < s: forward
	add	hl,bc
	dec	hl
	ex	de,hl
	add	hl,bc
	dec	hl
	ex	de,hl
	lddr
	jr	2$
1$:	ldir
2$:	pop	hl
	ret
