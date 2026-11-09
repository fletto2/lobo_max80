; DIP switch test: the eight switches read live from DIPSW, each marked
; once it has moved, and the boot device switches 6-8 select. ESC or
; BREAK goes back to the menu.

DPCOL	equ	14			; the column of switch 1, then every 6

dptest:	ld	a,1			; keys are caught while the screen is drawn
	ld	(kpoll),a
	xor	a
	ld	(kkey),a
	ld	(dpmoved),a
	ld	a,0Ch
	call	putc
	call	print
	db	"DIP SWITCH TEST",0
	ld	hl,2
	call	at
	call	print
	db	TH,"Switch:",TK,0
	ld	hl,DPCOL*256+2
	ld	c,'1'
dp1:	call	at
	ld	a,c
	call	putc
	ld	a,h
	add	a,6
	ld	h,a
	inc	c
	ld	a,c
	cp	'9'
	jr	nz,dp1
	ld	hl,3
	call	at
	call	print
	db	TH,"Position:",TK,0
	ld	hl,4
	call	at
	call	print
	db	TH,"Moved:",TK,0
	ld	hl,10
	call	at
	call	print
	db	TH,"A switch reads 1 when up. Switch 1 is bit 7 of DIPSW, switch 8 bit 0. The boot",0Dh,0Ah
	db	"ROM reads switches 6-8 at reset to pick the boot device. Switches 1-5 are left",0Dh,0Ah
	db	"to the operating systems. Move each switch to see it change.",TK,0Dh,0Ah,0Ah
	db	" ESC  ",TH,"Back to the menu",TK,0
	ld	a,(DIPSW)
	ld	(dpfirst),a
	cpl				; drawn on the first turn
	ld	(dpshown),a
dp2:	ld	a,(DIPSW)
	ld	hl,dpshown
	cp	(hl)
	call	nz,dpshow
	call	inkey
	jr	z,dp2
	cp	1Bh
	jr	z,dp3
	cp	03h			; BREAK
	jr	nz,dp2
dp3:	xor	a
	ld	(kpoll),a
	jp	drawmenu

; Draw the switches as A has them
dpshow:	ld	(dpshown),a
	ld	hl,dpfirst
	xor	(hl)
	ld	hl,dpmoved
	or	(hl)
	ld	(hl),a
	ld	d,a			; moved, switch 1 in bit 7
	ld	a,(dpshown)
	ld	e,a			; up
	ld	hl,DPCOL*256+3
dps1:	call	at
	push	hl
	ld	hl,dpdown
	rl	e
	jr	nc,dps2
	ld	hl,dpup
dps2:	call	puts
	pop	hl
	inc	l
	call	at
	push	hl
	ld	hl,dpno
	rl	d
	jr	nc,dps4
	ld	hl,dpyes
dps4:	call	puts
	pop	hl
	dec	l
	ld	a,h
	add	a,6
	ld	h,a
	cp	DPCOL+6*8
	jr	nz,dps1
	ld	hl,6
	call	vrow
	db	"DIPSW: ",0
	ld	a,(dpshown)
	call	phex8
	ld	hl,7
	call	vrow
	db	"Boot device, switches 6-8: ",0
	ld	a,(dpshown)
	and	7
	add	a,a
	ld	e,a
	ld	d,0
	ld	hl,dpboot
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	jp	puts

dpdown:	db	"DOWN",0
dpup:	db	"UP  ",0
dpno:	db	"NO ",0
dpyes:	db	"YES",0

; The boot ROM's table
dpboot:	dw	dpb0,dpb1,dpb2,dpb3,dpb4,dpb5,dpb6,dpb7
dpb0:	db	"NONE, the boot ROM beeps",0
dpb1:	db	"5.25",22h," floppy drive",0
dpb2:	db	"8",22h," floppy drive",0
dpb3:	db	"5.25",22h," UVC winchester",0
dpb4:	db	"8",22h," UVC winchester",0
dpb5:	db	"5.25",22h," UVC backup floppy",0
dpb6:	db	"8",22h," UVC backup floppy",0
dpb7:	db	"SASI hard disk",0
