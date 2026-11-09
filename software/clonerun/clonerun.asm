; CLONERUN.COM, Clone Runner for the Lobo MAX-80 under xcpmz80. New
; code and art, a port of Lode Runner: its rules, and its stages, read
; at build time from a file you supply.
;
; It saves font RAM, goes into 8-line rows, loads the glyphs and shows
; stage 1 in columns 12-67, rows 4-19, with the level and its gold on
; row 22 and the keys on row 23. In the viewer N or RIGHT shows the next
; level, P or LEFT the one before, UP and DOWN go 10 on or back, ENTER
; plays the level shown and ESC puts the font, the CRTC, VLATCH and the
; screen back and returns to the CCP. In play the arrows run, climb,
; hang and drop, Z and X dig left and right, and ESC goes back to the
; viewer. The hidden ladders and the false bricks show in the viewer.
; Up to 5 guards chase the runner. One touching it costs a life, and a
; hole closing on it too. P pauses, F1 gives up a life. 5 lives, then
; the game is over.
;
; Built with TEST defined (build.sh, as CRT.COM), it has the test levels
; of tests/levels_test.txt, and "CRT L S [F]" plays level L at once with
; key script S (test.asm) instead of the keyboard, frozen at round F if
; given. Row 23 then shows the runner's place, what it does, the rounds
; and the timings (testrow). TWICE builds and copies the runner twice a
; frame, so the difference in the timings is what one build and one
; copy take.
;
; build.sh makes build/glyphs.inc and build/levels.inc, then
; sjasmplus -Ibuild --raw=build/CLONERUN.COM clonerun.asm

	include	"hw.inc"
	include	"tune.inc"

FCOL	equ	12		; the field's first screen column
FROW0	equ	4		; its first screen row
FTILES	equ	28		; tiles a row
FROWS	equ	16		; rows of tiles
NTILES	equ	FTILES*FROWS
TROW	equ	64		; bytes a row in tiles: the border, the field, the stand bytes
SOFF	equ	32		; where in a row the stand bytes start (actors.asm)
MAXHLAD	equ	45		; hidden ladders a stage at most, as tools/levels.py keeps
MAXTICK	equ	4		; ticks run at most a frame
OVERWAIT equ	45		; frames, 0.75 s, GAME OVER ignores ENTER
KCAPS	equ	0F52Fh		; xcpmz80's Caps Lock, CVARS+2Fh in its common.asm
G_FIG	equ	92h		; the actors' glyphs, 6 each, in font RAM 2
TSTUB	equ	0DE00h		; the tick stub, common memory below xcpmz80's DF00h

	org	100h

start:	ld	(ccpsp),sp	; the CCP's stack stays as it is
	ld	sp,stack
	ld	de,m_home	; home and erase, the cursor at the start
	ld	c,9
	call	BDOS
	call	findstart
	jr	nc,st_0
	ld	de,m_nostart
	ld	c,9
	call	BDOS
	ld	sp,(ccpsp)
	ret
st_0:	call	gridinit	; the border of tiles and the tables, once
st_1:	di			; 80 columns, the window on video RAM
	ld	a,(VLATCH)
	ld	(vlsave),a
	and	0F0h
	or	W_VIDEO
	ld	(VLATCH),a
	ei
	ifdef	TEST
	call	tail
	endif
	call	fontin
	call	linein
	ld	a,(KCAPS)	; F1 here is Caps Lock to the kernel too
	ld	(capsave),a
	call	hookon
	call	keys		; what is down already, ENTER from the CCP, is no press
	ld	a,1
	ld	(level),a
	ifdef	TEST
	ld	a,(tlev)
	or	a
	jr	z,title
	ld	(level),a
	jp	toplay
	endif
	jr	title

; THE TITLE:
; Big letters of brick, a little scene, the high score of this run and
; the keys. ENTER plays from stage 1, S shows the stages, ESC quits.
title:	xor	a
	ld	(inplay),a
	ld	hl,scrbuf
	call	blank
	ld	hl,t_art
ti_1:	ld	a,(hl)		; the rows of tiles
	cp	0FFh
	jr	z,ti_5
	ld	b,a
	inc	hl
	ld	c,(hl)
	inc	hl
ti_2:	ld	a,(hl)
	inc	hl
	or	a
	jr	z,ti_1
	push	hl
	ld	d,a
	ld	hl,t_codes	; its left code, or none
ti_3:	ld	a,(hl)
	or	a
	jr	z,ti_4
	inc	hl
	cp	d
	ld	a,(hl)
	inc	hl
	jr	nz,ti_3
	call	bufptr
	ld	(hl),a
	inc	hl
	inc	a
	ld	(hl),a
ti_4:	pop	hl
	inc	c
	inc	c
	jr	ti_2
ti_5:	ld	hl,t_text	; the lines of text
ti_6:	ld	a,(hl)
	cp	0FFh
	jr	z,ti_7
	ld	b,a
	inc	hl
	ld	c,(hl)
	inc	hl
	ex	de,hl
	call	puts
	inc	de
	ex	de,hl
	jr	ti_6
ti_7:	ld	bc,21*256+31	; the high score
	ld	de,m_high
	call	puts
	ld	de,hiscore
	call	put7
	xor	a
	ld	(drawrow),a
tl_1:	call	waitvb
	call	drawsome
	ei
	call	keys
	ld	a,(drawrow)	; no keys until it is all there
	cp	ROWS
	jr	c,tl_1
	ld	a,(press)
	bit	K_ESC,a
	jp	nz,exit
	bit	K_ENTER,a
	jr	z,tl_2
	ld	a,1
	ld	(level),a
	jp	toplay
tl_2:	ld	a,(vpress)
	bit	K_S,a
	jp	nz,toview
	jr	tl_1

; The score kept as the high score if it is more
keephigh: ld	hl,score+3
	ld	de,hiscore+3
	ld	b,4
be_1:	ld	a,(de)
	cp	(hl)
	jr	c,be_2		; more
	ret	nz		; less
	dec	hl
	dec	de
	djnz	be_1
	ret
be_2:	ld	hl,score
	ld	de,hiscore
	ld	bc,4
	ldir
	ret


; THE VIEWER:
toview:	xor	a
	ld	(inplay),a
	call	newlevel
view:	call	waitvb
	call	drawsome
	ei
	call	keys
	ld	a,(press)
	bit	K_ESC,a
	jp	nz,title
	bit	K_ENTER,a
	jr	nz,toplay
	ld	b,1
	bit	K_RIGHT,a
	jr	nz,vw_1
	bit	K_UP,a
	ld	b,10
	jr	nz,vw_1
	bit	K_DOWN,a
	jr	nz,vw_0
	ld	b,1
	bit	K_LEFT,a
	jr	nz,vw_0
	ld	a,(vpress)
	bit	K_N,a
	jr	nz,vw_1
	bit	K_P,a
	jr	z,view
vw_0:	ld	a,(level)	; B back, round past 1 to the last
	sub	b
	jr	z,vw_0a
	jr	nc,vw_2
vw_0a:	add	a,NLEVELS
	jr	vw_2
vw_1:	ld	a,(level)	; B on, round past the last to 1
	add	a,b
	jr	c,vw_1a
	cp	NLEVELS+1
	jr	c,vw_2
vw_1a:	sub	NLEVELS
vw_2:	ld	(level),a
	call	newlevel
	jr	view

; PLAY:
; The screen is drawn first. Then each frame, in the vertical blank,
; the holes that changed and the figures go in, and in the picture the
; ticks since last frame are counted, a round run every 2.4 of them, and
; up to FIGFRAME figures built for the next. A runner caught in a hole
; that fills starts the level again (replay).
toplay:
	ifdef	TEST
	ld	hl,0
	ld	(ttick),hl
	ld	(tframes),hl
	dec	hl
	ld	(idmin),hl
	ld	(vbmin),hl
	xor	a
	ld	(restarts),a
	endif
	ld	a,LIVES		; a new game
	ld	(lives),a
	ld	hl,0
	ld	(score),hl
	ld	(score+2),hl
	xor	a
	ld	(difficulty),a
	ld	(birthcol),a
replay:	ld	a,1
	ld	(inplay),a
	call	newlevel
	call	holeinit
	call	actinit
	xor	a
	ld	(started),a
	ld	(caught),a
	ld	(rtick),a
	ld	(paused),a
	ld	(moving),a
	ld	(entfree),a
	ld	(tapped),a
	ld	(prevk),a
	ld	(lastdir),a
	ld	(gowed),a
	ld	(gpend),a
	ld	(fmoves),a
	ld	(won),a
	ld	(revealed),a
	ld	(tqin),a
	ld	(tqout),a
	ld	(moveoff),a
	ld	(moveid),a
	call	status
	xor	a		; the screen drawn takes rows 22 and 23 too
	ld	(stchg),a
play:	call	waitvb
	ld	a,(drawrow)
	cp	ROWS
	jr	nc,pl_1
	call	drawsome
	ifdef	TEST
	ld	a,1		; the next frame's passes not counted: this
	ld	(tfmt),a	; one's work did not start with the picture
	endif
	jr	pl_2
pl_1:	call	holecopy
	call	tilecopy
	call	figcopy
	call	statcopy
	ifdef	TWICE
	ld	a,1
	ld	(actors+A_BUILT),a
	call	figcopy
	endif
	ifdef	TEST
	call	testvb
	endif
pl_2:	ei
	call	keys
	ld	a,(press)
	bit	K_ESC,a
	jr	z,pl_2b
	call	keephigh
	jp	toview
pl_2b:	ld	a,(drawrow)	; no moves until the screen is all there
	cp	ROWS
	jr	c,play
	ld	a,(vpress)
	bit	K_P,a
	call	nz,pause
	bit	K_F1,a		; giving up a life
	jr	z,pl_2a
	ld	a,(paused)
	or	a
	jr	nz,pl_2a
	inc	a
	ld	(caught),a
pl_2a:	ld	a,(started)
	or	a
	jr	nz,pl_3
	inc	a
	ld	(started),a
	ld	a,(tcount)
	ld	(tseen),a
pl_3:	ld	a,(tcount)	; the ticks since last frame, at most MAXTICK
	ld	hl,tseen
	ld	b,a
	sub	(hl)
	ld	(hl),b
	ld	b,a
	ld	a,(paused)	; none while paused
	or	a
	ld	a,b
	jr	z,pl_3a
	xor	a
pl_3a:	cp	MAXTICK+1
	jr	c,pl_4
	ld	a,MAXTICK
pl_4:	or	a
	jr	z,pl_6
	ld	b,a
pl_5:	push	bc
	ld	hl,rtick
	ld	a,(hl)
	add	a,ROUNDSTEP
	ld	(hl),a
	cp	ROUNDQ
	jr	c,pl_5a
	sub	ROUNDQ
	ld	(hl),a
	call	round
pl_5a:	pop	bc
	djnz	pl_5
pl_6:	call	gframe		; a guard's move owed by the round
	ld	a,(caught)
	or	a
	jr	z,pl_6b
	ifdef	TEST
	ld	hl,restarts
	inc	(hl)
	endif
	call	death
	ld	hl,lives
	dec	(hl)
	jp	nz,replay
	jp	gameover
pl_6b:	ld	a,(won)
	or	a
	jr	z,pl_7
	call	endstage
	jp	replay
pl_7:	call	buildsome
	ifdef	TWICE
	ld	ix,actors
	call	figbuild
	endif
	ifdef	TEST
	call	testrow
	endif
	jp	play

; One round: the keys, the moves the last round still owes, the holes,
; the runner and the gold it takes, and the guards. One guard's move is
; made now and the rest one a frame after it (gframe), then a guard
; touching the runner and the stage done (gdone). Between rounds only
; the guards move, so the round comes out the same as with every move at
; once, and no frame has more than one guard's chase in it but the one
; that has to finish a round's moves.
round:	ld	a,(caught)	; none after the runner is caught or done
	ld	hl,won
	or	(hl)
	ret	nz
	ifdef	TEST
	call	script
	ret	c		; frozen
	else
	ld	a,(tapped)
	endif
	and	KR|KL|KU|KD|KZ|KX
	ld	(rkeys),a
	ld	hl,prevk	; the direction pressed last goes first
	ld	c,(hl)
	ld	(hl),a
	ld	b,a
	ld	a,c
	cpl
	and	b
	and	KR|KL|KU|KD
	jr	z,rk_1
	ld	(lastdir),a
rk_1:	xor	a
	ld	(tapped),a	; B the keys: nothing moves until the first
	ld	a,(moving)
	or	b
	ret	z
	ld	(moving),a
	call	gflush		; the last round's guards done first
	ret	c
	call	holetick
	call	runner
	call	rungold
	call	guards_
	call	gstep		; one guard's move now, the rest in the frames
	jp	gdone		; to come (guards.asm, gframe)

; The runner caught: two beeps, and the field still for a second
death:	ld	(BEEP),a
	ld	b,12
	call	frames
	ld	(BEEP),a
	ld	b,48

; Waits B frames, the screen as it is
frames:	push	bc
	call	waitvb
	ei
	pop	bc
	djnz	frames
	ret

; P: play stops, or goes on, and row 23 says so
pause:	ld	a,(paused)
	xor	1
	ld	(paused),a
	xor	a
	ld	(tapped),a
	call	status
	ld	a,(vpress)
	ret

; No lives left: GAME OVER on row 23 until ENTER or ESC, then the title.
; Row 23 takes the place of the test build's row there.
gameover:
	call	status
	ld	bc,23*256
	call	bufptr
	ld	b,COLS
