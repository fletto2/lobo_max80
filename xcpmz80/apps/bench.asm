; BENCH: how fast a disk reads, timed by the clock chip.
;
;	BENCH
;
; Reads BENCH.DAT on the default drive in 128-byte records with BDOS
; function 20, over and over, for 30 seconds of clock time. It starts on
; a change of the clock's second and stops at the end of the first pass
; after the time is up. Prints one line: the disk's tag, which is the
; first 16 bytes of BENCH.DAT, then passes, records, seconds. Runs under
; any CP/M with the I/O block at F000h, Lobo's CP/M 2.2 and xcpmz80.
; Any key during the wait for the clock stops it.

BDOS	equ	5
FCB	equ	5Ch
TAIL	equ	80h
BLK	equ	0F000h			; the I/O block under CP/M
PIODA	equ	BLK+7FCh		; port A: RAM chunks 7-4, clock data 3-0
PIODB	equ	BLK+7FEh		; port B: 6 HOLD, 5 READ, 4 WRITE, 3-0 register
RD	equ	20h

	org	100h
	ld	sp,stack
	ld	hl,name
	ld	de,FCB+1
	ld	bc,11
	ldir
	call	openf
	jp	z,nofile
	ld	de,FCB			; record 0 starts with the disk's tag
	ld	c,20
	call	BDOS
	or	a			; none: an empty file, no tag, no pass
	jp	nz,empty
	ld	hl,TAIL
	ld	de,tag
	ld	b,16
tg_1:	ld	a,(hl)			; a $ would end its printing
	cp	'$'
	jr	nz,tg_2
	ld	a,' '
tg_2:	ld	(de),a
	inc	hl
	inc	de
	djnz	tg_1
	ld	de,msgwait
	call	puts
	call	now			; wait for the second to change
	ld	(t0),hl
bn_w:	ld	c,11			; a key stops the wait
	call	BDOS
	or	a
	jp	nz,noclock
	call	now
	ld	de,(t0)
	or	a
	sbc	hl,de
	jr	z,bn_w
	call	now
	ld	(t0),hl
bn_p:	call	openf			; a pass
	jp	z,nofile
bn_r:	ld	de,FCB
	ld	c,20
	call	BDOS
	or	a
	jr	nz,bn_e
	ld	hl,(recs)
	inc	hl
	ld	(recs),hl
	jr	bn_r
bn_e:	ld	hl,(passes)
	inc	hl
	ld	(passes),hl
	call	elapsed			; HL seconds since the start
	ld	(secs),hl
	ld	de,(want)
	or	a
	sbc	hl,de
	jr	c,bn_p
	call	report
	jp	0

; The file's FCB at its first record, opened. Z if no such file.
openf:	xor	a
	ld	(FCB+12),a		; extent, S1, S2 and the record
	ld	(FCB+13),a
	ld	(FCB+14),a
	ld	(FCB+32),a
	ld	de,FCB
	ld	c,15
	call	BDOS
	inc	a			; FFh is no file
	ret

; HL = seconds from t0 to now, with the clock's hour turning over
elapsed:
	call	now
	ld	de,(t0)
	or	a
	sbc	hl,de
	ret	nc
	ld	de,3600
	add	hl,de
	ret

; HL = minutes * 60 + seconds, from the clock chip
now:	call	rtread
	ld	a,(regs+3)		; minutes
	ld	b,a
	add	a,a
	add	a,a
	add	a,b
	add	a,a			; tens * 10
	ld	b,a
	ld	a,(regs+2)
	add	a,b
	ld	b,a			; minutes
	ld	hl,0
	ld	de,60
	inc	b
nw_1:	dec	b
	jr	z,nw_2
	add	hl,de
	jr	nw_1
nw_2:	ld	a,(regs+1)		; seconds tens * 10
	ld	b,a
	add	a,a
	add	a,a
	add	a,b
	add	a,a
	ld	b,a
	ld	a,(regs)
	add	a,b
	ld	e,a
	ld	d,0
	add	hl,de
	ret

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

; Registers 0 to 3, seconds and minutes, to regs. A digit can carry
; between two reads, so read them again until two passes agree.
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
	cp	4
	jr	nz,rr_1
	xor	a			; READ off
	ld	(PIODB),a
	ld	a,e
	or	a
	jr	nz,rtread
	ret

; The result: passes, records, seconds, one line
report:	ld	de,tag
	call	puts
	ld	hl,(passes)
	call	pdec
	ld	e,' '
	call	putc
	ld	hl,(recs)
	call	pdec
	ld	e,' '
	call	putc
	ld	hl,(secs)
	call	pdec
	ld	de,msgend
	jp	puts

; HL in decimal
pdec:	ld	de,10000
	ld	c,0			; 1 once a digit has printed
	call	pd_1
	ld	de,1000
	call	pd_1
	ld	de,100
	call	pd_1
	ld	de,10
	call	pd_1
	ld	a,l
	add	a,'0'
	ld	e,a
	jp	putc
pd_1:	ld	b,'0'-1
pd_2:	inc	b
	or	a
	sbc	hl,de
	jr	nc,pd_2
	add	hl,de
	ld	a,b
	cp	'0'
	jr	nz,pd_3
	ld	a,c
	or	a
	ret	z			; leading zero
pd_3:	ld	c,1
	push	hl
	ld	e,b
	call	putc
	pop	hl
	ret

putc:	push	hl
	push	bc
	ld	c,2
	call	BDOS
	pop	bc
	pop	hl
	ret

puts:	ld	c,9
	jp	BDOS

nofile:	ld	de,msgnof
	call	puts
	jp	0
empty:	ld	de,msgemp
	call	puts
	jp	0
noclock: ld	c,1			; the key read, not left for the
	call	BDOS			; prompt after
	ld	de,msgclk
	call	puts
	jp	0

msgnof:	db	'No file',13,10,'$'
msgemp:	db	'BENCH.DAT is empty',13,10,'$'
msgclk:	db	13,10,'The clock chip does not change',13,10,'$'
msgwait: db	'Waiting for the clock',13,10,'$'
msgend:	db	13,10,'$'

tag:	ds	16
	db	' $'
want:	dw	30
name:	db	'BENCH   DAT'
t0:	dw	0
secs:	dw	0
passes:	dw	0
recs:	dw	0
regs:	db	0FFh,0FFh,0FFh,0FFh
	ds	64
stack:
