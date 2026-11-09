; The moving figures: each actor's 6 glyphs built
; in main RAM, then copied into font RAM and video RAM in the vertical
; blank, and the tick stub.
;
; An actor is built again only when it moved or a tile under it changed
; (A_DIRTY), at most FIGFRAME a frame, one fewer for each guard's move
; made in the frame, in the order they move, the rest the next frame. Its glyphs and its cells go in in the next blank
; (A_BUILT). Then in every blank each shown figure's codes go back into
; video RAM, in the same order, so a cell two figures share shows the
; later one, and a cell a figure left that another still covers is
; mended.

FIGFRAME equ	2		; figures built a frame, at most

; B tile row, C tile column, a tile that changed: every actor whose
; figure covers it marked to be built again. Keeps IX.
dirtyat:
	push	iy
	ld	iy,actors
	ld	de,ASIZE
	ld	a,c		; C its first field cell
	add	a,a
	ld	c,a
dy_1:	ld	a,(iy+A_ST)
	cp	S_END
	jr	z,dy_3
	ld	a,b		; the figure's rows: A_FROW and the one below
	sub	(iy+A_FROW)
	cp	2
	jr	nc,dy_2
	ld	a,(iy+A_FCOL)	; its cells: A_FCOL to A_FCOL + 2
	sub	c
	add	a,2		; the tile's 2 cells reach them: -2 to 1
	cp	4
	jr	nc,dy_2
	ld	(iy+A_DIRTY),1
dy_2:	add	iy,de
	jr	dy_1
dy_3:	pop	iy
	ret

; Builds up to FIGFRAME of the actors marked, in their order, one fewer
; for each guard's move made this frame (fmoves, guards.asm), which it
; then clears
buildsome:
	ld	ix,actors
	ld	hl,fmoves
	ld	a,FIGFRAME
	sub	(hl)
	ld	(hl),0
	ret	z
	ret	c
	ld	(nbuild),a
bs_1:	ld	a,(ix+A_ST)
	cp	S_END
	ret	z
	ld	a,(ix+A_DIRTY)
	or	a
	jr	z,bs_2
	ld	a,(ix+A_VIS)
	or	a
	jr	z,bs_2
	call	figbuild
	call	newcells
	ld	hl,nbuild
	dec	(hl)
	ret	z
bs_2:	ld	de,ASIZE
	add	ix,de
	jr	bs_1

; A the shape actor IX shows now. The step of a run, a climb or a hang
; comes from where it is, (fpx) its left edge and (fpy) its top, as
; figbuild leaves them: a running step every 4 dots, a hand over hand
; every 8, a climbing step every 4 lines.
shape:	ld	a,(ix+A_POSE)
	cp	M_DIG
	jr	nz,sh_1
	ld	a,(ix+A_FACE)
	or	a
	ld	a,FG_DIG
	jp	p,sh_9
	ld	a,FG_DIGL
	jr	sh_9
sh_1:	cp	M_FALL
	ld	a,FG_FALL
	jr	z,sh_9
	ld	a,(ix+A_POSE)
	cp	M_STAND
	ld	a,FG_STAND
	jr	z,sh_9
	ld	a,(ix+A_POSE)
	cp	M_CLIMB
	jr	nz,sh_2
	ld	a,(fpy)
	rrca
	rrca
	and	1
	add	a,FG_CLIMB0
	jr	sh_9
sh_2:	cp	M_HANG
	jr	nz,sh_3
	ld	a,(fpx)
	rrca
	rrca
	rrca
	and	1
	add	a,FG_HANG0
	jr	sh_9
sh_3:	ld	a,(fpx)		; running
	rrca
	rrca
	and	3
	ld	b,a
	ld	a,(ix+A_FACE)
	or	a
	ld	a,FG_RUN0
	jp	p,sh_4
	ld	a,FG_RUNL0
sh_4:	add	a,b
sh_9:	add	a,(ix+A_SOFF)
	ret

; FIGURE BUILDING:
; IX an actor: its 6 glyphs at A_BUF, from the tiles under it with its
; shape over them through the mask, and where it is now in A_FCOL,
; A_FROW, A_FSH and A_FLN. It is marked built and no longer dirty.
figbuild:
	ld	l,(ix+A_X)	; HL its left edge, dots from the field's left
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,(ix+A_OX)
	add	a,a
	ld	e,a
	ld	d,0
	bit	7,a
	jr	z,fb_0
	dec	d
fb_0:	add	hl,de
	ld	a,l
	ld	(fpx),a
	and	7
	ld	(ix+A_FSH),a
	ld	(fshift),a
	srl	h
	rr	l
	srl	h
	rr	l
	srl	h
	rr	l
	ld	(ix+A_FCOL),l
	ld	a,(ix+A_Y)	; its top, lines from the field's top
	add	a,a
	add	a,a
	add	a,a
	add	a,(ix+A_OY)
	ld	(fpy),a
	ld	e,a
	and	7
	ld	(ix+A_FLN),a
	ld	(fl),a
	ld	a,e
	rrca
	rrca
	rrca
	and	1Fh
	ld	(ix+A_FROW),a
	push	ix		; the tiles under it
	pop	hl
	ld	de,A_BUF
	add	hl,de
	ld	(fbase),hl
	ex	de,hl
	ld	b,(ix+A_FROW)
	call	fb_row
	inc	b
	call	fb_row
	call	shape		; HL its rows
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	de,figdata
	add	hl,de
	ld	b,8
fb_1:	push	bc
	push	hl
	ld	b,(hl)		; the row's figure and mask moved right
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	d,(hl)
	ld	h,b
	ld	l,e
	ld	e,0
	xor	a
	push	af
	ld	a,(fshift)
	or	a
	jr	z,fb_3
	ld	b,a
	pop	af
fb_2:	srl	h
	rr	l
	rr	e
	srl	c
	rr	d
	rra
	djnz	fb_2
	push	af
fb_3:	pop	af
	ld	(fm+2),a
	ld	a,c
	ld	(fm),a
	ld	a,d
	ld	(fm+1),a
	ld	a,h
	ld	(ff),a
	ld	a,l
	ld	(ff+1),a
	ld	a,e
	ld	(ff+2),a
	ld	a,(fl)		; HL the glyph row it falls on, in the top glyph
	ld	e,a		; row or the bottom one
	and	7
	bit	3,e
	jr	z,fb_4
	add	a,24
fb_4:	ld	e,a
	ld	d,0
	ld	hl,(fbase)
	add	hl,de
	ld	de,ff
	ld	b,3
fb_5:	ld	a,(de)		; mask out, figure in
	inc	de
	inc	de
	inc	de
	ld	c,a
	ld	a,(de)
	dec	de
	dec	de
	cpl
	and	(hl)
	or	c
	ld	(hl),a
	ld	a,l
	add	a,8
	ld	l,a
	jr	nc,fb_6
	inc	h
fb_6:	djnz	fb_5
	ld	hl,fl
	inc	(hl)
	pop	hl
	ld	de,4
	add	hl,de
	pop	bc
	djnz	fb_1
	ld	(ix+A_DIRTY),0
	ld	(ix+A_BUILT),1
	ret

; Field row B, field cells A_FCOL on: the 3 glyphs under them into DE.
; Keeps B.
fb_row:	ld	c,(ix+A_FCOL)
	ld	a,3
fr_1:	push	af
	push	bc
	push	de
	call	bgglyph
	pop	de
	ld	bc,8
	ldir
	pop	bc
	inc	c
	pop	af
	dec	a
	jr	nz,fr_1
	ret

; Field row B, field cell C: HL the 8 rows of the glyph scrbuf has there,
; blank outside the field
bgglyph:
	ld	hl,blank8
	ld	a,b
	cp	FROWS
	ret	nc
	ld	a,c
	cp	2*FTILES
	ret	nc
	add	a,FCOL
	ld	c,a
	ld	a,b
	add	a,FROW0
	ld	b,a
	call	bufptr
	ld	a,(hl)
	sub	80h
	jr	c,bg_1
	ld	hl,font2
	jr	bg_2
bg_1:	ld	a,(hl)
	sub	F1LO
	ld	hl,font1
bg_2:	ld	e,a
	ld	d,0
	ex	de,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,de
	ret

; Call in the vertical blank. Each actor built since the last blank: its
; glyphs into font RAM 2, the cells it left put back from scrbuf, and
; its new cells kept. An actor no longer shown: its cells put back. Then
; every shown actor's codes into its cells.
figcopy:
	ld	ix,actors
fc_1:	ld	a,(ix+A_ST)
	cp	S_END
	jr	z,fc_5
	ld	a,(ix+A_BUILT)
	or	a
	jr	nz,fc_2
	ld	a,(ix+A_VIS)
	or	a
	jr	nz,fc_4
	call	putback		; hidden
	jr	fc_4
fc_2:	ld	(ix+A_BUILT),0
	ld	a,(VLATCH)	; the glyphs
	and	0F8h
	or	W_FONT2
	ld	(VLATCH),a
	ld	l,(ix+A_CODE)
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	de,WINDOW-80h*8
	add	hl,de
	ex	de,hl
	push	ix
	pop	hl
	ld	bc,A_BUF
	add	hl,bc
	ld	bc,48
	ldir
	call	vidwin
	call	putback
	push	ix		; the new cells held
	pop	hl
	ld	de,A_NNEW
	add	hl,de
	ld	d,h
	ld	e,l
	ld	bc,-CELLS
	ex	de,hl
	add	hl,bc
	ex	de,hl
	ld	bc,CELLS
	ldir
	ld	(ix+A_REDO),1
fc_4:	ld	de,ASIZE
	add	ix,de
	jr	fc_1
fc_5:	call	vidwin		; the codes, where cells under them were
	ld	a,(drawrow)	; written, and all while the screen is drawn
	sub	ROWS
	sbc	a,a
	ld	c,a
	ld	ix,actors
fc_6:	ld	a,(ix+A_ST)
	cp	S_END
	ret	z
	ld	a,(ix+A_VIS)
	or	a
	jr	z,fc_7
	ld	a,(ix+A_REDO)
	or	c
	jr	z,fc_7
	ld	(ix+A_REDO),0
	push	bc
	call	putcodes
	pop	bc
fc_7:	ld	de,ASIZE
	add	ix,de
	jr	fc_6

; B, C a screen row and column, D rows and E columns from there: each
; figure holding cells there marked to have its codes written again.
; A figure's cells are taken as 2 rows of 3 from its first held cell,
; which may be more than it holds but never less. Keeps BC and IX.
redo:	push	iy
	ld	a,d
	inc	a
	ld	h,a		; H rows + 1, L columns + 2
	ld	a,e
	add	a,2
	ld	l,a
	ld	de,ASIZE
	ld	iy,actors
rd_1:	ld	a,(iy+A_ST)
	cp	S_END
	jr	z,rd_3
	ld	a,(iy+A_NOLD)
	or	a
	jr	z,rd_2
	ld	a,(iy+A_OROW)	; its rows B - 1 to B + D - 1
	sub	b
	inc	a
	cp	h
	jr	nc,rd_2
	ld	a,(iy+A_OCOL)	; its columns C - 2 to C + E - 1
	sub	c
	add	a,2
	cp	l
	jr	nc,rd_2
	ld	(iy+A_REDO),1
rd_2:	add	iy,de
	jr	rd_1
rd_3:	pop	iy
	ret

