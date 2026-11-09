; Clock chip test: the MSM5832's 13 registers read live and decoded, the
; digits checked against their ranges, the second timed against the
; tick, and the rear TIME SET button found the way TIMESET finds it.
; ESC or BREAK goes back to the menu.

RTCOL	equ	30			; the column of the values
RTBTN	equ	30			; ticks between button checks
RTSTOP	equ	120			; ticks with no new second: stopped
RT_RD	equ	20h			; port B: READ
RT_WR	equ	10h			; WRITE
RT_HOLD	equ	40h			; HOLD
RT_PIOA	equ	40h			; port A as the diagnostic keeps it

rttest:	ld	a,1			; keys are caught while the screen is drawn
	ld	(kpoll),a
	xor	a
	ld	(kkey),a
	ld	(rtseen),a
	ld	(rtbtn),a
	ld	a,0Ch
	call	putc
	call	print
	db	"CLOCK CHIP TEST",0
	ld	hl,2
	call	at
	call	print
	db	TH,"Registers 0-12:",0Dh,0Ah
	db	"Time:",0Dh,0Ah
	db	"Hour mode, register 5:",0Dh,0Ah
	db	"Date, month/day/year:",0Dh,0Ah
	db	"Day of the week, register 6:",0Dh,0Ah
	db	"Leap year, register 8 bit 2:",0Dh,0Ah
	db	"Digits in range:",0Dh,0Ah,0Ah
	db	"Seconds counting:",0Dh,0Ah
	db	"Ticks a second:",0Dh,0Ah
	db	"TIME SET button:",TK,0Dh,0Ah,0Ah
	db	" ESC  ",TH,"Back to the menu",TK,0Dh,0Ah,0Ah
	db	TH,"Hold the TIME SET button to see if it registers.",TK,0
	ld	a,0FFh			; all drawn on the first turn
	ld	(rtdreg),a
	ld	(rtdcnt),a
	ld	(rtdbtn),a
	ld	hl,0FFFFh
	ld	(rtdint),hl
	ld	hl,0
	ld	(rtint),hl
	ld	hl,(ticks)
	ld	(rtlast),hl
	ld	(rtbt),hl
	call	rtread
	ld	a,(rtregs)
	ld	(rtsec),a
	call	rtbutton
rtl1:	call	inkey
	jr	z,rtl2
	cp	1Bh
	jr	z,rtexit
	cp	03h			; BREAK
	jr	z,rtexit
rtl2:	call	rtread
	ld	a,(rtregs)		; a new second: time it
	ld	hl,rtsec
	cp	(hl)
	jr	z,rtl3
	ld	(hl),a
	ld	hl,(ticks)
	ld	de,(rtlast)
	ld	(rtlast),hl
	or	a
	sbc	hl,de
	ld	a,(rtseen)		; the first second came part way
	or	a
	jr	z,rtl2a
	ld	(rtint),hl
rtl2a:	ld	a,1
	ld	(rtseen),a
rtl3:	ld	hl,(ticks)
	ld	de,(rtbt)
	or	a
	sbc	hl,de
	ld	de,RTBTN
	or	a
	sbc	hl,de
	call	nc,rtbutton
	call	rtshow
	jr	rtl1
rtexit:	xor	a
	ld	(kpoll),a
	jp	drawmenu

; Register A of the clock to A, bits 3-0
rtget:	or	RT_RD
	ld	(PIODB),a
	ld	a,4			; at least 6 us
rtg1:	dec	a
	jr	nz,rtg1
	ld	a,(PIODA)
	and	0Fh
	ret

; All 13 registers to rtregs, read again until two passes agree
rtread:	ld	c,8			; tries
rtr1:	ld	hl,rtregs
	ld	b,0
rtr2:	ld	a,b
	call	rtget
	ld	(hl),a
	inc	hl
	inc	b
	ld	a,b
	cp	13
	jr	nz,rtr2
	ld	hl,rtregs
	ld	b,0
	ld	e,0			; differences
rtr3:	ld	a,b
	call	rtget
	cp	(hl)
	jr	z,rtr4
	inc	e
rtr4:	inc	hl
	inc	b
	ld	a,b
	cp	13
	jr	nz,rtr3
	xor	a
	ld	(PIODB),a
	ld	a,e
	or	a
	ret	z
	dec	c
	jr	nz,rtr1
	ret

; rtbtn 1 if a write to register 3 takes, so the button is held. The
; old digit goes back under the same HOLD.
rtbutton:
	ld	hl,(ticks)
	ld	(rtbt),hl
	ld	a,RT_HOLD+3
	ld	(PIODB),a
	ld	b,0			; let HOLD settle
rtb1:	djnz	rtb1
	ld	a,RT_HOLD+3
	call	rtget
	ld	c,a			; the old digit
	ld	a,6
	call	rtput
	ld	a,RT_HOLD+3
	call	rtget
	ld	b,0
	cp	6
	jr	nz,rtb2
	inc	b
	ld	a,c
	call	rtput
rtb2:	ld	a,b
	ld	(rtbtn),a
	xor	a
	ld	(PIODB),a
	ret

; A to register 3 under HOLD. Port A goes to all outputs for the write,
; with the RAM bits kept, then back to bits 3-0 in.
rtput:	push	af
	ld	a,0CFh
	ld	(PIOCA),a
	xor	a
	ld	(PIOCA),a
	pop	af
	or	RT_PIOA
	ld	(PIODA),a
	ld	a,RT_HOLD+3
	ld	(PIODB),a
	ld	a,RT_HOLD+RT_WR+3
	ld	(PIODB),a
	ld	a,RT_HOLD+3
	ld	(PIODB),a
	ld	a,0CFh
	ld	(PIOCA),a
	ld	a,0Fh
	ld	(PIOCA),a
	ret

; Draw what changed
rtshow:	ld	hl,rtregs
	ld	de,rtdreg
	ld	b,13
rts1:	ld	a,(de)
	cp	(hl)
	jr	nz,rts2
	inc	hl
	inc	de
	djnz	rts1
	jr	rts3
rts2:	ld	hl,rtregs
	ld	de,rtdreg
	ld	bc,13
	ldir
	call	rtregsd
rts3:	ld	hl,(ticks)		; counting, if a second came lately
	ld	de,(rtlast)
	or	a
	sbc	hl,de
	ld	de,RTSTOP
	or	a
	sbc	hl,de
	ld	a,0			; 0 NO, 1 YES, 2 WAITING for the first
	jr	nc,rts4
	ld	a,(rtseen)
	or	a
	jr	nz,rts4
	ld	a,2
rts4:	ld	hl,rtdcnt
	cp	(hl)
	jr	z,rts6
	ld	(hl),a
	ld	hl,RTCOL*256+10
	call	at
	ld	hl,dpno
	ld	a,(rtdcnt)
	or	a
	jr	z,rts5
	ld	hl,dpyes
	dec	a
	jr	z,rts5
	ld	hl,rtwait
rts5:	call	puts
	call	clreol
rts6:	ld	hl,(rtint)
	ld	de,(rtdint)
	or	a
	sbc	hl,de
	jr	z,rts8
	add	hl,de
	ld	(rtdint),hl
	ld	hl,RTCOL*256+11
	call	at
	ld	hl,(rtint)
	ld	a,h
	or	l
	jr	nz,rts7
	call	print
	db	"TIMING",0
	jr	rts8
rts7:	call	pdec16
	call	clreol
rts8:	ld	a,(rtbtn)
	ld	hl,rtdbtn
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	hl,RTCOL*256+12
	call	at
	ld	hl,rtnot
	ld	a,(rtdbtn)
	or	a
	jr	z,rts9
	ld	hl,rtheld
rts9:	jp	puts

; The register rows, 2-8, from rtdreg
rtregsd:
	ld	hl,RTCOL*256+2
	call	at
	ld	hl,rtdreg
	ld	b,13
rd1:	ld	a,(hl)
	call	phex4
	ld	a,' '
	call	putc
	inc	hl
	djnz	rd1
	ld	hl,RTCOL*256+3		; hours tens without the mode bits
	call	at
	ld	a,(rtdreg+5)
	and	3
	ld	h,a
	ld	a,(rtdreg+4)
	call	rtpair
	ld	a,':'
	call	putc
	ld	hl,(rtdreg+2)		; L units, H tens
	call	rtpairhl
	ld	a,':'
	call	putc
	ld	hl,(rtdreg+0)
	call	rtpairhl
	ld	hl,RTCOL*256+4
	call	at
	ld	hl,rt24
	ld	a,(rtdreg+5)
	bit	3,a
	jr	nz,rd2
	ld	hl,rtam
	bit	2,a
	jr	z,rd2
	ld	hl,rtpm
rd2:	call	puts
	ld	hl,RTCOL*256+5
	call	at
	ld	hl,(rtdreg+9)		; month
	call	rtpairhl
	ld	a,'/'
	call	putc
	ld	a,(rtdreg+8)		; day, tens without the leap bit
	and	3
	ld	h,a
	ld	a,(rtdreg+7)
	call	rtpair
	ld	a,'/'
	call	putc
	ld	hl,(rtdreg+11)		; year
	call	rtpairhl
	ld	hl,RTCOL*256+6
	call	at
	ld	a,(rtdreg+6)
	call	phex4
	ld	hl,RTCOL*256+7
	call	at
	ld	hl,dpno
	ld	a,(rtdreg+8)
	bit	2,a
	jr	z,rd3
	ld	hl,dpyes
rd3:	call	puts
	ld	hl,RTCOL*256+8		; each digit against its mask and limit
	call	at
	ld	hl,rtdreg
	ld	de,rtlim
	ld	b,0
rd4:	ld	a,(de)			; mask
	and	(hl)
	inc	de
	ex	de,hl
	cp	(hl)			; limit
	ex	de,hl
	inc	de
	jr	z,rd5
	jr	nc,rd6
rd5:	inc	hl
	inc	b
	ld	a,b
	cp	13
	jr	nz,rd4
	call	print
	db	"YES",0
	jp	clreol
rd6:	call	print
	db	"NO, register ",0
	ld	l,b
	ld	h,0
	call	pdec16
	jp	clreol

; L units and H tens as two digits
rtpairhl:
	ld	a,l
; A units and H tens as two digits
rtpair:	push	af
	ld	a,h
	call	phex4
	pop	af
	jp	phex4

; Each register: the mask of its digit and the largest digit allowed
rtlim:	db	0Fh,9, 0Fh,5, 0Fh,9, 0Fh,5, 0Fh,9, 03h,2, 0Fh,6
	db	0Fh,9, 03h,3, 0Fh,9, 0Fh,1, 0Fh,9, 0Fh,9

rt24:	db	"24-HOUR   ",0
rtam:	db	"12-HOUR AM",0
rtpm:	db	"12-HOUR PM",0
rtwait:	db	"WAITING",0
rtnot:	db	"NOT HELD",0
rtheld:	db	"HELD    ",0
