; xcpmz80 FORMAT and SYS. Kept in common memory, run from the
; shell with A2 mapped.
;
; FORMAT d: writes every track of a floppy in the layout of Lobo's
; COPIER (17 x 512-byte MFM sectors numbered 0 to 16), then an empty
; FAT12 volume with the boot sector and the system, so the disk boots.
; FORMAT d: 360, 180 or 720 makes a floppy of 9 sectors numbered 0 to 8
; on the 5-inch connector, the layout of mkdisk.py --525, which boots.
; PC after the size numbers them 1 to 9, a PC's
; layout, which the machine does not boot. FORMAT d: 1440 makes a
; 3.5-inch 1.44M one, 18 sectors, on the 8-inch connector, at 500
; kbit/s. A drive found to be 5-inch gets 360K when no size is given.
; FORMAT d: MB makes an empty FAT volume of MB megabytes on the SASI
; hard disk, as mkdisk.py --hd does. SYS d: puts the boot code and the
; system on a FAT volume and keeps its BPB.
;
; The system is read from A:, the boot device, first: sectors 0 to
; SYSSEC, kept in the TPA at SYSBUF, which is free while the shell runs.
; That way A: can be formatted too.

SYSBUF		equ	1000h		; in the TPA
	assert	high fmtslt == high (fmtslt+17)	; fslots, trkbuild
FMTSZ		equ	11900		; 18 sectors of 1.44M, gap 84
	assert	FMTSZ & 0FFh		; the count in B is not 0

; FORMAT d:, FORMAT d: size [PC] (fmtab), or FORMAT d: MB
cformat: call	memchk
	jp	c,fmt_use
	push	hl
	call	seldrv
	pop	hl
	jp	nz,sherr
	ld	a,(ix+D_TYPE)
	cp	DT_SASI
	jr	z,fmt_h
	ld	de,0			; a floppy: a size?
	ld	(fmtk),de
	xor	a
	ld	(fmtpc),a
	ld	(fmtilv),a
	call	skipsp
	call	ilvopt			; ILV n first?
	jp	c,fmt_use
	ld	a,(hl)
	or	a
	jr	z,fmt_1
	ld	de,fmtab
fmt_r:	ld	a,(de)
	or	a
	jp	z,fmt_use
	push	de
	call	fmtarg
	pop	de
	jr	z,fmt_k
	ex	de,hl
	ld	bc,FROW
	add	hl,bc
	ex	de,hl
	jr	fmt_r
fmt_k:	ld	(fmtk),de
	jr	fmt_1
fmt_h:
	call	skipsp			; the hard disk: its size
	call	getnum
	jp	c,fmt_use
	or	a
	jp	z,fmt_use
	cp	33
	jp	nc,fmt_use
	ld	(fmtmb),a
	call	hdsize			; its last sector must read: a drive
	dec	hl			; smaller than the volume is refused
	ex	de,hl			; before anything is asked or written
	ld	hl,fmtbuf
	call	rdsec
	jr	z,fmt_1
	call	pmsgsh
	db	0Dh,0Ah,"The drive is smaller than that",0Dh,0Ah,0
fmt_1:	call	pmsg
	db	0Dh,0Ah,"Format ",0
	call	pdrv
	call	pmsg
	db	": and lose its files (Y/N)? ",0
	call	conin
	call	upper
	push	af
	call	kputc
	call	crlf
	pop	af
	cp	'Y'
	jp	nz,shell
	call	sysget			; the system, before A: is touched
	jp	nz,sherr
	call	fmtums
	ld	a,(ix+D_TYPE)
	cp	DT_SASI
	jr	z,fmt_hd
	call	fgeom			; the format this writes
	jp	nz,fmt_err
	call	fmtds
	jp	nz,fmt_err
	call	fmttrks
	jp	nz,fmt_err
	call	fbpbcp			; the floppy BPB
	ld	hl,(fmtk)		; a size: its BPB over it
	ld	a,h
	or	l
	jr	z,fmt_vol
	ld	de,9
	add	hl,de
	ld	a,(hl)			; sectors a cluster
	ld	(fmtbuf+0Dh),a
	inc	hl
	ld	de,fmtbuf+11h		; root entries to sectors a FAT
	ld	bc,7
	ldir
	ld	a,(ix+D_SPT)		; and the geometry, as fgeom set it
	ld	(fmtbuf+18h),a
	ld	a,(ix+D_HEADS)
	ld	(fmtbuf+1Ah),a
	call	fmt25
	jr	fmt_vol
fmt_hd:	call	hdbpb
fmt_vol:	call	fmtvol
	jp	nz,fmt_err
	call	fmtum
	ld	a,(fmtdrv)		; its folders are gone: at the root
	call	cwdroot
	call	pmsg
	db	"Formatted, ",0
	ld	a,(fmtdrv)
	call	mntsh
	jp	pfree
fmt_use:	call	pmsgsh
	db	0Dh,0Ah,"FORMAT d: for a floppy, FORMAT d: DS for a double sided "
	db	"8-inch,",0Dh,0Ah
	db	"FORMAT d: 360, 180, 720 or 1440 for other sizes, then PC",0Dh,0Ah
	db	"for a PC's layout, which does not boot here,",0Dh,0Ah
	db	"FORMAT d: MB (1 to 32) for the hard disk.",0Dh,0Ah
	db	"ILV n after d: or at the end sets a floppy's interleave",0Dh,0Ah,0

; BPB byte 25h tells the boot sector that two sides of 9 sectors are
; numbered from 0, as mkdisk.py --525 sets it
fmt25:	ld	a,(ix+D_SBASE)
	or	a
	ret	nz
	ld	a,(ix+D_HEADS)
	dec	a
	ret	z
	ld	a,(ix+D_SPT)
	cp	SPT
	ret	z
	ld	a,1
	ld	(fmtbuf+25h),a
	ret

; Lobo's layout on two sides wants a double sided disk: SYSFLG bit 4
; is set when the selected 8-inch drive says single sided. Not checked
; for 1.44M, whose drive sits on an adapter, or a 5-inch drive. NZ,
; A = E_NOTRDY if the drive is not there.
fmtds:	ld	a,(ix+D_HEADS)
	dec	a
	ret	z
	ld	a,(ix+D_SPT)
	cp	SPT
	jr	z,fs_1
	xor	a
	ret
fs_1:	call	fdsel
	ret	nz
	ld	a,(SYSFLG)
	and	10h
	ret	z
	call	fmtum
	call	pmsgsh
	db	"Single sided disk",0Dh,0Ah,0

; Z if the text at HL is the name at DE, up to 4 characters or a 0,
; and the line ends there, or goes on with PC alone, which sets fmtpc
fmtarg:	push	hl
	ld	b,4
fz_1:	ld	a,(de)
	or	a
	jr	z,fz_2
	cp	(hl)
	jr	nz,fz_9
	inc	de
	inc	hl
	djnz	fz_1
fz_2:	call	skipsp
	ld	a,(hl)
	or	a
	jr	z,fz_9
	call	ilvopt			; ILV n after the size
	jr	c,fz_n
	jr	nz,fz_p
	ld	a,(hl)
	or	a
	jr	fz_9
fz_p:	ld	a,(hl)
	cp	'P'
	jr	nz,fz_9
	inc	hl
	ld	a,(hl)
	cp	'C'
	jr	nz,fz_9
	inc	hl
	call	skipsp
	call	ilvopt			; or after PC
	jr	c,fz_n
	ld	a,(hl)
	or	a
	jr	nz,fz_9
	inc	a
	ld	(fmtpc),a
	xor	a
fz_9:	pop	hl
	ret
fz_n:	or	1
	jr	fz_9

; ILV n at HL, the interleave, 1 to 16: Z, fmtilv set and HL past it and
; the spaces after it. NZ, HL kept, if the text is not ILV. Carry if n
; is missing or out of range.
ilvopt:	ld	a,(hl)
	cp	'I'
	jr	nz,io_no		; cp leaves carry for a lower letter
	inc	hl
	ld	a,(hl)
	cp	'L'
	jr	nz,io_n
	inc	hl
	ld	a,(hl)
	cp	'V'
	jr	nz,io_n1
	inc	hl
	call	skipsp
	call	getnum
	ret	c
	or	a
	scf
	ret	z
	cp	17
	ccf
	ret	c
	ld	(fmtilv),a
	call	skipsp
	xor	a
	ret
io_n1:	dec	hl
io_n:	dec	hl
io_no:	or	1			; NZ, no carry
	ret

; fmtslt: the sector in each slot of a track, as mkdisk.py --ilv puts
; them: sector l in slot l * interleave, or the next free slot after
; it. The interleave is fmtilv, or by default 3 on 8-inch, 17 a track,
; where the kernel takes longer between sectors than 2 leave, else 2.
fslots:	ld	a,(fmtilv)
	or	a
	jr	nz,fo_0
	ld	a,(ix+D_SPT)
	cp	17
	ld	a,3
	jr	z,fo_0
	dec	a
fo_0:	ld	d,a			; D the interleave
	ld	hl,fmtslt
	ld	b,18
	ld	a,0FFh
	call	fill
	ld	c,0			; C the sector
	ld	e,0			; E sector * interleave, mod SPT
fo_1:	ld	b,e			; B the slot
	ld	hl,fmtslt
	ld	a,e
	add	a,l
	ld	l,a
fo_2:	ld	a,(hl)
	inc	a
	jr	z,fo_3			; free
	inc	hl
	inc	b
	ld	a,b
	cp	(ix+D_SPT)
	jr	c,fo_2
	ld	b,0
	ld	hl,fmtslt
	jr	fo_2
fo_3:	ld	(hl),c
	ld	a,e
	add	a,d
fo_4:	cp	(ix+D_SPT)
	jr	c,fo_5
	sub	(ix+D_SPT)
	jr	fo_4
fo_5:	ld	e,a
	inc	c
	ld	a,c
	cp	(ix+D_SPT)
	jr	c,fo_1
	ret

; The floppy's geometry for fmtk: its fmtab row, or 0 for the drive's
; own kind, found now. Sets the drive's kind, D_SPT, D_HEADS and
; D_SBASE (0 for 17 a track and 9 without PC, else 1), fmtcyl and fmtgap. NZ,
; A = E_NOTRDY if the drive is not there.
fgeom:	ld	hl,(fmtk)
	ld	a,h
	or	l
	jr	nz,gm_r
	call	fdsel			; finds the kind
	ret	nz
	ld	a,(ix+D_KIND)
	cp	2
	jr	nz,gm_8
	ld	hl,fmtab		; 5-inch: 360K
	ld	(fmtk),hl
gm_r:	ld	de,4
	add	hl,de
	ld	a,(hl)			; the connector
	push	hl
	call	fdkind
	pop	hl
	inc	hl
	ld	a,(hl)
	ld	(ix+D_SPT),a
	inc	hl
	ld	a,(hl)
	ld	(ix+D_HEADS),a
	inc	hl
	ld	a,(hl)			; cylinders
	inc	hl
	ld	b,(hl)			; the gap after each sector
	jr	gm_9
gm_8:	ld	(ix+D_SPT),SPT
	ld	(ix+D_HEADS),1
	ld	a,TRACKS
	ld	b,18			; COPIER's
gm_9:	ld	(fmtcyl),a
	ld	a,b
	ld	(fmtgap),a
	ld	(ix+D_TRK),0FFh
	ld	a,(ix+D_SPT)
	sub	SPT			; 0 for 17 a track
	jr	z,gm_b
	add	a,SPT-9			; fmtpc for 9
	ld	a,(fmtpc)
	jr	z,gm_b
	ld	a,1
gm_b:	ld	(ix+D_SBASE),a
	call	fslots
	xor	a
	ret

; The floppy sizes FORMAT takes: the name, the connector (1 8-inch, 2
; 5-inch), sectors a track, sides, cylinders, the gap after a sector,
; then the BPB's sectors a cluster (0Dh) and its bytes 11h to 17h, as
; mkdisk.py makes them. The rest of the BPB is the floppy one's (512
; bytes a sector, RSVD, 2 FATs) and the geometry. A 0 ends it.
FROW	equ	17
fmtab:	db	"360",0,2,9,2,40,80, 2
	dw	112,720
	db	0FDh
	dw	1
	db	"180",0,2,9,1,40,80, 1
	dw	64,360
	db	0FCh
	dw	1
	db	"720",0,2,9,2,80,80, 2
	dw	112,1440
	db	0F9h
	dw	2
	db	"1440",1,18,2,80,84, 1	; 3.5-inch on the 8-inch connector
	dw	224,2880
	db	0F0h
	dw	9
	db	"DS",0,0,1,17,2,77,18, 2	; 8-inch double sided, Lobo's sectors
	dw	256,2618
	db	0F0h
	dw	4
	db	0
