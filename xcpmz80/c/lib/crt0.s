; Start-up for SDCC programs under CP/M. A .COM loads at 0100h.
; Sets the stack under the BDOS, copies the initialized data to where
; the program wants it, zeroes the rest of the data, which C expects and
; CP/M does not give, then runs main(argc, argv) and ends with
; exit(0).

	.module	crt0
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

	; The order of the areas, so the linker lays them out so. The
	; Makefile links twice, the second time with _INITIALIZED where
	; _INITIALIZER is, so the initial values load where the program
	; wants them and take no memory twice. The copy below then copies
	; them onto themselves, and is skipped.
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
	call	_cpmargs		; DE = argv, from the command tail
	ld	hl,(_cpmargc)		; sdcccall(1): argc in HL, and
					; argv in DE, from cpmargs
	call	_main			; its result, in DE, for exit
	ex	de,hl
	push	hl
	call	_exit

	.area	_GSINIT
gsinit:
	.area	_GSFINAL
	ret

	; The heap starts after everything else
	.area	_HEAP
___heap:
