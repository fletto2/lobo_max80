; TETRIS.COM: the Game Boy Tetris 1P A-type game for the Lobo MAX-80
; under CP/M 2.2 or xcpmz80. Our own Z80 code. The game's numbers come
; from your own copy of the cartridge, lifted by port/tools/build.py into
; tables.asm, which is never shared.
;
; The title, ENTER to go on, DOWN held for hard mode. The level select,
; the arrows and ENTER, Z back. In the game SPACE shows or
; hides NEXT, ENTER or ESC pauses, after GAME OVER ENTER goes back to
; the level select. BREAK quits, and ESC outside play.
;
; Built with TEST defined, for the emulator tests, it also shows a
; test pattern on rows 22 and 23: which page is on screen (PAGE 0 or
; PAGE 1), a frame count run through the change lists, and the presses
; of each key. Row 0 shows the engine's timings, the frames of the last
; spawn, drop and lock, the piece's row, the grace locks and the least
; idle time in any frame (testtick). It starts the game at once, unless
; MENU is defined. LEVEL n sets the start level, HARD hard mode,
; FIRST n the first piece's id and the ids in turn after it, not rolled, FILL n a test board (game.asm), PIECES n
; how many pieces before it stops, SCRIPT n a key script that stands in
; for the keyboard (script), SCORE n and LINES n the start score and
; lines. QUIET leaves out row 0 but the idle count
; and the frame count and key counts, to time the game's own work.
;
; sjasmplus --raw=TETRIS.COM tetris.asm

	include	"hw.inc"

	org	100h

start:	ld	(ccpsp),sp	; the CCP's stack stays as it is
	ld	sp,stack
	ld	de,m_home	; home and erase, the cursor at the start
	ld	c,9
	call	BDOS
	call	findstart
	jr	nc,st_1
	ld	de,m_nostart
	ld	c,9
	call	BDOS
	ld	sp,(ccpsp)
	ret
st_1:	ld	a,r		; the virtual DIV starts where the wait for us left R
	ld	(vdiv+1),a
	call	vidin
	ld	a,2
	ld	(wpage),a
	call	frame
	ifdef	TEST
	call	testpat
	endif
	ld	hl,list0
	ld	(curlst),hl
	ld	(curend),hl
	ld	hl,list1
	ld	(prevlst),hl
	ld	(prevend),hl
	ifdef	TEST
	ifndef	MENU
	call	newgame		; the test build plays at once
	else
	call	totitle
	endif
	else
	call	totitle
	endif
	call	render		; the first screen on the hidden page
	call	keys		; what is down already, ENTER from the CCP, is no press
	di
	call	setr2		; page 0, the shown one
	ei

main:	call	waitvb
	ld	a,(shown)	; show the page written last frame
	xor	1
	ld	(shown),a
	call	setr2
	ei
	call	keys
	ld	a,(press)
	bit	K_QUIT,a
	jr	nz,exit
	ifdef	TEST
	ld	hl,(frames)
	inc	hl
	ld	(frames),hl
	ifdef	SCRIPT
	call	script
	endif
	endif
	call	clock
	call	pausekeys
	ld	a,(wipe)
	or	a
	jr	z,mn_1
	call	wipestep
	jr	mn_2
mn_1:	ld	a,(paused)
	or	a
	call	z,tick
mn_2:
	ifdef	TEST
	call	testtick
	endif
	call	render
	jr	main

totitle:
	ld	a,S_TITLE
	ld	(state),a
	jp	drawtitle

; Blanks the screen, waits until no key has been down for 4 frames, so
; the BIOS has nothing held to repeat, puts the machine back, empties
; the console input and clears the screen for the CCP.
exit:	call	clrscr
	ld	c,4
ex_1:	push	bc
	call	waitvb
	ei
	pop	bc
	ld	a,(KEYS+0FFh)	; every row
	or	a
	jr	z,ex_2
	ld	c,5
ex_2:	dec	c
	jr	nz,ex_1
	call	vidout
ex_3:	ld	e,0FFh		; BDOS 6, input
	ld	c,6
	call	BDOS
	or	a
	jr	nz,ex_3
	ld	de,m_home
	ld	c,9
	call	BDOS
	ld	sp,(ccpsp)
	ret

; The static screen, on both pages: the background, the boxes, the board
; frame and the labels
frame:	ld	bc,0
fr_1:	push	bc
	call	bgcode
	call	putboth
	pop	bc
	inc	c
	ld	a,c
	cp	COLS/2
	jr	nz,fr_1
	ld	c,0
	inc	b
	ld	a,b
	cp	ROWS
	jr	nz,fr_1
	ld	ix,putboth
	ld	hl,boxes
fr_2:	ld	a,(hl)		; top row, left column, bottom row, right column, glyphs
	cp	0FFh
	jr	z,fr_3
	ld	b,a
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	push	hl
	call	boxdraw
	pop	hl
	jr	fr_2
fr_3:	ld	hl,labels
fr_4:	ld	b,(hl)		; row, column, text
	inc	hl
	ld	a,b
	or	a
	ret	z
	ld	c,(hl)
	inc	hl
	call	puts
	inc	hl
	jr	fr_4

boxes:	db	1,1,11,11,G_BOX		; score, lines and level
	db	1,28,8,35,G_BOX		; NEXT
	db	1,14,20,25,G_FRAME	; the board
	db	0FFh

labels:	db	2,30,"NEXT",0
	db	2,3,"SCORE",0
	db	5,3,"LINES",0
	db	8,3,"LEVEL",0
	db	0

	ifdef	TEST
; THE TEST BUILD'S PATTERN AND TIMINGS

; Each page names itself on the message line, and the bottom row names
; the keys whose presses it counts
testpat:
	xor	a
	ld	(wpage),a
	ld	bc,22*256+1
	ld	hl,m_page0
	call	puts
	ld	a,1
	ld	(wpage),a
	ld	bc,22*256+1
	ld	hl,m_page1
	call	puts
	ld	a,2
	ld	(wpage),a
	ld	bc,23*256+0
	ld	hl,m_keys
	call	puts
	ret

; A frame count in hex at row 22, columns 8-11, each key press
; counted, 0-9, under its name, and on row 0 in hex from column 1: the
; frames of the last spawn, drop and lock, the piece's board row, the
; grace locks, the fewest idle loops in waitvb, each at least 37
; T-states, and the frames from lock to spawn, last time and the last
; time lines cleared, the piece's column and code, drawn every other
; frame. Row 22 from column 26: the frames of the last sideways move and
; the last try at one. Row 21 from column 26, by roll: the virtual GB
; cycle count at its first rDIV read, the current piece's type, the old
; hidden piece (now NEXT) and the new hidden one.
testtick:
	ld	hl,(frames)	; the least idle time, after the first frames
	ld	de,16
	or	a
	sbc	hl,de
	jr	c,tt_0
	ld	hl,(idle)
	ld	de,(minidle)
	or	a
	sbc	hl,de
	jr	nc,tt_0
	ld	hl,(idle)
	ld	(minidle),hl
	ifdef	QUIET
	ld	bc,0*256+22	; only the idle count, when it changes
	jp	sethex2
	endif
tt_0:
	ifdef	QUIET
	ret
	endif
	ld	a,(frames)	; row 0 every other frame, to save time
	rrca
	jr	c,tt_1
	ld	bc,0*256+1
	ld	hl,(t_spawn)
	call	sethex2
	inc	c
	ld	hl,(t_drop)
	call	sethex2
	inc	c
	ld	hl,(t_lock)
	call	sethex2
	inc	c
	ld	a,(prow)
	call	sethex
	inc	c
	ld	a,(stuck)
	call	sethex
	inc	c
	ld	hl,(minidle)
	call	sethex2
	inc	c
	ld	a,(t_gap)
	call	sethex
	inc	c
	ld	a,(t_cgap)
	call	sethex
	inc	c
	ld	a,(pcol)
	call	sethex
	inc	c
	ld	a,(pcode)
	call	sethex
	ld	bc,22*256+26
	ld	hl,(t_move)
	call	sethex2
	inc	c
	ld	hl,(t_try)
	call	sethex2
tt_1:	ld	bc,22*256+8
	ld	hl,(frames)
	ld	a,h
	call	sethex
	ld	a,(frames)
	call	sethex
	ld	a,(press)
	ld	d,a
	ld	hl,counts
	ld	bc,23*256+1
	ld	e,7		; LEFT to SPACE
tk_1:	srl	d
	jr	nc,tk_3
	ld	a,(hl)
	inc	a
	cp	10
	jr	c,tk_2
	xor	a
tk_2:	ld	(hl),a
	add	a,'0'
	push	de
	push	hl
	push	bc
	call	setcell
	pop	bc
	pop	hl
	pop	de
tk_3:	inc	hl
	inc	c
	inc	c
	dec	e
	jr	nz,tk_1
	ret

	ifdef	SCRIPT
; The keys from a script, not the keyboard: each entry a frame and the
; keys held from it on, as keys sets them. A frame of FFFFh ends it.
script:	ld	hl,scripts
	ld	b,SCRIPT
sc_1:	dec	b
	jr	z,sc_3
sc_2:	ld	e,(hl)		; skip a script
	inc	hl
	ld	d,(hl)
	inc	hl
	inc	hl
	ld	a,d
	and	e
	inc	a
	jr	nz,sc_2
	jr	sc_1
sc_3:	ld	c,0		; the keys held now
sc_4:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,d
	and	e
	inc	a
	jr	z,sc_5
	push	hl
	ld	hl,(frames)
	or	a
	sbc	hl,de
	pop	hl
	jr	c,sc_5		; not yet
	ld	c,(hl)
	inc	hl
	jr	sc_4
sc_5:	ld	a,(sheld)
	cpl
	and	c
	ld	(press),a
	ld	a,c
	ld	(held),a
	ld	(sheld),a
	ret

KR	equ	1<<K_RIGHT
KL	equ	1<<K_LEFT
scripts:
	; 1: RIGHT held at frame 30 to 89
	dw	30
	db	KR
	dw	90
	db	0
	dw	0FFFFh
	db	0
	; 2: RIGHT and LEFT held together, the same
	dw	30
	db	KR|KL
	dw	90
	db	0
	dw	0FFFFh
	db	0
	; 3: LEFT held at frame 30 to 89, into the wall
	dw	30
	db	KL
	dw	90
	db	0
	dw	0FFFFh
	db	0
	; 4: Z, Z, UP: rotation 0 to 1 to 2 to 1
	dw	30
	db	1<<K_ROTB
	dw	32
	db	0
	dw	34
	db	1<<K_ROTB
	dw	36
	db	0
	dw	38
	db	1<<K_ROTA
	dw	40
	db	0
	dw	0FFFFh
	db	0
	; 5: Z then UP and Z together, Z wins: 0 to 1 to 2
	dw	30
	db	1<<K_ROTB
	dw	32
	db	0
	dw	34
	db	(1<<K_ROTB)|(1<<K_ROTA)
	dw	36
	db	0
	dw	0FFFFh
	db	0
	; 6: Z blocked by FILL 3, then UP: 0 to 3
	dw	30
	db	1<<K_ROTB
	dw	32
	db	0
	dw	34
	db	1<<K_ROTA
	dw	36
	db	0
	dw	0FFFFh
	db	0
	; 7: Z once
	dw	30
	db	1<<K_ROTB
	dw	32
	db	0
	dw	0FFFFh
	db	0
	; 8: DOWN held from frame 30 on
	dw	30
	db	1<<K_DOWN
	dw	0FFFFh
	db	0
	; 9: DOWN held at frame 30 to 59
	dw	30
	db	1<<K_DOWN
	dw	60
	db	0
	dw	0FFFFh
	db	0
	; 10: DOWN held and ENTER at frame 30, ENTER at 50
	dw	30
	db	(1<<K_DOWN)|(1<<K_PAUSE)
	dw	32
	db	0
	dw	50
	db	1<<K_PAUSE
	dw	52
	db	0
	dw	0FFFFh
	db	0
	; 11: ENTER at frame 1100 and 1150
	dw	1100
	db	1<<K_PAUSE
	dw	1102
	db	0
	dw	1150
	db	1<<K_PAUSE
	dw	1152
	db	0
	dw	0FFFFh
	db	0
	; 12: ENTER at frame 30
	dw	30
	db	1<<K_PAUSE
	dw	32
	db	0
	dw	0FFFFh
	db	0
	; 13: ENTER at frame 30 and 300
	dw	30
	db	1<<K_PAUSE
	dw	32
	db	0
	dw	300
	db	1<<K_PAUSE
	dw	302
	db	0
	dw	0FFFFh
	db	0
	endif

; HL in hex at row B, columns C to C + 3
sethex2:
	ld	a,h
	push	hl
	call	sethex
	pop	hl
	ld	a,l

; A in hex at row B, columns C and C + 1, through the change list
sethex:	push	af
	rrca
	rrca
	rrca
	rrca
	call	sh_1
	pop	af
sh_1:	and	0Fh
	add	a,'0'
	cp	'9'+1
	jr	c,sh_2
	add	a,'A'-'9'-1
sh_2:	push	bc
	call	setcell
	pop	bc
	inc	c
	ret
	endif

	include	"game.asm"
	include	"keys.asm"
	include	"video.asm"
	include	"tables.asm"

m_home:	db	1Eh,1Bh,'Y','$'
m_nostart:
	db	"TETRIS: no single cursor in video RAM, screen start not found",13,10,'$'
	ifdef	TEST
m_page0:
	db	"PAGE 0",0
m_page1:
	db	"PAGE 1",0
m_keys:	db	"L0R0D0U0Z0E0S0",0
	endif

; DATA. All of it is in the .COM, so it starts zeroed.

ccpsp:	dw	0
vstart:	dw	0		; ring address of the screen start
vlsave:	db	0		; VLATCH as CP/M had it
shown:	db	0		; the page on screen, 0 even, 1 odd
wpage:	db	0		; the page puts and putcell write, 2 both
held:	db	0
press:	db	0
	ifdef	TEST
frames:	dw	0
counts:	ds	7,0
t_spawn: dw	0
t_drop:	dw	0
t_lock:	dw	0
t_gap:	db	0
t_cgap:	db	0
npieces: db	0
t_move:	dw	0
t_try:	dw	0
sheld:	db	0
r_k:	ds	3		; the last roll, as row 21 shows it
r_c:	db	0
idle:	dw	0
minidle: dw	0FFFFh
	endif
	ifdef	LEVEL
level0:	db	LEVEL		; the level picked
	else
level0:	db	0
	endif
level:	db	0		; the game's, the GB's $FFA9
	ifdef	HARD
hard:	db	1
	else
hard:	db	0		; hard mode, the GB's hIsHardMode
	endif
wmode:	db	0
speed:	db	0		; frames a row, from the speed table
state:	db	0
timer:	db	0
dropctr: db	0
pcode:	db	0		; id x 4 + rotation
pglyph:	db	0
prow:	db	0		; the board row and column of the piece's grid
pcol:	db	0
drawg:	db	0
	ifdef	FIRST
nextcode: db	FIRST*4		; the test build's first piece, then in turn
	else
nextcode: db	0		; the GB's NEXT, spec 1
	endif
hidden:	db	0		; the GB's hHiddenLoadedPiece, kept from game to game
nexthide: db	0		; the GB's wNextPieceHidden
paused:	db	0
wipe:	db	0		; frames left of the pause wipe
vdiv:	ds	3		; the virtual GB cycle count, rDIV its bits 8-15
stuck:	db	0		; grace locks at the spawn place
das:	db	0		; the sideways auto repeat counter
timer2:	db	0		; the GB's hTimer2, soft drop
sdcount: db	0		; soft drop rows this piece, and the blocked one
candown: db	0		; DOWN must be pressed again, the GB's $C0C7
score:	ds	3		; binary, up to 999,999
nlines:	dw	0		; up to 9999
num:	ds	3
numrc:	dw	0
oldcol:	db	0		; the piece before move
oldcode: db	0
sidecol: db	0
nrows:	db	0
lrows:	ds	4		; the full rows, top first
pass:	db	0
rrow:	db	0
board:	ds	BROWS*BCOLS
curlst:	dw	0		; this frame's changes
curend:	dw	0
prevlst: dw	0		; last frame's changes
prevend: dw	0
fontbuf: ds	200h		; font RAM 2, rows 0-7 of 80h-BFh
bx_c0:	db	0		; boxdraw's box, each column then row
bx_r0:	db	0
bx_c1:	db	0
bx_r1:	db	0
bx_g:	db	0
	ds	8		; blank, the letter before a message's first
chbuf:	ds	11*8		; a message's letters from font RAM 1
sn_p:	dw	0		; the NEXT piece's cells, its glyph, its offsets
sn_g:	dw	0
sn_xo:	db	0
sn_yo:	db	0
sn_y:	db	0
sn_n:	db	0
nbuf:	ds	12*8		; its 12 glyphs, 4 across by 3 down

MAXCHG	equ	192
list0:	ds	MAXCHG*3
list1:	ds	MAXCHG*3
	ds	128
stack:
