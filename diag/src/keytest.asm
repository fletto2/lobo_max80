; Keyboard test: the 8 x 8 matrix on the screen, each key shown while it
; is down and marked once it has been pressed, with a beep as it goes
; down. ESC three times in a row,
; or any key on the terminal, goes back to the menu.

kbtest:	ld	hl,kcur
	ld	b,25			; kcur, kseen, kdrawn, kesc
tk2:	ld	(hl),0
	inc	hl
	djnz	tk2
	xor	a
	ld	(kkey),a
	inc	a
	ld	(kpoll),a
	ld	a,0Ch
	call	putc
	call	print
	db	"KEYBOARD TEST",0
	ld	hl,2			; row 2, column 0
	call	at
	call	print
	db	"Row",0
	ld	hl,6*256+2
	ld	b,'0'
tk1:	call	at
	ld	a,'D'
	call	putc
	ld	a,b
	call	putc
	ld	a,h
	add	a,9
	ld	h,a
	inc	b
	ld	a,b
	cp	'8'
	jr	nz,tk1
	ld	l,3			; the lines between the rows
tk5a:	ld	h,4
	call	at
	ld	a,TH
	call	putc
	ld	b,73
	ld	a,'-'
tk5b:	call	putc
	djnz	tk5b
	ld	a,TK
	call	putc
	inc	l
	inc	l
	ld	a,l
	cp	21
	jr	nz,tk5a
	ld	hl,21
	call	at
	call	print
	db	TH,"Keys in brackets, ",TK,"[A]",TH,", are down now. Keys with a plus, ",TK,"A+"
	db	TH,", have been pressed.",0Dh,0Ah
	db	"Three keys down together can show a fourth that is not (TRM TS-17).",0Dh,0Ah
	db	"Press ",TK,"ESC",TH," three times in a row, or any key on the terminal, to go back.",TK,0
	ld	c,0
tk3:	ld	a,c
	add	a,a
	add	a,4
	ld	l,a
	ld	h,0
	call	at			; row 4 + 2C
	ld	a,'8'
	call	putc
	call	kmask
	call	phex8
	ld	h,76
	call	at
	ld	a,TH
	call	putc
	ld	a,'|'
	call	putc
	ld	a,TK
	call	putc
	ld	b,0
	ld	d,0
	ld	a,0FFh
	push	bc
	call	kcells
	pop	bc
	inc	c
	ld	a,c
	cp	8
	jr	nz,tk3

tk4:	call	poll
	ld	a,(SIOCA)
	and	1
	jr	z,tk5
	ld	a,(SIODA)
	jr	tk8
tk5:	ld	a,(kkey)
	or	a
	jr	z,tk7
	ld	b,a
	xor	a
	ld	(kkey),a
	ld	hl,kesc
	ld	a,b
	cp	1Bh
	jr	z,tk6
	ld	(hl),0
	jr	tk7
tk6:	inc	(hl)
	ld	a,(hl)
	cp	3
	jr	nc,tk8
tk7:	ld	c,0
tk9:	push	bc
	call	krchk
	pop	bc
	inc	c
	ld	a,c
	cp	8
	jr	nz,tk9
	jr	tk4
tk8:	xor	a
	ld	(kkey),a
	ld	(kpoll),a
	jp	drawmenu

; C = the row. Draws the cells whose key has gone down or up, or has
; been pressed for the first time. Down is the matrix as read, pressed
; is kseen, marked by every scan.
krchk:	call	kmask
	ld	e,a
	ld	d,0
	ld	hl,MATRIX
	add	hl,de
	ld	b,(hl)			; down now
	ld	hl,kseen
	call	kidx
	ld	d,(hl)			; pressed
	ld	hl,kdrawn
	call	kidx
	ld	a,d
	xor	(hl)
	ld	e,a
	ld	(hl),d
	ld	hl,kcur
	call	kidx
	ld	a,b
	xor	(hl)
	or	e
	ret	z
	push	af
	ld	a,(hl)			; a key gone down beeps
	cpl
	and	b
	jr	z,kr0
	ld	(BEEP),a
kr0:	pop	af
	ld	(hl),b

; Row C, with B the keys down, D the keys pressed and A the cells to
; draw
kcells:	ld	(kchg),a
	ld	e,0			; the bit
kr1:	ld	a,(kchg)
	rrca
	ld	(kchg),a
	call	c,kcell
	rrc	b
	rrc	d
	inc	e
	ld	a,e
	cp	8
	jr	nz,kr1
	jr	kcount

; The cell of row C, bit E, from bit 0 of B (down) and D (pressed). A
; key not pressed yet is thin, the rest thick. Keeps BC, DE.
kcell:	ld	a,e
	add	a,a
	add	a,a
	add	a,a
	add	a,e
	add	a,4
	ld	h,a
	ld	a,c
	add	a,a
	add	a,4
	ld	l,a
	call	at			; row 4 + 2C, column 4 + 9E
	ld	a,TH
	call	putc
	ld	a,'|'
	call	putc
	ld	a,b
	or	d
	rrca
	ld	a,TK
	call	c,putc
	ld	a,' '
	bit	0,b
	jr	z,kr2
	ld	a,'['
kr2:	call	putc
	push	bc
	push	de
	call	klabel
	pop	de
	pop	bc
	ld	l,a			; its length
	ld	a,']'
	bit	0,b
	call	nz,putc
	ld	a,' '
	bit	0,d
	jr	z,kr4
	ld	a,'+'
kr4:	call	putc
	ld	a,' '
	bit	0,b
	call	z,putc
	ld	a,5			; 9 a cell
	sub	l
	jr	z,kr6
	ld	l,a
	ld	a,' '
kr5:	call	putc
	dec	l
	jr	nz,kr5
kr6:	ld	a,TK
	jp	putc

; The keys pressed so far on row 20, the None position left out
kcount:	ld	hl,kseen
	ld	bc,8*256+0
kc1:	ld	a,b
	cp	1
	ld	a,(hl)
	jr	nz,kc2
	and	0BFh			; row 7 D6
kc2:	or	a
	jr	z,kc3
	srl	a
	jr	nc,kc2
	inc	c
	jr	kc2
kc3:	inc	hl
	djnz	kc1
	ld	hl,4*256+20
	call	at
	call	print
	db	TH,"Keys pressed: ",TK,0
	ld	l,c
	ld	h,0
	call	pdec16
	call	print
	db	TH," of 63",TK,0
	ret

; A = 1 << C. Keeps BC.
kmask:	push	bc
	ld	b,c
	inc	b
	ld	a,1
	jr	km2
km1:	add	a,a
km2:	djnz	km1
	pop	bc
	ret

; HL = HL + C. Keeps A, DE.
kidx:	push	de
	ld	e,c
	ld	d,0
	add	hl,de
	pop	de
	ret

; Prints the name of row C, bit E. A = its length.
klabel:	ld	a,c
	cp	6
	jr	nc,kl1
	add	a,a
	add	a,a
	add	a,a
	add	a,e
	ld	l,a
	ld	h,0
	ld	de,ktab
	add	hl,de
	ld	a,(hl)
	call	putc
	ld	a,1
	ret
kl1:	sub	6
	add	a,a
	add	a,a
	add	a,a
	add	a,e
	ld	b,a
	inc	b
	ld	hl,klab
	jr	kl3
kl2:	ld	a,(hl)
	inc	hl
	or	a
	jr	nz,kl2
kl3:	djnz	kl2
kl4:	ld	a,(hl)
	inc	hl
	or	a
	jr	z,kl5
	call	putc
	inc	b
	jr	kl4
kl5:	ld	a,b
	ret

klab:	db	"ENTER",0,"CLEAR",0,"BREAK",0,"UP",0,"DOWN",0,"LEFT",0
	db	"RIGHT",0,"SPACE",0
	db	"SHIFT",0,"F1",0,"F2",0,"F3",0,"F4",0,"ESC",0,0,"CTRL",0
