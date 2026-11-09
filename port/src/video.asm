; The screen: the start, the glyphs, the two pages and the change lists.
;
; A cell is an offset from the screen start, row x 80 + 2 x column, the
; even character of a wide cell. Page 0 is the even characters, page 1
; the odd ones. The window stays on video RAM 400h-7FFh the whole game.

; Finds the screen start from the BIOS cursor, the one 7Fh in video RAM
; after 1Eh and ESC Y. Carry set when there is not exactly one.
findstart:
	ld	b,0		; hits, stops at 2
	ld	hl,VIDLO
fs_1:	ld	a,(hl)
	cp	CURSOR
	call	z,fs_hit
	inc	hl
	ld	a,h
	or	l
	jr	nz,fs_1		; to FFFFh
	di
	ld	a,(VLATCH)
	ld	c,a
	and	0F8h
	or	W_VIDEO
	ld	(VLATCH),a
	ld	hl,WINDOW
fs_2:	ld	a,(hl)
	cp	CURSOR
	call	z,fs_hit
	inc	hl
	ld	a,h
	cp	0F4h		; to F3FFh
	jr	nz,fs_2
	ld	a,c
	ld	(VLATCH),a
	ei
	ld	a,b
	cp	1
	scf
	ret	nz
	or	a
	ret

; HL a CPU address in video RAM: count it and keep its ring address
fs_hit:	ld	a,b
	cp	2
	ret	z
	inc	b
	push	hl
	ld	de,0400h	; FC00h-FFFFh to 000h-3FFh, F000h-F3FFh to 400h-7FFh
	add	hl,de
	ld	a,h
	and	07h
	ld	h,a
	ld	(vstart),hl
	pop	hl
	ret

; DE the cell offset, A the page: HL its CPU address. Keeps BC and DE.
cellptr:
	ld	hl,(vstart)
	add	hl,de
	add	a,l
	ld	l,a
	jr	nc,cp_1
	inc	h
cp_1:	ld	a,h		; ring 000h-3FFh at FC00h, 400h-7FFh at F000h
	and	07h
	add	a,0Ch
	and	0Fh
	or	0F0h
	ld	h,a
	ret

; B row, C column: DE the cell offset. Keeps BC.
celloff:
	ld	l,b
	ld	h,0
	add	hl,hl
	ld	de,rowoff
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	l,c
	ld	h,0
	add	hl,hl
	add	hl,de
	ex	de,hl
	ret

; B row, C column, A code: write the cell on both pages, now
putboth:
	push	af
	call	celloff
	xor	a
	call	cellptr
	pop	af
	ld	(hl),a
	push	af
	ld	a,1
	call	cellptr
	pop	af
	ld	(hl),a
	ret

; B row, C column, A code: write the cell on page (wpage) now, both
; pages when it is 2
putcell:
	push	af
	ld	a,(wpage)
	cp	2
	jr	z,pc_1
	call	celloff
	ld	a,(wpage)
	call	cellptr
	pop	af
	ld	(hl),a
	ret
pc_1:	pop	af
	jr	putboth

; B row, C column, HL text ending in 0: write it on page (wpage) now
puts:	ld	a,(hl)
	or	a
	ret	z
	push	hl
	call	putcell
	pop	hl
	inc	hl
	inc	c
	jr	puts

; Blanks all 24 rows of both pages
clrscr:	ld	de,0
	ld	bc,ROWS*COLS
cs_1:	xor	a
	call	cellptr
	ld	(hl),' '
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,cs_1
	ret

; B row, C column, A code: a change for the hidden page, written this
; frame and again next frame, so both pages get it. At most MAXCHG a
; frame.
setcell:
	push	af
	call	celloff
	ld	hl,(curend)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	pop	af
	ld	(hl),a
	inc	hl
	ld	(curend),hl
	ret

; Writes the hidden page: last frame's changes, then this frame's, and
; makes this frame's list last frame's
render:	ld	a,(shown)
	xor	1
	ld	(wpage),a
	ld	hl,(prevlst)
	ld	bc,(prevend)
	call	wrlist
	ld	hl,(curlst)
	ld	bc,(curend)
	push	hl
	push	bc
	call	wrlist
	ld	hl,(prevlst)	; the old list becomes the new, empty
	ld	(curlst),hl
	ld	(curend),hl
	pop	hl
	ld	(prevend),hl
	pop	hl
	ld	(prevlst),hl
	ret

; HL the first change, BC the end: write them on page (wpage)
wrlist:	ld	a,l
	cp	c
	jr	nz,wl_1
	ld	a,h
	cp	b
	ret	z
wl_1:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	push	hl
	push	af
	ld	a,(wpage)
	call	cellptr
	pop	af
	ld	(hl),a
	pop	hl
	jr	wrlist

; Waits for the start of the next vertical blank: the picture, then
; SYSFLG bit 6 off for longer than a line. Returns with interrupts off.
; The test build counts the passes through the picture into idle.
waitvb:	di
	ld	hl,SYSFLG
	ifdef	TEST
	ld	de,0
	endif
wv_1:	bit	6,(hl)
	jr	z,wv_1
wv_2:
	ifdef	TEST
	inc	de
	endif
	ld	b,OFFRUN
wv_3:	bit	6,(hl)
	jr	nz,wv_2
	djnz	wv_3
	ifdef	TEST
	ld	(idle),de
	endif
	ret

; Shows page (shown). Call with interrupts off.
setr2:	ld	a,2
	ld	(CRTREG),a
	ld	a,(shown)
	add	a,R2EVEN
	ld	(CRTBYT),a
	ret

; Saves font RAM 2's rows 0-7 of 80h-BFh, writes the glyphs, sets double
; width with the window on video RAM, and goes into 8-line rows
vidin:	di
	ld	a,(VLATCH)
	ld	(vlsave),a
	and	0F0h
	or	W_FONT2
	ld	(VLATCH),a
	ld	hl,WINDOW
	ld	de,fontbuf
	ld	bc,200h
	ldir
	ld	hl,glyphs
	ld	de,WINDOW
	ld	bc,NGLYPH*8
	ldir
	ld	a,(vlsave)
	and	0F0h
	or	WIDE|W_VIDEO
	ld	(VLATCH),a
	ei
	jr	linein

; Shows the even characters, goes back to the BIOS's 9-line rows and
; puts back font RAM 2 and VLATCH
vidout:	call	waitvb
	xor	a
	ld	(shown),a
	call	setr2
	call	lineout
	di
	ld	a,(vlsave)
	and	0F0h
	or	W_FONT2
	ld	(VLATCH),a
	ld	hl,fontbuf
	ld	de,WINDOW
	ld	bc,200h
	ldir
	ld	a,(vlsave)
	ld	(VLATCH),a
	ei
	ret

; Into 8-line rows. This
; BIOS frame gets R5 = 22, so it is 274 lines with its sync still at line
; 234, and the sync of the first 8-line frame, at line 224, comes 264
; lines on.
linein:	call	waitvb
	ld	a,5
	ld	c,22
	call	crtw
	call	dwait
	ld	hl,crt8
	jr	crtset

; Back to the BIOS's 9-line rows. This 8-line frame gets R4 = 30 and
; R5 = 6, so it is 254 lines with its sync still at line 224, and the
; BIOS frame's sync at line 234 comes 264 lines on.
lineout:
	call	waitvb
	ld	a,4
	ld	c,30
	call	crtw
	ld	a,5
	ld	c,6
	call	crtw
	call	dwait
	ld	hl,crt9

; HL register and value pairs ending in FFh, written. Interrupts back on.
crtset:	ld	a,(hl)
	cp	0FFh
	jr	z,ct_1
	inc	hl
	ld	c,(hl)
	inc	hl
	call	crtw
	jr	crtset
ct_1:	ei
	ret

; R9, R4, R7, R5 for 8-line rows, 33 rows of 8, and the BIOS's
crt8:	db	9,7, 4,32, 7,28, 5,0, 0FFh
crt9:	db	9,8, 4,27, 7,26, 5,12, 0FFh

; CRTC register A = C
crtw:	ld	(CRTREG),a
	ld	a,c
	ld	(CRTBYT),a
	ret

; Waits for the picture's first line
dwait:	ld	hl,SYSFLG
dw_1:	bit	6,(hl)
	jr	z,dw_1
	ret

