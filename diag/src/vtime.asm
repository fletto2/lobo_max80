; Video timing test: SYSFLG bit 6, the CRTC's display enable, read and
; timed. It is on only while the beam is in the picture, so it goes off
; in every horizontal blank, and an off run longer than a line is the
; vertical blank. Any key measures again, ESC or BREAK goes back.

VFN	equ	4			; frames timed
VLN	equ	200			; lines timed, all in the picture
VTN	equ	4			; ticks timed
VLONG	equ	16			; an off run this long is the vertical blank

vttest:	ld	a,0Ch
	call	putc
	call	print
	db	"VIDEO TIMING TEST",0
	ld	hl,13
	call	at
	call	print
	db	TH,"The CRTC table gives 216 lines of picture, 264 a frame and 120 characters a",0Dh,0Ah
	db	"line, so 59.97 Hz, 15.83 kHz and 63.2 us from the 15.2 MHz dot clock. The rates",0Dh,0Ah
	db	"are timed against the 61.035 Hz tick, from the 8 MHz crystal.",TK,0Dh,0Ah,0Ah
	db	" Any key  ",TH,"Measure again",TK,"          ESC  ",TH,"Back to the menu",TK,0
vt1:	call	vmeas
	call	vshow
vt2:	call	waitkey
	cp	1Bh
	jp	z,drawmenu
	cp	03h			; BREAK
	jp	z,drawmenu
	jr	vt1

; Measure: vres 0 if every value was found, else 1 stuck off, 2 stuck
; on, 3 no vertical blank, 4 too few lines of picture to time
vmeas:	ld	a,1
	ld	(vres),a
	ld	c,0			; off until it comes on
	call	vwait
	ret	c
	ld	a,2
	ld	(vres),a
	ld	c,40h			; on until it goes off
	call	vwait
	ret	c
	ld	a,3
	ld	(vres),a
	call	vsync
	ret	c
	ld	hl,1			; line 0 is on now
vm1:	push	hl
	ld	c,40h
	call	vwait			; the end of the line
	call	nc,voff			; and the off run after it
	pop	hl
	ret	c
	cp	VLONG
	jr	nc,vm2
	inc	hl
	jr	vm1
vm2:	ld	(vpic),hl
	ld	a,4
	ld	(vres),a
	ld	de,VLN+1
	or	a
	sbc	hl,de
	ret	c
	call	vsync			; lines: from the end of line 0
	ret	c
	ld	c,40h
	ld	de,1
	call	vedge
	ret	c
	ld	de,VLN*2
	call	vedge
	ret	c
	ld	(vil),hl
	call	vsync			; frames: from the end of line 0
	ret	c
	ld	c,40h
	ld	de,1
	call	vedge
	ret	c
	ld	hl,(vpic)
	add	hl,hl
	add	hl,hl
	add	hl,hl			; 2 edges a line, VFN frames
	ex	de,hl
	call	vedge
	ret	c
	ld	(vif),hl
	ld	a,(SYSCLR)		; ticks: from the first that comes
	ld	de,1
	call	vtick
	ld	de,VTN
	call	vtick
	ld	(vit),hl
	ld	hl,(ticks)
	ld	de,VTN+1
	add	hl,de
	ld	(ticks),hl
	xor	a
	ld	(vres),a
	ret

; Wait while bit 6 is C, 00h or 40h, up to about 0.7 s. Carry if it
; never changed.
vwait:	ld	hl,0
vw1:	ld	a,(SYSFLG)
	and	40h
	cp	c
	jr	nz,vw2
	dec	hl
	ld	a,h
	or	l
	jr	nz,vw1
	scf
	ret
vw2:	or	a
	ret

; Bit 6 has just gone off: wait for it to come on. A = the turns it
; was off, 255 at most. Carry if it never came on.
voff:	ld	e,0
vo1:	ld	a,(SYSFLG)
	and	40h
	jr	nz,vo2
	inc	e
	jr	nz,vo1
	dec	e
	ld	c,0
	call	vwait
	ret	c
vo2:	ld	a,e
	or	a
	ret

; Find the vertical blank and return as line 0 starts. Carry if there
; is none in about three frames.
vsync:	ld	d,3
	ld	b,0
vs1:	push	bc
	push	de
	ld	c,40h
	call	vwait
	call	nc,voff
	pop	de
	pop	bc
	ret	c
	cp	VLONG
	ret	nc			; long: line 0 has started
	djnz	vs1
	dec	d
	jr	nz,vs1
	scf
	ret

; HL = turns of the loop over DE changes of bit 6, C its value now.
; Both paths take 70 T-states, so HL measures time. Each timing calls
; this twice, once to find a change and once to count from it, and HL
; starts at 1 for the 52 T-states between the two. Carry if HL runs
; out, about 0.9 s.
vedge:	ld	hl,1
ve1:	inc	hl
	ld	a,(SYSFLG)
	and	40h
	cp	c
	jr	nz,ve2
	ld	a,h
	or	l
	jr	z,vto
	nop
	nop
	jp	ve1
ve2:	ld	c,a
	dec	de
	ld	a,d
	or	e
	jp	nz,ve1
	ret
vto:	scf
	ret

; HL = turns of the same loop over DE ticks, called the same way. The
; turn with a tick takes 79 T-states, the SYSCLR read, the rest 70. Nine
; T-states a tick in about 83000 is under 0.02%.
vtick:	ld	hl,1
	ld	c,0
vk1:	inc	hl
	ld	a,(SYSFLG)
	and	80h
	cp	c
	jr	nz,vk2
	ld	a,h
	or	l
	jr	z,vto
	nop
	nop
	jp	vk1
vk2:	ld	a,(SYSCLR)		; clears the tick
	dec	de
	ld	a,d
	or	e
	jp	nz,vk1
	ret

; The results, rows 2-10
vshow:	ld	hl,2
	call	vrow
	db	"Display enable, SYSFLG bit 6: ",0
	ld	a,(vres)
	ld	hl,vtsoff
	dec	a
	jr	z,vsh1
	ld	hl,vtson
	dec	a
	jr	z,vsh1
	ld	hl,vtstog
vsh1:	call	puts
	ld	hl,3
	call	vrow
	db	"Vertical blank found: ",0
	ld	a,(vres)
	or	a
	jr	z,vsh2
	cp	4
	jr	z,vsh2
	call	print			; stuck, or no long off run
	db	"NO",0
	ld	l,5
vsh3:	ld	h,0			; rows L-10 cleared
	call	at
	call	clreol
	inc	l
	ld	a,l
	cp	11
	jr	nz,vsh3
	ret
vsh2:	call	print
	db	"YES",0
	ld	hl,5
	call	vrow
	db	"Lines of picture: ",0
	ld	hl,(vpic)
	call	pdec16
	ld	a,(vres)
	or	a
	jr	z,vsh5
	call	print
	db	TH,", too few to time",TK,0
	ld	l,6
	jr	vsh3
vsh5:	ld	bc,(vif)		; lines a frame x 10 = vif x 500 / vil
	ld	de,500
	call	setdvd
	ld	bc,(vil)
	ld	de,1
	call	vdiv
	ld	(vlf),hl
	ld	bc,(vil)		; line period, 0.1 us = vil x 32768 / (vit x 10)
	ld	de,32768
	call	setdvd
	ld	bc,(vit)
	ld	de,10
	call	vdiv
	ld	(vt01),hl
	ld	hl,6
	call	vrow
	db	"Lines a frame: ",0
	ld	hl,(vlf)
	ld	a,10
	call	pfix
	ld	hl,7
	call	vrow
	db	"Vertical blank: ",0
	ld	hl,(vpic)		; lines x 10
	add	hl,hl
	ld	d,h
	ld	e,l
	add	hl,hl
	add	hl,hl
	add	hl,de
	ex	de,hl
	ld	hl,(vlf)
	or	a
	sbc	hl,de
	jr	nc,vsh6
	ld	hl,0
vsh6:	push	hl
	ld	a,10
	call	pfix
	call	print
	db	TH," lines, ",TK,0
	pop	bc			; ms x 10 = lines x 10 x vt01 / 10000
	ld	de,(vt01)
	call	setdvd
	ld	bc,10000
	ld	de,1
	call	vdiv
	ld	a,10
	call	pfix
	call	print
	db	TH," ms",TK,0
	ld	hl,8
	call	vrow
	db	"Frame rate: ",0
	ld	bc,(vit)		; Hz x 100 = vit x 61035 / (vif x 10)
	ld	de,61035
	call	setdvd
	ld	bc,(vif)
	ld	de,10
	call	vdiv
	ld	a,100
	call	pfix
	call	print
	db	TH," Hz",TK,0
	ld	hl,9
	call	vrow
	db	"Line rate: ",0
	ld	bc,(vit)		; kHz x 100 = vit x 30518 / (vil x 100)
	ld	de,30518
	call	setdvd
	ld	bc,(vil)
	ld	de,100
	call	vdiv
	ld	a,100
	call	pfix
	call	print
	db	TH," kHz",TK,0
	ld	hl,10
	call	vrow
	db	"Line period: ",0
	ld	hl,(vt01)
	ld	a,10
	call	pfix
	call	print
	db	TH," us",TK,0
	ret

vtsoff:	db	"STUCK OFF",0
vtson:	db	"STUCK ON",0
vtstog:	db	"TOGGLING",0

; The row in L cleared, and the label after the call, thin
vrow:	call	at
	call	clreol
	ld	a,TH
	call	putc
	pop	hl
	call	puts
	push	hl
	ld	a,TK
	jp	putc

; dvd = BC x DE
setdvd:	call	mul16
	ld	(dvd),hl
	ld	(dvd+2),de
	ret

; HL = dvd / (BC x DE), rounded
vdiv:	call	mul16
	ld	(dvs),hl
	ld	(dvs+2),de
	srl	d			; dvd + dvs / 2
	rr	e
	rr	h
	rr	l
	ld	bc,(dvd)
	add	hl,bc
	ld	(dvd),hl
	ex	de,hl
	ld	bc,(dvd+2)
	adc	hl,bc
	ld	(dvd+2),hl
	call	udiv32
	ld	hl,(dvd)
	ret

; HL / A, 10 or 100, with one or two decimals
pfix:	push	af
	ld	(dvd),hl
	ld	hl,0
	ld	(dvd+2),hl
	ld	(dvs+2),hl
	ld	l,a
	ld	(dvs),hl
	call	udiv32
	ld	hl,(dvd)
	call	pdec16
	ld	a,'.'
	call	putc
	pop	af
	ld	hl,(drem)
	cp	10
	jr	z,pf1
	ld	a,l			; a leading 0 for two places
	cp	10
	jr	nc,pf1
	ld	a,'0'
	call	putc
pf1:	jp	pdec16
