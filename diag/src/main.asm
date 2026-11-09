; Start, the menu and run all

main:	di
	ld	sp,STACK
	ld	hl,VARS
	ld	de,VARS+1
	ld	bc,VARSZ-1
	ld	(hl),0
	ldir
	ld	a,(MLCOPY)		; the boot ROM's MLATCH, still in A1
	ld	(bootml),a
	ld	a,high BLK
	ld	(blkhi),a
	ld	a,1
	ld	(stride),a
	ld	(scrout),a
	ld	(sioon),a
	call	sioinit
	call	crtinit
	call	fontload
	call	blk0			; how much RAM, for the menu
	call	findb
	call	blkf

menu:	call	drawmenu
mloop:	call	dmfoot
	ld	hl,13
	call	at
	call	print
	db	"Select item to run: ",0
	ld	hl,sioon		; the cursor box on the screen only
	ld	b,(hl)
	ld	(hl),0
	ld	a,G_SOLID
	call	putc
	ld	(hl),b
	call	waitkey
	ld	hl,cmds
mfind:	ld	c,a
	ld	a,(hl)
	or	a
	jr	z,mloop			; not a choice
	cp	c
	ld	a,c
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	jr	nz,mfind
	ld	hl,20*256+13		; the cursor box off while the item runs
	call	at
	ld	a,' '
	call	putc
	ex	de,hl
	call	jphl
	ld	a,(ovrun)		; results over the footer: kept until a key
	or	a
	jr	z,mdone
	ld	hl,rclip		; row 23 taking text again
	ld	a,(hl)
	ld	(hl),0
	push	af
	ld	hl,23
	call	at
	call	clreol
	pop	af
	or	a
	jr	z,mlp1
	call	pmore
	ld	a,' '
	call	putc
mlp1:	call	print
	db	TH,"Any key for the menu.",TK,0
	call	waitkey
	call	rclear
mdone:	xor	a
	ld	(rmode),a
	ld	(ovrun),a
	jp	mloop

jphl:	jp	(hl)

cmds:	db	'1'
	dw	cvram
	db	'2'
	dw	cfram
	db	'3'
	dw	scr80
	db	'4'
	dw	scr40
	db	'5'
	dw	cchars
	db	'6'
	dw	cmain
	db	'7'
	dw	kbtest
	db	'A'
	dw	runall
	db	'8'
	dw	beeper
	db	'9'
	dw	sptest
	db	'B'
	dw	pptest
	db	'C'
	dw	bxtest
	db	'D'
	dw	rttest
	db	'E'
	dw	dptest
	db	'F'
	dw	dktest
	db	'G'
	dw	vttest
	db	'H'
	dw	notyet
; items I and J off the menu: write-through and memory timing were for
; validating the emulator, not machine diagnostics
;	db	'I'
;	dw	wttest
;	db	'J'
;	dw	mttest
	db	0

drawmenu:
	ld	a,0Ch
	call	putc
	call	print
	db	"MAX-80 DIAGNOSTIC",0
	ld	hl,2
	call	at
	call	print
	db	" 1  ",TH,"Video RAM test (D16)",TK,0Dh,0Ah
	db	" 2  ",TH,"Font RAM test (E21)",TK,0Dh,0Ah
	db	" 3  ",TH,"Test screens, 80 columns",TK,0Dh,0Ah
	db	" 4  ",TH,"Test screens, 40 columns",TK,0Dh,0Ah
	db	" 5  ",TH,"Character set",TK,0Dh,0Ah
	db	" 6  ",TH,"Main RAM test, all 128K, and banking",TK,0Dh,0Ah
	db	" 7  ",TH,"Keyboard test",TK,0Dh,0Ah
	db	" 8  ",TH,"Beeper",TK,0Dh,0Ah,0Ah
	db	" A  ",TH,"Run all RAM tests until a key is pressed",TK,0
	ld	hl,46*256+2		; the second column, rows 2-11
	ld	de,mcol2
dm2:	call	at
	ex	de,hl
	call	puts
	ex	de,hl
	inc	l
	ld	a,(de)
	or	a
	jr	nz,dm2
	ret

mcol2:	db	"9  ",TH,"Serial ports",TK,0
	db	"B  ",TH,"Printer port",TK,0
	db	"C  ",TH,"Expansion bus",TK,0
	db	"D  ",TH,"Clock chip",TK,0
	db	"E  ",TH,"DIP switches",TK,0
	db	"F  ",TH,"Disk drives",TK,0
	db	"G  ",TH,"Video timing",TK,0
	db	"H  ",TH,"Winchester interface",TK,0
;	db	"I  ",TH,"Write-through to RAM",TK,0
;	db	"J  ",TH,"Memory timing",TK,0
	db	0

; The RAM, boot device and serial port on rows 21-23, drawn again on
; each turn of the menu in case a long report ran over them
dmfoot:	ld	hl,21
	call	at
	call	clreol
	call	print
	db	TH,"Detected RAM: ",TK,0
	ld	a,(nchunk)		; 32K each
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	ld	l,a
	ld	h,0
	call	pdec16
	ld	a,'K'
	call	putc
	ld	hl,22
	call	at
	call	clreol
	call	print
	db	TH,"Boot device: ",TK,0
	ld	a,(bootml)
	and	20h
	jr	z,df1
	call	print
	db	"8",22h," floppy drive",0
	jr	df2
df1:	call	print
	db	"5.25",22h," floppy drive",0
df2:	ld	hl,23
	call	at
	call	clreol
	call	print
	db	TH,"Serial port A 9600-8N1 mirrors screen output.",TK,0
	ret

; Clear the results area, rows 15-20, and rows 21-23 too once results
; have run over them, and put the cursor at row 15. The area takes a
; page at a time unless run all has set it to cut.
rclear:	ld	a,(rmode)
	or	a
	jr	nz,rcl0
	inc	a
	ld	(rmode),a
rcl0:	xor	a
	ld	(rclip),a
	ld	l,20
	ld	a,(ovrun)
	or	a
	jr	z,rcl1
	ld	l,23
rcl1:	ld	h,0
	call	at
	call	clreol
	dec	l
	ld	a,l
	cp	14
	jr	nz,rcl1
	ld	hl,15
	jp	at

; A menu item with no test written
notyet:	call	rclear
	call	print
	db	"This test is not written.",0
	ret

; Each key beeps, ESC goes back. Any write to BEEP beeps.
beeper:	call	rclear
	call	print
	db	"BEEPER",0Dh,0Ah
	db	TH,"Each key beeps, about 2 kHz for 1/15 second. ",TK,"ESC",TH," goes back.",TK,0
bp1:	call	waitkey
	cp	1Bh
	jp	z,rclear
	ld	(BEEP),a
	jr	bp1

cvram:	call	rclear
	call	tvram
	jp	vreport

cfram:	call	rclear
	call	tfram
	jp	freport

cmain:	call	rclear
	jp	tmain

; Run the RAM tests over and over, until a key, counting the passes.
; Row 15 keeps the count, the results go below it.
runall:	ld	hl,0
	ld	(passes),hl
	ld	(fails),hl
	ld	(vfails),hl
	ld	(ffails),hl
	ld	(mmfails),hl
	ld	a,2			; no waiting for a key mid pass
	ld	(rmode),a
ra1:	call	rclear
	call	racount
	xor	a
	ld	(rabad),a
	call	tvram
	push	af
	call	vreport
	pop	af
	ld	hl,vfails
	call	rafail
	call	tfram
	push	af
	call	freport
	pop	af
	ld	hl,ffails
	call	rafail
	call	tmain
	ld	hl,mmfails
	call	rafail
	ld	a,(rabad)
	or	a
	ld	hl,fails
	call	nz,inc16
	ld	hl,passes
	call	inc16
	call	racount
	ld	b,30			; half a second for a key
	call	pause
	or	a
	jp	z,ra1
	ret

; A nonzero: a failure, counted in the word at HL and in this pass
rafail:	or	a
	ret	z
	ld	(rabad),a
	jp	inc16

; The counts on row 15, then the cursor to row 16
racount:
	ld	hl,15
	call	at
	call	print
	db	TH,"Pass ",TK,0
	ld	hl,(passes)
	call	pdec16
	call	print
	db	TH,", failed ",TK,0
	ld	hl,(fails)
	call	pdec16
	call	print
	db	TH,": video RAM ",TK,0
	ld	hl,(vfails)
	call	pdec16
	call	print
	db	TH,", font RAM ",TK,0
	ld	hl,(ffails)
	call	pdec16
	call	print
	db	TH,", main RAM ",TK,0
	ld	hl,(mmfails)
	call	pdec16
	call	print
	db	TH,". Hold a key to stop.",TK,0
	ld	hl,16
	jp	at

; Add 1 to the word at HL, stopping at FFFFh. Keeps AF.
inc16:	push	af
	inc	(hl)
	jr	nz,i16a
	inc	hl
	inc	(hl)
	jr	nz,i16b
	dec	(hl)			; it was FFFFh
	dec	hl
	dec	(hl)
	pop	af
	ret
i16b:	dec	hl
i16a:	pop	af
	ret

