; xcpmz80 FAT layer. Runs in A2. FAT12 and FAT16 volumes of up to
; 65535 sectors of 512 bytes. The BPB in sector 0 describes each
; volume.

; Select drive A (0-2) for the cache and point IX at it. Z if it has
; a device, else NZ and A = E_BADDRV.
seldrv:	cp	NDRV
	jr	nc,sd1
	ld	(drvnum),a
	call	drvix
	ld	a,(ix+D_TYPE)
	or	a
	jr	z,sd1
	xor	a
	ret
sd1:	ld	a,E_BADDRV
	or	a
	ret

; Mount drive A: select it, and read its BPB if not mounted yet.
; Z on success, else NZ and A = error. A floppy that gives no BPB is
; tried once more from the other first sector number: Lobo's layout
; numbers from 0, a PC's from 1, on either connector.
mount:	call	seldrv
	ret	nz
	call	mnt_0
	ret	nz
	jp	setdir
mnt_0:	ld	a,(ix+D_MNT)		; mounted already: Z, A = 0
	dec	a
	ret	z
	call	mount1
	ret	z
	cp	E_READ
	ret	nz
	ld	a,(ix+D_TYPE)
	cp	DT_FLOPPY
	ld	a,E_READ
	ret	nz
	ld	a,(ix+D_SBASE)
	xor	1
	ld	(ix+D_SBASE),a
	ld	a,(drvnum)		; what was read from the other is wrong
	call	bforget
	ld	a,(drvnum)
	call	seldrv
mount1:	ld	de,0
	call	getsec
	ret	nz
	push	hl
	pop	iy			; IY = the boot sector
	ld	a,(iy+0Bh)		; 512 bytes a sector
	or	a
	jp	nz,mtbad
	ld	a,(iy+0Ch)
	cp	2
	jp	nz,mtbad
	ld	a,(iy+0Dh)		; sectors per cluster, a power of 2
	or	a
	jp	z,mtbad
	ld	(ix+D_SPC),a
	ld	b,0
mt1:	rrca
	jr	c,mt2
	inc	b
	jr	mt1
mt2:	ld	(ix+D_SPCSH),b
	ld	l,(iy+0Eh)		; reserved
	ld	h,(iy+0Fh)
	ld	(ix+D_FATSEC),l
	ld	(ix+D_FATSEC+1),h
	ld	a,(iy+10h)
	or	a
	jp	z,mtbad
	ld	(ix+D_NFATS),a
	ld	c,(iy+16h)		; sectors per FAT
	ld	b,(iy+17h)
	ld	(ix+D_SPF),c
	ld	(ix+D_SPF+1),b
mt3:	add	hl,bc			; root = reserved + FATs * SPF
	dec	a
	jr	nz,mt3
	ld	(ix+D_ROOTSEC),l
	ld	(ix+D_ROOTSEC+1),h
	ex	de,hl			; DE = root
	ld	l,(iy+11h)		; root entries, 16 a sector
	ld	h,(iy+12h)
	ld	(ix+D_ROOTENT),l
	ld	(ix+D_ROOTENT+1),h
	ld	b,4
	call	shrb
	ld	(ix+D_ROOTSECS),l
	add	hl,de
	ld	(ix+D_DATASEC),l
	ld	(ix+D_DATASEC+1),h
	ex	de,hl			; DE = data start
	ld	l,(iy+13h)		; total sectors, 16 bit only
	ld	h,(iy+14h)
	ld	a,h
	or	l
	jr	z,mtbad
	ld	(ix+D_TOTAL),l
	ld	(ix+D_TOTAL+1),h
	or	a
	sbc	hl,de
	jr	c,mtbad
	ld	b,(ix+D_SPCSH)		; clusters = data sectors >> SPCSH
	call	shrb
	inc	hl			; highest cluster = clusters + 1
	ld	(ix+D_MAXCL),l
	ld	(ix+D_MAXCL+1),h
	ld	de,-(4085+1)		; FAT16 from 4085 clusters: carry
	add	hl,de
	sbc	a,a			; 0 or 1
	neg
	ld	(ix+D_FAT16),a
	ld	a,(iy+18h)		; floppy geometry
	ld	(ix+D_SPT),a
	ld	a,(iy+1Ah)
	ld	(ix+D_HEADS),a
	call	freeptr			; free clusters: counted when asked
	ld	(hl),0FFh
	inc	hl
	ld	(hl),0FFh
	ld	hl,0			; and a folder's place on another disk
	ld	(dscix),hl
	ld	a,(frdrv)		; and the fresh cluster, if on this
	dec	a			; drive: never zeroed on a disk it may
	ld	hl,drvnum		; not be on. Another drive's stays
	cp	(hl)
	jr	nz,mt_fr
	xor	a
	ld	(frdrv),a
mt_fr:	ld	(ix+D_HINT),2
	ld	(ix+D_HINT+1),0
	ld	(ix+D_MNT),1
	jp	cwdchk
mtbad:	ld	a,E_READ
	or	a
	ret

; Unmount drive A, after writing out its buffers
umount:	push	af
	call	drvix
	ld	(ix+D_MNT),0
	ld	(ix+D_RO),0		; and not write protected (28)
	pop	af
	jp	bforget

; ------------------------------------------------------------------
; FAT entries. IX = the mounted drive, drvnum = its number.

; HL = the entry for cluster HL. Z on success.
fatget:	call	fatloc			; HL = data
	ret	nz
	ld	e,(hl)
	call	fatnext
	ret	nz
	ld	d,(hl)
	ex	de,hl
	ld	a,(ix+D_FAT16)	; FAT16: done, Z
	dec	a
	ret	z
	ld	a,(fodd)
	or	a
	ld	a,h
	jr	z,fg1			; even: the low 12 bits
	add	hl,hl			; odd: the top 12 bits, H = bits 4-11
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	l,h
	rrca				; and A = bits 12-15
	rrca
	rrca
	rrca
fg1:	and	0Fh
	ld	h,a
	xor	a
	ret

; Set the entry for cluster HL to DE. Z on success.
fatset:	push	de
	call	fatloc
	pop	de
	ret	nz
	ld	a,(ix+D_FAT16)
	or	a
	jr	nz,fs16
	ld	a,(fodd)
	or	a
	jr	nz,fsodd
	ld	(hl),e			; even: low 8 bits, then the low nibble
	call	bdirty			; of the next byte
	call	fatnext
	ret	nz
	ld	a,d
	xor	(hl)
	and	0Fh
	xor	(hl)
	jr	fsput
fsodd:	ld	a,e			; odd: the high nibble of this byte,
	add	a,a			; then 8 bits in the next
	add	a,a
	add	a,a
	add	a,a
	xor	(hl)
	and	0F0h
	xor	(hl)
	ld	(hl),a
	call	bdirty
	call	fatnext
	ret	nz
	ld	a,e			; DE >> 4, low byte: E's high nibble
	xor	d			; and D's low one, swapped
	and	0F0h
	xor	d
	rrca
	rrca
	rrca
	rrca
	jr	fsput
fs16:	ld	(hl),e
	call	bdirty
	call	fatnext
	ret	nz
	ld	a,d
fsput:	ld	(hl),a
	xor	a
	jp	bdirty

; HL = address of the first byte of cluster HL's entry, in the cache.
; fodd = 1 for an odd FAT12 cluster. The sector is kept in fsecn and
; the byte in fbyte, for fatnext. Z, A = 0 on success.
fatloc:	ld	a,(ix+D_FAT16)
	or	a
	jr	z,fl12
	ld	a,l			; FAT16: sector H, byte 2 * L
	ld	l,h
	ld	h,0
	add	a,a
	ld	c,a
	ld	b,h
	rl	b
	jr	fl1
fl12:	ld	a,l			; FAT12: byte HL + HL / 2
	and	1
	ld	(fodd),a
	ld	d,h
	ld	e,l
	srl	d
	rr	e
	add	hl,de
	ld	a,h			; sector HL / 512, byte HL % 512
	and	1
	ld	b,a
	ld	c,l
	srl	h
	ld	l,h
	ld	h,0
fl1:	ld	(fbyte),bc
	ld	e,(ix+D_FATSEC)
	ld	d,(ix+D_FATSEC+1)
	add	hl,de
	ld	(fsecn),hl
	ex	de,hl
	call	getsec			; keeps BC
	ret	nz
	add	hl,bc			; Z, A = 0 from getsec
	ret

; HL = the byte after HL in the FAT, which may be in the next sector.
; Keeps DE. One call after each fatloc: fbyte and fsecn stay put.
fatnext: inc	hl
	ld	bc,(fbyte)
	ld	a,c			; carry if fbyte is 511 (B is 0 or 1)
	add	a,b
	jr	c,fn1
	xor	a
	ret
fn1:	push	de			; the next sector
	ld	de,(fsecn)
	inc	de
	call	getsec
	pop	de
	ret

