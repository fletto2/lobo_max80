; Start-up for SDCC programs on the resident C library. As
; lib/crt0.s, and first starts the library in B2, function 0: where the
; heap starts, the program's errno, and its buffers for the strings and
; the struct tm the library gives. With no library, under another CP/M
; or with no CLIB.SYS, it says so and ends.

	.module	crt0r
	.globl	_main
	.globl	_exit
	.globl	l__INITIALIZER
	.globl	s__INITIALIZER
	.globl	s__INITIALIZED
	.globl	l__DATA
	.globl	s__DATA
	.globl	___heap
	.globl	_cpmargs
	.globl	_cpmargc
	.globl	___clib_init
	.globl	_errno
	.globl	___clibstr
	.globl	___clibtm

	; The order of the areas, as lib/crt0.s
	.area	_CODE
	.area	_HOME
	.area	_GSINIT
	.area	_GSFINAL
	.area	_INITIALIZER
	.area	_INITIALIZED
	.area	_DATA
	.area	_BSEG
	.area	_BSS
	.area	_HEAP

	.area	_CODE
start:	ld	sp,(6)
	ld	bc,#l__INITIALIZER
	ld	a,b
	or	c
	jr	z,1$
	ld	de,#s__INITIALIZED
	ld	hl,#s__INITIALIZER
	ld	a,e
	cp	l
	jr	nz,0$
	ld	a,d
	cp	h
	jr	z,1$			; linked in place
0$:	ldir
1$:	ld	bc,#l__DATA
	ld	a,b
	or	c
	jr	z,2$
	ld	hl,#s__DATA
	ld	(hl),#0
	dec	bc
	ld	a,b
	or	c
	jr	z,2$
	ld	d,h
	ld	e,l
	inc	de
	ldir
2$:	call	gsinit
	ld	c,#12			; xcpmz80 is CP/M 3 to a program
	call	5
	cp	#0x30
	jr	c,3$			; CP/M 2.2: no LIBFN to call
	ld	hl,#___clibtm
	push	hl
	ld	hl,#___clibstr
	push	hl
	ld	hl,#_errno
	push	hl
	ld	hl,#___heap
	push	hl
	call	___clib_init
	pop	af
	pop	af
	pop	af
	pop	af
	ld	a,h
	or	l
	jr	nz,4$
3$:	ld	de,#nolib
	ld	c,#9
	call	5
	jp	0
4$:	call	_cpmargs		; DE = argv, from the command tail
	ld	hl,(_cpmargc)		; sdcccall(1): argc in HL, and
					; argv in DE, from cpmargs
	call	_main
	ld	hl,#0
	push	hl
	call	_exit

nolib:	.ascii	"Needs xcpmz80 and its C library, CLIB.SYS"
	.db	13,10
	.ascii	"$"

	.area	_GSINIT
gsinit:
	.area	_GSFINAL
	ret

	; The heap starts after everything else
	.area	_HEAP
___heap:
