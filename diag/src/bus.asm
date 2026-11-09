; Expansion bus test: all 256 ports read and shown, a card's ports
; standing out from the floating FFh, and one port written, read and
; checked for read-back. ESC or BREAK goes back to the menu.

BXCOL	equ	54			; the column of the labels at the right
BXVAL	equ	69			; and of their values
BXDRAW	equ	10			; ticks between redraws
BXBURST	equ	64			; INs or OUTs a turn of the loop

bxtest:	ld	a,1			; keys are caught while the screen is drawn
	ld	(kpoll),a
	xor	a
	ld	(kkey),a
	ld	(bxport),a
	ld	(bxbyte),a
	ld	(bxmode),a
	ld	(bxent),a
	ld	(bxck),a
	ld	hl,0
	ld	(bxcnt),hl
	ld	a,0Ch
	call	putc
	call	print
	db	"EXPANSION BUS TEST",0
	ld	hl,3*256+2		; the low digit of each column
	call	at
	call	print
	db	TH," 0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F",TK,0
	ld	hl,BXCOL*256+2
	ld	de,bxlabs
bx1:	call	at
	ex	de,hl
	call	puts
	ex	de,hl
	inc	l
	ld	a,(de)
	or	a
	jr	nz,bx1
	ld	a,0FFh			; all drawn on the first turn
	ld	(bxdmode),a
	ld	(bxdck),a
	ld	(bxdbyte),a		; the byte starts at 00h
	ld	(bxdport),a		; and the port at 00h
	ld	hl,0FFFFh
	ld	(bxdcnt),hl
	call	bxscan
	ld	a,(bxrd)
	cpl
	ld	(bxdrd),a
	call	bxlive
bxl1:	call	inkey
	jr	z,bxl2
	call	bxkey
	jr	c,bxexit
	call	bxlive
bxl2:	ld	a,(bxmode)
	dec	a
	call	z,bxwb
	ld	a,(bxmode)
	cp	2
	call	z,bxrb
	ld	hl,(ticks)
	ld	de,(bxdt)
	or	a
	sbc	hl,de
	ld	de,BXDRAW
	or	a
	sbc	hl,de
	call	nc,bxlive
	jr	bxl1
bxexit:	xor	a
	ld	(kpoll),a
	jp	drawmenu

; A key in A. Carry to leave.
bxkey:	ld	b,a
	ld	a,(bxent)
	or	a
	jp	nz,bxhexk
	ld	a,b
	cp	1Bh
	jr	z,bxkx
	cp	03h			; BREAK
	jr	z,bxkx
	ld	c,-16
	cp	80h			; up
	jr	z,bxk1
	ld	c,16
	cp	81h			; down
	jr	z,bxk1
	ld	c,-1
	cp	82h			; left
	jr	z,bxk1
	ld	c,1
	cp	83h			; right
	jr	nz,bxk2
bxk1:	ld	a,(bxport)
	add	a,c
	call	bxmove
	or	a
	ret
bxk2:	ld	c,1
	cp	'P'
	jr	z,bxk3
	inc	c
	cp	'V'
	jr	nz,bxk4
bxk3:	ld	a,c			; typing starts: 1 the port, 2 the byte
	ld	(bxent),a
	xor	a
	ld	(bxhex),a
	ld	(bxhn),a
	call	bxpent
	or	a
	ret
bxk4:	cp	'O'
	jr	nz,bxk5
	ld	a,(bxport)
	ld	c,a
	ld	a,(bxbyte)
	out	(c),a
	ld	hl,bxcnt
	call	inc16
	or	a
	ret
bxk5:	ld	b,1
	cp	'W'
	jr	z,bxk6
	inc	b
	cp	'R'
	jr	nz,bxk7
bxk6:	ld	a,(bxmode)		; the same key again stops it
	cp	b
	ld	a,0
	jr	z,bxk6a
	ld	a,b
bxk6a:	ld	(bxmode),a
	or	a
	ret
bxk7:	cp	'K'
	jr	nz,bxk8
	call	bxcheck
	or	a
	ret
bxk8:	cp	'S'
	call	z,bxscan
	or	a
	ret
bxkx:	scf
	ret

; A hex digit in B for the field being typed. Any other key ends the
; typing with the field as it was.
bxhexk:	ld	a,b
	sub	'0'
	jr	c,bxhx
	cp	10
	jr	c,bxh1
	sub	'A'-'0'-10
	cp	10
	jr	c,bxhx
	cp	16
	jr	nc,bxhx
bxh1:	ld	b,a
	ld	a,(bxhex)
	rlca
	rlca
	rlca
	rlca
	or	b
	ld	(bxhex),a
	ld	hl,bxhn
	inc	(hl)
	ld	a,(hl)
	cp	2
	jr	z,bxh2
	call	bxpent
	or	a
	ret
bxh2:	ld	a,(bxent)
	dec	a
	ld	a,(bxhex)
	jr	nz,bxh3
	call	bxmove
	jr	bxhx
bxh3:	ld	(bxbyte),a
bxhx:	xor	a			; both fields drawn again
	ld	(bxent),a
	ld	a,(bxport)
	cpl
	ld	(bxdport),a
	ld	a,(bxbyte)
	cpl
	ld	(bxdbyte),a
	or	a
	ret

; The field being typed: the digit so far and a _ for each to come
bxpent:	ld	a,(bxent)
	ld	l,2
	dec	a
	jr	z,bpe1
	ld	l,4
bpe1:	ld	h,BXVAL
	call	at
	ld	a,(bxhn)
	or	a
	jr	z,bpe2
	ld	a,(bxhex)
	call	phex4
	call	print
	db	"_h",0
	ret
bpe2:	call	print
	db	"__h",0
	ret

; The port in A becomes the one chosen. Its brackets move on the grid,
; and its last read and the read-back check start from its scan.
bxmove:	push	af
	call	bxsync			; the old port's last read kept first
	pop	af
	ld	hl,bxport
	ld	b,(hl)
	ld	(hl),a
	ld	a,b
	call	bxseps
	ld	a,(bxport)
	call	bxseps
	call	bxvp
	ld	a,(hl)
	ld	(bxrd),a
	xor	a
	ld	(bxck),a
	ret

; OUT the byte BXBURST times, counted
bxwb:	ld	a,(bxport)
	ld	c,a
	ld	a,(bxbyte)
	ld	b,BXBURST
bwb1:	out	(c),a
	djnz	bwb1
	ld	hl,(bxcnt)
	ld	de,BXBURST
	add	hl,de
	jr	nc,bwb2
	ld	hl,0FFFFh
bwb2:	ld	(bxcnt),hl
	ret

; IN the port BXBURST times, the last kept
bxrb:	ld	a,(bxport)
	ld	c,a
	ld	b,BXBURST
brb1:	in	a,(c)
	djnz	brb1
	ld	(bxrd),a
	ret

; Each pattern of bxpats written and read back, stopping at the first
; that does not come back
bxcheck:
	ld	a,(bxport)
	ld	c,a
	ld	hl,bxpats
	ld	b,12
bck1:	ld	a,(hl)
	ld	(bxckw),a
	out	(c),a
	push	hl
	ld	hl,bxcnt
	call	inc16
	pop	hl
	ld	e,a
	in	a,(c)
	ld	(bxckr),a
	ld	(bxrd),a
	cp	e
	ld	a,2			; FAIL
	jr	nz,bck2
	inc	hl
	djnz	bck1
	dec	a			; PASS
bck2:	ld	(bxck),a
	ret

; All 256 ports read into bxval and drawn
bxscan:	ld	hl,bxval
	ld	bc,0
bsc1:	in	a,(c)
	ld	(hl),a
	inc	hl
	inc	c
	jr	nz,bsc1
	call	bxvp
	ld	a,(hl)
	ld	(bxrd),a
	ld	b,0
bsc2:	call	bxrow
	inc	b
	ld	a,b
	cp	16
	jr	nz,bsc2
	jp	bxnffd

; HL = the chosen port's place in bxval
bxvp:	ld	a,(bxport)
	ld	l,a
	ld	h,0
	ld	de,bxval
	add	hl,de
	ret

; Grid row B, ports B0h-BFh, on screen row B+3. Keeps BC.
bxrow:	push	bc
	ld	a,b
	add	a,3
	ld	l,a
	ld	h,0
	call	at
	ld	a,TH
	call	putc
	ld	a,b
	call	phex4
	ld	a,'0'
	call	putc
	ld	a,TK
	call	putc
	ld	a,b
	rlca
	rlca
	rlca
	rlca
	ld	d,a
	ld	e,0
bro1:	call	bxsch
	call	putc
	ld	a,e
	cp	16
	jr	z,bro2
	add	a,d
	call	bxv2
	inc	e
	jr	bro1
bro2:	pop	bc
	ret

; A = the character left of column E (0-16) of the row starting at port
; D: [ before the chosen port, ] after it, else a space
bxsch:	ld	a,(bxport)
	sub	d
	cp	16
	jr	nc,bsh1
	cp	e
	ld	a,'['
	ret	z
	ld	a,(bxport)
	sub	d
	inc	a
	cp	e
	ld	a,']'
	ret	z
bsh1:	ld	a,' '
	ret

; The separators either side of port A, drawn again
bxseps:	ld	b,a
	and	0F0h
	ld	d,a
	ld	a,b
	and	0Fh
	ld	e,a
	call	bss1
	inc	e
bss1:	ld	a,e
	ld	h,a
	add	a,a
	add	a,h
	add	a,2
	ld	h,a
	ld	a,d
	rrca
	rrca
	rrca
	rrca
	add	a,3
	ld	l,a
	call	at
	call	bxsch
	jp	putc

; Port A's scanned value drawn on the grid
bxcell:	ld	b,a
	and	0Fh
	ld	h,a
	add	a,a
	add	a,h
	add	a,3
	ld	h,a
	ld	a,b
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	add	a,3
	ld	l,a
	call	at
	ld	a,b
; Port A's scanned value as two digits, thin if FFh. Keeps DE and HL.
bxv2:	push	hl
	push	de
	ld	l,a
	ld	h,0
	ld	de,bxval
	add	hl,de
	ld	a,(hl)
	pop	de
	pop	hl
	cp	0FFh
	jr	nz,bv1
	call	print
	db	TH,"FF",TK,0
	ret
bv1:	push	af
	rrca
	rrca
	rrca
	rrca
	call	phex4
	pop	af
	jp	phex4

; The grid follows the chosen port's last read
bxsync:	call	bxvp
	ld	a,(bxrd)
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	a,(bxport)
	call	bxcell
	jp	bxnffd

; The count of ports not reading FFh
bxnffd:	ld	hl,bxval
	ld	de,0
	ld	b,0
bnf1:	ld	a,(hl)
	inc	a
	jr	z,bnf2
	inc	de
bnf2:	inc	hl
	djnz	bnf1
	ld	hl,BXVAL*256+7
	call	at
	ex	de,hl
	call	pdec16
	jp	clreol

; Draw the fields that changed since the last time
bxlive:	ld	hl,(ticks)
	ld	(bxdt),hl
	ld	a,(bxent)		; fields being typed are left alone
	or	a
	jr	nz,bli2
	ld	a,(bxport)
	ld	hl,bxdport
	cp	(hl)
	jr	z,bli1
	ld	(hl),a
	ld	hl,BXVAL*256+2
	call	at
	ld	a,(bxdport)
	call	phex8
bli1:	ld	a,(bxbyte)
	ld	hl,bxdbyte
	cp	(hl)
	jr	z,bli2
	ld	(hl),a
	ld	hl,BXVAL*256+4
	call	at
	ld	a,(bxdbyte)
	call	phex8
bli2:	ld	a,(bxrd)
	ld	hl,bxdrd
	cp	(hl)
	jr	z,bli3
	ld	(hl),a
	ld	hl,BXVAL*256+3
	call	at
	ld	a,(bxdrd)
	call	phex8
bli3:	call	bxsync
	ld	hl,(bxcnt)
	ld	de,(bxdcnt)
	or	a
	sbc	hl,de
	jr	z,bli5
	add	hl,de
	ld	(bxdcnt),hl
	ld	hl,BXVAL*256+5
	call	at
	ld	hl,(bxcnt)
	call	pdec16
	call	clreol
bli5:	ld	a,(bxmode)
	ld	hl,bxdmode
	cp	(hl)
	jr	z,bli7
	ld	(hl),a
	ld	hl,BXVAL*256+6
	call	at
	ld	a,(bxmode)
	ld	hl,bxmidle
	or	a
	jr	z,bli6
	ld	hl,bxmwr
	dec	a
	jr	z,bli6
	ld	hl,bxmrd
bli6:	call	puts
bli7:	ld	a,(bxck)
	ld	hl,bxdck
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	hl,BXVAL*256+8
	call	at
	ld	hl,bxnt
	ld	a,(bxck)
	or	a
	jr	z,bli8
	ld	hl,bxpass
	dec	a
	jr	z,bli8
	ld	hl,bxfail
bli8:	call	puts
	call	clreol
	ld	hl,BXCOL*256+9		; what failed, or nothing
	call	at
	call	clreol
	ld	a,(bxck)
	cp	2
	ret	nz
	call	print
	db	TH,"Wrote ",TK,0
	ld	a,(bxckw)
	call	phex8
	call	print
	db	TH,", read ",TK,0
	ld	a,(bxckr)
	jp	phex8

; The labels and keys at the right, rows 2-19
bxlabs:	db	TH,"Port:",TK,0
	db	TH,"Reads:",TK,0
	db	TH,"Byte to write:",TK,0
	db	TH,"Writes:",TK,0
	db	TH,"Mode:",TK,0
	db	TH,"Ports not FFh:",TK,0
	db	TH,"Read back:",TK,0
	db	" ",0
	db	" ",0
	db	"Arrows ",TH,"Move the port",TK,0
	db	"P      ",TH,"Type a port, hex",TK,0
	db	"V      ",TH,"Type the byte, hex",TK,0
	db	"O      ",TH,"OUT it once",TK,0
	db	"W      ",TH,"OUT it repeatedly",TK,0
	db	"R      ",TH,"IN it repeatedly",TK,0
	db	"K      ",TH,"Check read-back",TK,0
	db	"S      ",TH,"Scan all 256 again",TK,0
	db	"ESC    ",TH,"Back to the menu",TK,0
	db	0

bxpats:	db	00h,0FFh,55h,0AAh,01h,02h,04h,08h,10h,20h,40h,80h
bxmidle:	db	"IDLE   ",0
bxmwr:	db	"WRITING",0
bxmrd:	db	"READING",0
bxnt:	db	"NOT TESTED",0
bxpass:	db	"PASS",0
bxfail:	db	"FAIL",0
