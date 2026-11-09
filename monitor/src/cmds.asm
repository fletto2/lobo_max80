; The commands, but for L and P, srec.asm. Each starts with IX = refa.
; A command that loops over memory writes nothing to the block and
; prints nothing until the loop ends, since every write in the I/O block
; also lands in A1.

DLINES	equ	21			; D: lines a screen

; D addr [len], and D alone goes on from the last
cD:	call	atend
	jr	nz,cd1
	ld	hl,dnext
	ld	de,refa
	ld	bc,3
	ldir
	ld	hl,DLINES*16
	jr	cd2
cd1:	call	getaddr
	call	atend
	ld	hl,DLINES*16
	jr	z,cd2
	call	gethex
	ld	a,h
	or	l
	jp	z,elen
cd2:	ld	(rlen),hl
	call	endl
	call	chkrng
	call	blkask
	xor	a
	ld	(dlines),a
cd3:	ld	de,16
	call	nextd
	jr	z,cd9
	ld	(pn),bc
	ld	de,BUF
	call	getp
	call	mnorm
	call	dline
	ld	bc,(pn)
	call	adv
	ld	hl,dlines
	inc	(hl)
	ld	a,(hl)
	cp	DLINES
	jr	nz,cd3
	ld	(hl),0
	ld	hl,(rlen)
	ld	a,h
	or	l
	jr	z,cd9
	call	print
	db	"More: any key, ESC stops.",0
	call	waitk
	push	af
	ld	a,0Dh
	call	putc
	call	clreol
	pop	af
	cp	1Bh
	jr	z,cd9
	cp	3
	jr	nz,cd3
cd9:	ld	hl,refa
	ld	de,dnext
	ld	bc,3
	ldir
	jp	cmd

; One line of D: the address, pn bytes of BUF in hex and as text
dline:	call	pref
	call	space
	ld	hl,BUF
	ld	b,16
	ld	a,(pn)
	ld	c,a
dl1:	call	space
	ld	a,c
	or	a
	jr	z,dl2
	dec	c
	ld	a,(hl)
	inc	hl
	call	ph2
	jr	dl3
dl2:	call	space
	call	space
dl3:	djnz	dl1
	call	space
	call	space
	ld	hl,BUF
	ld	a,(pn)
	ld	b,a
dl4:	ld	a,(hl)
	inc	hl
	cp	' '
	jr	c,dl5
	cp	7Fh
	jr	c,dl6
dl5:	ld	a,'.'
dl6:	call	putc
	djnz	dl4
	jp	crlf

; E addr: a hex byte and Enter writes, Enter alone goes to the next,
; a dot or ESC ends
cE:	call	getaddr
	call	endl
	ld	hl,1
	ld	(rlen),hl
	call	chkrng
ce0:	call	rd1
	ld	(ebyte),a
	call	mnorm
	call	pref
	call	space
	ld	a,(ebyte)
	call	ph2
	call	space
	call	getline
	ld	a,(lesc)
	or	a
	jp	nz,cmd
	ld	hl,LINE
	ld	(lp),hl
	call	skip
	jp	z,ce5
	cp	'.'
	jp	z,cmd
	call	getbyte
	ld	(ewrote),a
	call	endl
	call	over
	jp	c,emon
	ld	hl,ewrote
	ld	bc,1
	call	putp
	call	rd1
	ld	(ebyte),a
	call	mnorm
	ld	a,(ewrote)
	ld	hl,ebyte
	cp	(hl)
	jr	z,ce4
	call	print
	db	"Did not stick: wrote ",0
	ld	a,(ewrote)
	call	phex8
	call	print
	db	", read ",0
	ld	a,(ebyte)
	call	phex8
	call	print
	db	", bits ",0
	ld	a,(ewrote)
	ld	hl,ebyte
	xor	(hl)
	call	pbin8
	call	crlf
	jr	ce5
ce4:	call	print
	db	"Now ",0
	ld	a,(ebyte)
	call	phex8
	call	crlf
ce5:	ld	bc,1
	call	adv
	ld	a,(ix+0)
	inc	a
	jp	z,ce0
	bit	7,(ix+2)		; off the end of the chunk
	jp	z,ce0
	jp	cmd

; F addr len byte
cF:	call	getaddr
	call	getlen
	call	getbyte
	ld	(BUF),a
	call	endl
	call	wchk
	ld	hl,BUF
	ld	de,BUF+1
	ld	bc,255
	ldir
cf1:	call	nextn
	jr	z,cf2
	push	bc
	ld	hl,BUF
	call	putp
	pop	bc
	call	adv
	jr	cf1
cf2:	call	eprint
	db	"Filled.",0

; M from to len, through BUF, so the two can be in different chunks.
; Backward when the same memory overlaps upward.
cM:	call	getaddr
	ld	ix,refb
	call	getaddr
	call	getlen
	call	endl
	call	wchk
	ld	ix,refa
	call	chkrng
	call	blkask
	ld	a,(refa)
	ld	hl,refb
	cp	(hl)
	jr	nz,cm5
	ld	hl,(refb+1)
	ld	de,(refa+1)
	or	a
	sbc	hl,de
	jr	c,cm5
	ld	de,(rlen)
	or	a
	sbc	hl,de
	jr	nc,cm5
	ld	bc,(rlen)		; to the end of both
	call	adv
	ld	ix,refb
	call	adv
cm3:	call	nextn
	jr	z,cm9
	ld	ix,refa
	call	back
	ld	ix,refb
	call	back
	ld	ix,refa
	push	bc
	ld	de,BUF
	call	getp
	pop	bc
	ld	ix,refb
	ld	hl,BUF
	call	putp
	jr	cm3
cm5:	call	nextn
	jr	z,cm9
	ld	ix,refa
	push	bc
	ld	de,BUF
	call	getp
	pop	bc
	push	bc
	call	adv
	pop	bc
	ld	ix,refb
	push	bc
	ld	hl,BUF
	call	putp
	pop	bc
	call	adv
	jr	cm5
cm9:	call	eprint
	db	"Moved.",0

; Starts a list of hits
hclear:	ld	hl,0
	ld	(hcount),hl
	ld	(coff),hl
	xor	a
	ld	(hn),a
	ret

; Keeps a hit at coff with bytes B and C, while there is room, and
; counts it. Keeps BC, DE, HL.
addhit:	push	de
	push	hl
	ld	hl,(hcount)
	inc	hl
	ld	a,h
	or	l
	jr	nz,ah1
	dec	hl
ah1:	ld	(hcount),hl
	ld	a,(hn)
	cp	NHIT
	jr	nc,ah9
	inc	a
	ld	(hn),a
	dec	a
	add	a,a
	add	a,a
	ld	l,a
	ld	h,0
	ld	de,HITS
	add	hl,de
	ld	de,(coff)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(hl),b
	inc	hl
	ld	(hl),c
ah9:	pop	hl
	pop	de
	ret

; coff on by 1. Keeps all but flags.
offinc:	push	hl
	ld	hl,(coff)
	inc	hl
	ld	(coff),hl
	pop	hl
	ret

; rtmp = the address at HL (3 bytes) plus the offset DE, IX = rtmp.
; Keeps BC.
hitref:	ld	ix,rtmp
	ld	a,(hl)
	ld	(ix+0),a
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	add	hl,de
	ld	(ix+1),l
	ld	(ix+2),h
	ret

; The count in hcount and the word after the call
pcount:	ld	hl,(hcount)
	call	pdec16
	pop	hl
	call	puts
	push	hl
	jp	crlf

; C addr addr len: the first differences, then a count
cC:	call	getaddr
	ld	ix,refb
	call	getaddr
	call	getlen
	call	endl
	call	chkrng
	call	blkask
	ld	ix,refa
	call	chkrng
	call	blkask
	ld	hl,refa
	ld	de,refc
	ld	bc,6			; refa, refb to refc, refd
	ldir
	call	hclear
cc1:	call	nextn
	jr	z,cc5
	ld	(pn),bc
	ld	ix,refa
	ld	de,BUF
	call	getp
	ld	bc,(pn)
	call	adv
	ld	ix,refb
	ld	de,BUF2
	call	getp
	ld	bc,(pn)
	call	adv
	ld	hl,BUF
	ld	de,BUF2
	ld	bc,(pn)
cc2:	ld	a,(de)
	cp	(hl)
	jr	z,cc3
	push	bc
	ld	b,(hl)
	ld	c,a
	call	addhit
	pop	bc
cc3:	call	offinc
	inc	hl
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,cc2
	jr	cc1
cc5:	call	mnorm
	ld	hl,HITS
	ld	a,(hn)
	or	a
	jr	z,cc8
	ld	b,a
cc6:	push	bc
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	push	hl
	push	de
	ld	hl,refc
	call	hitref
	call	pref
	call	space
	pop	de
	pop	hl
	ld	a,(hl)
	call	ph2
	call	print
	db	"  ",0
	push	hl
	ld	hl,refd
	call	hitref
	call	pref
	call	space
	pop	hl
	inc	hl
	ld	a,(hl)
	call	ph2
	inc	hl
	call	crlf
	pop	bc
	djnz	cc6
cc8:	call	pcount
	db	" differences.",0
	jp	cmd

; K addr len: an 8-bit sum and CRC-16/XMODEM
cK:	call	getaddr
	call	getlen
	call	endl
	call	chkrng
	call	blkask
	xor	a
	ld	(ksum),a
	ld	h,a
	ld	l,a
	ld	(kcrc),hl
ck1:	call	nextn
	jr	z,ck5
	ld	(pn),bc
	ld	de,BUF
	call	getp
	ld	bc,(pn)
	call	adv
	ld	hl,BUF
	ld	de,(kcrc)
	ld	bc,(pn)
ck2:	push	bc
	ld	c,(hl)
	ld	a,(ksum)
	add	a,c
	ld	(ksum),a
	ld	a,c
	xor	d			; t = high byte xor data
	ld	c,a
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	xor	c			; t = t xor t >> 4
	ld	c,a
	rrca
	rrca
	rrca
	ld	b,a
	and	1Fh
	xor	e
	ld	d,a			; high = low xor t >> 3
	ld	a,c
	rlca
	rlca
	rlca
	rlca
	and	0F0h
	xor	d
	ld	d,a			; xor t << 4
	ld	a,b
	and	0E0h
	xor	c
	ld	e,a			; low = t << 5 xor t
	pop	bc
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,ck2
	ld	(kcrc),de
	jr	ck1
ck5:	call	mnorm
	call	print
	db	"Sum ",0
	ld	a,(ksum)
	call	phex8
	call	print
	db	", CRC-16 ",0
	ld	hl,(kcrc)
	call	phex16
	call	crlf
	jp	cmd

; S addr len bytes: bytes in hex, or a string in quotes, or both
cS:	call	getaddr
	call	getlen
	ld	de,PAT
	ld	b,0
cs1:	push	bc
	push	de
	call	skip
	pop	de
	pop	bc
	jr	z,cs5
	cp	'"'
	jr	z,cs3
	push	bc
	push	de
	call	getbyte
	pop	de
	pop	bc
	call	patadd
	jr	cs1
cs3:	inc	hl
	ld	a,(hl)
	or	a
	jr	z,cs4
	cp	'"'
	jr	z,cs35
	call	patadd
	jr	cs3
cs35:	inc	hl
cs4:	ld	(lp),hl
	jr	cs1
cs5:	ld	a,b
	or	a
	jp	z,ewhat
	ld	l,a
	ld	h,0
	ld	(plen),hl
	call	chkrng
	call	blkask
	ld	hl,refa
	ld	de,refc
	ld	bc,3
	ldir
	call	hclear
cs6:	call	brk
	ld	hl,(rlen)
	ld	de,(plen)
	or	a
	sbc	hl,de
	jr	c,cs20
	inc	hl			; places left to try
	ld	de,256
	call	minde
	ld	(np),hl
	ld	de,(plen)
	add	hl,de
	dec	hl
	ld	b,h
	ld	c,l
	ld	de,BUF
	call	getp
	ld	hl,BUF
	ld	bc,(np)
cs7:	push	bc
	push	hl
	ld	de,PAT
	ld	a,(plen)
	ld	b,a
cs8:	ld	a,(de)
	cp	(hl)
	jr	nz,cs9
	inc	hl
	inc	de
	djnz	cs8
	call	addhit
cs9:	pop	hl
	pop	bc
	call	offinc
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,cs7
	ld	bc,(np)
	call	adv
	ld	hl,(rlen)
	or	a
	sbc	hl,bc
	ld	(rlen),hl
	jr	cs6
cs20:	call	mnorm
	ld	hl,HITS
	ld	a,(hn)
	or	a
	jr	z,cs24
	ld	b,a
cs21:	push	bc
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	inc	hl
	inc	hl
	push	hl
	ld	hl,refc
	call	hitref
	call	pref
	call	crlf
	pop	hl
	pop	bc
	djnz	cs21
cs24:	call	pcount
	db	" found.",0
	jp	cmd

; A to the pattern, B bytes so far
patadd:	ld	c,a
	ld	a,b
	cp	PATMAX
	jp	nc,ewhat
	ld	a,c
	ld	(de),a
	inc	de
	inc	b
	ret

; HL = the smaller of HL and DE
minde:	push	hl
	or	a
	sbc	hl,de
	pop	hl
	ret	c
	ex	de,hl
	ret

; T addr len: each pattern written over all of it, then read back
NTPAT	equ	5
tptab:	db	55h,0AAh,00h,0FFh	; the fifth comes from the address

cT:	call	getaddr
	call	getlen
	call	endl
	call	wchk
	ld	hl,refa
	ld	de,refc
	ld	bc,3
	ldir
	ld	hl,(rlen)
	ld	(tlen),hl
	call	hclear
	xor	a
	ld	(tbits),a
	ld	(tpat),a
ct1:	call	trest
ct2:	call	nextn
	jr	z,ct3
	ld	(pn),bc
	call	tmake
	ld	bc,(pn)
	ld	hl,BUF2
	call	putp
	ld	bc,(pn)
	call	adv
	jr	ct2
ct3:	call	trest
	ld	hl,0
	ld	(coff),hl
ct4:	call	nextn
	jr	z,ct7
	ld	(pn),bc
	call	tmake
	ld	bc,(pn)
	ld	de,BUF
	call	getp
	ld	hl,BUF
	ld	de,BUF2
	ld	bc,(pn)
ct6:	ld	a,(de)
	cp	(hl)
	jr	z,ct65
	push	bc
	ld	b,a
	xor	(hl)
	ld	c,a
	ld	a,(tbits)
	or	c
	ld	(tbits),a
	ld	c,(hl)
	call	addhit
	pop	bc
ct65:	call	offinc
	inc	hl
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,ct6
	ld	bc,(pn)
	call	adv
	jr	ct4
ct7:	ld	hl,tpat
	inc	(hl)
	ld	a,(hl)
	cp	NTPAT
	jr	nz,ct1
	call	mnorm
	ld	hl,HITS
	ld	a,(hn)
	or	a
	jr	z,ct9
	ld	b,a
ct8:	push	bc
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	push	hl
	ld	hl,refc
	call	hitref
	call	pref
	call	print
	db	" wrote ",0
	pop	hl
	ld	a,(hl)
	inc	hl
	call	ph2
	call	print
	db	" read ",0
	ld	a,(hl)
	inc	hl
	call	ph2
	call	crlf
	pop	bc
	djnz	ct8
ct9:	ld	hl,(hcount)
	call	pdec16
	call	print
	db	" errors in 5 patterns, bad bits ",0
	ld	a,(tbits)
	call	pbin8
	call	crlf
	jp	cmd

; Back to the start of the range for the next pass
trest:	ld	hl,refc
	ld	de,refa
	ld	bc,3
	ldir
	ld	hl,(tlen)
	ld	(rlen),hl
	ld	ix,refa
	ret

; BUF2 = pn bytes of this pattern for the address at IX
tmake:	ld	a,(tpat)
	cp	NTPAT-1
	jr	z,tm2
	ld	e,a
	ld	d,0
	ld	hl,tptab
	add	hl,de
	ld	a,(hl)
	ld	hl,BUF2
	ld	bc,(pn)
tm1:	ld	(hl),a
	inc	hl
	dec	bc
	ld	e,a
	ld	a,b
	or	c
	ld	a,e
	jr	nz,tm1
	ret
tm2:	ld	e,(ix+1)		; low xor high byte of the address
	ld	d,(ix+2)
	ld	hl,BUF2
	ld	bc,(pn)
tm3:	ld	a,e
	xor	d
	ld	(hl),a
	inc	hl
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,tm3
	ret

; G addr, or G alone for the start an S-record file gave. A RET comes
; back to the monitor.
cG:	call	atend
	jr	z,cg1
	call	getaddr
	call	endl
	ld	a,(ix+0)
	ld	(gochunk),a
	ld	l,(ix+1)
	ld	h,(ix+2)
	ld	(goaddr),hl
	jr	cg2
cg1:	ld	a,(gohas)
	or	a
	jr	nz,cg2
	call	eprint
	db	"No start address yet.",0
cg2:	ld	a,(gochunk)
	inc	a
	jr	z,cg3
	call	eprint
	db	"A chunk address cannot run: give a Z80 address.",0
cg3:	ld	sp,STACK
	ld	hl,cg4
	push	hl
	ld	hl,(goaddr)
	jp	(hl)
cg4:	di
	call	eprint
	db	"Back in the monitor.",0

; I port
cI:	call	getbyte
	push	af
	call	endl
	pop	af
	ld	c,a
	ld	b,0
	in	e,(c)
	push	de
	push	bc
	call	print
	db	"Port ",0
	pop	bc
	ld	a,c
	call	phex8
	call	print
	db	" reads ",0
	pop	de
	ld	a,e
	call	phex8
	call	crlf
	jp	cmd

; O port byte
cO:	call	getbyte
	push	af
	call	getbyte
	push	af
	call	endl
	pop	af
	pop	bc
	ld	c,b
	ld	b,0
	out	(c),a
	jp	cmd

; RUN chunk: a quick check of the places the monitor needs, then the
; program and 7000h-7FFFh, the stack in it, to the same place in the
; chunk, which then goes in the low half. The other half gets A1, or A2
; if the chunk is A1.
PROGSZ	equ	PROG_END-1000h

cR:	ld	hl,(lp)
	ld	a,(hl)
	cp	'U'
	jp	nz,ewhat
	inc	hl
	ld	a,(hl)
	cp	'N'
	jp	nz,ewhat
	inc	hl
	ld	(lp),hl
	call	skip
	call	chname
	jp	c,ewhat
	ld	(lp),hl
	ld	(rtgt),a
	call	chkch
	call	endl
	ld	a,(rtgt)
	ld	hl,lowch
	cp	(hl)
	jr	nz,cr3
	call	eprint
	db	"It is running there.",0
cr3:	call	mapc
	ld	hl,9000h
	ld	bc,PROGSZ
	call	qcheck
	ld	hl,0F000h
	ld	bc,1000h
	call	qcheck
	ld	hl,1000h
	ld	de,9000h
	ld	bc,PROGSZ
	ldir
	ld	hl,7000h
	ld	de,0F000h
	ld	bc,1000h
	ldir
	ld	hl,1000h
	ld	de,9000h
	ld	bc,PROGSZ
cr4:	ld	a,(de)
	cp	(hl)
	jr	nz,cr8
	inc	hl
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,cr4
	ld	a,(rtgt)
	ld	d,a
	or	a
	ld	a,40h
	jr	z,cr5
	ld	a,d
	add	a,a
	add	a,a
	add	a,a
	add	a,a
cr5:	ld	(B_PIODA),a		; from here on this is the copy
	ld	(pionow),a
	ld	a,d
	ld	(lowch),a
	call	mnorm
	call	print
	db	"Now running in ",0
	ld	a,(lowch)
	call	pchn
	call	crlf
	jp	cmd
cr8:	ex	de,hl
cr9:	res	7,h
	ld	(rtmp+1),hl
	ld	a,(rtgt)
	ld	(rtmp),a
	call	mnorm
	ld	ix,rtmp
	call	pref
	call	eprint
	db	" failed, so RUN stopped.",0

; 55h and AAh through BC bytes at HL, a byte at a time
qcheck:	ld	(hl),55h
	ld	a,(hl)
	cp	55h
	jr	nz,cr9
	ld	(hl),0AAh
	ld	a,(hl)
	cp	0AAh
	jr	nz,cr9
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,qcheck
	ret

cHelp:	call	endl
	ld	hl,helptx
	call	puts
	jp	cmd

helptx:	db	"Numbers in hex. An address is 1234 through the map as it stands, or A1:",0Dh,0Ah
	db	"A2: B1: B2: and an offset to 7FFF. ESC or BREAK stops a long command.",0Dh,0Ah
	db	"D addr [len]      Dump, a screen at a time. D alone goes on",0Dh,0Ah
	db	"E addr            Edit: hex and Enter writes, Enter next, dot ends",0Dh,0Ah
	db	"F addr len byte   Fill",0Dh,0Ah
	db	"M from to len     Move",0Dh,0Ah
	db	"S addr len bytes  Search for hex bytes or a ",22h,"string",22h,0Dh,0Ah
	db	"C addr addr len   Compare",0Dh,0Ah
	db	"K addr len        Checksum: 8-bit sum, CRC-16",0Dh,0Ah
	db	"G [addr]          Go, a RET comes back",0Dh,0Ah
	db	"L                 Load S-records from channel A",0Dh,0Ah
	db	"P addr len        Punch S-records to channel A",0Dh,0Ah
	db	"T addr len        Test: 5 patterns, bad bits and addresses",0Dh,0Ah
	db	"I port            Read a port",0Dh,0Ah
	db	"O port byte       Write a port",0Dh,0Ah
	db	"RUN chunk         Move the monitor there, so A1 can be tested",0Dh,0Ah
	db	"The console writes to the block, and that lands in A1, so A1 offsets",0Dh,0Ah
	db	"0400-0BFF and 7400-7BFF may be disturbed between commands.",0Dh,0Ah,0
