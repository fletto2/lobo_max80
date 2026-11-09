; char *strcpy(char *d, const char *s)
	.module	strcpy
	.globl	_strcpy
	.area	_CODE
_strcpy:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	push	de
1$:	ld	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	or	a
	jr	nz,1$
	pop	hl
	ret
