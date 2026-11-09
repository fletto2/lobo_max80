; The figures' moves: the tiles as the rules see them, and the moves the runner and
; the guards share, a step a round.
;
; A figure is an actor, a block of ASIZE bytes reached through IX. It
; stands on tile A_X, A_Y with an offset A_OX, A_OY of -4 to 3 eighths
; of a tile, the C64's image positions. A step moves it an eighth, 2
; dots across or 1 line down. Past 3 it goes on to the next tile at -4,
; and back past -4 to the tile before at 3. The rules are PHYSICS.md's,
; through the JavaScript model.

; Tile kinds. 0-7 are the level's, in tools/levels.py's order.
T_EMPTY	equ	0
T_BRICK	equ	1
T_SOLID	equ	2
T_LADDER equ	3
T_BAR	equ	4
T_TRAP	equ	5		; a false brick, empty to the rules
T_HLADDER equ	6		; a hidden ladder, empty until the gold is gone
T_GOLD	equ	7		; gold, on an empty tile
T_HOLE	equ	8		; a hole open or filling, empty to the rules (holes.asm)
T_DIG	equ	9		; a hole crumbling open, brick to the rules

; What a figure does, for its shape
M_STAND	equ	0
M_RUN	equ	1
M_CLIMB	equ	2
M_HANG	equ	3
M_FALL	equ	4
M_DIG	equ	5		; digging, standing still

; A guard's state (guards.asm). S_END marks the actor after the last guard.
S_NORMAL equ	0
S_TRAP	equ	1		; held in a hole
S_CLIMB	equ	2		; climbing out of one
S_DEAD	equ	3		; killed, to come back
S_END	equ	0FFh

; An actor
A_X	equ	0		; tile column
A_Y	equ	1		; tile row
A_OX	equ	2		; offset across, -4 to 3 eighths
A_OY	equ	3		; offset down
A_FACE	equ	4		; 1 right, -1 left
A_POSE	equ	5		; M_*
A_ANIM	equ	6		; steps taken
A_ST	equ	7		; S_* for a guard, S_NORMAL for the runner
A_HOLD	equ	8		; rounds left held in a hole
A_HX	equ	9		; the hole's column
A_HY	equ	10		; and row
A_CARRY	equ	11		; nonzero: carrying gold
A_CT	equ	12		; its moves left carrying it
A_COOL	equ	13		; moves before it may take gold again
A_DEAD	equ	14		; rounds before it comes back
A_SOFF	equ	15		; added to the shape: 0, or GFIG for a guard
A_DIRTY	equ	16		; nonzero: to be built again (figures.asm)
A_VIS	equ	17		; nonzero: shown
A_BUILT	equ	18		; nonzero: built, to be copied in the blank
A_CODE	equ	19		; its first glyph code
A_FCOL	equ	20		; as last built: the first field cell across
A_FROW	equ	21		; the first field row
A_FSH	equ	22		; dots into the cell
A_FLN	equ	23		; lines into the row
A_REDO	equ	24		; nonzero: its codes to be written again (figcopy)
A_NOLD	equ	25		; screen cells holding its codes, 6 at most
A_OROW	equ	26		; the first one's screen row
A_OCOL	equ	27		; and column
A_OLD	equ	28		; each its video RAM and scrbuf addresses and code
A_NNEW	equ	58		; the same 33 bytes for the cells of the last build
A_BUF	equ	91		; its 6 glyphs, the top row's 3 then the bottom's
ASIZE	equ	139
CELLS	equ	A_NNEW-A_NOLD	; the bytes of A_NOLD to A_OLD's end

; B tile row, C tile column: A its kind as the rules see it, solid
; outside the field and empty above it (row FFh). Keeps BC, DE and HL.
tileat:	push	hl
	call	rawtile
	ld	l,a
	ld	h,high rulet
	ld	a,(hl)
	pop	hl
	ret

; Each kind as the rules see it, copied into rulet (gridinit)
behave:	db	T_EMPTY,T_BRICK,T_SOLID,T_LADDER,T_BAR,T_EMPTY,T_EMPTY,T_EMPTY
	db	T_EMPTY,T_BRICK
NKINDS	equ	$-behave

; The chase's flags (guards.asm), each kind as the rules see it: a wall,
; holding up a body above it, a ladder, a bar, gold, a hole. The chase
; sees a hole under a tile as the brick it was, as the originals do: their
; digging clears the active tile and leaves brick in the background, the
; one the guards read, so they walk straight on and fall in.
F_WALL	equ	1
F_HOLD	equ	2
F_LAD	equ	4
F_BAR	equ	8
F_GOLD	equ	80h
F_HOLE	equ	40h		; a hole: to the chase brick under a body
rflags:	db	0,F_WALL|F_HOLD,F_WALL|F_HOLD,F_LAD|F_HOLD,F_BAR
	assert	T_EMPTY = 0 && T_BRICK = 1 && T_SOLID = 2 && T_LADDER = 3 && T_BAR = 4

; B tile row, C tile column: A its kind in tiles, solid outside the
; field, empty above it. Keeps BC and DE. The border of tiles gives
; both for row FFh to 16 and column FFh to 30.
rawtile:
	ld	a,b
	inc	a
	cp	FROWS+2
	jr	nc,rt_1
	rrca			; (B+1)*TROW: the low 2 bits on top
	rrca
	ld	l,a
	and	3Fh
	add	a,high tiles
	ld	h,a
	ld	a,l
	and	0C0h
	ld	l,a
	ld	a,c
	inc	a
	cp	SOFF
	jr	nc,rt_1
	or	l
	ld	l,a
	ld	a,(hl)
	ret
rt_1:	ld	a,T_SOLID
	ret

; B tile row, C tile column, in the field: HL its place in tiles. Keeps
; AF, BC and DE.
tileptr:
	push	af
	call	cellp
	pop	af
	ret

; The same, but A lost
cellp:	ld	a,b
	inc	a
	rrca
	rrca
	ld	l,a
	and	3Fh
	add	a,high tiles
	ld	h,a
	ld	a,l
	and	0C0h
	ld	l,a
	ld	a,c
	inc	a
	or	l
	ld	l,a
	ret

	assert	TROW = 64 && SOFF = 32 && FTILES+4 = SOFF && (tiles & 0FFh) = 0 && (rulet & 0FFh) = 0 && (flagt & 0FFh) = 0

; B row, C column, a tile in the field just changed: the stand bytes of
; it and of the tile above it made again. Keeps all.
standfix:
	push	af
	push	bc
	push	de
	push	hl
	call	cellp
	ld	d,high flagt
	call	stand1
	ld	a,b
	or	a
	jr	z,sx_1
	dec	b
	ld	a,l
	sub	TROW
	ld	l,a
	jr	nc,sx_0
	dec	h
sx_0:	call	stand1
sx_1:	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

; HL a tile in the field, row B, D the page of flagt: its stand byte, 1
; when a body there is held up or on a bar, a bar there, or the bottom
; row, or brick, solid or a ladder under it. Keeps BC, D and HL.
stand1:	ld	e,(hl)
	ld	a,(de)
	and	F_BAR
	jr	nz,s1_y
	ld	a,b
	cp	FROWS-1
	jr	nc,s1_y
	push	hl
	ld	a,l
	add	a,TROW
	ld	l,a
	jr	nc,s1_0
	inc	h
s1_0:	ld	e,(hl)
	ld	a,(de)
	pop	hl
	and	F_HOLD
	jr	z,s1_w		; A 0
s1_y:	ld	a,1
s1_w:	set	5,l		; the stand byte: SOFF on, in the same row
	ld	(hl),a
	res	5,l
	ret

; At the start of a stage: every stand byte in the field
standall:
	ld	b,0
	ld	d,high flagt
sa_1:	ld	c,0
sa_2:	push	de
	call	cellp
	pop	de
	call	stand1
	inc	c
	ld	a,c
	cp	FTILES
	jr	c,sa_2
	inc	b
	ld	a,b
	cp	FROWS
	jr	c,sa_1
	ret

; Z set when kind A is a wall: brick or solid
iswall:	cp	T_BRICK
	ret	z
	cp	T_SOLID
	ret

; B row, C column: NZ when a guard other than the actor at (self), and
; not dead, is on that tile. Keeps BC, DE, HL and IX.
guardat:
	push	iy
	push	de
	ld	iy,actors+ASIZE
	ld	de,ASIZE
ga_1:	ld	a,(iy+A_ST)
	cp	S_END
	jr	z,ga_no
	cp	S_DEAD
	jr	z,ga_2
	ld	a,(iy+A_X)
	cp	c
	jr	nz,ga_2
	ld	a,(iy+A_Y)
	cp	b
	jr	nz,ga_2
	push	iy		; not the mover itself
	ex	(sp),hl
	ld	a,(self)
	xor	l
	jr	nz,ga_3
	ld	a,(self+1)
	xor	h
ga_3:	ex	(sp),hl
	pop	iy
	jr	nz,ga_yes
ga_2:	add	iy,de
	jr	ga_1
ga_no:	pop	de
	pop	iy
	xor	a
	ret
ga_yes:	pop	de
	pop	iy
	ld	a,1
	ret

; B row, C column: carry set when that tile holds up a body above it,
; brick, solid, a ladder, or a guard, or it is below the field. Keeps BC
; and DE.
supports:
	ld	a,b
	cp	FROWS
	ccf
	ret	c
	call	tileat
	cp	T_BRICK
	jr	z,su_y
	cp	T_SOLID
	jr	z,su_y
	cp	T_LADDER
	jr	z,su_y
	call	guardat
	ret	z		; carry clear from the xor
su_y:	scf
	ret

; IX an actor, (self) set to it: carry set when it falls. Not on a
; ladder, not on a bar at the bar's height, and above the middle of its
; tile or with nothing holding it up.
isfall:	ld	b,(ix+A_Y)
	ld	c,(ix+A_X)
	call	tileat
	cp	T_LADDER
	jr	z,if_no
	cp	T_BAR
	jr	nz,if_1
	ld	a,(ix+A_OY)
	or	a
	jr	z,if_no
if_1:	ld	a,(ix+A_OY)
	or	a
	scf
	ret	m
	inc	b
	call	supports
	ccf
	ret
if_no:	or	a
	ret

; IX an actor, (self) and (isguard) set, A a way, K_LEFT, K_RIGHT, K_UP
; or K_DOWN: carry set when it can step that way. Walls stop it, and
; for a guard, other guards. Up only on a ladder, or from just below
; one. Down onto anything but a wall or a guard.
canmove:
	ld	b,(ix+A_Y)
	ld	c,(ix+A_X)
	cp	K_LEFT
	jr	z,cm_l
	cp	K_RIGHT
	jr	z,cm_r
	cp	K_UP
	jr	z,cm_u
	ld	a,(ix+A_OY)	; down
	or	a
	jp	m,cm_y
	ld	a,b
	cp	FROWS-1
	jr	nc,cm_n
	inc	b
	call	tileat
	call	iswall
	jr	z,cm_n
	call	guardat
	jr	nz,cm_n
	jr	cm_y
cm_l:	ld	a,(ix+A_OX)
	dec	a
	jp	p,cm_y		; right of the middle: back to it
	ld	a,c
	or	a
	jr	z,cm_n
	dec	c
	jr	cm_s
cm_r:	ld	a,(ix+A_OX)
	or	a
	jp	m,cm_y		; left of the middle: on to it
	ld	a,c
	cp	FTILES-1
	jr	nc,cm_n
	inc	c
cm_s:	call	blocked
	ccf
	ret
cm_u:	call	tileat
	cp	T_LADDER
	jr	nz,cm_u2
	ld	a,(ix+A_OY)
	dec	a
	jp	p,cm_y		; below the middle
	ld	a,b
	or	a
	jr	z,cm_n
	dec	b
	call	blocked
	ccf
	ret
cm_u2:	ld	a,(ix+A_OY)	; below the middle, a ladder below
	dec	a
	jp	m,cm_n
	inc	b
	call	tileat
	cp	T_LADDER
	jr	nz,cm_n
cm_y:	scf
	ret
cm_n:	or	a
	ret

; B row, C column: carry set when it is a wall, or a guard is there and
; the mover is a guard. Keeps BC and DE.
blocked:
	call	tileat
	call	iswall
	scf
	ret	z
	ld	a,(isguard)
	or	a
	ret	z
	call	guardat
	scf
	ret	nz
	or	a
	ret

; IX an actor, A a way it can go (canmove): one step. Across, it turns
; that way, and comes an eighth nearer the middle of its row. Up or
; down, it comes an eighth nearer the middle of its column.
step:	cp	K_UP
	jr	z,sp_up
	cp	K_DOWN
	jr	z,sp_dn
	ld	d,1
	cp	K_RIGHT
	jr	z,sp_h
	ld	d,-1
sp_h:	ld	(ix+A_FACE),d
	ld	a,(ix+A_OX)
	add	a,d
	cp	4
	jr	nz,sp_1
	inc	(ix+A_X)
	ld	a,-4
	jr	sp_2
sp_1:	cp	-5
	jr	nz,sp_2
	dec	(ix+A_X)
	ld	a,3
sp_2:	ld	(ix+A_OX),a
	ld	a,(ix+A_OY)
	call	toward0
	ld	(ix+A_OY),a
	ld	b,(ix+A_Y)
	ld	c,(ix+A_X)
	call	tileat
	ld	e,M_RUN
	cp	T_BAR
	jr	nz,sp_3
	ld	a,(ix+A_OY)
	or	a
	jr	nz,sp_3
	ld	e,M_HANG
sp_3:	ld	(ix+A_POSE),e
	jr	sp_5
sp_up:	ld	d,-1
	jr	sp_v
sp_dn:	ld	d,1
sp_v:	ld	a,(ix+A_OY)
	call	addy
	ld	a,(ix+A_OX)
	call	toward0
	ld	(ix+A_OX),a
	ld	(ix+A_POSE),M_CLIMB
sp_5:	inc	(ix+A_ANIM)
	ld	(ix+A_DIRTY),1
	ret

; IX an actor, A its A_OY, D 1 or -1: A_OY moved by D, on to the next
; or the last row past 3 or -4
addy:	add	a,d
	cp	4
	jr	nz,ay_1
	inc	(ix+A_Y)
	ld	a,-4
	jr	ay_2
ay_1:	cp	-5
	jr	nz,ay_2
	dec	(ix+A_Y)
	ld	a,3
ay_2:	ld	(ix+A_OY),a
	ret

; A an offset: one nearer 0
toward0:
	or	a
	ret	z
	jp	m,t0_1
	dec	a
	ret
t0_1:	inc	a
	ret

; IX an actor: one step of a fall, an eighth down, and an eighth nearer
; the middle of its column
fallstep:
	ld	d,1
	ld	a,(ix+A_OY)
	call	addy
	ld	a,(ix+A_OX)
	call	toward0
	ld	(ix+A_OX),a
	ld	(ix+A_POSE),M_FALL
	ld	(ix+A_DIRTY),1
	ret

; IX an actor that has stopped falling: hanging on a bar, on a ladder or
; standing
snappose:
	ld	a,(ix+A_POSE)
	cp	M_FALL
	ret	nz

; IX an actor that has stopped: on a ladder, hanging on a bar at its
; height, or standing
restpose:
	ld	b,(ix+A_Y)
	ld	c,(ix+A_X)
	call	tileat
	ld	e,M_CLIMB
	cp	T_LADDER
	jr	z,sn_1
	ld	e,M_STAND
	cp	T_BAR
	jr	nz,sn_1
	ld	a,(ix+A_OY)
	or	a
	jr	nz,sn_1
	ld	e,M_HANG
sn_1:	ld	(ix+A_POSE),e
	ld	(ix+A_DIRTY),1
	ret

; THE RUNNER:
; One round of the runner, the keys in (rkeys). Digging, it waits for
; its hole. Falling, it falls. Else Z or X digs if it can, else the
; first of UP, DOWN, LEFT and RIGHT held that it can go.
runner:	ld	ix,actors
	ld	(self),ix
	xor	a
	ld	(isguard),a
	ld	(rfall),a
	ld	a,(ix+A_POSE)
	cp	M_DIG
	jp	z,contdig
	call	isfall
	sbc	a,a
	ld	(rfall),a
	or	a
	jr	z,ru_1
	call	fallstep
	call	isfall
	call	nc,snappose
	ret
ru_1:	ld	a,(rkeys)
	and	KZ|KX
	jr	z,ru_2
	call	trydig
	ret	z
ru_2:	ld	a,(rkeys)	; the direction pressed last, then any
	ld	hl,lastdir
	and	(hl)
	call	rtry
	ret	c
	ld	a,(rkeys)
	call	rtry
	ret	c
	ld	a,(ix+A_POSE)	; none: a runner stops
	cp	M_RUN
	ret	nz
	ld	a,(ix+A_OY)
	or	a
	ret	nz
	jp	restpose

; IX the runner, A keys: the first of them it can step, carry set if so
rtry:	ld	c,a
	ld	hl,rdirs
	ld	b,4
ru_3:	ld	a,c
	and	(hl)
	inc	hl
	jr	z,ru_4
	ld	a,(hl)
	push	hl
	push	bc
	call	canmove
	pop	bc
	pop	hl
	jr	nc,ru_4
	ld	a,(hl)
	call	step
	scf
	ret
ru_4:	inc	hl
	djnz	ru_3
	or	a
	ret

; The keys the runner tries, in order, each its bit and its way
rdirs:	db	KU,K_UP, KD,K_DOWN, KL,K_LEFT, KR,K_RIGHT

; DIGGING:
; IX the runner, held up, Z or X in (rkeys), X first: digs the brick one
; row down and one column across, if it is not on the bottom row, the
; tile beside it empty to the rules with no gold or guard on it, the
; target brick and the hole table not full. Wherever it is in its tile
; it then stands in the middle, as the Apple II's nudges do,
; digging, facing the hole. Z set when it digs.
trydig:	ld	e,1
	ld	a,(rkeys)
	bit	K_DIGR,a
	jr	nz,td_1
	ld	e,-1
td_1:	ld	a,(ix+A_X)
	add	a,e
	ld	c,a
	cp	FTILES
	jr	nc,td_no
	ld	b,(ix+A_Y)
	ld	a,b
	cp	FROWS-1
	jr	nc,td_no
	call	tileat		; beside it
	or	a
	jr	nz,td_no
	call	rawtile
	cp	T_GOLD
	jr	z,td_no
	call	guardat
	jr	nz,td_no
	inc	b
	call	rawtile		; the target
	cp	T_BRICK
	jr	nz,td_no
	push	de
	push	ix
	call	newhole
	pop	ix
	pop	de
	jr	nz,td_no
	ld	a,b
	ld	(digrow),a
	ld	a,c
	ld	(digcol),a
	ld	(ix+A_OX),0
	ld	(ix+A_OY),0
	ld	(ix+A_FACE),e
	ld	(ix+A_POSE),M_DIG
	ld	(ix+A_DIRTY),1
	xor	a
	ret
td_no:	or	1
	ret

; IX the runner, digging: stands once its hole is open. A guard on the
; brick being dug or above it stops the dig, and the brick is whole
; again.
contdig:
	ld	a,(digrow)
	ld	b,a
	ld	a,(digcol)
	ld	c,a
	call	guardat
	jr	nz,cd_1
	dec	b
	call	guardat
	jr	nz,cd_1
	ld	hl,(digh)
	inc	hl
	inc	hl
	ld	a,(hl)
	cp	PH_OPEN
	ret	c
	jr	cd_2
cd_1:	push	ix
	ld	ix,(digh)
	ld	(ix+H_PH),PH_DONE
	call	setphase
	pop	ix
cd_2:	jp	restpose
