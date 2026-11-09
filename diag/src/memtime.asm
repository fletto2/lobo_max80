; Memory timing. TRM TS-3: "Every video memory access causes the
; Z80 clock to stretch a small but unpredictable amount", with no figure,
; and TS-8 says SLORAM runs slowly. So each kind of memory gets passes of
; 16 reads or 16 writes, counted over MTK ticks, against the same passes
; on plain RAM. A pass on plain RAM is MTLOOP T-states, the two wait
; states of the SYSCLR read included (TS-3). A slower memory makes
; fewer passes, and the T-states an access costs over plain RAM are
; MTLOOP x (plain passes - its passes) / (its passes x 16). That is a
; ratio of counts, so the CPU clock does not enter it. Each kind is run
; MTRUNS times, each run against a plain run just before it, and the
; lowest and highest figures shown.

MTK	equ	8			; ticks a run
MTRUNS	equ	4
MTLOOP	equ	149			; 16 x 7, INC DE 6, LD A,(SYSCLR) 15, RLCA 4, JR 12
MTPLAIN	equ	0A000h			; plain RAM: A2, the high half

; A kind: bit 1 writes, bit 2 through the window on font RAM, the
; address, the name
mtkinds:
	db	1
	dw	BLK+0C00h, mtn1
	db	2
	dw	BLK+0C00h, mtn2
	db	5
	dw	BLK, mtn3
	db	6
	dw	BLK, mtn4
	db	1
	dw	BLK+0700h, mtn5
	db	2
	dw	BLK+0700h, mtn6
	db	0

mtn1:	db	"Video RAM, reads:",0
mtn2:	db	"Video RAM, writes:",0
mtn3:	db	"Font RAM, reads:",0
mtn4:	db	"Font RAM, writes:",0
mtn5:	db	"SLORAM, reads:",0
mtn6:	db	"SLORAM, writes:",0

mtbase:	dw	0			; passes on plain RAM
mtpass:	dw	0			; and on the memory timed
mtmin:	dw	0
mtmax:	dw	0

mttest:	ld	a,0Ch
	call	putc
	call	print
	db	"MEMORY TIMING TEST",0
	ld	hl,13
	call	at
	call	print
	db	TH,"T-states an access takes over plain RAM, lowest and highest of 4 runs, timed",0Dh,0Ah
	db	"against the tick. The TRM says video RAM stretches the clock a small but",0Dh,0Ah
	db	"unpredictable amount, and SLORAM runs slowly. The TRM gives no figure.",TK,0Dh,0Ah,0Ah
	db	" Any key  ",TH,"Measure again",TK,"          ESC  ",TH,"Back to the menu",TK,0
mt_again:	call	mtall
mt_key:	call	waitkey
	cp	1Bh
	jp	z,drawmenu
	cp	03h			; BREAK
	jp	z,drawmenu
	jr	mt_again

; Every kind, a row each from row 3, then the plain passes
mtall:	ld	ix,mtkinds
	ld	l,3
mt_ma1:	ld	a,(ix+0)
	or	a
	jr	z,mt_ma3
	push	hl
	call	mtone
	pop	hl
	push	hl
	ld	h,0
	call	at
	call	clreol
	ld	a,TH
	call	putc
	ld	l,(ix+3)
	ld	h,(ix+4)
	call	puts
	ld	a,TK
	call	putc
	ld	hl,21*256
	pop	de
	push	de
	ld	l,e
	call	at
	ld	hl,(mtmin)
	ld	a,100
	call	pfix
	call	print
	db	TH," to ",TK,0
	ld	hl,(mtmax)
	ld	a,100
	call	pfix
	call	print
	db	TH," T an access",TK,0
	pop	hl
	inc	l
	ld	bc,5
	add	ix,bc
	jr	mt_ma1
mt_ma3:	inc	l
	ld	h,0
	call	at
	call	clreol
	call	print
	db	TH,"Plain RAM: ",TK,0
	ld	hl,(mtbase)
	call	pdec16
	call	print
	db	TH," passes of 149 T in 8 ticks",TK,0
	ret

; The kind at IX: MTRUNS runs, the lowest and highest in mtmin, mtmax,
; in hundredths of a T-state
mtone:	ld	hl,0FFFFh
	ld	(mtmin),hl
	ld	hl,0
	ld	(mtmax),hl
	ld	b,MTRUNS
mt_mo1:	push	bc
	ld	hl,MTPLAIN
	call	mtgo
	ld	(mtbase),de
	bit	2,(ix+0)
	jr	z,mt_mo2
	ld	a,(vlnow)		; the window on font RAM 00h-7Fh
	and	0F8h
	or	4
	ld	(VLATCH),a
mt_mo2:	ld	l,(ix+1)
	ld	h,(ix+2)
	call	mtgo
	ld	(mtpass),de
	ld	a,(vlnow)		; the window as it was
	ld	(VLATCH),a
	call	mtcalc
	ex	de,hl
	ld	hl,(mtmin)
	or	a
	sbc	hl,de
	jr	c,mt_mo3
	ld	(mtmin),de
mt_mo3:	ld	hl,(mtmax)
	or	a
	sbc	hl,de
	jr	nc,mt_mo4
	ld	(mtmax),de
mt_mo4:	pop	bc
	djnz	mt_mo1
	ret

; Reads or writes, as the kind at IX says, at HL: the passes in DE
mtgo:	bit	1,(ix+0)
	jr	nz,mtwrite

; Passes of 16 reads at HL in MTK ticks, into DE
mtread:	ld	c,MTK
	ld	a,(SYSCLR)		; a tick left from before does not count
mt_mr0:	ld	a,(SYSCLR)		; from the next tick
	rlca
	jr	nc,mt_mr0
	ld	de,0
mt_mr1:	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	ld	a,(hl)
	inc	de
	ld	a,(SYSCLR)
	rlca
	jr	nc,mt_mr1
	dec	c
	jr	nz,mt_mr1
	ret

; Passes of 16 writes at HL in MTK ticks, into DE. The byte written is
; the one there, so the screen and the font do not change.
mtwrite:
	ld	b,(hl)
	ld	c,MTK
	ld	a,(SYSCLR)		; a tick left from before does not count
mt_mw0:	ld	a,(SYSCLR)
	rlca
	jr	nc,mt_mw0
	ld	de,0
mt_mw1:	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	ld	(hl),b
	inc	de
	ld	a,(SYSCLR)
	rlca
	jr	nc,mt_mw1
	dec	c
	jr	nz,mt_mw1
	ret

; HL = MTLOOP x 100 x (mtbase - mtpass) / (mtpass x 16), rounded, the
; hundredths of a T-state an access costs. 0 if the memory was no slower.
mtcalc:	ld	hl,(mtbase)
	ld	de,(mtpass)
	or	a
	sbc	hl,de
	jr	c,mt_mc1
	jr	z,mt_mc1
	ex	de,hl
	ld	bc,MTLOOP*100
	call	setdvd
	ld	bc,(mtpass)
	ld	de,16
	jp	vdiv
mt_mc1:	ld	hl,0
	ret
