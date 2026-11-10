; The keys, read straight from the matrix once a frame. Five row reads. A, S and D work as
; LEFT, DOWN and RIGHT, Q as Z and E as UP.

; Bits in held and press
K_LEFT	equ	0		; LEFT or A
K_RIGHT	equ	1		; RIGHT or D
K_DOWN	equ	2		; DOWN or S
K_ROTA	equ	3		; UP or E, the GB's A, clockwise
K_ROTB	equ	4		; Z or Q, the GB's B, counterclockwise
K_PAUSE	equ	5		; ENTER, the GB's START
K_NEXT	equ	6		; SPACE, the GB's SELECT
K_QUIT	equ	7		; BREAK, and ESC outside play

; held: the keys down now. press: down now and not last frame.
keys:	ld	e,0
	ld	a,(KEYS+40h)	; row 6: ENTER CLEAR BREAK UP DOWN LEFT RIGHT SPACE
	ld	c,a
	bit	5,c
	jr	z,ky_1
	set	K_LEFT,e
ky_1:	bit	6,c
	jr	z,ky_2
	set	K_RIGHT,e
ky_2:	bit	4,c
	jr	z,ky_3
	set	K_DOWN,e
ky_3:	bit	3,c
	jr	z,ky_4
	set	K_ROTA,e
ky_4:	bit	0,c
	jr	z,ky_4a
	set	K_PAUSE,e
ky_4a:	bit	2,c
	jr	z,ky_5
	set	K_QUIT,e
ky_5:	bit	7,c
	jr	z,ky_6
	set	K_NEXT,e
ky_6:	ld	a,(KEYS+08h)	; row 3: Z at bit 2
	bit	2,a
	jr	z,ky_7
	set	K_ROTB,e
ky_7:	ld	a,(KEYS+80h)	; row 7: ESC at bit 5, in play as ENTER, the
	bit	5,a		; pause, else as BREAK
	jr	z,ky_9
	ld	a,(state)
	cp	S_OVER
	jr	nc,ky_7a
	set	K_PAUSE,e
	jr	ky_9
ky_7a:	set	K_QUIT,e
ky_9:	ld	a,(KEYS+01h)	; row 0: A at bit 1, D at 4, E at 5
	ld	c,a
	bit	1,c
	jr	z,ky_10
	set	K_LEFT,e
ky_10:	bit	4,c
	jr	z,ky_11
	set	K_RIGHT,e
ky_11:	bit	5,c
	jr	z,ky_12
	set	K_ROTA,e
ky_12:	ld	a,(KEYS+04h)	; row 2: Q at bit 1, S at 3
	ld	c,a
	bit	1,c
	jr	z,ky_13
	set	K_ROTB,e
ky_13:	bit	3,c
	jr	z,ky_8
	set	K_DOWN,e
ky_8:	ld	a,(held)
	cpl
	and	e
	ld	(press),a
	ld	a,e
	ld	(held),a
	ret
