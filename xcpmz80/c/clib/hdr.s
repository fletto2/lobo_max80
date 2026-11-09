; CLIB.SYS's start: the C library resident in bank B2, loaded at
; 0000h by the kernel. A program's thunk jumps to 0005h with C = LIBFN
; and DE = the function's number, and the kernel's libent maps B2 and
; jumps here with the program's return address on top of the stack and
; the arguments above it, as SDCC put them. The stack is the program's,
; in A1, which stays mapped.
;
; dispatch: __clib_pre copies the arguments that point under 8000h,
; into B1, to an arena on the program's stack, in A1, and gives the function's
; address. The function runs on the arguments where they are, then
; __clib_post copies back what it wrote and gives back the result,
; which goes back to the program through libout in common memory.

	.module	clibhdr
	.globl	___clib_pre
	.globl	___clib_post
	.globl	___lcopy
	.globl	___clib_res
	.globl	l__INITIALIZER
	.globl	s__INITIALIZER
	.globl	s__INITIALIZED
	.globl	l__DATA
	.globl	s__DATA
	.globl	___clib_reset

	; The order of the areas, so the linker lays them out so, from
	; 0000h: the header first
	.area	_CODE
	.area	_INITIALIZER
	.area	_HOME
	.area	_GSINIT
	.area	_GSFINAL
	.area	_DATA
	.area	_INITIALIZED
	.area	_BSEG
	.area	_BSS
	.area	_HEAP

	.area	_CODE
	jp	dispatch
	.db	1			; 0003h, the version
	.db	0
	.db	0xc3			; 0005h, jp bdosent, for the library's
	.dw	0			; own BDOS calls, as in a TPA
libout:	.dw	0			; 0008h, the kernel fills these in
lcopyp:	.dw	0			; 000Ah
	.ascii	"CLIB"			; 000Ch, what the kernel checks

	.area	_CODE
; The state of one call. Not in _DATA, which __clib_reset zeroes.
pret:	.dw	0			; the program's return address
___clib_res:
	.dw	0,0			; the result, HL then DE

dispatch:
	pop	hl
	ld	(pret),hl
	ld	hl,#0
	add	hl,sp			; the arguments
	push	hl
	push	de
	call	___clib_pre		; HL = the function, 0 none
	pop	af
	pop	af
	ld	a,h
	or	l
	jr	z,1$
	call	2$
	ld	(___clib_res),hl
	ld	(___clib_res+2),de
	call	___clib_post
1$:	ld	hl,(pret)
	push	hl
	ld	hl,(libout)
	push	hl
	ld	hl,(___clib_res)
	ld	de,(___clib_res+2)
	ret				; to libout, then to the program
2$:	jp	(hl)

; void __lcopy(const void *from, void *to, unsigned n): n bytes, not 0,
; as the program sees memory, by lcopy in common memory
___lcopy:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	pop	hl
	push	ix
	push	iy
	call	3$
	pop	iy
	pop	ix
	ret
3$:	push	hl
	ld	hl,(lcopyp)
	ex	(sp),hl
	ret

; void __clib_reset(void): the library's variables as the image has
; them, for each program
___clib_reset:
	ld	bc,#l__INITIALIZER
	ld	a,b
	or	c
	jr	z,4$
	ld	de,#s__INITIALIZED
	ld	hl,#s__INITIALIZER
	ldir
4$:	ld	bc,#l__DATA
	ld	a,b
	or	c
	ret	z
	ld	hl,#s__DATA
	ld	(hl),#0
	dec	bc
	ld	a,b
	or	c
	ret	z
	ld	d,h
	ld	e,l
	inc	de
	ldir
	ret

	.area	_GSINIT
	.area	_GSFINAL
	ret
