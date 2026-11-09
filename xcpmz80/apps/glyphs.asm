; GLYPHS: show every shape font RAM holds, 00h-BFh, in a table.
; C0h-FFh have no shapes of their own and show 80h-BFh. The codes go
; straight into video RAM, so control codes show as their glyphs too.
; Needs the 80 column screen.

BDOS	equ	5
BLK	equ	0F000h			; the I/O block under xcpmz80
VLATCH	equ	BLK+7DCh		; a read gives its RAM copy
VIDLO	equ	BLK+0C00h		; video RAM 000h-3FFh
VIDWIN	equ	BLK			; video RAM 400h-7FFh, window 2
VIDEO2	equ	2
COLS	equ	80
TOP	equ	3			; screen row of the 00h row
LEFT	equ	5			; screen column of the 0 column

	org	100h
	ld	de,m_table		; clears the screen, so row 0 is
	ld	c,9			; video RAM 000h
	call	BDOS
	di
	ld	a,(VLATCH)
	push	af
	and	0F8h
	or	VIDEO2
	ld	(VLATCH),a
	ld	hl,TOP*COLS+LEFT
	ld	c,0			; the code
gl_row:	ld	b,16
gl_col:	push	hl
	ld	de,VIDLO
	ld	a,h
	cp	4
	jr	c,gl_put
	ld	de,VIDWIN-400h
gl_put:	add	hl,de
	ld	(hl),c
	pop	hl
	inc	hl
	inc	hl
	inc	hl
	inc	c
	djnz	gl_col
	ld	de,COLS-16*3
	add	hl,de
	ld	a,c
	cp	0C0h
	jr	nz,gl_row
	pop	af
	ld	(VLATCH),a
	ei
	ret

m_table: db	1Bh,"*"
	db	"Font RAM, codes 00h-BFh. C0h-FFh show the same shapes "
	db	"as 80h-BFh.",0Dh,0Ah,0Dh,0Ah
	db	"     0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F",0Dh,0Ah
	db	"00h",0Dh,0Ah,"10h",0Dh,0Ah,"20h",0Dh,0Ah,"30h",0Dh,0Ah
	db	"40h",0Dh,0Ah,"50h",0Dh,0Ah,"60h",0Dh,0Ah,"70h",0Dh,0Ah
	db	"80h",0Dh,0Ah,"90h",0Dh,0Ah,"A0h",0Dh,0Ah,"B0h",0Dh,0Ah
	db	0Dh,0Ah,"$"
