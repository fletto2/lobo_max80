; The engine: board, gravity, lock, line clears, spawn and top-out, as
; the Game Boy game behaves. One tick a frame, in the GB's order: its scene code
; (gravity, line check, lock, collapse), then the timer, then what its
; VBlank handler does (flash passes, spawn, the row redraw). The GB
; checks lines before it writes a landed piece into the board, so the
; check comes a frame after the lock: spawn 2 frames after it, or 93
; with lines, the 7th flash pass at 62.
;
; The board is 18 rows of 10 cells, 0 empty, else the glyph that shows
; there. A piece is its code, id x 4 + rotation, and the board row and
; column of its 4x4 grid's top left. Grid cells above row 0 are free
; and never drawn.

BROWS	equ	18
BCOLS	equ	10
WELLR	equ	2		; screen row and column of board cell 0, 0
WELLC	equ	15

; States
S_FALL	equ	0		; a piece falls
S_CHECK	equ	1		; locked last frame, the line check comes
S_FLASH	equ	2		; flash passes, or the spawn when no rows
S_COLL	equ	3		; waiting to collapse
S_DRAW	equ	4		; redrawing a row a frame, 17 to 0
S_OVER	equ	5		; game over
S_TITLE	equ	6		; the title
S_SELECT equ	7		; the level select

; A new game: empty board, the first piece
newgame:
	ld	hl,board
	ld	b,BROWS*BCOLS
ng_1:	ld	(hl),0
	inc	hl
	djnz	ng_1
	ifdef	FILL
	call	fill
	endif
	ld	a,(level0)
	ld	(level),a
	xor	a
	ld	(stuck),a
	ld	a,DASINIT
	ld	(das),a
	ld	hl,0
	ld	(score),hl
	xor	a
	ld	(score+2),a
	ld	(nlines),hl
	ifdef	SCORE
	ld	hl,SCORE & 0FFFFh	; the test build's start score and lines
	ld	(score),hl
	ld	a,SCORE >> 16
	ld	(score+2),a
	endif
	ifdef	LINES
	ld	hl,LINES
	ld	(nlines),hl
	endif
	call	setspeed
	call	showstats
	ifndef	FIRST
	xor	a		; the GB's two L seeds, then three spawns (0x1A71-0x1AAC)
	ld	(pcode),a
	ld	(nextcode),a
	call	nextpiece
	call	nextpiece
	endif
	jp	spawn

; The NEXT piece becomes the current one, the hidden one NEXT, and a new
; hidden one is rolled
nextpiece:
	ld	a,(nextcode)
	ld	(pcode),a
	ifdef	FIRST
	add	a,4
	cp	28
	jr	c,np_1
	xor	a
np_1:	ld	(nextcode),a
	else
	call	roll
	endif
	jp	shownext

	ifndef	FIRST
; The GB's 1P picker (0x2041-0x2066): a candidate 4 x ((rDIV - 1) mod 7),
; rolled again when the hidden piece, it and the current one together
; are no more than the current one's type, at most 3 tries. rDIV is
; bits 8-15 of the virtual cycle count vdiv. A try reads it again as
; many cycles later as the GB's loop took: 100, 56 a pass of its count
; loop, p = rDIV - 1 passes, less 4 for each of the p / 7 wraps.
roll:	ld	a,(pcode)
	and	0FCh
	ld	c,a
	ld	b,3
	ifdef	TEST
	ld	hl,(vdiv)
	ld	(r_k),hl
	ld	a,(vdiv+2)
	ld	(r_k+2),a
	ld	a,c
	ld	(r_c),a
	endif
ro_1:	ld	a,(vdiv+1)
	dec	a
	ld	l,a		; L passes
	ld	h,0		; H wraps, passes / 7
	ld	e,a
ro_2:	ld	a,e		; E passes mod 7
	sub	7
	jr	c,ro_3
	ld	e,a
	inc	h
	jr	ro_2
ro_3:	ld	a,e
	add	a,a
	add	a,a
	ld	d,a		; D the candidate
	dec	b
	jr	z,ro_ok		; the third is taken
	ld	a,(hidden)
	or	d
	or	c
	and	0FCh
	cp	c
	jr	nz,ro_ok
	push	bc		; again, that many cycles on
	ld	a,h
	add	a,a
	add	a,a
	ld	c,a		; C 4 x wraps
	ld	h,0
	ld	d,h
	ld	e,l
	add	hl,hl
	add	hl,hl
	add	hl,hl
	or	a
	sbc	hl,de
	add	hl,hl
	add	hl,hl
	add	hl,hl		; 56 x passes
	ld	de,100
	add	hl,de
	ld	e,c
	ld	d,0
	or	a
	sbc	hl,de
	call	addvdiv
	pop	bc
	jr	ro_1
ro_ok:	ld	a,(hidden)
	ld	(nextcode),a
	ld	a,d
	ld	(hidden),a
	ifdef	TEST
	ld	bc,21*256+26
	ld	a,(r_k+2)
	call	sethex
	ld	a,(r_k+1)
	call	sethex
	ld	a,(r_k)
	call	sethex
	inc	c
	ld	a,(r_c)
	call	sethex
	ld	a,(nextcode)
	call	sethex
	ld	a,(hidden)
	call	sethex
	endif
	ret
	endif

; A frame of the GB's: 70224 cycles on the virtual count
clock:	ld	hl,70224 & 0FFFFh
	call	addvdiv
	ld	hl,vdiv+2
	inc	(hl)		; 70224 is 11250h
	ret

; HL onto vdiv
addvdiv:
	ld	a,(vdiv)
	add	a,l
	ld	(vdiv),a
	ld	a,(vdiv+1)
	adc	a,h
	ld	(vdiv+1),a
	ret	nc
	ld	a,(vdiv+2)
	inc	a
	ld	(vdiv+2),a
	ret

; The NEXT window: the piece in rotation 0, centered to the dot under
; NEXT, or blank while hidden. The piece is drawn into the 12 glyphs
; G_NEXT on, shown in rows 4-6 and columns 30-33, centered in them: an
; offset of 16 - 4 x its width dots across and 12 - 4 x its height lines
; down.
shownext:
	ld	a,(nexthide)
	or	a
	jp	nz,nextoff
	ld	hl,nbuf
	ld	b,12*8
sn_0:	ld	(hl),0
	inc	hl
	djnz	sn_0
	ld	a,(nextcode)	; its glyph, from our table
	and	0FCh
	add	a,a
	ld	e,a
	ld	d,0
	ld	hl,glyphs
	add	hl,de
	ld	(sn_g),hl
	ld	a,(nextcode)	; its cells
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	de,pcells
	add	hl,de
	ld	(sn_p),hl
	push	hl		; the bounds: rows D to E, columns B to C
	pop	ix
	ld	h,4
	ld	de,0FF00h
	ld	bc,0FF00h
sn_1:	ld	a,(ix+0)
	cp	d
	jr	nc,$+3
	ld	d,a
	cp	e
	jr	c,$+3
	ld	e,a
	ld	a,(ix+1)
	cp	b
	jr	nc,$+3
	ld	b,a
	cp	c
	jr	c,$+3
	ld	c,a
	inc	ix
	inc	ix
	dec	h
	jr	nz,sn_1
	ld	a,c		; dots across: 12 - 4 x (C - B), less the first column's
	sub	b
	add	a,a
	add	a,a
	neg
	add	a,12
	ld	c,a
	ld	a,b
	add	a,a
	add	a,a
	add	a,a
	neg
	add	a,c
	ld	(sn_xo),a
	ld	a,e		; lines down: 8 - 4 x (E - D), less the first row's
	sub	d
	add	a,a
	add	a,a
	neg
	add	a,8
	ld	e,a
	ld	a,d
	add	a,a
	add	a,a
	add	a,a
	neg
	add	a,e
	ld	(sn_yo),a
	ld	ix,(sn_p)
	ld	a,4
sn_2:	ld	(sn_n),a
	ld	a,(ix+0)	; the block's top line
	add	a,a
	add	a,a
	add	a,a
	ld	hl,sn_yo
	add	a,(hl)
	ld	(sn_y),a
	ld	a,(ix+1)	; its left dot, a multiple of 4
	add	a,a
	add	a,a
	add	a,a
	ld	hl,sn_xo
	add	a,(hl)
	ld	c,a
	ld	de,(sn_g)
	ld	b,8
sn_3:	ld	a,(sn_y)	; glyph (y / 8) x 4 + x / 8, its line y and 7
	ld	l,a
	and	7
	ld	h,a
	ld	a,l
	and	18h
	add	a,a
	add	a,a
	add	a,h
	ld	h,a
	ld	a,c
	and	18h
	add	a,h
	ld	l,a
	ld	h,0
	push	de
	ld	de,nbuf
	add	hl,de
	pop	de
	ld	a,(de)
	bit	2,c
	jr	nz,sn_4
	or	(hl)
	ld	(hl),a
	jr	sn_5
sn_4:	push	af		; half a cell over: into this glyph and the next
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	or	(hl)
	ld	(hl),a
	pop	af
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	push	de
	ld	de,8
	add	hl,de
	pop	de
	or	(hl)
	ld	(hl),a
sn_5:	inc	de
	ld	hl,sn_y
	inc	(hl)
	djnz	sn_3
	inc	ix
	inc	ix
	ld	a,(sn_n)
	dec	a
	jr	nz,sn_2
	di
	ld	a,(VLATCH)
	push	af
	and	0F8h
	or	W_FONT2
	ld	(VLATCH),a
	ld	hl,nbuf
	ld	de,WINDOW+(G_NEXT-80h)*8
	ld	bc,12*8
	ldir
	pop	af
	ld	(VLATCH),a
	ei
	ld	a,G_NEXT
	ld	d,1
	jr	nc_1

; The NEXT piece's 12 cells blank
nextoff:
	ld	a,' '
	ld	d,0

; A the first code, D 1 to count up or 0 to repeat it
nc_1:	ld	bc,4*256+30
nc_2:	ld	e,4
nc_3:	push	af
	push	bc
	push	de
	call	setcell
	pop	de
	pop	bc
	pop	af
	add	a,d
	inc	c
	dec	e
	jr	nz,nc_3
	ld	c,30
	inc	b
	ld	e,a
	ld	a,b
	cp	7
	ld	a,e
	jr	nz,nc_2
	ret

; ENTER pauses, the GB's START, and SPACE, its SELECT, shows or hides
; NEXT, also while paused (InGameCheckResetAndPause, 0x1BF4-0x1C68). Only
; in play, and not while a wipe runs.
pausekeys:
	ld	a,(state)
	cp	S_OVER
	ret	nc
	ld	a,(wipe)
	or	a
	ret	nz
	ld	a,(press)
	bit	K_PAUSE,a
	jr	nz,pk_1
	bit	K_NEXT,a
	ret	z
	ld	a,(nexthide)
	xor	1
	ld	(nexthide),a
	jp	shownext
pk_1:	ld	a,(paused)
	xor	1
	ld	(paused),a
	ld	a,W_PAUSE
	jr	nz,startwipe
	ld	a,W_RESUME

; A the wipe's mode: the well over 3 frames, 6 rows a frame, blank or the
; board's own cells, then what the mode draws. The game waits meanwhile.
startwipe:
	ld	(wmode),a
	ld	a,3
	ld	(wipe),a
	ret

W_PAUSE	equ	1		; then PAUSE, NEXT hidden, as the GB's pause screen
W_RESUME equ	2		; the board, then the piece and NEXT
W_TITLE	equ	3		; then the title
W_SELECT equ	4		; then the level select
W_GAME	equ	5		; then a new game

wipestep:
	ld	a,(wipe)
	ld	b,a
	ld	a,3
	sub	b
	ld	b,a
	add	a,a
	add	a,b
	add	a,a		; the first of 6 rows
	ld	b,a
	ld	e,6
ws_1:	push	bc
	push	de
	ld	a,(wmode)
	cp	W_RESUME
	ld	d,' '
	jr	nz,ws_2
	ld	d,0		; the board's own cells
ws_2:	call	putrow
	pop	de
	pop	bc
	inc	b
	dec	e
	jr	nz,ws_1
	ld	hl,wipe
	dec	(hl)
	ret	nz
	ld	a,(wmode)
	cp	W_PAUSE
	jr	z,ws_pause
	cp	W_TITLE
	jr	z,drawtitle
	cp	W_SELECT
	jp	z,drawselect
	cp	W_GAME
	jp	z,newgame
	call	msgoff	; W_RESUME
	call	shownext
	ld	a,(state)
	cp	S_FALL
	ret	nz
	jp	show
ws_pause:
	call	nextoff
	ld	hl,m_pause
	jp	msgshow

; The title, in the well: ENTER goes on to the level select, with DOWN
; held hard mode, which stays on until the program ends, as the GB's
; hIsHardMode does until a reset (0x04E8-0x04EE)
drawtitle:
	call	nextoff
	ld	hl,t_title
	jp	centers
title:	ld	a,(press)
	bit	K_PAUSE,a
	ret	z
	ld	a,(held)
	bit	K_DOWN,a
	jr	z,ti_1
	ld	a,1
	ld	(hard),a
ti_1:	ld	a,S_SELECT
	ld	(state),a
	ld	a,W_SELECT
	jp	startwipe

; The level select, levels 0-4 over 5-9, the GB's
; GameState11_ATypeSelectionMain (0x15BF-0x1613): RIGHT and LEFT a level
; within 0-9, UP and DOWN 5 between the rows. ENTER starts the game, Z
; goes back to the title. The level stays from game to game.
drawselect:
	ld	hl,m_level
	ld	b,4+WELLR
	call	center
	ld	hl,t_select
	call	putstrs
	ld	a,(hard)
	or	a
	ld	a,G_HEART
	ld	bc,14*256+WELLC+4
	call	nz,setcell
	ld	a,'>'
	jr	selmark
select:	ld	a,(press)
	ld	b,a
	bit	K_PAUSE,b
	ld	a,W_GAME
	jp	nz,startwipe
	bit	K_ROTB,b
	jr	z,se_1
	ld	a,S_TITLE
	ld	(state),a
	ld	a,W_TITLE
	jp	startwipe
se_1:	ld	a,(level0)
	ld	c,a
	bit	K_RIGHT,b
	jr	z,se_2
	cp	9
	ret	z
	inc	a
	jr	se_5
se_2:	bit	K_LEFT,b
	jr	z,se_3
	or	a
	ret	z
	dec	a
	jr	se_5
se_3:	bit	K_ROTA,b	; UP
	jr	z,se_4
	cp	5
	ret	c
	sub	5
	jr	se_5
se_4:	bit	K_DOWN,b
	ret	z
	cp	5
	ret	nc
	add	a,5
se_5:	push	af
	ld	a,' '		; the mark off the old level, on the new
	call	selmark
	pop	af
	ld	(level0),a
	ld	a,'>'

; A at the mark's place, left of level (level0) in the select
selmark:
	push	af
	ld	a,(level0)
	ld	b,8+WELLR
	cp	5
	jr	c,sm_1
	sub	5
	ld	b,10+WELLR
sm_1:	add	a,a
	add	a,WELLC
	ld	c,a
	pop	af
	jp	setcell

; After GAME OVER, ENTER goes back to the level select
overkeys:
	ld	a,(press)
	bit	K_PAUSE,a
	ret	z
	call	msgoff		; GAME OVER off
	ld	a,S_SELECT
	ld	(state),a
	ld	a,W_SELECT
	jp	startwipe

; HL a message ending in 0, at most 10 letters: the message box under
; the board, rows 21-23 and columns 14-25, the text centered in its 10
; columns, through the change list
msgshow:
	push	hl
	ld	ix,setcell
	ld	bc,21*256+14
	ld	de,23*256+25
	ld	a,G_BOX
	call	boxdraw
	pop	hl
	ld	b,22

; HL a text ending in 0, at most 10 letters, centered in the well's 10
; columns on row B, through the change list. Returns HL past the 0.
center:	ld	d,b
	push	hl
	ld	b,0		; its length
ms_1:	ld	a,(hl)
	or	a
	jr	z,ms_2
	inc	b
	inc	hl
	jr	ms_1
ms_2:	inc	hl
	ex	(sp),hl
	ld	a,10
	sub	b
	srl	a		; the blank cells before it, carry when odd
	jr	c,ms_3
	add	a,WELLC
	ld	c,a
	ld	b,d
	call	putstr
	pop	hl
	ret
ms_3:	add	a,WELLC
	push	af
	push	bc
	push	de
	call	msgglyphs
	pop	de
	pop	bc
	pop	af
	ld	c,a
	ld	a,b		; B + 1 cells, G_MSG on
	inc	a
	ld	e,a
	ld	b,d
	ld	a,G_MSG
ms_4:	push	af
	push	bc
	push	de
	call	setcell
	pop	de
	pop	bc
	pop	af
	inc	a
	inc	c
	dec	e
	jr	nz,ms_4
	pop	hl
	ret

; HL texts as center takes them, each after its row, a row of FFh ends
; them. One at most may be odd, its glyphs are made fresh each time.
centers:
	ld	a,(hl)
	cp	0FFh
	ret	z
	ld	b,a
	inc	hl
	call	center
	jr	centers

; The message box off: the background back over it
msgoff:	ld	bc,21*256+14
mo_1:	push	bc
	call	bgcode
	call	setcell
	pop	bc
	inc	c
	ld	a,c
	cp	26
	jr	nz,mo_1
	ld	c,14
	inc	b
	ld	a,b
	cp	24
	jr	nz,mo_1
	ret

; HL texts as putstr takes them, each after its row and column, a row
; of FFh ends them
putstrs:
	ld	a,(hl)
	cp	0FFh
	ret	z
	ld	b,a
	inc	hl
	ld	c,(hl)
	inc	hl
	call	putstr
	inc	hl
	jr	putstrs

; HL a text ending in 0 at row B from column C, through the change list.
; Returns HL on the 0.
putstr:	ld	a,(hl)
	or	a
	ret	z
	push	hl
	push	bc
	call	setcell
	pop	bc
	pop	hl
	inc	hl
	inc	c
	jr	putstr

m_pause: db	"PAUSE",0
m_level: db	"LEVEL",0
t_title: db	6+WELLR,"TETRIS",0
	db	11+WELLR,"ENTER",0
	db	12+WELLR,"TO START",0
	db	0FFh
t_select:
	db	8+WELLR,WELLC+1,"0 1 2 3 4",0
	db	10+WELLR,WELLC+1,"5 6 7 8 9",0
	db	0FFh

; The speed for the level, plus 10 in hard mode up to 20, from the lifted
; table (0x1AE8)
setspeed:
	ld	a,(hard)
	or	a
	ld	a,(level)
	jr	z,ss_0
	add	a,10
	cp	21
	jr	c,ss_0
	ld	a,20
ss_0:	ld	hl,speeds
	add	a,l
	ld	l,a
	jr	nc,ss_1
	inc	h
ss_1:	ld	a,(hl)
	ld	(speed),a
	ret

; One frame
tick:	ld	a,(state)
	cp	S_OVER
	jp	z,overkeys
	cp	S_TITLE
	jp	z,title
	cp	S_SELECT
	jp	z,select
	cp	S_CHECK		; a lock is checked the frame after, as on the GB
	call	z,lines
	ld	a,(state)
	cp	S_FALL
	call	z,move
	ld	a,(state)
	cp	S_FALL
	call	z,gravity
	ld	a,(state)
	cp	S_COLL
	jr	nz,tc_1
	ld	a,(timer)
	or	a
	call	z,collapse
tc_1:	ld	hl,timer	; the GB's hTimer1 and hTimer2
	ld	a,(hl)
	or	a
	jr	z,tc_4
	dec	(hl)
tc_4:	ld	hl,timer2
	ld	a,(hl)
	or	a
	jr	z,tc_2
	dec	(hl)
tc_2:	ld	a,(state)
	cp	S_FLASH
	jr	nz,tc_3
	ld	a,(timer)
	or	a
	call	z,flash
tc_3:	ld	a,(state)
	cp	S_DRAW
	call	z,redraw
	ret

; Rotation, then the sideways move, as the GB's InGameCheckButtonsPressed
; (0x24BB-0x2571). Z, the GB's B, is checked first and adds 1 to the
; rotation, counterclockwise on screen, UP, the GB's A, takes 1, clockwise. A rotation that collides is put
; back, no kicks. RIGHT wins over LEFT. A press moves at once and arms
; the shared repeat counter with DASINIT, a held key counts it down and
; moves at 0 with DASREP, a blocked move puts it at DASBLK, and neither
; held puts it at DASINIT. The piece is drawn again only when it moved.
move:	ld	a,(pcol)
	ld	(oldcol),a
	ld	a,(pcode)
	ld	(oldcode),a
	ld	c,a
	ld	a,(press)
	bit	K_ROTB,a
	jr	nz,mv_b
	bit	K_ROTA,a
	jr	z,mv_side
	ld	a,c		; A: rotation - 1, 0 to 3
	and	3
	ld	a,c
	jr	z,mv_a3
	dec	a
	jr	mv_rot
mv_a3:	or	3
	jr	mv_rot
mv_b:	ld	a,c		; B: rotation + 1, 3 to 0
	and	3
	cp	3
	ld	a,c
	jr	z,mv_b0
	inc	a
	jr	mv_rot
mv_b0:	and	0FCh
mv_rot:	ld	(pcode),a
	push	bc
	call	collide
	pop	bc
	jr	nc,mv_side
	ld	a,c
	ld	(pcode),a
mv_side:
	ld	a,(pcol)
	ld	(sidecol),a
	ld	a,(held)
	ld	c,a
	ld	a,(press)
	ld	b,a
	bit	K_RIGHT,b
	ld	a,DASINIT
	jr	nz,mv_r
	bit	K_RIGHT,c
	jr	z,mv_left
	ld	hl,das
	dec	(hl)
	jr	nz,mv_done
	ld	a,DASREP
mv_r:	ld	(das),a
	ld	hl,pcol
	inc	(hl)
	jr	mv_try
mv_left:
	bit	K_LEFT,b
	ld	a,DASINIT
	jr	nz,mv_l
	bit	K_LEFT,c
	jr	z,mv_set
	ld	hl,das
	dec	(hl)
	jr	nz,mv_done
	ld	a,DASREP
mv_l:	ld	(das),a
	ld	hl,pcol
	dec	(hl)
mv_try:
	ifdef	TEST
	ld	hl,(frames)
	ld	(t_try),hl
	endif
	call	collide
	jr	c,mv_back
	ifdef	TEST
	ld	hl,(frames)
	ld	(t_move),hl
	endif
	jr	mv_done
mv_back:
	ld	a,(sidecol)
	ld	(pcol),a
	ld	a,DASBLK
mv_set:	ld	(das),a
mv_done:
	ld	a,(pcol)	; moved: off at the old place, on at the new
	ld	b,a
	ld	a,(oldcol)
	cp	b
	ld	a,(pcode)
	ld	c,a
	jr	nz,mv_draw
	ld	a,(oldcode)
	cp	c
	ret	z
mv_draw:
	push	bc
	ld	a,(oldcol)
	ld	(pcol),a
	ld	a,(oldcode)
	ld	(pcode),a
	call	unshow
	pop	bc
	ld	a,b
	ld	(pcol),a
	ld	a,c
	ld	(pcode),a
	jp	show

; The GB's InGameHandlePieceFalling (0x2071-0x2126). With DOWN the only
; direction held, a soft drop: a row every 3 frames on timer2, counted,
; the natural counter left alone. After a landing DOWN must be pressed
; again first (candown, the GB's $C0C7). Otherwise the natural counter
; counts down, and at 0 drops a row and is armed again. A landing after
; soft drop rows scores the count less 1.
gravity:
	ld	a,(held)
	and	(1<<K_DOWN)|(1<<K_LEFT)|(1<<K_RIGHT)
	cp	1<<K_DOWN
	jr	nz,gr_nat
	ld	a,(candown)
	or	a
	jr	z,gr_soft
	ld	a,(press)
	and	(1<<K_DOWN)|(1<<K_LEFT)|(1<<K_RIGHT)
	cp	1<<K_DOWN
	jr	nz,gr_nat
	xor	a
	ld	(candown),a
gr_soft:
	ld	a,(timer2)
	or	a
	ret	nz
	ld	a,3
	ld	(timer2),a
	ld	hl,sdcount
	inc	(hl)
	jr	gr_drop
gr_nat:	xor	a
	ld	(sdcount),a
	ld	a,(dropctr)
	or	a
	jr	z,gr_1
	dec	a
	ld	(dropctr),a
	ret
gr_1:	ld	a,(speed)
	ld	(dropctr),a
gr_drop:
	call	unshow
	ld	hl,prow
	inc	(hl)
	call	collide
	jr	c,gr_2
	ifdef	TEST
	ld	hl,(frames)
	ld	(t_drop),hl
	endif
	jp	show
gr_2:	ld	hl,prow		; landed: back up a row and lock
	dec	(hl)
	call	show
	ifdef	TEST
	ld	hl,(frames)
	ld	(t_lock),hl
	endif
	call	lock
	ld	a,S_CHECK
	ld	(state),a
	ld	a,1
	ld	(candown),a
	ld	a,(sdcount)	; soft drop points, the count less 1
	or	a
	jr	z,gr_3
	dec	a
	ld	l,a
	ld	h,0
	call	addscore
	call	showscore
	xor	a
	ld	(sdcount),a
gr_3:	ld	a,(prow)	; at the unmoved spawn place: top-out
	cp	SPAWNR
	ret	nz
	ld	a,(pcol)
	cp	SPAWNC
	ret	nz
	ld	hl,stuck
	ld	a,(hl)
	or	a
	jr	nz,gameover
	inc	(hl)		; the first time is a grace lock
	ret

	ifdef	PIECES
gamestop:
	ld	a,S_OVER
	ld	(state),a
	ret
	endif

gameover:
	ld	a,S_OVER
	ld	(state),a
	ld	hl,m_over
	jp	msgshow

; Writes the piece into the board
lock:	ld	a,(pcode)
	call	cells
lk_1:	push	bc
	ld	a,(hl)		; row
	add	a,d
	inc	hl
	ld	b,a
	ld	a,(hl)
	add	a,e
	inc	hl
	ld	c,a
	ld	a,b
	or	a
	jp	m,lk_2		; above the board
	push	hl
	call	bptr
	ld	a,(pglyph)
	ld	(hl),a
	pop	hl
lk_2:	pop	bc
	djnz	lk_1
	ret

; Rows 2-17 full go into lrows, top first, nrows of them. Then 2 frames
; to the spawn or the first flash pass.
lines:	xor	a
	ld	(nrows),a
	ld	(pass),a
	ld	hl,lrows
	ld	b,2
ln_1:	push	hl
	push	bc
	ld	c,0
	call	bptr
	ld	b,BCOLS
ln_2:	ld	a,(hl)
	or	a
	jr	z,ln_3
	inc	hl
	djnz	ln_2
ln_3:	pop	bc
	pop	hl
	jr	z,ln_4		; a hole
	ld	(hl),b
	inc	hl
	ld	a,(nrows)
	inc	a
	ld	(nrows),a
ln_4:	inc	b
	ld	a,b
	cp	BROWS
	jr	nz,ln_1
	ld	a,(nrows)	; lines, up to 9999
	ld	hl,(nlines)
	add	a,l
	ld	l,a
	jr	nc,ln_5
	inc	h
ln_5:	ld	de,10000
	push	hl
	or	a
	sbc	hl,de
	pop	hl
	jr	c,ln_6
	ld	hl,9999
ln_6:	ld	(nlines),hl
	ld	a,2
	ld	(timer),a
	ld	a,S_FLASH
	ld	(state),a
	ret

; With no rows, the spawn. Else one of 7 passes 10 frames apart: the
; even ones flash, the odd ones show the rows again, the last blanks
; them. Pass n beeps when n < nrows, one beep a line.
flash:	ld	a,(nrows)
	or	a
	jp	z,spawn
	ld	a,(pass)
	ld	c,a
	ld	a,(nrows)
	dec	a
	cp	c
	jr	c,fl_1
	ld	(BEEP),a
fl_1:	ld	a,(nrows)
	ld	b,a
	ld	hl,lrows
fl_2:	push	bc
	push	hl
	ld	b,(hl)
	ld	a,(pass)
	cp	6
	ld	d,' '
	jr	z,fl_3
	rrca
	ld	d,G_FLASH
	jr	nc,fl_3
	ld	d,0		; the board's own cells
fl_3:	call	putrow
	pop	hl
	pop	bc
	inc	hl
	djnz	fl_2
	ld	hl,pass
	inc	(hl)
	ld	a,(hl)
	cp	7
	ld	a,10
	jr	nz,fl_4
	ld	a,S_COLL
	ld	(state),a
	ld	a,13
fl_4:	ld	(timer),a
	ret

; The full rows leave the board, top first, each one by moving every
; row above it down one and emptying row 0. The redraw starts.
collapse:
	ld	a,(nrows)
	ld	b,a
	ld	hl,lrows
co_1:	push	bc
	push	hl
	ld	b,(hl)
	ld	c,0
	call	bptr		; HL the full row
	push	hl
	ld	de,board
	or	a
	sbc	hl,de
	ld	b,h		; BC the cells above it
	ld	c,l
	pop	hl
	ld	de,BCOLS-1
	ex	de,hl
	add	hl,de
	ex	de,hl		; DE the full row's last cell
	dec	hl		; HL the last cell above it
	ld	a,b
	or	c
	jr	z,co_2
	lddr
co_2:	ld	hl,board
	ld	b,BCOLS
co_3:	ld	(hl),0
	inc	hl
	djnz	co_3
	pop	hl
	pop	bc
	inc	hl
	djnz	co_1
	ld	a,S_DRAW
	ld	(state),a
	ld	a,BROWS-1
	ld	(rrow),a
	ret

; One row of the board onto the screen a frame, 17 up to 0, then the
; spawn
redraw:	ld	a,(rrow)
	cp	14		; the GB's redraw stage 5: the line score
	call	z,linescore
	ld	a,(rrow)
	cp	3		; stage 16: the level
	call	z,levelup
	ld	a,(rrow)
	cp	2		; stage 17: the lines shown
	call	z,showlines
	ld	a,(rrow)
	ld	b,a
	ld	d,0
	call	putrow
	ld	hl,rrow
	ld	a,(hl)
	or	a
	jp	z,spawn
	dec	(hl)
	ret

; The clear's score, its constant times level + 1 (0x1F91)
linescore:
	ld	a,(nrows)
	dec	a
	add	a,a
	ld	e,a
	ld	d,0
	ld	hl,scores
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	a,(level)
	inc	a
ls_1:	push	af
	push	de
	ex	de,hl
	call	addscore
	pop	de
	pop	af
	dec	a
	jr	nz,ls_1
	jp	showscore

; Up a level when lines / 10 passes it, below 20 and 1000 lines
; (0x244B), the speed with it
levelup:
	ld	a,(level)
	cp	20
	ret	z
	ld	b,a
	ld	hl,(nlines)
	ld	de,1000
	or	a
	sbc	hl,de
	ret	nc
	add	hl,de
	ld	c,0		; C = lines / 10
	ld	de,10
lu_1:	or	a
	sbc	hl,de
	jr	c,lu_2
	inc	c
	jr	lu_1
lu_2:	ld	a,b
	cp	c
	ret	nc
	inc	a
	ld	(level),a
	call	setspeed
	ld	a,(speed)
	ld	(dropctr),a
	jp	showlevel

; HL points onto the score, up to 999,999
addscore:
	ld	a,(score)
	add	a,l
	ld	(score),a
	ld	a,(score+1)
	adc	a,h
	ld	(score+1),a
	ld	a,(score+2)
	adc	a,0
	ld	(score+2),a
	ld	hl,score	; 1,000,000 is 0F4240h
	ld	a,(hl)
	sub	40h
	inc	hl
	ld	a,(hl)
	sbc	a,42h
	inc	hl
	ld	a,(hl)
	sbc	a,0Fh
	ret	c
	ld	hl,999999 & 0FFFFh
	ld	(score),hl
	ld	a,999999 >> 16
	ld	(score+2),a
	ret

; The numbers under their labels
showstats:
	call	showscore
	call	showlines
showlevel:
	ld	a,(hard)	; a heart after it in hard mode, as the GB's
	or	a
	ld	a,G_HEART
	jr	nz,sl_1
	ld	a,' '
sl_1:	ld	bc,9*256+9
	call	setcell
	ld	a,(level)
	ld	l,a
	ld	h,0
	ld	bc,9*256+3
	jr	putnum16
showlines:
	ld	hl,(nlines)
	ld	bc,6*256+3
putnum16:
	ld	(num),hl
	xor	a
	ld	(num+2),a
	jr	putnum
showscore:
	ld	hl,(score)
	ld	(num),hl
	ld	a,(score+2)
	ld	(num+2),a
	ld	bc,3*256+3

; num, 24 bits, in 6 places at row B from column C through the change
; list, the leading zeros blank. num ends 0.
putnum:	ld	(numrc),bc
	ld	hl,pow10
	ld	e,6
	ld	d,0		; a digit not 0 seen
pn_1:	ld	c,'0'-1
pn_2:	inc	c
	ld	a,(num)
	sub	(hl)
	ld	(num),a
	inc	hl
	ld	a,(num+1)
	sbc	a,(hl)
	ld	(num+1),a
	inc	hl
	ld	a,(num+2)
	sbc	a,(hl)
	ld	(num+2),a
	dec	hl
	dec	hl
	jr	nc,pn_2
	ld	a,(num)		; one too many: back
	add	a,(hl)
	ld	(num),a
	inc	hl
	ld	a,(num+1)
	adc	a,(hl)
	ld	(num+1),a
	inc	hl
	ld	a,(num+2)
	adc	a,(hl)
	ld	(num+2),a
	inc	hl
	ld	a,c
	cp	'0'
	jr	nz,pn_3
	ld	a,d
	or	a
	jr	nz,pn_4
	ld	a,e
	dec	a
	ld	a,' '
	jr	nz,pn_5
pn_3:	ld	d,1
pn_4:	ld	a,c
pn_5:	push	hl
	push	de
	ld	bc,(numrc)
	push	bc
	call	setcell
	pop	bc
	inc	c
	ld	(numrc),bc
	pop	de
	pop	hl
	dec	e
	jr	nz,pn_1
	ret

pow10:	d24	100000, 10000, 1000, 100, 10, 1

; Row B through the change list: every cell D, or the board's own when
; D is 0
putrow:	ld	c,0
pr_1:	push	bc
	push	de
	ld	a,d
	or	a
	jr	nz,pr_2
	call	bptr
	ld	a,(hl)
	or	a
	jr	nz,pr_2
	ld	a,' '
pr_2:	push	af
	ld	a,b
	add	a,WELLR
	ld	b,a
	ld	a,c
	add	a,WELLC
	ld	c,a
	pop	af
	call	setcell
	pop	de
	pop	bc
	inc	c
	ld	a,c
	cp	BCOLS
	jr	nz,pr_1
	ret

; The next piece at the spawn place, rotation 0, the drop counter armed:
; the GB's PlayNextPieceLoadNextAndHiddenPiece (0x2007)
spawn:
	ifdef	TEST
	ld	hl,(frames)	; frames from the lock, and from a lock that cleared
	ld	de,(t_lock)
	or	a
	sbc	hl,de
	ld	a,l
	ld	(t_gap),a
	ld	a,(nrows)
	or	a
	jr	z,sp_2
	ld	a,l
	ld	(t_cgap),a
sp_2:
	endif
	ifdef	PIECES
	ld	hl,npieces	; the test build stops after this many pieces
	ld	a,(hl)
	cp	PIECES
	jp	nc,gamestop
	inc	(hl)
	endif
	call	nextpiece
	ld	a,(pcode)
	rrca
	rrca
	add	a,G_L
	ld	(pglyph),a
	ld	a,SPAWNR
	ld	(prow),a
	ld	a,SPAWNC
	ld	(pcol),a
	ld	a,(speed)
	ld	(dropctr),a
	xor	a
	ld	(state),a
	ifdef	TEST
	ld	hl,(frames)
	ld	(t_spawn),hl
	endif
	jr	show

; The piece on the screen, or off it (its cells show the board again)
show:	ld	a,(pglyph)
	jr	sh_0
unshow:	xor	a
sh_0:	ld	(drawg),a
	ld	a,(pcode)
	call	cells
sw_1:	push	bc
	ld	a,(hl)
	add	a,d
	jp	m,sw_3		; above the board
	ld	b,a
	inc	hl
	ld	a,(hl)
	dec	hl
	add	a,e
	ld	c,a
	push	hl
	push	de
	ld	a,(drawg)
	or	a
	jr	nz,sw_2
	push	bc
	call	bptr
	pop	bc
	ld	a,(hl)
	or	a
	jr	nz,sw_2
	ld	a,' '
sw_2:	push	af
	ld	a,b
	add	a,WELLR
	ld	b,a
	ld	a,c
	add	a,WELLC
	ld	c,a
	pop	af
	call	setcell
	pop	de
	pop	hl
sw_3:	inc	hl
	inc	hl
	pop	bc
	djnz	sw_1
	ret

; Carry set when the piece overlaps a wall, the floor or a cell
collide:
	ld	a,(pcode)
	call	cells
cl_1:	push	bc
	ld	a,(hl)		; row
	add	a,d
	inc	hl
	ld	c,a
	ld	a,(hl)		; column
	add	a,e
	inc	hl
	cp	BCOLS		; left of 0 is 80h-FFh, not below 10 either
	jr	nc,cl_hit
	ld	b,a
	ld	a,c
	or	a
	jp	m,cl_2		; above the board, free
	cp	BROWS
	jr	nc,cl_hit
	push	hl
	ld	c,b
	ld	b,a
	call	bptr
	ld	a,(hl)
	pop	hl
	or	a
	jr	nz,cl_hit
cl_2:	pop	bc
	djnz	cl_1
	or	a
	ret
cl_hit:	pop	bc
	scf
	ret

; A the piece code: HL its 4 cells as row, column in the grid, D and E
; the grid's board row and column, B 4
cells:	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	de,pcells
	add	hl,de
	ld	a,(prow)
	ld	d,a
	ld	a,(pcol)
	ld	e,a
	ld	b,4
	ret

; B row, C column: HL the board cell. Keeps BC and DE.
bptr:	push	de
	ld	l,b
	ld	h,0
	add	hl,hl
	ld	d,h
	ld	e,l
	add	hl,hl
	add	hl,hl
	add	hl,de		; row x 10
	ld	e,c
	ld	d,0
	add	hl,de
	ld	de,board
	add	hl,de
	pop	de
	ret

	ifdef	FILL
; Test boards for the emulator tests: FILL n picks one. Each row: the board
; row, then its 10 cells, a row number of FFh ends it.
fill:	ld	hl,fills
	ld	b,FILL
fi_1:	dec	b
	jr	z,fi_3
fi_2:	ld	a,(hl)		; skip a board
	inc	hl
	cp	0FFh
	jr	z,fi_1
	ld	de,BCOLS
	add	hl,de
	jr	fi_2
fi_3:	ld	a,(hl)
	inc	hl
	cp	0FFh
	ret	z
	push	hl
	ld	b,a
	ld	c,0
	call	bptr
	ex	de,hl
	pop	hl
	ld	bc,BCOLS
	ldir
	jr	fi_3

W	equ	G_WALL
fills:	; 1: row 17 full but for columns 2-5, where the I lands
	db	17, W,W,0,0,0,0,W,W,W,W
	db	0FFh
	; 2: rows 16 and 17 full but where the L lands, and row 15 not
	db	15, W,0,0,0,0,0,0,0,0,W
	db	16, W,W,0,0,0,W,W,W,W,W
	db	17, W,W,0,W,W,W,W,W,W,W
	db	0FFh
	; 3: one cell where the L's rotation 1 would go, at the spawn
	db	1, 0,0,0,0,W,0,0,0,0,0
	db	0FFh
	; 4: rows 14-17 full but column 3, where an upright I drops
	db	14, W,W,W,0,W,W,W,W,W,W
	db	15, W,W,W,0,W,W,W,W,W,W
	db	16, W,W,W,0,W,W,W,W,W,W
	db	17, W,W,W,0,W,W,W,W,W,W
	db	0FFh
	endif

m_over:	db	"GAME OVER",0
