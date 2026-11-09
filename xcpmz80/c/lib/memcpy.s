; void *memcpy(void *d, const void *s, size_t n), arguments on the
; stack. LDIR. The struct copy ___memcpy is in smemcpy.s.
	.module	memcpy
	.globl	_memcpy
	.area	_CODE
_memcpy:
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
	ld	l,c
	pop	bc
	ld	a,b
	or	c
	jr	z,1$
	ldir
1$:	pop	hl
	ret