; IX an actor: the cells it holds put back from scrbuf, and none held.
; The window must show video RAM.
putback:
	ld	a,(ix+A_NOLD)
	or	a
	ret	z
	ld	b,(ix+A_OROW)	; the figures over them to be written again
	ld	c,(ix+A_OCOL)
	ld	de,0203h
	call	redo
	ld	b,(ix+A_NOLD)
	push	ix
	pop	hl
	ld	de,A_OLD
	add	hl,de
pk_1:	ld	e,(hl)		; video RAM
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)		; scrbuf
	inc	hl
	ld	a,(hl)
	inc	hl
	inc	hl
	push	hl
	ld	h,a
	ld	l,c
	ld	a,(hl)
	ld	(de),a
	pop	hl
	djnz	pk_1
	ld	(ix+A_NOLD),0
	ret

; IX an actor just built, in the picture: its cells in the field into
; A_NNEW, each its video RAM address through the window, its scrbuf
; address and its code, ready for figcopy
newcells:
	ld	a,(ix+A_FROW)	; the first cell, kept if it is off the field
	add	a,FROW0
	ld	(ix+A_NNEW+1),a
	ld	a,(ix+A_FCOL)
	add	a,FCOL
	ld	(ix+A_NNEW+2),a
	push	ix
	pop	hl
	ld	de,A_NNEW+3
	add	hl,de
	ld	e,(ix+A_CODE)
	ld	d,0		; cells kept
	ld	b,(ix+A_FROW)
	call	nc_row
	inc	b
	call	nc_row
	ld	(ix+A_NNEW),d
	ret
nc_row:	ld	c,(ix+A_FCOL)
	ld	a,3
nc_1:	push	af
	ld	a,b
	cp	FROWS
	jr	nc,nc_2
	ld	a,c
	cp	2*FTILES
	jr	nc,nc_2
	push	bc
	push	de
	ld	a,b
	add	a,FROW0
	ld	b,a
	ld	a,c
	add	a,FCOL
	ld	c,a
	push	hl
	call	vcell
	ex	de,hl		; DE video RAM
	call	bufptr		; HL scrbuf
	ex	(sp),hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	pop	de
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	pop	de
	ld	(hl),e		; the code
	inc	hl
	inc	d
	pop	bc
nc_2:	inc	e
	inc	c
	pop	af
	dec	a
	jr	nz,nc_1
	ret

; IX an actor: its codes into the cells it holds. The window must show
; video RAM.
putcodes:
	ld	b,(ix+A_NOLD)
	inc	b
	dec	b
	ret	z
	push	ix
	pop	hl
	ld	de,A_OLD
	add	hl,de
pc_1:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	inc	hl
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	(de),a
	djnz	pc_1
	ret

; THE TICK:
; A stub in front of the system's tick handler counts the 61 Hz ticks
; in tcount. It is copied to TSTUB, at or above 8000h, where xcpmz80
; keeps the same memory mapped whatever bank the low half shows: past
; the program's buffers, which run over 8000h with the 150 stages. It
; keeps AF: the system's handler saves the flags as it finds them, and
; an INC here left alone would change the Z flag of whatever the tick
; broke into.
stubsrc:
	disp	TSTUB
tstub:	push	af
	push	hl
	ld	hl,tcount
	inc	(hl)
	pop	hl
	pop	af
tsjump:	jp	0		; the system's handler
tcount:	db	0
	ent
STUBLEN	equ	$-stubsrc

; Puts the stub in front of the tick: the vector at I x 256 + FEh
hookon:	ld	hl,stubsrc
	ld	de,TSTUB
	ld	bc,STUBLEN
	ldir
	di
	ld	a,i
	ld	h,a
	ld	l,0FEh
	ld	(vecad),hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	(tsjump+1),de
	ld	de,TSTUB
	ld	(hl),d
	dec	hl
	ld	(hl),e
	ei
	ret

; Takes it out again
hookoff:
	di
	ld	hl,(vecad)
	ld	de,(tsjump+1)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ei
	ret
