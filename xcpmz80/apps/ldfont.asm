; LDFONT: load a font file into the MAX-80's font RAM.
;
;	LDFONT name	reads name.FNT, or name with its own type
;
; The file is font RAM as it is laid out, the form tools/mkfont.py
; writes: 1K for characters 00h-7Fh, font RAM 1, or 2K for those and
; font RAM 2, 80h-BFh. 7Fh is the cursor's shape. The new font shows at once and stays until
; the next cold start, which loads the system's own font again.

BDOS	equ	5
FCB	equ	5Ch
BLK	equ	0F000h			; the I/O block under xcpmz80
WINDOW	equ	BLK			; SWAP1K, 1K, VLATCH bits 2-0
VLATCH	equ	BLK+7DCh		; a read gives its RAM copy
FONT1	equ	4			; the window on font RAM 1
FONT2	equ	6			; and 2

	org	100h
	ld	a,(FCB+1)		; a name?
	cp	' '
	ld	de,m_use
	jr	z,msg
	ld	a,(FCB+9)		; no type: .FNT
	cp	' '
	jr	nz,lf_1
	ld	hl,s_fnt
	ld	de,FCB+9
	ld	bc,3
	ldir
lf_1:	xor	a
	ld	(FCB+32),a
	ld	de,FCB
	ld	c,15			; open
	call	BDOS
	inc	a
	ld	de,m_none
	jr	z,msg
	ld	de,buf			; read it all, 17 records at most
	ld	b,0
lf_2:	push	bc
	push	de
	ld	c,26			; DMA
	call	BDOS
	ld	de,FCB
	ld	c,20			; read
	call	BDOS
	pop	de
	pop	bc
	or	a
	jr	nz,lf_3
	inc	b
	ld	a,b
	cp	17
	jr	z,lf_bad
	ld	hl,128
	add	hl,de
	ex	de,hl
	jr	lf_2
lf_3:	ld	a,b			; 8 records or 16
	cp	8
	jr	z,lf_4
	cp	16
	jr	nz,lf_bad
lf_4:	di
	ld	a,(VLATCH)		; as it is now, 40 columns kept
	ld	c,a
	ld	hl,buf
	ld	a,FONT1
	call	copy
	ld	a,b
	cp	16
	ld	a,FONT2
	call	z,copy
	ld	a,c			; the window back
	ld	(VLATCH),a
	ei
	ld	de,m_done
msg:	ld	c,9
	jp	BDOS
lf_bad:	ld	de,m_bad
	jr	msg

; Window A on font RAM, keeping the rest of VLATCH (C), and the next 1K
; at HL into it
copy:	push	bc
	ld	b,a
	ld	a,c
	and	0F8h
	or	b
	ld	(VLATCH),a
	ld	de,WINDOW
	ld	bc,400h
	ldir
	pop	bc
	ret

s_fnt:	db	"FNT"
m_use:	db	"LDFONT name loads a font file, 1K for characters 00h-7Fh "
	db	"or 2K for 00h-BFh,",0Dh,0Ah
	db	"type .FNT if none is given",0Dh,0Ah,"$"
m_none:	db	"No file",0Dh,0Ah,"$"
m_bad:	db	"Not a font: 1K or 2K",0Dh,0Ah,"$"
m_done:	db	"Font loaded",0Dh,0Ah,"$"

buf:					; 2K and one record
