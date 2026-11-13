; xcpmz80 kernel helpers: console output, numbers, names.

crlf:	ld	a,0Dh
	call	kputc
	ld	a,0Ah
	jr	kputc

space:	ld	a,' '
	; fall into kputc

; Put A on the console. Tabs go to the next multiple of 8, and the
; column is kept in the SCB, as CP/M's BDOS does. Keeps BC, DE, HL.
kputc:	push	bc
	cp	09h
	jr	z,kp_tab
	ld	c,a
	call	kraw
	pop	bc
	ret
kp_tab:	ld	c,' '
	call	kraw
	ld	a,(scb+SCB_COL)
	and	7
	jr	nz,kp_tab
	pop	bc
	ret

; Print the string that follows the call, NUL-ended, and return from
; the caller. Uses HL.
pmsgr:	pop	hl
; Print the NUL-ended string at HL. HL ends past the NUL.
pstr:	ld	a,(hl)
	inc	hl
	or	a
	ret	z
	call	kputc
	jr	pstr

; Print the string that follows the call, NUL-ended
pmsg:	ex	(sp),hl
	call	pstr
	ex	(sp),hl
	ret

; Print A in decimal
pdeca:	ld	l,a
	ld	h,0
	; fall into pdec

; Print HL in decimal
pdec:	ld	de,0
	ld	(dvhi),de
	; fall into pdec32

; Print dvhi:HL, 32 bits, in decimal
pdec32:	ld	(dvlo),hl
	ld	b,0			; digits pushed
pd_1:	push	bc
	ld	hl,dvhi+1		; dvhi:dvlo /= 10 by long division,
	ld	d,4			; a byte at a time from the top
	xor	a			; (dvhi follows dvlo). A = remainder
dt_1:	ld	e,(hl)
	ld	b,8
dt_2:	sla	e			; remainder:byte * 2
	rla
	cp	10
	jr	c,dt_3
	sub	10
	inc	e			; a quotient bit
dt_3:	djnz	dt_2
	ld	(hl),e
	dec	hl
	dec	d
	jr	nz,dt_1
	pop	bc
	add	a,'0'
	push	af
	inc	b
	ld	hl,(dvlo)
	ld	de,(dvhi)
	ld	a,h
	or	l
	or	d
	or	e
	jr	nz,pd_1
pd_2:	pop	af
	call	kputc
	djnz	pd_2
	ret

upper:	cp	'a'
	ret	c
	cp	'z'+1
	ret	nc
	sub	20h
	ret

skipsp:	ld	a,(hl)
	cp	' '
	jr	z,ss_1
	cp	09h
	ret	nz
ss_1:	inc	hl
	jr	skipsp

; Is A a delimiter of names, as CP/M's? Z if so: control characters,
; the blank and the list. Keeps A, BC and HL, carry clear.
isdelim: cp	' '+1
	jr	nc,id_1
	cp	a			; Z
	ret
id_1:	push	hl
	push	bc
	ld	hl,delims
	ld	bc,ndelim
	cpir				; Z if found
	pop	bc
	pop	hl
	ret
delims:	db	"=.:;<>,|[]+/"		; not _, which FAT names hold
ndelim	equ	$-delims

; Parse a file name at HL into the 12 bytes at DE: drive (0 default,
; 1 A: ...) and 11 name bytes, blank filled, '*' as '?', upper case.
; Leading blanks are skipped. HL ends after the name. A = number of '?'
; in it, and carry if the name was bad (a drive letter out of range).
parsefn: call	skipsp
	push	de
	xor	a
	ld	(qcount),a
	ld	(de),a			; default drive
	inc	de
	push	de			; blank the name
	ld	b,11
pf_1:	ld	a,' '
	ld	(de),a
	inc	de
	djnz	pf_1
	pop	de
	inc	hl			; "d:"?
	ld	a,(hl)
	dec	hl
	cp	':'
	jr	nz,pf_2
	ld	a,(hl)
	call	upper
	sub	'A'-1
	jr	c,pf_bad
	cp	16+1
	jr	nc,pf_bad
	dec	de
	ld	(de),a
	inc	de
	inc	hl
	inc	hl
pf_2:	ld	b,8
	call	pf_part
	ld	a,(hl)			; ".ext"
	cp	'.'
	jr	nz,pf_3
	inc	hl
	pop	de			; DE = the FCB start
	push	de
	ex	de,hl
	ld	bc,9
	add	hl,bc
	ex	de,hl
	ld	b,3
	call	pf_part
pf_3:	pop	de
	ld	a,(qcount)
	or	a			; clear carry
	ret
pf_bad:	pop	de
	scf
	ret

; Up to B name characters at HL into DE. '*' fills the rest with '?'.
; Extra characters are skipped.
pf_part: ld	a,(hl)
	call	isdelim
	ret	z
	inc	hl
	cp	'*'
	jr	z,pp_star
	call	upper
	cp	'?'
	call	z,pp_q
	ld	c,a
	ld	a,b
	or	a
	jr	z,pf_part		; full: skip it
	ld	a,c
	ld	(de),a
	inc	de
	dec	b
	jr	pf_part
pp_star: ld	a,b
	or	a
	jr	z,pf_part
	ld	a,'?'
	call	pp_q
	ld	(de),a
	inc	de
	djnz	pp_star
	jr	pf_part
pp_q:	push	hl
	ld	hl,qcount
	inc	(hl)
	pop	hl
	ret

; Print the 11-byte name at HL as NAME.EXT, no blanks. Keeps HL.
pname:	push	hl
	ld	b,8
	call	pn_1
	ld	a,(hl)
	and	7Fh
	cp	' '
	jr	z,pn_3
	ld	a,'.'
	call	kputc
	ld	b,3
	call	pn_1
pn_3:	pop	hl
	ret
pn_1:	ld	a,(hl)			; B characters, no blanks
	and	7Fh
	cp	' '
	call	nz,kputc
	inc	hl
	djnz	pn_1
	ret

; Compare B bytes at HL and DE, the pattern at DE ('?' matches
; anything). Bit 7 is ignored (attributes). Z if they match.
match:	ld	a,(de)
	cp	'?'
	jr	z,mh_1
	xor	(hl)
	and	7Fh
	ret	nz
mh_1:	inc	hl
	inc	de
	djnz	match
	ret

; Zero BC + 1 bytes from HL, BC not 0. DE and HL end as LDIR leaves them.
zfill:	ld	d,h
	ld	e,l
	inc	de
	ld	(hl),0
	ldir
	ret
