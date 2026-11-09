; Gold, the hidden ladders and the end of a stage, from PHYSICS.md through the
; JavaScript model.
;
; The runner takes gold when its middle is near its tile's, 250 points.
; A guard picks it up the same way, when it has none and has waited out
; GOLDCOOL moves since it last dropped some, and carries it CARRYMIN to
; CARRYMIN + 51 moves. Then it drops it where it stands, on an empty tile
; held up from below. Held in a hole, it drops it on the rim, or climbing
; out, as it steps off. A guard killed with gold loses it. With no gold
; left, on the field or carried, the hidden ladders show, and the runner
; standing on row 0 ends the stage: 1500 points counted up in 100s, a
; life more, and the next stage, stage 1 again after the last at the
; next difficulty, up to MAXDIFF.
;
; A tile changed in play goes through settile: into tiles and scrbuf,
; the figures over it built again, and onto a queue that tilecopy
; empties into video RAM, TQFRAME pairs a blank.

TQSIZE	equ	64		; changed tiles waiting, a power of 2
TQFRAME	equ	8		; copied a blank

; B tile row, C tile column, A a tile kind: into tiles and scrbuf, and
; queued to be copied. Keeps IX.
settile:
	push	af
	call	tileptr
	pop	af
	ld	(hl),a
	call	standfix
	push	bc
	add	a,a		; its two codes in play
	ld	e,a
	ld	d,0
	ld	hl,playpair
	add	hl,de
	ex	de,hl
	ld	a,b
	add	a,FROW0
	ld	b,a
	ld	a,c
	add	a,a
	add	a,FCOL
	ld	c,a
	call	bufptr
	ld	a,(de)
	ld	(hl),a
	inc	de
	inc	hl
	ld	a,(de)
	ld	(hl),a
	pop	bc
	ld	a,(tqin)	; queued
	ld	l,a
	ld	h,0
	add	hl,hl
	ld	de,tqueue
	add	hl,de
	ld	(hl),b
	inc	hl
	ld	(hl),c
	ld	a,(tqin)
	inc	a
	and	TQSIZE-1
	ld	(tqin),a
	jp	dirtyat

; Call in the vertical blank, after holecopy: up to TQFRAME queued tiles
; copied, and the figures over them marked to be written again
tilecopy:
	call	vidwin
	ld	b,TQFRAME
tc_1:	ld	a,(tqout)
	ld	hl,tqin
	cp	(hl)
	ret	z
	push	bc
	ld	l,a
	ld	h,0
	add	hl,hl
	ld	de,tqueue
	add	hl,de
	ld	a,(hl)
	add	a,FROW0
	ld	b,a
	inc	hl
	ld	a,(hl)
	add	a,a
	add	a,FCOL
	ld	c,a
	ld	de,0102h
	call	redo
	call	cellpair
	ld	a,(tqout)
	inc	a
	and	TQSIZE-1
	ld	(tqout),a
	pop	bc
	djnz	tc_1
	ret

; IX an actor: carry set when its middle is within 3 eighths of its
; tile's both ways and the tile holds gold, B and C its row and column
atgold:	ld	a,(ix+A_OX)
	add	a,3
	cp	7
	ret	nc
	ld	a,(ix+A_OY)
	add	a,3
	cp	7
	ret	nc
	ld	b,(ix+A_Y)
	ld	c,(ix+A_X)
	call	rawtile
	cp	T_GOLD
	scf
	ret	z
	or	a
	ret

; In the round, after the runner moves: gold taken
rungold:
	ld	ix,actors
	call	atgold
	ret	nc
	xor	a
	call	settile
	ld	(BEEP),a
	ld	hl,ngold
	dec	(hl)
	ld	de,SC_GOLD
	call	addscore

; With no gold left, the hidden ladders shown, once
goldgone:
	ld	a,(ngold)
	or	a
	ret	nz
	ld	a,(revealed)
	or	a
	ret	nz
	inc	a
	ld	(revealed),a
	ld	a,(nhlad)	; the list hidlist made
	or	a
	ret	z
	ld	hl,hlad
rv_1:	push	af
	ld	b,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	push	hl
	ld	a,T_LADDER
	call	settile
	pop	hl
	pop	af
	dec	a
	jr	nz,rv_1
	ret

; At the start of a stage: the hidden ladders in tiles listed in hlad,
; a row and a column each, nhlad of them, at most 45 (tools/levels.py)
hidlist:
	ld	hl,tiles+TROW+1	; along tiles, B row, C column
	ld	de,hlad
	xor	a
	ld	(nhlad),a
	ld	b,a
hl_1:	ld	c,0
hl_2:	ld	a,(hl)
	cp	T_HLADDER
	jr	nz,hl_3
	ld	a,b
	ld	(de),a
	inc	de
	ld	a,c
	ld	(de),a
	inc	de
	ld	a,(nhlad)
	inc	a
	ld	(nhlad),a
hl_3:	inc	hl
	inc	c
	ld	a,c
	cp	FTILES
	jr	c,hl_2
	ld	a,l		; over the border
	add	a,TROW-FTILES
	ld	l,a
	jr	nc,hl_4
	inc	h
hl_4:
	inc	b
	ld	a,b
	cp	FROWS
	jr	c,hl_1
	ret

; IX a guard, after its move, not held in a hole: gold picked up, or
; carried on, or dropped
guardgold:
	ld	a,(ix+A_CARRY)
	or	a
	jr	nz,gg_1
	ld	a,(ix+A_COOL)
	or	a
	ret	nz
	call	atgold
	ret	nc
	xor	a
	call	settile
	ld	(ix+A_CARRY),1
	call	random		; carried CARRYMIN to CARRYMIN + 51 moves
	and	63
	cp	52
	jr	c,gg_0
	sub	52
gg_0:	add	a,CARRYMIN
	ld	(ix+A_CT),a
	ret
gg_1:	ld	a,(ix+A_CT)
	or	a
	jr	z,gg_2
	dec	(ix+A_CT)
	ret	nz
gg_2:	ld	a,(ix+A_OX)	; in the middle of an empty tile, held up
	or	(ix+A_OY)
	ret	nz
	ld	b,(ix+A_Y)
	ld	c,(ix+A_X)
	inc	b
	call	supports
	dec	b
	ret	nc

; IX a guard carrying gold, B row, C column: it drops it there if the
; tile is empty
gdrop:	call	rawtile
	cp	T_EMPTY
	ret	nz
	ld	a,T_GOLD
	call	settile
	ld	(ix+A_CARRY),0
	ld	(ix+A_COOL),GOLDCOOL
	ret

; A pseudo-random byte, from a 16-bit xorshift: the same each run, so
; the tests see the same game
random:	ld	hl,(seed)
	ld	a,h
	rra
	ld	a,l
	rra
	xor	h
	ld	h,a
	ld	a,l
	rra
	ld	a,h
	rra
	xor	l
	ld	l,a
	xor	h
	ld	h,a
	ld	(seed),hl
	ret

; In the round, last: carry set when the stage is done, the gold gone
; and the runner standing on row 0
stagedone:
	ld	a,(revealed)
	or	a
	ret	z
	ld	a,(actors+A_Y)
	or	a
	ret	nz
	ld	a,(actors+A_OY)
	or	a
	ret	nz
	ld	a,(rfall)
	or	a
	ret	nz
	scf
	ret

; The stage done: a life more, up to 255, 1500 points counted up in
; 100s with a beep each, and the next stage, stage 1 after the last at
; the next difficulty
endstage:
	ld	hl,lives
	inc	(hl)
	jr	nz,es_0
	dec	(hl)
es_0:	ld	b,SC_LEVEL
es_1:	push	bc
	ld	de,0100h
	call	addscore
	ld	(BEEP),a
	ld	b,4
	call	vbstat
	pop	bc
	djnz	es_1
	ld	b,30
	call	vbstat
	ld	hl,level
	inc	(hl)
	ld	a,(hl)
	cp	NLEVELS+1
	ret	c
	ld	(hl),1
	ld	a,(difficulty)
	cp	MAXDIFF
	ret	nc
	inc	a
	ld	(difficulty),a
	ret

; B frames waited, rows 22 and 23 copied when they change
vbstat:	push	bc
	call	waitvb
	call	statcopy
	ei
	pop	bc
	djnz	vbstat
	ret
