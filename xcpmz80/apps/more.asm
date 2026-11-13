; MORE: show a text file a screen at a time.
;
;	MORE NAME.EXT
;
; After 23 lines it waits at --More--: Space shows the next screen,
; Enter the next line, Q or ^C stops. A line longer than 80 columns
; counts as two, a tab goes to the next column of 8, the file ends at
; ^Z or its last record. Bit 7 is dropped, as the console does, and
; other control characters show as ^L and so on, two columns, so the
; count of lines is the screen's. Only BDOS calls, so it runs under any
; CP/M.

BDOS	equ	5
FCB	equ	5Ch
DMA	equ	80h
ROWS	equ	23			; lines a screen, the prompt the 24th
COLS	equ	80

	org	100h
	ld	sp,stack
	ld	a,(FCB+1)
	cp	' '
	ld	de,m_use
	jr	z,quit
	xor	a
	ld	(FCB+12),a		; EX
	ld	(FCB+32),a		; CR
	ld	de,FCB
	ld	c,15
	call	BDOS
	inc	a
	ld	de,m_none
	jr	z,quit
mo_rec:	ld	de,DMA
	ld	c,26
	call	BDOS
	ld	de,FCB
	ld	c,20
	call	BDOS
	or	a
	jp	nz,0			; the end
	ld	hl,DMA
mo_ch:	ld	a,(hl)
	cp	1Ah
	jp	z,0
	push	hl
	call	show
	pop	hl
	inc	l			; DMA is 80h-FFh
	jr	nz,mo_ch
	jr	mo_rec

quit:	ld	c,9
	call	BDOS
	jp	0

; A character to the screen, counting columns and lines
show:	and	7Fh			; bit 7 off, as the console
	cp	9
	jr	z,sh_tab
	cp	13
	jr	z,sh_cr
	cp	10
	jr	z,sh_lf
	cp	' '
	jr	c,sh_ctl		; other controls as ^X, counted
	cp	7Fh
	jr	z,sh_ctl
	call	out
	ld	hl,col
	inc	(hl)
	ld	a,(hl)
	cp	COLS
	ret	c
	ld	(hl),0			; the screen wrapped
	jr	newln
sh_ctl:	push	af
	ld	a,'^'
	call	show
	pop	af
	xor	40h			; 0Ch: L, 7Fh: ?
	jr	show
sh_tab:	ld	a,' '
	call	show
	ld	a,(col)
	and	7
	jr	nz,sh_tab
	ret
sh_cr:	xor	a
	ld	(col),a
	ld	a,13
	jr	out
sh_lf:	ld	a,10			; down a row, the column kept, as
	call	out			; the console does
newln:	ld	hl,line
	inc	(hl)
	ld	a,(hl)
	cp	ROWS
	ret	c
	; a screen full: wait
mo_pr:	ld	de,m_more
	ld	c,9
	call	BDOS
mo_key:	ld	c,1			; not 6: DRI's BDOS 2.2 keeps a key
	call	BDOS			; typed while the screen filled in
					; a buffer that only 1 reads.
					; Its echo goes with the prompt.
	cp	' '
	ld	b,0			; a new screen
	jr	z,mo_go
	cp	13
	ld	b,ROWS-1		; one more line
	jr	z,mo_go
	cp	3
	jr	z,mo_q
	and	5Fh
	cp	'Q'
	jr	z,mo_q
	ld	de,m_wipe		; another key: its echo off, and the
	ld	c,9			; prompt again
	call	BDOS
	jr	mo_pr
mo_q:	ld	de,m_wipe		; Q or ^C: the prompt off, and out
	ld	c,9
	call	BDOS
	jp	0
mo_go:	ld	a,b
	ld	(line),a
	ld	de,m_wipe
	ld	c,9
	jp	BDOS

out:	ld	e,a
	ld	c,2
	jp	BDOS

m_use:	db	"MORE NAME.EXT: show a file a screen at a time",13,10,"$"
m_none:	db	"MORE: no such file",13,10,"$"
m_more:	db	"--More--$"
m_wipe:	db	13,"                ",13,"$"	; the prompt and the key it
					; echoed, a tab too
col:	db	0
line:	db	0
	ds	64
stack:
