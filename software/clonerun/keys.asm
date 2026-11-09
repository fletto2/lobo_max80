; The keys, read straight from the matrix once a frame.

; Bits in held and press, the keys of play
K_RIGHT	equ	0		; RIGHT
K_LEFT	equ	1		; LEFT
K_UP	equ	2		; UP
K_DOWN	equ	3		; DOWN
K_DIGL	equ	4		; Z, ENTER or SHIFT, dig left
K_DIGR	equ	5		; X, ^ (~) or _ (DEL), dig right
K_ENTER	equ	6		; ENTER, play the level shown
K_ESC	equ	7		; ESC

; Bits in vheld and vpress, the viewer's keys
K_N	equ	0		; N, the next level
K_P	equ	1		; P, the level before, in play pause
K_F1	equ	2		; F1, in play give up a life
K_S	equ	3		; S, on the title the stages

KR	equ	1<<K_RIGHT
KL	equ	1<<K_LEFT
KU	equ	1<<K_UP
KD	equ	1<<K_DOWN
KZ	equ	1<<K_DIGL
KX	equ	1<<K_DIGR

; held: the keys down now. press: down now and not last frame. The same
; for the viewer's keys in vheld and vpress.
keys:	ld	e,0
	ld	d,0
	ld	a,(KEYS+40h)	; row 6: ENTER CLEAR BREAK UP DOWN LEFT RIGHT SPACE
	ld	c,a
	bit	6,c
	jr	z,ky_1
	set	K_RIGHT,e
ky_1:	bit	5,c
	jr	z,ky_2
	set	K_LEFT,e
ky_2:	bit	3,c
	jr	z,ky_3
	set	K_UP,e
ky_3:	bit	4,c
	jr	z,ky_4
	set	K_DOWN,e
ky_4:	bit	1,c		; CLEAR is DOWN too
	jr	z,ky_4a
	set	K_DOWN,e
ky_4a:	bit	0,c
	jr	nz,ky_4b
	ld	a,1		; ENTER up: from now on it digs
	ld	(entfree),a
	jr	ky_5
ky_4b:	set	K_ENTER,e
	ld	a,(entfree)	; not the ENTER that started the stage
	or	a
	jr	z,ky_5
	set	K_DIGL,e
ky_5:	ld	a,(KEYS+08h)	; row 3: X at bit 0, Z at bit 2, ^ and _ on top
	ld	c,a
	bit	2,c
	jr	z,ky_5a
	set	K_DIGL,e
ky_5a:	and	0C1h
	jr	z,ky_5b
	set	K_DIGR,e
ky_5b:	ld	a,(KEYS+02h)	; row 1: N at bit 6
	bit	6,a
	jr	z,ky_6
	set	K_N,d
ky_6:	ld	a,(KEYS+04h)	; row 2: P at bit 0, S at bit 3
	bit	0,a
	jr	z,ky_6a
	set	K_P,d
ky_6a:	bit	3,a
	jr	z,ky_7
	set	K_S,d
ky_7:	ld	a,(KEYS+80h)	; row 7: SHIFT at bit 0, either one, F1 at 1, ESC at 5
	ld	c,a
	bit	0,c
	jr	z,ky_7s
	set	K_DIGL,e
	ld	a,(KEYS+40h)	; SHIFT and ENTER, both digs: with LEFT or CLEAR
	rrca			; the matrix may show ESC or F1, not pressed
	jr	c,ky_8
ky_7s:	ld	a,c
	bit	1,a
	jr	z,ky_7a
	set	K_F1,d
ky_7a:	bit	5,a
	jr	z,ky_8
	set	K_ESC,e
ky_8:	ld	a,(held)
	cpl
	and	e
	ld	(press),a
	ld	a,e
	ld	(held),a
	ld	hl,tapped	; down at all since the last round
	or	(hl)
	ld	(hl),a
	ld	a,(vheld)
	cpl
	and	d
	ld	(vpress),a
	ld	a,d
	ld	(vheld),a
	ret
