; Disk drive test: select a drive on either connector, step the head,
; load it, keep the 5.25-inch motor running, and show what the drive
; sends back. ESC or BREAK goes back to the menu, or stops a command
; still running.

DRATE0	equ	3			; 15 ms on 8-inch, 30 ms on 5.25-inch, as the boot ROM's
DIDXN	equ	4			; turns timed for the speed
DCMDT	equ	610			; ticks, 10 s, a command may take: a restore
					; over 255 steps at 30 ms takes 7.7 s

; Step rates for r1r0, 2 MHz on 8-inch and 1 MHz on 5.25-inch (Appendix D)
rate8:	db	3,6,10,15
rate5:	db	6,12,20,30

dktest:	xor	a
	ld	(dsel),a
	ld	(dside),a
	ld	(dmotor),a
	ld	(dhead),a
	ld	(kkey),a
	ld	(dres),a
	ld	(dfm),a
	ld	h,a
	ld	l,a
	ld	(drpm),hl
	ld	a,DRATE0
	ld	(drate),a
	ld	a,1			; keys are caught while the screen is drawn
	ld	(kpoll),a
	ld	a,(bootml)
	and	20h
	ld	(deight),a
	call	dlatchw
	ld	a,0D0h xor 0FFh		; force interrupt: type I status from here on
	ld	(FCTRL),a
	call	dkdraw
	call	dhload			; head unloaded
dk1:	call	dkeep
	call	dshow
	call	inkey
	jr	nz,dk2
	call	dspeed
	jr	dk1
dk2:	cp	1Bh
	jr	z,dkexit
	cp	03h			; BREAK
	jr	z,dkexit
	cp	'0'
	jr	c,dk3
	cp	'5'
	jr	nc,dk3
	sub	'0'
	ld	(dsel),a
	call	dlatchw
	jr	dk5
dk3:	ld	hl,dkeys
dk4:	ld	c,a
	ld	a,(hl)
	or	a
	jr	z,dk1			; not a key of this test
	cp	c
	ld	a,c
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	jr	nz,dk4
	ex	de,hl
	call	jphl
dk5:	jr	dk1

; Drive deselected and head unloaded, then the menu. After a command
; that did not finish, a force interrupt in place of the seek.
dkexit:	xor	a
	ld	(kpoll),a
	ld	(dsel),a
	ld	(dhead),a
	call	dlatchw
	ld	a,(dres)
	cp	2
	call	c,dhload
	ld	a,0D0h xor 0FFh
	ld	(FCTRL),a
	jp	drawmenu

dkeys:	db	'C'
	dw	dkconn
	db	'S'
	dw	dkside
	db	'M'
	dw	dkmotor
	db	'H'
	dw	dkhead
	db	'I'
	dw	dkin
	db	'O'
	dw	dkout
	db	'R'
	dw	dkrest
	db	'E'
	dw	dkend
	db	'P'
	dw	dkrate
	db	'A'
	dw	dkids
	db	0

dkconn:	ld	a,(deight)
	xor	20h
	ld	(deight),a
	jr	dlatchw

dkside:	ld	a,(dside)
	xor	1
	ld	(dside),a
	jr	dlatchw

dkmotor:
	ld	a,(dmotor)
	xor	1
	ld	(dmotor),a
	ret	z
	jr	dlatchw			; a write starts the 5.25-inch motor

dkhead:	ld	a,(dhead)
	xor	1
	ld	(dhead),a
	jr	dhload

dkin:	ld	a,50h			; step in, track register updated
	jr	dcmd

; Step out. At track register 0 the head still steps but the register
; stays at 0.
dkout:	ld	a,(FTRACK)
	cpl
	or	a
	ld	a,70h
	jr	nz,dcmd
	ld	a,60h
	jr	dcmd

dkrest:	xor	a			; restore
	jr	dcmd

; Seek to the last track, 76 on 8-inch, 39 on 5.25-inch
dkend:	ld	a,(deight)
	or	a
	ld	a,76
	jr	nz,dke1
	ld	a,39
dke1:	cpl
	ld	(FDATA),a
	ld	a,10h
	jr	dcmd

dkrate:	ld	a,(drate)
	inc	a
	and	3
	ld	(drate),a
	ret

; MLATCH from the settings: the drive select, side 1, 8-inch, double
; density
dlatchw:
	ld	a,(dsel)
	ld	b,a
	xor	a
	inc	b
	scf
dl1:	rla
	djnz	dl1
	rra				; bit n-1 for drive n, 0 for none
	ld	b,a
	ld	a,(dside)
	or	a
	jr	z,dl2
	set	4,b
dl2:	ld	a,(dfm)
	xor	40h			; MLATCH bit 6 set for MFM
	or	b
	ld	b,a
	ld	a,(deight)
	or	b
	ld	(dlatch),a
	ld	(MLATCH),a
	ret

; Seek to the track the FDC is on, loading or unloading the head as
; dhead says
dhload:	ld	hl,(ticks)
	ld	(dhtick),hl
	ld	a,(FTRACK)
	ld	(FDATA),a		; both complemented
	ld	a,10h

; Type I command A, with the head load bit and the step rate added, and
; wait for it to finish, into dres. No verify, so no disk is needed. ESC
; or BREAK stops it, as does an FDC still busy after DCMDT ticks, with a
; force interrupt. Other keys are dropped.
dcmd:	ld	b,a
	ld	a,(dhead)
	or	a
	ld	a,b
	jr	z,dc1
	or	08h
dc1:	ld	b,a
	ld	a,(drate)
	or	b
	cpl
	ld	(FCTRL),a
	ld	b,40			; about 100 us for the FDC to take it
dc2:	djnz	dc2
	ld	hl,(ticks)
	push	hl
dc3:	call	inkey
	jr	z,dc4
	ld	c,2
	cp	1Bh
	jr	z,dcstop
	cp	03h			; BREAK
	jr	z,dcstop
dc4:	ld	a,(FSTAT)
	cpl
	rra
	jr	nc,dcok			; not busy
	ld	hl,(ticks)
	pop	de
	push	de
	or	a
	sbc	hl,de
	ld	de,DCMDT
	or	a
	sbc	hl,de
	jr	c,dc3
	ld	c,3
dcstop:	ld	a,0D0h xor 0FFh
	ld	(FCTRL),a
	jr	dc5
dcok:	ld	c,1
dc5:	pop	de
	ld	a,c
	ld	(dres),a
	ret

; Keep the 5.25-inch motor on with a latch write, and the head loaded
; with a seek in place each second, before the FDC unloads it
dkeep:	ld	a,(dmotor)
	or	a
	jr	z,dkp1
	ld	a,(deight)
	or	a
	jr	nz,dkp1
	ld	a,(dlatch)
	ld	(MLATCH),a
dkp1:	ld	a,(dhead)
	or	a
	ret	z
	ld	hl,(ticks)
	ld	de,(dhtick)
	or	a
	sbc	hl,de
	ld	de,61
	sbc	hl,de
	ret	c
	jp	dhload

; The fixed text
dkdraw:	ld	a,0Ch
	call	putc
	call	print
	db	"DISK DRIVE TEST",0
	ld	hl,dlabels
