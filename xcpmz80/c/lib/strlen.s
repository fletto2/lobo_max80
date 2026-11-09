; size_t strlen(const char *s): CPIR for the 0
	.module	strlen
	.globl	_strlen
	.area	_CODE
_strlen:
	pop	bc
	pop	hl
	push	hl
	push	bc
	xor	a
	ld	b,a
	ld	c,a
	cpir
	ld	a,c		; BC = -(length+1), so the length is ~BC
	cpl
	ld	l,a
	ld	a,b
	cpl
	ld	h,a
	ret
