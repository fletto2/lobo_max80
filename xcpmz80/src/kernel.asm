; xcpmz80 kernel. Runs in A2, mapped at 0000h-7FFFh while it runs,
; loaded at 1000h. The block layer, FAT, the BDOS, the program loader
; and the shell. Programs run in B1 low and A1 high, and reach the
; kernel through bdosent in common memory.

	org	1000h
kmain:	ld	hl,BSS			; zero the variables
	ld	de,BSS+1
	ld	bc,BSSEND-BSS-1
	ld	(hl),0
	ldir
	ld	hl,CBSS			; and those in common memory
	ld	de,CBSS+1
	ld	bc,CBSSEND-CBSS-1
	ld	(hl),0
	ldir
	call	ubtpa
	call	scbinit
	call	diskinit
	ld	a,0CFh			; PIO port B: all outputs, for the clock
	ld	(PIOCB),a
	xor	a
	ld	(PIOCB),a
	ld	(PIODB),a
	call	psign
	call	pmsg
	db	", ",0
	ld	hl,TPAK			; the TPA
	call	pdec
	call	pmsg
	db	"K TPA",0Dh,0Ah,0
	xor	a			; the boot device is A:
	ld	(scb+SCB_DRV),a
	ld	(shdrv),a
	call	clrtpa
	call	clibload
	xor	a			; no batch from memory yet
	ld	(subact),a
	call	subchk			; a batch left waiting goes on, or
	ld	a,(subact)		; else AUTOEXEC.BAT
	or	a
	jp	nz,shell
	call	autoex
	jp	kw_1

; ucopy, upeek and upoke reach the TPA again, outside any BDOS call
ubtpa:	ld	a,BANK_TPA
	ld	(UBANK),a
	ret

; ------------------------------------------------------------------
; The C library: CLIB.SYS from the boot drive, loaded at 0000h in
; B2, where libent in common memory jumps. Without it, or with no B2, a
; stub there gives 0 for every call, which a program's crt0 takes for
; no library. The file starts with the dispatcher's jump, then "CLIB"
; and the version at 0003h. libout's address goes at 0008h, lcopy's at
; 000Ah.
CLIB_MAX	equ	256		; records, the whole of B2
TPAK		equ	(bdosent-100h) >> 10	; the TPA in K

clibload: ld	a,(RAMK)
	cp	128
	ret	c			; no B2
	ld	hl,ubtpa			; every way out maps the TPA again
	push	hl
	ld	a,BANK_B2
	ld	(UBANK),a
	call	clstub
	ld	hl,clibname
	call	cfcbset
	call	fopenq
	ret	nz
	call	nrecs
	ret	c
	ld	de,CLIB_MAX+1
	sbc	hl,de			; carry clear from nrecs
	ret	nc			; too big for B2
	add	hl,de
	ld	(prrecs),hl
	ld	hl,0
	ld	(prfrom),hl
	ld	(prdest),hl
	call	ldrecs
	jr	nz,cl_8
cl_2:	ld	hl,0Ch			; "CLIB" at 000Ch, or it is not one
	ld	de,clibmag
	ld	b,4
cl_3:	call	upeek
	ex	de,hl
	cp	(hl)
	ex	de,hl
	jr	nz,cl_8
	inc	hl
	inc	de
	djnz	cl_3
	ld	hl,6			; the BDOS, libout and lcopy for
	ld	de,bdosent		; the library
	call	clw
	ld	de,libout
	call	clw
	ld	de,lcopy
	call	clw
	call	pmsg
	db	"C library loaded",0Dh,0Ah,0
	ret
cl_8:	call	clstub			; a bad file: the stub again
	call	pmsg
	db	"Bad CLIB.SYS",0Dh,0Ah,0
	ret

; Records prfrom up to prrecs of the file in CFCB to prdest on, in the
; bank UBANK. Z at the end of them or of the file, NZ (A) on an error.
ldrecs:	ld	hl,(prfrom)
	ld	de,(prrecs)
	or	a
	sbc	hl,de
	jr	nc,lr_9
	add	hl,de
	call	rdrec
	ret	nz
	or	a
	jr	nz,lr_9
	ld	hl,CBUF
	ld	de,(prdest)
	ld	bc,128
	call	ucopy
	ld	(prdest),de
	ld	hl,(prfrom)
	inc	hl
	ld	(prfrom),hl
	jr	ldrecs
lr_9:	xor	a
	ret

clw:	ld	a,e			; the word DE at HL in the bank UBANK, HL on
	call	upoke
	inc	hl
	ld	a,d
	call	upoke
	inc	hl
	ret

clstub:	ld	hl,clibstub
	ld	de,0
	ld	bc,clibsl
	jp	ucopy

clibname: db	0,"CLIB    SYS"
clibmag	equ	clibname+1

; The sign-on and the RAM size: "... MAX-80, 128K"
psign:	ld	hl,signon
	call	pstr
	ld	a,(RAMK)
	call	pdeca
	ld	a,'K'
	jp	kputc

signon:	db	"XCP/M-Z80 v0.2 for the Lobo MAX-80, ",0

; The boot sector puts the boot device here: 0 floppy, 1 SASI
BOOTDEV: db	0

scbinit: ld	hl,scb
	ld	de,scb+1
	ld	bc,SCBSZ-1
	ld	(hl),0
	ldir
	ld	a,31h
	ld	(scb+SCB_VER),a
	ld	a,COLS-1
	ld	(scb+SCB_WIDTH),a
	ld	a,ROWS
	ld	(scb+SCB_PAGE),a
	ld	hl,bdosent		; no RSXs yet
	ld	(rsxtop),hl
	ld	(scb+SCB_MXTPA),hl
	ld	hl,scb			; its own address, which CP/M 3's
	ld	(scb+SCB_BASE),hl	; DATE and others look up
	ld	hl,0100h		; programs from the current drive,
	ld	(scb+SCB_PATH),hl	; then A:, as SETDEF shows and sets
	ld	hl,0FFFFh
	ld	(scb+SCB_PATH+2),hl
	ld	a,1			; console page mode off: the screen
	ld	(scb+SCB_PMODE),a	; does not stop
	ld	hl,8000h		; the console on the CRT, AUX on SIOA,
	ld	(scb+SCB_CIVEC),hl	; the list on the printer
	ld	(scb+SCB_COVEC),hl
	ld	h,40h
	ld	(scb+SCB_AIVEC),hl
	ld	(scb+SCB_AOVEC),hl
	ld	h,10h
	ld	(scb+SCB_LOVEC),hl
	; fall into scbprog

; The settings each program starts with
scbprog: ld	a,'$'
	ld	(scb+SCB_DELIM),a
	ld	a,1
	ld	(scb+SCB_MULTI),a
	xor	a
	ld	(scb+SCB_ERMODE),a
	ld	(scb+SCB_LIST),a
	ld	hl,0
	ld	(scb+SCB_CMODE),hl
	ld	hl,0080h
	ld	(scb+SCB_DMA),hl
	ret

; Zero the TPA's page zero and set its jumps
clrtpa:	ld	hl,CBUF
	ld	de,CBUF+1
	ld	bc,127
	ld	(hl),0
	ldir
	ld	hl,CBUF
	ld	de,0
	ld	bc,128
	call	ucopy
	ld	hl,CBUF
	ld	bc,128
	call	ucopy
	; fall into pzero

; Page zero: JP WBOOT at 0, JP BDOS at 5, drive and user at 4
pzero:	ld	a,0C3h
	ld	(CBUF),a
	ld	(CBUF+5),a
	ld	hl,biostab+3
	ld	(CBUF+1),hl
	ld	hl,(rsxtop)
	ld	(CBUF+6),hl
	ld	(scb+SCB_MXTPA),hl
	ld	hl,0003h		; keep the IOBYTE
	call	upeek
	ld	(CBUF+3),a
	ld	a,(scb+SCB_USER)
	rlca
	rlca
	rlca
	rlca
	ld	b,a
	ld	a,(scb+SCB_DRV)
	or	b
	ld	(CBUF+4),a
	ld	hl,CBUF
	ld	de,0
	ld	bc,8
	call	ucopy
	ld	hl,stub			; rsxcall's call from below the RSXs,
	ld	de,CBUF			; by way of common memory
	ld	bc,6
	ldir
	ld	hl,CBUF
	ld	de,RSXSTUB
	ld	bc,6
	jp	ucopy
stub:	call	0005h
	jp	rsxret

; Warm boot, from wboot in common: SP at STKTOP, A2 low. Write what
; is waiting, let the floppies be read again, and back to the shell
; on the drive it was on.
kwboot:	xor	a			; ^C at the prompt: UP is the shell's alone,
	ld	(lnhist),a		; not a chained program's function 10
	call	kwcom
	call	rsxfree
	call	pzero
kw_0:	ld	a,(chainf)		; function 47: a command to run next
	or	a
	jr	z,kw_1
	xor	a
	ld	(chainf),a
	ld	hl,chainbuf
	ld	de,linebuf
	ld	bc,127
	ldir
	xor	a
	ld	(linebuf+127),a
	call	crlf
	jp	docmd
kw_1:	call	subchk
	jp	shell

; A program returned by RET (progret). If page zero's warm boot jump
; still goes to the BIOS, as a warm boot. If a program has hooked it,
; as CP/M 2.2's XSUB does to stay in while a batch runs, back to the
; shell with page zero as it is, as CP/M 2.2's CCP does: the hook
; came back here, and the warm boot it catches comes back here too.
kret:	ld	hl,0001h
	call	upeek
	ld	e,a
	inc	hl
	call	upeek
	ld	d,a
	ld	hl,biostab+3
	or	a
	sbc	hl,de
	jr	z,kwboot
	call	kwcom
	jr	kw_0
; Both ways back: the TPA bank, the disks, the program's settings, the
; shell's drive
kwcom:	call	ubtpa
	call	kreset
	call	scbprog
	ld	a,(shdrv)
	ld	(scb+SCB_DRV),a
	ret

; A CP/M 2.2 CCP's entries at BIOS-1600h (CCP22): programs that stay in
; memory, as QWIKKEY does, go back to the CCP there, at +3, after
; hooking page zero. Both come back to the shell as a RET does, with
; page zero kept. Written only when 0006h is above them, so nothing kept
; under it is written over. A program may load over them, as over
; CP/M 2.2's CCP.
ccpent:	ld	hl,0007h
	call	upeek
	cp	high CCP22 + 1
	ret	c
	ld	hl,ccpjp
	ld	de,CCP22
	ld	bc,6
	jp	ucopy

; Is there an A:$$$.SUB? Set subact if so. Errors say no. A batch
; run from memory (subact 2) goes on.
subchk:	ld	a,(subact)
	cp	2
	ret	z
	xor	a
	ld	(subact),a
	ld	hl,subname
	call	cfcbset
	call	fopenq			; errors say no
	ret	nz
	inc	a			; A = 0 from fopenq
	ld	(subact),a
	ret
subname: db	1,"$$$     SUB"

; Fill CFCB from the 12 bytes at HL: drive and name, the rest zero
cfcbset: push	hl
	ld	hl,CFCB
	ld	de,CFCB+1
	ld	bc,35
	ld	(hl),0
	ldir
	pop	hl
	ld	de,CFCB
	ld	bc,12
	ldir
	ret

; ------------------------------------------------------------------
; Load and run the program in cmdfcb (drive and name), with the tail
; at HL. Carry if there is no such program. Does not return otherwise.
runprog: ld	(tailp),hl
	ld	a,(cmdfcb)		; a drive given: that one only
	or	a
	jr	z,rp_p
	call	rp_try
	jr	z,rp_1
	scf
	ret
rp_p:	ld	hl,scb+SCB_PATH		; else the search path in the SCB
	ld	b,4
rp_p1:	ld	a,(hl)
	cp	0FFh
	jr	z,rp_pe
	push	hl
	push	bc
	call	rpdrv			; a drive tried before, as the current
	ld	c,a			; drive and A: when on A:, once only
	ld	de,scb+SCB_PATH
rp_p3:	ld	a,e
	cp	l
	jr	z,rp_p4
	ld	a,(de)
	call	rpdrv
	cp	c
	jr	z,rp_dup
	inc	de
	jr	rp_p3
rp_p4:	ld	a,c
	call	rp_try
	jr	rp_p5
rp_dup:	or	0FFh			; NZ: not found there
rp_p5:	pop	bc
	pop	hl
	jr	z,rp_1
	inc	hl
	djnz	rp_p1
rp_pe:	ld	a,(rootf)		; then the same drives' roots, if a
	or	a			; drive is in a folder
	jr	nz,rp_e
	ld	hl,cwdcl
	ld	b,NDRV*2
rp_p2:	or	(hl)
	inc	hl
	djnz	rp_p2
	scf
	ret	z
	ld	(rootf),a
	jr	rp_p
rp_e:	xor	a
	ld	(rootf),a
	scf
	ret

	assert	high (scb+SCB_PATH) = high (scb+SCB_PATH+3)	; rp_p3 checks E
; A = a path entry's drive, 1-16, 0 the current one: the drive, 1-16
rpdrv:	or	a
	ret	nz
	ld	a,(scb+SCB_DRV)
	inc	a
	ret

; Open the .COM named in cmdfcb on drive A (0 the current one) in CFCB
rp_try:	push	af
	ld	hl,cmdfcb
	call	cfcbset
	pop	af
	ld	(CFCB),a
	ld	hl,comext
; The extension at HL into CFCB, and open it quietly
fextq:	ld	de,CFCB+9
	ld	bc,3
	ldir
	jp	fopenq

rp_1:	xor	a
	ld	(rootf),a
	call	ccpent			; before the program, which may load over it
	call	ldtell
	ld	a,(fdrive)		; the FAT now, with the head near it, not
	call	mount			; between the first cluster and the next
	ld	hl,(CFCB+F_CLUS)
	call	fatget
	ld	a,(fdrive)		; the drive it came from, for 0050h
	inc	a
	ld	(progdrv),a
	call	nrecs			; does it fit?
	jr	c,rp_big
	ld	(prrecs),hl
	push	hl			; records under what 0006h gives: the
	ld	hl,0007h		; BDOS, the lowest RSX, or XSUB
	call	upeek
	pop	hl
	sub	1
	ld	e,a
	ld	d,0
	sla	e
	rl	d
	ex	de,hl
	or	a
	sbc	hl,de
	jr	c,rp_big
	ld	hl,0			; a CP/M 3 file with an RSX header
	ld	(prfrom),hl		; starts with RET: skip the header page
	ld	(rsxhdr),hl
	call	rdrec
	jp	nz,sherr
	ld	a,(CBUF)
	cp	0C9h
	jr	nz,rp_2
	ld	hl,CBUF
	ld	de,rsxhdr
	ld	bc,128
	ldir
	ld	hl,2
	ld	(prfrom),hl
rp_2:	ld	hl,0100h
	ld	(prdest),hl
	call	ldrecs			; record by record into the TPA
	jp	nz,sherr
	ld	a,(rsxhdr)		; RSXs to load?
	cp	0C9h
	jr	nz,rp_5
	call	rsxload
	jr	c,rp_big
	call	pzero			; 0006h to the lowest RSX
	ld	hl,(rsxhdr+1)		; RSXs only: back to the shell
	ld	a,h
	or	l
	jp	z,shell
rp_5:	call	settail
	call	scbprog
	call	flushall
	ld	a,(scb+SCB_DRV)
	ld	(shdrv),a
	jp	golaunch
rp_big:	call	pmsg
	db	"Too big",0Dh,0Ah,0
	or	a
	ret

comext:	db	"COM"

; ------------------------------------------------------------------
; CP/M 3 RSXs. A .COM file made by GENCOM starts with a header record:
; RET, the program's length, and at 0Fh the number of RSXs, each then
; 16 bytes at 10h: offset in the file, code length, FFh if only for a
; CP/M 3 without banks, the name. The code is assembled at 0100h and
; followed by its relocation bitmap, a bit a byte, high bit first.
; The file is in the TPA at its own offsets. Each RSX goes in whole
; pages under the lowest one so far, and links in: its 0009h jump
; goes on to what 0006h held, and 0006h comes to its 0006h. Carry if
; they do not fit above the file.

rsxload: ld	a,(rsxhdr+0Fh)
	ld	(rsxn),a
	ld	hl,rsxhdr+10h
rx_1:	ld	a,(rsxn)
	or	a
	ret	z
	dec	a
	ld	(rsxn),a
	ld	(rsxent),hl
	ld	bc,16
	add	hl,bc
	push	hl
	call	rsx1
	pop	hl
	ret	c
	jr	rx_1

; Load the RSX of the header entry at rsxent
rsx1:	ld	ix,(rsxent)
	ld	a,(ix+4)		; only for CP/M 3 without banks:
	or	a			; the kernel has it already
	ret	nz
	ld	l,(ix+2)		; pages = (length + 255) / 256
	ld	h,(ix+3)
	ld	de,255
	add	hl,de
	ld	a,(rsxtop+1)		; base page
	sub	h
	ret	c
	ld	(rsxbias+1),a		; the base, page aligned
	dec	a			; assembled at 0100h
	ld	(rsxbias),a
	ld	hl,(prdest)		; the base must be above the file
	ld	a,(rsxbias+1)
	cp	h
	ret	c
	jr	nz,r1_1
	ld	a,l
	or	a
	scf
	ret	nz
r1_1:	ld	l,(ix+0)		; HL = the code, DE = its bitmap
	ld	h,(ix+1)
	ld	c,(ix+2)
	ld	b,(ix+3)
	push	hl
	add	hl,bc
	ex	de,hl
	pop	hl
	ld	a,80h			; the bit for this byte
r1_2:	push	af
	ld	a,b
	or	c
	jr	z,r1_5
	ex	de,hl
	call	upeek			; the bitmap byte
	ex	de,hl
	ld	(rsxent),a		; (ix keeps the entry)
	pop	af
	push	af
	push	hl
	ld	hl,rsxent
	and	(hl)
	pop	hl
	jr	z,r1_3
	call	upeek			; relocate this byte
	push	hl
	ld	hl,rsxbias
	add	a,(hl)
	pop	hl
	call	upoke
r1_3:	inc	hl
	dec	bc
	pop	af
	rrca
	jr	nc,r1_2
	inc	de			; the next bitmap byte
	jr	r1_2
r1_5:	pop	af
	ld	l,(ix+0)		; move it to the base
	ld	h,(ix+1)
	ld	c,(ix+2)
	ld	b,(ix+3)
	ld	a,(rsxbias+1)
	ld	d,a
	ld	e,0
	push	de
	call	ucopy
	pop	hl
	ld	l,0Ah			; its jump on: to what 0006h held
	ld	de,(rsxtop)
	call	clw
	ld	de,5			; 0Ch, the module before it: page zero
	call	clw
	ld	l,6			; it is the lowest now
	ld	(rsxtop),hl
	or	a
	ret

; Unlink the RSXs whose remove flag (0Eh) is set, as CP/M 3 does at
; a warm boot and by function 59. The space of the lowest ones comes
; back to the TPA. Then 0006h and the SCB's TPA top follow.
rsxfree: ld	hl,0			; the link to the first is rsxtop
	ld	(rsxlink),hl
	ld	hl,(rsxtop)
rf_1:	ld	de,bdosent		; the end of the chain?
	or	a
	sbc	hl,de
	add	hl,de
	jr	z,rf_9
	push	hl			; DE = the next, at 0Ah
	ld	l,0Ah
	call	upeek
	ld	e,a
	inc	hl
	call	upeek
	ld	d,a
	ld	l,0Eh			; to be removed?
	call	upeek
	or	a
	jr	nz,rf_2
	pop	hl			; kept: the link to the next is its 0Ah
	ld	l,0Ah
	ld	(rsxlink),hl
	ex	de,hl
	jr	rf_1
rf_2:	pop	hl			; removed: the link skips it
	ld	hl,(rsxlink)
	ld	a,h
	or	l
	jr	nz,rf_3
	ld	(rsxtop),de
	ex	de,hl
	jr	rf_1
rf_3:	call	clw
	ex	de,hl
	jr	rf_1
rf_9:	ld	hl,(rsxtop)		; 0006h and the SCB
	ld	(scb+SCB_MXTPA),hl
	ex	de,hl
	ld	hl,0006h
	jp	clw

; RSXs loaded: show them the program load, as function 59 through them
; with the program's FCB at 005Ch, as CP/M 3's CCP loads by 59. SAVE's
; RSX hooks the warm boot there. The kernel's 59 takes it as done.
ldtell:	ld	hl,(rsxtop)
	ld	de,bdosent
	or	a
	sbc	hl,de
	ret	z
	ld	hl,0100h
	ld	(CFCB+F_R0),hl
	ld	hl,CFCB
	ld	de,005Ch
	ld	bc,36
	call	ucopy
	ld	a,1
	ld	(ldown),a
	ld	c,59
	ld	de,005Ch
	call	rsxcall
	xor	a
	ld	(ldown),a
	ld	hl,005Ch		; the FCB back: an RSX may have used
	ld	de,CFCB			; the BDOS's copy
	ld	bc,36
	jp	ucopy

; fopen, quiet: errors come back as NZ
fopenq:	ld	a,0FFh
	ld	(scb+SCB_ERMODE),a
	call	fopen
	push	af
	xor	a
	ld	(scb+SCB_ERMODE),a
	pop	af
	ret	nz
	or	a			; Z: open, NZ: R_NOFILE (A = FFh)
	ret

; Page zero for the program: FCB 1 and 2 at 5Ch and 6Ch from the first
; two names of the tail, the tail at 80h, the drive at 50h
settail: ld	hl,pzbuf		; build 5Ch-FFh in pzbuf
	ld	de,pzbuf+1
	ld	bc,PZLEN-1
	ld	(hl),0
	ldir
	ld	a,(progdrv)
	ld	(pzbuf),a
	ld	hl,(tailp)		; the names: parsefn blanks a name
	ld	de,pzbuf+5Ch-50h	; that is not there
	call	parsefn
	call	skippw
	ld	de,pzbuf+6Ch-50h
	call	parsefn
	ld	hl,(tailp)		; the tail: length, then the text
	ld	de,pzbuf+81h-50h
	ld	b,0
st_3:	ld	a,(hl)
	or	a
	jr	z,st_4
	ld	(de),a
	inc	hl
	inc	de
	inc	b
	ld	a,b
	cp	126
	jr	c,st_3
st_4:	ld	a,b			; the 0 after the tail: pzbuf is zeroed
	ld	(pzbuf+80h-50h),a
	ld	hl,pzbuf		; to 0050h, through CBUF
	ld	de,0050h
	ld	bc,PZLEN
	jr	ustore

; Skip a ";password" after a name
skippw:	ld	a,(hl)
	cp	';'
	ret	nz
sp_1:	inc	hl
	ld	a,(hl)
	call	isdelim
	jr	nz,sp_1
	ret

; Copy BC bytes from the kernel at HL to the program at DE, through
; CBUF, 128 at a time
ustore:	ld	a,b
	or	c
	ret	z
	push	bc
	ld	a,b
	or	a
	jr	nz,us_1
	ld	a,c
	cp	128
	jr	c,us_2
us_1:	ld	bc,128
us_2:	push	bc
	push	de
	ld	de,CBUF
	ldir
	pop	de
	pop	bc
	push	hl
	push	bc
	ld	hl,CBUF
	call	ucopy			; DE moves on
	pop	bc
	pop	hl
	ex	(sp),hl
	or	a
	sbc	hl,bc
	ld	b,h
	ld	c,l
	pop	hl
	jr	ustore

; A file call's result: on to the shell's error unless Z and A = 0
fchk:	jr	nz,sherr
	or	a
	ret	z
; A file error in the shell: print it, back to the prompt
sherr:	push	af
	call	crlf
	pop	af
	cp	R_NOFILE
	jr	z,she_nf
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
	call	crlf
	jr	shell
she_nf:	call	pmsg
	db	"No file",0Dh,0Ah,0
	jr	shell

	include	"ccp.asm"
	include	"bdos.asm"
	include	"file.asm"
	include	"dir.asm"
	include	"fat.asm"
	include	"disk.asm"
	include	"clock.asm"
	include	"util.asm"
	include	"format.asm"		; FORMAT and SYS
KERNEL_END:
