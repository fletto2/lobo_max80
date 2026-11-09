; unsigned int bdos(unsigned char fn, unsigned int de): calls the
; BDOS at 0005h and gives back HL, where CP/M 3 and xcpmz80 return, with
; A in L. As __sdcccall(0) (__LIB), the arguments are on the stack,
; the caller pops them, and IX, its frame pointer, must be kept.

	.module	bdos
	.globl	_bdos
	.globl	_getr

	.area	_CODE
_bdos:	ld	hl,#2
	add	hl,sp
	ld	c,(hl)
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	push	ix
	push	iy
	call	5
	pop	iy
	pop	ix
	ret

; unsigned char getr(void): the Z80's refresh register, for a seed
_getr:	ld	a,r
	ld	l,a
	ret

; unsigned int __bios22(unsigned char n, unsigned int bc, unsigned int de):
; BIOS entry n by the jump table that 0001h points into, CP/M 2.2's way.
; Gives back HL and A, A in L for the entries that give no HL.
	.globl	___bios22
___bios22:
	ld	hl,#2
	add	hl,sp
	ld	a,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	push	ix
	push	iy
	ld	(bion),a
	push	de
	ld	l,a
	ld	h,#0
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,de
	ld	de,(1)
	add	hl,de
	ld	de,#-3
	add	hl,de
	pop	de
	call	1$
	pop	iy
	pop	ix
	ld	c,a
	ld	a,(bion)
	cp	#9			; SELDSK and SECTRAN give HL
	ret	z
	cp	#16
	ret	z
	ld	l,c
	ld	h,#0
	ret
1$:	jp	(hl)

	.area	_DATA
bion:	.ds	1
