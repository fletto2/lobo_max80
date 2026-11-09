; Printer port test: the four status inputs read live, each marked once
; it has changed, the eight data outputs set by key or walked, and a
; test line sent while BUSY allows. ESC or BREAK goes back to the menu.

PPCOL	equ	30			; the column of the values
PPDRAW	equ	10			; ticks between redraws
PPWALK	equ	30			; ticks a step of the walk

pptest:	ld	a,1			; keys are caught while the screen is drawn
	ld	(kpoll),a
	xor	a
	ld	(kkey),a
	ld	(ppmode),a
	ld	(ppchg),a
	ld	(ppidx),a
	ld	hl,0
	ld	(ppcnt),hl
	ld	a,0Ch
	call	putc
	call	print
	db	"PRINTER PORT TEST",0
	ld	hl,2
	call	at
	call	print
	db	TH,"Status, PSTAT:",0Dh,0Ah,0Dh,0Ah
	db	"BUSY, pin 21, bit 7:",0Dh,0Ah
	db	"OUTPAPER, pin 23, bit 6:",0Dh,0Ah
	db	"UNITSELCT, pin 25, bit 5:",0Dh,0Ah
	db	"FAULT, pin 28, bit 4:",0Dh,0Ah
	db	"Ready for CP/M, BUSY LOW:",0Dh,0Ah
	db	"Ready for LDOS, status 3Xh:",0Dh,0Ah,0Ah
	db	"Data out, PDATA:",0Dh,0Ah
	db	"PD7-PD0, pins 17-3:",0Dh,0Ah
	db	"Writes, each strobes pin 1:",0Dh,0Ah
	db	"Mode:",TK,0Dh,0Ah,0Ah
	db	" 0-7  ",TH,"Toggle a data bit, PD0-PD7    ",TK," Z    ",TH,"All outputs 00h",TK,0Dh,0Ah
	db	" F    ",TH,"All outputs FFh               ",TK," W    ",TH,"Walk a 1 across the outputs",TK,0Dh,0Ah
	db	" S    ",TH,"Send a test line over and over",TK," ESC  ",TH,"Back to the menu",TK,0
	ld	hl,PPCOL*256+3
	call	at
	call	print
	db	TH,"Level   Changed",TK,0
	ld	a,(PSTAT)
	ld	(ppfirst),a
	ld	a,0FFh			; all drawn on the first turn
	ld	(ppdchg),a
	ld	(ppddata),a
	ld	(ppdmode),a
	ld	hl,0FFFFh
	ld	(ppdcnt),hl
	xor	a
	call	ppout
	call	ppshow
ppl1:	ld	a,(PSTAT)
	ld	hl,ppfirst
	xor	(hl)
	ld	hl,ppchg
	or	(hl)
	ld	(hl),a
	call	inkey
	jr	z,ppl2
	call	ppkey
	jr	c,ppexit
ppl2:	ld	a,(ppmode)
	cp	1
	call	z,ppsend
	ld	a,(ppmode)
	cp	2
	call	z,ppwstep
	ld	hl,(ticks)
	ld	de,(ppdt)
	or	a
	sbc	hl,de
	ld	de,PPDRAW
	or	a
	sbc	hl,de
	call	nc,ppshow
	jr	ppl1
ppexit:	xor	a
	ld	(kpoll),a
	jp	drawmenu

; A key in A. Carry to leave.
ppkey:	cp	1Bh
	jr	z,ppkx
	cp	03h			; BREAK
	jr	z,ppkx
	cp	'0'
	jr	c,ppk1
	cp	'8'
	jr	nc,ppk1
	sub	'0'-1
	ld	b,a
	ld	a,80h
ppk0:	rlca				; bit 0-7
	djnz	ppk0
	ld	hl,ppdata
	xor	(hl)
	jr	ppkw
ppk1:	cp	'Z'
	jr	nz,ppk2
	xor	a
	jr	ppkw
ppk2:	cp	'F'
	jr	nz,ppk3
	ld	a,0FFh
ppkw:	ld	b,a			; a byte set by hand stops the modes
	xor	a
	ld	(ppmode),a
	ld	a,b
	call	ppout
	or	a
	ret
ppk3:	ld	b,2
	cp	'W'
	jr	z,ppk4
	dec	b
	cp	'S'
	jr	z,ppk4
	or	a
	ret
ppk4:	ld	a,(ppmode)		; the same key again stops it
	cp	b
	ld	a,0
	jr	z,ppk5
	ld	a,b
ppk5:	ld	(ppmode),a
	cp	1
	jr	nz,ppk6
	xor	a			; the test line from its start
	ld	(ppidx),a
ppk6:	ld	a,(ppmode)
	cp	2
	jr	nz,ppk7
	ld	hl,(ticks)
	ld	(ppwt),hl
	ld	a,1
	call	ppout
ppk7:	or	a
	ret
ppkx:	scf
	ret

; A to PDATA, kept in ppdata and counted. Keeps AF.
ppout:	ld	(ppdata),a
	ld	(PDATA),a
	ld	hl,ppcnt
	jp	inc16

; The next byte of the test line, if BUSY is low
ppsend:	ld	a,(PSTAT)
	rla
	ret	c
	ld	a,(ppidx)
	ld	e,a
	ld	d,0
	ld	hl,pptext
	add	hl,de
	ld	a,(hl)
	or	a
	jr	nz,pps1
	ld	(ppidx),a		; the end: from the start again
	ld	a,(pptext)
pps1:	call	ppout
	ld	hl,ppidx
	inc	(hl)
	ret

; The walk's next step, once PPWALK ticks have passed
ppwstep:
	ld	hl,(ticks)
	ld	de,(ppwt)
	or	a
	sbc	hl,de
	ld	de,PPWALK
	or	a
	sbc	hl,de
	ret	c
	ld	hl,(ticks)
	ld	(ppwt),hl
	ld	a,(ppdata)
	rlca
	or	a
	jr	nz,ppout
	inc	a
	jr	ppout

; Draw the fields that changed since the last time
ppshow:	ld	hl,(ticks)
	ld	(ppdt),hl
	ld	a,(PSTAT)
	ld	hl,ppdst
	cp	(hl)
	ld	(hl),a
	jr	nz,psh1
	ld	a,(ppchg)
	ld	hl,ppdchg
	cp	(hl)
	jr	z,psh2
psh1:	ld	a,(ppchg)
	ld	(ppdchg),a
	call	ppinp
psh2:	ld	a,(ppdata)
	ld	hl,ppddata
	cp	(hl)
	jr	z,psh3
	ld	(hl),a
	ld	hl,PPCOL*256+11
	call	at
	ld	a,(ppdata)
	call	phex8
	ld	hl,PPCOL*256+12
	call	at
	ld	a,(ppdata)
	call	pbin8
psh3:	ld	hl,(ppcnt)
	ld	de,(ppdcnt)
	or	a
	sbc	hl,de
	jr	z,psh4
	add	hl,de
	ld	(ppdcnt),hl
	ld	hl,PPCOL*256+13
	call	at
	ld	hl,(ppcnt)
	call	pdec16
	call	clreol
psh4:	ld	a,(ppmode)
	ld	hl,ppdmode
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	hl,PPCOL*256+14
	call	at
	ld	a,(ppmode)
	ld	hl,ppmidle
	or	a
	jr	z,psh5
	ld	hl,ppmsend
	dec	a
	jr	z,psh5
	ld	hl,ppmwalk
psh5:	jp	puts

; The status rows, from ppdst and ppdchg
ppinp:	ld	hl,PPCOL*256+2
	call	at
	ld	a,(ppdst)
	call	phex8
	ld	a,(ppdst)
	ld	e,a			; levels, bit 7 first
	ld	a,(ppdchg)
	ld	d,a			; changed
	ld	hl,PPCOL*256+4
ppi1:	call	at
	push	hl
	ld	hl,pplow
	rl	e
	jr	nc,ppi2
	ld	hl,pphigh
ppi2:	call	puts
	pop	hl
	ld	a,h
	add	a,8
	ld	h,a
	call	at
	push	hl
	ld	hl,dpno
	rl	d
	jr	nc,ppi3
	ld	hl,dpyes
ppi3:	call	puts
	pop	hl
	ld	h,PPCOL
	inc	l
	ld	a,l
	cp	8
	jr	nz,ppi1
	call	at			; row 8, CP/M: BUSY low
	ld	a,(ppdst)
	ld	hl,dpyes
	rla
	jr	nc,ppi4
	ld	hl,dpno
ppi4:	call	puts
	ld	hl,PPCOL*256+9		; LDOS: bits 7-4 are 0011
	call	at
	ld	a,(ppdst)
	and	0F0h
	cp	30h
	ld	hl,dpyes
	jr	z,ppi5
	ld	hl,dpno
ppi5:	jp	puts

pplow:	db	"LOW ",0
pphigh:	db	"HIGH",0
ppmidle:	db	"IDLE   ",0
ppmsend:	db	"SENDING",0
ppmwalk:	db	"WALKING",0
pptext:	db	"THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789",0Dh,0Ah,0
