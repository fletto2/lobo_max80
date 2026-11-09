; void *memset(void *d, int c, size_t n)
	.module	memset
	.globl	_memset
	.area	_CODE
_memset:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	push	de
	ex	de,hl
	ld	e,a
	ld	a,b
	or	c
	jr	z,1$
	ld	(hl),e
	dec	bc
	ld	a,b
	or	c
	jr	z,1$
	ld	d,h
	ld	e,l
	inc	de
	ldir
1$:	pop	hl
	ret
