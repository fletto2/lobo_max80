; The holes:
; a table of the holes dug, each going through its phases a round at a
; time. A hole crumbles open in 4 steps while the runner digs, stays
; open, fills back in 4 steps and is brick again. Each change goes into
; tiles and scrbuf at once, marks the figures over it to be built again,
; and goes into video RAM in the next vertical blank (holecopy). When a
; hole is brick again, the runner on its tile is caught, and a guard on
; it is killed (guards.asm).
;
; While it crumbles open its tile is T_DIG, brick to the rules. Open and
; while it fills it is T_HOLE, empty to the rules, so a figure falls in
; and walks out sideways where it can.

; A hole table entry
H_ROW	equ	0		; tile row, FFh for a free entry
H_COL	equ	1		; tile column
H_PH	equ	2		; phase, PH_*
H_CNT	equ	3		; rounds left in the phase, 2 bytes
H_NEW	equ	5		; nonzero: to be copied into video RAM
HSIZE	equ	6

; The phases. phtab gives each one's codes, tile kind and length.
PH_OPEN	equ	4		; 0-3 crumbling, 4 open, 5-8 filling
PH_DONE	equ	9		; brick again, the entry freed once copied

; Each phase: its left and right codes, its tile kind, its rounds
phtab:	db	G_CRUMBLE1,G_CRUMBLE1+1,T_DIG
	dw	DIGSTEP
	db	G_CRUMBLE2,G_CRUMBLE2+1,T_DIG
	dw	DIGSTEP
	db	G_CRUMBLE3,G_CRUMBLE3+1,T_DIG
	dw	DIGSTEP
	db	G_CRUMBLE4,G_CRUMBLE4+1,T_DIG
	dw	DIGSTEP
	db	' ',' ',T_HOLE
	dw	HOLEOPEN
	db	G_FILL1,G_FILL1+1,T_HOLE
	dw	FILLSTEP
	db	G_FILL2,G_FILL2+1,T_HOLE
	dw	FILLSTEP
	db	G_FILL3,G_FILL3+1,T_HOLE
	dw	FILLSTEP
	db	G_FILL4,G_FILL4+1,T_HOLE
	dw	FILLSTEP
	db	G_BRICK,G_BRICK+1,T_BRICK
	dw	0

; Empties the table
holeinit:
	ld	ix,holes
	ld	de,HSIZE
	ld	b,NHOLES
hi_1:	ld	(ix+H_ROW),0FFh
	ld	(ix+H_NEW),0
	add	ix,de
	djnz	hi_1
	ret

; B row, C column: a new hole there, in its first phase, (digh) its
; entry. Z set when made, clear when the table is full. Keeps BC.
newhole:
	ld	ix,holes
	ld	de,HSIZE
	ld	a,NHOLES
nh_1:	inc	(ix+H_ROW)
	jr	z,nh_2
	dec	(ix+H_ROW)
	add	ix,de
	dec	a
	jr	nz,nh_1
	inc	a		; full: Z clear
	ret
nh_2:	ld	(ix+H_ROW),b
	ld	(ix+H_COL),c
	ld	(ix+H_PH),0
	ld	(digh),ix
	push	bc
	call	setphase
	pop	bc
	xor	a
	ret

; One round of every hole. A hole turning back to brick catches the
; runner on its tile (caught) and kills a guard on it (gkill).
holetick:
	ld	ix,holes
	ld	b,NHOLES
ht_1:	ld	a,(ix+H_ROW)
	inc	a
	jr	z,ht_2		; free
	ld	a,(ix+H_PH)
	cp	PH_DONE
	jr	nc,ht_2
	ld	l,(ix+H_CNT)
	ld	h,(ix+H_CNT+1)
	dec	hl
	ld	(ix+H_CNT),l
	ld	(ix+H_CNT+1),h
	ld	a,h
	or	l
	jr	nz,ht_2
	inc	(ix+H_PH)
	push	bc
	call	setphase
	ld	a,(ix+H_PH)
	cp	PH_DONE
	call	z,closed
	pop	bc
ht_2:	ld	de,HSIZE
	add	ix,de
	djnz	ht_1
	ret

; IX an entry: its phase's codes into scrbuf, its kind into tiles, its
; count started, the figures over it marked, and marked to be copied
setphase:
	ld	a,(ix+H_PH)	; HL its phtab entry, 5 bytes
	ld	l,a
	ld	h,0
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,hl
	add	hl,de
	ld	de,phtab
	add	hl,de
	push	hl
	ld	a,(ix+H_ROW)
	add	a,FROW0
	ld	b,a
	ld	a,(ix+H_COL)
	add	a,a
	add	a,FCOL
	ld	c,a
	call	bufptr
	ex	de,hl
	pop	hl
	ldi
	ldi
	ld	a,(hl)		; the kind
	inc	hl
	ld	e,(hl)		; the count
	inc	hl
	ld	d,(hl)
	ld	(ix+H_CNT),e
	ld	(ix+H_CNT+1),d
	ld	b,(ix+H_ROW)
	ld	c,(ix+H_COL)
	call	tileptr
	ld	(hl),a
	call	standfix
	ld	(ix+H_NEW),1
	jp	dirtyat

; IX an entry turned back to brick: the runner on its tile caught, a
; guard on it killed
closed:	ld	b,(ix+H_ROW)
	ld	c,(ix+H_COL)
	ld	a,(actors+A_X)
	cp	c
	jr	nz,cl_1
	ld	a,(actors+A_Y)
	cp	b
	jr	nz,cl_1
	ld	a,1
	ld	(caught),a
cl_1:	jp	gkill

; Call in the vertical blank, before figcopy: each hole that changed
; into video RAM from scrbuf, and an entry that is brick again freed.
; figcopy then puts the figures' codes back over any of these cells.
holecopy:
	call	vidwin
	ld	ix,holes
	ld	b,NHOLES
hc_1:	ld	a,(ix+H_NEW)
	or	a
	jr	z,hc_2
	ld	(ix+H_NEW),0
	push	bc
	ld	a,(ix+H_ROW)
	add	a,FROW0
	ld	b,a
	ld	a,(ix+H_COL)
	add	a,a
	add	a,FCOL
	ld	c,a
	ld	de,0102h	; the figures over it to be written again
	call	redo
	call	cellpair
	pop	bc
	ld	a,(ix+H_PH)
	cp	PH_DONE
	jr	c,hc_2
	ld	(ix+H_ROW),0FFh
hc_2:	ld	de,HSIZE
	add	ix,de
	djnz	hc_1
	ret

; B screen row, C screen column: that cell and the next copied from
; scrbuf into video RAM. The window must show video RAM.
cellpair:
	call	bufptr
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	call	vcell
	ld	(hl),e
	inc	c
	call	vcell
	ld	(hl),d
	ret
