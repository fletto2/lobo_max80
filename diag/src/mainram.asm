; Main RAM and banking. The 128K is four 32K chunks, A1, A2, B1, B2, and
; each is tested in the high half, 8000h-FFFFh, by March U, with the I/O
; block moved to 0000h out of the way. Every error is counted and its
; bits kept, so a test does not stop at the first bad bit. The program
; runs from A1, so A1 is tested from a copy in a chunk that passed.
; The console follows the block by blkhi, and one status line shows
; each step as it runs.

RESZ	equ	8		; errors (2), bad bits, first address (2), wrote, read, tested
TAG2	equ	8000h+SIG+1	; the second tag of the high half check

tags:	db	0A1h,0A2h,0B1h,0B2h

; Main RAM and banking. A = 0 and Z if all of it passed.
tmain:	call	print
	db	TH,"Main RAM test: ",TK,0
	ld	hl,(crow)
	ld	(pstat),hl
	ld	hl,res
	ld	de,res+1
	ld	bc,mmfails-res-1
	ld	(hl),0
	ldir
	xor	a
	ld	(bunsafe),a
	call	blk0
	call	mmsg
	db	"looking for bank B",0
	call	findb
	call	mmsg
	db	"banking, high half",0
	call	bkhigh
	ld	c,1
tm1:	call	unsafe
	jr	nz,tm2
	call	piohi
	call	cres
	call	ctag
	ld	(mtag),a
	push	bc
	call	march
	pop	bc
tm2:	inc	c
	ld	a,(nchunk)
	cp	c
	jr	nz,tm1
	call	mmsg
	db	"banking, low half",0
	call	bklow
	call	tma1
	call	mmsg
	db	"retention, about 6 s",0
	call	tret
	call	mmsg
	db	"DONE",0
	call	blkf
	ld	hl,(pstat)
	ld	h,0
	inc	l
	call	at
	call	mmrep
	jp	mmres

; The status line: the string after the call. Keeps every register.
mmsg:	ex	(sp),hl
	push	af
	push	hl
	ld	hl,(pstat)
	call	at
	pop	hl
	call	puts
	call	clreol
	pop	af
	ex	(sp),hl
	ret

; The status line: chunk mtag, step A of the march, the errors so far
; from the result at IX. Keeps every register.
mstep:	push	af
	push	bc
	push	de
	push	hl
	ld	e,a
	ld	hl,(pstat)
	call	at
	ld	a,(mtag)
	call	phex4x
	call	print
	db	TH,", March U step ",TK,0
	ld	a,e
	add	a,'0'
	call	putc
	call	print
	db	TH," of 5, ",0
	ld	hl,mtext
	ld	b,e
	dec	b
	jr	z,ms2
ms1:	ld	a,(hl)
	inc	hl
	or	a
	jr	nz,ms1
	djnz	ms1
ms2:	call	puts
	call	print
	db	", errors ",TK,0
	ld	l,(ix+0)
	ld	h,(ix+1)
	call	pdec16
	call	clreol
	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

mtext:	db	"up w0",0
	db	"up r0 w1 r1 w0",0
	db	"up r0 w1",0
	db	"down r1 w0 r0 w1",0
	db	"down r1 w0",0

; The I/O block to 0000h, with the window kept
blk0:	ld	a,(vlnow)
	and	0Fh
	ld	(VLATCH),a
	ld	(B_VLATCH),a		; and its RAM copy at 0000h
	xor	a
	ld	(blkhi),a
	ret

; The PIO back to A1 low, A2 high, and the block back to F000h
blkf:	ld	a,40h
	ld	(B_PIODA),a
	ld	a,(vlnow)
	ld	(B_VLATCH),a
	ld	(VLATCH),a
	ld	a,high BLK
	ld	(blkhi),a
	ret

; Chunk C in the high half, A1 in the low
piohi:	ld	a,c
	rrca
	rrca
	ld	(B_PIODA),a
	ret

; A = the tag of chunk C, its name in hex
ctag:	push	hl
	push	bc
	ld	hl,tags
	ld	b,0
	add	hl,bc
	ld	a,(hl)
	pop	bc
	pop	hl
	ret

; IX = the result of chunk C
cres:	push	bc
	ld	a,c
	add	a,a
	add	a,a
	add	a,a
	ld	c,a
	ld	b,0
	ld	ix,res
	add	ix,bc
	pop	bc
	ret

; Each chunk in the high half gets its tag at 8000h and TAG2, then each
; is read back. A chunk decoded as another shows the other's tag.
bkhigh:	ld	a,(nchunk)
	ld	b,a
	ld	c,0
bh1:	call	piohi
	call	ctag
	ld	(8000h),a
	ld	(TAG2),a
	inc	c
	djnz	bh1
	ld	a,(nchunk)
	ld	b,a
	ld	c,0
	ld	hl,bhigh
bh2:	call	piohi
	call	ctag
	ld	d,a
	ld	a,(8000h)
	cp	d
	jr	nz,bh3
	ld	a,(TAG2)
bh3:	ld	(hl),a
	cp	d
	call	nz,bhbad
	inc	hl
	inc	c
	djnz	bh2
	ret

; Chunk C read A, not its tag: C and the chunk whose tag it shows share
; storage, and a march on either could land on the program
bhbad:	push	bc
	push	hl
	ld	e,a
	call	cbit
	ld	hl,bunsafe
	or	(hl)
	ld	(hl),a
	ld	b,4
	ld	c,0
bb1:	call	ctag
	cp	e
	jr	nz,bb2
	call	cbit
	or	(hl)
	ld	(hl),a
bb2:	inc	c
	djnz	bb1
	pop	hl
	pop	bc
	ret

; A = the bit of chunk C
cbit:	push	bc
	ld	b,c
	inc	b
	xor	a
	scf
cb1:	rla
	djnz	cb1
	pop	bc
	ret

; NZ if chunk C failed the high half check
unsafe:	call	cbit
	push	hl
	ld	hl,bunsafe
	and	(hl)
	pop	hl
	ret

; March U over 8000h-FFFFh, the chunk already mapped there, into the
; result at IX. 13 operations a byte:
; up w0, up r0 w1 r1 w0, up r0 w1, down r1 w0 r0 w1, down r1 w0
march:	ld	a,1
	call	mstep
	ld	hl,8000h
	ld	de,8001h
	ld	bc,7FFFh
	ld	(hl),0
	ldir
	ld	de,00FFh		; D the 0 of the march, E the 1
	ld	a,2
	call	mstep
	ld	hl,8000h
mu1:	ld	a,(hl)
	cp	d
	call	nz,errd
	ld	(hl),e
	ld	a,(hl)
	cp	e
	call	nz,erre
	ld	(hl),d
	inc	hl
	bit	7,h
	jp	nz,mu1
	ld	a,3
	call	mstep
	ld	h,80h
mu2:	ld	a,(hl)
	cp	d
	call	nz,errd
	ld	(hl),e
	inc	hl
	bit	7,h
	jp	nz,mu2
	ld	a,4
	call	mstep
	ld	hl,0FFFFh
mu3:	ld	a,(hl)
	cp	e
	call	nz,erre
	ld	(hl),d
	ld	a,(hl)
	cp	d
	call	nz,errd
	ld	(hl),e
	dec	hl
	bit	7,h
	jp	nz,mu3
	ld	a,5
	call	mstep
	ld	hl,0FFFFh
mu4:	ld	a,(hl)
	cp	e
	call	nz,erre
	ld	(hl),d
	dec	hl
	bit	7,h
	jp	nz,mu4
	ld	(ix+7),1		; tested
	ret

; A wrong byte at HL: A came back, D (errd) or E (erre) was written
errd:	push	bc
	ld	c,d
	jr	err1
erre:	push	bc
	ld	c,e
err1:	ld	b,a
	xor	c
	or	(ix+2)
	ld	(ix+2),a
	ld	a,(ix+0)
	or	(ix+1)
	jr	nz,err2
	ld	(ix+3),l
	ld	(ix+4),h
	ld	(ix+5),c
	ld	(ix+6),b
err2:	inc	(ix+0)
	jr	nz,err3
	inc	(ix+1)
	jr	nz,err3
	dec	(ix+0)			; stays at FFFFh
	dec	(ix+1)
err3:	pop	bc
	ret

; Carry clear if chunk C passed March U and the high half check.
; Keeps IX at its result.
cok:	push	bc
	push	hl
	call	cres
	ld	a,(ix+7)
	dec	a
	jr	nz,ck1
	ld	a,(ix+0)
	or	(ix+1)
	jr	nz,ck1
	call	unsafe
	jr	nz,ck1
	pop	hl
	pop	bc
	or	a
	ret
ck1:	pop	hl
	pop	bc
	scf
	ret

; C = a chunk other than A1 that passed. Carry if there is none.
ggood:	ld	c,1
gg1:	ld	a,(nchunk)
	cp	c
	scf
	ret	z
	call	cok
	ret	nc
	inc	c
	jr	gg1

; The program, 1000h-7FFFh, into the chunk in the high half
pcopy:	ld	hl,1000h
	ld	de,9000h
	ld	bc,7000h
	ldir
	ret

; Each good chunk gets a copy of the program with its tag at SIG, then
; each in turn is put in the low half, the code going on from its copy,
; and SIG read. The copies match but for SIG, so nothing may be written
; between a switch and the switch back: the reads go to the alternate
; registers.
bklow:	ld	a,0A1h
	ld	(SIG),a
	ld	e,1			; the chunks to check, A1 always
	ld	c,1
bl1:	ld	a,(nchunk)
	cp	c
	jr	z,bl3
	call	cok
	jr	c,bl2
	call	piohi
	push	bc
	push	de
	call	pcopy
	pop	de
	pop	bc
	call	ctag
	ld	(SIG+8000h),a
	call	cbit
	or	e
	ld	e,a
bl2:	inc	c
	jr	bl1
bl3:	ld	a,e
	ld	(blchk),a
	ld	c,0
bl4:	ld	a,c			; chunk C low, A1 high
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	jr	nz,bl5
	ld	a,40h			; A1 low, A2 high
bl5:	ld	b,a
	ld	hl,tags
	ld	a,l
	add	a,c
	ld	l,a
	jr	nc,bl6
	inc	h
bl6:	ld	d,(hl)			; the tag of chunk C
	ld	a,e
	ld	h,c
	inc	h
bl7:	rrca
	dec	h
	jr	nz,bl7
	ld	a,d			; not checked: its own tag, blchk tells
	jr	nc,bl8
	ld	a,b
	ld	(B_PIODA),a
	ld	a,(SIG)
	ld	h,a
	ld	a,40h
	ld	(B_PIODA),a
	ld	a,h
bl8:	exx
	ld	b,c
	ld	c,d
	ld	d,e
	ld	e,a
	exx
	inc	c
	ld	a,c
	cp	4
	jr	nz,bl4
	exx
	ld	a,b
	ld	(blow),a
	ld	a,c
	ld	(blow+1),a
	ld	a,d
	ld	(blow+2),a
	ld	a,e
	ld	(blow+3),a
	exx
	ret

; A1 from a copy of the program in a good chunk. The copy is made, the
; low half switched to it, and A1 tested in the high half. Then the
; program goes back into A1 and the low half to A1. No stack writes
; between a copy and its switch. A write to the I/O block also lands
; in A1, whatever the PIO maps, so the screen copy to SIO A is
; off while A1 is under test.
tma1:	ld	c,0
	call	unsafe
	ret	nz
	call	ggood
	ret	c			; none: A1 is not tested
	call	piohi
	ld	a,c
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	ld	b,a			; chunk C low, A1 high
	push	bc
	call	pcopy
	pop	bc
	ld	a,b
	ld	(B_PIODA),a
	ld	c,0
	call	cres
	ld	a,0A1h
	ld	(mtag),a
	ld	a,(sioon)
	push	af
	xor	a
	ld	(sioon),a
	call	march
	pop	af
	ld	(sioon),a
	call	pcopy
	ld	a,40h
	ld	(B_PIODA),a
	ret

; A = 0 and Z if every chunk passed both checks and March U
mmres:	ld	c,0
mo1:	ld	a,(nchunk)
	cp	c
	jr	z,mo2a
	call	cok
	jr	c,mo3
	ld	hl,blow
	ld	b,0
	add	hl,bc
	call	ctag
	cp	(hl)
	jr	nz,mo3
	inc	c
	jr	mo1
