; CLOCK: read the MAX-80's clock chip and print the date and time,
; a worked example of the clock chip.
;
;	CLOCK		prints such as 10/30/26 21:44:50
;
; The MSM5832 sits behind the PIO: port B bits 3-0 pick a register, bit
; 5 is READ, and the digit comes back on port A bits 3-0. It runs under
; any CP/M with the I/O block at F000h, Lobo's CP/M 2.2 and xcpmz80.

BDOS	equ	5
BLK	equ	0F000h			; the I/O block under CP/M
PIODA	equ	BLK+7FCh		; port A: RAM chunks 7-4, clock data 3-0
PIODB	equ	BLK+7FEh		; port B: 6 HOLD, 5 READ, 4 WRITE, 3-0 register
RD	equ	20h

	org	100h
	call	rtread
	ld	hl,regs+5		; hours tens: bit 3 24-hour, bit 2 PM
	ld	a,(hl)
	and	03h
	ld	(hl),a
	ld	hl,regs+8		; date tens: bit 2 leap year
	ld	a,(hl)
	and	03h
	ld	(hl),a
	ld	hl,fmt			; 80h + a register, or a character
cl_1:	ld	a,(hl)
	inc	hl
	or	a
	ret	z
	jp	p,cl_2
	and	7Fh
	ld	de,regs
	add	a,e
	ld	e,a
	jr	nc,cl_3
	inc	d
cl_3:	ld	a,(de)
	add	a,'0'
cl_2:	push	hl
	ld	e,a
	ld	c,2			; console output
	call	BDOS
	pop	hl
	jr	cl_1

; Register A of the clock to A, bits 3-0. The chip wants READ held at
; least 6 us before the data is good.
rtget:	or	RD
	ld	(PIODB),a
	ld	a,4
rg_1:	dec	a
	jr	nz,rg_1
	ld	a,(PIODA)
	and	0Fh
	ret

; All 13 registers to regs. A digit can carry between two reads, so read
; them all again until two passes agree.
rtread:	ld	hl,regs
	ld	b,0
	ld	e,0			; differences from the last pass
rr_1:	ld	a,b
	call	rtget
	cp	(hl)
	jr	z,rr_2
	ld	(hl),a
	inc	e
rr_2:	inc	hl
	inc	b
	ld	a,b
	cp	13
	jr	nz,rr_1
	xor	a			; READ off
	ld	(PIODB),a
	ld	a,e
	or	a
	jr	nz,rtread
	ret

; The registers: 0 seconds, 1 tens, 2 minutes, 3 tens, 4 hours, 5 tens,
; 6 day of the week, 7 date, 8 tens, 9 month, 10 tens, 11 year, 12 tens
R	equ	80h
fmt:	db	R+10,R+9,'/',R+8,R+7,'/',R+12,R+11,' '
	db	R+5,R+4,':',R+3,R+2,':',R+1,R+0,0Dh,0Ah,0
regs:	db	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
