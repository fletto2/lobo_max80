; xcpmz80 shell. Runs in A2. The command line of CP/M's CCP with
; CP/M's built-in commands and the Unix names of the same ones. A
; command that is not built in runs NAME.COM, from the current drive
; or A:, or NAME.SUB or NAME.BAT as a batch file. A:AUTOEXEC.BAT runs
; at a cold boot.
; Batch lines come from A:$$$.SUB, last record first, as CP/M 2.2's
; SUBMIT writes it, so its SUBMIT.COM works too.

shell:	ld	sp,STKTOP
	xor	a
	ld	(dsdirs),a
	ld	(rootf),a
	dec	a
	ld	(dirovd),a
	call	crlf
	ld	a,(scb+SCB_DRV)
	ld	(shdrv),a
	call	pcwd
	ld	a,'>'
	call	kputc
	ld	a,(subact)
	or	a
	jr	z,sh_kbd
	call	subline
	jr	nz,sh_kbd
	ld	hl,linebuf		; a batch line: show it
	call	pstr
	jp	sh_go
sh_kbd:	ld	hl,(rsxtop)		; RSXs loaded: through them, as
	ld	de,bdosent		; CP/M 3's CCP, for GET and SUBMIT
	or	a
	sbc	hl,de
	jr	z,sh_own
	ld	hl,0080h		; function 10 at 0080h in the TPA
	ld	a,126
	call	upoke
	ld	hl,scb+SCB_CCPF		; the CCP reads: SUBMIT's RSX gives
	set	5,(hl)			; it the batch's command lines
	ld	c,10
	ld	de,0080h
	call	rsxcall
	ld	hl,scb+SCB_CCPF
	res	5,(hl)
	ld	hl,0081h
	call	upeek
	ld	(lnlen),a
	or	a
	jr	z,sh_len
	ld	c,a			; by way of common memory
	ld	b,0
	push	bc
	ld	hl,0082h
	ld	de,CBUF
	call	ucopy
	pop	bc
	ld	hl,CBUF
	ld	de,linebuf
	ldir
	jr	sh_len
sh_own:	ld	a,127
	ld	(lnmax),a
	ld	a,(scb+SCB_COL)
	ld	(lnstart),a
	ld	(lnend),a
	ld	a,1			; UP brings back the last line here
	ld	(lnhist),a
	call	rdline
	xor	a
	ld	(lnhist),a
	ld	a,(lnlen)		; kept for UP, if not empty
	or	a
	jr	z,sh_len
	ld	(histlen),a
	ld	c,a
	ld	b,0
	ld	hl,linebuf
	ld	de,histbuf
	ldir
sh_len:	ld	a,(lnlen)
	ld	e,a
	ld	d,0
	ld	hl,linebuf
	add	hl,de
	ld	(hl),0
sh_go:	call	crlf
	; fall into docmd

; Run the command line in linebuf
docmd:	ld	sp,STKTOP
	ld	hl,linebuf		; upper case, as CP/M's CCP
dc_1:	ld	a,(hl)
	or	a
	jr	z,dc_2
	call	upper
	ld	(hl),a
	inc	hl
	jr	dc_1
dc_2:	ld	hl,linebuf
	call	skipsp
	or	a
	jp	z,shell
	cp	';'			; a comment
	jp	z,shell
	ld	de,cmdfcb
	call	parsefn
	jp	c,dc_what
	ld	(cmdtail),hl
	ld	a,(cmdfcb+1)		; "B:": change drive
	cp	' '
	jr	nz,dc_3
	ld	a,(cmdfcb)
	or	a
	jr	z,dc_what
	dec	a
	ld	(fdrive),a
	call	mount
	jp	nz,sherr
	ld	a,(fdrive)
	ld	(scb+SCB_DRV),a
	jp	shell
dc_3:	ld	a,(cmdfcb)		; built in? (no drive, no extension)
	or	a
	jr	nz,dc_ext
	ld	a,(cmdfcb+9)
	cp	' '
	jr	nz,dc_ext
	ld	hl,btab			; the typed name against each, as
dc_4:	ld	a,(hl)			; match does: '?' matches anything
	or	a
	jr	z,dc_ext
	ld	de,cmdfcb+1
	ld	bc,8*256		; B places, C bit 7 once past the name
dc_m:	ld	a,' '			; past its end the name is blank
	bit	7,c
	jr	nz,dc_m1
	ld	a,(hl)			; bit 7 marks its last character
	ld	c,a
	inc	hl
dc_m1:	ex	de,hl
	xor	(hl)
	and	7Fh
	jr	z,dc_m2
	ld	a,(hl)
	cp	'?'
dc_m2:	ex	de,hl
	jr	nz,dc_no
	inc	de
	djnz	dc_m
	ld	a,(hl)			; HL is past the name: its routine,
	inc	hl			; for dc_7's RET
	ld	h,(hl)
	ld	l,a
	push	hl
	ld	hl,(cmdtail)		; options in [ ]: the program of that
dc_6:	ld	a,(hl)			; name if there is one, as CP/M 3's
	inc	hl			; CCP runs DIR.COM for DIR [FULL]
	or	a
	jr	z,dc_7
	cp	'['
	jr	nz,dc_6
	call	tryprog
dc_7:	ld	hl,(cmdtail)
	ret				; into the command, HL = its tail
dc_no:	bit	7,c			; not this one: on past its name
	jr	nz,dc_n2
dc_n1:	bit	7,(hl)
	inc	hl
	jr	z,dc_n1
dc_n2:	inc	hl			; and its routine
	inc	hl
	jr	dc_4
dc_ext:	call	tryprog			; returns only if there is none
dc_sub:	call	runsub			; NAME.SUB?
	jp	nc,shell
dc_what: ld	hl,cmdfcb+1		; as CP/M: "NAME?"
	call	pname
	ld	a,'?'
	call	kputc
	jp	shell

; Run cmdfcb's program with the tail at cmdtail. Back here only if
; there is none.
tryprog: ld	hl,(cmdtail)
	call	runprog
	ret	c
	jp	shell

; The built-in commands: the name, bit 7 set on its last character,
; then the routine
btab:	db	"DI",'R'+80h
	dw	cdir
	db	"L",'S'+80h
	dw	cls_
	db	"ER",'A'+80h
	dw	cera
	db	"R",'M'+80h
	dw	cera
	db	"DE",'L'+80h
	dw	cera
	db	"RE",'N'+80h
	dw	cren
	db	"M",'V'+80h
	dw	cmv
	db	"TYP",'E'+80h
	dw	ctype
	db	"CA",'T'+80h
	dw	ctype
	db	"SAV",'E'+80h
	dw	csave
	db	"USE",'R'+80h
	dw	cuser
	db	"C",'P'+80h
	dw	ccp
	db	"COP",'Y'+80h
	dw	ccp
	db	"FRE",'E'+80h
	dw	cfree
	db	"CL",'S'+80h
	dw	cclear
	db	"CLEA",'R'+80h
	dw	cclear
	db	"VE",'R'+80h
	dw	cver
	db	"HEL",'P'+80h
	dw	chelp
	db	"FORMA",'T'+80h
	dw	cformat
	db	"SY",'S'+80h
	dw	csys
	db	"SUBMI",'T'+80h
	dw	csubmit
	db	"C",'D'+80h
	dw	ccd
	db	"CHDI",'R'+80h
	dw	ccd
	db	"PW",'D'+80h
	dw	cpwd
	db	"MKDI",'R'+80h
	dw	cmkdir
	db	"M",'D'+80h
	dw	cmkdir
	db	"RMDI",'R'+80h
	dw	crmdir
	db	"R",'D'+80h
	dw	crmdir
	db	0

; CD path, CHDIR: the current folder of the path's drive. CD alone, PWD:
; show the current one.
ccd:	call	skipsp
	or	a
	jr	z,cpwd
	xor	a
	ld	(wlast),a
	call	walk
	jp	nz,sherr
	call	cdset
	jp	shell
cpwd:	call	crlf
	ld	a,(scb+SCB_DRV)
	call	pcwd
	jp	shell

; MKDIR path, MD: make a folder. RMDIR path, RD: remove an empty one.
cmkdir:	call	cmr_0
	call	xmkdir
	jr	cmr_1
crmdir:	call	cmr_0
	call	xrmdir
cmr_1:	jp	nz,sherr
	jp	shell
cmr_0:	call	skipsp			; a name, or What?
	or	a
	ret	nz
	pop	af
	jp	dc_what

; ------------------------------------------------------------------
; argpat, then argfcb to DE. HL = argend.
argcp:	push	de
	call	argpat
	pop	de
	ld	hl,argfcb
	ld	bc,12
	ldir
	ld	hl,(argend)
	ret

; argpat, the count zeroed, and the first entry
dirbeg:	ld	a,A_DIR			; folders too: a path's walk clears it
	push	af
	call	argpat
	pop	af
	ld	(dsdirs),a
	ld	hl,0
	ld	(ncount),hl
	jp	dsfirst

; argpat for one file: a name, no wildcard, else What?
arg1:	call	argpat
	ld	hl,argfcb+1
	; fall into nowild

; The 11-byte name at HL: none, or a ? in it, is What?
nowild:	ld	a,(hl)
	cp	' '
	jp	z,dc_what
	ld	b,11
nw_1:	ld	a,(hl)
	cp	'?'
	jp	z,dc_what
	inc	hl
	djnz	nw_1
	ret

; Parse a file name argument at HL into argfcb, '*.*' if there is
; none, and mount its drive. HL ends after it. Errors go to sherr.
argpat:	call	skipsp
	ld	de,argfcb
	call	parsep
	jp	c,dc_what
	ld	(argend),hl
	ld	a,(argfcb+1)		; no name: everything
	cp	' '
	jr	nz,ap_1
	ld	hl,argfcb+1
	ld	b,11
ap_0:	ld	(hl),'?'
	inc	hl
	djnz	ap_0
ap_1:	ld	a,(argfcb)
	or	a
	jr	nz,ap_2
	ld	a,(scb+SCB_DRV)
	inc	a
ap_2:	dec	a
	ld	(fdrive),a
	call	mount
	jp	nz,sherr
	ld	hl,argfcb+1
	ld	de,spat
	ld	bc,11
	ldir
	ld	hl,(argend)
	ret

; DIR [name]: four names a line, as CP/M's. System and hidden files
; are left out.
cdir:	call	dirbeg			; folders too
cd_1:	jr	nz,cd_9
	ld	a,(hl)			; not . and ..
	cp	'.'
	jr	z,cd_4
	push	hl
	ld	de,DE_ATTR
	add	hl,de
	ld	a,(hl)
	pop	hl
	and	A_HID or A_SYS
	jr	nz,cd_4
	ld	a,(ncount)
	and	3
	jr	nz,cd_2
	call	crlf
	ld	a,(fdrive)
	add	a,'A'
	call	kputc
	ld	a,':'
	call	kputc
	jr	cd_3
cd_2:	call	pmsg
	db	" :",0
cd_3:	call	space
	push	hl
	ld	de,DE_ATTR
	add	hl,de
	bit	4,(hl)			; A_DIR
	pop	hl
	jr	nz,cd_d
	ld	b,8
	call	pchars
	call	space
	ld	b,3
	call	pchars
cd_5:	ld	hl,(ncount)
	inc	hl
	ld	(ncount),hl
	call	kbreak
cd_4:	call	dsnext
	jr	cd_1
cd_d:	ld	a,(scb+SCB_COL)		; a folder: NAME\, as wide as a file
	add	a,12
	push	af
	call	pname
	ld	a,5Ch
	call	kputc
	pop	bc
cd_p:	ld	a,(scb+SCB_COL)
	cp	b
	jr	nc,cd_5
	call	space
	jr	cd_p
cd_9:	cp	R_NOFILE
	jp	nz,sherr
	ld	hl,(ncount)
	ld	a,h
	or	l
	jp	nz,shell
	call	crlf
	call	pmsg
	db	"No file",0
	jp	shell

; Print B characters at HL, attribute bits off. HL moves on.
pchars:	ld	a,(hl)
	and	7Fh
	call	kputc
	inc	hl
	djnz	pchars
	ret

; A key pressed: back to the shell. ^S waits for the next key, and goes
; on unless that is ^C. Keeps HL.
kbreak:	call	xconst
	ret	z
	call	xconin
	cp	13h
	jp	nz,shell
	call	xconin
	cp	03h
	jp	z,shell
	ret

; LS [name]: every file, its size, then the count and the space left
cls_:	call	dirbeg			; folders too
ls_1:	jp	nz,ls_9
	ld	a,(hl)			; not . and ..
	cp	'.'
	jr	z,ls_n
	push	hl
	call	crlf
	call	pname
	push	hl
	ld	de,DE_ATTR
	add	hl,de
	bit	4,(hl)
	pop	hl
	ld	a,5Ch
	call	nz,kputc
	ld	a,(scb+SCB_COL)		; sizes at column 14
	ld	b,a
	ld	a,13
	sub	b
	jr	c,ls_2
	jr	z,ls_2
	ld	b,a
ls_s:	call	space
	djnz	ls_s
ls_2:	pop	hl
	push	hl
	ld	de,DE_ATTR
	add	hl,de
	ld	a,(hl)
	ld	(lsattr),a
	pop	hl
	and	A_DIR
	jr	z,ls_f
	call	pmsg
	db	"<DIR>",0
	jr	ls_4
ls_f:	ld	de,DE_SIZE
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	(dvhi),hl
	ex	de,hl
	call	pdec32
	ld	a,(lsattr)		; R/O, SYS, HID
	and	A_RO
	jr	z,ls_3
	call	pmsg
	db	" R/O",0
ls_3:	ld	a,(lsattr)
	and	A_SYS or A_HID
	jr	z,ls_4
	call	pmsg
	db	" SYS",0
ls_4:	ld	hl,(ncount)
	inc	hl
	ld	(ncount),hl
	call	kbreak
ls_n:	call	dsnext
	jp	ls_1
ls_9:	cp	R_NOFILE
	jp	nz,sherr
	call	crlf
	ld	hl,(ncount)
	call	pdec
	call	pmsg
	db	" files, ",0
	call	pfree
	jp	shell

; Print "NNNK free" for the mounted drive IX
pfree:	call	fatcount		; clusters * SPC / 2 = K
	ld	b,(ix+D_SPCSH)
	inc	b
pf__1:	dec	b
	jr	z,pf__2
	add	hl,hl
	jr	pf__1
pf__2:	srl	h
	rr	l
	call	pdec
	call	pmsg
	db	"K free",0
	ret

; FREE [d:]
cfree:	call	argpat
	call	crlf
	ld	a,(fdrive)
	add	a,'A'
	call	kputc
	call	pmsg
	db	": ",0
	call	pfree
	jp	shell

; ERA name: delete. All of them asks first.
cera:	call	skipsp
	or	a
	jp	z,dc_what
	call	argpat
	ld	hl,argfcb+1		; every name?
	ld	b,11
ce_1:	ld	a,(hl)
	cp	'?'
	jr	nz,ce_3
	inc	hl
	djnz	ce_1
	call	pmsg
	db	"ALL (Y/N)? ",0
	call	xconin
	call	upper
	push	af
	call	kputc
	pop	af
	cp	'Y'
	jp	nz,shell
ce_3:	ld	hl,argfcb
	call	cfcbset
	call	fdelete
	call	fchk
	jp	shell

; REN new=old, as CP/M's, in one folder. MV old new, as Unix, through
; COPY's loop: see mvone.
cren:	ld	de,renew
	call	argcp
	ld	a,0FFh			; the old name's folder, not the new one's
	ld	(dirovd),a
	call	skipsp
	cp	'='
	jp	nz,dc_what
	inc	hl
	ld	de,reold
	call	argcp
rename:	ld	hl,renew+1		; whole names, no wildcards
	call	nowild
	ld	hl,reold+1
	call	nowild
	ld	hl,reold
	call	cfcbset
	ld	a,(reold)		; one drive: the old name's, or the
	or	a			; new one's if only it has one
	ld	a,(renew)
	jr	nz,rn_1
	ld	(CFCB),a
	jr	rn_2
rn_1:	or	a			; both: the same one
	jr	z,rn_2
	ld	hl,reold
	cp	(hl)
	jp	nz,dc_what
rn_2:
	ld	hl,renew+1
	ld	de,CFCB+17
	ld	bc,11
	ldir
	call	frename
	jp	nz,sherr
	or	a
	jp	z,shell
	jp	mv_tk			; MV's message

; TYPE name: the text up to ^Z
ctype:	call	arg1
	ld	hl,argfcb
	call	cfcbset
	call	fopen
	call	fchk
	call	crlf
	ld	hl,0
ct_1:	push	hl
	call	rdrec
	pop	hl
	jp	nz,sherr
	or	a
	jp	nz,shell
	push	hl
	ld	hl,CBUF
	ld	b,128
ct_2:	ld	a,(hl)
	cp	1Ah
	jr	z,ct_9
	call	kputc
	inc	hl
	djnz	ct_2
	pop	hl
	call	kbreak
	inc	hl
	ld	a,h			; 8M: the end
	or	l
	jp	z,shell
	jr	ct_1
ct_9:	pop	hl
	jp	shell

; SAVE n name: n pages from 0100h
csave:	call	skipsp
	call	getnum
	jp	c,dc_what
	ld	(savepg),a
	call	arg1
	ld	hl,argfcb
	call	cfcbset
	call	fmake
	call	fchk
	ld	hl,0100h
	ld	(prdest),hl
	ld	hl,0			; records: pages * 2, up to 510
sv_0:	push	hl
	ld	a,(savepg)
	ld	e,a
	ld	d,0
	ex	de,hl
	add	hl,hl
	ex	de,hl
	or	a
	sbc	hl,de
	pop	hl
	jr	z,sv_9
	push	hl
	ld	hl,(prdest)
	ld	de,CBUF
	ld	bc,128
	call	ucopy
	ld	(prdest),hl
	pop	hl
	push	hl
	call	wrrec
	pop	hl
	jp	nz,sherr
	inc	hl
	jr	sv_0
sv_9:	call	fclose
	jp	nz,sherr
	jp	shell

; A = the decimal number at HL. Carry if there is none or it is over 255.
getnum:	ld	a,(hl)
	sub	'0'
	ret	c
	cp	10
	ccf
	ret	c
	ld	c,0
gn_1:	ld	a,(hl)
	sub	'0'
	jr	c,gn_9
	cp	10
	jr	nc,gn_9
	ld	b,a
	ld	a,c
	cp	26
	ccf
	ret	c
	add	a,a
	ld	c,a
	add	a,a
	add	a,a
	add	a,c
	add	a,b
	ret	c
	ld	c,a
	inc	hl
	jr	gn_1
gn_9:	ld	a,c
	or	a
	ret

; USER n
cuser:	call	skipsp
	call	getnum
	jp	c,dc_what
	cp	16
	jp	nc,dc_what
	ld	(scb+SCB_USER),a
	jp	shell

; CP from to, COPY from to. "to" may be a drive. "from" may have
; wildcards when "to" is a drive. The copy is byte exact.
ccp:	xor	a
	db	01h			; LD BC,nn: skips the LD A,1
cmv:	ld	a,1
	ld	(mvflag),a
	ld	de,cpsrc
	call	argcp
	ld	a,(fdrive)		; the source drive, made explicit
	inc	a
	ld	(cpsrc),a
	ld	de,(dirov)		; and its folder
	ld	(srcdir),de
	ld	a,(dirovd)
	ld	(srcdrv),a
	ld	a,0FFh
	ld	(dirovd),a
	call	skipsp
	or	a
	jp	z,dc_what
	ld	de,cpdst
	call	parsep
	jp	c,dc_what
	ld	de,(dirov)
	ld	(dstdir),de
	ld	a,(dirovd)
	ld	(dstdrv),a
	call	cpsrcd
	ld	a,(cpdst)
	or	a
	jr	nz,cp_1
	ld	a,(scb+SCB_DRV)
	inc	a
	ld	(cpdst),a
cp_1:	call	cpfold
	ld	hl,cpsrc+1		; the pattern, kept for each batch
	ld	de,cppat
	ld	bc,11
	ldir
	xor	a
	ld	(cpstate),a
cp_g:	ld	hl,cppat
	ld	de,cpsrc+1
	ld	bc,11
	ldir
	call	cpsrcd
	ld	hl,cpsrc		; the names first: copying moves the
	call	cfcbset			; directory
	call	fcbdrv
	jp	nz,sherr
	call	fcbpat
	xor	a
	ld	(ncount),a
	ld	de,namebuf
	ld	(nameptr),de
	ld	a,(cpstate)		; NAMEMAX at a time: the next batch
	or	a			; from the last one's place. The
	jr	z,cp_g1			; source's entries stay in their slots
	ld	hl,(cppos)
	ld	(dpos),hl
	call	dsnext
	jr	cp_2
cp_g1:	call	dsfirst
cp_2:	jr	nz,cp_3
	ld	de,(nameptr)
	ld	bc,11
	ldir
	ld	(nameptr),de
	ld	hl,ncount
	inc	(hl)
	ld	a,(hl)
	cp	NAMEMAX
	jr	nc,cp_4m
	call	dsnext
	jr	cp_2
cp_4m:	ld	hl,(dpos)		; more may follow
	ld	(cppos),hl
	ld	a,1
	ld	(cpstate),a
	jr	cp_4
cp_3:	cp	R_NOFILE		; the last batch
	jp	nz,sherr
	ld	hl,cpstate
	ld	a,(ncount)
	or	a
	jr	nz,cp_3c
	or	(hl)			; none in a later batch: done
	jp	z,she_nf
	jp	shell
cp_3c:	ld	(hl),0
cp_4:
	cp	1			; several: "to" must be a drive
	jr	z,cp_5
	ld	a,(cpdst+1)
	cp	' '
	jp	nz,dc_what
cp_5:	ld	hl,namebuf
	ld	(nameptr),hl
cp_6:	ld	hl,(nameptr)		; one file: source name
	ld	de,cpsrc+1
	ld	bc,11
	ldir
	ld	(nameptr),hl
	ld	hl,cpdst			; the destination name: its own, or
	ld	de,cpdst2		; the source's
	ld	bc,12
	ldir
	ld	a,(cpdst+1)
	cp	' '
	jr	nz,cp_7
	ld	hl,cpsrc+1
	ld	de,cpdst2+1
	ld	bc,11
	ldir
cp_7:	ld	hl,cpdst2+1		; a ? in the new name takes the
	ld	de,cpsrc+1		; source's letter, so a wildcard is never
	ld	b,11			; made, or erased when the disk fills
cp_w:	ld	a,(hl)
	cp	'?'
	jr	nz,cp_w2
	ld	a,(de)
	ld	(hl),a
cp_w2:	inc	hl
	inc	de
	djnz	cp_w
	call	crlf
	ld	hl,cpsrc+1
	call	pname
	ld	a,(mvflag)
	or	a
	jr	nz,cp_mv
	call	copy1
	jr	cp_8
cp_mv:	call	mvone
cp_8:	call	kbreak
	ld	hl,ncount
	dec	(hl)
	jr	nz,cp_6
	ld	a,(cpstate)
	or	a
	jp	z,shell
	jp	cp_g

; If "to" is the name of a folder, with no \ after it, that folder
; becomes the destination and the name is left blank
cpfold:	ld	hl,cpdst+1
	ld	a,(hl)
	cp	' '
	ret	z
	ld	b,11
cf_1:	ld	a,(hl)			; no wildcards
	cp	'?'
	ret	z
	inc	hl
	djnz	cf_1
	call	cpdstd
	ld	hl,cpdst
	call	cfcbset
	call	fcbdrv
	ret	nz
	ld	hl,CFCB+F_NAME
	call	namepat
	call	wpfind
	ret	nz
	ld	(dstdir),hl
	ld	a,(drvnum)
	ld	(dstdrv),a
	ld	hl,cpdst+1
	ld	de,cpdst+2
	ld	bc,10
	ld	(hl),' '
	ldir
	ret

; MV one file, cpsrc to cpdst2. In one folder a rename, to another
; folder on the drive the directory entry moves, to another drive a
; copy and the source erased after it. A ? in the new name keeps the
; source's character.
mvone:	call	cpsrcd
	ld	hl,cpsrc
	call	cfcbset
	call	fcbdrv
	jp	nz,sherr
	ld	a,(drvnum)
	push	af
	ld	hl,(dircl)
	push	hl
	call	cpdstd
	ld	hl,cpdst2
	call	cfcbset
	call	fcbdrv
	jp	nz,sherr
	pop	de			; the source's folder and drive
	pop	af
	ld	hl,drvnum
	cp	(hl)
	jr	nz,mv_x
	ld	hl,(dircl)
	ld	(mvdst),hl
	or	a
	sbc	hl,de
	push	af
	call	cpsrcd
	ld	hl,cpsrc
	call	cfcbset
	ld	hl,cpdst2+1
	ld	de,CFCB+17
	ld	bc,11
	ldir
	pop	af
	jr	nz,mv_3
	call	frename
	jr	mv_4
mv_3:	call	fmove
mv_4:	jp	nz,sherr
	or	a
	ret	z
mv_tk:	call	crlf
	call	pmsg
	db	"No file, or the new name is taken",0
	jp	shell
mv_x:	ld	hl,CFCB+F_NAME		; another drive: the name must be free
	call	fcbpat			; there too, file or folder, or the copy
	call	dsany			; would replace it
	jr	z,mv_tk
	cp	R_NOFILE
	jp	nz,sherr
	call	copy1
	call	cpsrcd
	ld	hl,cpsrc
	call	cfcbset
	call	fdelete
	jp	fchk

; CFCB to DE, or HL to CFCB: the 36 bytes of an FCB
fromcfcb: ld	hl,CFCB
	jr	fc_36
tocfcb:	ld	de,CFCB
fc_36:	ld	bc,36
	ldir
	ret

; Copy cpsrc to cpdst2, byte exact
copy1:	call	cpsrcd
	ld	hl,cpsrc		; open the source, keep its FCB
	call	cfcbset
	call	fopen
	call	fchk
	ld	hl,(dircl)
	ld	(srcreal),hl
	ld	de,srcfcb
	call	fromcfcb
	call	cpdstd			; the same file? The same drive,
	ld	hl,cpdst2		; folder and name
	call	cfcbset
	call	fcbdrv
	call	fchk
	ld	a,(srcfcb+F_DRIVE)
	ld	b,a
	ld	a,(cpdst2)
	dec	a
	cp	b
	jr	nz,c1_0
	ld	hl,(srcreal)
	ld	de,(dircl)
	or	a
	sbc	hl,de
	jr	nz,c1_0
	ld	hl,srcfcb+F_NAME
	ld	de,cpdst2+1
	ld	b,11
	call	match
	jr	nz,c1_0
	call	pmsg
	db	": the same file",0
	ret
c1_0:	ld	hl,cpdst2		; make the destination
	call	cfcbset
	call	fmake
	call	fchk
	ld	de,dstfcb
	call	fromcfcb
	ld	hl,0
	ld	(cprec),hl
	ld	hl,6			; the TPA, free while the shell runs, from
	ld	de,CBUF			; 0100h to the BDOS entry in page zero:
	ld	bc,2			; read it full, then write it out, so
	call	ucopy			; from disk to disk the heads move once
	ld	hl,(CBUF)		; a fill, not every few records
	ld	l,0
	ld	(cptop),hl
c1_1:	ld	hl,0100h
	ld	(cpptr),hl
	ld	hl,0
	ld	(cpn),hl
	xor	a
	ld	(cpeof),a
c1_2:	ld	hl,(cpptr)		; the TPA full?
	ld	de,(cptop)
	or	a
	sbc	hl,de
	jr	nc,c1_4
	ld	hl,srcfcb		; a record from the source
	call	tocfcb
	ld	hl,(cprec)
	ld	de,(cpn)
	add	hl,de
	jr	c,c1_8m			; 8M, as BDOS reads end there
	call	rdrec
	jr	nz,c1_rer
	push	af
	ld	de,srcfcb
	call	fromcfcb
	pop	af
	or	a
	jr	nz,c1_3
	ld	hl,CBUF			; into the TPA
	ld	de,(cpptr)
	ld	bc,128
	call	ucopy
	ld	(cpptr),de
	ld	hl,(cpn)
	inc	hl
	ld	(cpn),hl
	jr	c1_2
c1_8m:	ld	a,2			; cut at 8M: 2, and the ld bc
	db	01h			; skips the ld a,1
c1_3:	ld	a,1			; the end of the source
	ld	(cpeof),a
c1_4:	ld	hl,0100h		; then all of it to the destination
	ld	(cpptr),hl
c1_5:	ld	hl,(cpn)
	ld	a,h
	or	l
	jr	z,c1_6
	ld	hl,(cpptr)
	ld	de,CBUF
	ld	bc,128
	call	ucopy
	ld	(cpptr),hl
	ld	hl,dstfcb
	call	tocfcb
	ld	hl,(cprec)
	call	wrrec
	jr	nz,c1_err
	ld	de,dstfcb
	call	fromcfcb
	ld	hl,(cprec)
	inc	hl
	ld	(cprec),hl
	ld	hl,(cpn)
	dec	hl
	ld	(cpn),hl
	jr	c1_5
; A read or a write failed: close the part written, so its clusters
; are in its entry, and erase it, then the error
c1_rer:	push	af			; a read: the source's FCB in CFCB
	ld	hl,dstfcb
	call	tocfcb
	pop	af
c1_err:	push	af
	call	fclose
	call	cpdstd
	ld	hl,cpdst2
	call	cfcbset
	call	fdelete
	pop	af
	jp	sherr
c1_6:	ld	a,(cpeof)
	or	a
	jp	z,c1_1
c1_9:	ld	hl,dstfcb		; the exact size, then close
	call	tocfcb			; A is cpeof, kept
	dec	a			; cut at 8M: the size written
	jr	nz,c1_cl
	ld	hl,srcfcb+F_SIZE
	ld	de,CFCB+F_SIZE
	ld	bc,4
	ldir
	ld	a,(CFCB+F_FLAG)
	or	1
	ld	(CFCB+F_FLAG),a
c1_cl:	call	fclose
	jp	nz,sherr
	ret

; CLS, CLEAR
cclear:	ld	a,1Ah			; clear, as Lobo's BIOS
	call	kputc
	jp	shell

; VER
cver:	call	crlf
	call	psign
	jp	shell

; HELP
; HELP topic: CP/M 3's HELP.COM, if there is one
chelp:	call	skipsp
	or	a
	jr	z,ch_1
	call	tryprog
ch_1:	call	pmsg
	db	0Dh,0Ah
	db	"DIR, LS [d:][name]      list files",0Dh,0Ah
	db	"TYPE, CAT name          show a text file",0Dh,0Ah
	db	"ERA, RM, DEL name       delete",0Dh,0Ah
	db	"REN new=old             rename",0Dh,0Ah
	db	"MV old new              rename, or move",0Dh,0Ah
	db	"CP, COPY from to        copy, byte exact",0Dh,0Ah
	db	"SAVE n name             save n pages from 0100h",0Dh,0Ah
	db	"USER n, FREE [d:], CLS, VER",0Dh,0Ah
	db	"FORMAT d: [MB]          make a boot disk, MB for the hard disk",0Dh,0Ah
	db	"SYS d:                  put the system on a disk",0Dh,0Ah
	db	"d:                      change drive",0Dh,0Ah
	db	"CD [path], PWD          change or show the folder",0Dh,0Ah
	db	"MD, MKDIR path          make a folder",0Dh,0Ah
	db	"RD, RMDIR path          remove an empty folder",0Dh,0Ah
	db	"NAME                    run NAME.COM, NAME.SUB or NAME.BAT",0Dh,0Ah
	db	"SUBMIT name             run NAME.SUB, $1 to $9 from the line",0Dh,0Ah
	db	"HELP topic              CP/M 3's HELP.COM",0
	jp	shell

; ------------------------------------------------------------------
; Batch files

; Take the last line of A:$$$.SUB into linebuf, NUL ended, and cut it
; off, or with subact 2 the next line of subbuf. NZ when there is none
; left (and subact is cleared). subact 3: a $$$.SUB that could not be
; cut, so none until the next SUBMIT.
subline: ld	a,(subact)
	cp	3
	jr	z,sl_off
	cp	2
	jr	nz,sl_file
	ld	bc,(subnext)
	ld	hl,(subtot)
	or	a
	sbc	hl,bc
	jr	z,sl_none
	inc	bc
	ld	(subnext),bc
	dec	bc
	call	subnth
	call	subexp
	jr	sl_cpy
sl_file: ld	hl,subname
	call	cfcbset
	call	fopenq
	jr	nz,sl_none
	call	nrecs
	ld	a,h
	or	l
	jr	z,sl_del
	dec	hl
	push	hl
	call	rdrec
	pop	hl
	jr	nz,sl_none
	or	a
	jr	nz,sl_none
	push	hl
	call	sl_cpy
	pop	hl			; cut the record off
	ld	a,h			; record 0, the last line: the file
	or	l			; goes. Not the size's low 16 bits,
	jr	z,sl_del1		; 0 at record 512 too
	ld	a,h
	ld	h,l
	ld	l,0
	srl	a
	rr	h
	rr	l
	ld	(CFCB+F_SIZE),hl
	ld	(CFCB+F_SIZE+2),a
	ld	a,1
	ld	(CFCB+F_FLAG),a
	call	ftrunc			; not cut, on a protected disk: the
	jr	nz,sl_bad		; line runs once and the batch stops,
	call	fclose			; or it would run for ever
	jr	nz,sl_bad
	xor	a
	ret
sl_bad:	ld	a,3
	ld	(subact),a
	xor	a
	ret
sl_off:	or	a			; NZ: none
	ret
sl_del1: push	af			; the last line: the file goes
	call	sl_kill
	pop	af
	xor	a
	ret
sl_del:	call	sl_kill
sl_none: xor	a
	ld	(subact),a
	inc	a
	ret
sl_kill: ld	hl,subname
	call	cfcbset
	jp	fdelete
; The line in CBUF, count then text, into linebuf. Z.
sl_cpy:	ld	a,(CBUF)
	cp	127
	jr	c,sl_1
	ld	a,127
sl_1:	ld	c,a
	ld	b,0
	ld	hl,CBUF+1
	ld	de,linebuf
	or	a
	jr	z,sl_2
	ldir
sl_2:	xor	a
	ld	(de),a
	ret

; At a cold boot with no batch waiting: A:AUTOEXEC.BAT, if there is
; one, as a batch with no parameters. Carry if there is none.
autoex:	ld	hl,autonm
	ld	de,cmdfcb
	ld	bc,12
	ldir
	ld	(cmdtail),hl		; at the 0 after the name
	ld	hl,batext
	jr	runsb
autonm:	db	0,"AUTOEXEC   ",0

; NAME.SUB, or NAME.BAT, with the tail as $1-$9: write A:$$$.SUB,
; lines last first. Carry if there is neither.
runsub:	ld	hl,subext
	call	runsb
	ret	nc
	ld	hl,batext
runsb:	push	hl
	ld	hl,cmdfcb
	call	cfcbset
	pop	hl
	call	fextq
	jr	z,ru_1
	ld	a,(cmdfcb)		; on A: too, if not on A: already
	or	a
	scf
	ret	nz
	ld	a,(scb+SCB_DRV)
	or	a
	scf
	ret	z
	ld	a,1
	ld	(CFCB),a
	call	fopenq
	scf
	ret	nz
ru_1:	ld	hl,0			; the file into subbuf
	ld	de,subbuf
ru_2:	push	hl
	push	de
	call	rdrec
	pop	de
	pop	hl
	jp	nz,sherr
	or	a
	jr	nz,ru_3
	push	hl
	ld	hl,subbuf+SUBMAX-128	; room for it?
	or	a
	sbc	hl,de
	pop	hl
	jr	c,ru_big
	push	hl
	ld	hl,CBUF
	ld	bc,128
	ldir
	pop	hl
	inc	hl
	jr	ru_2
ru_big:	call	crlf			; not cut short: none of it runs
	call	pmsg
	db	"Batch file too long",0
	jp	shell
ru_3:	ld	hl,subbuf+SUBMAX	; ends at ^Z: one after the text, when
	or	a			; there is room, else the file's own
	sbc	hl,de
	jr	z,ru_3f
	ld	a,1Ah
	ld	(de),a
	jr	ru_3g
ru_3f:	ld	hl,subbuf
	ld	bc,SUBMAX
	ld	a,1Ah
	cpir
	jr	nz,ru_big
ru_3g:
	ld	hl,(cmdtail)		; the parameters: words of the tail
	call	splitargs
	ld	hl,subbuf		; count the lines
	ld	bc,0
ru_4:	ld	a,(hl)
	cp	1Ah
	jr	z,ru_6
	inc	bc
ru_5:	ld	a,(hl)
	inc	hl
	cp	1Ah
	jr	z,ru_5e
	cp	0Ah
	jr	nz,ru_5
	jr	ru_4
ru_5e:	dec	hl
	jr	ru_4
ru_6:	ld	(sublines),bc
	ld	(subtot),bc
	ld	hl,subname		; make A:$$$.SUB, or, when A: is
	call	cfcbset			; write protected or full, run
	call	fmake			; the lines from subbuf
	jr	nz,ru_mem
	or	a
	jr	nz,ru_mem
	ld	hl,0			; record number
	ld	(cprec),hl
ru_7:	ld	bc,(sublines)		; the lines, last first
	ld	a,b
	or	c
	jr	z,ru_9
	dec	bc
	ld	(sublines),bc
	call	subnth			; HL = line BC
	call	subexp			; into CBUF, expanded
	ld	hl,(cprec)
	push	hl
	call	wrrec
	pop	hl
	jr	nz,ru_bad
	inc	hl
	ld	(cprec),hl
	jr	ru_7
ru_9:	call	fclose
	jr	nz,ru_bad
	ld	a,1
	ld	(subact),a
	or	a
	ret
ru_bad:	call	sl_kill			; a part written: none of it
ru_mem:	ld	hl,0			; from memory, first line first
	ld	(subnext),hl
	ld	a,2
	ld	(subact),a
	or	a
	ret
subext:	db	"SUB"
batext:	db	"BAT"

; HL = the start of line BC of subbuf
subnth:	ld	hl,subbuf
sn__1:	ld	a,b
	or	c
	ret	z
sn__2:	ld	a,(hl)
	inc	hl
	cp	0Ah
	jr	nz,sn__2
	dec	bc
	jr	sn__1

; The line at HL into CBUF as SUBMIT's record: count, text, $n
; replaced with parameter n and $$ with $. CR, LF and ^Z end it.
subexp:	ld	de,CBUF+1
	ld	c,0
se__1:	ld	a,(hl)
	cp	0Dh
	jr	z,se__9
	cp	0Ah
	jr	z,se__9
	cp	1Ah
	jr	z,se__9
	inc	hl
	cp	'$'
	jr	nz,se__3
	ld	a,(hl)
	cp	'$'
	jr	z,se__2
	sub	'1'
	jr	c,se__d
	cp	9
	jr	nc,se__d
	inc	hl
	push	hl
	call	argn			; HL = parameter A, NUL ended
se__p:	ld	a,(hl)
	or	a
	jr	z,se__q
	call	se__put
	inc	hl
	jr	se__p
se__q:	pop	hl
	jr	se__1
se__d:	ld	a,'$'
	jr	se__3
se__2:	inc	hl
se__3:	call	se__put
	jr	se__1
se__9:	ld	a,c
	ld	(CBUF),a
	xor	a
	ld	(de),a
	ret
se__put: push	af
	ld	a,c
	cp	125
	jr	nc,se__x
	pop	af
	call	upper
	ld	(de),a
	inc	de
	inc	c
	ret
se__x:	pop	af
	ret

; Split the tail at HL into words in argbuf, NUL ended, argc of them
splitargs:
	ld	de,argbuf
	xor	a
	ld	(argc),a
sa__1:	call	skipsp
	or	a
	jr	z,sa__9
	ld	a,(argc)
	inc	a
	ld	(argc),a
sa__2:	ld	a,(hl)
	or	a
	jr	z,sa__3
	cp	' '
	jr	z,sa__3
	ld	(de),a
	inc	hl
	inc	de
	jr	sa__2
sa__3:	xor	a
	ld	(de),a
	inc	de
	jr	sa__1
sa__9:	ret

; SUBMIT name params: as NAME params, here in the shell.
csubmit: call	skipsp
	or	a
	jr	z,cs_use
	ld	de,cmdfcb
	call	parsefn
	jp	c,dc_what
	ld	(cmdtail),hl
	jp	dc_sub
cs_use:	call	pmsg
	db	0Dh,0Ah,"SUBMIT name [parameters]",0Dh,0Ah,0
	jp	shell

; HL = word A (0 is $1) of argbuf, or an empty string
argn:	ld	b,a
	ld	a,(argc)
	cp	b
	ld	hl,empty
	ret	z
	ret	c
	ld	hl,argbuf
	inc	b
an__1:	dec	b
	ret	z
an__2:	ld	a,(hl)
	inc	hl
	or	a
	jr	nz,an__2
	jr	an__1
empty:	db	0