mo2a:	ld	hl,rterr		; and no retention errors
	ld	a,(hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	jr	nz,mo3
mo2:	xor	a
	ret
mo3:	ld	a,1
	or	a
	ret

mmrep:	ld	a,(nchunk)
	cp	4
	jr	z,mp1
	call	print
	db	TH,"Bank B not found, testing 64K.",TK,0Dh,0Ah,0
mp1:	call	print
	db	TH,"Banking: ",TK,0
	call	bfails
	jr	z,mp1a
	call	print
	db	"FAIL",0Dh,0Ah,0
	jr	mp1c
mp1a:	call	print
	db	"PASS",0
	ld	b,3			; the chunks there, as bits
	ld	a,(nchunk)
	cp	2
	jr	z,mp1d
	ld	b,0Fh
mp1d:	ld	a,(blchk)
	cp	b
	jr	z,mp1b
	call	print
	db	TH,", not every chunk checked",TK,0
mp1b:	call	print
	db	0Dh,0Ah,0
mp1c:	ld	c,0
mp2:	ld	a,(nchunk)
	cp	c
	jr	z,mp4
	ld	b,0
	ld	hl,bhigh
	call	bchk
	inc	b
	ld	hl,blow
	call	bchk
	inc	c
	jr	mp2
mp4:	call	print
	db	TH,"Main RAM, March U:",TK,0
	ld	c,0
mp5:	ld	a,(nchunk)
	cp	c
	jr	z,mp8
	ld	a,' '
	call	putc
	call	ctag
	call	phex4x
	call	cres
	ld	a,(ix+7)
	or	a
	jr	nz,mp6
	call	print
	db	" NOT TESTED",0
	jr	mp7
mp6:	ld	a,(ix+0)
	or	(ix+1)
	jr	nz,mp6a
	call	print
	db	" PASS",0
	jr	mp7
mp6a:	call	print
	db	" FAIL",0
mp7:	inc	c
	jr	mp5
mp8:	call	print
	db	0Dh,0Ah,0
	ld	c,0
mp9:	ld	a,(nchunk)
	cp	c
	jr	z,mp10
	call	cres
	ld	a,(ix+0)
	or	(ix+1)
	call	nz,cfail
	inc	c
	jr	mp9
mp10:	call	print
	db	TH,"Retention, 1 s twice:",TK,0
	ld	c,0
mp11:	ld	a,(nchunk)
	cp	c
	jr	z,mp14
	ld	a,' '
	call	putc
	call	ctag
	call	phex4x
	call	rtix
	ld	a,c
	or	a
	jr	z,mp12			; A1 holds the program
	call	unsafe
	jr	nz,mp12
	ld	a,(ix+0)
	or	a
	jr	nz,mp13
	call	print
	db	" PASS",0
	jr	mp12a
mp12:	call	print
	db	" NOT TESTED",0
	jr	mp12a
mp13:	call	print
	db	" FAIL",0
mp12a:	inc	c
	jr	mp11
mp14:	call	print
	db	0Dh,0Ah,0
	ld	c,0
mp15:	ld	a,(nchunk)
	cp	c
	ret	z
	call	rtix
	ld	a,(ix+0)
	or	a
	call	nz,rtfail
	inc	c
	jr	mp15

; The retention errors of chunk C, IX from rtix
rtfail:	call	ctag
	call	phex4x
	call	print
	db	TH,": ",TK,0
	ld	l,(ix+0)
	ld	h,0
	call	pdec16
	ld	a,(ix+0)
	inc	a
	jr	nz,rf1
	ld	a,'+'
	call	putc
rf1:	call	print
	db	TH," retention errors, bad bits D7-D0: ",TK,0
	ld	a,(ix+4)
	call	pbin8
	call	print
	db	TH,".",TK,0Dh,0Ah,0
	ret

; IX = rterr + C, its bad bits at IX+4
rtix:	push	bc
	ld	b,0
	ld	ix,rterr
	add	ix,bc
	pop	bc
	ret

; Retention: each chunk but A1 that is safe to write gets a pattern from
; its addresses over its high half. The CPU then leaves 8000h-FFFFh
; alone for about 1 s, with only the refresh to keep it, and each chunk
; is read back. Then again with the pattern inverted. A1 holds the
; program and is not tested.
RETW	equ	3			; turns of the 1.7M T-state wait, about 1 s
tret:	ld	hl,rterr
	ld	b,8
tr0:	ld	(hl),0
	inc	hl
	djnz	tr0
	ld	e,0			; the pattern: address low XOR high XOR E
tr1:	ld	c,1
tr2:	ld	a,(nchunk)
	cp	c
	jr	z,tr4
	call	unsafe
	jr	nz,tr3
	call	piohi
	call	rfill
tr3:	inc	c
	jr	tr2
tr4:	ld	a,40h
	ld	(B_PIODA),a
	call	rwait
	ld	c,1
tr5:	ld	a,(nchunk)
	cp	c
	jr	z,tr7
	call	unsafe
	jr	nz,tr6
	call	piohi
	call	rtix
	call	rcheck
tr6:	inc	c
	jr	tr5
tr7:	ld	a,40h
	ld	(B_PIODA),a
	ld	a,e
	cpl
	ld	e,a
	or	a
	jr	nz,tr1			; once more, inverted
	ret

; The pattern over 8000h-FFFFh
rfill:	ld	hl,8000h
rfl1:	ld	a,l
	xor	h
	xor	e
	ld	(hl),a
	inc	hl
	bit	7,h
	jr	nz,rfl1
	ret

; 8000h-FFFFh against the pattern, errors and bad bits at IX
rcheck:	ld	hl,8000h
rck1:	ld	a,l
	xor	h
	xor	e
	xor	(hl)
	jr	z,rck2
	or	(ix+4)
	ld	(ix+4),a
	inc	(ix+0)
	jr	nz,rck2
	dec	(ix+0)			; stays at 255
rck2:	inc	hl
	bit	7,h
	jr	nz,rck1
	ret

; About 1 s with no main RAM access above 8000h. The tick cannot be
; read with the block at 0000h, so a counted loop.
rwait:	ld	b,RETW
rw1:	ld	hl,0
rw2:	dec	hl
	ld	a,h
	or	l
	jr	nz,rw2
	djnz	rw1
	ret

; The two letters of a tag, with no h
phex4x:	push	af
	rrca
	rrca
	rrca
	rrca
	call	phex4
	pop	af
	jp	phex4

; NZ if any chunk read another's tag in either half
bfails:	ld	c,0
bf1:	ld	a,(nchunk)
	cp	c
	ret	z
	call	ctag
	ld	hl,bhigh
	call	bfat
	ret	nz
	ld	hl,blow
	call	bfat
	ret	nz
	inc	c
	jr	bf1

; A against entry C of the table at HL. Keeps A, C.
bfat:	ld	b,0
	add	hl,bc
	cp	(hl)
	ret

; Banking: the tag read for chunk C from the table at HL against its
; own. B = 0 the high half, 1 the low, where a chunk left out of the
; check is shown as NOT CHECKED.
bchk:	push	hl
	push	bc
	ld	a,l
	add	a,c
	ld	l,a
	jr	nc,bc1
	inc	h
bc1:	ld	a,b
	or	a
	jr	z,bc1a
	call	cbit
	push	hl
	ld	hl,blchk
	and	(hl)
	pop	hl
	jr	nz,bc1a
	call	print
	db	"  ",0
	call	ctag
	call	phex4x
	call	print
	db	TH," in the low half ",TK,"NOT CHECKED",TH,": it failed March U or the high half.",TK,0Dh,0Ah,0
	jr	bc4
bc1a:	call	ctag
	cp	(hl)
	jr	z,bc4
	call	print
	db	"  ",0
	call	ctag
	call	phex4x
	call	print
	db	TH," in the ",0
	ld	a,b
	or	a
	jr	nz,bc3
	call	print
	db	"high",0
	jr	bc3a
bc3:	call	print
	db	"low",0
bc3a:	call	print
	db	" half reads ",TK,0
	ld	a,(hl)
	call	phex8
	call	print
	db	TH,", not ",TK,0
	call	ctag
	call	phex8
	call	print
	db	TH,".",TK,0Dh,0Ah,0
bc4:	pop	bc
	pop	hl
	ret

; The errors of chunk C, result at IX
cfail:	call	ctag
	call	phex4x
	call	print
	db	TH,": ",TK,0
	ld	l,(ix+0)
	ld	h,(ix+1)
	call	pdec16
	call	print
	db	TH," errors, first at offset ",TK,0
	ld	l,(ix+3)
	ld	a,(ix+4)
	and	7Fh
	ld	h,a
	call	phex16
	call	print
	db	TH,", wrote ",TK,0
	ld	a,(ix+5)
	call	phex8
	call	print
	db	TH,", read ",TK,0
	ld	a,(ix+6)
	call	phex8
	call	print
	db	TH,".",0Dh,0Ah,"  Bad bits D7-D0: ",TK,0
	ld	a,(ix+2)
	call	pbin8
	call	print
	db	TH,", in the bank ",TK,0
	ld	a,c
	cp	2
	ld	a,'A'
	jr	c,cf1
	inc	a
cf1:	call	putc
	call	print
	db	TH," row of 4164s.",TK,0Dh,0Ah,0
	ret