go_0:	ld	(hl),' '
	inc	hl
	djnz	go_0
	ld	bc,23*256+FCOL
	ld	de,m_over
	call	puts
	ld	a,OVERWAIT
	ld	(ovwait),a
go_1:	call	waitvb		; both rows, in the test build too
	call	vidwin
	ld	a,22
	call	onerow
	ld	a,23
	call	onerow
	ei
	call	keys
	ld	c,1<<K_ENTER|1<<K_ESC
	ld	hl,ovwait	; ENTER digs, so at first only ESC
	ld	a,(hl)
	or	a
	jr	z,go_2
	dec	(hl)
	ld	c,1<<K_ESC
go_2:	ld	a,(press)
	and	c
	jr	z,go_1
	call	keephigh
	jp	title

; Rows 22 and 23 in play, into scrbuf, to be copied in the next blank:
; the score, the lives, the stage and its gold, and the keys or PAUSED
status:	ld	bc,22*256+FCOL
	call	bufptr
	ld	b,2*FTILES
ss_0:	ld	(hl),' '
	inc	hl
	djnz	ss_0
	ld	bc,22*256+FCOL
	ld	de,m_score
	call	puts
	ld	de,score
	call	put7
	ld	bc,22*256+FCOL+16
	ld	de,m_men
	call	puts
	ld	a,(lives)
	call	put3
	ld	bc,22*256+FCOL+27
	ld	de,m_level
	call	puts
	ld	a,(level)
	call	put3
	ld	bc,22*256+FCOL+2*FTILES-8
	ld	de,m_gold
	call	puts
	ld	a,(ngold)
	call	put3
	ld	bc,23*256+FCOL
	call	bufptr
	ld	b,2*FTILES
ss_1:	ld	(hl),' '
	inc	hl
	djnz	ss_1
	ld	bc,23*256+FCOL
	ld	de,m_phelp
	ld	a,(paused)
	or	a
	jr	z,ss_2
	ld	de,m_paused
ss_2:	call	puts
	ld	a,1
	ld	(stchg),a
	ret

; Call in the vertical blank: rows 22 and 23 to the screen if they
; changed. The test build keeps row 23 for itself (testvb).
statcopy:
	ld	a,(stchg)
	or	a
	ret	z
	xor	a
	ld	(stchg),a
	call	vidwin
	ld	a,22
	call	onerow
	ifndef	TEST
	ld	a,23
	call	onerow
	endif
	ret

; DE a score in BCD, 4 digits: added to score
addscore:
	ld	hl,score
	ld	a,(hl)
	add	a,e
	daa
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,d
	daa
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,0
	daa
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,0
	daa
	ld	(hl),a
	jp	status

; DE a score, 4 BCD bytes, the lowest first: its 7 low digits at HL, HL
; after them
put7:	inc	de
	inc	de
	inc	de
	ld	a,(de)
	and	0Fh
	add	a,'0'
	ld	(hl),a
	inc	hl
	ld	b,3
p7_1:	dec	de
	ld	a,(de)
	call	putbcd
	djnz	p7_1
	ret

; A two BCD digits at HL, HL after them
putbcd:	push	af
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	add	a,'0'
	ld	(hl),a
	inc	hl
	pop	af
	and	0Fh
	add	a,'0'
	ld	(hl),a
	inc	hl
	ret

; The actors at the level's start: the runner standing at its start,
; and after it the end mark
actinit:
	ld	ix,actors
	call	actclr
	ld	a,(pcol)
	ld	(ix+A_X),a
	ld	a,(prow)
	ld	(ix+A_Y),a
	ld	(ix+A_SOFF),0
	ld	(ix+A_CODE),G_FIG
	ld	a,(nguard)	; the guards at their starts
	ld	b,a
	ld	hl,(guards)
	ld	c,G_FIG
	ld	de,ASIZE
	jr	ai_2
ai_1:	add	ix,de
	push	bc
	push	hl
	push	de
	call	actclr
	pop	de
	pop	hl
	pop	bc
	ld	a,(hl)
	ld	(ix+A_X),a
	inc	hl
	ld	a,(hl)
	ld	(ix+A_Y),a
	inc	hl
	ld	(ix+A_SOFF),GFIG
	ld	a,c
	add	a,6
	ld	c,a
	ld	(ix+A_CODE),a
	dec	b
ai_2:	ld	a,b
	or	a
	jr	nz,ai_1
	add	ix,de
	ld	(ix+A_ST),S_END
	ret

; IX an actor: standing, facing right, shown and to be built, holding
; no cells
actclr:	push	ix
	pop	hl
	ld	b,A_BUF
ac_1:	ld	(hl),0
	inc	hl
	djnz	ac_1
	ld	(ix+A_FACE),1
	ld	(ix+A_DIRTY),1
	ld	(ix+A_VIS),1
	ld	(ix+A_REDO),1
	ret

; Blanks the screen, waits until no key has been down for 4 frames, so
; the BIOS has nothing held to repeat, puts the machine back, empties
; the console input and clears the screen for the CCP.
exit:	ld	hl,scrbuf
	call	blank
	xor	a
	ld	(drawrow),a
ex_0:	call	waitvb
	call	drawsome
	ei
	ld	a,(drawrow)
	cp	ROWS
	jr	c,ex_0
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
	call	hookoff
	ld	a,(capsave)
	ld	(KCAPS),a
	call	lineout
	call	fontout
	di
	ld	a,(vlsave)
	ld	(VLATCH),a
	ei
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

; Saves font RAM 1 and rows 0-7 of font RAM 2, the only rows 8-line
; cells show, then writes our glyphs, all in the vertical blank
fontin:	ld	hl,WINDOW
	ld	de,f1save
	ld	bc,400h
	ld	a,W_FONT1
	call	vbcopy
	ld	hl,WINDOW
	ld	de,f2save
	ld	bc,200h
	ld	a,W_FONT2
	call	vbcopy
	ld	hl,font1
	ld	de,WINDOW+F1LO*8
	ld	bc,F1N*8
	ld	a,W_FONT1
	call	vbcopy
	ld	hl,font2
	ld	de,WINDOW+(F2LO-80h)*8
	ld	bc,F2N*8
	ld	a,W_FONT2
	jp	vbcopy

; Puts font RAM back as fontin found it
fontout:
	ld	hl,f1save
	ld	de,WINDOW
	ld	bc,400h
	ld	a,W_FONT1
	call	vbcopy
	ld	hl,f2save
	ld	de,WINDOW
	ld	bc,200h
	ld	a,W_FONT2
	jp	vbcopy

; Level (level), 1 on: unpacked into tiles, drawn into scrbuf, and
; drawsome starts copying it to the screen
newlevel:
	ld	a,(level)
	dec	a
	ld	l,a
	ld	h,0
	add	hl,hl
	ld	de,levtab
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	a,(hl)		; gold, runner column and row, guards
	ld	(ngold),a
	inc	hl
	ld	a,(hl)
	ld	(pcol),a
	inc	hl
	ld	a,(hl)
	ld	(prow),a
	inc	hl
	ld	a,(hl)
	ld	(nguard),a
	inc	hl
	ld	(guards),hl	; each a column and a row
	add	a,a
	ld	e,a
	ld	d,0
	add	hl,de		; the tiles follow
	call	unpack
	ld	a,(inplay)	; for play: the hidden ladders and stand bytes
	or	a
	call	nz,hidlist
	ld	a,(inplay)
	or	a
	call	nz,standall
	call	build
	xor	a
	ld	(drawrow),a
	ret

; Once, at the start: rulet from behave, flagt from rulet, and tiles
; all solid with the row above the field empty and every stand byte 0.
; Only the field's tiles and stand bytes change after that. Keeps HL.
gridinit:
	push	hl
	ld	hl,rulet	; rulet: kinds 0-127 and 128-255 alike
	ld	b,2
gn_1:	push	bc
	ld	de,behave
	ld	b,128
gn_2:	ld	a,b		; behave's 10 kinds, the rest empty
	cp	128-NKINDS+1
	ld	a,T_EMPTY
	jr	c,gn_3
	ld	a,(de)
	inc	de
gn_3:	ld	(hl),a
	inc	hl
	djnz	gn_2
	pop	bc
	djnz	gn_1
	ld	hl,rulet	; flagt from rulet
	ld	de,flagt
gn_4:	push	hl
	ld	a,(hl)
	ld	hl,rflags
	add	a,l
	ld	l,a
	jr	nc,gn_5
	inc	h
gn_5:	ld	a,(hl)
	pop	hl
	ld	(de),a
	inc	hl
	inc	e
	jr	nz,gn_4
	ld	a,F_GOLD
	ld	(flagt+T_GOLD),a
	ld	a,F_HOLD|F_HOLE
	ld	(flagt+T_HOLE),a
	ld	hl,tiles	; tiles all solid
	ld	de,tiles+1
	ld	(hl),T_SOLID
	ld	bc,(FROWS+2)*TROW-1
	ldir
	ld	hl,tiles	; the row above the field empty
	ld	b,SOFF
gn_7:	ld	(hl),T_EMPTY
	inc	hl
	djnz	gn_7
	ld	hl,tiles+SOFF	; every stand byte 0
	ld	de,TROW-SOFF
	ld	c,FROWS+2
gn_8:	ld	b,TROW-SOFF
gn_9:	ld	(hl),0
	inc	hl
	djnz	gn_9
	add	hl,de
	dec	c
	jr	nz,gn_8
	pop	hl
	ret

; HL a level's tiles, 3 bits each, 8 in 3 bytes, the first in the top
; bits (tools/levels.py): one a byte into tiles, the border left
unpack:	ld	ix,tiles+TROW+1
	ld	a,FTILES
	ld	(ucol),a
	ld	a,NTILES/8
up_1:	push	af
	ld	c,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	b,8
up_2:	xor	a
	sla	e
	rl	d
	rl	c
	rla
	sla	e
	rl	d
	rl	c
	rla
	sla	e
	rl	d
	rl	c
	rla
	ld	(ix+0),a
	inc	ix
	ld	a,(ucol)	; past the row's end: over the border
	dec	a
	jr	nz,up_3
	push	de
	ld	de,TROW-FTILES
	add	ix,de
	pop	de
	ld	a,FTILES
up_3:	ld	(ucol),a
	djnz	up_2
	pop	af
	dec	a
	jr	nz,up_1
	ret

; scrbuf from tiles and the level's starts and counts. In play the
; hidden ladders and the starts are not shown, and a false brick is a
; brick.
build:	ld	hl,scrbuf
	call	blank
	ld	hl,tilepair
	ld	a,(inplay)
	or	a
	jr	z,bd_0
	ld	hl,playpair
bd_0:	ld	(pairs),hl
	ld	hl,tiles+TROW+1
	ld	de,scrbuf+FROW0*COLS+FCOL
	ld	c,FROWS
bd_1:	ld	b,FTILES
bd_2:	push	bc
	ld	a,(hl)		; the tile's two codes
	inc	hl
	push	hl
	add	a,a
	ld	c,a
	ld	b,0
	ld	hl,(pairs)
	add	hl,bc
	ldi
	ldi
	pop	hl
	pop	bc
	djnz	bd_2
	push	hl
	ld	hl,COLS-2*FTILES
	add	hl,de
	ex	de,hl
	pop	hl
	ld	a,l		; over the border
	add	a,TROW-FTILES
	ld	l,a
	jr	nc,bd_5
	inc	h
bd_5:	dec	c
	jr	nz,bd_1
	ld	a,(inplay)
	or	a
	jr	nz,bd_4
	ld	a,(prow)	; the starts, drawn as standing figures
	ld	b,a
	ld	a,(pcol)
	ld	c,a
	ld	a,G_PLAYER
	call	putpair
	ld	a,(nguard)
	or	a
	jr	z,bd_4
	ld	hl,(guards)
bd_3:	push	af
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	push	hl
	ld	a,G_GUARD
	call	putpair
	pop	hl
	pop	af
	dec	a
	jr	nz,bd_3
bd_4:	ld	bc,22*256+FCOL	; LEVEL nnn
	ld	de,m_level
	call	puts
	ld	a,(level)
	call	put3
	ld	bc,22*256+FCOL+2*FTILES-8	; GOLD nnn, ending in column 67
	ld	de,m_gold
	call	puts
	ld	a,(ngold)
	call	put3
	ld	bc,23*256+FCOL
	ld	de,m_help
	ld	a,(inplay)
	or	a
	jp	z,puts
	ld	de,m_phelp
	jp	puts

; HL 1920 bytes: all blank
blank:	ld	(hl),' '
	ld	d,h
	ld	e,l
	inc	de
	ld	bc,ROWS*COLS-1
	ldir
	ret

; B tile row, C tile column, A a tile's left code: the tile in scrbuf
putpair:
	push	af
	ld	a,c
	add	a,a
	add	a,FCOL
	ld	c,a
	ld	a,b
	add	a,FROW0
	ld	b,a
	call	bufptr
	pop	af
	ld	(hl),a
	inc	hl
	inc	a
	ld	(hl),a
	ret

; B row, C column: HL its place in scrbuf. Keeps BC and DE.
bufptr:	push	de
	ld	l,b
	ld	h,0
	add	hl,hl
	ld	de,rowoff
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,scrbuf
	add	hl,de
	ld	e,c
	ld	d,0
	add	hl,de
	pop	de
	ret

; B row, C column, DE text ending in 0: written into scrbuf, HL after it
puts:	call	bufptr
putshl:	ld	a,(de)
	or	a
	ret	z
	ld	(hl),a
	inc	hl
	inc	de
	jr	putshl

; A as three digits at HL, HL after them
put3:	ld	b,'0'-1
p3_1:	inc	b
	sub	100
	jr	nc,p3_1
	add	a,100
	ld	(hl),b
	inc	hl

; A, 0 to 99, as two digits at HL, HL after them
put2:	ld	b,'0'-1
p2_1:	inc	b
	sub	10
	jr	nc,p2_1
	add	a,10+'0'
	ld	(hl),b
	inc	hl
	ld	(hl),a
	inc	hl
	ret

	include	"screen.asm"
	include	"keys.asm"
	include	"actors.asm"
	include	"figures.asm"
	include	"holes.asm"
	include	"guards.asm"
	include	"gold.asm"
	ifdef	TEST
	include	"test.asm"
	endif

; Each tile kind's two codes in the viewer, in tools/levels.py's order
tilepair:
	db	' ',' '			; empty
	db	G_BRICK,G_BRICK+1
	db	G_SOLID,G_SOLID+1
	db	G_LADDER,G_LADDER+1
	db	G_BAR,G_BAR+1
	db	G_TRAP,G_TRAP+1		; a false brick, marked
	db	G_EXIT,G_EXIT+1		; a hidden ladder
	db	G_GOLD,G_GOLD+1

; The same in play: a false brick a brick, a hidden ladder not there
playpair:
	db	' ',' '
	db	G_BRICK,G_BRICK+1
	db	G_SOLID,G_SOLID+1
	db	G_LADDER,G_LADDER+1
	db	G_BAR,G_BAR+1
	db	G_BRICK,G_BRICK+1
	db	' ',' '
	db	G_GOLD,G_GOLD+1

m_home:	db	1Eh,1Bh,'Y','$'
m_nostart:
	db	"CLONERUN: no single cursor in video RAM, screen start not found",13,10,'$'
m_level: db	"LEVEL ",0
m_gold:	db	"GOLD ",0
m_help:	db	"N/RIGHT: NEXT  P/LEFT: BACK  UP/DOWN: 10  ENTER: PLAY  ESC: TITLE",0
; The title (title): rows of tiles, '#' brick, '@' solid, 'H' ladder,
; '$' gold, '&' and '0' the starts, '.' empty, each a screen row and
; column, then the lines of text, each FFh ended
t_art:
	db	2,20,"###.#...###.#..#.###",0
	db	3,20,"#...#...#.#.##.#.#..",0
	db	4,20,"#...#...#.#.#.##.##.",0
	db	5,20,"#...#...#.#.#..#.#..",0
	db	6,20,"###.###.###.#..#.###",0
	db	8,15,"##..#.#.#..#.#..#.###.##.",0
	db	9,15,"#.#.#.#.##.#.##.#.#...#.#",0
	db	10,15,"##..#.#.#.##.#.##.##..##.",0
	db	11,15,"#.#.#.#.#..#.#..#.#...#.#",0
	db	12,15,"#.#.###.#..#.#..#.###.#.#",0
	db	14,20,"..........H.........",0
	db	15,20,"..&...$...H...$..0..",0
	db	16,20,"######.###########@@",0
	db	0FFh
t_text:
	db	18,18,"THE 150 STAGES AND RULES OF LODE RUNNER 1983",0
	db	19,26,"FOR THE MAX-80 UNDER XCPMZ80",0
	db	23,FCOL,"ENTER: PLAY  S: CHOOSE A STAGE  ESC: QUIT",0
	db	0FFh
t_codes: db	'#',G_BRICK,'@',G_SOLID,'H',G_LADDER,'$',G_GOLD
	db	'&',G_PLAYER,'0',G_GUARD,0
m_high:	db	"HIGH SCORE ",0

m_phelp: db	"ARROWS: RUN  Z/X RET/DEL: DIG  P: PAUSE  F1: GIVE UP",0
m_paused: db	"PAUSED  P: GO ON  ESC: BACK TO THE LEVELS",0
m_over:	db	"GAME OVER  ENTER OR ESC: BACK TO THE TITLE",0
m_score: db	"SCORE ",0
m_men:	db	"MEN ",0

	include	"glyphs.inc"
	ifdef	TEST
	include	"testlevels.inc"
	else
	include	"levels.inc"
	endif
blank8:	ds	8

ccpsp:	dw	0
vlsave:	db	0
vstart:	dw	0		; the screen start's place in video RAM, 000h-7FFh
vc_win:	db	0
vc_left: dw	0
drawrow: db	ROWS		; the next row drawsome copies
held:	db	0
press:	db	0
vheld:	db	0
vpress:	db	0
level:	db	0		; 1 on
inplay:	db	0		; nonzero in play
pairs:	dw	0
rkeys:	db	0		; the keys for this round
self:	dw	0		; the actor moving
isguard: db	0		; nonzero when it is a guard
started: db	0		; the ticks are being counted
tseen:	db	0		; tcount when last read
rtick:	db	0		; into the round, in ROUNDQ parts
vecad:	dw	0		; the tick vector's address
nbuild:	db	0		; figures still to build this frame
fbase:	dw	0		; the glyphs being built
fpx:	db	0		; its left edge in dots, the low byte
fpy:	db	0		; its top in lines
fshift:	db	0		; dots into the cell
fl:	db	0		; the figure row's line
ff:	ds	3		; a figure row moved right, then its mask
fm:	ds	3
ngold:	db	0
pcol:	db	0
prow:	db	0
nguard:	db	0
guards:	dw	0
caught:	db	0		; nonzero when a hole filled on the runner
digh:	dw	0		; the hole being dug
digrow:	db	0		; its tile
digcol:	db	0
rfall:	db	0		; nonzero when the runner falls
lives:	db	0
score:	ds	4		; BCD, the lowest two digits first
hiscore: ds	4		; the best this run
stchg:	db	0		; nonzero: rows 22 and 23 to be copied
paused:	db	0
capsave: db	0		; the kernel's Caps Lock when the game began
ovwait:	db	0		; frames GAME OVER still ignores ENTER
tapped:	db	0		; keys down at all since the last round
prevk:	db	0		; the last round's keys
lastdir: db	0		; the direction pressed last
moving:	db	0		; nonzero once a key has moved the runner
entfree: db	0		; nonzero once ENTER has been up in this stage
won:	db	0		; nonzero: the stage done
revealed: db	0		; nonzero: the hidden ladders shown
tqin:	db	0		; the tile queue's ends (gold.asm)
tqout:	db	0
seed:	dw	0ACE1h		; random's
tqueue:	ds	TQSIZE*2	; each a tile row and column
difficulty: db	0		; 0 to 10, up each time round the stages
moveoff: db	0		; the round in 6 of the guards' moves
moveid:	db	0		; the guard whose turn it is, 0 on
birthcol: db	0		; where the next guard comes back
rbcnt:	dw	0
cotry:	db	0
rpx:	dw	0		; the runner's place in eighths, across and down
best:	db	0		; the chase: the way found so far
bestr:	db	0		; and its rating
spath:	db	0		; the way being rated
sx:	db	0		; the guard's place
sy:	db	0
sleft:	db	0		; the ends of its row it can reach
sright:	db	0
gowed:	db	0		; guard moves the round still owes (guards.asm)
gpend:	db	0		; the round's touch and stage check still to do
fmoves:	db	0		; guard moves made this frame
nhlad:	db	0		; hidden ladders in the stage (gold.asm)
hlad:	ds	2*MAXHLAD	; each its row and column
ucol:	db	0		; unpack: tiles left in the row
sfptr:	dw	0		; the chase: the guard's place in tiles
sfcol:	dw	0		; colp: the column's place in tiles

; The buffers, after the end of the file, so the .COM does not carry them.
; tiles is the field with a border, 18 rows of TROW bytes on a page
; boundary: row 0 empty, above the field, then the field's 16 rows, each
; a solid column, its 28 tiles and 3 solid columns, then a solid row
; below it. Tile row B, column C is at tiles + (B+1)*TROW + C+1, so the
; place comes from shifts (actors.asm, tileptr). SOFF bytes on from each
; tile is its stand byte, 1 when a body there is held up or on a bar,
; for the chase (actors.asm, standfix), 0 in the border. rulet, on a page
; boundary too, gives each kind as the rules see it. flagt gives each
; kind as the F_ flags the chase tests.
endcom:
rulet	equ	(endcom+255) & 0FF00h
flagt	equ	rulet+256
tiles	equ	flagt+256
scrbuf	equ	tiles+(FROWS+2)*TROW
f1save	equ	scrbuf+ROWS*COLS	; font RAM 1
f2save	equ	f1save+400h		; font RAM 2, rows 0-7
actors	equ	f2save+200h		; the runner, 5 guards and the end mark
holes	equ	actors+7*ASIZE		; the hole table (holes.asm)
stack	equ	holes+NHOLES*HSIZE+128
	assert	stack <= TSTUB
	assert	G_FIG+6*6 <= 0C0h