; B row, C column: A the background's dither glyph there, its level from
; the distance to the board, 1 to 10, and G_EDGE in column 39. The test
; build leaves row 23 blank for its key counts. Keeps BC and DE.
bgcode:
	ifdef	TEST
	ld	a,b
	cp	23
	ld	a,' '
	ret	z
	endif
	ld	a,c
	cp	39
	ld	a,G_EDGE
	ret	z
	push	hl
	push	de
	ld	d,0
	ld	e,c
	ld	hl,bgcol
	add	hl,de
	ld	a,(hl)
	ld	e,b
	ld	hl,bgrow
	add	hl,de
	add	a,(hl)
	add	a,2
	pop	de
	pop	hl
	bit	7,a
	jr	nz,bg_1
	or	a
	jr	z,bg_1
	cp	11
	jr	c,bg_2
	ld	a,10
	jr	bg_2
bg_1:	ld	a,1
bg_2:	add	a,G_DITH-1
	ret

; The level's part from the column and from the row
bgcol:	db	9,8,7,6,6,5,4,4,3,2,2,1,0,0
	db	-9,-8,-7,-7,-6,-5,-5,-4,-3,-3,-2,-1
	db	0,0,1,2,2,3,4,4,5,6,6,7,8,9
bgrow:	db	1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2

; A box from row B, column C to row D, column E, the border glyph set
; from A, the inside blank. IX writes a cell, B row, C column, A code,
; putboth or setcell.
boxdraw:
	ld	(bx_g),a
	ld	(bx_c0),bc
	ld	(bx_c1),de
bd_1:	push	bc
	call	bxcode
	call	jpix
	pop	bc
	ld	a,(bx_c1)
	cp	c
	jr	z,bd_2
	inc	c
	jr	bd_1
bd_2:	ld	a,(bx_r1)
	cp	b
	ret	z
	inc	b
	ld	a,(bx_c0)
	ld	c,a
	jr	bd_1

jpix:	jp	(ix)

; B row, C column in the box: A its code. Keeps BC.
bxcode:	ld	e,0		; the set's top left
	ld	a,(bx_r0)
	cp	b
	jr	z,bx_1
	ld	e,5		; bottom left
	ld	a,(bx_r1)
	cp	b
	jr	z,bx_1
	ld	e,3		; left
	ld	a,(bx_c0)
	cp	c
	jr	z,bx_2
	ld	e,4		; right
	ld	a,(bx_c1)
	cp	c
	jr	z,bx_2
	ld	a,' '
	ret
bx_1:	ld	a,(bx_c0)	; the top or bottom row: left, middle or right
	cp	c
	jr	z,bx_2
	inc	e
	ld	a,(bx_c1)
	cp	c
	jr	nz,bx_2
	inc	e
bx_2:	ld	a,(bx_g)
	add	a,e
	ret

; HL text ending in 0, B its length, odd: glyphs G_MSG on for the B + 1
; cells that show it half a cell off the grid, each the right half of one
; letter and the left half of the next, from font RAM 1
msgglyphs:
	di
	ld	a,(VLATCH)
	push	af
	and	0F8h
	or	W_FONT1
	ld	(VLATCH),a
	ld	de,chbuf
mg_1:	ld	a,(hl)
	or	a
	jr	z,mg_2
	push	hl
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	push	bc
	ld	bc,WINDOW
	add	hl,bc
	ld	bc,8
	ldir
	pop	bc
	pop	hl
	inc	hl
	jr	mg_1
mg_2:	ld	c,8		; blank after the last letter
mg_3:	ld	(de),a
	inc	de
	dec	c
	jr	nz,mg_3
	pop	af
	push	af
	and	0F8h
	or	W_FONT2
	ld	(VLATCH),a
	ld	ix,chbuf-8	; the blank before the first
	ld	de,WINDOW+(G_MSG-80h)*8
	inc	b
mg_4:	ld	c,8
mg_5:	ld	a,(ix+0)
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	ld	h,a
	ld	a,(ix+8)
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	or	h
	ld	(de),a
	inc	de
	inc	ix
	dec	c
	jr	nz,mg_5
	djnz	mg_4
	pop	af
	ld	(VLATCH),a
	ei
	ret

rowoff:
.r = 0
	dup	ROWS
	dw	.r*COLS
.r = .r+1
	edup

; Our glyphs, codes 80h-A4h, rows 0-7, the pieces in the GB's id order
; L, J, I, O, Z, S, T, drawn for this port. Bit 7 is the left dot. Each shows twice as wide.
; Row 0 and bit 0 stay clear on the blocks, so neighbors show a gap.
; G_MSG on, up to 11, are made for each message.
G_L	equ	80h		; the GB's ids, 0 to 6
G_J	equ	81h
G_I	equ	82h
G_O	equ	83h
G_Z	equ	84h
G_S	equ	85h
G_T	equ	86h
G_FLASH	equ	87h
G_WALL	equ	88h		; the test boards' cells
G_HEART	equ	89h
G_FRAME	equ	8Ah		; top left, top, top right, left, right, bottom left, bottom, bottom right
G_BOX	equ	92h		; the same
G_DITH	equ	9Ah		; levels 1 to 10, 1 the darkest
G_EDGE	equ	0A4h		; level 10 with its right half blank, for column 39
NGLYPH	equ	37
G_MSG	equ	0A5h
G_NEXT	equ	0B0h		; 12, the NEXT piece, made for each piece

glyphs:	db	000h,0FEh,082h,0BAh,0BAh,0BAh,082h,0FEh	; L
	db	000h,0FEh,082h,082h,082h,082h,082h,0FEh	; J
	db	000h,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh	; I
	db	000h,0FEh,082h,082h,092h,082h,082h,0FEh	; O
	db	000h,0FEh,0AAh,0D6h,0AAh,0D6h,0AAh,0FEh	; Z
	db	000h,0FEh,0C2h,0A2h,092h,08Ah,086h,0FEh	; S
	db	000h,0FEh,0FEh,0C6h,0C6h,0C6h,0FEh,0FEh	; T
	db	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh	; Flash
	db	0AAh,055h,0AAh,055h,0AAh,055h,0AAh,055h	; Checker
	db	06Ch,0FEh,0FEh,0FEh,07Ch,038h,010h,000h	; Heart
	; Board frame: 1 dot clear by the well, 3 solid, 1 clear, a checker
	db	0AAh,055h,0AAh,040h,0AFh,04Fh,0AFh,04Eh
	db	0AAh,055h,0AAh,000h,0FFh,0FFh,0FFh,000h
	db	0AAh,055h,0AAh,005h,0F2h,0F5h,0F2h,075h
	db	0AEh,04Eh,0AEh,04Eh,0AEh,04Eh,0AEh,04Eh
	db	072h,075h,072h,075h,072h,075h,072h,075h
	db	0AEh,04Fh,0AFh,04Fh,0A0h,055h,0AAh,055h
	db	000h,0FFh,0FFh,0FFh,000h,055h,0AAh,055h
	db	072h,0F5h,0F2h,0F5h,002h,055h,0AAh,055h
	; Boxes: double lines on the outer edge
	db	0FFh,080h,0BFh,0A0h,0A0h,0A0h,0A0h,0A0h
	db	0FFh,000h,0FFh,000h,000h,000h,000h,000h
	db	0FFh,001h,0FDh,005h,005h,005h,005h,005h
	db	0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h
	db	005h,005h,005h,005h,005h,005h,005h,005h
	db	0A0h,0A0h,0A0h,0A0h,0A0h,0BFh,080h,0FFh
	db	000h,000h,000h,000h,000h,0FFh,000h,0FFh
	db	005h,005h,005h,005h,005h,0FDh,001h,0FFh
	; Background: a 4 x 4 Bayer dither, level n lights n dots of 16
	db	088h,000h,000h,000h,088h,000h,000h,000h
	db	088h,000h,022h,000h,088h,000h,022h,000h
	db	0AAh,000h,022h,000h,0AAh,000h,022h,000h
	db	0AAh,000h,0AAh,000h,0AAh,000h,0AAh,000h
	db	0AAh,044h,0AAh,000h,0AAh,044h,0AAh,000h
	db	0AAh,044h,0AAh,011h,0AAh,044h,0AAh,011h
	db	0AAh,055h,0AAh,011h,0AAh,055h,0AAh,011h
	db	0AAh,055h,0AAh,055h,0AAh,055h,0AAh,055h
	db	0EEh,055h,0AAh,055h,0EEh,055h,0AAh,055h
	db	0EEh,055h,0BBh,055h,0EEh,055h,0BBh,055h
	; Column 39: one page draws only its left half, so the right half stays blank
	db	0E0h,050h,0B0h,050h,0E0h,050h,0B0h,050h
