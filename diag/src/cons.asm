; Console: the 80 x 24 screen, kept in SHADOW as well, and its copy out
; of SIO channel A as a VT100 would take it. CR, LF (which also returns
; the cursor to column 0) and FF (clear) are the only controls, with TH
; and TK, which switch the screen to the font's thin second style and
; back.

TH	equ	0Eh
TK	equ	0Fh

; A to the screen when scrout is set, and to SIO A when sioon is. The
; keyboard is scanned first when kpoll is set. Keeps every register.
putc:	push	af
	push	bc
	push	de
	push	hl
	ld	c,a
	ld	a,(kpoll)
	or	a
	call	nz,poll
	ld	a,c
	cp	TH
	jr	z,pu1
	cp	TK
	jr	nz,pu2
pu1:	and	1
	xor	1
	ld	(thin),a
	jr	pu3
pu2:	call	sputc
	ld	a,(scrout)
	or	a
	call	nz,vputc
pu3:	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

vputc:	ld	a,c
	cp	0Dh
	jr	nz,vp1
	xor	a
	ld	(ccol),a
	ret
vp1:	cp	0Ah
	jr	z,newline
	cp	0Ch
	jp	z,vcls
	ld	a,(rclip)		; cut: nothing more on row 23
	or	a
	jr	z,vp2
	ld	a,(crow)
	cp	23
	ret	z
vp2:	ld	a,(thin)
	or	a
	ld	a,c
	call	nz,tmap
	ld	hl,(crow)
	call	vidx
	call	vaddr
	ld	(de),a
	ld	de,SHADOW
	add	hl,de
	ld	(hl),a
	ld	a,(ccol)
	inc	a
	ld	(ccol),a
	cp	80
	ret	c
newline:
	xor	a
	ld	(ccol),a
	ld	a,(rmode)
	or	a
	jr	nz,nlres
	ld	a,(crow)
	inc	a
	cp	24
	jp	nc,scroll
nl1:	ld	(crow),a
	ret

; A new line in the results area, rows 15-22. Past row 20 the footer is
; overwritten. Onto row 23 the area either waits for a key and starts
; again at row 15 (rmode 1) or is cut, taking no more text on row 23
; until rclear (rmode 2).
nlres:	ld	a,(crow)
	cp	23
	ret	nc
	inc	a
	cp	21
	jr	c,nl1
	ld	hl,ovrun
	ld	(hl),1
	cp	23
	jr	c,nl1
	ld	a,(rclip)
	or	a
	jr	z,nlr2
	ld	a,23
	jr	nl1
nlr2:	ld	a,(thin)
	push	af
	ld	hl,23
	call	at
	call	clreol
	ld	a,(rmode)
	dec	a
	jr	z,nlpage
	call	pmore
	ld	a,1
	ld	(rclip),a
	jr	nlp2
nlpage:	call	print
	db	TH,"More: any key.",TK,0
	call	waitkey
	call	rclear
	ld	hl,15
	call	at
nlp2:	pop	af
	ld	(thin),a
	ret
scroll:	ld	hl,SHADOW+80
	ld	de,SHADOW
	ld	bc,23*80
	ldir
	ld	h,d
	ld	l,e
	inc	de
	ld	(hl),' '
	ld	bc,79
	ldir
	jr	vredraw

; A as the second style shows it: 25h-5Fh at 85h-BFh, 60h-7Fh at
; 00h-1Fh. Space and 21h-24h stay as they are, since the test glyphs
; are over 80h-84h.
tmap:	cp	25h
	ret	c
	cp	60h
	jr	nc,tmp1
	add	a,60h
	ret
tmp1:	cp	80h
	ret	nc
	sub	60h
	ret

; Clear the screen and the whole 2K of video RAM, cursor home, thick
; The line a cut results area ends with
pmore:	call	print
	db	TH,"More lines: see the serial copy, or run the test alone.",TK,0
	ret

vcls:	xor	a
	ld	(thin),a
	ld	(rmode),a
	ld	(ovrun),a
	ld	(rclip),a
	ld	hl,SHADOW
	ld	de,SHADOW+1
	ld	bc,24*80-1
	ld	(hl),' '
	ldir
	ld	hl,0
	ld	(crow),hl
	ld	a,' '
	jr	vfill

; The shadow copy back onto the screen, and spaces in the 128 bytes
; past it. vredraw, vfill and fontload use the block at F000h and do
; nothing while it is moved, so a scroll then is only in SHADOW until
; the next redraw.
vredraw:
	call	blkmov
	ret	nz
	ld	a,(vlnow)
	ld	(VLATCH),a
	ld	hl,SHADOW
	ld	de,VIDLO
	ld	bc,400h
	ldir
	ld	de,VIDWIN
	ld	bc,24*80-400h
	ldir
	ld	h,d
	ld	l,e
	inc	de
	ld	(hl),' '
	ld	bc,800h-24*80-1
	ldir
	ret

; A into every byte of video RAM
vfill:	push	af
	call	blkmov
	pop	bc
	ret	nz
	ld	a,b
	ld	hl,VIDLO
	ld	de,VIDLO+1
	ld	bc,3FFh
	ld	(hl),a
	ldir
	ld	hl,VIDWIN
	ld	de,VIDWIN+1
	ld	bc,3FFh
	ld	(hl),a
	ldir
	ret

; NZ if the I/O block is not at F000h
blkmov:	ld	a,(blkhi)
	cp	high BLK
	ret

; HL = row L x 80 + column H, the offset in video RAM. Keeps A.
vidx:	push	af
	ld	a,h
	ld	h,0
	add	hl,hl
	add	hl,hl
	ld	d,h
	ld	e,l			; row x 4
	add	hl,hl
	add	hl,hl
	add	hl,de			; row x 20
	add	hl,hl
	add	hl,hl			; row x 80
	ld	e,a
	ld	d,0
	add	hl,de
	pop	af
	ret

; DE = the CPU address of video RAM offset HL, with the window on video
; RAM 400h-7FFh: 000h-3FFh at block+C00h, 400h-7FFh at the block. The
; block is where blkhi says. Keeps A, HL.
vaddr:	push	af
	ld	a,(blkhi)
	ld	d,a
	ld	a,h
	add	a,0Ch
	and	0Fh
	or	d
	ld	d,a
	ld	e,l
	pop	af
	ret

; Cursor to row L, column H, on the screen and the terminal. Keeps HL.
at:	ld	(crow),hl
	ld	a,(sioon)
	or	a
	ret	z
	ld	a,1Bh
	call	sout
	ld	a,'['
	call	sout
	ld	a,l
	inc	a
	call	sdec
	ld	a,';'
	call	sout
	ld	a,h
	inc	a
	call	sdec
	ld	a,'H'
	jp	sout

; Spaces from the cursor to the end of the row, cursor kept. Keeps HL.
clreol:	push	hl
	ld	a,(scrout)
	or	a
	jr	z,ce2
	ld	hl,(crow)
	push	hl
	call	vidx
	pop	bc			; B = column
	ld	a,80
	sub	b
	ld	b,a
ce1:	call	vaddr
	ld	a,' '
	ld	(de),a
	push	hl
	ld	de,SHADOW
	add	hl,de
	ld	(hl),a
	pop	hl
	inc	hl
	djnz	ce1
ce2:	ld	a,(sioon)
	or	a
	jr	z,ce3
	ld	a,1Bh
	call	sout
	ld	a,'['
	call	sout
	ld	a,'K'
	call	sout
ce3:	pop	hl
	ret

; The string after the call, to a 0
print:	ex	(sp),hl
	call	puts
	ex	(sp),hl
	ret

; The string at HL, to a 0. HL comes back past the 0.
puts:	ld	a,(hl)
	inc	hl
	or	a
	ret	z
	call	putc
	jr	puts

; A as two hex digits and an h
phex8:	push	af
	rrca
	rrca
	rrca
	rrca
	call	phex4
	pop	af
	push	af
	call	phex4
	ld	a,'h'
	call	putc
	pop	af
	ret
phex4:	and	0Fh
	add	a,90h
	daa
	adc	a,40h
	daa
	jp	putc

; HL as four hex digits and an h
phex16:	ld	a,h
	push	af
	rrca
	rrca
	rrca
	rrca
	call	phex4
	pop	af
	call	phex4
	ld	a,l
	jr	phex8

; A as 8 binary digits, bit 7 first
pbin8:	push	af
	push	bc
	ld	c,a
	ld	b,8
pb1:	ld	a,'0'
	rl	c
	adc	a,0
	call	putc
	djnz	pb1
	pop	bc
	pop	af
	ret

; HL in decimal, no leading zeros. Keeps HL.
pdec16:	push	bc
	push	de
	push	hl
	ld	e,0			; set once a digit is printed
	ld	bc,-10000
	call	pdig
	ld	bc,-1000
	call	pdig
	ld	bc,-100
	call	pdig
	ld	bc,-10
	call	pdig
	ld	a,l
	add	a,'0'
	call	putc
	pop	hl
	pop	de
	pop	bc
	ret
pdig:	ld	a,'0'-1
pd1:	inc	a
	add	hl,bc
	jr	c,pd1
	sbc	hl,bc			; carry is clear: one too many
	cp	'0'
	jr	nz,pd2
	bit	0,e
	ret	z
pd2:	ld	e,1
	jp	putc

; The character in C to SIO A, FF as a VT100 clear
sputc:	ld	a,(sioon)
	or	a
	ret	z
	ld	a,c
	cp	0Ch
	jr	nz,sout
	ld	hl,ansicls
sp1:	ld	a,(hl)
	or	a
	ret	z
	call	sout
	inc	hl
	jr	sp1
ansicls:
	db	1Bh,"[2J",1Bh,"[H",0

; A to SIO A once the transmitter is empty, in the block where blkhi
; says. A transmitter that stays full for about 40 ms turns the copy
; off. Keeps BC, DE, HL.
sout:	push	bc
	push	de
	push	hl
	ld	c,a
	ld	a,(blkhi)
	or	high (SIOCA-BLK)
	ld	h,a
	ld	l,low SIOCA
	ld	de,4000
so1:	bit	2,(hl)
	jr	nz,so2
	dec	de
	ld	a,d
	or	e
	jr	nz,so1
	xor	a
	ld	(sioon),a
	jr	so3
so2:	ld	l,low SIODA
	ld	(hl),c
so3:	pop	hl
	pop	de
	pop	bc
	ret

; A, 1 to 99, in decimal to SIO A. Keeps BC.
sdec:	push	bc
	ld	b,'0'-1
sd1:	inc	b
	sub	10
	jr	nc,sd1
	add	a,10+'0'
	ld	c,a
	ld	a,b
	cp	'0'
	call	nz,sout
	ld	a,c
	call	sout
	pop	bc
	ret
