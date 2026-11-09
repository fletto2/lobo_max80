; The screen: the start, the vertical blank, 8-line rows, and copying
; into font RAM and video RAM. findstart, waitvb, linein, lineout,
; crtset, crtw and dwait.
;
; Nothing here writes font RAM or video RAM while the picture shows.
; vbcopy and drawsome do
; their copying in the vertical blank, a part a frame.

; Finds the screen start from the BIOS cursor, the one 7Fh in video RAM
; after 1Eh and ESC Y. Carry set when there is not exactly one.
findstart:
	ld	b,0		; hits, stops at 2
	ld	hl,VIDLO
fs_1:	ld	a,(hl)
	cp	CURSOR
	call	z,fs_hit
	inc	hl
	ld	a,h
	or	l
	jr	nz,fs_1		; to FFFFh
	di
	ld	a,(VLATCH)
	ld	c,a
	and	0F8h
	or	W_VIDEO
	ld	(VLATCH),a
	ld	hl,WINDOW
fs_2:	ld	a,(hl)
	cp	CURSOR
	call	z,fs_hit
	inc	hl
	ld	a,h
	cp	0F4h		; to F3FFh
	jr	nz,fs_2
	ld	a,c
	ld	(VLATCH),a
	ei
	ld	a,b
	cp	1
	scf
	ret	nz
	or	a
	ret

; HL a CPU address in video RAM: count it and keep its ring address
fs_hit:	ld	a,b
	cp	2
	ret	z
	inc	b
	push	hl
	ld	de,0400h	; FC00h-FFFFh to 000h-3FFh, F000h-F3FFh to 400h-7FFh
	add	hl,de
	ld	a,h
	and	07h
	ld	h,a
	ld	(vstart),hl
	pop	hl
	ret

; Waits for the start of the next vertical blank: the picture, then
; SYSFLG bit 6 off for longer than a line. Returns with interrupts off.
; The test build counts the passes through the picture into idle, 37
; T-states each. The frame's work starts with the picture (testvb), so
; already in the vertical blank here means the work ran over the
; picture, and idle is 0.
waitvb:	di
	ld	hl,SYSFLG
	ifdef	TEST
	push	de
	ld	de,0
	ld	b,OFFRUN
wv_0:	bit	6,(hl)
	jr	nz,wv_2
	djnz	wv_0
	ld	de,8000h	; ran over: bit 15 says so
	endif
wv_1:	bit	6,(hl)
	jr	z,wv_1
wv_2:
	ifdef	TEST
	inc	de
	endif
	ld	b,OFFRUN
wv_3:	bit	6,(hl)
	jr	nz,wv_2
	djnz	wv_3
	ifdef	TEST
	bit	7,d
	jr	z,wv_4
	ld	de,0
wv_4:	ld	(idle),de
	pop	de
	endif
	ret

; Puts the window back on video RAM 400h-7FFh
vidwin:	ld	a,(VLATCH)
	and	0F8h
	or	W_VIDEO
	ld	(VLATCH),a
	ret

; Into 8-line rows. This
; BIOS frame gets R5 = 22, so it is 274 lines with its sync still at line
; 234, and the sync of the first 8-line frame, at line 224, comes 264
; lines on.
linein:	call	waitvb
	ld	a,5
	ld	c,22
	call	crtw
	call	dwait
	ld	hl,crt8
	jr	crtset

; Back to the BIOS's 9-line rows. This 8-line frame gets R4 = 30 and
; R5 = 6, so it is 254 lines with its sync still at line 224, and the
; BIOS frame's sync at line 234 comes 264 lines on.
lineout:
	call	waitvb
	ld	a,4
	ld	c,30
	call	crtw
	ld	a,5
	ld	c,6
	call	crtw
	call	dwait
	ld	hl,crt9

; HL register and value pairs ending in FFh, written. Interrupts back on.
crtset:	ld	a,(hl)
	cp	0FFh
	jr	z,ct_1
	inc	hl
	ld	c,(hl)
	inc	hl
	call	crtw
	jr	crtset
ct_1:	ei
	ret

; R9, R4, R7, R5 for 8-line rows, 33 rows of 8, and the BIOS's
crt8:	db	9,7, 4,32, 7,28, 5,0, 0FFh
crt9:	db	9,8, 4,27, 7,26, 5,12, 0FFh

; CRTC register A = C
crtw:	ld	(CRTREG),a
	ld	a,c
	ld	(CRTBYT),a
	ret

; Waits for the picture's first line
dwait:	ld	hl,SYSFLG
dw_1:	bit	6,(hl)
	jr	z,dw_1
	ret

; HL from, DE to, BC bytes, A the window (W_FONT1 or W_FONT2) the copy
; reads or writes through: copied 256 bytes a vertical blank, with
; interrupts off, the window put back on video RAM after each part.
vbcopy:	ld	(vc_win),a
vc_1:	ld	a,b
	or	c
	ret	z
	push	hl
	push	bc
	call	waitvb
	pop	bc
	ld	a,(VLATCH)
	and	0F8h
	ld	l,a
	ld	a,(vc_win)
	or	l
	ld	(VLATCH),a
	pop	hl
	ld	(vc_left),bc
	ld	a,b
	or	a
	jr	z,vc_2		; under 256 left: all of it
	ld	bc,100h
vc_2:	ldir
	ld	bc,(vc_left)	; less this part
	ld	a,b
	or	a
	jr	z,vc_3
	dec	b
	jr	vc_4
vc_3:	ld	c,a
vc_4:	ld	a,(VLATCH)
	and	0F8h
	or	W_VIDEO
	ld	(VLATCH),a
	ei
	jr	vc_1

; Call in the vertical blank: copies the next ROWPART rows of scrbuf
; into video RAM, from row (drawrow), until all 24 are done
ROWPART	equ	6
drawsome:
	call	vidwin
	ld	b,ROWPART
ds_1:	ld	a,(drawrow)
	cp	ROWS
	ret	nc
	push	bc
	call	onerow
	ld	hl,drawrow
	inc	(hl)
	pop	bc
	djnz	ds_1
	ret

; Copies row A of scrbuf into video RAM. The window must show video RAM.
onerow:	ld	l,a		; HL = the row x 80
	ld	h,0
	add	hl,hl
	ld	de,rowoff
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	push	de
	ld	hl,(vstart)	; its CPU address in video RAM
	add	hl,de
	call	vaddr
	ex	de,hl
	pop	hl
	ld	bc,scrbuf
	add	hl,bc
	jp	rowcopy

; B row, C column: HL the cell's CPU address in video RAM. Keeps BC, DE.
vcell:	push	de
	ld	l,b
	ld	h,0
	add	hl,hl
	ld	de,rowoff
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,(vstart)
	add	hl,de
	ld	e,c
	ld	d,0
	add	hl,de
	pop	de

; HL a place in the 2K ring of video RAM, any high bits: its CPU address,
; 000h-3FFh at FC00h and 400h-7FFh at F000h through the window.
vaddr:	ld	a,h
	and	07h
	add	a,0Ch
	and	0Fh
	or	0F0h
	ld	h,a
	ret

; HL from, DE the CPU address in video RAM: one row, 80 bytes, split
; where it runs off the end of FC00h-FFFFh or of F000h-F3FFh
rowcopy:
	push	hl
	ld	hl,0		; the end of FC00h-FFFFh
	ld	a,d
	cp	0FCh
	jr	nc,rc_1
	ld	hl,0F400h	; the end of F000h-F3FFh
rc_1:	or	a
	sbc	hl,de		; bytes to the end
	ld	bc,COLS
	or	a
	sbc	hl,bc
	jr	nc,rc_3		; the row fits
	add	hl,bc
	ld	a,l		; under 80
	pop	hl
	ld	c,a
	ld	b,0
	push	af
	ldir
	ld	a,d		; on to the other part of the ring
	cp	0F4h
	ld	d,0FCh
	jr	z,rc_2
	ld	d,0F0h
rc_2:	pop	af
	neg
	add	a,COLS
	ld	c,a
	ldir
	ret
rc_3:	pop	hl
	ldir
	ret

; The offset of each row in video RAM and in scrbuf
rowoff:
.r = 0
	dup	ROWS
	dw	.r*COLS
.r = .r+1
	edup