; Carry if HL ends a chain, or is free or bad: below 2 or above the
; highest cluster (which is below FF8h for FAT12, FFF8h for FAT16).
; Keeps HL and DE.
fateoc:	ld	a,l
	and	0FEh
	or	h
	scf
	ret	z			; 0 or 1
	ld	a,(ix+D_MAXCL)	; MAXCL - cluster: carry if beyond
	sub	l
	ld	a,(ix+D_MAXCL+1)
	sbc	a,h
	ret

; HL = a free cluster, marked as the end of a chain. NZ, A = E_FULL,
; if there is none.
fatalloc:
	ld	l,(ix+D_HINT)
	ld	h,(ix+D_HINT+1)
	ld	(fstart),hl
fa_1:	push	hl
	call	fatget
	pop	de
	ret	nz
	ld	a,h
	or	l
	ex	de,hl
	jr	z,fa_3			; free
	inc	hl
	call	fateoc
	jr	nc,fa_2
	ld	hl,2			; past the end: wrap
fa_2:	ld	de,(fstart)
	ld	a,h
	cp	d
	jr	nz,fa_1
	ld	a,l
	cp	e
	jr	nz,fa_1
	ld	a,E_FULL
	or	a
	ret
fa_3:	ld	(ix+D_HINT),l
	ld	(ix+D_HINT+1),h
	push	hl
	ld	de,0FFFFh		; end of chain (FAT12 keeps 12 bits)
	call	fatset
	pop	hl
	ret	nz
	ld	a,-1			; one fewer free
	call	freeadj
	xor	a
	ret

; Free the chain starting at HL. dsub's place in a folder goes: the
; chain it was in may be this one.
fatfree: push	hl
	ld	hl,0
	ld	(dscix),hl
	pop	hl
ffr_1:	call	fateoc
	jr	c,ff9
	call	frgone			; the fresh cluster, if it goes
	push	hl
	call	fatget
	pop	de
	ret	nz
	push	hl
	ex	de,hl
	ld	de,0
	call	fatset
	pop	hl
	ret	nz
	ld	a,1			; one more free
	call	freeadj
	jr	ffr_1
ff9:	xor	a
	ret

; HL = HL >> B, for B 0 or more. B = 0 after.
shrb:	inc	b
sb_1:	dec	b
	ret	z
	srl	h
	rr	l
	jr	sb_1

; DE = first sector of cluster HL
clsec:	dec	hl
	dec	hl
	ld	b,(ix+D_SPCSH)
	inc	b
cs1:	dec	b
	jr	z,cs2
	add	hl,hl
	jr	cs1
cs2:	ld	e,(ix+D_DATASEC)
	ld	d,(ix+D_DATASEC+1)
	add	hl,de
	ex	de,hl
	ret

; Count the free clusters: HL
fatcount:
	call	freeptr			; counted since the mount?
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	a,d
	and	e
	inc	a
	jr	z,fcn_0
	ex	de,hl
	ret
fcn_0:	push	hl			; no: count them, and keep it
	call	fcn_s
	pop	hl
	jr	nz,fcn_9		; a FAT not read: not kept
	ld	(hl),d
	dec	hl
	ld	(hl),e
fcn_9:	ex	de,hl
	ret
; DE = the free clusters. NZ if a FAT sector could not be read, DE
; those counted before it
fcn_s:	ld	de,0
	ld	hl,2
fcn_1:	push	de
	push	hl
	call	fatget
	jr	nz,fcn_e
	ld	a,h
	or	l
	pop	hl
	pop	de
	jr	nz,fcn_2
	inc	de
fcn_2:	inc	hl
	call	fateoc			; keeps DE
	jr	nc,fcn_1
	xor	a
	ret
fcn_e:	pop	hl
	pop	de
	ret

; HL = drive IX's free count in dfree. Keeps BC and DE.
freeptr: push	de
	push	ix
	pop	hl
	ld	de,-drvtab		; drive * DSZ, DSZ 32
	add	hl,de
	ld	a,l
	rrca
	rrca
	rrca
	rrca
	and	0Eh			; drive * 2, NDRV up to 8
	ld	l,a
	ld	h,0
	ld	de,dfree
	add	hl,de
	pop	de
	ret

; The count, if kept, one less (A = -1) or more (A = 1). Keeps BC, DE, HL.
freeadj: push	hl
	push	de
	ld	e,a
	call	freeptr
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	a
	jr	z,fj_9			; not counted
	dec	hl
	ld	a,e			; D = E's sign, for the high byte
	rla
	sbc	a,a
	ld	d,a
	ld	a,(hl)
	add	a,e
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,d
	ld	(hl),a
fj_9:	pop	de
	pop	hl
	ret
