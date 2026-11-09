; Serial port test: both channels of the SIO, with each output (DTR,
; RTS, break on TxD) turned on and off by a key, the inputs (CTS, DCD,
; break on RxD) read live, the rate picked, a test line sent over and
; over, and the bytes received shown. The Z80 SIO has no loopback mode.
; ESC or BREAK goes back.

; A channel's fields, from IX
SPRATE	equ	0			; COM8116 rate code
SPWR5	equ	1			; WR5 as written
SPSEND	equ	2			; nonzero: sending the test line
SPIDX	equ	3			; and the next byte of it
SPCH	equ	4			; 0 channel A, 1 channel B
SPCNT	equ	5			; bytes received, 2 bytes
SPNEW	equ	7			; nonzero: the bytes received to draw again
SPHIST	equ	8			; the last 8 received, newest last
SPDRATE	equ	16			; and as drawn: the rate
SPDWR5	equ	17			; WR5
SPDSEND	equ	18			; sending
SPDRR0	equ	19			; the inputs
SPDSEL	equ	20			; selected

sptest:	ld	a,1			; keys are caught while the screen is drawn
	ld	(kpoll),a
	xor	a
	ld	(kkey),a
	ld	(spsel),a
	ld	ix,spa
	ld	(ix+SPCH),0
	call	spnew
	ld	ix,spb
	ld	(ix+SPCH),1
	call	spnew
	call	spdraw
spl1:	call	poll
	ld	a,(kkey)
	or	a
	jr	z,spl2
	push	af
	xor	a
	ld	(kkey),a
	pop	af
	call	spkey
	jr	c,spexit
spl2:	ld	ix,spa			; a byte on channel A is a key too
	call	sprx
	jr	nc,spl3
	cp	'a'
	jr	c,spl2a
	cp	'z'+1
	jr	nc,spl2a
	sub	20h
spl2a:	call	spkey
	jr	c,spexit
spl3:	ld	ix,spb
	call	sprx
	ld	ix,spa
	call	spsend
	ld	ix,spb
	call	spsend
	ld	ix,spa
	call	spshow
	ld	ix,spb
	call	spshow
	jr	spl1

; Channel B reset, its outputs off as at power on, and channel A as
; the menu has it, with the screen copy on again
spexit:	ld	a,18h
	ld	(SIOCB),a
	call	sioinit
	xor	a
	ld	(kpoll),a
	inc	a
	ld	(sioon),a
	jp	drawmenu

; The key in A. Carry to leave.
spkey:	cp	1Bh
	jp	z,spkx
	cp	03h			; BREAK
	jp	z,spkx
	ld	c,a
	ld	ix,spa
	ld	a,(spsel)
	or	a
	jr	z,spk1
	ld	ix,spb
spk1:	ld	a,c
	cp	'A'
	jr	nz,spk2
	xor	a
	jr	spk3
spk2:	cp	'B'
	jr	nz,spk4
	ld	a,1
spk3:	ld	(spsel),a
	jr	spkok
spk4:	cp	'R'
	jr	nz,spk5
	call	spaoff
	ld	a,(ix+SPRATE)
	inc	a
	and	0Fh
	ld	(ix+SPRATE),a
	call	spbaud
	jr	spkok
spk5:	ld	b,80h
	cp	'D'
	jr	z,spk6
	ld	b,02h
	cp	'T'
	jr	z,spk6
	ld	b,10h
	cp	'K'
	jr	nz,spk7
spk6:	call	spaoff
	ld	a,(ix+SPWR5)
	xor	b
	ld	(ix+SPWR5),a
	call	spwr5
	jr	spkok
spk7:	cp	'S'
	jr	nz,spk8
	call	spaoff
	ld	a,(ix+SPSEND)
	xor	1
	ld	(ix+SPSEND),a
	ld	(ix+SPIDX),0
	jr	spkok
spk8:	cp	'C'
	jr	nz,spkok
	xor	a
	ld	(ix+SPCNT),a
	ld	(ix+SPCNT+1),a
	inc	a
	ld	(ix+SPNEW),a
spkok:	or	a
	ret
spkx:	scf
	ret

; The screen copy off once channel A is changed, so the test's bytes and
; rates do not mix with it. Keeps BC.
spaoff:	ld	a,(ix+SPCH)
	or	a
	ret	nz
	ld	(sioon),a
	ret

; The channel at IX set up as the menu has channel A: 9600, 8 bits, one
; stop bit, no auto enables, DTR and RTS on, not sending
spnew:	xor	a
	ld	(ix+SPSEND),a
	ld	(ix+SPIDX),a
	ld	(ix+SPCNT),a
	ld	(ix+SPCNT+1),a
	inc	a
	ld	(ix+SPNEW),a
	ld	(ix+SPRATE),0Eh
	ld	(ix+SPWR5),0EAh
	ld	a,0FFh			; all drawn on the first turn
	ld	(ix+SPDRATE),a
	ld	(ix+SPDWR5),a
	ld	(ix+SPDSEND),a
	ld	(ix+SPDRR0),a
	ld	(ix+SPDSEL),a
	call	spbaud
	call	spctl
	ld	de,spsetup
	ld	b,spsetn
spn1:	ld	a,(de)
	ld	(hl),a
	inc	de
	djnz	spn1
spwr5:	call	spctl
	ld	(hl),5
	ld	a,(ix+SPWR5)
	ld	(hl),a
	ret

spsetup:	db	18h,18h,14h,44h,13h,0C1h,11h,0
spsetn	equ	$-spsetup

; The channel's rate code to its COM8116 register
spbaud:	ld	a,(ix+SPCH)
	add	a,a
	add	a,a
	add	a,low BAUDA
	ld	l,a
	ld	h,high BAUDA
	ld	a,(ix+SPRATE)
	ld	(hl),a
	ret

; HL = the channel's control port
spctl:	ld	a,(ix+SPCH)
	add	a,a
	add	a,low SIOCA
	ld	l,a
	ld	h,high SIOCA
	ret

; A = RR0, read after a reset of the latched status bits. HL = the
; control port.
sprr0:	call	spctl
	ld	(hl),10h
	ld	a,(hl)
	ret

; A byte received: carry and the byte in A, counted and kept
sprx:	call	sprr0
	rra
	ret	nc
	dec	hl			; the data port
	ld	a,(hl)
	push	af
	ld	l,(ix+SPCNT)
	ld	h,(ix+SPCNT+1)
	inc	hl
	ld	(ix+SPCNT),l
	ld	(ix+SPCNT+1),h
	push	ix
	pop	hl
	ld	de,SPHIST
	add	hl,de
	ld	d,h
	ld	e,l
	inc	hl
	ld	bc,7
	ldir
	pop	af
	ld	(de),a
	ld	(ix+SPNEW),1
	scf
	ret

; The next byte of the test line, if sending and the transmitter is
; empty
spsend:	ld	a,(ix+SPSEND)
	or	a
	ret	z
	call	sprr0
	and	4
	ret	z
	push	hl
	ld	e,(ix+SPIDX)
	ld	d,0
	ld	hl,sptext
	add	hl,de
	ld	a,(hl)
	or	a
	jr	nz,sps1
	ld	e,a			; the end: from the start again
	ld	a,(sptext)
sps1:	inc	e
	ld	(ix+SPIDX),e
	pop	hl
	dec	hl			; the data port
	ld	(hl),a
	ret

sptext:	db	"THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789",0Dh,0Ah,0

; The screen, values drawn by spshow
spdraw:	ld	a,0Ch
	call	putc
	call	print
	db	"SERIAL PORT TEST",0
	ld	hl,20*256+2
	call	at
	call	print
	db	"Channel A",0
	ld	hl,50*256+2
	call	at
	call	print
	db	"Channel B",0
	ld	hl,splabels
	ld	c,3
spd1:	push	hl
	ld	l,c
	ld	h,0
	call	at
	pop	hl
	ld	a,TH
	call	putc
	call	puts
	ld	a,TK
	call	putc
	inc	c
	ld	a,(hl)
	or	a
	jr	nz,spd1
	ld	hl,13
	call	at
	call	print
	db	" A B  ",TH,"Pick channel A or B           ",TK," R    ",TH,"Next rate",TK,0Dh,0Ah
	db	" D    ",TH,"DTR on or off                 ",TK," T    ",TH,"RTS on or off",TK,0Dh,0Ah
	db	" K    ",TH,"Break on TxD, on or off       ",TK," S    ",TH,"Send a test line over and over",TK,0Dh,0Ah
	db	" C    ",TH,"Clear the bytes received      ",TK," ESC  ",TH,"Back to the menu",TK,0Dh,0Ah,0Ah
	db	TH,"A change to channel A stops the screen copy on it, until ESC puts it back.",TK,0
	ret

; Labels for rows 3-11
splabels:
	db	"Rate:",0
	db	"DTR, pin 20:",0
	db	"RTS, pin 4:",0
	db	"TxD, pin 2:",0
	db	"CTS, pin 5:",0
	db	"DCD, pin 8:",0
	db	"RxD break, pin 3:",0
	db	"Bytes received:",0
	db	"Last received:",0
	db	0

; The values of the channel at IX that changed, in column 20 or 50,
; kept in D
spshow:	ld	d,20
	ld	a,(ix+SPCH)
	or	a
	jr	z,sh1
	ld	d,50
sh1:	ld	a,(spsel)
	cp	(ix+SPCH)
	ld	a,0
	jr	nz,sh2
	inc	a
sh2:	cp	(ix+SPDSEL)
	jr	z,sh3
	ld	(ix+SPDSEL),a
	ld	a,d
	add	a,10
	ld	h,a
	ld	l,2
	call	at
	ld	hl,spsel0
	ld	a,(ix+SPDSEL)
	or	a
	jr	z,sh2a
	ld	hl,spsel1
sh2a:	call	puts
sh3:	ld	a,(ix+SPRATE)
	cp	(ix+SPDRATE)
	jr	z,sh4
	ld	(ix+SPDRATE),a
	ld	l,3
	call	spat
	ld	a,(ix+SPRATE)
	ld	l,a
	ld	h,0
	add	hl,hl
	ld	b,h
	ld	c,l
	add	hl,hl
	add	hl,bc			; 6 bytes each
	ld	bc,sprates
	add	hl,bc
	call	puts
sh4:	ld	a,(ix+SPWR5)
	cp	(ix+SPDWR5)
	jr	nz,sh5
	ld	a,(ix+SPSEND)
	cp	(ix+SPDSEND)
	jr	z,sh7
sh5:	ld	a,(ix+SPWR5)
	ld	(ix+SPDWR5),a
	ld	a,(ix+SPSEND)
	ld	(ix+SPDSEND),a
	ld	l,4
	call	spat
	ld	a,(ix+SPWR5)
	and	80h
	call	sponoff
	ld	l,5
	call	spat
	ld	a,(ix+SPWR5)
	and	02h
	call	sponoff
	ld	l,6
	call	spat
	ld	hl,sptbrk
	ld	a,(ix+SPWR5)
	and	10h
	jr	nz,sh6
	ld	hl,sptsend
	ld	a,(ix+SPSEND)
	or	a
	jr	nz,sh6
	ld	hl,sptidle
sh6:	call	puts
sh7:	call	sprr0
	and	0A8h
	cp	(ix+SPDRR0)
	jr	z,sh8
	ld	(ix+SPDRR0),a
	ld	l,7
	call	spat
	ld	a,(ix+SPDRR0)
	and	20h
	call	sponoff
	ld	l,8
	call	spat
	ld	a,(ix+SPDRR0)
	and	08h
	call	sponoff
	ld	l,9
	call	spat
	ld	hl,spno
	ld	a,(ix+SPDRR0)
	and	80h
	jr	z,sh7a
	ld	hl,spyes
sh7a:	call	puts
sh8:	ld	a,(ix+SPNEW)
	or	a
	ret	z
	ld	(ix+SPNEW),0
	ld	l,10
	call	spat
	ld	l,(ix+SPCNT)
	ld	h,(ix+SPCNT+1)
	call	pdec16
	call	print
	db	"     ",0
	ld	l,11
	call	spat
	ld	a,(ix+SPCNT+1)		; B = how many of the 8 to show
	or	a
	ld	b,8
	jr	nz,sh9
	ld	a,(ix+SPCNT)
	cp	8
	jr	nc,sh9
	ld	b,a
sh9:	push	ix
	pop	hl
	ld	a,SPHIST+8
	sub	b
	ld	e,a
	ld	d,0
	add	hl,de
	ld	a,8
	sub	b
	ld	c,a			; the blanks after them
	ld	a,b
	or	a
	jr	z,sh11
sh10:	ld	a,(hl)
	push	af
	rrca
	rrca
	rrca
	rrca
	call	phex4
	pop	af
	call	phex4
	ld	a,' '
	call	putc
	inc	hl
	djnz	sh10
sh11:	ld	a,c
	or	a
	ret	z
	call	print
	db	"   ",0
	dec	c
	jr	sh11

; Cursor to row L in the column in D
spat:	ld	h,d
	jp	at

; ON if A is nonzero, else OFF
sponoff:
	ld	hl,spoff
	or	a
	jr	z,spo1
	ld	hl,spon
spo1:	jp	puts

spon:	db	"ON ",0
spoff:	db	"OFF",0
spyes:	db	"YES",0
spno:	db	"NO ",0
sptbrk:	db	"BREAK  ",0
sptsend:
	db	"SENDING",0
sptidle:
	db	"IDLE   ",0
spsel0:	db	"        ",0
spsel1:	db	"SELECTED",0

; The COM8116 rates, codes 0-F, 6 bytes each
sprates:
	db	"50   ",0
	db	"75   ",0
	db	"110  ",0
	db	"134.5",0
	db	"150  ",0
	db	"300  ",0
	db	"600  ",0
	db	"1200 ",0
	db	"1800 ",0
	db	"2000 ",0
	db	"2400 ",0
	db	"3600 ",0
	db	"4800 ",0
	db	"7200 ",0
	db	"9600 ",0
	db	"19200",0
