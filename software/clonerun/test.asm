; THE TEST BUILD (CRT.COM, CRT2.COM), for test.sh
;
; "CRT L S [F]": tail reads L, the test level to play at once, S, the
; key script that stands in for the keyboard in play, and F, a round to
; freeze at in place of the script's own. Row 23 shows, in hex, from
; column 0: X the runner's tile column, U its offset across in eighths,
; Y its tile row, W its offset down, M what it does, D its way across
; (01 right, FF left), T the rounds run, I the fewest passes through the
; picture after the frame's work, 37 T-states each (waitvb), V the
; fewest passes through the vertical blank left after the copies, 30
; T-states each (testvb), H the holes in the table, F the phase of its
; first entry (FF free) and R the times the level started again. I and
; V count from the 17th frame of play. From column 66, when the level
; has a guard, G and the first guard's column, offset across, row,
; offset down, what it does (80h on when it faces left) and its state.

; Reads the command tail into tlev, tscr and tfrz
tail:	ld	hl,80h
	ld	b,(hl)
	inc	hl
	call	num
	ld	(tlev),a
	call	num
	ld	(tscr),a
	push	af
	call	num
	ld	(tfrz),de
	pop	af
	or	a
	ret	z
	dec	a		; sptr, the script's first entry
	add	a,a
	ld	e,a
	ld	d,0
	ld	hl,stab
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	(sptr),hl
	ret

; HL the tail, B the characters left: DE the next number, 0 if none,
; and A its low byte
num:	ld	de,0
nm_1:	ld	a,b
	or	a
	jr	z,nm_3
	ld	a,(hl)
	cp	' '
	jr	nz,nm_2
	inc	hl
	dec	b
	jr	nm_1
nm_2:	ld	a,b
	or	a
	jr	z,nm_3
	ld	a,(hl)
	sub	'0'
	jr	c,nm_3
	cp	10
	jr	nc,nm_3
	push	hl		; DE x 10 + the digit
	ld	h,d
	ld	l,e
	add	hl,hl
	add	hl,hl
	add	hl,de
	add	hl,hl
	ld	e,a
	ld	d,0
	add	hl,de
	ex	de,hl
	pop	hl
	inc	hl
	dec	b
	jr	nm_2
nm_3:	ld	a,e
	ret

; The keys for this round, in A, from the script, or the keyboard with
; no script. Carry set once the script's freeze round is reached: the
; round is not run.
script:	ld	a,(tscr)
	or	a
	jr	nz,sc_0
	ld	a,(tapped)
	ret
sc_0:	ld	hl,(sptr)
	ld	c,0
sc_1:	ld	e,(hl)		; each entry a round and the keys held from it
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,d
	and	e
	inc	a
	jr	z,sc_3		; FFFFh, the end
	push	hl
	ld	hl,(ttick)
	or	a
	sbc	hl,de
	pop	hl
	jr	c,sc_2		; not yet
	ld	c,(hl)
sc_2:	inc	hl
	jr	sc_1
sc_3:	ld	e,(hl)		; the freeze round, FFFFh for none
	inc	hl
	ld	d,(hl)
	ld	hl,(tfrz)	; or the command line's
	ld	a,h
	or	l
	jr	z,sc_3a
	ex	de,hl
sc_3a:	ld	hl,(ttick)
	or	a
	sbc	hl,de
	jr	c,sc_4
	scf
	ret
sc_4:	ld	hl,(ttick)
	inc	hl
	ld	(ttick),hl
	ld	a,c
	or	a
	ret

; In the vertical blank after figcopy: every 16th frame row 23 to the
; screen, the other frames the passes left in the blank counted. Returns
; as the picture starts, so the frame's work starts with it (waitvb).
testvb:	ld	hl,(tframes)
	inc	hl
	ld	(tframes),hl
	ld	a,l
	and	15
	jr	nz,tv_1
	ld	a,23
	call	onerow
	ld	hl,SYSFLG
tv_0:	bit	6,(hl)
	jr	z,tv_0
	ret
tv_1:	ld	hl,SYSFLG
	ld	de,0
tv_2:	inc	de
	bit	6,(hl)
	jr	z,tv_2
	ld	hl,vbmin
	jp	newmin

; After the frame's work: the fewest idle passes, and row 23 in scrbuf
; in the frame before testvb shows it. The passes of the frame that
; wrote row 23 are not counted, the writing is the test's, not the
; game's.
testrow:
	ld	hl,tfmt
	ld	a,(hl)
	ld	(hl),0
	or	a
	jr	nz,tr_0
	ld	de,(idle)
	ld	hl,idmin
	call	newmin
tr_0:	ld	a,(tframes)	; testvb shows row 23 when the count is 0 mod 16
	and	15
	cp	15
	ret	nz
	ld	a,(tscr)	; on the keyboard, none until a key moves the
	ld	hl,moving	; runner, so that -k sees row 22 as a prompt
	or	(hl)
	ret	z
	ld	(tfmt),a
	ld	bc,23*256
	call	bufptr
	push	hl
	ld	b,COLS
tr_1:	ld	(hl),' '
	inc	hl
	djnz	tr_1
	pop	hl
	ld	ix,actors
	ld	a,'X'
	ld	c,(ix+A_X)
	call	field2
	ld	a,'U'
	ld	c,(ix+A_OX)
	call	field2
	ld	a,'Y'
	ld	c,(ix+A_Y)
	call	field2
	ld	a,'W'
	ld	c,(ix+A_OY)
	call	field2
	ld	a,'M'
	ld	c,(ix+A_POSE)
	call	field2
	ld	a,'D'
	ld	c,(ix+A_FACE)
	call	field2
	ld	(hl),'T'
	inc	hl
	inc	hl
	ld	de,(ttick)
	call	hex4
	ld	(hl),'I'
	inc	hl
	inc	hl
	ld	de,(idmin)
	call	hex4
	ld	(hl),'V'
	inc	hl
	inc	hl
	ld	de,(vbmin)
	call	hex4
	push	hl		; the holes in the table
	ld	hl,holes
	ld	de,HSIZE
	ld	bc,NHOLES*256
tr_2:	ld	a,(hl)
	inc	a
	jr	z,tr_3
	inc	c
tr_3:	add	hl,de
	djnz	tr_2
	pop	hl
	ld	a,'H'
	call	field2
	ld	a,(holes+H_ROW)	; the first entry's phase
	cp	0FFh
	jr	z,tr_4
	ld	a,(holes+H_PH)
tr_4:	ld	c,a
	ld	a,'F'
	call	field2
	ld	a,(restarts)
	ld	c,a
	ld	a,'R'
	call	field2
	ld	ix,actors+ASIZE	; the first guard: G then x, ox, y, oy, pose
	ld	a,(ix+A_ST)	; (80h on when it faces left) and state
	cp	S_END
	ret	z
	ld	(hl),'G'
	inc	hl
	inc	hl
	ld	a,(ix+A_X)
	call	hx_1
	ld	a,(ix+A_OX)
	call	hx_1
	ld	a,(ix+A_Y)
	call	hx_1
	ld	a,(ix+A_OY)
	call	hx_1
	ld	a,(ix+A_FACE)
	and	80h
	or	(ix+A_POSE)
	call	hx_1
	ld	a,(ix+A_ST)
	jp	hx_1

; A a letter, C a byte: "A cc " at HL, HL after it
field2:	ld	(hl),a
	inc	hl
	inc	hl
	ld	a,c
	jr	hex2

; DE a count: kept at HL if it is fewer, from the 17th frame on
newmin:	ld	a,(tframes+1)
	or	a
	jr	nz,mi_1
	ld	a,(tframes)
	cp	17
	ret	c
mi_1:	ld	a,(hl)
	inc	hl
	ld	b,(hl)
	ld	c,a		; BC the least so far
	ex	de,hl
	or	a
	sbc	hl,bc
	ret	nc
	add	hl,bc
	ex	de,hl
	ld	(hl),d
	dec	hl
	ld	(hl),e
	ret

; DE in hex at HL, then a space, HL after it
hex4:	ld	a,d
	call	hx_1
	ld	a,e
hex2:	call	hx_1
	inc	hl
	ret
hx_1:	push	af
	rrca
	rrca
	rrca
	rrca
	call	hx_2
	pop	af
hx_2:	and	0Fh
	add	a,'0'
	cp	'9'+1
	jr	c,hx_3
	add	a,'A'-'9'-1
hx_3:	ld	(hl),a
	inc	hl
	ret

; The key scripts, each entries of a round and the keys held from it,
; then FFFFh and the round to freeze at, FFFFh for none
stab:	dw	s1,s2,s3,s4,s5,s6,s7,s8,s9,s10
	dw	s11,s12,s13,s14,s15,s16,s17,s18,s19,s20
	dw	s21,s22,s23,s24,s25,s26,s27,s28,s29,s30
s1:	dw	0		; RIGHT, frozen after 13 rounds
	db	KR
	dw	0FFFFh,13
s2:	dw	0		; RIGHT 400 rounds, into a brick
	db	KR
	dw	400
	db	0
	dw	0FFFFh,0FFFFh
s3:	dw	0		; LEFT 400 rounds, into a solid block
	db	KL
	dw	400
	db	0
	dw	0FFFFh,0FFFFh
s4:	dw	0		; 2 tiles RIGHT to a ladder, then UP held
	db	KR
	dw	16
	db	KU
	dw	400
	db	0
	dw	0FFFFh,0FFFFh
s5:	dw	0		; the same, then DOWN held
	db	KR
	dw	16
	db	KU
	dw	100
	db	KD
	dw	400
	db	0
	dw	0FFFFh,0FFFFh
s6:	dw	0		; 10 tiles RIGHT, onto a bar and along it
	db	KR
	dw	80
	db	0
	dw	0FFFFh,0FFFFh
s7:	dw	0		; the same, then DOWN: off the bar
	db	KR
	dw	80
	db	0
	dw	100
	db	KD
	dw	110
	db	0
	dw	0FFFFh,0FFFFh
s8:	dw	0		; 5 tiles RIGHT, off a ledge
	db	KR
	dw	40
	db	0
	dw	0FFFFh,0FFFFh
s9:	dw	0		; the same, frozen in the fall
	db	KR
	dw	40
	db	0
	dw	0FFFFh,60
s10:	dw	0		; back and forth, for the timings
	db	KR
	dw	30
	db	KL
	dw	60
	db	KR
	dw	90
	db	KL
	dw	120
	db	KR
	dw	150
	db	KL
	dw	180
	db	0
	dw	0FFFFh,0FFFFh

; Digging. Level 5 has the runner on a brick floor, levels 6 and 7 digs
; that are refused, level 4 a ledge one brick thick.
s11:	dw	0		; X, dig right, then nothing
	db	KX
	dw	2
	db	0
	dw	0FFFFh,0FFFFh
s12:	dw	0		; Z, dig left, then nothing
	db	KZ
	dw	2
	db	0
	dw	0FFFFh,0FFFFh
s13:	dw	0		; X, then RIGHT into the hole, then UP held
	db	KX
	dw	2
	db	0
	dw	15
	db	KR
	dw	30
	db	KU
	dw	0FFFFh,0FFFFh
s14:	dw	0		; X, a tile LEFT, X again: two holes side by side, then RIGHT
	db	KX
	dw	2
	db	0
	dw	13
	db	KL
	dw	21
	db	KX
	dw	23
	db	0
	dw	40
	db	KR
	dw	0FFFFh,0FFFFh
s15:	dw	0		; X and LEFT held: a row of holes, for the timings
	db	KX|KL
	dw	0FFFFh,0FFFFh
s16:	dw	0		; X, then RIGHT: over the hole and through it
	db	KX
	dw	2
	db	0
	dw	15
	db	KR
	dw	30
	db	0
	dw	0FFFFh,0FFFFh
s17:	dw	0		; off the ledge, Z held once in the air, frozen in the fall
	db	KR
	dw	36
	db	KZ
	dw	0FFFFh,60
s18:	dw	0		; RIGHT 1 tile onto a ladder, then X
	db	KR
	dw	8
	db	0
	dw	12
	db	KX
	dw	14
	db	0
	dw	0FFFFh,0FFFFh
s19:	dw	0		; RIGHT 4 tiles onto a bar, then Z
	db	KR
	dw	32
	db	0
	dw	34
	db	KZ
	dw	36
	db	0
	dw	0FFFFh,0FFFFh
s20:	dw	0		; RIGHT 4 tiles, through gold in the ledge
	db	KR
	dw	40
	db	0
	dw	0FFFFh,0FFFFh
s21:	dw	0		; LEFT 3 tiles, through a false brick
	db	KL
	dw	40
	db	0
	dw	0FFFFh,0FFFFh
s22:	dw	0		; RIGHT 1 tile onto a hidden ladder, then UP held
	db	KR
	dw	8
	db	KU
	dw	40
	db	0
	dw	0FFFFh,0FFFFh
s23:	dw	0		; LEFT 2 rounds, then the guard comes
	db	KL
	dw	2
	db	0
	dw	0FFFFh,0FFFFh
s24:	dw	0		; X, then LEFT 2 tiles from the hole
	db	KX
	dw	14
	db	KL
	dw	30
	db	0
	dw	0FFFFh,0FFFFh
s25:	dw	0		; X, and the runner stands by the hole
	db	KX
	dw	14
	db	0
	dw	0FFFFh,0FFFFh
s26:	dw	0		; RIGHT held, into the guard, life after life
	db	KR
	dw	0FFFFh,0FFFFh
s30:	dw	0		; Z, a hole to the left, then stand
	db	KZ
	dw	4
	db	0
	dw	0FFFFh,0FFFFh
s29:	dw	0		; onto a ladder, UP 3 eighths, then X
	db	KR
	dw	8
	db	KU
	dw	11
	db	KX
	dw	13
	db	0
	dw	0FFFFh,0FFFFh
s28:	dw	0		; DOWN a ladder, then RIGHT too, off it
	db	KD
	dw	20
	db	KD|KR
	dw	0FFFFh,32
s27:	dw	0		; RIGHT 4 tiles through gold, then UP held
	db	KR
	dw	32
	db	KU
	dw	0FFFFh,0FFFFh

tlev:	db	0
tscr:	db	0
sptr:	dw	0
tfrz:	dw	0		; the freeze tick from the command line, 0 for none
restarts: db	0
ttick:	dw	0
tframes: dw	0
idle:	dw	0
tfmt:	db	0		; row 23 written this frame
idmin:	dw	0FFFFh
vbmin:	dw	0FFFFh
