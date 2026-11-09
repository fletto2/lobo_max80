; ___memcpy, which SDCC 4 calls to copy a struct: sdcccall(1),
; HL = the destination, DE = the source, the count on the stack, taken
; off by the callee. The destination comes back in DE. Without z80.lib's
; memcpy.rel, which defines _memcpy as well, over the library's.
	.module	smemcpy
	.globl	___memcpy
	.area	_CODE
___memcpy:
	ex	de,hl			; HL = the source, DE = the destination
	pop	bc			; the return address
	ex	(sp),hl			; HL = the count, the source in its place
	push	bc
	ld	b,h
	ld	c,l
	ld	hl,#2
	add	hl,sp
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a			; HL = the source
	push	de
	ld	a,b
	or	c
	jr	z,1$
	ldir
1$:	pop	de			; the destination
	pop	hl			; the return address
	pop	bc			; the count's place
	jp	(hl)
