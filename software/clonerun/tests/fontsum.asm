; FONTSUM.COM, for test.sh: prints VLATCH's RAM copy and a 16-bit sum
; of each 1K of font RAM, as "VL 32 F1 1234 F2 5678". Run before and
; after CLONERUN, the two lines must match.

	include	"hw.inc"

	org	100h
	ld	a,(VLATCH)
	ld	(vl),a
	ld	a,W_FONT1
	call	sum
	ld	(sum1),hl
	ld	a,W_FONT2
	call	sum
	ld	(sum2),hl
	ld	de,m_vl
	call	print
	ld	a,(vl)
	call	hex
	ld	de,m_f1
	call	print
	ld	hl,(sum1)
	call	hex2
	ld	de,m_f2
	call	print
	ld	hl,(sum2)
	call	hex2
	ld	de,m_crlf
print:	ld	c,9
	jp	BDOS

; A the window: HL the sum of the 1K it shows
sum:	di
	ld	c,a
	ld	a,(vl)
	and	0F8h
	or	c
	ld	(VLATCH),a
	ld	hl,0
	ld	de,WINDOW
	ld	bc,400h
sm_1:	ld	a,(de)
	add	a,l
	ld	l,a
	jr	nc,sm_2
	inc	h
sm_2:	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,sm_1
	ld	a,(vl)
	ld	(VLATCH),a
	ei
	ret

hex2:	push	hl
	ld	a,h
	call	hex
	pop	hl
	ld	a,l
hex:	push	af
	rrca
	rrca
	rrca
	rrca
	call	hx_1
	pop	af
hx_1:	and	0Fh
	add	a,'0'
	cp	'9'+1
	jr	c,hx_2
	add	a,'A'-'9'-1
hx_2:	ld	e,a
	ld	c,2
	jp	BDOS

m_vl:	db	"VL $"
m_f1:	db	" F1 $"
m_f2:	db	" F2 $"
m_crlf:	db	13,10,'$'
vl:	db	0
sum1:	dw	0
sum2:	dw	0
