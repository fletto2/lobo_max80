; int strcmp(const char *a, const char *b): -1, 0 or 1, by the
; first byte that differs, unsigned
	.module	strcmp
	.globl	_strcmp
	.area	_CODE
_strcmp:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a		; DE = a, HL = b
1$:	ld	a,(de)
	cp	(hl)
	jr	nz,2$
	or	a
	jr	z,3$
	inc	de
	inc	hl
	jr	1$
2$:	ld	hl,#1
	ret	nc
	ld	hl,#-1
	ret
3$:	ld	h,a
	ld	l,a
	ret