dd1:	ld	e,(hl)			; row, column, text
	inc	hl
	ld	d,(hl)
	inc	hl
	ex	de,hl
	call	at
	ex	de,hl
	ld	a,TH
	call	putc
	call	puts
	ld	a,TK
	call	putc
	ld	a,(hl)
	or	a
	jr	nz,dd1
	ld	hl,11
	call	at
	call	print
	db	" 1-4  ",TH,"Select drive DS1-DS4",TK,"          0    ",TH,"No drive selected",TK,0Dh,0Ah
	db	" C    ",TH,"8",22h," or 5.25",22h," connector",TK,"         S    ",TH,"Side 0 or 1",TK,0Dh,0Ah
	db	" I    ",TH,"Step in",TK,"                       O    ",TH,"Step out",TK,0Dh,0Ah
	db	" R    ",TH,"Recalibrate to track 0",TK,"        E    ",TH,"Seek to the last track, 76 or 39",TK,0Dh,0Ah
	db	" P    ",TH,"Step rate",TK,"                     H    ",TH,"Head load, 8",22h," pin 18",TK,0Dh,0Ah
	db	" M    ",TH,"Motor, 5.25",22h," pin 16",TK,"           ESC  ",TH,"Back to the menu",TK,0Dh,0Ah
	db	" A    ",TH,"Read the ID fields on the selected side, MFM or FM",TK,0Dh,0Ah,0Ah
	db	TH,"ESC also stops a step or seek still running. A busy FDC stops after 10 s.",TK,0
	ld	a,1
	ld	(ddirty),a
	ret

; A: the ID fields under the head on the selected side, by READ ADDRESS
; up to 40 times, MFM, then FM if MFM found none. One line: the density,
; the track and size the IDs carry, the sector numbers found, in order,
; and any CRC errors and reads that found no ID. Three misses in a row
; end it. Needs a drive selected, the 5.25-inch motor on with M, and an
; index pulse within 2 s.
dkids:	ld	hl,20
	call	at
	call	print
	db	TH,"ID fields under the head:",TK,0
	call	clreol
	ld	hl,21
	call	at
	call	clreol
	ld	a,(dsel)
	or	a
	jr	nz,dki1
	call	print
	db	"NONE: select a drive with 1-4 first",0
	ret
dki1:	ld	a,(deight)
	or	a
	jr	nz,dki0
	ld	a,(dmotor)
	or	a
	jr	nz,dki0
	call	print
	db	"NONE: turn the motor on with M first",0
	ret
dki0:	call	dlatchw
	ld	a,0D0h xor 0FFh		; force interrupt: type I status
	ld	(FCTRL),a
	ld	d,3			; about 2 s for an index pulse
	ld	bc,0
dki5:	ld	a,(FSTAT)		; the index, bit 1, low when there
	and	02h
	jr	z,dki2
	dec	bc
	ld	a,b
	or	c
	jr	nz,dki5
	dec	d
	jr	nz,dki5
	call	print
	db	"NONE: no index pulses, no disk in or the drive not turning",0
	ret
dki2:	call	dkside1
	xor	a
	ld	(dfm),a
	jp	dlatchw

; The selected side, on row 21
dkside1:
	call	print
	db	TH,"Side ",TK,0
	ld	a,(dside)
	add	a,'0'
	call	putc
	call	print
	db	TH,": ",TK,0
	xor	a
	call	dkscan
	jr	nz,dks1
	ld	a,40h
	call	dkscan
	jr	nz,dks1
	call	print
	db	"NONE, MFM or FM",0
	ret
dks1:	ld	a,(dfm)
	or	a
	jr	nz,dks2
	call	print
	db	"MFM",0
	jr	dks3
dks2:	call	print
	db	"FM",0
dks3:	call	print
	db	TH,", track ",TK,0
	ld	a,(dvd)
	ld	l,a
	ld	h,0
	call	pdec16
	call	print
	db	TH,", ",TK,0
	ld	a,(dvd+1)		; 128 << N
	and	3
	ld	b,a
	inc	b
	ld	hl,64
dks4:	add	hl,hl
	djnz	dks4
	call	pdec16
	call	print
	db	TH," bytes, sectors",TK,0
	ld	c,0
dks6:	call	dkadr
	ld	a,(hl)
dks6a:	rrca
	djnz	dks6a
	and	80h
	jr	z,dks7
	ld	a,' '
	call	putc
	push	bc
	ld	l,c
	ld	h,0
	call	pdec16
	pop	bc
dks7:	inc	c
	ld	a,c
	cp	32
	jr	nz,dks6
	ld	a,(dvd+2)
	or	a
	jr	z,dks8
	call	print
	db	TH,", CRC errors ",TK,0
	ld	a,(dvd+2)
	ld	l,a
	ld	h,0
	call	pdec16
dks8:	ld	a,(dmiss)
	or	a
	ret	z
	call	print
	db	TH,", no ID ",TK,0
	ld	a,(dmiss)
	ld	l,a
	ld	h,0
	jp	pdec16

; HL = the byte of sector C in dmap, B = its bit + 1. Keeps C.
dkadr:	ld	a,c
	and	7
	inc	a
	ld	b,a
	ld	a,c
	rrca
	rrca
	rrca
	and	3
	ld	e,a
	ld	d,0
	ld	hl,dmap
	add	hl,de
	ret

; Up to 40 READ ADDRESS at density A (0 MFM, 40h FM) into dmap, the
; track and size into dvd, the CRC errors into dvd+2, the misses into
; dmiss. Three misses in a row end it. NZ if any ID came.
dkscan:	ld	(dfm),a
	call	dlatchw			; the motor on, the side, the density
	xor	a
	ld	hl,dmap
	ld	(hl),a
	inc	hl
	ld	(hl),a
	inc	hl
	ld	(hl),a
	inc	hl
	ld	(hl),a
	ld	(dvd+2),a
	ld	(dvd+3),a
	ld	(dmiss),a
	ld	(drun),a
	ld	b,40
dsc1:	push	bc
	call	dkid1
	pop	bc
	jr	nc,dsc0
	ld	hl,dmiss
	inc	(hl)
	ld	hl,drun
	inc	(hl)
	ld	a,(hl)
	cp	3
	jr	nc,dsc3			; three in a row: done
	jr	dsc2a
dsc0:	ld	c,a
	xor	a
	ld	(drun),a
	ld	a,(did)
	ld	(dvd),a
	ld	a,(did+3)
	ld	(dvd+1),a
	ld	hl,dvd+3
	inc	(hl)
	ld	a,c
	and	08h			; CRC error
	jr	z,dsc2
	ld	hl,dvd+2
	inc	(hl)
	jr	dsc2a
dsc2:	push	bc
	ld	a,(did+2)
	cp	32
	jr	nc,dsc2b
	ld	c,a
	call	dkadr
	ld	a,80h
dsc2c:	rlca
	djnz	dsc2c
	or	(hl)
	ld	(hl),a
dsc2b:	pop	bc
dsc2a:	djnz	dsc1
dsc3:	ld	a,(dvd+3)
	or	a
	ret

; One READ ADDRESS into did. NC and A = the status if an ID came, CY
; if not. The waits count loops, not ticks: a tick poll between two
; bytes would lose one.
dkid1:	ld	a,0C4h xor 0FFh		; read address, 15 ms settle
	ld	(FCTRL),a
	ld	b,40
dki3:	djnz	dki3
	ld	d,3			; about 2 s for the first byte
	ld	bc,0
dki4:	ld	a,(USTAT)
	bit	7,a
	jr	z,dki6			; DRQ
	bit	6,a
	jp	z,dknone		; INTRQ with no byte: no ID found
	dec	bc
	ld	a,b
	or	c
	jr	nz,dki4
	dec	d
	jr	nz,dki4
	jp	dkstop
dki6:	ld	hl,did
	ld	b,6
	ld	de,0
dki7:	ld	a,(USTAT)
	bit	7,a
	jr	z,dki8
	bit	6,a
	jr	z,dknone		; ended short
	dec	de
	ld	a,d
	or	e
	jr	nz,dki7
	jr	dkstop
dki8:	ld	a,(FDATA)
	cpl
	ld	(hl),a
	inc	hl
	djnz	dki7
	ld	de,0
dki9:	ld	a,(USTAT)
	bit	6,a
	jr	z,dki10
	dec	de
	ld	a,d
	or	e
	jr	nz,dki9
	jr	dkstop
dki10:	ld	a,(FSTAT)
	cpl
	bit	4,a			; record not found
	scf
	ret	nz
	or	a
	ret

dkstop:	ld	a,0D0h xor 0FFh		; force interrupt
	ld	(FCTRL),a
dknone:	scf
	ret

; Labels: row, column, text. Values go right after each.
dlabels:
	db	2,0,"Drive:",0
	db	2,27,"Connector:",0
	db	2,54,"Side:",0
	db	3,0,"Step rate:",0
	db	3,27,"Motor:",0
	db	3,54,"Head load:",0
	db	4,0,"Track register:",0
	db	4,27,"Last command:",0
	db	6,0,"Ready:",0
	db	6,27,"Track 0:",0
	db	6,54,"Write protect:",0
	db	7,0,"Head loaded:",0
	db	7,27,"Seek error:",0
	db	7,54,"Single sided:",0
	db	8,0,"Speed:",0
	db	8,27,"5.25",22h," motors turning:",0
	db	0

; The values. Each is drawn only when it changed, or every one when
; ddirty is set, so a key does not wait on a whole screen going out of
; the serial port.
dshow:	ld	a,(FSTAT)
	cpl
	ld	(dstat),a
	ld	a,(SYSFLG)
	ld	(dsysf),a
	ld	ix,dyes
dsh1:	ld	a,(ix+0)
	or	a
	jr	z,dsh2
	ld	l,(ix+2)
	ld	h,(ix+3)
	ld	a,(hl)
	xor	(ix+5)
	and	(ix+4)
	push	ix
	pop	hl
	ld	de,6
	add	hl,de
	call	dchg
	jr	z,dsh4
	ld	l,(ix+1)
	ld	h,(ix+0)
	ld	b,a
	ld	a,(ix+7)
	or	a
	ld	a,b
	jr	nz,dsh3
	call	pyesno
	jr	dsh4
dsh3:	call	ponoff
dsh4:	ld	de,8
	add	ix,de
	jr	dsh1
dsh2:	ld	a,(dsel)
	ld	hl,dshsel
	call	dchg
	jr	z,dsh7
	ld	hl,7*256+2
	call	at
	ld	a,(dsel)
	or	a
	jr	nz,dsh5
	call	print
	db	"NONE",0
	jr	dsh7
dsh5:	call	print
	db	"DS",0
	ld	a,(dsel)
	add	a,'0'
	call	putc
	ld	a,' '
	call	putc
dsh7:	ld	a,(deight)
	ld	hl,dsheight
	call	dchg
	jr	z,dsh9
	ld	hl,38*256+2
	call	at
	ld	a,(deight)
	or	a
	jr	z,dsh8
	call	print
	db	"8",22h,"   ",0
	jr	dsh9
dsh8:	call	print
	db	"5.25",22h,0
dsh9:	ld	a,(dside)
	ld	hl,dshside
	call	dchg
	jr	z,dsh10
	ld	hl,60*256+2
	call	at
	ld	a,(dside)
	add	a,'0'
	call	putc
dsh10:	ld	a,(drate)
	ld	hl,deight
	or	(hl)
	ld	hl,dshrate
	call	dchg
	jr	z,dsh12
	ld	hl,11*256+3
	call	at
	ld	a,(drate)
	ld	c,a
	ld	b,0
	ld	hl,rate8
	ld	a,(deight)
	or	a
	jr	nz,dsh11
	ld	hl,rate5
dsh11:	add	hl,bc
	ld	l,(hl)
	ld	h,b
	call	pdec16
	call	print
	db	" ms ",0
dsh12:	ld	a,(FTRACK)
	cpl
	ld	hl,dshtrk
	call	dchg
	jr	z,dsh13
	ld	hl,16*256+4
	call	at
	ld	a,(dshtrk)
	ld	l,a
	ld	h,0
	call	pdec16
	call	print
	db	"  ",0
dsh13:	ld	a,(dres)
	ld	hl,dshres
	call	dchg
	jr	z,dsh13b
	ld	hl,41*256+4
	call	at
	ld	a,(dres)
	add	a,a
	add	a,a
	ld	l,a
	add	a,a
	add	a,l			; 12 bytes each
	ld	l,a
	ld	h,0
	ld	de,drtext
	add	hl,de
	call	puts
dsh13b:	ld	hl,(drpm)
	ld	de,(drpmsh)
	ld	(drpmsh),hl
	ld	a,(ddirty)
	or	a
	jr	nz,dsh14
	sbc	hl,de
	jr	z,dsh16
dsh14:	ld	hl,7*256+8
	call	at
	ld	hl,(drpm)
	ld	a,h
	or	l
	jr	nz,dsh15
	call	print
	db	"NO INDEX",0
	jr	dsh16
dsh15:	call	pdec16
	call	print
	db	" RPM    ",0
dsh16:	xor	a
	ld	(ddirty),a
	ret

drtext:	db	"NONE       ",0
	db	"DONE       ",0
	db	"STOPPED    ",0
	db	"TIMED OUT  ",0

; NZ if A is not the byte at HL, or every value is to be drawn. The
; byte at HL becomes A. Keeps A.
dchg:	push	bc
	ld	b,a
	ld	a,(ddirty)
	or	a
	jr	nz,dch1
	ld	a,(hl)
	cp	b
dch1:	ld	(hl),b
	ld	a,b
	pop	bc
	ret

; YES and NO, ON and OFF values: column, row, the byte, its mask, XORed
; with, the value as drawn, 0 for YES or NO and 1 for ON or OFF
dyes:	db	7,6
	dw	dstat
	db	80h,80h,0,0		; ready
	db	36,6
	dw	dstat
	db	04h,0,0,0		; track 0
	db	69,6
	dw	dstat
	db	40h,0,0,0		; write protect
	db	13,7
	dw	dstat
	db	20h,0,0,0		; head loaded
	db	39,7
	dw	dstat
	db	10h,0,0,0		; seek error
	db	68,7
	dw	dsysf
	db	10h,0,0,0		; single sided
	db	49,8
	dw	dsysf
	db	20h,0,0,0		; 5.25-inch motors turning
	db	34,3
	dw	dmotor
	db	0FFh,0,0,1
	db	65,3
	dw	dhead
	db	0FFh,0,0,1
	db	0

; At HL, YES if A is not 0, else NO
pyesno:	push	af
	call	at
	pop	af
	or	a
	jr	z,pyn1
	call	print
	db	"YES",0
	ret
pyn1:	call	print
	db	"NO ",0
	ret

; At HL, ON if A is not 0, else OFF
ponoff:	push	af
	call	at
	pop	af
	or	a
	jr	z,pof1
	call	print
	db	"ON ",0
	ret
pof1:	call	print
	db	"OFF",0
	ret

; The speed from the index pulse into drpm, 0 if no pulse comes within
; a second. Gives up at once, drpm left alone, when a key is waiting.
; A loop counts its turns over DIDXN turns of the disk, and over whole
; ticks, 61.035 a second, which gives its speed. So RPM =
; 3662 x DIDXN x (turns a tick span) / (ticks x turns over DIDXN turns).
dspeed:	ld	hl,(ticks)
	ld	(dt0),hl
dsp1:	call	dsgate			; the pulse to end
	ret	c
	call	didx
	jr	nz,dsp1
dsp2:	call	dsgate			; and the next to start
	ret	c
	call	didx
	jr	z,dsp2
	ld	hl,0			; E:HL turns of the loop
	ld	e,l
	ld	d,l			; ticks
	ld	b,2			; the index bit as last seen
	ld	c,DIDXN
dsp3:	inc	hl
	ld	a,h
	or	l
	jr	nz,dsp4
	inc	e
dsp4:	ld	a,(SYSFLG)
	rla
	jr	nc,dsp5
	call	dstick
	ret	c
dsp5:	ld	a,(FSTAT)
	cpl
	and	2
	cp	b
	jr	z,dsp3
	ld	b,a
	or	a
	jr	z,dsp3			; a pulse ended
	dec	c
	jr	nz,dsp3
	ld	a,d
	cp	2
	ret	c
	dec	d			; tick spans
	ld	(dvs),hl		; the turns over DIDXN, x 4 later
	ld	l,e
	ld	h,0
	ld	(dvs+2),hl
	ld	hl,(dlast)		; dvd = turns a tick span x 16
	ld	bc,(dfirst)
	or	a
	sbc	hl,bc
	ld	(dvd),hl
	ld	a,(dfirst+2)
	ld	c,a
	ld	a,(dlast+2)
	sbc	a,c
	ld	l,a
	ld	h,0
	ld	(dvd+2),hl
	ld	hl,dvd
	ld	b,4
dsp6:	call	shl32
	djnz	dsp6
	ld	hl,dvs			; the loop's turns over DIDXN x 4
	call	shl32
	call	shl32
	ld	hl,(dvs)
	ld	(direv),hl
	ld	hl,(dvs+2)
	ld	(direv+2),hl
	ld	l,d			; / tick spans
	ld	h,0
	ld	(dvs),hl
	ld	l,h
	ld	(dvs+2),hl
	call	udiv32
	ld	hl,(dvd+2)
	ld	a,h
	or	l
	ret	nz			; too fast to count
	ld	bc,(dvd)
	ld	de,3662			; 60 x 61.035
	call	mul16
	ld	(dvd),hl
	ld	(dvd+2),de
	ld	hl,(direv)
	ld	(dvs),hl
	ld	hl,(direv+2)
	ld	(dvs+2),hl
	call	udiv32
	ld	hl,(dvd)
	ld	(drpm),hl
	ret

; A tick while counting: keep the clock and keyboard going, note the
; count. Carry to give up: a key waiting, or 2 s with no result (drpm
; 0 then).
dstick:	ld	a,(SYSCLR)		; clears the tick
	push	hl
	ld	hl,(ticks)
	inc	hl
	ld	(ticks),hl
	pop	hl
	call	kscan
	ld	a,d
	or	a
	jr	nz,dst1
	ld	(dfirst),hl
	ld	a,e
	ld	(dfirst+2),a
dst1:	ld	(dlast),hl
	ld	a,e
	ld	(dlast+2),a
	inc	d
	call	dskey
	ret	c
	ld	a,d
	cp	122
	ccf
	ret	nc
	jr	dsnone

; Carry to give up: a key waiting, or a second with no pulse (drpm 0)
dsgate:	call	poll
	call	dskey
	ret	c
	ld	hl,(ticks)
	ld	de,(dt0)
	or	a
	sbc	hl,de
	ld	de,61
	sbc	hl,de
	ccf
	ret	nc
dsnone:	ld	hl,0
	ld	(drpm),hl
	scf
	ret

; Carry if a key is waiting, on the keyboard or the terminal
dskey:	ld	a,(kkey)
	or	a
	scf
	ret	nz
	ld	a,(SIOCA)
	rra
	ret

; NZ while the index pulse is on
didx:	ld	a,(FSTAT)
	cpl
	and	2
	ret

; The 4 bytes at HL times 2. Keeps HL.
shl32:	push	hl
	sla	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)
	pop	hl
	ret

; DE:HL = BC x DE
mul16:	ld	hl,0
	ld	a,16
ml1:	add	hl,hl
	rl	e
	rl	d
	jr	nc,ml2
	add	hl,bc
	jr	nc,ml2
	inc	de
ml2:	dec	a
	jr	nz,ml1
	ret

; dvd / dvs, 32 bits: the quotient in dvd, the remainder in drem
udiv32:	ld	hl,0
	ld	(drem),hl
	ld	(drem+2),hl
	ld	b,32
ud1:	ld	hl,dvd
	call	shl32
	ld	hl,drem
	rl	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)
	ld	hl,(drem)
	ld	de,(dvs)
	or	a
	sbc	hl,de
	ex	de,hl
	ld	hl,(drem+2)
	push	bc
	ld	bc,(dvs+2)
	sbc	hl,bc
	pop	bc
	jr	c,ud2
	ld	(drem),de
	ld	(drem+2),hl
	ld	hl,dvd
	inc	(hl)
ud2:	djnz	ud1
	ret
