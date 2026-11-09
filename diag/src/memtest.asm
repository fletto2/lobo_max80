; Video RAM and font RAM tests. Each RAM is 2K, seen as two 1K pieces,
; and gets March U once for each of four backgrounds.

; The two pieces of a RAM: VLATCH, CPU address, offset in the RAM less
; the CPU address
vsegs:	db	VL_VIDEO
	dw	VIDLO,(0-VIDLO) & 0FFFFh	; video RAM 000h-3FFh
	db	VL_VIDEO
	dw	VIDWIN,(400h-VIDWIN) & 0FFFFh	; 400h-7FFh in the window
fsegs:	db	VL_ROM+4
	dw	BLK,(0-BLK) & 0FFFFh	; font RAM 1, characters 00h-7Fh
	db	VL_ROM+6
	dw	BLK,(400h-BLK) & 0FFFFh	; font RAM 2, 80h-BFh

; The 0 of each march, its 1 the inverse. Between them every two bits
; of a byte are both alike and different, so bits shorted together show.
bgtab:	db	00h,55h,33h,0Fh
NBG	equ	$-bgtab

; March U: direction (0 up), the work on each byte
mutab:	db	0
	dw	mw0
	db	0
	dw	mr0w1r1w0
	db	0
	dw	mr0w1
	db	1
	dw	mr1w0r0w1
	db	1
	dw	mr1w0
NMU	equ	($-mutab)/3

; Video RAM: the screen is lost while it runs and redrawn after.
; A = 0 and Z if it passed.
tvram:	xor	a
	ld	(scrout),a
	ld	ix,vsegs
	call	mtrun
	call	vredraw
	ld	a,1
	ld	(scrout),a
	jr	mtres

; Font RAM: the font is lost while it runs and loaded again after
tfram:	ld	ix,fsegs
	call	mtrun
	call	fontload
mtres:	ld	hl,(merr)
	ld	a,h
	or	l
	ret	z
	ld	a,1
	or	a
	ret

; March U over the RAM at IX for each background. D holds the 0 of the
; march, E the 1.
mtrun:	ld	hl,0
	ld	(merr),hl
	xor	a
	ld	(mbits),a
	ld	hl,bgtab
	ld	b,NBG
mr1:	push	bc
	ld	d,(hl)
	ld	a,d
	cpl
	ld	e,a
	inc	hl
	push	hl
	ld	hl,mutab
	ld	b,NMU
mr2:	push	bc
	ld	a,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	push	bc
	pop	iy
	push	hl
	call	melem
	pop	hl
	pop	bc
	djnz	mr2
	call	poll			; keep the keyboard scanned
	pop	hl
	pop	bc
	djnz	mr1
	ld	a,(vlnow)
	ld	(VLATCH),a
	ret

; One march element over the RAM at IX, up when A is 0, down when not:
; IY works on the byte at HL. Keeps DE.
melem:	push	ix
	ld	(mdir),a
	or	a
	jr	z,me1
	ld	bc,5			; down: the second piece first
	add	ix,bc
me1:	ld	b,2
me2:	push	bc
	ld	a,(ix+0)
	ld	(VLATCH),a
	ld	l,(ix+3)
	ld	h,(ix+4)
	ld	(mdelta),hl
	ld	l,(ix+1)
	ld	h,(ix+2)
	ld	bc,400h
	ld	a,(mdir)
	or	a
	jr	z,me4
	push	de
	ld	de,3FFh			; down from the top byte
	add	hl,de
	pop	de
me3:	call	jpiy
	dec	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,me3
	ld	bc,-5
	jr	me6
me4:	call	jpiy
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,me4
	ld	bc,5
me6:	add	ix,bc
	pop	bc
	djnz	me2
	pop	ix
	ret

jpiy:	jp	(iy)

mw0:	ld	(hl),d
	ret

mr0w1r1w0:
	ld	a,(hl)
	cp	d
	call	nz,merrd
	ld	(hl),e
	ld	a,(hl)
	cp	e
	call	nz,merre
	ld	(hl),d
	ret

mr0w1:	ld	a,(hl)
	cp	d
	call	nz,merrd
	ld	(hl),e
	ret

mr1w0r0w1:
	ld	a,(hl)
	cp	e
	call	nz,merre
	ld	(hl),d
	ld	a,(hl)
	cp	d
	call	nz,merrd
	ld	(hl),e
	ret

mr1w0:	ld	a,(hl)
	cp	e
	call	nz,merre
	ld	(hl),d
	ret

; A wrong byte at HL: A came back, D (merrd) or E (merre) was written.
; Keeps BC, DE and HL.
merrd:	push	bc
	ld	c,d
	jr	me7
merre:	push	bc
	ld	c,e
me7:	push	hl
	ld	b,a
	xor	c
	ld	hl,mbits
	or	(hl)
	ld	(hl),a
	ld	hl,(merr)
	ld	a,h
	or	l
	jr	nz,me8
	pop	hl			; the first: its offset in the RAM
	push	hl
	push	de
	ld	de,(mdelta)
	add	hl,de
	ld	(mfirst),hl
	pop	de
	ld	a,c
	ld	(mwrote),a
	ld	a,b
	ld	(mread),a
	ld	hl,0
me8:	inc	hl
	ld	a,h
	or	l
	jr	z,me9			; stays at FFFFh
	ld	(merr),hl
me9:	pop	hl
	pop	bc
	ret

vreport:
	call	print
	db	TH,"Video RAM (D16): ",TK,0
	jr	mreport
freport:
	call	print
	db	TH,"Font RAM (E21): ",TK,0

; The result of the last test, from merr on
mreport:
	ld	hl,(merr)
	ld	a,h
	or	l
	jr	nz,rp1
	call	print
	db	"PASS",TH,", ",TK,"2048",TH," bytes, March U, ",TK,"4",TH," backgrounds",TK,0Dh,0Ah,0
	ret
rp1:	call	print
	db	"FAIL",TH,", ",TK,0
	call	pdec16
	call	print
	db	TH," errors",0Dh,0Ah
	db	"  First at offset ",TK,0
	ld	hl,(mfirst)
	call	phex16
	call	print
	db	TH,", wrote ",TK,0
	ld	a,(mwrote)
	call	phex8
	call	print
	db	TH,", read ",TK,0
	ld	a,(mread)
	call	phex8
	call	print
	db	TH,". Bad bits D7-D0: ",TK,0
	ld	a,(mbits)
	call	pbin8
	call	print
	db	0Dh,0Ah,0
	ret
