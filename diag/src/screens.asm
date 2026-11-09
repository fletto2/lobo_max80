; Test screens for the monitor and the video circuit. Each waits for a
; key, BREAK or ESC goes back to the menu. Their names go out SIO A only.

scr80:	ld	hl,list80
	ld	a,VL_VIDEO
	ld	b,1
	jr	scrs
scr40:	ld	hl,list40
	ld	a,VL_VIDEO+8		; VLATCH bit 3, double width
	ld	b,2
	jr	scrs
cchars:	ld	hl,listch
	ld	a,VL_VIDEO
	ld	b,1

; Show the screens listed at HL, with VLATCH A and B video cells a
; column
scrs:	call	setvl
	ld	a,b
	ld	(stride),a
	xor	a
	ld	(scrout),a
	ld	(sodd),a
sc1:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,d
	or	e
	jr	z,sc2
	push	hl
	ex	de,hl
	call	jphl
	call	waitkey
	pop	hl
	cp	03h
	jr	z,sc2
	cp	1Bh
	jr	nz,sc1
sc2:	call	crtinit
	ld	a,1
	ld	(stride),a
	ld	(scrout),a
	xor	a
	ld	(sodd),a
	jp	vredraw

list80:	dw	s_solid,s_grid,s_check,s_vert,s_horz,s_h,s_frame,s_chars,0
list40:	dw	s_solid,s_grid,s_check,s_vert,s_horz,s_h,s_frame,s_chars
	dw	s_even,s_odd,0
listch:	dw	s_chars,0

s_solid:
	call	print
	db	"Solid",0Dh,0Ah,0
	ld	a,G_SOLID
	jp	vfill
s_grid:	call	print
	db	"Grid",0Dh,0Ah,0
	ld	a,G_GRID
	jp	vfill
s_check:
	call	print
	db	"Dots",0Dh,0Ah,0
	ld	a,G_CHECK
	jp	vfill
s_vert:	call	print
	db	"Vertical lines",0Dh,0Ah,0
	ld	a,G_VERT
	jp	vfill
s_horz:	call	print
	db	"Horizontal lines",0Dh,0Ah,0
	ld	a,G_HORZ
	jp	vfill
s_h:	call	print
	db	"H everywhere",0Dh,0Ah,0
	ld	a,'H'
	jp	vfill

; A frame round the edge of the screen, and its size in the middle
s_frame:
	call	print
	db	"Frame",0Dh,0Ah,0
	ld	a,' '
	call	vfill
	call	scols
	ld	b,a
	ld	hl,0
fr1:	ld	a,G_SOLID
	ld	l,0
	call	sput
	ld	l,23
	call	sput
	inc	h
	djnz	fr1
	call	scols
	dec	a
	ld	c,a			; the last column
	ld	l,1
	ld	b,22
fr2:	ld	h,0
	ld	a,G_SOLID
	call	sput
	ld	h,c
	call	sput
	inc	l
	djnz	fr2
	call	scols
	sub	20
	rra
	ld	c,a			; 20 characters, centered
	ld	b,11
	ld	hl,t80
	ld	a,(stride)
	dec	a
	jr	z,fr3
	ld	hl,t40
fr3:	call	stext
	call	scols
	sub	20
	rra
	ld	c,a
	ld	b,12
	ld	hl,tkeys
	jp	stext
t80:	db	"80 COLUMNS, 24 ROWS",0
t40:	db	"40 COLUMNS, 24 ROWS",0
tkeys:	db	"KEY NEXT, BREAK MENU",0

; Every code, 16 a row, labeled with the high digit
s_chars:
	call	print
	db	"Character set",0Dh,0Ah,0
	ld	a,' '
	call	vfill
	ld	bc,0
	ld	hl,tchars
	call	stext
	ld	e,0			; the code
	ld	l,2			; the row
ch1:	ld	h,0
	ld	a,e
	rrca
	rrca
	rrca
	rrca
	call	hexch
	call	sput
	inc	h
	ld	a,'0'
	call	sput
	ld	h,4
	ld	b,16
ch2:	ld	a,e
	call	sput
	inc	h
	inc	h
	inc	e
	djnz	ch2
	inc	l
	ld	a,e
	or	a
	jr	nz,ch1
	ret
tchars:	db	"CHARACTER SET",0

; 40 columns: the even cells say one thing and the odd cells another.
; R2 = 97 shows the even ones, 98 the odd ones.
s_even:	call	print
	db	"40 columns, even cells, R2 = 97",0Dh,0Ah,0
	call	s_eo
	ld	a,97
	jr	setr2
s_odd:	call	print
	db	"40 columns, odd cells, R2 = 98",0Dh,0Ah,0
	call	s_eo
	ld	a,98
	jr	setr2

; Both texts, one in the even cells and one in the odd, so each screen
; stands alone
s_eo:	ld	a,' '
	call	vfill
	ld	bc,11*256+10
	ld	hl,teven
	call	stext
	ld	a,1
	ld	(sodd),a
	ld	bc,11*256+10
	ld	hl,todd
	call	stext
	xor	a
	ld	(sodd),a
	ret

setr2:	push	af
	ld	a,2
	ld	(CRTREG),a
	pop	af
	ld	(CRTBYT),a
	ret
teven:	db	"EVEN CELLS, R2 = 97",0
todd:	db	"ODD CELLS, R2 = 98 ",0

; A = the columns on the screen, 80 or 40
scols:	ld	a,(stride)
	dec	a
	ld	a,80
	ret	z
	ld	a,40
	ret

; A as one hex digit
hexch:	and	0Fh
	add	a,90h
	daa
	adc	a,40h
	daa
	ret

; A into the cell at row L, column H. In 40 columns that is video cell
; H x 2, plus 1 when sodd is set. Keeps every register.
sput:	push	de
	push	hl
	push	af
	ld	a,(stride)
	dec	a
	jr	z,su1
	ld	a,(sodd)
	sla	h
	add	a,h
	ld	h,a
su1:	call	vidx
	call	vaddr
	pop	af
	ld	(de),a
	pop	hl
	pop	de
	ret

; The string at HL into the screen from row B, column C
stext:	ld	a,(hl)
	inc	hl
	or	a
	ret	z
	push	hl
	ld	l,b
	ld	h,c
	call	sput
	pop	hl
	inc	c
	jr	stext
