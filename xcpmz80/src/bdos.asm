; xcpmz80 BDOS. Runs in A2, called from bdosent in common memory
; with C = function and DE = parameter, which in a program's call is a
; TPA address. Returns HL. The functions of CP/M 2.2 and the ones of
; CP/M 3 that programs use, on FAT files.

kbdos:	ld	(bparam),de
	xor	a
	ld	(wbdrv),a
	ld	a,c
	ld	(bfunc),a
	ld	hl,0
	ld	(bret),hl
	ld	hl,bdret		; every function returns through bdret
	push	hl
	cp	NFUNC
	jr	c,kb_1
	sub	98			; 98-112
	jr	c,kb_none
	cp	15
	jr	c,kb_2
	cp	152-98
	jp	z,f152
	sub	118-98			; 118-125, the folders
	cp	8
	ret	nc
	ld	l,a
	ld	h,0
	add	hl,hl
	ld	bc,xtab
	jr	kb_3
kb_none: ret
kb_2:	add	a,NFUNC
kb_1:	ld	l,a
	ld	h,0
	add	hl,hl
	ld	bc,ftab		; DE stays the parameter
kb_3:	add	hl,bc
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	a,e
	jp	(hl)

bdret:	ld	hl,(bret)
	ret

; Return FFh, or A (in L, H = 0)
fff:	ld	a,0FFh
retA:	ld	l,a
	ld	h,0
	ld	(bret),hl
	ret

NFUNC	equ	61
ftab:	dw	f0,f1,f2,f3,f4,f5,f6,f7,f8,f9
	dw	f10,f11,f12,f13,f14,f15,f16,f17,f18,f19
	dw	f20,f21,f22,f23,f24,f25,f26,f27,f28,f29
	dw	f30,f31,f32,f33,f34,f35,f36,f37,fnone,fnone
	dw	f40,fff,fnone,fnone,f44,f45,f46,f47,f48,f49
	dw	f50,fnone,fnone,fnone,fnone,fnone,fnone,fnone,fnone,f59
	dw	fff
	dw	fnone,f99,fnone,fnone,f102,fnone,fnone,f105,fnone,f107
; 98 free blocks, 100 and 101 the directory label, 104 set the clock
; (only with its button held): nothing to do, 0
	dw	f108,f109,f110,f111,f112

fnone:	ret

; The folder functions. DE is a path, NUL ended. A = 0, or FFh.
xtab:	dw	f118,f119,fnone,fnone,fnone,fnone,f124,f125
f118:	call	bpath
	call	xmkdir
	jr	fxret
f119:	call	bpath
	call	xrmdir
	jr	fxret
f124:	call	bpath
	xor	a
	ld	(wlast),a
	call	walk
	jp	nz,fff
	call	cdset
	xor	a
fxret:	jp	nz,fff
	xor	a
	jp	retA
; 125: the current drive's folder into DE, as \GAMES, NUL ended
f125:	ld	a,(scb+SCB_DRV)
	call	pthptr
	ld	de,(bparam)
	ld	a,5Ch
f125_1:	ex	de,hl
	call	upoke
	inc	hl
	ex	de,hl
	ld	a,(hl)
	inc	hl
	or	a
	jr	nz,f125_1
	ex	de,hl
	jp	upoke
; The program's path at DE into linebuf, upper case. HL = linebuf.
bpath:	ld	hl,(bparam)
	ld	de,linebuf
	ld	b,127
bp_1:	call	upeek
	call	upper
	ld	(de),a
	or	a
	jr	z,bp_2
	inc	hl
	inc	de
	djnz	bp_1
	xor	a
	ld	(de),a
bp_2:	ld	hl,linebuf
	ret

; 59: load overlay. DE = 0, from the CCP and RSXs: remove the RSXs
; that set their remove flag. Else the file of the FCB at DE goes into
; the TPA from the address in its random record field: A = 0, FFh if
; there is no such file, FEh if it does not fit under 0006h. The
; shell's own 59, made so the RSXs see a program load, as CP/M 3's
; CCP loads by 59, is taken as done. 60, call an RSX, gets here when
; no RSX took it: FFh.
f59:	ld	a,d
	or	e
	jp	z,rsxfree		; A = 0, as bret is
	ld	a,(ldown)
	or	a
	ret	nz
	call	fcbin0
	call	fopen
	jp	nz,dskerr
	cp	R_NOFILE
	jp	z,retA
	ld	hl,(CFCB+F_R0)
	ld	(prdest),hl
	ld	hl,0
	ld	(prfrom),hl
f59_3:	ld	hl,(prfrom)		; record by record
	call	rdrec
	jp	nz,dskerr
	or	a
	ret	nz
	ld	hl,0007h		; under 0006h?
	call	upeek
	ld	c,a
	ld	hl,(prdest)
	ld	de,127
	add	hl,de
	jr	c,f59_big
	ld	a,h
	cp	c
	jr	nc,f59_big
	ld	hl,CBUF
	ld	de,(prdest)
	ld	bc,128
	call	ucopy
	ld	(prdest),de
	ld	hl,(prfrom)
	inc	hl
	ld	(prfrom),hl
	jr	f59_3
f59_big: ld	a,0FEh
	jp	retA

; 0: system reset, the end of the program
f0:	jp	wboot

; ------------------------------------------------------------------
; Console

; 1: read a character, with echo
f1:	call	xconin			; a patched CONIN too, as 6 and 10
	push	af
	call	echo
	pop	af
	jp	retA

; Echo A as CP/M does: printing characters, CR, LF, BS and tab
echo:	cp	' '
	jp	nc,kputc
	cp	0Dh
	jp	z,kputc
	cp	08h			; BS, tab and LF
	ret	c
	cp	0Bh
	jp	c,kputc
	ret


; 2: write E, tabs expanded. ^S stops the output until the next key.
f2:	call	brkchk			; keeps DE
	ld	a,e
	jp	kputc

; ^S waiting? Wait for the next key, and ^C then ends the program.
; Not when console mode bit 1 is set.
brkchk:	ld	a,(scb+SCB_CMODE)
	and	02h
	ret	nz
	call	kpeek
	cp	13h
	ret	nz
	call	xconin
	call	xconin
	cp	03h
	ret	nz
	jp	wboot

; 3: AUX in, 4: AUX out, 5: list out
f3:	call	auxin
	jp	retA
f4:	ld	c,e
	jp	auxout
f5:	ld	c,e
	jp	list

; 6: direct console I/O. FFh: a key or 0. FEh: status. FDh: wait for a
; key. Else write E as it is.
f6:	inc	a
	jr	z,f6_ff
	inc	a
	jr	z,f6_fe
	inc	a
	jr	z,f6_fd
	ld	c,e
	jp	conout
f6_ff:	call	xconst
	ret	z			; 0, in bret
f6_fd:	call	xconin
	jp	retA
f6_fe:	call	xconst
	jp	retA

; 7, 8: IOBYTE, at 0003h in the TPA
f7:	ld	hl,0003h
	call	upeek
	jp	retA
f8:	ld	hl,0003h
	jp	upoke

; 9: print the string at DE up to the delimiter ('$')
f9:	ex	de,hl
f9_1:	ld	de,CBUF			; 32 bytes at a time into CBUF: most
	ld	bc,32			; strings are short, and a copy of 128
	call	ucopy			; cost more than printing them
	ld	de,CBUF			; HL moves on to the next chunk
	ld	a,(scb+SCB_DELIM)
	ld	c,a
	ld	b,32
f9_2:	ld	a,(de)
	cp	c
	ret	z
	call	brkchk			; keeps BC, DE, HL
	ld	a,(de)
	call	kputc
	inc	de
	djnz	f9_2
	jr	f9_1

; 10: read a line into the buffer at DE: max, count, characters. The
; editing keys of CP/M: BS, DEL and the back arrow rub out, ^X and ^U kill the line,
; ^R types it again, ^E goes to a new line, ^P echoes to the printer,
; ^C at the start ends the program. CR or LF ends the line, and only CR
; is echoed.
f10:	ld	a,d
	or	e
	jr	nz,f10_1
	ld	de,(scb+SCB_DMA)	; CP/M 3: 0 means the DMA buffer
	ld	(bparam),de
f10_1:	ex	de,hl
	call	upeek			; the maximum
	ld	(lnmax),a
	ld	a,(scb+SCB_COL)
	ld	(lnstart),a
	ld	(lnend),a
	call	rdline
	ld	hl,(bparam)		; count and text back to the program, a
	inc	hl			; byte at a time: up to 255 (I283)
	ld	a,(lnlen)
	call	upoke
	or	a
	ret	z
	ld	b,a
	ld	de,linebuf
f10_2:	inc	hl
	ld	a,(de)
	call	upoke
	inc	de
	djnz	f10_2
	ret

; Read a line into linebuf, lnlen long, at most lnmax. Each key's
; handler returns to rl1, which it finds on the stack.
rdline:	xor	a
	ld	(lnlen),a
rl1:	ld	hl,rl1
	push	hl
	call	xconin
	cp	0Dh
	jr	z,rlend
	cp	0Ah
	jr	z,rlend
	cp	08h
	jp	z,rlbs
	cp	7Fh
	jr	z,rlbs
	cp	1Eh			; the back arrow, 08h on Lobo's 5.25-inch
	jr	z,rlbs			; CP/M 2.2
	cp	18h			; ^X
	jp	z,rlkill
	cp	1Ch			; UP, at the shell's prompt
	jp	z,rlup
	cp	15h			; ^U
	jp	z,rlkill
	cp	12h			; ^R
	jr	z,rlretype
	cp	05h			; ^E: the line again from the start of
	jp	z,rle			; the next row, so the back arrow knows
	cp	10h			; ^P
	jr	z,rlprn
	cp	03h			; ^C
	jr	nz,rl2
	ld	hl,lnlen		; at the start of the line?
	inc	(hl)
	dec	(hl)
	jr	nz,rl2
	call	ctlout			; shown as ^C
	jp	wboot
rl2:	ld	b,a			; into the line
	ld	a,(lnmax)
	ld	c,a
	ld	a,(lnlen)
	cp	c
	ret	nc			; full
	ld	e,a
	ld	d,0
	ld	hl,linebuf
	add	hl,de
	ld	(hl),b
	inc	a
	ld	(lnlen),a
	ld	a,b
	call	ctlout
	ld	a,(lnmax)		; full: the line ends, as CP/M's does
	ld	hl,lnlen		; (I283)
	cp	(hl)
	ret	nz
rlend:	pop	hl			; the line is done
	ld	a,0Dh
	jp	kputc
rlprn:	ld	a,(scb+SCB_LIST)
	xor	1
	ld	(scb+SCB_LIST),a
	ret
rle:	xor	a			; ^E
	ld	(lnstart),a
	ld	(lnend),a
rlretype: call	crlf
	ld	a,(lnstart)
	or	a
	jp	z,rltype
	ld	b,a
rr1:	call	space
	djnz	rr1
	jp	rltype

; Rub out the last character: a printable one away from the start of a
; screen row goes by BS, space, BS, so the rest of the line stays as it
; is, and at the start of a wrapped row it steps up to the end of the
; row above. A control character shown as ^X or a tab retypes
; the line.
rlbs:	ld	a,(lnlen)
	or	a
	ret	z
	dec	a
	ld	b,a
	ld	e,a
	ld	d,0
	ld	hl,linebuf
	add	hl,de
	ld	a,(hl)
	cp	' '
	jr	c,rlbs_2
	cp	7Fh
	jr	nc,rlbs_2
	ld	a,(CURCOL)		; the screen's column, not SCB_COL, which
	or	a			; output by function 6 leaves behind
	jr	z,rlbs_up
	ld	a,b
	ld	(lnlen),a
	ld	a,08h
	call	kputc
	call	space
	ld	a,08h
	jp	kputc
rlbs_up: ld	a,b			; at the start of a wrapped row: the
	ld	(lnlen),a		; last column of the row above
	call	rlrow
	call	space			; which wraps back down
	call	rlrow
	ld	hl,scb+SCB_COL		; one column less than before the space
	dec	(hl)
	dec	(hl)
	ret
; Up, and right to the last column, on the screen alone: not to the
; printer (^P), and SCB_COL is left as it was. Keeps BC.
rlrow:	push	bc
	ld	c,0Bh
	call	conout
	ld	b,COLS-1
	ld	c,0Ch
rlrw_1:	call	conout
	djnz	rlrw_1
	pop	bc
	ret
; Back one column, up to the end of the row above from the start of a
; wrapped row, where a BS would stop. Keeps BC and HL.
rlback:	ld	a,(CURCOL)		; the screen's column, as rlbs
	or	a
	jr	z,rlbk_up
	ld	a,08h
	jp	kputc
rlbk_up: call	rlrow
	push	hl
	ld	hl,scb+SCB_COL
	dec	(hl)
	pop	hl
	ret
rlbs_2:	ld	a,b
	jr	rlset
rlkill:	xor	a
rlset:	ld	(lnlen),a		; simplest right: retype what is left

; Wipe the line on the screen back to where it started, and type it.
; kputc and space keep HL.
rlredo:	ld	hl,lnstart
	ld	a,(scb+SCB_COL)
	sub	(hl)
	jr	z,rltype
	jr	c,rltype
	ld	b,a
rd1:	call	rlback
	djnz	rd1
	ld	a,(lnend)		; blank to where the line reached
	sub	(hl)
	jr	c,rltype
	jr	z,rltype
	ld	b,a
	push	bc
rd2:	call	space
	djnz	rd2
	pop	bc
rd2b:	call	rlback
	djnz	rd2b
rltype:	ld	a,(lnlen)
	or	a
	ret	z
	ld	b,a
	ld	hl,linebuf
rty_1:	ld	a,(hl)
	call	ctlout
	inc	hl
	djnz	rty_1
	ret

; UP at the shell's prompt: the last line it ran, in place of this one
rlup:	ld	b,a
	ld	a,(lnhist)
	or	a
	ld	a,b
	jp	z,rl2			; elsewhere 1Ch goes in as ^\
	ld	a,(histlen)
	or	a
	ret	z
	ld	c,a
	ld	b,0
	ld	hl,histbuf
	ld	de,linebuf
	ldir
	ld	a,(histlen)
	jp	rlset

; Echo A as the line editor shows it: control characters as ^X, tabs
; expanded. Note the furthest column reached in lnend. Keeps BC.
ctlout:	cp	' '
	jr	nc,co1
	cp	09h
	jr	z,co1
	push	af
	ld	a,'^'
	call	kputc
	pop	af
	add	a,'@'
co1:	call	kputc
	push	bc
	ld	a,(lnend)
	ld	b,a
	ld	a,(scb+SCB_COL)
	cp	b
	pop	bc
	ret	c
	ld	(lnend),a
	ret

; 11: console status: 1 if a key is waiting
f11:	ld	a,(scb+SCB_CMODE)	; mode bit 0: 1 only for a ^C waiting,
	rra				; as CP/M 3's
	jr	nc,f11_n
	call	kpeek
	cp	3
	ret	nz
	ld	a,1
	jp	retA
f11_n:	call	xconst
	ret	z
	ld	a,1
	jp	retA

; 12: version: CP/M 3.1 file system
f12:	ld	a,31h
	jp	retA

; ------------------------------------------------------------------
; Disks and files

; 13: reset the disk system: everything written, floppies to be read
; again, DMA 0080h, drive A:
f13:	call	kreset
	xor	a
	ld	(scb+SCB_DRV),a
	ret

kreset:	call	flushall
	ld	b,NDRV			; forget every floppy: it may be changed
	xor	a
kr_1:	push	af
	push	bc
	call	drvix
	ld	(ix+D_RO),0		; every drive read-write again
	ld	a,(ix+D_TYPE)
	cp	DT_FLOPPY
	jr	nz,kr_2
	pop	bc
	pop	af
	push	af
	push	bc
	call	umount
kr_2:	pop	bc
	pop	af
	inc	a
	djnz	kr_1
	ld	hl,0080h
	ld	(scb+SCB_DMA),hl
	ret

; 14: select drive E
f14:	ld	a,e
	push	af
	call	dmount
	pop	bc
	jp	nz,dskerr
	ld	a,b
	ld	(scb+SCB_DRV),a
	ret

; 15: open
f15:	call	fcbin0
	call	fopen
	jp	nz,dskerr
	or	a
	call	z,extchk
fcbout33: push	af			; the FCB back, 33 bytes
	ld	bc,33
fo_cp:	ld	hl,CFCB
	ld	de,(bparam)
	call	ucopy
	pop	af
	jp	retA
fcbout36: push	af
	ld	bc,36
	jr	fo_cp

; A = 0 if the FCB's extent is in the file, or in the directory entry
; that holds one of its records, as CP/M has it, else FFh and the FCB
; is not open. An entry holds 16K << entk, from the DPB of the file's
; drive, made here and the program's put back.
extchk:	ld	a,(CFCB+F_EX)
	and	1Fh
	ret	z
	ld	hl,DPB
	ld	de,CBUF
	ld	bc,17
	ldir
	ld	hl,dirblks		; and dirblks, blkk, entk, bnsz
	ld	bc,4
	ldir
	ld	a,(fdrive)
	call	drvix
	call	mkdpb
	ld	a,(entk)
	push	af
	ld	hl,CBUF
	ld	de,DPB
	ld	bc,17
	ldir
	ld	de,dirblks
	ld	bc,4
	ldir
	pop	bc			; B = entk: EX without its low bits
	ld	a,0FFh
	inc	b
ec_1:	dec	b
	jr	z,ec_2
	add	a,a
	jr	ec_1
ec_2:	ld	b,a
	ld	a,(CFCB+F_EX)
	and	1Fh
	and	b
	ld	l,a			; the entry's first record
	ld	h,0
	ld	b,7
ec_3:	add	hl,hl
	djnz	ec_3
	ld	a,h
	or	l
	ret	z			; A = 0: the first entry, always there
	ex	de,hl
	call	nrecs			; HL = the file's records
	jr	c,ec_ok
	or	a
	sbc	hl,de
	jr	z,ec_no
	jr	c,ec_no
ec_ok:	xor	a
	ret
ec_no:	xor	a
	ld	(CFCB+F_MAGIC),a
	dec	a
	ret

; Open and make set S2 to 0, as CP/M's do: a program may leave anything
; there (MAC does)
fcbin0:	call	fcbin
s2zero:	xor	a
	ld	(CFCB+F_S2),a
	ret

; Copy the program's FCB at DE into CFCB
fcbin:	ex	de,hl
	ld	de,CFCB
	ld	bc,36
	call	ucopy
	ld	hl,CFCB+F_NAME
	; fall into nameup

; Upper-case the 11 name bytes at HL, keeping the attribute bits: FAT
; short names are upper case, and MBASIC, for one, passes lower case
nameup:	ld	b,11
nu_1:	ld	a,(hl)
	and	7Fh
	cp	'a'
	jr	c,nu_2
	cp	'z'+1
	jr	nc,nu_2
	ld	a,(hl)
	sub	20h
	ld	(hl),a
nu_2:	inc	hl
	djnz	nu_1
	ret

; 16: close
f16:	call	fcbin
	call	fclose
	jp	nz,dskerr
	jp	fcbout33

; 17: search first. 18: search next. A directory entry of CP/M's form
; goes to the DMA buffer at 0, and A = 0. FFh when there are no more.
; A '?' in EX gives every extent of a file, else extent 0 only.
f17:	ld	(sfcba),de
	call	fcbin
	ld	a,(CFCB+F_DR)
	sub	'?'			; every entry: as every name
	ld	(sall),a
	jr	nz,f17_1
	ld	(CFCB+F_DR),a
	ld	hl,CFCB+F_NAME
	ld	b,12
f17_0:	ld	(hl),'?'
	inc	hl
	djnz	f17_0
f17_1:	call	fcbdrv
	jp	nz,dskerr
	call	mkdpb
	ld	a,(fdrive)
	ld	(sdrive),a
	ld	a,(CFCB+F_EX)
	ld	(sexmode),a
	call	fcbpat
	ld	hl,spat
	ld	de,sspat
	ld	bc,11
	ldir
	call	dsfirst
	jr	sfound

f18:	ld	a,(sdrive)		; carry on where 17 or 18 left off
	call	dmount
	jp	nz,dskerr
	call	mkdpb
	ld	hl,sspat
	ld	de,spat
	ld	bc,11
	ldir
	ld	a,(sall)		; CP/M reads the FCB that 17 was
	or	a			; given again: CRCK puts its pattern
	jr	z,f18_1			; back in it after finding its place
	ld	de,(sfcba)
	call	fcbin
	ld	a,(CFCB+F_EX)
	ld	(sexmode),a
	call	fcbpat
f18_1:	ld	hl,(sdpos)
	ld	(dpos),hl
	ld	a,(sexmode)		; the next extent of the same file?
	cp	'?'
	jr	nz,f18_2
	call	dirent
	jp	nz,dskerr
	push	hl
	call	entexts			; A = its extents
	pop	hl
	ld	b,a
	ld	a,(sext)
	inc	a
	cp	b
	jr	nc,f18_2
	ld	(sext),a
	jr	semit
f18_2:	call	dsnext
sfound:	jr	z,sf_1
	cp	R_NOFILE
	jp	nz,dskerr
	xor	a			; none: 18 finds nothing either, not
	ld	(sall),a		; the file an earlier search was on
	ld	(sspat),a
	ld	(sexmode),a
	dec	a
	jp	retA
sf_1:	xor	a
	ld	(sext),a
	ld	a,(sexmode)		; one asked-for extent: is it there?
	cp	'?'
	jr	z,semit
	and	1Fh
	ld	b,a
	ld	a,(entk)
	inc	a
sf_2:	dec	a
	jr	z,sf_3
	srl	b
	jr	sf_2
sf_3:	ld	a,b
	ld	(sext),a
	or	a
	jr	z,semit
	push	hl
	call	entexts
	pop	hl
	ld	b,a
	ld	a,(sext)
	cp	b
	jr	c,semit
	call	dsnext
	jr	sfound

; HL = a FAT entry: put its extent sext in CP/M's form in CBUF, and
; CBUF to the DMA buffer
semit:	ld	de,(dpos)
	ld	(sdpos),de
	push	hl
	ld	hl,CBUF			; E5h after the entry
	ld	de,CBUF+1
	ld	bc,127
	ld	(hl),0E5h
	ldir
	pop	hl
	push	hl
	ld	a,(scb+SCB_USER)
	ld	de,CBUF
	ld	(de),a
	inc	de
	ld	bc,11
	ldir
	ld	a,(hl)			; attributes
	ld	hl,CBUF+9
	bit	0,a
	jr	z,se_1
	set	7,(hl)
se_1:	inc	hl
	bit	2,a
	jr	z,se_2
	set	7,(hl)
se_2:	pop	hl
	ld	de,DE_SIZE		; records of this extent
	add	hl,de
	ld	de,CFCB+F_SIZE		; through CFCB's size and EX
	ld	bc,4
	ldir
	call	lastext			; the file's last extent
	ld	(slast),hl
	ld	a,(entk)		; the entry's first, and its last:
	ld	b,a			; the first + EXM, or the file's last
	ld	hl,(sext)
	ld	h,0
	inc	b
se_s:	dec	b
	jr	z,se_t
	add	hl,hl
	jr	se_s
se_t:	ld	(sfirst),hl
	ld	a,(DPB+4)		; EXM
	ld	e,a
	ld	d,0
	add	hl,de
	ld	de,(slast)
	push	hl
	or	a
	sbc	hl,de
	pop	hl
	jr	c,se_u
	ex	de,hl
se_u:	ld	a,l			; EX and S2 of that extent
	and	1Fh
	ld	(CFCB+F_EX),a
	ld	(CBUF+12),a
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,h
	and	3Fh
	ld	(CFCB+F_S2),a
	ld	(CBUF+14),a
	xor	a
	ld	(CBUF+13),a
	call	setrc
	ld	a,(CFCB+F_RC)
	ld	(CBUF+15),a
	ld	hl,CBUF+16		; no blocks yet
	ld	b,16
se_3:	ld	(hl),0
	inc	hl
	djnz	se_3
	call	extrec			; records in the entry: those before
	ld	de,(sfirst)		; its last extent, and that one's RC
	ex	de,hl
	ld	b,7
se_r:	add	hl,hl
	djnz	se_r
	ex	de,hl
	or	a
	sbc	hl,de
	ld	a,(CFCB+F_RC)
	ld	e,a
	ld	d,0
	add	hl,de
	ld	a,(DPB+3)		; blocks = (records + BLM) >> BSH
	ld	e,a
	add	hl,de
	ld	a,(DPB+2)
	ld	b,a
se_b:	srl	h
	rr	l
	djnz	se_b
	ld	a,l
	or	a
	jr	z,se_5
	ld	b,a
	ld	hl,CBUF+16		; a 1 for each, 1 or 2 bytes
se_4:	ld	(hl),1
	inc	hl
	ld	a,(bnsz)
	cp	2
	jr	nz,se_4b
	inc	hl
se_4b:	djnz	se_4
se_5:	ld	hl,CBUF
	ld	de,(scb+SCB_DMA)
	ld	bc,128
	call	ucopy
	xor	a
	jp	retA

; A = the directory entries of the file whose entry is at HL, each
; for EXM + 1 extents: 1 at least, 255 at most
entexts: ld	de,DE_SIZE
	add	hl,de
	ld	de,CFCB+F_SIZE
	ld	bc,4
	ldir
	call	lastext
	ld	a,(entk)
	inc	a
en_1:	dec	a
	jr	z,en_2
	srl	h
	rr	l
	jr	en_1
en_2:	inc	hl
	ld	a,h
	or	a
	ld	a,l
	ret	z
	ld	a,0FFh
	ret

; HL = the number of the file's last 16K extent, from its size in CFCB:
; (records - 1) / 128, 0 for an empty file
lastext: call	nrecs
	jr	nc,le_1
	ld	hl,0FFFFh
le_1:	ld	a,h
	or	l
	ret	z
	dec	hl
	ld	a,l
	rla
	ld	l,h
	ld	h,0
	rl	l
	rl	h
	ret

; 19: delete
f19:	call	fcbin
	call	fdelete
	jp	nz,dskerr
	jp	retA

; 20: read sequential, the multi-sector count of records
f20:	call	seqopn			; B = count, C = 0 done
	jp	nz,dskerr
f20_1:	call	seqfix			; CR 128: the next extent now
	ld	a,(CFCB+F_S2)		; past 8M, 65536 records: the end
	cp	10h
	jr	nc,f20_eof
	push	bc
	call	seqrec
	call	rdrec
	pop	bc
	jp	nz,dskerr
	or	a
	jr	nz,f20_eof
	call	todma
	ld	hl,CFCB+F_CR		; CR on, to 128 at most, as CP/M 2.2
	inc	(hl)
	inc	c
	djnz	f20_1
	xor	a
f20_9:	push	bc			; fcbout33 uses BC
	call	fcbout33
	pop	bc
	or	a			; an error: H = the records done
	ret	z
	ld	a,c
	ld	(bret+1),a
	ret
f20_eof: ld	a,1
	jr	f20_9

; 21: write sequential
f21:	call	seqopn
	jp	nz,dskerr
f21_1:	call	seqfix
	ld	a,(CFCB+F_S2)		; past 8M: the disk is full for it
	cp	10h
	ld	a,E_FULL
	jr	nc,f21_err
	push	bc
	call	fromdma
	call	seqrec
	call	wrrec
	pop	bc
	jr	nz,f21_err
	ld	hl,CFCB+F_CR
	inc	(hl)
	inc	c
	djnz	f21_1
	push	bc
	call	setrc			; RC counts what was written
	pop	bc
	xor	a
	jr	f20_9
f21_err: cp	E_FULL			; disk full: CP/M's 2
	jp	nz,dskerr
	ld	a,2
	jr	f20_9

; The FCB must be ours: if not, open it now, keeping its position
fcbopen: ld	a,(CFCB+F_MAGIC)
	cp	MAGIC
	ret	z
	ld	hl,(CFCB+F_EX)		; EX and S1
	push	hl
	ld	a,(CFCB+F_S2)
	push	af
	ld	a,(CFCB+F_CR)
	push	af
	call	fopen
	ld	e,a			; its result, kept from the restores
	pop	bc
	ld	a,b
	ld	(CFCB+F_CR),a
	pop	bc
	ld	a,b
	ld	(CFCB+F_S2),a
	pop	hl
	ld	(CFCB+F_EX),hl
	ld	a,e
	ret	nz
	cp	R_NOFILE
	jr	z,fop_no
	call	setrc
	xor	a
	ret
fop_no:	ld	a,E_READ		; nothing to read or write: an error
	or	a
	ret

; HL = the sequential record: (S2 * 32 + EX) * 128 + CR, CR 128 the
; next extent's first, as function 36 counts it
seqrec:	call	extrec
	ld	a,(CFCB+F_CR)
	ld	e,a
	ld	d,0
	add	hl,de
	ret

; Sequential reads and writes leave CR at 128 after an extent's last
; record, EX as it was, as CP/M 2.2: a reopen finds that extent, and
; "CR = RC" appends to a file of whole extents. The next one moves on.
; Keeps BC.
seqfix:	ld	hl,CFCB+F_CR
	bit	7,(hl)
	ret	z
	ld	(hl),7Fh

; Move on a record: CR, then EX, then S2. A new extent gets its RC.
seqnext: ld	hl,CFCB+F_CR
	inc	(hl)
	ret	p			; CR still under 128
	ld	(hl),0
	ld	hl,CFCB+F_EX
	ld	a,(hl)
	inc	a
	and	1Fh
	ld	(hl),a
	jr	nz,sn_1
	inc	hl			; S2, two on
	assert	F_S2 == F_EX+2
	inc	hl
	inc	(hl)
sn_1:	push	bc
	call	setrc
	pop	bc
	ret

; CBUF to the program's xdma, and xdma on a record. Keeps BC.
todma:	push	bc
	ld	hl,CBUF
	ld	de,(xdma)
	ld	bc,128
	call	ucopy
	ld	(xdma),de
	pop	bc
	ret

; The program's xdma to CBUF, and xdma on a record. Keeps BC.
fromdma: push	bc
	ld	hl,(xdma)
	ld	de,CBUF
	ld	bc,128
	call	ucopy
	ld	(xdma),hl
	pop	bc
	ret

; 22: make
f22:	call	fcbin0
	call	fmake
	jp	nz,dskerr
	jp	fcbout33

; 23: rename
f23:	call	fcbin
	ld	hl,CFCB+16+F_NAME	; the new name
	call	nameup
	call	frename
	jp	nz,dskerr
	jp	retA

; 24: login vector, the drives mounted. 29: R/O vector.
f24:	ld	e,D_MNT
	jr	drvvec
f29:	ld	e,D_RO
drvvec:	ld	d,0			; DE = the drive table byte to test
	ld	b,NDRV
	ld	c,1
	ld	hl,0
	xor	a
dv_1:	push	af
	call	drvix			; keeps BC, DE, HL
	add	ix,de
	ld	a,(ix+0)
	or	a
	jr	z,dv_2
	ld	a,l
	or	c
	ld	l,a
dv_2:	sla	c
	pop	af
	inc	a
	djnz	dv_1
	ld	(bret),hl
	ret

; 25: the current drive
f25:	ld	a,(scb+SCB_DRV)
	jp	retA

; 26: set the DMA address
f26:	ld	(scb+SCB_DMA),de
	ret

; 27: the allocation vector of the current drive, one bit a block of
; the made-up DPB, in common memory where the program can read it
f27:	call	curmnt
	jp	nz,dskerr
	call	mkdpb
	ld	hl,ALV			; clear it, then the directory blocks
	ld	de,ALV+1
	ld	bc,ALVSZ-1
	ld	(hl),0
	ldir
	ld	a,(dirblks)
	ld	b,a
	ld	hl,0
f27_1:	push	bc
	push	hl
	call	alvset
	pop	hl
	pop	bc
	inc	hl
	djnz	f27_1
	ld	hl,2			; then each used cluster's blocks
f27_2:	push	hl
	call	fatget
	ld	a,h
	or	l
	pop	hl
	jr	z,f27_4
	push	hl
	dec	hl			; block = dirblks + (cluster - 2) *
	dec	hl			; sectors per cluster / sectors a block
	ld	b,(ix+D_SPCSH)
	inc	b
f27_s:	dec	b
	jr	z,f27_t
	add	hl,hl
	jr	f27_s
f27_t:	ld	a,(ix+D_SPC)		; HL = first sector, the cluster's
	ld	c,a			; C sectors cover (C+3)/4 blocks
f27_3:	push	hl
	ld	a,(blkk)
	add	a,2
	ld	b,a
f27_5:	srl	h
	rr	l
	djnz	f27_5
	ld	a,(dirblks)
	ld	e,a
	ld	d,0
	add	hl,de
	call	alvset
	pop	hl
	inc	hl
	dec	c
	jr	nz,f27_3
	pop	hl
f27_4:	inc	hl
	call	fateoc
	jr	nc,f27_2
	ld	hl,ALV
	ld	(bret),hl
	ret

; Set bit HL of the allocation vector, bit 7 of the first byte first.
; Changes HL.
alvset:	ld	a,h			; past the end: drop it
	cp	high (ALVSZ*8)
	ret	nc
	assert	low (ALVSZ*8) == 0
	ld	a,l
	and	7
	ld	b,a
	srl	h
	rr	l
	srl	h
	rr	l
	srl	h
	rr	l
	ld	de,ALV
	add	hl,de
	ld	a,80h
	inc	b
al_1:	dec	b
	jr	z,al_2
	rrca
	jr	al_1
al_2:	or	(hl)
	ld	(hl),a
	ret

; Mount the current drive
curmnt:	ld	a,(scb+SCB_DRV)
; Mount drive A, noted in fdrive for the error message
dmount:	ld	(fdrive),a
	jp	mount

; Make a DPB for the mounted drive IX, at DPB in common memory, the
; root directory as its directory. The block is 2K, or 4K, 8K or 16K
; when the disk has more blocks than the allocation vector holds, as a
; CP/M hard disk has. Sets dirblks, the directory blocks, blkk, entk
; and bnsz.
mkdpb:	ld	hl,DPB
	ld	de,DPB+1
	ld	bc,16
	ld	(hl),0
	ldir
	ld	a,(ix+D_SPT)		; records a track
	or	a
	jr	nz,mk_1
	ld	a,16			; a hard disk: any
mk_1:	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	ld	(DPB+0),hl
	xor	a
	ld	(blkk),a
mk_k:	ld	a,(blkk)		; dirblks = entries / (64 << blkk),
	add	a,6			; rounded up
	ld	b,a
	ld	hl,1
mk_2:	add	hl,hl
	djnz	mk_2
	dec	hl
	ld	e,(ix+D_ROOTENT)
	ld	d,(ix+D_ROOTENT+1)
	add	hl,de
	ld	a,(blkk)
	add	a,6
	ld	b,a
mk_3:	srl	h
	rr	l
	djnz	mk_3
	ld	a,l
	ld	(dirblks),a
	ld	l,(ix+D_TOTAL)		; DSM = dirblks + data sectors /
	ld	h,(ix+D_TOTAL+1)	; (4 << blkk) - 1
	ld	e,(ix+D_DATASEC)
	ld	d,(ix+D_DATASEC+1)
	or	a
	sbc	hl,de
	ld	a,(blkk)
	add	a,2
	ld	b,a
mk_4:	srl	h
	rr	l
	djnz	mk_4
	ld	a,(dirblks)
	ld	e,a
	ld	d,0
	add	hl,de
	dec	hl
	ld	a,h			; more than ALVSZ * 8 blocks: bigger ones
	cp	high (ALVSZ*8)
	jr	c,mk_5
	ld	a,(blkk)
	cp	3
	jr	nc,mk_cap
	inc	a
	ld	(blkk),a
	jr	mk_k
mk_cap:	ld	hl,ALVSZ*8-1
mk_5:	ld	(DPB+5),hl
	ld	a,(blkk)		; 2-byte block numbers, 8 an entry, or
	ld	c,a			; 1-byte, 16 an entry, from DSM 256
	ld	b,2
	ld	a,h
	or	a
	jr	nz,mk_6
	inc	c
	dec	b
mk_6:	ld	a,b
	ld	(bnsz),a
	ld	a,c
	ld	(entk),a
	ld	a,1			; EXM = (1 << entk) - 1
	inc	c
mk_7:	dec	c
	jr	z,mk_8
	add	a,a
	jr	mk_7
mk_8:	dec	a
	ld	(DPB+4),a
	ld	a,(blkk)		; BSH 4 + blkk, BLM (16 << blkk) - 1
	ld	b,a
	add	a,4
	ld	(DPB+2),a
	ld	a,16
	inc	b
mk_9:	dec	b
	jr	z,mk_10
	add	a,a
	jr	mk_9
mk_10:	dec	a
	ld	(DPB+3),a
	ld	l,(ix+D_ROOTENT)	; DRM
	ld	h,(ix+D_ROOTENT+1)
	dec	hl
	ld	(DPB+7),hl
	ld	a,(dirblks)		; AL0, AL1: that many bits from the top
	ld	b,a
	ld	hl,0
mk_11:	scf
	rr	h
	rr	l
	djnz	mk_11
	ld	a,h
	ld	(DPB+9),a
	ld	a,l
	ld	(DPB+10),a
	ld	a,2			; PSH, PHM: 512-byte sectors
	ld	(DPB+15),a
	ld	a,3
	ld	(DPB+16),a
	ret

; 28: write protect the current drive
f28:	call	curmnt
	jp	nz,dskerr
	ld	(ix+D_RO),1
	ret


; 30: set file attributes
f30:	call	fcbin
	call	fattrib
	jp	nz,dskerr
	jp	retA

; 31: the DPB of the current drive
f31:	call	curmnt
	jp	nz,dskerr
	call	mkdpb
	ld	hl,DPB
	ld	(bret),hl
	ret

; 32: user number: FFh gets it, else sets it. Files are the same in
; every user number, as FAT has none.
f32:	inc	a
	jr	z,f32_1
	ld	a,e
	and	0Fh
	ld	(scb+SCB_USER),a
	ret
f32_1:	ld	a,(scb+SCB_USER)
	jp	retA

; 33: read random, the multi-sector count of records from R0-R2, as
; CP/M 3's. The sequential position ends on the last record read.
f33:	call	ranset
	jr	nz,ranerr
f33_1:	push	bc
	call	seqrec
	call	rdrec
	pop	bc
	jp	nz,dskerr
	or	a
	jr	nz,ranout
	call	todma
	inc	c
	xor	a
	dec	b
	jr	z,ranout
	call	seqnext
	jr	f33_1

; 34, 40: write random, the multi-sector count of records from R0-R2.
; FAT has no holes, so 40's zeroed gap is 34's too.
f34:
f40:	call	ranset
	jr	nz,ranerr
f40_1:	call	fromdma
	push	bc
	call	seqrec
	call	wrrec
	pop	bc
	jr	nz,f40_err
	inc	c
	dec	b
	jr	z,f40_9
	call	seqnext
	jr	f40_1
f40_err: cp	E_FULL
	jp	nz,dskerr
	ld	a,2
	db	0FEh			; cp n: skips the xor
f40_9:	xor	a
	push	af
	push	bc
	call	setrc			; RC counts what was written
	pop	bc
	pop	af
; The FCB back, R0-R2 as they came: the position is on the last record
; read or written. On an error, H = the records done.
ranout:	jp	f20_9

; Copy in the FCB and open it if need be, then as ranini. NZ, A = the
; error, if it cannot be opened.
seqopn:	call	fcbin
	call	fcbopen
	ret	nz
; xdma from the DMA address, B = the multi-sector count, C = 0 done.
; Keeps the flags.
ranini:	ld	hl,(scb+SCB_DMA)
	ld	(xdma),hl
	ld	a,(scb+SCB_MULTI)
	ld	b,a
	ld	c,0
	ret

ranerr:	cp	6
	jp	z,fcbout36
	jp	dskerr

; Copy in the FCB, open it if need be, and set EX, S2, CR from R0-R2.
; NZ, A = 6 if R2 is set (past 8M), or A = error.
ranset:	call	seqopn
	ret	nz
	ld	a,(CFCB+F_R0+2)
	or	a
	ld	a,6
	ret	nz
	ld	hl,(CFCB+F_R0)
	ld	a,l
	and	7Fh
	ld	(CFCB+F_CR),a
	add	hl,hl			; HL >> 7 into H
	ld	a,h
	and	1Fh
	ld	(CFCB+F_EX),a
	ld	a,h
	rlca
	rlca
	rlca
	and	07h
	ld	b,a
	ld	a,(CFCB+F_R0+1)
	rlca			; bit 7 of R1 is bit 15 of the record
	and	01h
	rlca
	rlca
	rlca
	or	b
	ld	(CFCB+F_S2),a
	call	setrc
	xor	a
	jr	ranini

; 35: file size in records into R0-R2
f35:	call	fcbin
	call	fcbopen
	jr	nz,f35_no
	call	nrecs
	ld	a,0
	jr	nc,f35_1
	inc	a
	ld	hl,0
f35_1:	ld	(CFCB+F_R0),hl
	ld	(CFCB+F_R0+2),a
	xor	a
	jp	fcbout36
f35_no:	cp	E_READ
	jp	nz,dskerr
	ld	a,R_NOFILE
	jp	retA

; 36: set the random record from the sequential position
f36:	call	fcbin
	call	seqrec
	ld	(CFCB+F_R0),hl
	xor	a
	ld	(CFCB+F_R0+2),a
	jp	fcbout36

; 37: reset the drives in the vector DE
f37:	ld	b,NDRV
	xor	a
f37_1:	srl	d
	rr	e
	jr	nc,f37_2
	push	af
	push	bc
	push	de
	call	umount
	pop	de
	pop	bc
	pop	af
f37_2:	inc	a
	djnz	f37_1
	ret

; 44: multi-sector count, 1-128
f44:	dec	a			; 1-128 to 0-127, the rest have bit 7
	jp	m,fff
	inc	a
	ld	(scb+SCB_MULTI),a
	ret

; 45: error mode: FFh return, FEh return and print, else print and end
f45:	ld	(scb+SCB_ERMODE),a
	ret

; 46: free space of drive E, in records, 3 bytes into the DMA buffer
f46:	ld	a,e
	call	dmount
	jp	nz,dskerr
	call	fatcount		; HL clusters * 4 * SPC records
	ld	a,0
	ld	b,(ix+D_SPCSH)
	inc	b
	inc	b
	inc	b
f46_1:	dec	b
	jr	z,f46_2
	add	hl,hl
	rla
	jr	f46_1
f46_2:	ld	(CBUF),hl
	ld	(CBUF+2),a
	ld	hl,CBUF
	ld	de,(scb+SCB_DMA)
	ld	bc,3
	call	ucopy
	xor	a
	jp	retA

; 47: chain to the command line in the DMA buffer
f47:	ld	hl,(scb+SCB_DMA)
	ld	de,chainbuf
	ld	bc,128
	call	ucopybig
	ld	a,1
	ld	(chainf),a
	jp	wboot

; 48: flush buffers
f48:	call	flushall
	jp	nz,dskerr
	ret

; 49: get or set a byte or word of the SCB. DE = SCBPB: offset, then
; FFh set byte, FEh set word, else get, then the value.
f49:	ex	de,hl
	ld	de,CBUF
	ld	bc,4
	call	ucopy
	ld	a,(CBUF)
	cp	SCBSZ
	ret	nc
	ld	e,a
	ld	d,0
	ld	hl,scb
	add	hl,de
	ld	a,(CBUF+1)
	inc	a			; FFh: set a byte
	jr	z,f49_b
	inc	a			; FEh: set a word
	jr	z,f49_w
	jp	gs_get			; else get the word
f49_w:	ld	a,(CBUF+3)
	inc	hl
	ld	(hl),a
	dec	hl
f49_b:	ld	a,(CBUF+2)
	ld	(hl),a
	ret

; 50: direct BIOS call. DE = BIOSPB: function, A, BC, DE, HL.
f50:	ex	de,hl
	ld	de,CBUF
	ld	bc,9
	call	ucopy
	ld	a,(CBUF)
	cp	26			; TIME here: the BIOS one comes in
	jr	z,f50_t			; through the BDOS
	cp	25			; MOVE between the program's addresses,
	jr	z,f50_m			; not the kernel's below 8000h
	cp	BIOSN
	ret	nc
	ld	l,a			; * 3
	add	a,a
	add	a,l
	ld	l,a
	ld	h,0
	ld	de,biostab
	add	hl,de
	ld	de,f50_ret
	push	de
	push	hl
	ld	bc,(CBUF+2)
	ld	de,(CBUF+4)
	ld	hl,(CBUF+6)
	ld	a,(CBUF+1)
	ret				; into the table entry
f50_m:	ld	bc,(CBUF+2)		; BC bytes from DE to HL, as MOVE
	ld	a,b
	or	c
	ret	z
	ld	de,(CBUF+4)
	ld	hl,(CBUF+6)
	ex	de,hl
	jp	ucopy			; in common memory, as it maps the TPA
f50_t:	ld	a,(CBUF+2)		; C = 0: get the time, FFh: set it,
	or	a			; which the clock takes only with its
	ret	nz			; TIME SET button held
	jp	scbtime
f50_ret: ld	(bret),hl		; SELDSK, SECTRAN, DEVTBL, DRVTBL
	ld	b,a			; return HL, the others A
	ld	a,(CBUF)
	cp	9
	ret	z
	cp	16
	ret	z
	cp	20
	ret	z
	cp	22
	ret	z
	ld	a,b
	jp	retA


; 99: truncate the file, R0-R1 its last record, as CP/M 3. FFh, the
; file unchanged, for a record past its end.
f99:	call	ranset
	jp	nz,dskerr
	ld	a,(CFCB+F_NAME+8)	; t1': the file is R/O
	rla
	ld	a,E_ROFILE
	jp	c,dskerr
	ld	hl,(CFCB+F_R0)		; the new size: (R + 1) * 128 bytes
	inc	hl
	ld	a,h
	or	l
	jr	z,f99_x
	ld	a,h
	ld	h,l
	ld	l,0
	srl	a
	rr	h
	rr	l
	ld	c,a			; C:HL
	push	hl
	ld	hl,(CFCB+F_SIZE)	; within the file's last record?
	ld	a,(CFCB+F_SIZE+2)
	ld	de,127
	add	hl,de
	adc	a,0
	pop	de
	or	a
	sbc	hl,de
	sbc	a,c
	jr	c,f99_x
	ld	hl,(CFCB+F_SIZE)	; R the last record: the size as it is,
	ld	a,(CFCB+F_SIZE+2)	; not that record made whole
	or	a
	sbc	hl,de
	sbc	a,c
	jr	nc,f99_1
	ld	de,(CFCB+F_SIZE)
	ld	a,(CFCB+F_SIZE+2)
	ld	c,a
f99_1:	ex	de,hl
	ld	a,c
	ld	(CFCB+F_SIZE),hl
	ld	(CFCB+F_SIZE+2),a
	xor	a
	ld	(CFCB+F_SIZE+3),a
	ld	a,(CFCB+F_FLAG)
	or	1
	ld	(CFCB+F_FLAG),a
	call	ftrunc
	jp	nz,dskerr
	call	fclose
	jp	nz,dskerr
	xor	a			; the FCB back: it holds the size
	jp	fcbout36
f99_x:	ld	a,0FFh
	jp	retA


; 102: read the file's date stamps into the FCB, CP/M 3 style: create
; at +24 and update at +28, as days, hour, minute. FAT has one date,
; which goes in both.
f102:	call	fcbin
	call	fcbdrv
	jp	nz,dskerr
	call	fcbpat
	call	dsfirst
	jr	z,f102_1
	cp	R_NOFILE
	jp	nz,dskerr
	jp	retA
f102_1:	ld	de,DE_TIME
	add	hl,de
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	call	fat2cpm			; HL = days, B = hour, C = minute
	ld	(CFCB+24),hl
	ld	(CFCB+28),hl
	ld	l,b			; hour, then minute
	ld	h,c
	ld	(CFCB+26),hl
	ld	(CFCB+30),hl
	xor	a
	jp	fcbout36


; 105: date and time into the 4 bytes at DE: days since 31 Dec 1977,
; hour and minute in BCD. A = seconds in BCD.
f105:	call	scbtime
	ld	hl,scb+SCB_DATE
	ld	de,(bparam)
	ld	bc,4
	call	ucopy
	ld	a,(scb+SCB_DATE+4)
	jp	retA

; The date and time now into the SCB, as CP/M 3's BIOS TIME puts them
; there: days since 31 Dec 1977, then hour, minute, second in BCD
scbtime: call	cpmnow			; HL days, B hour, C minute, A second
	ld	(scb+SCB_DATE),hl
	ld	(scb+SCB_DATE+4),a
	ld	l,b
	ld	h,c
	ld	(scb+SCB_DATE+2),hl
	ret

; 107: the serial number, 6 bytes at DE
f107:	ld	hl,COMMON_ORG
	ld	bc,6
	jp	ucopy

; 108: program return code: FFFFh gets it, else sets it
f108:	ld	hl,scb+SCB_RETC
	jr	getset
; 109: console mode
f109:	ld	hl,scb+SCB_CMODE
getset:	ld	a,d
	and	e
	inc	a
	jr	z,gs_get
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ret
gs_get:	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	(bret),hl
	ret

; 110: the string delimiter: FFFFh gets it, else E sets it
f110:	ld	hl,scb+SCB_DELIM
	ld	a,d
	and	e
	inc	a
	jr	z,f110_1
	ld	(hl),e
	ret
f110_1:	ld	a,(hl)
	jp	retA

; 111: print a block, 112: list a block. DE = CCB: address, length.
f111:	xor	a
	db	21h			; ld hl,nn: skips the ld a,1
f112:	ld	a,1
blk:	ld	(blkdev),a
	ex	de,hl
	ld	de,CBUF
	ld	bc,4
	call	ucopy
	ld	hl,(CBUF)
	ld	bc,(CBUF+2)
bk_1:	ld	a,b
	or	c
	ret	z
	call	upeek
	push	bc
	push	hl
	ld	c,a
	ld	a,(blkdev)
	or	a
	ld	a,c
	jr	nz,bk_2
	call	kputc
	jr	bk_3
bk_2:	call	list
bk_3:	pop	hl
	pop	bc
	inc	hl
	dec	bc
	jr	bk_1

; 152: parse a file name. DE = PFCB: the text's address, the FCB's.
; HL = the address after the name, 0 at the end of the line, FFFFh
; if the name is bad.
f152:	ex	de,hl
	ld	de,CBUF
	ld	bc,4
	call	ucopy
	ld	hl,(CBUF)		; the text's address and the FCB's, kept:
	push	hl			; ucopybig uses CBUF
	ld	hl,(CBUF+2)
	push	hl
	ld	hl,(CBUF)		; the text, 128 bytes of it
	ld	de,pbuf
	ld	bc,128
	call	ucopybig
	ld	hl,pbuf			; in upper case, as CP/M 3 parses it
	ld	b,128
pp_u:	ld	a,(hl)
	call	upper
	ld	(hl),a
	inc	hl
	djnz	pp_u
	ld	hl,pbuf
	ld	de,CBUF+4		; FCB: drive, name, then zeros
	push	hl
	ld	hl,CBUF+4
	ld	b,36
pp_1:	ld	(hl),0
	inc	hl
	djnz	pp_1
	pop	hl
	call	parsefn
	jr	c,pp_bad
	ld	a,(hl)			; a password ";PW" is skipped
	cp	';'
	jr	nz,pp_2
pp_s:	inc	hl
	ld	a,(hl)
	call	isdelim
	jr	nz,pp_s
pp_2:	pop	de			; the FCB's address
	push	de
	push	hl
	ld	hl,CBUF+4
	ld	bc,32
	call	ucopy
	pop	hl
	pop	de
	push	hl			; as CP/M 3's: past the blanks, the end
	call	skipsp			; of the line is 0, another delimiter
	or	a			; its address, else the place just
	jr	z,pp_e2			; after the name
	cp	0Dh
	jr	z,pp_e2
	call	isdelim
	jr	z,pp_d
	pop	hl
	push	hl
pp_d:	pop	af
	ld	de,pbuf			; its address in the text
	or	a
	sbc	hl,de
	pop	de
	add	hl,de
	ld	(bret),hl
	ret
pp_e2:	pop	hl
	pop	hl
	ld	hl,0
	ld	(bret),hl
	ret
pp_bad:	pop	de
	pop	de
	ld	hl,0FFFFh
	ld	(bret),hl
	ret

; Copy BC bytes from the program at HL to the kernel at DE, through CBUF
ucopybig: ld	a,b
	or	c
	ret	z
	push	bc
	ld	a,b			; at most 128 at a time
	or	a
	jr	nz,ub_1
	ld	a,c
	cp	128
	jr	c,ub_2
ub_1:	ld	bc,128
ub_2:	push	bc
	push	de
	ld	de,CBUF
	call	ucopy			; HL moves on
	pop	de
	pop	bc
	push	hl
	ld	hl,CBUF
	push	bc
	ldir
	pop	bc
	pop	hl
	ex	(sp),hl			; count -= done
	or	a
	sbc	hl,bc
	ld	b,h
	ld	c,l
	pop	hl
	jr	ucopybig

; ------------------------------------------------------------------
; A disk error A from a function. In error mode FFh, return A = FFh
; and H = the error. Else print it, and end the program unless the mode
; is FEh.
dskerr:	ld	(errcode),a
	ld	a,(scb+SCB_ERMODE)
	cp	0FFh
	jr	z,de_ret
	push	af
	call	crlf
	call	pmsg
	db	"CP/M Error On ",0
	ld	a,(wbdrv)		; a write-back's drive, or the call's
	dec	a
	jp	p,dk_1
	ld	a,(fdrive)
dk_1:	add	a,'A'
	call	kputc
	call	pmsg
	db	": ",0
	ld	a,(errcode)
	ld	hl,errmsgs
	dec	a
	add	a,a
	ld	e,a
	ld	d,0
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	call	pstr
	call	pmsg
	db	0Dh,0Ah,"Function ",0
	ld	a,(bfunc)
	ld	l,a
	ld	h,0
	call	pdec
	call	crlf
	pop	af
	cp	0FEh
	jp	nz,wboot
de_ret:	ld	a,(errcode)		; CP/M 3's code in H
	cp	E_FULL
	jr	c,de_r1
	ld	a,E_READ
de_r1:	ld	h,a
	ld	l,0FFh
	ld	(bret),hl
	ret

errmsgs: dw	em1,em2,em3,em4,em5,em6,em1
	dw	em8,em9,em10,em11,em12,em13,em14,em15
em8:	db	"No folder",0
em9:	db	"Exists",0
em10:	db	"Not empty",0
em11:	db	"Bad name",0
em12:	db	"Path too long",0
em13:	db	"In use",0
em14:	db	"No memory",0
em15:	db	"Root full",0
em1:	db	"Disk I/O",0
em2:	db	"Read/Only",0
em3:	db	"Read/Only File",0
em4:	db	"Invalid Drive",0
em5:	db	"Disk Full",0
em6:	db	"Not Ready",0