fmt_err:	push	af
	call	fmtum
	pop	af
	jp	sherr

; SYS d: the boot code and system of A: onto the FAT volume in d:
csys:	call	memchk
	jr	c,sy_use
	call	mntsh
	call	sysat			; room for it in the reserved sectors,
	ld	hl,SYSSEC		; from where it goes (a track on in a
	add	hl,de			; PC's layout) to the first FAT?
	ex	de,hl
	ld	l,(ix+D_FATSEC)
	ld	h,(ix+D_FATSEC+1)
	or	a
	sbc	hl,de
	jr	nc,sy_1
	call	pmsgsh
	db	0Dh,0Ah,"No room for the system",0Dh,0Ah,0
sy_1:	call	sysget
	jp	nz,sherr
	call	fmtums			; its boot sector: our code, its BPB
	ld	de,0
	ld	hl,fmtbuf
	call	rdsec
	jr	nz,fmt_err
	call	bootcp			; our code around its BPB
	call	syswr
	jr	nz,fmt_err
	call	fmtum
	call	pmsg
	db	0Dh,0Ah,"System on ",0
	call	pdrv
	call	pmsgsh
	db	":",0Dh,0Ah,0
sy_use:	call	pmsgsh
	db	0Dh,0Ah,"SYS d:",0Dh,0Ah,0

; fmtbuf is in the TPA's common part: on to the shell's error if what
; 0006h points at, an RSX or a program kept in memory, is below its end.
; Then on into getdrv.
memchk:	push	hl
	ld	hl,0007h
	call	upeek
	pop	hl
	cp	(fmtbuf+FMTSZ+255)/256
	ld	a,E_NOMEM
	jp	c,sherr
; A = fmtdrv = the drive named at HL, as "B:" or "B". Carry if there
; is none.
getdrv:	call	skipsp
	call	upper
	sub	'A'
	ret	c
	cp	NDRV
	ccf
	ret	c
	ld	c,a
	inc	hl
	ld	a,(hl)
	cp	':'
	jr	nz,gd_1
	inc	hl
	ld	a,(hl)
gd_1:	call	isdelim
	scf
	ret	nz
	ld	a,c
	ld	(fmtdrv),a
	or	a
	ret

; Mount drive A as fdrive, or on to the shell's error
mntsh:	ld	(fdrive),a
	call	mount
	ret	z
	jp	sherr

; Unmount fmtdrv, then select it
fmtums:	call	fmtum
; Select fmtdrv
fmtsel:	ld	a,(fmtdrv)
	jp	seldrv
; Unmount fmtdrv
fmtum:	ld	a,(fmtdrv)
	jp	umount

; Print the letter of fmtdrv
pdrv:	ld	a,(fmtdrv)
	add	a,'A'
	jp	kputc

; Write out and empty the cache, then read
; sector 0 and the SYSSEC system sectors of A: into the TPA at SYSBUF
sysget:	call	flushall
	ret	nz
	call	bclear
	xor	a
	call	seldrv
	ret	nz
	ld	de,0
	ld	hl,SYSBUF
	call	sg_sec
	ret	nz
	call	sysat
	ld	b,SYSSEC
sg_1:	push	bc
	call	sg_sec
	pop	bc
	ret	nz
	inc	de
	djnz	sg_1
	xor	a
	ret
sg_sec:	push	hl			; sector DE to the TPA at HL, HL on
	ld	hl,fmtbuf
	call	rdsec
	pop	hl
	ret	nz
	push	de
	ex	de,hl			; DE = where in the TPA
	ld	hl,fmtbuf
	ld	bc,512
	call	ucopy
	ex	de,hl
	pop	de
	xor	a
	ret

; DE = the first system sector of drive IX: 1, or on a floppy in a PC's
; layout, sectors from 1, its sectors a track + 1. That track's first
; sector, side 1 sector 1, holds the boot sector again: the boot ROM
; reads it when sector 0 is not there
sysat:	ld	de,1
	ld	a,(ix+D_TYPE)
	cp	DT_FLOPPY
	ret	nz
	ld	a,(ix+D_SBASE)
	or	a
	ret	z
	ld	e,(ix+D_SPT)
	inc	e
	ret

; Write fmtbuf as sector 0 of fmtdrv, and again just before the system
; on a PC's layout, then the system from SYSBUF+512
syswr:	call	fmtsel
	ld	de,0
	ld	hl,fmtbuf
	call	wrsec
	ret	nz
	call	sysat
	dec	e
	jr	z,sw_0
	call	wrsec
	ret	nz
sw_0:	call	sysat
	ld	hl,SYSBUF+512
	ld	b,SYSSEC
sw_1:	push	bc
	push	de
	ld	de,fmtbuf
	ld	bc,512
	call	ucopy			; HL moves on
	pop	de
	push	hl
	ld	hl,fmtbuf
	call	wrsec
	pop	hl
	pop	bc
	ret	nz
	inc	de
	djnz	sw_1
	xor	a
	ret

; ------------------------------------------------------------------
; Write all the tracks of the floppy fmtdrv (IX), each side of a
; cylinder in turn. NZ, A = E_ code.
fmttrks: xor	a
	ld	(fmttrk),a
	ld	(fmtsd),a
ft_1:	call	pmsg
	db	0Dh,"Track ",0
	ld	a,(fmttrk)
	ld	l,a
	ld	h,0
	call	pdec
	call	trkbuild
	ld	a,(fmttrk)
	ld	(fdcyl),a
	ld	a,3			; tries
	ld	(fdtries),a
ft_2:	call	fdsel
	ret	nz
	call	fdseek
	ld	hl,fdwdly		; after a seek or a motor start, the
	ld	a,(hl)			; head's 50 ms in all, as fdrw waits
	ld	(hl),0			; before a write
	or	a
	ld	a,35
	call	nz,msdelay
	ld	a,(fmtsd)		; the side, bit 4
	rrca
	rrca
	rrca
	rrca
	or	(ix+D_UNIT)
	or	(ix+D_LATCH)
	ld	(MLATCH),a
	ld	a,(fmttrk)
	cpl
	ld	(FTRACK),a
	ld	hl,USTAT
	ld	de,fmtbuf
	di
	ld	a,0F0h xor 0FFh		; write track
	ld	(FCTRL),a
	call	fd5go			; 5-inch: a disk there?
	ld	a,E_NOTRDY
	jr	nz,ft_to
	ld	bc,(FMTSZ & 0FFh) * 256 + FMTSZ / 256 + 1
ftw:	ld	a,0C0h			; as the sector write loop, B and C
ftw1:	and	(hl)			; counting down fmtbuf
	jp	m,ftw2
	ld	a,(de)
	cpl
	ld	(FDATA),a
	inc	de
	djnz	ftw
	dec	c
	jr	nz,ftw
ftf:	ld	a,0C0h			; past fmtbuf, a 3.5-inch drive's
ftf1:	and	(hl)			; longer track: 4Eh to the index
	jp	m,ftf2
	ld	a,4Eh xor 0FFh
	ld	(FDATA),a
	jp	ftf
ftf2:	jp	pe,ftf
	jr	ftw3
ftw2:	jp	pe,ftw
ftw3:	ei
	ld	a,(FSTAT)
	cpl
	and	0E4h			; not ready, protected, write fault,
					; lost data
	jr	z,ft_3
	bit	7,a
	ld	c,E_NOTRDY
	jr	nz,ft_9
	bit	6,a
	ld	c,E_WRPROT
	jr	nz,ft_9
	ld	hl,fdtries
	dec	(hl)
	jp	nz,ft_2
	ld	c,E_WRITE
ft_9:	call	crlf
	ld	a,c
	or	a
	ret
ft_to:	ei
	ld	c,a
	jr	ft_9
ft_3:	ld	a,(ix+D_HEADS)		; the other side, or the next cylinder
	dec	a
	jr	z,ft_4
	ld	hl,fmtsd
	ld	a,(hl)
	xor	1
	ld	(hl),a
	jp	nz,ft_1
ft_4:	ld	a,(fmttrk)
	inc	a
	ld	(fmttrk),a
	ld	hl,fmtcyl
	cp	(hl)
	jp	c,ft_1
	call	crlf
	xor	a
	ret

; Build track fmttrk in fmtbuf, as Lobo's COPIER does: 20 bytes of
; 4Eh, then for each sector 12 x 00h, 3 x F5h (A1h syncs), the ID
; (FEh, track, side 0, sector, size 2) and its CRC (F7h), 22 x 4Eh,
; 12 x 00h, 3 x F5h, FBh, 512 x E5h, the CRC, 18 x 4Eh. 4Eh to the end.
trkbuild:
	ld	e,0			; slots a cylinder, so that a step and
	ld	a,(ix+D_KIND)		; the settle find its first sector:
	dec	a			; 0 on 5-inch (measured best),
	jr	nz,tk_0			; 3 on 8-inch
	ld	e,3
tk_0:	ld	a,(fmttrk)
	ld	b,a
	xor	a
	inc	b
	jr	tk_3
tk_1:	add	a,e
	cp	(ix+D_SPT)
	jr	c,tk_3
	sub	(ix+D_SPT)
tk_3:	djnz	tk_1
	ld	(fmtrot),a
	ld	hl,fmtbuf
	ld	b,20
	ld	a,4Eh
	call	fill
	ld	c,0
tb_1:	call	syncf
	ld	(hl),0FEh
	inc	hl
	ld	a,(fmttrk)
	ld	(hl),a
	inc	hl
	ld	a,(fmtsd)
	ld	(hl),a
	inc	hl
	ld	a,(fmtrot)		; the slot in this track's turn
	ld	b,a
	ld	a,c
	sub	b
	jr	nc,tb_r
	add	a,(ix+D_SPT)
tb_r:	push	hl			; the sector in that slot, fslots'
	ld	hl,fmtslt
	add	a,l
	ld	l,a
	ld	a,(hl)
	pop	hl
	add	a,(ix+D_SBASE)
	ld	(hl),a
	inc	hl
	ld	(hl),2
	inc	hl
	ld	(hl),0F7h
	inc	hl
	ld	b,22
	ld	a,4Eh
	call	fill
	call	syncf
	ld	(hl),0FBh
	inc	hl
	ld	b,0
	ld	a,0E5h
	call	fill
	call	fill
	ld	(hl),0F7h
	inc	hl
	ld	a,(fmtgap)
	ld	b,a
	ld	a,4Eh
	call	fill
	inc	c
	ld	a,c
	cp	(ix+D_SPT)
	jr	c,tb_1
	ex	de,hl			; 4Eh to the end of the buffer
	ld	hl,fmtbuf+FMTSZ
	or	a
	sbc	hl,de
	ld	b,h
	ld	c,l
	ex	de,hl
	ld	(hl),4Eh
	ld	d,h
	ld	e,l
	inc	de
	dec	bc
	ldir
	ret

; 12 x 00h, 3 x F5h (A1h syncs) at HL
syncf:	ld	b,12
	xor	a
	call	fill
	ld	b,3
	ld	a,0F5h
	; fall into fill

; B bytes of A at HL (0 is 256)
fill:	ld	(hl),a
	inc	hl
	djnz	fill
	ret

; ------------------------------------------------------------------
; HL = the hard disk volume's sectors, MB * 2048, 65504 at most:
; whole tracks of 32 sectors, which mtools checks
hdsize:	ld	a,(fmtmb)
	ld	h,a
	ld	l,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ret	nc
	ld	hl,0FFE0h
	ret

; The boot sector from SYSBUF into fmtbuf, the BPB for the hard disk
; of fmtmb megabytes over it, as mkdisk.py --hd makes it: 512 root
; entries, 2K clusters up to 16 MB and 4K above, FAT16 from 4085
; clusters, and the fewest FAT sectors that hold them.
hdbpb:	call	fbpbcp			; the floppy one to start from
	call	hdsize
	ld	(fmtbuf+13h),hl
	ld	a,(fmtmb)		; sectors a cluster
	cp	17
	ld	a,4
	jr	c,hb_2
	ld	a,8
hb_2:	ld	(fmtbuf+0Dh),a
	ld	hl,512
	ld	(fmtbuf+11h),hl
	ld	a,0F8h
	ld	(fmtbuf+15h),a
	ld	hl,32
	ld	(fmtbuf+18h),hl
	ld	a,80h
	ld	(fmtbuf+24h),a
	ld	hl,1			; spf: up from 1 until the FAT holds
hb_3:	ld	(fmtbuf+16h),hl		; the clusters
	ld	de,(fmtbuf+13h)		; data = total - rsvd - 2 * spf - 32
	ex	de,hl
	or	a
	sbc	hl,de
	sbc	hl,de
	ld	de,RSVD+32
	sbc	hl,de
	ld	a,(fmtbuf+0Dh)		; clusters = data / spc
hb_4:	srl	a
	jr	c,hb_5
	srl	h
	rr	l
	jr	hb_4
hb_5:	ld	(fmtcl),hl
	inc	hl			; FAT bytes: (clusters + 2) * 2 for
	inc	hl			; FAT16, * 3 / 2 + 1 for FAT12
	ld	de,4085-1+2
	ex	de,hl
	or	a
	sbc	hl,de
	ex	de,hl
	jr	nc,hb_12
	add	hl,hl			; FAT16
	ld	a,1
	jr	hb_6
hb_12:	ld	d,h
	ld	e,l
	srl	d
	rr	e
	add	hl,de
	inc	hl
	xor	a
hb_6:	ld	(fmtf16),a
	ld	de,(fmtbuf+16h)		; spf * 512 >= that?
	ex	de,hl
	add	hl,hl
	ld	h,l
	ld	l,0
	or	a
	sbc	hl,de
	jr	nc,hb_7
	ld	hl,(fmtbuf+16h)
	inc	hl
	jr	hb_3
hb_7:	ld	a,(fmtf16)		; FAT16: "FAT16" over the floppy
	or	a			; BPB's "FAT12"
	ret	z
	ld	a,'6'
	ld	(fmtbuf+36h+4),a
	ret

; Our boot sector from SYSBUF into fmtbuf, all but the BPB there, 0Bh
; to 3Dh
bootcp:	ld	hl,SYSBUF
	ld	de,fmtbuf
	ld	bc,0Bh
	call	ucopy
	ld	hl,SYSBUF+3Eh
	ld	de,fmtbuf+3Eh
	ld	bc,512-3Eh
	jp	ucopy

; Write the volume on fmtdrv: the boot sector, in fmtbuf with its BPB
; at 0Bh, our code from SYSBUF around it, the system, the FATs empty
; and the root directory empty. NZ, A = E_ code.
fmtvol:	call	bootcp
	ld	a,(fmtbuf+15h)		; the media byte, for the FATs
	ld	(fmtmed),a
	ld	hl,(fmtbuf+16h)		; and the sizes
	ld	(fmtspf),hl
	ld	a,(fmtbuf+36h+4)	; "FAT16" or "FAT12"
	sub	'2'
	ld	(fmtf16),a		; 4 for FAT16, 0 for FAT12
	ld	hl,(fmtbuf+11h)		; root sectors: entries / 16
	ld	b,4
	call	shrb
	ld	(fmtroot),hl
	call	syswr
	ret	nz
	ld	hl,fmtbuf		; then zeros: FATs and the root
	ld	bc,511
	call	zfill
	ld	de,RSVD
	ld	b,2			; two FATs
fv_1:	push	bc
	ld	a,(fmtmed)		; the first sector: media, then end
	ld	(fmtbuf),a		; of chain for cluster 1
	ld	a,0FFh
	ld	(fmtbuf+1),a
	ld	(fmtbuf+2),a
	ld	a,(fmtf16)
	or	a
	ld	a,0FFh
	jr	nz,fv_2
	xor	a
fv_2:	ld	(fmtbuf+3),a
	ld	hl,(fmtspf)
fv_3:	push	hl
	ld	hl,fmtbuf
	call	wrsec			; keeps BC, DE, HL
	ld	b,4			; the rest are zeros (B is pushed)
fv_z:	ld	(hl),0			; flags kept
	inc	hl
	djnz	fv_z
	pop	hl
	jr	nz,fv_9
	inc	de
	dec	hl
	ld	a,h
	or	l
	jr	nz,fv_3
	pop	bc
	djnz	fv_1
	ld	a,(fmtroot)		; the root, after the FATs
	ld	b,a
fv_4:	ld	hl,fmtbuf
	call	wrsec
	ret	nz
	inc	de
	djnz	fv_4
	xor	a
	ret
fv_9:	pop	bc
	ret

; The floppy BPB into fmtbuf's boot sector
fbpbcp:	ld	hl,fbpb
	ld	de,fmtbuf+0Bh
	ld	bc,3Eh-0Bh
	ldir
	ret

; The floppy BPB, the same bytes as in the boot sector
fbpb:	FLOPPYBPB
