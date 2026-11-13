; The page module in Z80 assembly, for the editors: page.c, which
; the host test checks, line for line. Compiled, page.c is 5.8K of code,
; this is 3.7K. The same functions, variables and layout as page.c
; and page.h, with PG_NP 48, PG_NPART 16 and PG_PARTSZ 512.
;
; The library's calls, __sdcccall(0) (__LIB): the arguments on the stack, a char as one byte, the
; caller pops them. A char comes back in L, an int or pointer in HL, a
; long in DEHL. __z88dk_fastcall takes its one argument in HL or L. IX
; is kept. Inside, the functions give A, and Z when it is 0.

	.module	page

NP	= 48			; pieces
NPART	= 16			; parts in the window
PARTSZ	= 512			; bytes of the file a part
PRECS	= 4			; PARTSZ / 128
LINEMAX	= 256			; the longest line
WORK	= 0x80			; in o: the work file
; PIECE
P_R	= 0
P_O	= 2
P_ER	= 3
P_EO	= 5
P_NL	= 6
PSZ	= 8
; PART
T_COST	= 8
T_TAG	= 10
T_DIRTY	= 11
TSZ	= 12

	.globl	_pg_tab, _pg_part, _pg_na, _pg_nb, _pg_np, _pg_budget
	.globl	_pg_cost, _pg_rows, _pg_on, _pg_line, _pg_err
	.globl	_pg_open, _pg_close, _pg_slide, _pg_free, _pg_touch
	.globl	_pg_newtag, _pg_goto, _pg_above, _pg_save
	.globl	_ed_end, _ed_step, _ed_tag, _ed_text, _ed_begin, _ed_add
	.globl	_ed_drop, _remove, _rename

	.area	_DATA
_pg_tab:	.ds	NP*PSZ
_pg_part:	.ds	NPART*TSZ
_pg_na:		.ds	1
_pg_nb:		.ds	1
_pg_np:		.ds	1
_pg_budget:	.ds	2
_pg_cost:	.ds	2
_pg_rows:	.ds	1	; set by the editor
_pg_on:		.ds	1
_pg_line:	.ds	LINEMAX+1
_pg_err:	.ds	2
fname:	.ds	16		; the file
wname:	.ds	16		; the work file
ofcb:	.ds	36
wfcb:	.ds	36
sfcb:	.ds	36
pfcb:	.ds	4		; for function 152
w_open:	.ds	1
pc:	.ds	PSZ		; a piece being made
pt:	.ds	2		; the part at hand
dn:	.ds	1		; the side: 1 below
tg:	.ds	1		; a part's tag
lasttag: .ds	1
rbuf:	.ds	128
r_rec:	.ds	2		; the record in rbuf, FFFFh none
r_w:	.ds	1
s_rec:	.ds	2		; the stream
s_er:	.ds	2
s_p:	.ds	2
s_n:	.ds	1
s_eo:	.ds	1
s_w:	.ds	1
s_raw:	.ds	2
s_lf:	.ds	1
cp:	.ds	1
cnt:	.ds	2
wbuf:	.ds	128
w_fcb:	.ds	2
w_rec:	.ds	2
w_n:	.ds	1
w_bad:	.ds	1
wk_rec:	.ds	2
wk_n:	.ds	1
tlen:	.ds	2		; wlines
wl:	.ds	2
wcnt:	.ds	2
lp:	.ds	2		; load
lcost:	.ds	2
lused:	.ds	2
lnl:	.ds	2
lsr:	.ds	2
lso:	.ds	1
ekeep:	.ds	2		; evict
ecnt:	.ds	1
eline:	.ds	2
sdown:	.ds	1		; pg_slide
skeep:	.ds	2
fk:	.ds	2		; fill
gn:	.ds	2		; pg_goto
ga:	.ds	2
gp:	.ds	2
gk:	.ds	2
gt:	.ds	2
obud:	.ds	2		; pg_open
cpn:	.ds	1		; pg_save
cpp:	.ds	2
sl:	.ds	2
spn:	.ds	1
stotal:	.ds	2
ab:	.ds	PSZ
snew:	.ds	NPART*PSZ	; pg_save: the parts' new pieces
snp:	.ds	2
sname:	.ds	2
sbak:	.ds	1
tmp:	.ds	16

	.area	_CODE

true:	ld	a,#1
	or	a
	ret
false:	xor	a
	ret

; ---- BDOS ----

; A function, DE the FCB, HL the record, BC the buffer or 0
pgbdos:	push	af
	push	hl
	push	de
	ld	a,b
	or	c
	jr	z,1$
	ld	e,c
	ld	d,b
	ld	c,#26
	call	bdos5
1$:	pop	hl		; the FCB
	pop	de		; the record
	push	hl
	ld	bc,#33
	add	hl,bc
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(hl),#0
	pop	de
	pop	af
	ld	c,a
bdos5:	push	ix
	push	iy
	call	5
	pop	iy
	pop	ix
	ret

; DE the FCB: closed
close:	ld	hl,#0
	ld	b,h
	ld	c,l
	ld	a,#16
	jr	pgbdos

; HL a name: removed
rm:	push	hl
	call	_remove
	pop	af
	ret

; ---- Names ----

; HL name, DE out, BC type: name to its '.', then '.' and type
mkname:	push	bc
	ld	b,#10
1$:	ld	a,(hl)
	or	a
	jr	z,2$
	cp	#0x2E
	jr	z,2$
	ld	(de),a
	inc	hl
	inc	de
	djnz	1$
2$:	ld	a,#0x2E
	ld	(de),a
	inc	de
	pop	hl
3$:	ld	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	or	a
	jr	nz,3$
	ret

; HL name, DE the FCB: made by function 152
mkfcb:	ld	(pfcb),hl
	ld	(pfcb+2),de
	ld	h,d
	ld	l,e
	ld	(hl),#0
	inc	de
	ld	bc,#35
	ldir
	ld	de,#pfcb
	ld	c,#152
	jr	bdos5

; HL name: the file's and the work file's names and FCB
named:	push	hl
	ld	hl,#fname
	ld	de,#fname+1
	ld	(hl),#0
	ld	bc,#15
	ldir
	pop	hl
	ld	de,#fname
	ld	b,#15
1$:	ld	a,(hl)
	or	a
	jr	z,2$
	ld	(de),a
	inc	hl
	inc	de
	djnz	1$
2$:	ld	hl,#fname
	ld	de,#wname
	ld	bc,#t_w
	call	mkname
	ld	hl,#fname
	ld	de,#ofcb
	call	mkfcb
	ld	hl,#0xFFFF
	ld	(r_rec),hl
	ret

; ---- Calls to the editor ----

; HL a line: A its tag, HL kept
tagof:	push	hl
	call	_ed_tag
	ld	a,l
	pop	hl
	ret

; HL a line, A the way: HL the next line that way, or 0
stepl:	push	af
	inc	sp
	push	hl
	call	_ed_step
	pop	af
	inc	sp
	ret

; A the way: HL the line at that end, or 0
endl:	push	af
	inc	sp
	call	_ed_end
	inc	sp
	ret

; HL a line: Z if it is 0 or its tag is not tg
istg:	ld	a,h
	or	l
	ret	z
	call	tagof
	push	hl
	ld	hl,#tg
	cp	(hl)
	pop	hl
	jp	nz,false
	jp	true

; ---- The stream over a piece ----

; HL the piece
sopen:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	(s_rec),de
	ld	a,(hl)
	inc	hl
	ld	c,a
	and	#WORK
	ld	(s_w),a
	ld	a,c
	and	#127
	push	hl
	ld	e,a
	ld	d,#0
	ld	hl,#rbuf
	add	hl,de
	ld	(s_p),hl
	pop	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	(s_er),de
	ld	a,(hl)
	ld	(s_eo),a
	xor	a
	ld	(s_n),a
	ld	(s_lf),a
	ret

; the stream's place into pc's start
here:	ld	hl,(s_p)
	ld	de,#rbuf
	or	a
	sbc	hl,de
	ld	a,l
	ld	hl,(s_rec)
	cp	#128
	jr	nz,1$
	inc	hl
	xor	a
1$:	ld	(pc+P_R),hl
	ld	hl,#s_w
	or	(hl)
	ld	(pc+P_O),a
	ret

; the next part of the stream into rbuf: A 0 at its end
refill:	ld	hl,(s_p)
	ld	de,#rbuf
	or	a
	sbc	hl,de
	ld	a,l
	cp	#128
	jr	nz,1$
	ld	hl,(s_rec)
	inc	hl
	ld	(s_rec),hl
	ld	(s_p),de
	xor	a
1$:	ld	c,a		; where
	ld	hl,(s_rec)
	ld	de,(s_er)
	or	a
	sbc	hl,de
	ld	b,#128		; the end in this record
	jr	c,2$
	jp	nz,false
	ld	a,(s_eo)
	ld	b,a
2$:	ld	a,c
	cp	b
	jp	nc,false
	push	bc
	ld	hl,(r_rec)
	ld	de,(s_rec)
	or	a
	sbc	hl,de
	jr	nz,3$
	ld	a,(r_w)
	ld	hl,#s_w
	cp	(hl)
	jr	z,4$
3$:	ld	hl,#0xFFFF
	ld	(r_rec),hl
	ld	de,#ofcb
	ld	a,(s_w)
	or	a
	jr	z,5$
	ld	de,#wfcb
5$:	ld	hl,(s_rec)
	ld	bc,#rbuf
	ld	a,#33
	call	pgbdos
	or	a
	jr	nz,8$
	ld	hl,(s_rec)
	ld	(r_rec),hl
	ld	a,(s_w)
	ld	(r_w),a
4$:	pop	bc
	ld	a,b
	sub	c
	ld	(s_n),a
	jp	true
8$:	pop	bc
	ld	hl,#e_read
	ld	(_pg_err),hl
	jp	false

; the next line into pg_line, CR dropped: HL its length, FFFFh at the
; end. s_raw the bytes it took, s_lf whether LF ended it
sgetl:	ld	hl,#0
	ld	(s_raw),hl
	xor	a
	ld	(s_lf),a
	ld	de,#_pg_line
	ld	bc,#LINEMAX
1$:	ld	a,(s_n)
	or	a
	jr	nz,2$
	push	de
	push	bc
	call	refill
	pop	bc
	pop	de
	jr	z,7$
2$:	ld	hl,(s_p)
	ld	a,(hl)
	inc	hl
	ld	(s_p),hl
	ld	hl,#s_n
	dec	(hl)
	ld	hl,(s_raw)
	inc	hl
	ld	(s_raw),hl
	cp	#10
	jr	z,6$
	cp	#13
	jr	z,1$
	ld	l,a
	ld	a,b
	or	c
	jr	z,5$
	ld	a,l
	ld	(de),a
	inc	de
	dec	bc
	jr	1$
5$:	ld	hl,(s_p)	; too long: split before it, put back, so
	dec	hl		; a CR LF right after still ends the line
	ld	(s_p),hl
	ld	hl,#s_n
	inc	(hl)
	ld	hl,(s_raw)
	dec	hl
	ld	(s_raw),hl
	jr	7$
6$:	ld	a,#1
	ld	(s_lf),a
7$:	xor	a
	ld	(de),a
	ld	hl,(s_raw)
	ld	a,h
	or	l
	jr	z,8$
	ex	de,hl
	ld	de,#_pg_line
	or	a
	sbc	hl,de
	ret
8$:	ld	hl,#0xFFFF
	ret

; the stream's lines counted, saturated: HL. With cp set, copied to the
; writer too
scount:	ld	hl,#0
	ld	(cnt),hl
1$:	ld	a,(s_n)
	or	a
	jr	nz,2$
	call	refill
	jr	z,9$
2$:	ld	a,(cp)
	or	a
	jr	z,3$
	ld	hl,(s_p)
	ld	a,(s_n)
	ld	c,a
	ld	b,#0
	call	wput
3$:	ld	hl,(s_p)
	ld	a,(s_n)
	ld	b,a
	ld	de,(cnt)
4$:	ld	a,(hl)
	inc	hl
	cp	#10
	jr	nz,5$
	inc	de
	ld	a,d
	and	e
	inc	a
	jr	nz,5$
	dec	de
5$:	djnz	4$
	ld	(cnt),de
	ld	(s_p),hl
	xor	a
	ld	(s_n),a
	jr	1$
9$:	ld	hl,(cnt)
	ret

; ---- The writer ----

wflush:	ld	de,(w_fcb)
	ld	hl,(w_rec)
	ld	bc,#wbuf
	ld	a,#34
	call	pgbdos
	or	a
	jr	z,1$
	ld	a,#1
	ld	(w_bad),a
1$:	ld	hl,(w_fcb)
	ld	de,#wfcb
	or	a
	sbc	hl,de
	ret	nz
	ld	a,(r_w)
	or	a
	ret	z
	ld	hl,(r_rec)
	ld	de,(w_rec)
	or	a
	sbc	hl,de
	ret	nz
	ld	hl,#0xFFFF
	ld	(r_rec),hl
	ret

; HL the bytes, BC how many
wput:	ld	a,b
	or	c
	ret	z
	ld	a,(hl)
	inc	hl
	push	hl
	push	bc
	ld	hl,#w_n
	ld	e,(hl)
	inc	(hl)
	ld	d,#0
	ld	hl,#wbuf
	add	hl,de
	ld	(hl),a
	ld	a,(w_n)
	cp	#128
	jr	nz,1$
	call	wflush
	ld	hl,(w_rec)
	inc	hl
	ld	(w_rec),hl
	xor	a
	ld	(w_n),a
1$:	pop	bc
	pop	hl
	dec	bc
	jr	wput

; pc starts where the writer is
wstart:	ld	hl,(w_rec)
	ld	(pc+P_R),hl
	ld	hl,(w_fcb)
	ld	de,#wfcb
	or	a
	sbc	hl,de
	ld	a,(w_n)
	jr	nz,1$
	or	#WORK
1$:	ld	(pc+P_O),a
	ld	hl,#0
	ld	(pc+P_NL),hl
	ret

; and ends there, the last record written
wend:	ld	a,(w_n)
	or	a
	call	nz,wflush
	ld	hl,(w_rec)
	ld	(pc+P_ER),hl
	ld	a,(w_n)
	ld	(pc+P_EO),a
	ret

; HL a piece: copied to the writer, DE and its nl its lines
copy:	push	hl
	call	sopen
	ld	a,#1
	ld	(cp),a
	call	scount
	xor	a
	ld	(cp),a
	ex	de,hl
	pop	hl
	ld	bc,#P_NL
	add	hl,bc
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ret

; HL a line: it and the lines after it while their tag is tg written,
; CR LF after each. HL their count
wlines:	ld	de,#0
	ld	(wcnt),de
1$:	ld	(wl),hl
	call	istg
	jr	z,9$
	ld	hl,#tlen
	push	hl
	ld	hl,(wl)
	push	hl
	call	_ed_text
	pop	af
	pop	af
	ld	bc,(tlen)
	call	wput
	ld	hl,#crlf
	ld	bc,#2
	call	wput
	ld	hl,(wcnt)
	inc	hl
	ld	(wcnt),hl
	ld	hl,(wl)
	ld	a,#1
	call	stepl
	jr	1$
9$:	ld	hl,(wcnt)
	ret

; the writer on the work file's end, made the first time, pc started
wwork:	ld	a,(w_open)
	or	a
	jr	nz,1$
	ld	hl,#wname
	call	rm
	ld	hl,#wname
	ld	de,#wfcb
	call	mkfcb
	ld	de,#wfcb
	ld	hl,#0
	ld	b,h
	ld	c,l
	ld	a,#22
	call	pgbdos
	inc	a
	jr	nz,2$
	ld	hl,#e_work
	ld	(_pg_err),hl
	jp	false
2$:	ld	a,#1
	ld	(w_open),a
	ld	hl,#0
	ld	(wk_rec),hl
	xor	a
	ld	(wk_n),a
1$:	ld	hl,(w_fcb)
	ld	de,#wfcb
	or	a
	sbc	hl,de
	jr	z,3$
	ld	(w_fcb),de
	ld	a,(wk_n)
	or	a
	jr	z,3$
	ld	hl,(wk_rec)
	ld	bc,#wbuf
	ld	a,#33
	call	pgbdos
3$:	ld	hl,(wk_rec)
	ld	(w_rec),hl
	ld	a,(wk_n)
	ld	(w_n),a
	xor	a
	ld	(w_bad),a
	call	wstart
	jp	true

; the work file's piece ended in pc: A 0 if a write failed
wdone:	call	wend
	ld	a,(w_bad)
	or	a
	jr	z,1$
	ld	hl,#e_wwrite
	ld	(_pg_err),hl
	ld	hl,#0		; wbuf holds the failed bytes: read again
	ld	(w_fcb),hl
	jp	false
1$:	ld	hl,(w_rec)
	ld	(wk_rec),hl
	ld	a,(w_n)
	ld	(wk_n),a
	jp	true

; ---- The lists ----

; HL a piece: Z if it is empty
empty:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	and	#127
	ld	c,a
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	cp	e
	ret	nz
	ld	a,b
	cp	d
	ret	nz
	ld	a,(hl)
	cp	c
	ret

; HL a, DE b: Z if b follows a in the same file
joins:	ld	bc,#P_ER
	add	hl,bc
	ld	a,(de)
	cp	(hl)
	ret	nz
	inc	de
	inc	hl
	ld	a,(de)
	cp	(hl)
	ret	nz
	inc	de
	inc	hl
	ld	a,(de)
	and	#127
	cp	(hl)
	ret	nz
	dec	hl
	dec	hl
	dec	hl
	ld	a,(de)
	xor	(hl)
	and	#WORK
	ret

; HL the piece nearest the window on side dn
nearest:
	ld	a,(dn)
	or	a
	jr	z,1$
	ld	a,(_pg_nb)
	neg
	add	a,#NP
	jr	2$
1$:	ld	a,(_pg_na)
	dec	a
2$:	ld	l,a
	ld	h,#0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	de,#_pg_tab
	add	hl,de
	ret

; HL the count of pieces on side dn
side:	ld	hl,#_pg_na
	ld	a,(dn)
	or	a
	ret	z
	ld	hl,#_pg_nb
	ret

flip:	ld	hl,#dn
	ld	a,(hl)
	xor	#1
	ld	(hl),a
	ret

; pc onto the list on side dn, merged with its neighbor there when they
; are one run of the same file. A 0 if there is no room
push:	ld	hl,#pc
	call	empty
	jp	z,true
	call	side
	ld	a,(hl)
	or	a
	jr	z,5$
	call	nearest
	ld	(gt),hl
	ld	bc,#P_NL
	add	hl,bc
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,(pc+P_NL)
	ld	a,d
	and	e
	inc	a
	jr	z,1$
	ld	a,h
	and	l
	inc	a
	jr	z,2$
	add	hl,de
	jr	c,5$
	ld	a,h
	and	l
	inc	a
	jr	z,5$
	jr	2$
1$:	ld	hl,#0xFFFF
2$:	ld	(cnt),hl
	ld	hl,#pc
	ld	de,(gt)
	ld	a,(dn)
	or	a
	jr	nz,3$
	ex	de,hl
3$:	call	joins
	jr	nz,5$
	ld	hl,(gt)
	ld	a,(dn)
	or	a
	jr	z,4$
	ex	de,hl
	ld	hl,#pc
	ld	bc,#3
	ldir
	jr	41$
4$:	ld	bc,#P_ER
	add	hl,bc
	ex	de,hl
	ld	hl,#pc+P_ER
	ld	bc,#3
	ldir
41$:	ld	hl,(gt)
	ld	bc,#P_NL
	add	hl,bc
	ld	de,(cnt)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	jp	true
5$:	ld	a,(_pg_na)
	ld	hl,#_pg_nb
	add	a,(hl)
	cp	#NP
	jr	nz,6$
	ld	hl,#e_many
	ld	(_pg_err),hl
	jp	false
6$:	call	side
	inc	(hl)
	call	nearest
	ex	de,hl
	ld	hl,#pc
	ld	bc,#PSZ
	ldir
	jp	true

; the piece nearest the window on side dn moved to the other
move:	call	nearest
	ld	de,#pc
	ld	bc,#PSZ
	ldir
	call	side
	dec	(hl)
	call	flip
	call	push
	jp	flip

; two pieces free in the table, made by compact if need be: A 0 if not
room:	ld	a,(_pg_na)
	ld	hl,#_pg_nb
	add	a,(hl)
	cp	#NP-1
	jp	c,true

; the pieces on the side with more of them copied to the work file as
; one piece: A 0 if that failed
compact:
	ld	a,(dn)
	push	af
	ld	a,(_pg_nb)
	ld	b,a
	ld	a,(_pg_na)
	cp	b
	ld	a,#0
	adc	a,a
	ld	(dn),a
	call	wwork
	jr	z,9$
	call	side
	ld	a,(hl)
	push	af
	ld	hl,#_pg_tab
	ld	a,(dn)
	or	a
	call	nz,nearest
	pop	af
	call	copyall
	call	wdone
	jr	z,9$
	call	side
	ld	(hl),#0
	call	push
9$:	pop	bc
	push	af
	ld	a,b
	ld	(dn),a
	pop	af
	or	a
	ret

_pg_above:
	ld	a,(_pg_na)
	ld	de,#0
	ld	hl,#_pg_tab+P_NL
	ld	bc,#PSZ-1
1$:	or	a
	jr	z,2$
	push	af
	ld	a,e
	add	a,(hl)
	ld	e,a
	inc	hl
	ld	a,d
	adc	a,(hl)
	ld	d,a
	add	hl,bc
	pop	af
	dec	a
	jr	1$
2$:	ex	de,hl
	ret

; ---- The window ----

; A an index: HL that part
partat:	ld	l,a
	ld	h,#0
	add	hl,hl
	add	hl,hl
	ld	d,h
	ld	e,l
	add	hl,hl
	add	hl,de
	ld	de,#_pg_part
	add	hl,de
	ret

; A a tag: HL its part and carry, or no carry
findtag:
	ld	c,a
	ld	a,(_pg_np)
	or	a
	ret	z
	ld	b,a
	ld	hl,#_pg_part+T_TAG
	ld	de,#TSZ
1$:	ld	a,(hl)
	cp	c
	jr	z,2$
	add	hl,de
	djnz	1$
	or	a
	ret
2$:	ld	de,#-T_TAG
	add	hl,de
	scf
	ret

; A a tag no part has
newtag:	ld	a,(lasttag)
	inc	a
	jr	nz,1$
	inc	a
1$:	ld	(lasttag),a
	call	findtag
	jr	c,newtag
	ld	a,(lasttag)
	ret

; void pg_touch(unsigned char tag) __z88dk_fastcall
_pg_touch:
	ld	a,l
	call	findtag
	ret	nc
	ld	de,#T_DIRTY
	add	hl,de
	ld	(hl),#1
	ret

; unsigned char pg_newtag(void)
_pg_newtag:
	ld	a,(_pg_np)
	or	a
	jr	nz,1$
	ld	hl,#_pg_part
	ld	de,#_pg_part+1
	ld	(hl),a
	ld	bc,#TSZ-1
	ldir
	call	newtag
	ld	(_pg_part+T_TAG),a
	ld	a,#1
	ld	(_pg_part+T_DIRTY),a
	ld	(_pg_np),a
1$:	ld	a,(_pg_np)
	dec	a
	call	partat
	ld	de,#T_TAG
	add	hl,de
	ld	l,(hl)
	ret

; the lines with tag tg at side dn of the window dropped
unload:	ld	a,(dn)
	call	endl
	call	istg
	ret	z
	ld	a,(dn)
	push	af
	inc	sp
	push	hl
	call	_ed_drop
	pop	af
	inc	sp
	jr	unload

; a part read in from the nearest piece on side dn: A 0 if none
load:	ld	a,(_pg_np)
	cp	#NPART
	jp	z,false
	call	side
	ld	a,(hl)
	or	a
	jp	z,false
	call	nearest
	ld	(lp),hl
	ld	de,#pc
	ld	bc,#PSZ
	ldir
	ld	a,(dn)
	or	a
	jr	nz,10$
	; above: the tail of the piece, from a line's start
	ld	hl,(pc+P_ER)
	ld	de,(pc+P_R)
	or	a
	sbc	hl,de
	ld	de,#PRECS+1
	or	a
	sbc	hl,de
	jr	c,10$
	ld	hl,(pc+P_ER)
	ld	de,#-PRECS
	add	hl,de
	ld	(pc+P_R),hl
	ld	a,(pc+P_O)
	and	#WORK
	ld	hl,#pc+P_EO
	or	(hl)
	ld	(pc+P_O),a
	ld	hl,#pc
	call	sopen
1$:	call	sgetl
	bit	7,h
	jr	nz,10$
	ld	a,(s_lf)
	or	a
	jr	z,1$
	ld	a,(s_n)
	or	a
	jr	nz,2$
	call	refill
	jr	z,10$		; unless one line ends it
2$:	call	here
10$:	call	newtag
	ld	(tg),a
	ld	hl,#pc
	call	sopen
	ld	a,(dn)
	push	af
	inc	sp
	call	_ed_begin
	inc	sp
	ld	hl,#0
	ld	(lcost),hl
	ld	(lused),hl
	ld	(lnl),hl
11$:	ld	a,(dn)
	or	a
	jr	z,12$
	ld	a,(s_lf)
	or	a
	jr	z,12$
	ld	hl,(lused)
	ld	de,#PARTSZ
	or	a
	sbc	hl,de
	jr	nc,20$
	ld	hl,(lcost)
	ld	a,h
	or	l
	jr	z,12$
	ld	de,(_pg_cost)
	add	hl,de
	ld	de,(_pg_budget)
	or	a
	sbc	hl,de
	jr	nc,20$
12$:	call	sgetl
	bit	7,h
	jr	nz,20$
	ld	a,(tg)
	push	af
	inc	sp
	push	hl
	ld	hl,#_pg_line
	push	hl
	call	_ed_add
	pop	af
	pop	af
	inc	sp
	ld	a,h
	or	l
	jp	z,30$
	ld	de,(lcost)
	add	hl,de
	ld	(lcost),hl
	ld	hl,(lused)
	ld	de,(s_raw)
	add	hl,de
	ld	(lused),hl
	ld	a,(s_lf)
	ld	e,a
	ld	d,#0
	ld	hl,(lnl)
	add	hl,de
	ld	(lnl),hl
	jr	11$
20$:	ld	hl,(_pg_err)
	ld	a,h
	or	l
	jp	nz,30$
	ld	hl,(lused)
	ld	a,h
	or	l
	jp	z,30$
	; the part, from pc's start to the stream's place
	ld	hl,(pc+P_R)
	ld	(lsr),hl
	ld	a,(pc+P_O)
	ld	(lso),a
	call	here
	ld	hl,(pc+P_R)
	ld	(pc+P_ER),hl
	ld	a,(pc+P_O)
	ld	c,a
	and	#127
	ld	(pc+P_EO),a
	ld	a,(dn)
	or	a
	jr	z,21$
	ld	hl,(lp)		; below: the piece starts at its end
	ld	de,(pc+P_R)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(hl),c
	ld	a,(_pg_np)
	call	partat
	jr	22$
21$:	ld	a,(_pg_np)	; above: the parts down one
	call	partat
	ld	de,#_pg_part
	or	a
	sbc	hl,de
	ld	a,h
	or	l
	jr	z,23$
	ld	b,h
	ld	c,l
	ld	hl,#_pg_part-1
	add	hl,bc
	push	hl
	ld	de,#TSZ
	add	hl,de
	ex	de,hl
	pop	hl
	lddr
23$:	ld	hl,(lp)		; and the piece ends at its start
	ld	de,#P_ER
	add	hl,de
	ld	de,(lsr)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	a,(lso)
	and	#127
	ld	(hl),a
	ld	hl,#_pg_part
22$:	ld	(pt),hl
	ld	hl,(lsr)
	ld	(pc+P_R),hl
	ld	a,(lso)
	ld	(pc+P_O),a
	ld	hl,(lnl)
	ld	(pc+P_NL),hl
	ld	hl,#_pg_np
	inc	(hl)
	ld	de,(pt)
	ld	hl,#pc
	ld	bc,#PSZ
	ldir
	ex	de,hl
	ld	de,(lcost)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	a,(tg)
	ld	(hl),a
	inc	hl
	ld	(hl),#0
	ld	hl,(_pg_cost)
	add	hl,de
	ld	(_pg_cost),hl
	ld	hl,(lp)
	ld	de,#P_NL
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	a,d
	and	e
	inc	a
	jr	z,24$
	ex	de,hl
	ld	bc,(lnl)
	or	a
	sbc	hl,bc
	ex	de,hl
	ld	(hl),d
	dec	hl
	ld	(hl),e
24$:	ld	hl,(lp)
	call	empty
	jp	nz,true
	call	side
	dec	(hl)
	jp	true
30$:	call	unload
	jp	false

; HL keep: the part at side dn of the window out to the list there,
; unless it is within pg_rows lines of keep. Written to the work file
; if it was changed. A 0 if not
evict:	ld	(ekeep),hl
	ld	a,(_pg_np)
	or	a
	jp	z,false
	ld	b,a
	ld	a,(dn)
	or	a
	jr	z,1$
	ld	a,b
	dec	a
1$:	call	partat
	ld	(pt),hl
	ld	de,#T_TAG
	add	hl,de
	ld	a,(hl)
	ld	(tg),a
	ld	a,(_pg_rows)
	ld	(ecnt),a
2$:	ld	hl,(ekeep)
	call	istg
	jp	nz,false
	ld	a,h
	or	l
	jr	z,4$
	ld	a,(ecnt)
	or	a
	jr	z,4$
	dec	a
	ld	(ecnt),a
	ld	a,(dn)
	call	stepl
	ld	(ekeep),hl
	jr	2$
4$:	call	room
	jp	z,false
	ld	hl,(pt)
	ld	de,#pc
	ld	bc,#PSZ
	ldir
	ld	hl,(pt)
	ld	de,#T_DIRTY
	add	hl,de
	ld	a,(hl)
	or	a
	jr	z,9$
	ld	hl,(pc+P_R)	; none, if all its lines went
	ld	(pc+P_ER),hl
	ld	a,(pc+P_O)
	and	#127
	ld	(pc+P_EO),a
	ld	a,(dn)
	call	endl
	call	istg
	jr	z,9$
	ld	(eline),hl
	ld	a,(dn)
	or	a
	jr	z,6$
5$:	ld	hl,(eline)	; written from its first line
	xor	a
	call	stepl
	call	istg
	jr	z,6$
	ld	(eline),hl
	jr	5$
6$:	call	wwork
	jp	z,false
	ld	hl,(eline)
	call	wlines
	ld	(pc+P_NL),hl
	call	wdone
	jp	z,false
9$:	call	unload
	call	push
	ld	hl,(pt)
	ld	de,#T_COST
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,(_pg_cost)
	or	a
	sbc	hl,de
	ld	(_pg_cost),hl
	ld	hl,#_pg_np
	dec	(hl)
	ld	a,(dn)
	or	a
	jp	nz,true
	ld	a,(_pg_np)	; the parts up one
	call	partat
	ld	de,#_pg_part
	or	a
	sbc	hl,de
	ld	a,h
	or	l
	jp	z,true
	ld	b,h
	ld	c,l
	ld	hl,#_pg_part+TSZ
	ld	de,#_pg_part
	ldir
	jp	true

; unsigned char pg_free(void *keep) __z88dk_fastcall
_pg_free:
	push	hl
	xor	a
	ld	(dn),a
	call	evict
	pop	hl
	jr	nz,1$
	ld	a,#1
	ld	(dn),a
	call	evict
1$:	ld	l,a
	ret

; unsigned char pg_slide(unsigned char down, void *keep)
_pg_slide:
	ld	hl,#2
	add	hl,sp
	ld	a,(hl)
	ld	(sdown),a
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	(skeep),de
	ld	hl,#0
	ld	(_pg_err),hl
1$:	ld	a,(sdown)
	ld	(dn),a
	call	load
	jr	nz,3$
	ld	hl,(_pg_err)
	ld	a,h
	or	l
	jr	nz,8$
	call	side
	ld	a,(hl)
	or	a
	jr	z,8$
	call	other
	ld	hl,(skeep)
	call	evict
	jr	nz,1$
	ld	hl,(_pg_err)
	ld	a,h
	or	l
	jr	nz,8$
	ld	hl,#e_mem
	ld	(_pg_err),hl
8$:	ld	l,#0
	ret
3$:	call	other
4$:	ld	hl,(_pg_budget)
	ld	de,(_pg_cost)
	or	a
	sbc	hl,de
	jr	nc,5$
	ld	hl,(skeep)
	call	evict
	jr	nz,4$
5$:	ld	l,#1
	ret
other:	ld	a,(sdown)
	xor	#1
	ld	(dn),a
	ret

; the window loaded from above while it is short of lines above, then
; both ways up to the budget
fill:	xor	a
	ld	(dn),a
	ld	hl,#0
	ld	(fk),hl
1$:	ld	hl,(fk)
	ld	a,(_pg_rows)
	ld	e,a
	ld	d,#0
	or	a
	sbc	hl,de
	jr	nc,2$
	call	load
	jr	z,2$
	ld	hl,(_pg_part+P_NL)
	ld	de,(fk)
	add	hl,de
	ld	(fk),hl
	jr	1$
2$:	ld	a,#1
	ld	(dn),a
	call	fillb
	xor	a
	ld	(dn),a
fillb:	ld	hl,(_pg_cost)
	ld	de,(_pg_budget)
	or	a
	sbc	hl,de
	ret	nc
	call	load
	jr	nz,fillb
	ret

; void *pg_goto(unsigned int n) __z88dk_fastcall
_pg_goto:
	ld	(gn),hl
	ld	hl,#0
	ld	(_pg_err),hl
	xor	a
	ld	(dn),a
1$:	ld	a,(_pg_np)	; the window out above
	or	a
	jr	z,2$
	ld	hl,#0
	call	evict
	jr	nz,1$
	jp	90$
2$:	ld	a,(_pg_na)	; back while above is past n
	or	a
	jr	z,3$
	call	_pg_above
	ex	de,hl
	ld	hl,(gn)
	or	a
	sbc	hl,de
	jr	nc,3$
	call	move
	jr	2$
3$:	call	_pg_above
	ld	(ga),hl
	ld	a,#1
	ld	(dn),a
4$:	ld	a,(_pg_nb)	; on while the piece below ends before n
	or	a
	jr	z,6$
	call	nearest
	ld	(gp),hl
	ld	de,#P_NL
	add	hl,de
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	a
	jr	nz,5$
	ld	hl,(gp)		; its lines not yet counted
	call	sopen
	call	scount
	ex	de,hl
	ld	hl,(gp)
	ld	bc,#P_NL
	add	hl,bc
	ld	(hl),e
	inc	hl
	ld	(hl),d
5$:	ld	hl,(gp)
	ld	de,#P_NL
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,(ga)
	add	hl,de
	jr	c,6$
	ld	(gt),hl
	ex	de,hl
	ld	hl,(gn)
	or	a
	sbc	hl,de
	jr	c,6$
	ld	hl,(gt)
	ld	(ga),hl
	call	move
	jr	4$
6$:	ld	a,(_pg_nb)	; the piece split at the line
	or	a
	jp	z,8$
	ld	hl,(gn)
	ld	de,(ga)
	or	a
	sbc	hl,de
	jp	z,8$
	jp	c,8$
	ld	(gk),hl
	call	room
	jp	z,8$
	call	nearest
	ld	(gp),hl
	call	sopen
7$:	ld	hl,(gk)
	ld	a,h
	or	l
	jr	z,71$
	call	sgetl
	bit	7,h
	jr	nz,71$
	ld	a,(s_lf)
	ld	e,a
	ld	d,#0
	ld	hl,(gk)
	or	a
	sbc	hl,de
	ld	(gk),hl
	jr	7$
71$:	call	here
	ld	hl,(pc+P_R)
	ld	(pc+P_ER),hl
	ld	a,(pc+P_O)
	and	#127
	ld	(pc+P_EO),a
	ld	hl,(gp)
	ld	de,#pc
	ld	bc,#3
	ldir
	ld	hl,(gn)
	ld	de,(ga)
	or	a
	sbc	hl,de
	ld	(pc+P_NL),hl
	xor	a
	ld	(dn),a
	ld	hl,(_pg_err)
	ld	a,h
	or	l
	jr	nz,8$
	call	push
	jr	z,8$
	ld	hl,(gp)
	ld	de,(pc+P_ER)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	a,(hl)
	and	#WORK
	ld	b,a
	ld	a,(pc+P_EO)
	or	b
	ld	(hl),a
	ld	hl,(gp)
	ld	de,#P_NL
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	a,d
	and	e
	inc	a
	jr	z,72$
	ex	de,hl
	ld	bc,(pc+P_NL)
	or	a
	sbc	hl,bc
	ex	de,hl
	ld	(hl),d
	dec	hl
	ld	(hl),e
72$:	ld	hl,(gp)
	call	empty
	jr	nz,8$
	ld	hl,#_pg_nb
	dec	(hl)
8$:	ld	hl,(_pg_err)
	ld	a,h
	or	l
	jr	nz,90$
	ld	a,#1
	ld	(dn),a
	call	load
	ld	hl,#0
	jr	z,9$
	xor	a
	call	endl
9$:	ld	(gt),hl
	call	fill
	ld	hl,(gt)
	ret
90$:	ld	hl,#0
	ret

; ---- Open, close, save ----

; unsigned char pg_open(const char *name, unsigned int budget)
_pg_open:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	(obud),de
	call	_pg_close
	pop	hl
	call	named
	ld	de,#ofcb
	ld	hl,#0
	ld	b,h
	ld	c,l
	ld	a,#15
	call	pgbdos
	inc	a
	jr	z,9$
	ld	de,#ofcb
	ld	hl,#0
	ld	b,h
	ld	c,l
	ld	a,#35
	call	pgbdos
	ld	hl,#pc
	ld	de,#pc+1
	ld	(hl),#0
	ld	bc,#PSZ-1
	ldir
	ld	hl,#0xFFFF
	ld	(pc+P_NL),hl
	ld	hl,(ofcb+33)
	ld	a,h
	or	l
	jr	z,5$
	dec	hl		; the text ends at the first ^Z of the last record
	ld	(pc+P_ER),hl
	ld	de,#ofcb
	ld	bc,#rbuf
	ld	a,#33
	call	pgbdos
	or	a
	jr	nz,9$
	ld	hl,#rbuf
	ld	bc,#128
	ld	a,#0x1A
	cpir
	ld	a,#127
	jr	z,2$
	ld	hl,(pc+P_ER)
	inc	hl
	ld	(pc+P_ER),hl
	ld	c,#127
2$:	sub	c		; the ^Z's place, or 0 in the next record
	and	#127
	ld	(pc+P_EO),a
5$:	ld	hl,(obud)
	ld	(_pg_budget),hl
	ld	a,#1
	ld	(_pg_on),a
	ld	(dn),a
	call	push
	ld	l,#1
	ret
9$:	ld	l,#0
	ret

wclose:	ld	a,(w_open)
	or	a
	jr	z,1$
	ld	de,#wfcb
	call	close
	ld	hl,#wname
	call	rm
	xor	a
	ld	(w_open),a
1$:	ld	hl,#0
	ld	(w_fcb),hl
	ret

; void pg_close(void)
_pg_close:
	ld	a,(_pg_on)
	or	a
	ld	de,#ofcb
	call	nz,close
	call	wclose
	xor	a
	ld	(_pg_on),a
	ld	(_pg_na),a
	ld	(_pg_nb),a
	ld	(_pg_np),a
	ld	h,a
	ld	l,a
	ld	(_pg_cost),hl
	ret

; HL the first piece, A how many: copied to the writer as one, its
; lines in pc's nl
copyall:
	ld	(cpn),a
	ld	(cpp),hl
	call	wstart
1$:	ld	a,(cpn)
	or	a
	jp	z,wend
	dec	a
	ld	(cpn),a
	ld	hl,(cpp)
	call	copy
	ld	hl,(pc+P_NL)
	add	hl,de
	ld	(pc+P_NL),hl
	ld	hl,(cpp)
	ld	de,#PSZ
	add	hl,de
	ld	(cpp),hl
	jr	1$

; HL a number of lines: added to stotal
addtot:	ld	de,(stotal)
	add	hl,de
	ld	(stotal),hl
	ret

; long pg_save(const char *name, unsigned char bak)
_pg_save:
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	ld	(sbak),a
	ld	(sname),de
	ld	hl,#0
	ld	(_pg_err),hl
	ld	(stotal),hl
	ex	de,hl
	ld	de,#tmp
	ld	bc,#t_s
	call	mkname
	ld	hl,#tmp
	call	rm
	ld	hl,#tmp
	ld	de,#sfcb
	call	mkfcb
	ld	de,#sfcb
	ld	hl,#0
	ld	b,h
	ld	c,l
	ld	a,#22
	call	pgbdos
	inc	a
	jr	nz,1$
	ld	hl,#e_mkf
	ld	(_pg_err),hl
	jp	90$
1$:	ld	hl,#sfcb
	ld	(w_fcb),hl
	ld	hl,#0
	ld	(w_rec),hl
	xor	a
	ld	(w_n),a
	ld	(w_bad),a
	ld	hl,#_pg_tab	; the pieces above
	ld	a,(_pg_na)
	call	copyall
	ld	hl,#pc
	ld	de,#ab
	ld	bc,#PSZ
	ldir
	ld	hl,(pc+P_NL)
	call	addtot
	xor	a		; the window's parts
	call	endl
	ld	(sl),hl
	ld	a,(_pg_np)
	ld	(spn),a
	ld	hl,#_pg_part
	ld	(pt),hl
	ld	hl,#snew
	ld	(snp),hl
3$:	ld	a,(spn)
	or	a
	jr	z,6$
	dec	a
	ld	(spn),a
	ld	hl,(pt)
	ld	de,#T_TAG
	add	hl,de
	ld	a,(hl)
	ld	(tg),a
	inc	hl
	ld	a,(hl)
	push	af
	call	wstart
	pop	af
	or	a
	jr	z,4$
	ld	hl,(sl)
	call	wlines
	ld	(pc+P_NL),hl
	jr	42$
4$:	ld	hl,(pt)
	call	copy
	ld	(pc+P_NL),de
42$:	ld	hl,(sl)		; past its lines
	call	istg
	jr	z,43$
	ld	a,#1
	call	stepl
	ld	(sl),hl
	jr	42$
43$:	call	wend
	ld	de,(snp)	; the parts' own once it is saved
	ld	hl,#pc
	ld	bc,#PSZ
	ldir
	ld	(snp),de
	ld	hl,(pc+P_NL)
	call	addtot
	ld	hl,(pt)
	ld	de,#TSZ
	add	hl,de
	ld	(pt),hl
	jr	3$
6$:	ld	a,#1		; the pieces below
	ld	(dn),a
	call	nearest
	ld	a,(_pg_nb)
	call	copyall
	ld	hl,(pc+P_NL)
	call	addtot
	ld	a,(w_n)		; ^Z to the record's end
	or	a
	jr	z,7$
	ld	e,a
	ld	d,#0
	ld	hl,#wbuf
	add	hl,de
	ld	b,a
	ld	a,#128
	sub	b
	ld	b,a
	ld	a,#0x1A
61$:	ld	(hl),a
	inc	hl
	djnz	61$
	call	wflush
7$:	ld	de,#sfcb
	call	close
	ld	a,(w_bad)
	ld	hl,(_pg_err)
	or	h
	or	l
	jr	z,8$
	ld	hl,#tmp
	call	rm
	ld	hl,#0
	ld	(w_fcb),hl
	ld	hl,(_pg_err)
	ld	a,h
	or	l
	jp	nz,90$
	ld	hl,#e_write
	ld	(_pg_err),hl
	jp	90$
8$:	ld	a,(_pg_np)	; saved: the parts' pieces are the new ones
	or	a
	jr	z,87$
	ld	b,a
	ld	hl,#snew
	ld	de,#_pg_part
85$:	push	bc
	ld	bc,#PSZ
	ldir
	ex	de,hl
	ld	bc,#TSZ-PSZ
	add	hl,bc		; HL = the next part
	ex	de,hl
	pop	bc
	djnz	85$
	ld	hl,#_pg_part+T_DIRTY	; none changed now
	ld	de,#TSZ
	ld	a,(_pg_np)
	ld	b,a
86$:	ld	(hl),#0
	add	hl,de
	djnz	86$
87$:	ld	de,#ofcb	; the new file takes the name
	call	close
	ld	a,(sbak)
	or	a
	jr	z,81$
	ld	hl,(sname)
	ld	de,#fname
	ld	bc,#t_bak
	call	mkname
	ld	hl,#fname
	call	rm
	ld	hl,#fname
	push	hl
	ld	hl,(sname)
	push	hl
	call	_rename
	pop	af
	pop	af
	jr	82$
81$:	ld	hl,(sname)
	call	rm
82$:	ld	hl,(sname)
	push	hl
	ld	hl,#tmp
	push	hl
	call	_rename
	pop	af
	pop	af
	call	wclose		; and the pieces are its
	ld	hl,(sname)
	call	named
	ld	de,#ofcb
	ld	hl,#0
	ld	b,h
	ld	c,l
	ld	a,#15
	call	pgbdos
	xor	a
	ld	(_pg_na),a
	ld	(_pg_nb),a
	inc	a
	ld	(dn),a
	call	push
	ld	hl,#ab
	ld	de,#pc
	ld	bc,#PSZ
	ldir
	xor	a
	ld	(dn),a
	call	push
	ld	hl,(stotal)
	ld	de,#0
	ret
90$:	ld	hl,#0xFFFF
	ld	d,h
	ld	e,l
	ret

t_w:	.asciz	"$$W"
t_s:	.asciz	"$$S"
t_bak:	.asciz	"BAK"
crlf:	.db	13, 10
e_read:	.asciz	"Read error"
e_work:	.asciz	"Cannot make the work file"
e_wwrite: .asciz "Work file write error"
e_many:	.asciz	"Too many pieces, save the file"
e_mem:	.asciz	"Out of memory"
e_mkf:	.asciz	"Cannot make the file"
e_write: .asciz	"Write error"
