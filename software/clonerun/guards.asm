; The guards:
; up to 5, after the runner in actors, moved by the chase in PHYSICS.md
; through the JavaScript model.
;
; Each round the guards held in holes count down and the dead count
; towards coming back. Then some guards move, as many as MOVES gives for
; the number of guards and the difficulty, taking turns, the first in
; the round's frame and the others one a frame after it (gstep, gframe,
; and clonerun.asm, round). A guard falls
; like the runner and is held up by the same things. Otherwise it takes
; the way the chase proposes, if it can: other guards stop it. A guard
; whose middle reaches a hole is held in it TRAPHOLD rounds, scores 75,
; then climbs out to the rim and steps off sideways, towards the runner
; if it can. A hole closing on a guard kills it, and it comes back
; BIRTHTIME rounds later, from row 1 at a column that steps on each
; time, scoring 75.

; Guard moves a round, by 6 rounds in turn, for 0 to 11 guards plus the
; difficulty: the table of Simon Hung's Lode Runner Total Recall
; (github.com/SimonHung/LodeRunner_TotalRecall). With 5 guards each moves 2
; rounds in 5, always slower than the runner.
moves:	db	0,0,0,0,0,0, 0,1,1,0,1,1, 1,1,1,1,1,1, 1,2,1,1,2,1
	db	1,2,2,1,2,2, 2,2,2,2,2,2, 2,2,3,2,2,3, 2,3,3,2,3,3
	db	3,3,3,3,3,3, 3,3,4,3,3,4, 3,4,4,3,4,4, 4,4,4,4,4,4

; Nonzero A: IX the guard it gives, guard A (1 on)
guardix:
	ld	ix,actors
	ld	de,ASIZE
gi_1:	add	ix,de
	dec	a
	jr	nz,gi_1
	ret

; THE GUARDS' ROUND: the holds and the rebirths, and the moves the round
; owes into gowed, for gstep
guards_:
	ld	a,1		; touch and the stage check to come
	ld	(gpend),a
	ld	a,(nguard)
	or	a
	ret	z
	ld	ix,actors+ASIZE	; holds and rebirths, every guard
	ld	b,a
gr_1:	push	bc
	ld	a,(ix+A_ST)
	cp	S_TRAP
	jr	nz,gr_2
	ld	a,(ix+A_HOLD)
	or	a
	jr	z,gr_3
	dec	(ix+A_HOLD)
	jr	gr_3
gr_2:	cp	S_DEAD
	jr	nz,gr_3
	dec	(ix+A_DEAD)
	call	z,rebirth
gr_3:	ld	de,ASIZE
	add	ix,de
	pop	bc
	djnz	gr_1
	ld	a,(nguard)	; HL the moves this round
	ld	hl,difficulty
	add	a,(hl)
	cp	12
	jr	c,gr_4
	ld	a,11
gr_4:	ld	l,a
	ld	h,0
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,de
	add	hl,hl
	ld	de,moves
	add	hl,de
	ld	a,(moveoff)
	ld	e,a
	ld	d,0
	add	hl,de
	inc	a
	cp	6
	jr	c,gr_5
	xor	a
gr_5:	ld	(moveoff),a
	ld	a,(hl)
	ld	(gowed),a
	ret

; One of the moves the round owes, if any: the guard whose turn it is
; moves, and the next has the turn
gstep:	ld	a,(gowed)
	or	a
	ret	z
	dec	a
	ld	(gowed),a
	ld	hl,fmoves
	inc	(hl)
	ld	a,(moveid)
	ld	c,a
	inc	a
	ld	hl,nguard
	cp	(hl)
	jr	c,gs_1
	xor	a
gs_1:	ld	(moveid),a
	ld	a,c
	inc	a
	call	guardix
	jp	moveguard

; With the round's moves all made, the rest of the round: a guard
; touching the runner, then the stage done. Carry set when either
; ended play (caught or won set).
gdone:	ld	a,(gowed)
	or	a
	ret	nz		; carry clear from the OR
	ld	hl,gpend
	or	(hl)
	ret	z
	ld	(hl),0
	call	touch
	jr	c,gd_1
	call	stagedone
	ret	nc
	ld	a,1
	ld	(won),a
	scf
	ret
gd_1:	ld	a,1
	ld	(caught),a
	scf
	ret

; At the start of a round: the moves the last one still owes, all of
; them, and the rest of it. Carry set when that ended play.
gflush:	ld	a,(gowed)
	or	a
	jr	z,gdone
	call	gstep
	jr	gflush

; Once a frame, after its rounds: one move the round owes, at most one
; in the frame, then the rest of the round if the moves are done. Not
; while paused or once play has ended.
gframe:	ld	a,(gpend)
	or	a
	ret	z
	ld	a,(paused)
	ld	hl,caught
	or	(hl)
	ld	hl,won
	or	(hl)
	ret	nz
	ld	a,(fmoves)
	or	a
	call	z,gstep
	jp	gdone

; IX a guard: its move, when its turn comes
moveguard:
	ld	(self),ix
	ld	a,1
	ld	(isguard),a
	ld	a,(ix+A_ST)
	cp	S_DEAD
	ret	z
	ld	a,(ix+A_COOL)
	or	a
	jr	z,mg_1
	dec	(ix+A_COOL)
mg_1:	ld	a,(ix+A_ST)
	cp	S_TRAP
	jr	nz,mg_2
	ld	a,(ix+A_HOLD)
	or	a
	ret	nz
	ld	(ix+A_ST),S_CLIMB
mg_2:	ld	a,(ix+A_ST)
	cp	S_CLIMB
	jp	z,climbout
	call	isfall
	jr	nc,mg_3
	call	fallstep
	call	isfall
	call	nc,snappose
	jr	mg_5
mg_3:	call	bestmove
	cp	0FFh
	jr	z,mg_4
	push	af
	call	canmove
	pop	bc
	jr	nc,mg_4
	ld	a,b
	call	step
	jr	mg_5
mg_4:	ld	a,(ix+A_POSE)
	cp	M_RUN
	call	z,restpose
mg_5:	ld	a,(ix+A_OY)	; its middle in a hole: held there
	or	a
	jr	nz,mg_6
	ld	a,(ix+A_OX)
	add	a,3
	cp	7
	jr	nc,mg_6
	ld	b,(ix+A_Y)
	ld	c,(ix+A_X)
	call	rawtile
	cp	T_HOLE
	jr	nz,mg_6
	ld	(ix+A_OX),0
	ld	(ix+A_ST),S_TRAP
	ld	a,(difficulty)
	add	a,a
	add	a,a
	add	a,a
	add	a,TRAPHOLD
	ld	(ix+A_HOLD),a
	ld	(ix+A_HX),c
	ld	(ix+A_HY),b
	ld	(ix+A_POSE),M_FALL
	ld	(ix+A_DIRTY),1
	ld	a,(ix+A_CARRY)	; its gold onto the rim
	or	a
	jr	z,mg_5a
	dec	b
	call	gdrop
mg_5a:	ld	de,SC_TRAP
	jp	addscore
mg_6:	jp	guardgold

; IX a guard climbing out of its hole: up to the rim, the row above,
; unless a wall or a guard is there, then a step sideways, towards the
; runner if it can, until it is off the hole's column
climbout:
	ld	a,(ix+A_HY)
	dec	a
	ld	b,a		; B the rim's row
	ld	a,(ix+A_Y)
	cp	b
	jr	nz,co_1
	ld	a,(ix+A_OY)
	or	a
	jr	z,co_3		; on the rim
	jp	p,co_2
	inc	(ix+A_OY)
	jr	co_9
co_1:	ld	a,(ix+A_OY)	; in the hole: up, if the rim is free
	or	a		; looked at from the middle of the tile on
	jr	z,co_1a
	jp	p,co_2
co_1a:	ld	c,(ix+A_X)
	call	tileat
	call	iswall
	ret	z
	call	guardat
	ret	nz
co_2:	ld	d,-1
	ld	a,(ix+A_OY)
	call	addy
	ld	(ix+A_POSE),M_CLIMB
	jr	co_9
co_3:	ld	a,(actors+A_X)	; on the rim: towards the runner, or away
	cp	(ix+A_X)
	ld	a,K_RIGHT
	jr	nc,co_4
	ld	a,K_LEFT
co_4:	ld	(cotry),a
	call	canmove
	jr	c,co_5
	ld	a,(cotry)
	xor	K_LEFT^K_RIGHT
	ld	(cotry),a
	call	canmove
	ret	nc
co_5:	ld	a,(cotry)
	call	step
	ld	a,(ix+A_X)
	cp	(ix+A_HX)
	ret	z
	ld	a,(ix+A_CARRY)	; off the hole: its gold onto the rim
	or	a
	jr	z,co_6
	ld	b,(ix+A_HY)
	dec	b
	ld	c,(ix+A_HX)
	call	gdrop
co_6:	ld	(ix+A_ST),S_NORMAL
	ld	a,(ix+A_COOL)
	cp	8
	ret	nc
	ld	(ix+A_COOL),8
	ret
co_9:	inc	(ix+A_ANIM)
	ld	(ix+A_DIRTY),1
	ret

; B row, C column, a hole just brick again: a guard on it killed, hidden,
; to come back, and any gold it carried lost. Keeps IX.
gkill:	push	ix
	ld	a,(nguard)
	or	a
	jr	z,gk_3
	ld	ix,actors+ASIZE
	ld	de,ASIZE
gk_1:	push	af
	ld	a,(ix+A_ST)
	cp	S_DEAD
	jr	z,gk_2
	ld	a,(ix+A_X)
	cp	c
	jr	nz,gk_2
	ld	a,(ix+A_Y)
	cp	b
	jr	nz,gk_2
	ld	(ix+A_ST),S_DEAD
	ld	(ix+A_DEAD),BIRTHTIME
	ld	(ix+A_VIS),0
	ld	a,(ix+A_CARRY)	; its gold lost with it
	ld	(ix+A_CARRY),0
	or	a
	jr	z,gk_2
	push	bc
	push	de
	ld	hl,ngold
	dec	(hl)
	call	status
	call	goldgone
	pop	de
	pop	bc
gk_2:	add	ix,de
	pop	af
	dec	a
	jr	nz,gk_1
gk_3:	pop	ix
	ret

; IX a dead guard whose time is up: back on the first tile from row 1,
; column (birthcol) on, stepping right and then down, that is empty,
; with no guard and not the runner's. Scores 75. With no such tile it
; tries again next round.
rebirth:
	ld	a,(birthcol)
	ld	c,a
	ld	b,1
	ld	(self),ix
	ld	hl,FTILES*(FROWS-1)
	ld	(rbcnt),hl
rb_1:	call	rawtile
	or	a
	jr	nz,rb_2
	call	guardat
	jr	nz,rb_2
	ld	a,(actors+A_X)
	cp	c
	jr	nz,rb_3
	ld	a,(actors+A_Y)
	cp	b
	jr	nz,rb_3
rb_2:	inc	c		; the next tile
	ld	a,c
	cp	FTILES
	jr	c,rb_2a
	ld	c,0
	inc	b
	ld	a,b
	cp	FROWS
	jr	c,rb_2a
	ld	b,1
rb_2a:	ld	hl,(rbcnt)
	dec	hl
	ld	(rbcnt),hl
	ld	a,h
	or	l
	jr	nz,rb_1
	ld	(ix+A_DEAD),1
	ret
rb_3:	ld	(ix+A_X),c
	ld	(ix+A_Y),b
	xor	a
	ld	(ix+A_OX),a
	ld	(ix+A_OY),a
	ld	(ix+A_ST),a
	ld	(ix+A_CARRY),a
	ld	(ix+A_COOL),a
	ld	(ix+A_POSE),M_FALL
	ld	(ix+A_VIS),1
	ld	(ix+A_DIRTY),1
	ld	a,(birthcol)
	inc	a
	cp	FTILES
	jr	c,rb_4
	xor	a
rb_4:	ld	(birthcol),a
	ld	de,SC_REBIRTH
	jp	addscore

; THE CHASE (PHYSICS.md, EnemyMoveGetDirProposal):
; IX a guard, (self) set: A the way it proposes, K_*, or FFh for none.
; On the runner's row it walks straight at it unless a column from the
; next one to the runner's is a gap it would fall into: not a ladder or
; a bar, not the bottom row, and nothing under it. Gold or a hole under
; it is not a gap. A wall does not stop it, the move fails and it waits. Anything
; else, scanfloor.
bestmove:
	ld	a,(ix+A_Y)
	ld	hl,actors+A_Y
	cp	(hl)
	jp	nz,scanfloor
	ld	b,a
	ld	c,(ix+A_X)
bm_1:	ld	a,(actors+A_X)
	cp	c
	jr	z,bm_4
	jr	c,bm_3
	inc	c
	inc	c
bm_3:	dec	c
	call	tileat
	cp	T_LADDER
	jr	z,bm_1
	cp	T_BAR
	jr	z,bm_1
	ld	a,b
	cp	FROWS-1
	jr	nc,bm_1
	inc	b
	call	rawtile
	cp	T_GOLD
	jr	z,bm_2
	cp	T_HOLE
	call	nz,tileat
bm_2:	dec	b
	or	a
	jr	nz,bm_1
	jp	scanfloor
bm_4:	ld	a,(ix+A_X)	; nothing in the way
	cp	c
	ld	a,K_RIGHT
	ret	c
	ld	a,(ix+A_X)
	cp	c
	ld	a,K_LEFT
	ret	nz
	ld	a,(actors+A_OX)	; the same tile: by the offsets
	sub	(ix+A_OX)
	ld	a,0FFh
	ret	z
	ld	a,K_RIGHT
	ret	p
	ld	a,K_LEFT
	ret

; IX a guard on another row than the runner's: A the way to the best of
; the places it could fall or climb to, from its own column, then the
; columns it can reach to its left, then those to its right, each from
; the far end in. A place on
; the runner's row rates the columns between, one above it 100 and its
; rows above, one below 200 and its rows below, the least wins, the
; first found on a tie.
;
; The scan reads tiles through IX, kept for the guard and put back, so
; (IX+TROW) is the tile below and (IX-1) the one to the left. D holds
; the page of flagt: LD E,(IX+n) then LD A,(DE) gives the tile's F_
; flags. Other guards do not count in the scan.
scanfloor:
	ld	a,0FFh
	ld	(best),a
	ld	(bestr),a
	ld	a,(ix+A_X)
	ld	(sx),a
	ld	c,a
	ld	a,(ix+A_Y)
	ld	(sy),a
	ld	b,a
	push	ix
	call	cellp		; IX the guard's tile
	ld	(sfptr),hl
	push	hl
	pop	ix
	ld	d,high flagt
sf_1:	ld	a,c		; the left end it can reach along its row
	or	a
	jr	z,sf_2
	dec	ix
	call	sfgo
	jr	nc,sf_2		; a wall: the end before it
	jr	z,sf_1e		; not held there: the end, with it
	dec	c
	jr	sf_1
sf_1e:	dec	c
sf_2:	ld	a,c
	ld	(sleft),a
	ld	ix,(sfptr)	; the right end
	ld	a,(sx)
	ld	c,a
sf_3:	ld	a,c
	cp	FTILES-1
	jr	nc,sf_4
	inc	ix
	call	sfgo
	jr	nc,sf_4
	jr	z,sf_3e		; not held there: the end, with it
	inc	c
	jr	sf_3
sf_3e:	inc	c
sf_4:	ld	a,c
	ld	(sright),a
	ld	hl,(sfptr)	; its own column: down, then up
	ld	(sfcol),hl
	ld	a,(sx)
	ld	c,a
	ld	a,K_DOWN
	call	sfdown
	ld	a,K_UP
	call	sfup
	ld	a,(sleft)	; the left wing, from its far end in, and
	ld	c,a		; the right the same, as the originals
	ld	a,(sx)
	sub	c
	ld	b,a
	ld	hl,(sfptr)
	ld	a,l
	sub	b
	ld	l,a
	ld	(sfcol),hl
sf_5:	ld	a,(sx)
	cp	c
	jr	z,sf_6
	ld	a,K_LEFT
	call	sfdown
	ld	a,K_LEFT
	call	sfup
	inc	c
	ld	hl,sfcol	; the column's tile, in step with C
	inc	(hl)
	jr	sf_5
sf_6:	ld	a,(sx)
	ld	b,a
	ld	a,(sright)
	ld	c,a
	sub	b
	ld	b,a
	ld	hl,(sfptr)
	ld	a,l
	add	a,b
	ld	l,a
	ld	(sfcol),hl
sf_7:	ld	a,(sx)
	cp	c
	jr	z,sf_8
	ld	a,K_RIGHT
	call	sfdown
	ld	a,K_RIGHT
	call	sfup
	dec	c
	ld	hl,sfcol
	dec	(hl)
	jr	sf_7
sf_8:	pop	ix
	ld	a,(best)
	ret

; IX a tile on the guard's row beside the last, D the page of flagt:
; carry clear when the guard cannot go into it, a wall.
; Carry set when it can, and Z then when nothing holds a body up there,
; so the wing ends with it: not on a ladder or a bar, not on the bottom
; row, and over no brick, solid or ladder. Keeps BC, D and IX.
sfgo:	ld	e,(ix+0)
	ld	a,(de)
	ld	e,a
	and	F_WALL
	jr	nz,sg_n
	ld	a,e
	and	F_LAD|F_BAR
	jr	nz,sg_y
	ld	a,(sy)
	cp	FROWS-1
	jr	nc,sg_y
	ld	e,(ix+TROW)
	ld	a,(de)
	and	F_HOLD
	jr	nz,sg_y
	scf			; carry set, Z: not held, the end
	ret
sg_y:	or	1		; carry set, NZ: held, go on
	scf
	ret
sg_n:	or	a		; carry clear
	ret

; IX the column's tile on the guard's row, (sfcol), which scanfloor
; keeps in step with C, a row's tiles all in one page, and D the page of
; flagt
colp:	ld	ix,(sfcol)
	ld	d,high flagt
	ret

; Column C, A the way to rate it as: if the guard could fall from its
; row there (no wall below), how far it falls, stopping at a ladder, a
; bar or gold it could step off on the runner's row or below. Keeps C.
sfdown:	ld	(spath),a
	ld	a,(sy)
	ld	b,a
	cp	FROWS-1
	ret	nc
	call	colp
	ld	e,(ix+TROW)	; a wall or a hole below: no fall
	ld	a,(de)
	and	F_WALL|F_HOLE
	ret	nz
sd_1:	ld	a,b		; down to a wall below or the bottom row
	cp	FROWS-1
	jp	nc,rate
	ld	e,(ix+TROW)
	ld	a,(de)
	and	F_WALL|F_HOLE
	jp	nz,rate
	ld	e,(ix+0)
	ld	a,(de)
	and	F_LAD|F_BAR|F_GOLD
	jr	z,sd_2		; a ladder, a bar, gold: could it step off here?
	call	beside
	jr	nc,sd_2
	ld	a,(actors+A_Y)
	cp	b
	jp	z,rate
	jp	c,rate
sd_2:	inc	b
	ld	de,TROW
	add	ix,de
	ld	d,high flagt
	jr	sd_1

; Column C, A the way: if the guard stands on a ladder there, how high
; it climbs, stopping where it could step off on the runner's row or
; above. Keeps C.
sfup:	ld	(spath),a
	ld	a,(sy)
	ld	b,a
	call	colp
	ld	e,(ix+0)
	ld	a,(de)
	and	F_LAD
	ret	z
su_1:	ld	a,b
	or	a
	jr	z,rate
	ld	e,(ix+0)
	ld	a,(de)
	and	F_LAD
	jr	z,rate
	dec	b
	ld	de,-TROW
	add	ix,de
	ld	d,high flagt
	call	beside
	jr	nc,su_1
	ld	a,(actors+A_Y)
	cp	b
	jr	c,su_1
	jr	rate

; IX a tile: carry set when a body could stand to the left or the right
; of it, from their stand bytes, the border's 0 at either end of a row.
; Keeps all but AF.
beside:	ld	a,(ix+SOFF-1)
	or	(ix+SOFF+1)
	ret	z		; carry clear from the OR
	scf
	ret

; Row B, column C, the place reached: rated against the runner's row,
; kept with the way (spath) if it is the best so far. Keeps C.
rate:	ld	a,(actors+A_Y)
	ld	d,a
	ld	a,b
	sub	d
	jr	z,ra_1
	jr	c,ra_2
	add	a,200		; below the runner
	jr	ra_3
ra_1:	ld	a,(sx)		; on its row: the columns between
	sub	c
	jr	nc,ra_3
	neg
	jr	ra_3
ra_2:	neg			; above it
	add	a,100
ra_3:	ld	hl,bestr
	cp	(hl)
	ret	nc
	ld	(hl),a
	ld	a,(spath)
	ld	(best),a
	ret

; THE RUNNER CAUGHT:
; Carry set when a guard, not dead, is less than 6 eighths from the
; runner both ways
touch:	ld	a,(nguard)
	or	a
	ret	z
	ld	b,a
	ld	hl,actors
	call	place8
	ld	(rpx),de
	ld	ix,actors+ASIZE
to_1:	ld	a,(ix+A_ST)
	cp	S_DEAD
	jr	z,to_2
	push	ix
	pop	hl
	call	place8
	ld	a,(rpx)
	sub	e
	add	a,5
	cp	11
	jr	nc,to_2
	ld	a,(rpx+1)
	sub	d
	add	a,5
	cp	11
	jr	nc,to_2
	scf
	ret
to_2:	push	de
	ld	de,ASIZE
	add	ix,de
	pop	de
	djnz	to_1
	or	a
	ret

; HL an actor: E its place across in eighths, D down, the low bytes
place8:	ld	a,(hl)		; A_X
	add	a,a
	add	a,a
	add	a,a
	inc	hl
	inc	hl
	add	a,(hl)		; A_OX
	ld	e,a
	dec	hl
	ld	a,(hl)		; A_Y
	add	a,a
	add	a,a
	add	a,a
	inc	hl
	inc	hl
	add	a,(hl)		; A_OY
	ld	d,a
	ret
