; char *strchr(const char *s, int c): the first c, the 0 at the
; end included, or NULL
	.module	strchr
	.globl	_strchr
	.area	_CODE
_strchr:
	ld	hl,#4
	add	hl,sp
	ld	e,(hl)
	dec	hl
	ld	a,(hl)
	dec	hl
	ld	l,(hl)
	ld	h,a
1$:	ld	a,(hl)
	cp	e
	ret	z
	or	a
	jr	z,2$
	inc	hl
	jr	1$
2$:	ld	h,a
	ld	l,a
	ret
