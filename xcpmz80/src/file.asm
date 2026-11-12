; xcpmz80 files. Runs in A2. CP/M FCB operations on FAT, on the
; FCB copied into common memory at CFCB. A file is a FAT directory
; entry. Its state lives in the FCB's 16 allocation bytes, so a program
; may copy an open FCB, as CP/M allows:
F_DR		equ	0		; drive, 0 default, 1 A: ...
F_NAME		equ	1		; 8 + 3, attributes in bit 7 of 9-11
F_EX		equ	12
F_S1		equ	13
F_S2		equ	14
F_RC		equ	15
F_MAGIC		equ	16		; FAh when we opened it
F_DRIVE		equ	17		; the drive it is on, 0-2
F_CLUS		equ	18		; first cluster, 2 bytes
F_SIZE		equ	20		; bytes, 4 (3 used)
F_DSEC		equ	24		; directory sector, 2
F_DIDX		equ	26		; entry in that sector, 0-15
F_CCL		equ	27		; a cluster of the chain, 2
F_CORD		equ	29		; its place in the chain, 2
F_FLAG		equ	31		; bit 0: size or first cluster changed
F_CR		equ	32
F_R0		equ	33		; random record, 3 bytes
MAGIC		equ	0FAh

; FAT directory entry
DE_ATTR		equ	11
DE_TIME		equ	22
DE_DATE		equ	24
DE_CLUS		equ	26
DE_SIZE		equ	28
A_RO		equ	01h
A_HID		equ	02h
A_SYS		equ	04h
A_VOL		equ	08h
A_DIR		equ	10h
A_ARC		equ	20h

; CP/M's file errors, as function results
R_NOFILE	equ	0FFh

; ------------------------------------------------------------------
; Mount the FCB's drive. Z on success with IX set, else NZ, A = error.
fcbdrv:	ld	a,(CFCB+F_DR)
	and	1Fh
	jr	nz,fd_1
	ld	a,(scb+SCB_DRV)
	inc	a
fd_1:	dec	a
	ld	(fdrive),a
	jp	mount

; Mount the drive of the open FCB (F_DRIVE), as fcbdrv
fcbmnt:	ld	a,(CFCB+F_DRIVE)
	inc	a
	jr	fd_1

; As fcbdrv, for a change to the disk: NZ, A = E_WRPROT, if it is
; write protected
fcbdrw:	call	fcbdrv
	ret	nz
; NZ, A = E_WRPROT, if drive IX is write protected
wrprot:	ld	a,(ix+D_RO)
	or	a
	ld	a,E_WRPROT
	ret

; ------------------------------------------------------------------
; Directory search over folder dircl. The pattern is the 11 bytes at spat.
; dsfirst starts from entry 0, dsnext from dpos + 1. Z: found, HL = the
; entry in the cache, dpos its number. NZ: A = R_NOFILE, or an error.
dsfirst: ld	hl,0
	jr	ds_0
dsnext:	ld	hl,(dpos)
	inc	hl
ds_0:	ld	(dpos),hl
	call	dirent
	ret	nz
	ld	a,(hl)
	or	a
	jr	z,ds_end		; the end of the directory
	cp	0E5h
	jr	z,dsnext
	push	hl			; the name first, it fails sooner
	ld	de,spat
	ld	b,11
	call	match
	pop	hl
	jr	nz,dsnext
	ld	a,(dsdirs)		; no labels, nor folders unless
	xor	A_VOL or A_DIR		; dsdirs is A_DIR
	ld	b,a
	call	isattr
	jr	nz,dsnext
	ret				; Z, A = 0
ds_end:	ld	a,R_NOFILE
	or	a
	ret

; HL = address of entry HL of folder dircl in the cache. NZ, A =
; R_NOFILE past the last entry, or A = error. dsec, didx are its sector
; and index.
dirent:	ld	a,(dircl)
	ld	b,a
	ld	a,(dircl+1)
	or	b
	jp	nz,dsub
	ld	a,l			; the root: HL < entries?
	sub	(ix+D_ROOTENT)
	ld	a,h
	sbc	a,(ix+D_ROOTENT+1)
	jr	nc,ds_end
	ld	a,l
	and	0Fh
	ld	(didx),a
	ld	b,4
de_2:	srl	h
	rr	l
	djnz	de_2
	ld	e,(ix+D_ROOTSEC)
	ld	d,(ix+D_ROOTSEC+1)
	add	hl,de
	ld	(dsec),hl
	ex	de,hl
	call	getsec
	ret	nz
	ld	a,(didx)
deoff:	rrca				; HL += A * 32, for A 0-15
	rrca
	rrca
	ld	d,a
	and	0E0h
	ld	e,a
	xor	d
	ld	d,a
	add	hl,de
	xor	a
	ret

; HL = the entry the FCB points at (F_DSEC, F_DIDX), in the cache
fcbent:	ld	de,(CFCB+F_DSEC)
	call	getsec
	ret	nz
	ld	a,(CFCB+F_DIDX)
	and	0Fh
	jr	deoff

; Copy the 11 name bytes of the FCB, attribute bits off, to spat
fcbpat:	ld	hl,CFCB+F_NAME
	call	namepat
	ld	hl,spat			; $$$.SUB, the batch, in the root
	ld	de,subname+1
	ld	b,11
	call	match
	ret	nz
	ld	h,b			; B = 0
	ld	l,b
	ld	(dircl),hl
	ret
; Copy the 11 name bytes at HL, attribute bits off, to spat
namepat: ld	de,spat
	ld	b,11
fp_1:	ld	a,(hl)
	and	7Fh
	ld	(de),a
	inc	hl
	inc	de
	djnz	fp_1
	ret

; Fill the FCB from the directory entry at HL, found at dsec/didx:
; name and attributes, the private state, and RC for extent EX
fcbfill: push	hl
	ld	de,CFCB+F_NAME
	ld	bc,11
	ldir
	ld	c,(hl)			; attributes into t1' (R/O), t2' (SYS)
	ld	hl,CFCB+F_NAME+8
	ld	a,(hl)
	add	a,a
	rr	c			; A_RO
	rra
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	add	a,a
	rr	c
	rr	c			; A_SYS
	rra
	ld	(hl),a
	inc	hl
	res	7,(hl)
	pop	hl
	ld	de,DE_CLUS
	add	hl,de
	ld	de,CFCB+F_MAGIC		; F_MAGIC to F_FLAG, in order: the
	ld	a,MAGIC
	ld	(de),a
	inc	de
	ld	a,(fdrive)		; drive,
	ld	(de),a
	inc	de
	ld	bc,6			; first cluster and size (DE_CLUS, DE_SIZE),
	ldir
	ld	hl,dsec		; the entry's place (dsec, didx),
	ld	c,3
	ldir
	ld	hl,CFCB+F_CLUS	; the chain cache at the first cluster
	ld	c,2
	ldir
	xor	a
	ld	(de),a			; F_CORD 0
	inc	de
	ld	(de),a
	inc	de
	ld	(de),a			; F_FLAG 0
	ld	(CFCB+F_S1),a
	; fall into setrc

; RC = the records of extent (S2, EX) that the file holds
setrc:	call	extrec			; HL = first record of the extent
	ex	de,hl
	call	nrecs			; HL = records in the file, carry if
	jr	c,sr_full		; more than 65535, else no carry
	sbc	hl,de
	jr	c,sr_none
	ld	a,h
	or	a
	jr	nz,sr_full
	ld	a,l
	cp	81h
	jr	c,sr_1
sr_full: ld	a,80h
	jr	sr_1
sr_none: xor	a
sr_1:	ld	(CFCB+F_RC),a
	ret

; HL = the first record of the FCB's extent: (S2 * 32 + EX) * 128, in
; 16 bits: S2 * 4096 + EX * 128
extrec:	ld	a,(CFCB+F_S2)
	add	a,a
	add	a,a
	add	a,a
	add	a,a
	ld	h,a
	ld	a,(CFCB+F_EX)
	and	1Fh
	rra				; EX / 2, its bit 0 into carry
	ld	l,0
	rr	l
	or	h
	ld	h,a
	ret

; B:H:L = HL * 128
rec128:	xor	a
	srl	h
	rr	l
	rra
	ld	b,h
	ld	h,l
	ld	l,a
	ret

; HL = the file's size in records, rounded up. Carry if over 65535.
; Keeps DE.
nrecs:	ld	hl,(CFCB+F_SIZE)
	ld	a,(CFCB+F_SIZE+2)
	push	de
	ld	de,127
	add	hl,de
	pop	de
	adc	a,0
	add	hl,hl			; / 128 = * 2 / 256
	rla
	ret	c			; 65536 records or more
	ld	l,h
	ld	h,a
	ld	a,(CFCB+F_SIZE+3)
	or	a
	ret	z
	scf
	ret

; ------------------------------------------------------------------
; Open the FCB. A = 0, or R_NOFILE. NZ with an error.
fopen:	call	fcbdrv
	ret	nz
	call	fcbpat
	call	dsfirst
	jr	nz,fo_9
	call	fcbfill
	xor	a
	ret
fo_9:	cp	R_NOFILE		; none: Z, A = R_NOFILE
	ret

; Make the file. An existing file of that name is emptied and reused.
fmake:	call	fcbdrw
	ret	nz
	call	fcbpat
	call	dsfirst
	jr	z,fm_old
	cp	R_NOFILE
	ret	nz
	call	dsany			; a folder of that name: as full
	jr	z,fm_no
	cp	R_NOFILE
	ret	nz
	call	dnew			; a free entry
	jr	z,fm_4
	cp	R_NOFILE		; directory full: Z, A = R_NOFILE
	ret
fm_no:	ld	a,R_NOFILE
	cp	a
	ret
fm_old:	call	isro			; an old one: free its clusters
	ld	a,E_ROFILE
	ret	nz
	ld	de,DE_CLUS
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	dec	hl
	ld	b,6
fm_5:	ld	(hl),0			; no clusters, size 0
	inc	hl
	djnz	fm_5
	call	bdirty
	ex	de,hl
	call	fatfree
	ret	nz
	ld	hl,(dpos)		; the entry may have left the cache
	call	dirent
	ret	nz
fm_4:	push	hl
	call	stamp			; date and time
	pop	hl
	call	fcbfill			; RC 0: the file is empty
	xor	a
	ld	(CFCB+F_S2),a
	ret

; Put the time into the entry at HL, and mark its buffer written
stamp:	push	hl
	call	fatnow			; DE = date, BC = time
	pop	hl
	push	de
	ld	de,DE_TIME
	add	hl,de
	ld	(hl),c
	inc	hl
	ld	(hl),b
	inc	hl
	pop	de
	ld	(hl),e
	inc	hl
	ld	(hl),d
	jp	bdirty

; Close the FCB: write its size and first cluster to its entry if they
; changed, and everything to the disk. A = 0, or R_NOFILE.
fclose:	ld	a,(CFCB+F_MAGIC)
	cp	MAGIC
	jr	nz,fc_open
	call	fcbmnt
	ret	nz
	call	rccut
	ret	nz
	ld	a,(CFCB+F_FLAG)
	rrca
	jr	nc,fc_2
	call	fcbsync
	ret	nz
	call	stamp
	xor	a
	ld	(CFCB+F_FLAG),a
fc_2:	jp	flushall
fc_open: call	fopen			; never opened here: CP/M finds the
	ret	nz			; entry, and so do we
	cp	R_NOFILE
	jr	nz,fc_2
	ret

; An RC under 80h ends the file at that extent: CP/M 2.2's CCP and XSUB
; drop the last line of $$$.SUB by lowering RC and closing. Cut the
; file there when it is longer and was not written since it was opened
; (a writer's RC may lag). Z unless the cut fails.
rccut:	ld	a,(CFCB+F_FLAG)
	rrca
	jr	c,rc_9
	ld	a,(CFCB+F_RC)
	cp	80h
	jr	nc,rc_9
	call	extrec			; HL = records before the extent
	ld	a,(CFCB+F_RC)
	ld	e,a
	ld	d,0
	add	hl,de
	jr	c,rc_9
	call	rec128			; bytes = B:H:L, records * 128
	ld	a,(CFCB+F_SIZE)		; longer than that?
	sub	l
	ld	e,a
	ld	a,(CFCB+F_SIZE+1)
	sbc	a,h
	ld	d,a
	ld	a,(CFCB+F_SIZE+2)
	sbc	a,b
	jr	c,rc_9
	or	d
	or	e
	jr	z,rc_9
	ld	(CFCB+F_SIZE),hl
	ld	a,b
	ld	(CFCB+F_SIZE+2),a
	call	ftrunc
	ret	nz
	ld	a,1
	ld	(CFCB+F_FLAG),a
rc_9:	xor	a
	ret

; The FCB's first cluster and size into its directory entry, which is
; HL after, with the archive bit set. Z on success.
fcbsync: call	fcbent			; Z, A = 0
	ret	nz
	push	hl
	ld	de,DE_ATTR
	add	hl,de
	set	5,(hl)			; archive
	ld	de,DE_CLUS-DE_ATTR	; first cluster and size, in order in
	add	hl,de			; both
	ex	de,hl
	ld	hl,CFCB+F_CLUS
	ld	bc,6
	ldir
	pop	hl
	jp	bdirty			; Z, A = 0 still

; ------------------------------------------------------------------
; Records. HL = record number. The FCB is open (F_MAGIC).

; Point at record HL: frec_sec = its sector, frec_off = its offset.
; For a write (fwflag 1) the chain is grown to reach it. NZ, A = 1 if a
; read is past the end, or A = error.
recloc:	ld	(frec),hl
	call	fcbmnt
	ret	nz
	ld	a,(fwflag)
	or	a
	jr	nz,rl_1
	ld	de,(frec)		; a read: below the size?
	call	nrecs			; (keeps DE)
	jr	c,rl_1
	ex	de,hl			; no carry here
	sbc	hl,de
	jp	nc,rl_eof
rl_1:	ld	hl,(frec)		; sector number in the file
	srl	h
	rr	l
	srl	h
	rr	l
	ld	a,(ix+D_SPC)		; its sector in the cluster
	dec	a
	and	l
	ld	(fsin),a
	ld	b,(ix+D_SPCSH)		; the cluster's place in the chain
	call	shrb
	ld	(ford),hl
	ld	hl,(CFCB+F_CLUS)	; an empty file: give it a cluster
	ld	a,h
	or	l
	jr	nz,rl_4
	ld	a,(fwflag)
	or	a
	jp	z,rl_eof
	call	fatalloc
	ret	nz
	ld	(CFCB+F_CLUS),hl
	call	cfresh
	ld	hl,CFCB+F_FLAG
	set	0,(hl)
	jr	rl_5
rl_4:	ld	de,(CFCB+F_CORD)	; start from the cached place if it is
	ld	hl,(ford)		; not past the one we want
	or	a
	sbc	hl,de
	jr	c,rl_5
	ld	hl,(CFCB+F_CCL)
	ld	a,h
	or	l
	jr	nz,rl_8
rl_5:	ld	hl,0			; else from the first cluster
	ld	(CFCB+F_CORD),hl
	ld	hl,(CFCB+F_CLUS)
	ld	(CFCB+F_CCL),hl
rl_8:	ld	hl,(CFCB+F_CORD)	; there yet?
	ld	de,(ford)
	or	a
	sbc	hl,de
	jr	z,rl_10
	ld	hl,(CFCB+F_CCL)	; on down the chain
	call	fatget
	ret	nz
	call	fateoc
	jr	nc,rl_9
	ld	a,(fwflag)		; the end: grow it, or end of file
	or	a
	jr	z,rl_eof
	call	fatalloc
	ret	nz
	push	hl
	ex	de,hl
	ld	hl,(CFCB+F_CCL)
	call	fatset
	pop	hl
	ret	nz
	call	cfresh
rl_9:	ld	(CFCB+F_CCL),hl	; F_CCL and F_CORD move together, so
	ld	hl,(CFCB+F_CORD)	; an error on the way leaves them right
	inc	hl
	ld	(CFCB+F_CORD),hl
	jr	rl_8
rl_10:	ld	hl,(CFCB+F_CCL)
	call	clsec
	ld	a,(fsin)
	add	a,e
	ld	e,a
	jr	nc,rl_11
	inc	d
rl_11:	ld	(fsect),de
	ld	a,(frec)		; offset of the record in the sector:
	and	3			; (record & 3) * 128
	rrca
	ld	e,a
	and	1
	ld	d,a
	xor	e
	ld	e,a
	ld	(foff),de
	xor	a
	ret
rl_eof:	ld	a,1
	or	a
	ret

; A newly allocated cluster HL: zero its sectors, so that a record
; written into it does not read old data, and a short last sector reads
; clean. Keeps HL.
cfresh:	push	hl
	call	clsec
	ld	b,(ix+D_SPC)
cr_1:	push	bc
	call	newsec
	jr	nz,cr_2
	push	de
	ld	d,h
	ld	e,l
	inc	de
	ld	(hl),0
	ld	bc,511
	ldir
	call	bdirty
	pop	de
	inc	de
	pop	bc
	djnz	cr_1
	pop	hl
	ret
cr_2:	pop	bc
	pop	hl
	ret

; Read record HL into CBUF. A = 0, 1 at the end of the file, or NZ
; with an error. A short last record is filled with ^Z.
rdrec:	xor	a
	ld	(fwflag),a
	call	recloc
	jr	z,rr_1
	cp	1			; end of file: Z, A = 1
	ret
rr_1:	ld	de,(fsect)
	call	getsec
	ret	nz
	ld	de,(foff)
	add	hl,de
	ld	de,CBUF
	ld	bc,128
	ldir
	ld	hl,(frec)		; bytes left = size - record * 128
	call	rec128			; (only the last record is short)
	ld	de,(CFCB+F_SIZE)
	ex	de,hl
	or	a
	sbc	hl,de
	ld	a,(CFCB+F_SIZE+2)
	sbc	a,b
	jr	nz,rr_9			; 64K or more left
	ld	a,h
	or	a
	jr	nz,rr_9
	ld	a,l
	cp	128
	jr	nc,rr_9
	ld	e,a			; fill from byte L with ^Z
	ld	d,0
	ld	hl,CBUF
	add	hl,de
	ld	a,128
	sub	e
	ld	b,a
rr_2:	ld	(hl),1Ah
	inc	hl
	djnz	rr_2
rr_9:	xor	a
	ret

; Write CBUF as record HL. A = 0, or NZ with an error (A = E_FULL when
; the disk is full).
wrrec:	ld	a,(CFCB+F_DRIVE)
	call	drvix
	call	wrprot
	ret	nz
	ld	a,(CFCB+F_NAME+8)	; t1': the file is R/O
	and	80h
	ld	a,E_ROFILE
	ret	nz
	ld	a,1
	ld	(fwflag),a
	call	recloc
	ret	nz
	ld	de,(fsect)
	call	getsec
	ret	nz
	ld	de,(foff)
	add	hl,de
	ex	de,hl
	ld	hl,CBUF
	ld	bc,128
	ldir
	call	bdirty
	ld	hl,(frec)		; the size grows to the record's end,
	inc	hl			; B:H:L = (record + 1) * 128
	ld	a,h
	or	l
	ld	b,80h			; record 65535: 8M
	jr	z,wr_1
	call	rec128
wr_1:	ld	a,(CFCB+F_SIZE)	; at or past the size? size - B:H:L - 1
	scf				; borrows if so
	sbc	a,l
	ld	a,(CFCB+F_SIZE+1)
	sbc	a,h
	ld	a,(CFCB+F_SIZE+2)
	sbc	a,b
	jr	nc,wr_9		; inside the file: no change
	ld	(CFCB+F_SIZE),hl
	ld	a,b
	ld	(CFCB+F_SIZE+2),a
	ld	hl,CFCB+F_FLAG	; to be stamped at close
	set	0,(hl)
	jp	fcbsync			; the entry follows the file, so one
					; never closed has its clusters
wr_9:	xor	a
	ret

; ------------------------------------------------------------------
; NZ if the directory entry at HL is read only. Keeps HL.
isro:	ld	b,A_RO
; A = the attribute bits of the entry at HL that are in B, NZ if any.
; Keeps HL.
isattr:	push	hl
	ld	de,DE_ATTR
	add	hl,de
	ld	a,(hl)
	pop	hl
	and	b
	ret

; Delete every file matching the FCB. A = 0, or R_NOFILE if none.
fdelete: call	fcbdrw
	ret	nz
	call	fcbpat
	ld	a,R_NOFILE
	ld	(fres),a
	call	dsfirst			; one R/O match and none go, as in
fl_0:	jr	nz,fl_00		; CP/M 3
	call	isro
	ld	a,E_ROFILE
	ret	nz
	call	dsnext
	jr	fl_0
fl_00:	cp	R_NOFILE
	ret	nz
	call	dsfirst
fl_1:	jr	nz,fl_9
	ld	(hl),0E5h
	call	bdirty
	ld	de,DE_CLUS
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ex	de,hl
	call	fatfree
	ret	nz
	xor	a
	ld	(fres),a
	call	dsnext
	jr	fl_1
fl_9:	cp	R_NOFILE
	ret	nz
	call	flushall
	ret	nz
	ld	a,(fres)
	cp	a
	ret

; Rename the file named in the FCB to the name at FCB+17. A = 0, or
; R_NOFILE if it is not there or the new name is taken.
frename: call	fcbdrw
	ret	nz
	ld	hl,CFCB+17		; the new name must be free, of
	call	namepat			; files and folders
	call	dsany
	jr	z,fn_no
	cp	R_NOFILE
	ret	nz
	call	fcbpat
	call	dsfirst
	jr	z,fn_2
	cp	R_NOFILE
	ret	nz
fn_no:	ld	a,R_NOFILE
	cp	a
	ret
fn_2:	call	isro
	ld	a,E_ROFILE
	ret	nz
	ex	de,hl
	ld	hl,CFCB+17
	ld	b,11
fn_3:	ld	a,(hl)
	and	7Fh
	cp	'?'			; a '?' keeps the old character
	jr	z,fn_4
	ld	(de),a
fn_4:	inc	hl
	inc	de
	djnz	fn_3
	call	bdirty
	jp	flushall

; Move the file the FCB names, in folder dircl after fcbdrw, to folder
; mvdst on the same drive as the name at CFCB+17, its directory entry
; moved and no data copied. A = 0, R_NOFILE when there is no such file,
; the new name is taken or the folder has no room, or an error.
fmove:	call	fcbdrw
	ret	nz
	ld	hl,(dircl)
	ld	(mvsrc),hl
	ld	hl,(mvdst)		; the new name must be free there
	ld	(dircl),hl
	ld	hl,CFCB+17
	call	namepat
	call	dsany
	jp	z,fn_no
	cp	R_NOFILE
	ret	nz
	ld	hl,(mvsrc)
	ld	(dircl),hl
	call	fcbpat			; $$$.SUB: the root, so the old entry
	ld	hl,(dircl)		; is freed there
	ld	(mvsrc),hl
	call	dsfirst
	jr	z,fm_1
	cp	R_NOFILE
	ret	nz
	jp	fn_no
fm_1:	call	isro
	ld	a,E_ROFILE
	ret	nz
	ld	de,mvbuf		; keep the entry and where it is
	ld	bc,32
	ldir
	ld	hl,(dpos)
	ld	(mvpos),hl
	ld	hl,(mvdst)		; a new one in the folder
	ld	(dircl),hl
	ld	hl,CFCB+17
	call	namepat
	call	dnew
	jp	nz,fn_no
	ld	de,11			; with the old one's attributes,
	add	hl,de			; times, cluster and size
	ex	de,hl
	ld	hl,mvbuf+11
	ld	bc,21
	ldir
	call	bdirty
	ld	hl,(mvsrc)		; then the old one goes
	ld	(dircl),hl
	ld	hl,(mvpos)
	ld	(dpos),hl
	call	dirent
	ret	nz
	ld	(hl),0E5h
	call	bdirty
	jp	flushall

; Set the attributes of the files matching the FCB from its t1' (R/O)
; and t2' (SYS) bits. A = 0, or R_NOFILE.
fattrib: call	fcbdrv
	ret	nz
	call	fcbpat
	call	dsfirst
	jr	z,fat_1
	cp	R_NOFILE		; none: Z, A = R_NOFILE
	ret
fat_1:	ld	de,DE_ATTR
	add	hl,de
	ld	a,(hl)
	and	not (A_RO or A_SYS)
	ld	c,a
	ld	a,(CFCB+F_NAME+8)
	rlca
	and	1
	or	c
	ld	c,a
	ld	a,(CFCB+F_NAME+9)
	rlca
	rlca
	rlca
	and	A_SYS
	or	c
	ld	(hl),a
	call	bdirty
	jp	flushall

; Cut the file's chain to fit its F_SIZE: free the clusters past it.
; The FCB is open and its drive mounted (IX).
ftrunc:	ld	hl,(CFCB+F_SIZE)	; sectors = (size + 511) / 512
	ld	a,(CFCB+F_SIZE+2)
	ld	de,511
	add	hl,de
	adc	a,0
	ld	l,h			; / 256, then / 2
	ld	h,a
	srl	h
	rr	l
	ld	a,(ix+D_SPC)		; clusters = (sectors + SPC - 1) >> SPCSH
	dec	a
	ld	e,a
	ld	d,0
	add	hl,de
	ld	b,(ix+D_SPCSH)
	call	shrb
	ld	de,0			; the chain restarts the cache
	ld	(CFCB+F_CORD),de
	ld	de,(CFCB+F_CLUS)
	ld	(CFCB+F_CCL),de
	ld	a,h
	or	l
	jr	nz,tr_3
	ex	de,hl			; none kept: free it all, DE = 0
	ld	(CFCB+F_CLUS),de
	ld	(CFCB+F_CCL),de
	jp	fatfree
tr_3:	ld	a,d			; no chain: nothing to cut
	or	e
	ret	z
	ld	b,h			; walk to the last cluster kept
	ld	c,l
	ex	de,hl
tr_4:	dec	bc
	ld	a,b
	or	c
	jr	z,tr_5
	push	bc
	call	fatget
	pop	bc
	ret	nz
	call	fateoc
	jr	nc,tr_4
	xor	a			; the chain is shorter already
	ret
tr_5:	push	hl			; end the chain here, free the rest
	call	fatget
	pop	de
	ret	nz
	push	hl
	ex	de,hl
	ld	de,0FFFFh
	call	fatset
	pop	hl
	ret	nz
	jp	fatfree
