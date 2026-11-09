; Start, the command loop, the line editor, the parser and the map.
;
; The normal map: the block at F000h, the monitor's chunk low and another
; high. mapc shows a chunk high with the block at 0000h, so all 32K of it
; can be seen, and mnorm goes back. It writes only when the map changes,
; and each change writes to the block, which lands in A1. So a command
; maps once, runs its loop with nothing written to the block, and prints
; after.

main:	di
	ld	sp,STACK
	ld	hl,VARS
	ld	de,VARS+1
	ld	bc,MVEND-VARS-1
	ld	(hl),0
	ldir
	ld	a,high BLK
	ld	(blkhi),a
	ld	a,1
	ld	(scrout),a
	ld	(sioon),a
	ld	a,40h			; as the boot ROM left it
	ld	(pionow),a
	ld	a,0FFh
	ld	(curmap),a
	ld	(dnext),a
	call	sioinit
	call	crtinit
	call	fontload
	call	mblk0
	call	findb
	call	mblkf
	ld	a,0Ch
	call	putc
	call	print
	db	"MAX-80 monitor. ? or H for help. RAM: A1 A2",0
	ld	a,(nchunk)
	cp	4
	jr	nz,st1
	call	print
	db	" B1 B2",0
st1:	call	crlf

; Commands stop by jumping here, from any depth
cmd:	ld	sp,STACK
	call	mnorm
	xor	a
	ld	(inload),a
	ld	a,(lowch)
	call	pchn
	ld	a,'>'
	call	putc
	call	getline
	ld	hl,LINE
	ld	(lp),hl
	call	skip
	or	a
	jr	z,cmd
	inc	hl
	ld	(lp),hl
	ld	c,a
	ld	hl,ctab
cm1:	ld	a,(hl)
	or	a
	jp	z,ewhat
	inc	hl
	cp	c
	jr	z,cm2
	inc	hl
	inc	hl
	jr	cm1
cm2:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ex	de,hl
	ld	ix,refa
	jp	(hl)

ctab:	db	'D'
	dw	cD
	db	'E'
	dw	cE
	db	'F'
	dw	cF
	db	'M'
	dw	cM
	db	'S'
	dw	cS
	db	'C'
	dw	cC
	db	'K'
	dw	cK
	db	'G'
	dw	cG
	db	'L'
	dw	cL
	db	'P'
	dw	cP
	db	'T'
	dw	cT
	db	'I'
	dw	cI
	db	'O'
	dw	cO
	db	'R'
	dw	cR
	db	'?'
	dw	cHelp
	db	'H'
	dw	cHelp
	db	0

; The message after the call, then back to the prompt
eprint:	call	mnorm
	pop	hl
	call	puts
	call	crlf
	jp	cmd

ewhat:	call	eprint
	db	"What? ? gives help.",0
elen:	call	eprint
	db	"The length is 0.",0
epast:	call	eprint
	db	"That runs past the end.",0
emon:	call	eprint
	db	"The monitor is there. RUN moves it.",0

; ESC or BREAK. Waits for the key to come up, not for long, so that a
; stuck key cannot hang the monitor.
stop:	call	mnorm
	ld	hl,0
sp2:	ld	a,(MATRIX+0C0h)		; rows 6 and 7
	and	24h			; BREAK, ESC
	jr	z,sp3
	dec	hl
	ld	a,h
	or	l
	jr	nz,sp2
sp3:	ld	a,(inload)
	or	a
	call	nz,drain
	call	print
	db	"Stopped.",0
	call	crlf
	jp	cmd

; Checks for ESC or BREAK from either console, with the block anywhere,
; reading only. Keeps every register but A and flags.
brk:	push	hl
	call	brkk
	ld	a,(blkhi)
	or	high (SIOCA-BLK)
	ld	h,a
	ld	l,low SIOCA
	ld	a,(hl)
	rrca
	jr	nc,bk9
	ld	l,low SIODA
	ld	a,(hl)
	cp	1Bh
	jp	z,stop
	cp	3
	jp	z,stop
bk9:	pop	hl
	ret

; The same for the keyboard alone. Keeps HL.
brkk:	push	hl
	ld	a,(blkhi)
	or	high (MATRIX-BLK)
	ld	h,a
	ld	l,40h			; row 6
	ld	a,(hl)
	and	4			; BREAK
	jp	nz,stop
	ld	l,80h			; row 7
	ld	a,(hl)
	and	20h			; ESC
	jp	nz,stop
	pop	hl
	ret

; ---- The map ----

; The block to 0000h, its RAM copy too, as the diag does
mblk0:	ld	a,(vlnow)
	and	0Fh
	ld	(VLATCH),a
	ld	(B_VLATCH),a
	xor	a
	ld	(blkhi),a
	ret

; From there back to the normal map
mblkf:	ld	a,(pionow)
	ld	(B_PIODA),a
	ld	a,(vlnow)
	ld	(B_VLATCH),a
	ld	(VLATCH),a
	ld	a,high BLK
	ld	(blkhi),a
	ret

; Chunk A in the high half, the block at 0000h. Keeps BC, DE, HL.
mapc:	push	hl
	ld	hl,curmap
	cp	(hl)
	jr	z,mc9
	push	bc
	ld	c,a
	ld	a,(hl)
	ld	(hl),c
	inc	a
	call	z,mblk0
	ld	a,c
	rrca
	rrca
	ld	c,a
	ld	a,(pionow)
	and	30h			; the low half stays
	or	c
	ld	(B_PIODA),a
	pop	bc
mc9:	pop	hl
	ret

; The normal map. Keeps BC, DE, HL.
mnorm:	ld	a,(curmap)
	inc	a
	ret	z
	ld	a,0FFh
	ld	(curmap),a
	jp	mblkf

; HL = where the Z80 sees the address at IX, the map set for it. The
; monitor's own chunk is read through the low half with the block at
; F000h. Keeps BC, DE.
point:	ld	a,(ix+0)
	cp	0FFh
	jr	z,pt1
	ld	hl,lowch
	cp	(hl)
	jr	z,pt1
	call	mapc
	ld	l,(ix+1)
	ld	h,(ix+2)
	set	7,h
	ret
pt1:	call	mnorm
	ld	l,(ix+1)
	ld	h,(ix+2)
	ret

; BC bytes, not 0, from the address at IX to DE
getp:	call	point
	ldir
	ret

; BC bytes, not 0, from HL to the address at IX
putp:	push	hl
	call	point
	ex	de,hl
	pop	hl
	ldir
	ret

; The byte at the address at IX
rd1:	ld	de,BUF
	ld	bc,1
	call	getp
	ld	a,(BUF)
	ret

; The address at IX on by BC, and back by BC. Keep BC.
adv:	ld	l,(ix+1)
	ld	h,(ix+2)
	add	hl,bc
adv1:	ld	(ix+1),l
	ld	(ix+2),h
	ret
back:	ld	l,(ix+1)
	ld	h,(ix+2)
	or	a
	sbc	hl,bc
	jr	adv1

; BC = the next piece of rlen, at most 256 bytes (nextn) or DE (nextd),
; taken off rlen. Z when none is left. Stops on ESC or BREAK.
nextn:	ld	de,256
nextd:	call	brk
	ld	hl,(rlen)
	ld	a,h
	or	l
	ret	z
	ld	b,d
	ld	c,e
	or	a
	sbc	hl,de
	jr	nc,nx1
	add	hl,de
	ld	b,h
	ld	c,l
	ld	hl,0
nx1:	ld	(rlen),hl
	or	1
	ret

; ---- Keys and the line ----

; A = a key from the keyboard or channel A, flags set from A, Z if none.
; The keyboard's matrix gives no shifted codes, so they are made here,
; as Lobo's BIOS does: letters lower case, SHIFT upper, and the TRS-80
; symbols on the digits and punctuation. CLEAR and LEFT rub out.
mkey:	call	poll
	ld	a,(kkey)
	or	a
	jr	z,mk6
	ld	c,a
	xor	a
	ld	(kkey),a
	ld	a,(k1+7)
	ld	b,a
	ld	a,c
	cp	1Fh
	jr	z,mk0
	cp	82h
	jr	nz,mk1
mk0:	ld	a,8
	or	a
	ret
mk1:	cp	'A'
	jr	c,mk3
	cp	'Z'+1
	jr	nc,mk9
	bit	0,b
	jr	nz,mk9
	or	20h
	ret
mk3:	bit	0,b
	jr	z,mk9
	cp	'1'
	jr	c,mk4
	cp	';'+1
	jr	nc,mk9
	sub	10h			; 1-9 to !-), : and ; to * and +
	ret
mk4:	cp	','
	jr	c,mk9
	cp	'0'
	jr	z,mk9
	add	a,10h			; , - . / to < = > ?
	ret
mk9:	or	a
	ret
mk6:	ld	a,(SIOCA)
	and	1
	ret	z
	ld	a,(SIODA)
	and	7Fh
	ret

; Waits for a key, with the cursor up
waitk:	call	curon
wk1:	call	mkey
	jr	z,wk1
	jp	curoff

; A line into LINE, ended by a 0, upper case outside quotes. lesc is set
; if ESC or BREAK ended it, and the line is then empty.
getline:
	xor	a
	ld	(inq),a
	ld	(lesc),a
	ld	hl,LINE
	ld	b,a
gl1:	push	bc
	push	hl
	call	waitk
	pop	hl
	pop	bc
	cp	0Dh
	jr	z,gl9
	cp	8
	jr	z,glbs
	cp	7Fh
	jr	z,glbs
	cp	1Bh
	jr	z,glesc
	cp	3
	jr	z,glesc
	cp	' '
	jr	c,gl1
	cp	7Fh
	jr	nc,gl1
	ld	c,a
	ld	a,b
	cp	LINEMAX
	jr	nc,gl1
	ld	a,c
	cp	'"'
	call	z,qflip
	ld	a,(inq)
	or	a
	ld	a,c
	jr	nz,gl2
	cp	'a'
	jr	c,gl2
	cp	'z'+1
	jr	nc,gl2
	sub	20h
gl2:	ld	(hl),a
	inc	hl
	inc	b
	call	putc
	jr	gl1
glbs:	ld	a,b
	or	a
	jr	z,gl1
	dec	hl
	dec	b
	ld	a,(hl)
	cp	'"'
	call	z,qflip
	push	bc
	push	hl
	call	rubout
	pop	hl
	pop	bc
	jr	gl1
glesc:	ld	a,1
	ld	(lesc),a
	ld	hl,LINE
gl9:	ld	(hl),0
	jp	crlf

qflip:	ld	a,(inq)
	xor	1
	ld	(inq),a
	ret

; Takes the last character off the screen and the terminal
rubout:	ld	hl,ccol
	dec	(hl)
	ld	c,' '
	call	vputc
	ld	hl,ccol
	dec	(hl)
	ld	a,(sioon)
	or	a
	ret	z
	ld	a,8
	call	sout
	ld	a,' '
	call	sout
	ld	a,8
	jp	sout

; The cursor is a 7Fh in video RAM, as Lobo's BIOS has it, and never in
; SHADOW. curoff puts back the space under it. Both keep A, BC.
curon:	push	af
	ld	a,7Fh
	jr	cu1
curoff:	push	af
	ld	a,' '
cu1:	ld	hl,(crow)
	call	vidx
	call	vaddr
	ld	(de),a
	pop	af
	ret

; ---- The parser ----

; Past spaces and commas. A = the next character, HL = its place.
skip:	ld	hl,(lp)
sk1:	ld	a,(hl)
	cp	' '
	jr	z,sk2
	cp	','
	jr	nz,sk3
sk2:	inc	hl
	jr	sk1
sk3:	ld	(lp),hl
	or	a
	ret

; Z if nothing more is on the line
atend:	jp	skip

; Nothing more on the line, or What?
endl:	call	skip
	ret	z
	jp	ewhat

; A hex digit in A to its value, carry if it is not one. Keeps the rest.
hexv:	cp	'a'
	jr	c,hv1
	sub	20h
hv1:	sub	'0'
	ret	c
	cp	10
	ccf
	ret	nc
	sub	7
	cp	10
	ret	c
	cp	16
	ccf
	ret

; HL = a hex number of up to 4 digits from the line
gethex:	call	skip
	ex	de,hl
	ld	hl,0
	ld	b,0
gh1:	ld	a,(de)
	call	hexv
	jr	c,gh2
	inc	b
	bit	2,b
	jr	z,gh3
	bit	0,b
	jp	nz,ewhat		; a fifth digit
gh3:	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	or	l
	ld	l,a
	inc	de
	jr	gh1
gh2:	ld	a,b
	or	a
	jp	z,ewhat
	ld	(lp),de
	ld	a,(de)
	or	a
	ret	z
	cp	' '
	ret	z
	cp	','
	ret	z
	jp	ewhat

; A = a hex byte from the line
getbyte:
	call	gethex
	ld	a,h
	or	a
	jp	nz,ewhat
	ld	a,l
	ret

; Chunk name at HL. A = the chunk and HL past it, or carry.
chname:	ld	b,0
	ld	a,(hl)
	cp	'A'
	jr	z,cn1
	ld	b,2
	cp	'B'
	scf
	ret	nz
cn1:	inc	hl
	ld	a,(hl)
	dec	hl
	cp	'1'
	jr	z,cn2
	inc	b
	cp	'2'
	scf
	ret	nz
cn2:	inc	hl
	inc	hl
	ld	a,b
	or	a
	ret

; Refuses a chunk this machine does not have. Keeps A.
chkch:	ld	hl,nchunk
	cp	(hl)
	ret	c
	call	eprint
	db	"This machine has no such chunk.",0

; An address from the line to IX: 1234, or A2:1234
getaddr:
	call	skip
	call	chname
	jr	c,ga5
	ld	c,a
	ld	a,(hl)
	cp	':'
	jr	nz,ga5
	inc	hl
	ld	(lp),hl
	ld	a,c
	call	chkch
	ld	(ix+0),a
	call	gethex
	bit	7,h
	jp	nz,epast
	jr	ga6
ga5:	ld	(ix+0),0FFh
	call	gethex
ga6:	ld	(ix+1),l
	ld	(ix+2),h
	ret

; A length from the line to rlen
getlen:	call	gethex
	ld	a,h
	or	l
	jp	z,elen
	ld	(rlen),hl
	ret

; Refuses the rlen bytes at IX if they run off the chunk or the 64K
chkrng:	ld	l,(ix+1)
	ld	h,(ix+2)
	ld	de,(rlen)
	add	hl,de
	ld	a,(ix+0)
	inc	a
	jr	z,cr1
	jp	c,epast
	ld	de,8001h
	or	a
	sbc	hl,de
	ret	c
	jp	epast
cr1:	ret	nc
	ld	a,h
	or	l
	ret	z
	jp	epast

; Carry if the rlen bytes at IX reach the monitor: the program or
; 7000h-7FFFh of the chunk in the low half.
over:	ld	a,(ix+0)
	cp	0FFh
	jr	z,ov1
	ld	hl,lowch
	cp	(hl)
	jr	z,ov1
	or	a
	ret
ov1:	ld	e,(ix+1)
	ld	d,(ix+2)
	ld	hl,(rlen)
	dec	hl
	add	hl,de			; HL = the last byte, DE = the first
	ld	bc,1000h
	call	cmphl
	jr	c,ov3
	ex	de,hl
	ld	bc,PROG_END
	call	cmphl
	ex	de,hl
	ret	c
	ld	bc,7000h
	call	cmphl
	jr	c,ov3
	ex	de,hl
	ld	bc,8000h
	call	cmphl
	ex	de,hl
	ret
ov3:	or	a
	ret

; Carry if HL is below BC. Keeps HL.
cmphl:	push	hl
	or	a
	sbc	hl,bc
	pop	hl
	ret

; Checks before a command writes the rlen bytes at IX
wchk:	call	chkrng
	call	over
	jp	c,emon
	; falls into blkask

; A Z80 address in the I/O block reads and writes devices. Says so and
; asks. The chunk forms never reach the block.
blkask:	ld	a,(ix+0)
	inc	a
	ret	nz
	ld	l,(ix+1)
	ld	h,(ix+2)
	ld	de,(rlen)
	dec	de
	add	hl,de
	ld	a,h
	cp	high BLK
	ret	c
	call	print
	db	"That is the I/O block: a read of 7E0h clears the tick. Y goes on:",0
	call	waitk
	push	af
	call	crlf
	pop	af
	and	0DFh
	cp	'Y'
	ret	z
	jp	cmd

; ---- Printing ----

; cons.asm calls this for the diag's results area, not used here
rclear:	ret

crlf:	ld	a,0Dh
	call	putc
	ld	a,0Ah
	jp	putc

space:	ld	a,' '
	jp	putc

; A as two hex digits
ph2:	push	af
	rrca
	rrca
	rrca
	rrca
	call	phex4
	pop	af
	jp	phex4

; HL as four
ph4:	ld	a,h
	call	ph2
	ld	a,l
	jr	ph2

; The name of chunk A
pchn:	push	af
	rrca
	and	1
	add	a,'A'
	call	putc
	pop	af
	and	1
	add	a,'1'
	jp	putc

; The address at IX
pref:	ld	a,(ix+0)
	cp	0FFh
	jr	z,pf1
	call	pchn
	ld	a,':'
	call	putc
pf1:	ld	l,(ix+1)
	ld	h,(ix+2)
	jr	ph4
