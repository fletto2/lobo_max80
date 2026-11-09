; Added for xcpmz80: VI's side of the page module, ../page/page.h,
; in Z80 code as page.s is, to leave VI a bigger window.
;
; A file bigger than the memory is edited through a window of its lines,
; the list from Filemem to Fileend. Each line carries the tag of its part
; of the window, 0 for a line made since the last call of the module.
; Before each call new lines get the tag of the line above them, or of
; the first line below, and their part is marked changed. CHANGED marks
; the parts of the cursor's line and of the line above it, delline and
; dosub the parts of the lines they change. Line numbers count the lines
; above the window (cntllines).
;
; While an operator waits for its motion, or a range is read, the window
; stays put (pgfixed). A motion or a line past it sets pgbig, and the
; command says so and does nothing.
;
; __sdcccall(0) (__LIB) calls, as in page.s: the arguments on the stack, a char as
; one byte, the caller pops them. A char comes back in L, an int or a
; pointer in HL, a long in DEHL. __z88dk_fastcall takes its one argument
; in HL or L. IX is kept.

	.module	vpage

L_PREV	= 2			; struct line
L_S	= 4
L_TAG	= 10
LSZ	= 11			; its size
NP	= 48			; page.s: pieces
PSZ	= 8			; a PIECE
RESERVE	= 768			; memory left free for the editing

	.globl	_Filetop_s, _Filemem_s, _Fileend_s, _Curschar_s, _Topchar_s
	.globl	_Botchar_s, _NumLineSizes, _MustUpdateBotchar, _Changed
	.globl	_Rows, _IObuff
	.globl	_renum, _newline, _clrmark, _freetext, _free, _malloc, _emsg
	.globl	_msg, _freeall, _filealloc, ___heapfree, _nextline, _prevline
	.globl	_gotoline, _cntllines, _sprintf
	.globl	_pg_open, _pg_slide, _pg_free, _pg_touch, _pg_newtag, _pg_goto
	.globl	_pg_above, _pg_save, _pg_na, _pg_nb, _pg_on, _pg_err, _pg_rows
	.globl	_pg_tab
	.globl	_ed_end, _ed_step, _ed_tag, _ed_text, _ed_begin, _ed_add
	.globl	_ed_drop
	.globl	_pgfixed, _pgbig, _pgchanged, _pgopen, _pgcheck, _pgcur, _pgtop
	.globl	_pgnext, _pgfree, _pgload, _pggoto, _pgtotal, _pgsave, _pgfrom
	.globl	_pgfromline, _pgback, _pglo, _pghi

	.area	_DATA
_pgfixed:	.ds	1	; the window must not move
_pgbig:		.ds	1	; it would have had to
_pglo:		.ds	2	; the lines a command works on, while it is
_pghi:		.ds	2
anchor:		.ds	2	; ed_add puts lines before it
dl:		.ds	2	; ed_drop: the line
dto:		.ds	2	; and where the cursor goes
bt:		.ds	1	; before: the tag above
vkeep:		.ds	2	; slide
vres:		.ds	1	; what the module gave back
nline:		.ds	2	; need
ncnt:		.ds	2
ndown:		.ds	1
xdown:		.ds	1	; pgnext
xp:		.ds	4
gn:		.ds	2	; pggoto
gl:		.ds	4
sv:		.ds	4	; pgsave
slides:		.ds	2	; the window moved, so many times
cslides:	.ds	2	; pgcheck
fromline:	.ds	2	; where a search started
fromidx:	.ds	2
fromsl:		.ds	2

	.area	_CODE

; ---- Lines ----

; HL a line, A not 0: its next line, else the one before it
link:	or	a
	jr	nz,1$
	inc	hl
	inc	hl
1$:	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ret

; the same, but HL 0 and Z when that is Filetop or Fileend
nbr:	call	link
; HL a line: HL 0 and Z when it is Filetop or Fileend, which have a
; pointer 0. DE and BC are kept
real:	ld	a,(hl)
	inc	hl
	or	(hl)
	jr	z,1$
	inc	hl
	ld	a,(hl)
	inc	hl
	or	(hl)
	dec	hl
	dec	hl
1$:	dec	hl
	ret	nz
	ld	hl,#0
	ret

; HL a line: A its tag, Z when 0. HL and BC are kept
tagof:	push	hl
	ld	de,#L_TAG
	add	hl,de
	ld	a,(hl)
	pop	hl
	or	a
	ret

; the first line, or Fileend when there is none
first:	ld	hl,(_Filetop_s)
	ld	a,#1
	jr	link

; ---- The lines, for the module ----

_ed_end:
	ld	hl,#2
	add	hl,sp
	ld	a,(hl)
	or	a
	ld	hl,(_Filetop_s)
	jr	z,1$
	ld	hl,(_Fileend_s)	; the last: the one before Fileend
	xor	a
	jr	nbr
1$:	inc	a		; the first: the one after Filetop
	jr	nbr

_ed_step:
	ld	hl,#4
	add	hl,sp
	ld	a,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	l,(hl)
	ld	h,d
	jr	nbr

_ed_tag:
	pop	bc
	pop	hl
	push	hl
	push	bc
	call	tagof
	ld	l,a
	ret

_ed_text:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)		; DE the line
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	push	bc		; n
	ld	hl,#L_S
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)		; DE its text
	ld	h,d
	ld	l,e
	xor	a
	ld	b,a
	ld	c,a
	cpir			; HL past the NUL
	scf
	sbc	hl,de		; the length
	ex	de,hl
	ex	(sp),hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	pop	hl		; the text
	ret

_ed_begin:
	ld	hl,#2
	add	hl,sp
	ld	a,(hl)
	or	a
	ld	hl,(_Fileend_s)
	call	z,first		; at the top: before the first line
	ld	(anchor),hl
	ret

; as newline(), without alloc()'s message and its call of pgfree()
_ed_add:
	push	ix
	ld	ix,#0
	add	ix,sp
	ld	l,6(ix)
	ld	h,7(ix)
	ld	de,#LSZ+1
	add	hl,de
	push	hl
	call	_malloc
	pop	af
	ld	a,h
	or	l
	jr	z,9$		; no memory: 0
	ex	de,hl		; DE the line
	ld	hl,(anchor)
	push	hl
	inc	hl
	inc	hl
	ld	c,(hl)
	ld	(hl),e
	inc	hl
	ld	b,(hl)		; BC the line before anchor
	ld	(hl),d		; anchor->prev = l
	ld	h,b
	ld	l,c
	ld	(hl),e
	inc	hl
	ld	(hl),d		; before->next = l
	ex	de,hl
	pop	de
	ld	(hl),e
	inc	hl
	ld	(hl),d		; l->next = anchor
	inc	hl
	ld	(hl),c
	inc	hl
	ld	(hl),b		; l->prev = before
	inc	hl
	push	hl
	ld	de,#LSZ-L_S
	add	hl,de
	ex	de,hl		; DE the text, after the struct
	pop	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d		; l->s
	inc	hl
	ld	c,6(ix)
	ld	b,7(ix)
	inc	bc
	ld	(hl),c
	inc	hl
	ld	(hl),b		; l->size = n + 1
	inc	hl
	inc	hl
	inc	hl
	ld	a,8(ix)
	ld	(hl),a		; l->tag
	ld	l,4(ix)
	ld	h,5(ix)
	push	bc
	ldir			; the text and its NUL
	pop	hl
	ld	de,#LSZ+2	; the cost: the block and its header
	add	hl,de
9$:	pop	ix
	ret

; HL an LPtr: Z, and its line dto, when its line is dl
moved:	ld	de,(dl)
	ld	a,(hl)
	cp	e
	ret	nz
	inc	hl
	ld	a,(hl)
	cp	d
	dec	hl
	ret	nz
	ld	de,(dto)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ret

; a line leaves: the cursor and the screen move toward the window, and
; marks on it go. after() has the screen drawn again
_ed_drop:
	ld	hl,#4
	add	hl,sp
	ld	a,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	l,(hl)
	ld	h,d
	ld	(dl),hl
	sub	#1
	sbc	a,a		; A not 0 when not down: after it
	call	link
	ld	(dto),hl
	ld	hl,#_Curschar_s
	call	moved
	jr	nz,1$
	ld	hl,#0
	ld	(_Curschar_s+2),hl
1$:	ld	hl,#_Topchar_s
	call	moved
	ld	hl,#_Botchar_s
	call	moved
	ld	hl,(dl)
	push	hl
	call	_clrmark
	pop	af
	ld	hl,(dl)
	ld	e,(hl)
	inc	hl
	ld	d,(hl)		; DE its next
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)		; BC the one before
	ld	a,e
	ld	(bc),a
	inc	bc
	ld	a,d
	ld	(bc),a		; prev->next = next
	dec	bc
	ex	de,hl
	inc	hl
	inc	hl
	ld	(hl),c
	inc	hl
	ld	(hl),b		; next->prev = prev
	ld	hl,(dl)
	push	hl
	call	_freetext
	pop	af
	ld	hl,(dl)
	push	hl
	call	_free
	pop	af
	ret

; ---- Around each call of the module ----

; new lines get the tag above them, the first the tag of a line below
; it or a new one, and their part is marked changed
before:	xor	a
	ld	(bt),a
	ld	hl,(_Filemem_s)
1$:	call	real
	ret	z
	call	tagof
	jr	nz,4$
	ld	a,(bt)
	or	a
	jr	nz,3$
	push	hl
2$:	ld	a,#1
	call	nbr
	jr	z,21$
	call	tagof
	jr	z,2$
	jr	22$
21$:	call	_pg_newtag
	ld	a,l
22$:	pop	hl
3$:	push	hl
	ld	de,#L_TAG
	add	hl,de
	ld	(hl),a
	ld	l,a
	call	_pg_touch
	pop	hl
	call	tagof
4$:	ld	(bt),a
	ld	a,#1
	call	link
	jr	1$

; the window as the module left it: never empty, the cursor and the top
; of the screen in it, the lines numbered, an error said, the screen to
; be drawn again
after:	call	attach
	ld	hl,(slides)
	inc	hl
	ld	(slides),hl
	ld	hl,#-1
	ld	(_NumLineSizes),hl	; S_NOT_VALID: the screen drawn again
	ld	hl,#1
	ld	(_MustUpdateBotchar),hl
	ret
; The list's ends and positions set again, for a save, which moves no line
attach:	call	first
	ld	de,(_Fileend_s)
	or	a
	sbc	hl,de
	add	hl,de
	jr	nz,1$
	ld	hl,#1		; empty: an empty line
	push	hl
	call	_newline
	pop	af
	ex	de,hl
	ld	hl,(_Fileend_s)
	push	hl
	inc	hl
	inc	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ld	hl,(_Filetop_s)
	push	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ex	de,hl
	pop	bc
	pop	de
	push	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(hl),c
	inc	hl
	ld	(hl),b
	pop	hl
1$:	ld	(_Filemem_s),hl
	ld	hl,#_Curschar_s
	call	inwin
	ld	hl,#_Topchar_s
	call	inwin
	call	_renum
	ld	hl,(_pg_err)
	ld	a,h
	or	l
	jr	z,2$
	push	hl
	call	_emsg
	pop	af
	ld	hl,#0
	ld	(_pg_err),hl
2$:	ret

; HL an LPtr: on Filemem when its line is not in the window
inwin:	push	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	call	real
	pop	de
	ret	nz
	ld	hl,#_Filemem_s
	ld	bc,#4
	ldir
	ret

; A down, HL the line to keep: the window slides. A not 0 and NZ if it did
slide:	ld	(vkeep),hl
	ld	(vres),a
	call	before
	ld	hl,(vkeep)
	push	hl
	ld	a,(vres)
	push	af
	inc	sp
	call	_pg_slide
	pop	af
	inc	sp
done:	ld	a,l
	ld	(vres),a
	call	after
	ld	a,(vres)
	ld	l,a
	or	a
	ret

; HL a line at the edge of the window, A down: the window slides past
; it, NZ if there are lines past it now. While the window is fixed lines
; only come in, none go, and when there is no memory for them pgbig is set
more:	ld	c,a
	or	a
	ld	a,(_pg_nb)
	jr	nz,1$
	ld	a,(_pg_na)
1$:	or	a
	ret	z
	ld	a,(_pgfixed)
	or	a
	ld	a,c
	jr	z,slide
	ld	a,#255
	ld	(_pg_rows),a	; no part this near the line goes
	ld	a,c
	call	slide
	ret	nz
	ld	a,#1
	ld	(_pgbig),a
	xor	a
	ret

; HL a line, BC n, A down: n lines past it, when the file has them
need:	ld	(nline),hl
	ld	(ncnt),bc
	ld	(ndown),a
1$:	ld	hl,(nline)
	ld	bc,(ncnt)
2$:	ld	a,b
	or	c
	ret	z
	ld	a,(ndown)
	call	nbr
	jr	z,3$
	dec	bc
	jr	2$
3$:	ld	hl,(nline)
	ld	a,(ndown)
	call	more
	jr	nz,1$
	ret

; ---- VI's calls ----

; CHANGED: the parts of the cursor's line and of the line above it
_pgchanged:
	ld	a,#1
	ld	(_Changed),a
	ld	hl,(_Curschar_s)
	push	hl
	call	tagof
	ld	l,a
	call	_pg_touch
	pop	hl
	xor	a
	call	link
	call	tagof
	ld	l,a
	jp	_pg_touch

; pgopen(fname): the file read through a window, as it did not fit. What
; was read is freed first. 0 if the file cannot be opened
_pgopen:
	call	_freeall
	call	_filealloc
	ld	hl,(_Filemem_s)
	push	hl
	call	_free		; the empty line
	pop	af
	ld	hl,(_Fileend_s)
	ld	de,(_Filetop_s)
	ld	(_Curschar_s),hl
	ld	(_Topchar_s),hl
	ex	de,hl
	ld	(hl),e
	inc	hl
	ld	(hl),d		; Filetop->next = Fileend
	dec	hl
	ex	de,hl
	inc	hl
	inc	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d		; Fileend->prev = Filetop
	ld	hl,#0x7FF0
	push	hl
	call	_malloc		; fails, but joins the free blocks
	pop	af
	call	___heapfree
	ld	de,#-RESERVE
	add	hl,de
	jr	c,1$
	ld	hl,#0
1$:	push	hl		; the window's budget
	ld	hl,#4
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	push	de
	call	_pg_open
	pop	af
	pop	af
	ld	a,l
	or	a
	jr	z,2$
	call	screen
	ld	hl,#0
	call	_pg_goto
	ld	l,#1
2$:	jp	done

; pgcheck(): the lines the screen shows from Topchar in the window, and
; one more below the cursor, and one above it. When the cursor is not on
; the screen it is taken as half way down. The window keeps the screen's
; lines on the side it leaves. Called before the screen is drawn, and
; after, as drawing it may move Topchar. Not 0 if the window moved
_pgcheck:
	ld	hl,(slides)
	ld	(cslides),hl
	ld	a,(_pg_on)
	or	a
	jr	z,9$
	call	screen
	ld	b,a		; Rows - 1
	ld	c,#0		; the lines from Topchar to the cursor
	ld	hl,(_Topchar_s)
	ld	de,(_Curschar_s)
1$:	or	a
	sbc	hl,de
	add	hl,de
	jr	z,3$
	ld	a,c
	cp	b
	jr	z,2$
	inc	c
	ld	a,#1
	call	nbr
	jr	nz,1$
2$:	ld	a,b		; not on the screen
	srl	a
	ld	c,a
3$:	ld	a,c
	ld	(_pg_rows),a
	ld	a,b
	sub	c
	inc	a
	push	bc
	ld	c,a
	ld	b,#0
	ld	hl,(_Curschar_s)
	ld	a,#1
	call	need		; below
	pop	bc
	ld	a,b
	sub	c
	ld	(_pg_rows),a
	ld	bc,#1
	ld	hl,(_Curschar_s)
	xor	a
	call	need		; above
9$:	ld	hl,(slides)
	ld	de,(cslides)
	or	a
	sbc	hl,de
	ld	a,h
	or	l
	ld	l,a
	ret

; pgcur(down): the cursor's line is at the edge of the window, the window
; slides. Not 0 if there are lines past it now
_pgcur:	push	hl
	call	screen
	pop	af
	ld	hl,(_Curschar_s)
	call	more
	ld	l,a
	ret

; pg_rows a screen's lines, Rows - 1. A too
screen:	ld	a,(_Rows)
	dec	a
	ld	(_pg_rows),a
	ret

; pgtop(n): n lines below Topchar, or -n above it. The screen moves that
; way, so of the lines on the other side of Topchar the window keeps none
; when it moves down, and those left on the screen when it moves up
_pgtop:	ld	b,h
	ld	c,l
	ld	a,h
	rla
	jr	c,1$
	xor	a
	ld	(_pg_rows),a
	inc	a		; down
	jr	2$
1$:	call	screen
	add	a,c		; Rows - 1 - n
	jr	c,3$
	xor	a
3$:	ld	(_pg_rows),a
	xor	a
	ld	h,a
	ld	l,a
	sbc	hl,bc		; -n
	ld	b,h
	ld	c,l		; up
2$:	ld	hl,(_Topchar_s)
	jp	need

; pgnext(p, down): the line after p, or before it, the window slid for
; it when it must be. 0 at the end of the file
_pgnext:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	ld	(xdown),a
	xor	a
	ld	(_pg_rows),a	; only the line searched is kept
	ex	de,hl
	ld	de,#xp
	ld	bc,#4
	ldir
	call	xnext
	ld	a,h
	or	l
	ret	nz
	ld	hl,(xp)
	ld	a,(xdown)
	call	more
	jr	nz,xnext
	ld	hl,#0
	ret
xnext:	ld	hl,#xp
	push	hl
	ld	a,(xdown)
	or	a
	jr	z,1$
	call	_nextline
	jr	2$
1$:	call	_prevline
2$:	pop	af
	ret

; pgfree(): alloc() found no memory, a part out of memory: one a screen
; away from the cursor, or while the window is fixed one outside the lines
; from pglo to pghi, which the command works on. Not 0 if one went
_pgfree:
	ld	a,(_pg_on)
	or	a
	jr	z,9$
	ld	a,(_pgfixed)
	or	a
	jr	nz,1$
	call	screen
	ld	hl,(_Curschar_s)
	jr	5$
1$:	ld	hl,(_pglo)	; kept: the middle line, and half of them each way
	ld	a,h
	or	l
	jr	z,8$
	ld	de,(_pghi)
	ld	bc,#0
2$:	or	a
	sbc	hl,de
	add	hl,de
	jr	z,3$
	inc	bc
	ld	a,#1
	call	nbr
	jr	nz,2$
	jr	8$
3$:	srl	b
	rr	c
	ld	a,c
	inc	a
	ld	(_pg_rows),a
	ld	hl,(_pglo)
4$:	ld	a,b
	or	c
	jr	z,5$
	dec	bc
	ld	a,#1
	call	link
	jr	4$
5$:	push	hl
	call	before
	pop	hl
	call	_pg_free
	jp	done
8$:	xor	a
9$:	ld	l,a
	ret

; pgload(): the window has one line left, and the file more: a part more
_pgload:
	ld	a,(_pg_nb)
	ld	hl,#_pg_na
	or	(hl)
	ret	z
	ld	a,(_pg_nb)
	or	a
	jr	z,1$
	ld	a,#1
1$:	ld	hl,(_Curschar_s)
	jp	slide

; pggoto(n): line n of the file, 1 the first, 0 the last, when it is not
; in the window: the window loaded there. 0 when it is in the window.
; While the window is fixed, the cursor, and pgbig set
_pggoto:
	ld	a,(_pg_on)
	or	a
	jr	z,9$
	ld	a,h
	or	l
	jr	nz,1$
	dec	hl		; the last: FFFFh
1$:	ld	(gn),hl
	ld	a,(_pg_na)
	or	a
	jr	z,2$
	call	_pg_above
	ld	de,(gn)
	or	a
	sbc	hl,de
	jr	nc,3$		; at or above the window's top
2$:	ld	a,(_pg_nb)
	or	a
	jr	z,9$
	call	lines
	ld	de,(gn)
	ex	de,hl
	or	a
	sbc	hl,de
	jr	c,9$		; in the window
3$:	ld	hl,#_Curschar_s
	ld	de,#gl
	ld	bc,#4
	ldir
	ld	a,(_pgfixed)
	or	a
	jr	z,4$
	ld	(_pgbig),a
	ld	hl,#gl
	ret
4$:	call	screen
	call	before
	ld	hl,(gn)
	dec	hl
	call	_pg_goto
	ld	(gl),hl
	call	after
	ld	hl,(gl)
	ld	a,h
	or	l
	jr	nz,5$
	ld	hl,(_Fileend_s)	; at the end: the last line
	xor	a
	call	link
5$:	ld	(gl),hl
	ld	hl,#0
	ld	(gl+2),hl
	ld	hl,#gl
	ret
9$:	ld	hl,#0
	ret

; HL: cntllines(Filemem, Fileend), the window's last line and one
lines:	ld	hl,#_Fileend_s
	push	hl
	ld	hl,#_Filemem_s
	push	hl
	call	_cntllines
	pop	af
	pop	af
	ret

; pgtotal(): the lines of the file. pg_goto() at the open counted them,
; a piece not counted (FFFFh) would be taken as none
_pgtotal:
	call	lines
	dec	hl
	ld	a,(_pg_nb)
	or	a
	ret	z
	ex	de,hl
	ld	b,a
	ld	hl,#_pg_tab+NP*PSZ-2	; the furthest piece below: its nl
1$:	ld	a,(hl)
	inc	hl
	push	hl
	ld	h,(hl)
	ld	l,a
	inc	hl
	ld	a,h
	or	l
	jr	z,2$
	dec	hl
	add	hl,de
	ex	de,hl
2$:	pop	hl
	ld	a,l
	sub	#PSZ+1
	ld	l,a
	jr	nc,3$
	dec	h
3$:	djnz	1$
	ex	de,hl
	ret

; pgsave(fname, bak): the whole file written to fname, the old one kept
; as .BAK if bak. Not 0 if it was
_pgsave:
	call	before
	ld	hl,#4
	add	hl,sp
	ld	a,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	e,(hl)
	push	af
	inc	sp
	push	de
	call	_pg_save
	pop	af
	inc	sp
	ld	(sv),hl
	ld	(sv+2),de
	call	attach
	ld	a,(sv+3)
	rlca
	ld	l,#0
	ret	c		; -1: not written
	ld	hl,(sv+2)
	push	hl
	ld	hl,(sv)
	push	hl
	ld	hl,#6
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	push	de
	ld	hl,#wrote
	push	hl
	ld	hl,(_IObuff)
	push	hl
	call	_sprintf
	ld	hl,#10
	add	hl,sp
	ld	sp,hl
	ld	hl,(_IObuff)
	push	hl
	call	_msg
	pop	af
	xor	a
	ld	(_Changed),a
	ld	l,#1
	ret
wrote:	.db	0x22
	.ascii	"%s"
	.db	0x22
	.ascii	" %ld lines"
	.db	0

; pgfrom(): a search starts where the cursor is. pgback(): it failed, the
; cursor back there, if the window slid
_pgfrom:
	ld	hl,#_Curschar_s
	push	hl
	ld	hl,#_Filemem_s
	push	hl
	call	_cntllines
	pop	af
	pop	af
	ld	(fromline),hl
	ld	hl,(_Curschar_s+2)
	ld	(fromidx),hl
	ld	hl,(slides)
	ld	(fromsl),hl
	ret

_pgfromline:
	ld	hl,(fromline)
	ret

_pgback:
	ld	hl,(slides)
	ld	de,(fromsl)
	or	a
	sbc	hl,de
	ret	z
	ld	hl,(fromline)
	push	hl
	call	_gotoline
	pop	af
	ld	de,#_Curschar_s
	ld	bc,#2
	ldir
	ld	hl,(fromidx)
	ld	(_Curschar_s+2),hl
	ret
