; xcpmz80 block layer. Runs in A2. Logical drives A: to C: are a
; floppy drive or the SASI disk. Each is read and written in 512-byte
; sectors by a 16-bit LBA, through a cache of four buffers. The FDC
; driver follows Lobo's XFDC.MAC and the SASI driver Lobo's XWINI.MAC,
; as behavior; the code is our own.

NDRV		equ	3		; A: B: C:
DT_NONE		equ	0
DT_FLOPPY	equ	1
DT_SASI		equ	2

; The drive table, one DSZ-byte entry per drive, addressed by IX
D_TYPE		equ	0		; DT_ above
D_UNIT		equ	1		; floppy: MLATCH select bit. SASI: LUN << 5
D_MNT		equ	2		; 1 when the FAT is mounted
D_FAT16		equ	3		; 1 FAT16, 0 FAT12
D_SPC		equ	4		; sectors per cluster
D_SPCSH		equ	5		; log2 of it
D_FATSEC	equ	6		; first FAT sector, 2 bytes
D_SPF		equ	8		; sectors per FAT, 2
D_NFATS		equ	10
D_ROOTSEC	equ	11		; first root directory sector, 2
D_ROOTENT	equ	13		; root entries, 2
D_DATASEC	equ	15		; sector of cluster 2, 2
D_MAXCL		equ	17		; highest cluster number, 2
D_TOTAL		equ	19		; sectors, 2
D_SPT		equ	21		; floppy sectors per track
D_HEADS		equ	22		; floppy heads
D_HINT		equ	23		; where to look for a free cluster, 2
D_RO		equ	25		; 1 read only
D_TRK		equ	26		; floppy: the cylinder the head is on, FFh not known
D_ROOTSECS	equ	27		; root directory sectors
D_KIND		equ	28		; floppy: 0 not known, 1 8-inch, 2 5-inch
D_LATCH		equ	29		; MLATCH for it: 60h 8-inch, 40h 5-inch
D_SBASE		equ	30		; the first sector number, 0 or 1
D_RATE		equ	31		; the step rate bits
DSZ		equ	32

; Disk errors, in A with NZ. 1 to 4 are CP/M 3's codes, which a program
; gets in H in the return error modes. The others are given as 1.
E_READ		equ	1		; Disk I/O
E_WRPROT	equ	2		; Read/Only (the disk)
E_ROFILE	equ	3		; Read/Only File
E_BADDRV	equ	4		; Invalid Drive: no such device
E_FULL		equ	5		; Disk Full
E_NOTRDY	equ	6		; Not Ready: no disk in the drive
E_WRITE		equ	7		; Disk I/O, on a write
E_NOPATH	equ	8		; folders: No folder
E_EXISTS	equ	9		; Exists
E_NOTEMPTY	equ	10		; Not empty
E_BADNAME	equ	11		; Bad name
E_LONG		equ	12		; Path too long
E_INUSE		equ	13		; In use, the current folder
E_NOMEM		equ	14		; No memory, for FORMAT's track

; Point IX at drive A's table entry (A = 0, 1, 2). Keeps the others.
drvix:	push	de
	rrca				; A * DSZ, A < 8
	rrca
	rrca
	ld	e,a
	ld	d,0
	ld	ix,drvtab
	add	ix,de
	pop	de
	ret
	assert	DSZ == 32

; Fill the drive table from the boot device, in BOOTDEV: 0 an 8-inch
; floppy, 2 a 5-inch one, 1 SASI. The boot device is A:, the other floppy
; and the hard disk follow. A floppy's kind is found when it is first
; used, but for the boot floppy's.
diskinit:
	ld	hl,drvtab
	ld	de,drvtab+1
	ld	bc,NDRV*DSZ-1
	ld	(hl),0
	ldir
	call	bclear
	ld	a,(BOOTDEV)
	cp	1
	push	af
	ld	hl,dt_sasi
	jr	z,di2
	inc	hl			; dt_flop
	inc	hl
di2:	ld	de,drvtab
	ld	a,NDRV
di3:	ldi				; D_TYPE
	ldi				; D_UNIT
	ex	de,hl
	ld	bc,D_TRK-2
	add	hl,bc
	ld	(hl),0FFh
	ld	c,DSZ-D_TRK
	add	hl,bc
	ex	de,hl
	dec	a
	jr	nz,di3
	pop	af			; the boot floppy's kind
	ret	z
	srl	a
	inc	a
	ld	ix,drvtab
	jp	fdkind

dt_sasi: db	DT_SASI,0
dt_flop: db	DT_FLOPPY,1, DT_FLOPPY,2, DT_SASI,0

; ------------------------------------------------------------------
; Raw sector I/O. IX = drive, DE = LBA, HL = 512-byte buffer.
; Z on success, else NZ and A = E_ code. Keep BC, DE, HL.
rdsec:	xor	a
	jr	rw0
wrsec:	ld	a,1
rw0:	ld	(rwflag),a
	ld	a,(ix+D_TYPE)
	dec	a			; DT_FLOPPY
	jr	z,fdrw
	dec	a			; DT_SASI
	jp	z,sasrw
	ld	a,E_BADDRV
	or	a
	ret

; ------------------------------------------------------------------
; Floppy: double density, 512-byte sectors, numbered from 0 on 8-inch
; disks and from 1 on 5-inch ones, as a PC's. One or two heads, the
; sides alternating by cylinder, as FAT counts.
FD_LATCH	equ	60h		; MLATCH: double density, 8-inch
FD_RATE		equ	2		; 10 ms steps, Lobo's slow 8-inch rate
FD5_LATCH	equ	40h		; double density, 5-inch
FD5_RATE	equ	0		; 6 ms steps, for any drive but the oldest
FD5_SLOW	equ	3		; 30 ms, the boot ROM's: DIP switch 1 up

fdrw:	push	bc
	push	de
	push	hl
	ld	a,(ix+D_SPT)		; track = LBA / SPT, sector = remainder
	or	a
	jr	nz,fd0
	ld	a,SPT			; not mounted yet: the boot disk format
fd0:	ld	c,a
	ex	de,hl
	call	div16x8			; HL = track, A = sector
	ld	(fdsec),a
	ld	a,(ix+D_HEADS)
	cp	2
	ld	a,0			; side
	jr	nz,fd1
	srl	h
	rr	l
	rla
fd1:	ld	h,a
	ld	(fdcyl),hl		; and fdside
	ld	a,10			; tries
	ld	(fdtries),a
fdretry: call	fdsel
	jp	nz,fdfail
	call	fdseek
	ld	hl,fdwdly		; a write after a seek or a motor start:
	ld	a,(hl)			; 50 ms in all as Lobo's CHKDLY, a read
	ld	(hl),0			; none
	or	a
	jr	z,fdw0
	ld	a,(rwflag)
	or	a
	ld	a,35
	call	nz,msdelay
fdw0:	ld	a,(fdside)		; side, then the sector
	call	fdmlat
	ld	a,(fdcyl)
	cpl
	ld	(FTRACK),a
	ld	a,(fdsec)
	add	a,(ix+D_SBASE)
	cpl
	ld	(FSECTOR),a
	ld	a,(rwflag)		; 82h read, A2h write; bit 3 the side
	add	a,a			; to compare, as Lobo's
	add	a,a
	ld	b,a
	ld	a,(fdside)
	or	b
	add	a,a
	add	a,a
	add	a,a
	or	82h
	ld	hl,USTAT
	pop	de			; the buffer
	push	de
	ld	bc,FDATA
	exx				; f5rl and f5wl's count, about 1.6 s
	push	bc
	push	de
	ld	bc,0
	ld	e,2
	exx
	push	af			; off for the transfer, and after it
	call	iffget			; as they were: the BDOS keeps them
	ld	(fdiff),a		; off for some programs
	pop	af
	cpl
	ld	(FCTRL),a
	bit	1,(ix+D_KIND)		; 5-inch: no READY, so count the wait
	ld	a,(rwflag)
	jr	nz,f5go
	or	a
	jr	nz,fdwl
	; Read: as Lobo's loop, DRQ- and INTRQ- polled at USTAT
fdrl:	ld	a,(hl)			; DRQ- to carry, INTRQ- to sign
	add	a,a
	jr	c,fdr2
fdr1:	ld	a,(bc)
	cpl
	ld	(de),a
	inc	de
	jp	fdrl
fdr2:	jp	m,fdrl			; both still high: wait
	jr	fdend
fdwl:	ld	a,(hl)
	add	a,a
	jr	c,fdw2
fdw1:	ld	a,(de)
	cpl
	ld	(bc),a
	inc	de
	jp	fdwl
fdw2:	jp	m,fdwl
fdend:	exx
	pop	de
	pop	bc
	exx
	ld	a,(fdiff)
	or	a
	jr	z,fde_1
	ei
fde_1:
	ld	a,(FSTAT)
	cpl
	ld	c,a
	ld	a,(rwflag)
	or	a
	ld	a,9Ch			; read: not ready, RNF, CRC, lost data
	jr	z,fd5
	ld	a,0FCh			; write: also protect and fault
fd5:	and	c
	jr	z,fdfail		; done, A = 0
	ld	c,E_NOTRDY
	rla
	jr	c,fdfail1
	ld	c,E_WRPROT
	rla
	jr	c,fdfail1
	bit	6,a			; record not found: find the track again
	jr	z,fd7
	ld	(ix+D_TRK),0FFh
fd7:	ld	hl,fdtries
	dec	(hl)
	jp	nz,fdretry
rwerr:	ld	a,(rwflag)		; out of tries: Disk I/O
	or	a
	ld	a,E_READ
	jr	z,fdfail
	ld	a,E_WRITE
	jr	fdfail

; 5-inch, which has no READY: wait for the first DRQ or INTRQ, or for a
; disk that is not there, longer than the FDC takes to give up on a sector
; (5 turns). The first byte is taken from here, with no second look at
; USTAT: a DRQ has 27 us on a read and 23 us on a write at 1 MHz (Appendix
; D p.14-15), and this takes 19 us at worst.
f5go:	or	a
	jr	nz,f5wl
f5rl:	ld	a,(hl)
	add	a,a
	jr	nc,fdr1
	jp	p,fdend
	exx
	dec	bc
	ld	a,b
	or	c
	exx
	jr	nz,f5rl
	exx
	dec	e
	exx
	jr	nz,f5rl
	jr	f5to
f5wl:	ld	a,(hl)
	add	a,a
	jr	nc,fdw1
	jp	p,fdend
	exx
	dec	bc
	ld	a,b
	or	c
	exx
	jr	nz,f5wl
	exx
	dec	e
	exx
	jr	nz,f5wl
f5to:	ld	a,0D0h xor 0FFh		; nothing: stop the FDC
	ld	(FCTRL),a
	exx
	pop	de
	pop	bc
	exx
	ld	a,(fdiff)
	or	a
	jr	z,fdto
	ei
fdto:	ld	(ix+D_TRK),0FFh		; no disk: Not Ready
	ld	c,E_NOTRDY
fdfail1: ld	a,c
fdfail:	or	a
	pop	hl
	pop	de
	pop	bc
	ret

; Select the drive and stop the FDC. 8-inch: wait up to half a second for
; READY, as Lobo's SELECT. 5-inch, with no READY: wait 0.75 s for the
; motor if it had stopped, as Lobo's BIOS. A drive not used before is
; found first. NZ, A = E_NOTRDY if it is not there.
fdsel:	ld	a,(ix+D_KIND)
	or	a
	jr	z,fdfind
	ld	a,(SYSFLG)		; the 5-inch motors turning
	and	20h
	ld	c,a
	xor	a
	call	fdmlat0
	ld	b,a			; a new drive: load its head with a seek
	ld	hl,fdlast		; to where it is, as Lobo's SELECT
	sub	(hl)
	ld	(hl),b
	ld	(fdload),a		; not 0 for a new drive
	ld	a,0D0h xor 0FFh		; force interrupt
	ld	(FCTRL),a
	call	fdwait
	ld	a,(ix+D_KIND)
	cp	2
	jr	nz,fs8
	ld	a,c			; 5-inch: the motor turning?
	or	a
	jr	nz,fs6
	ld	a,1
	ld	(fdwdly),a
	ld	b,3
fs5:	ld	a,250
	call	msdelay
	djnz	fs5
fs6:	xor	a
	ret
fs8:	ld	b,50
fs2:	ld	a,(FSTAT)		; READY is bit 7, low when ready
	cpl				; once complemented
	bit	7,a
	ret	z
	ld	a,10
	call	msdelay
	djnz	fs2
fdnr:	ld	a,E_NOTRDY
	or	a
	ret

; Drive IX's select bits and latch, with side A (0 or 1) in bit 4, into
; MLATCH. A = what was written.
fdmlat:	rrca
	rrca
	rrca
	rrca
fdmlat0: or	(ix+D_UNIT)
	or	(ix+D_LATCH)
	ld	(MLATCH),a
	ret

; Find drive IX's kind: 8-inch if it shows READY there, else 5-inch if
; index pulses come there within 0.4 s. Z if found, else NZ, A =
; E_NOTRDY, and the kind is still not known.
fdfind:	ld	a,1
	call	fdkind
	call	fdsel
	ret	z
	ld	a,2
	call	fdkind
	call	fdsel
	ld	bc,38720		; about 0.4 s, two turns
ff1:	ld	a,(FSTAT)		; type I status: bit 1 the index, low
	and	02h			; when there
	jr	z,fs6
	dec	bc
	ld	a,b
	or	c
	jr	nz,ff1
	ld	(ix+D_KIND),0
	jr	fdnr

; Set drive IX's kind to A, 1 8-inch or 2 5-inch, and its latch, first
; sector and step rate with it. A 5-inch drive steps in 6 ms, or in 30
; with DIP switch 1 up, for the oldest drives.
fdkind:	ld	(ix+D_KIND),a
	dec	a			; 0 8-inch, 1 5-inch
	ld	(ix+D_SBASE),a
	ld	(ix+D_LATCH),FD_LATCH
	ld	(ix+D_RATE),FD_RATE
	ret	z
	ld	(ix+D_LATCH),FD5_LATCH
	ld	(ix+D_RATE),FD5_RATE
	ld	a,(DIPSW)		; switch 1 is bit 7, set when up
	add	a,a
	ret	nc
	ld	(ix+D_RATE),FD5_SLOW
	ret

; After write track, with HL = USTAT: on a 5-inch drive, which has no
; READY, wait for the first DRQ or INTRQ, or about 1.4 s for a disk that
; is not there. Z when it came, else NZ with the FDC stopped. Write track
; has until the index pulse to answer its first DRQ. A sector does not
; (f5go).
fd5go:	bit	1,(ix+D_KIND)		; 8-inch: on at once, Z
	ret	z
	exx
	push	bc
	push	de
	ld	bc,0
	ld	e,2			; 2 x 65536 rounds of 55 cycles
f5g1:	exx
	ld	a,(hl)			; DRQ- and INTRQ-
	and	0C0h
	cp	0C0h
	exx
	jr	nz,f5g2
	dec	bc
	ld	a,b
	or	c
	jr	nz,f5g1
	dec	e
	jr	nz,f5g1
	ld	a,0D0h xor 0FFh		; nothing: stop the FDC
	ld	(FCTRL),a
	or	a			; NZ
	jr	f5g3
f5g2:	xor	a
f5g3:	pop	de
	pop	bc
	exx
	ret

; Put the head on fdcyl. Restore first if we do not know where it is.
fdseek:	ld	a,(ix+D_TRK)
	cp	0FFh
	jr	nz,fk1
	ld	a,(ix+D_RATE)		; restore
	or	08h
	call	fdcmd1
	ld	a,1
	ld	(fdwdly),a
	xor	a
	ld	(ix+D_TRK),a
fk1:	ld	b,a
	cpl
	ld	(FTRACK),a
	ld	a,(fdload)
	or	a
	ld	a,(fdcyl)
	jr	nz,fk2
	cp	b
	ret	z
fk2:	ld	(ix+D_TRK),a
	cpl
	ld	(FDATA),a
	ld	a,1
	ld	(fdwdly),a
	ld	a,(ix+D_RATE)		; seek, head loaded
	or	18h
	call	fdcmd1
	ld	a,15			; head settle
	; fall into msdelay

; Wait A ms (5.07 MHz: 1 ms is about 5070 cycles, 21 a pass)
msdelay: push	bc
md1:	ld	b,240
md2:	nop
	nop
	djnz	md2
	dec	a
	jr	nz,md1
	pop	bc
	ret

; Give a type I command in A and wait for the FDC to finish
fdcmd1:	cpl
	ld	(FCTRL),a
	call	fdwait
fc1:	ld	a,(FSTAT)		; BUSY, bit 0, is low once complemented
	rra
	jr	nc,fc1
	ret

; About 100 us, for the FDC to take a command
fdwait:	push	bc
	ld	b,40
fw1:	djnz	fw1
	pop	bc
	ret

; ------------------------------------------------------------------
; SASI: one 512-byte block a command, LBA in DE (blocks above 65535 are
; not used). Three tries, as the controller retries itself.
sasrw:	push	bc
	push	de
	push	hl
	ld	a,3
	ld	(fdtries),a
sr0:	call	sassel
	jr	nz,srnr
	ld	a,(rwflag)		; 08h read, 0Ah write
	add	a,a
	add	a,8
	call	sasout
	ld	a,(ix+D_UNIT)		; LUN, block bits 20-16
	call	sasout
	ld	a,d
	call	sasout
	ld	a,e
	call	sasout
	ld	a,1			; one block
	call	sasout
	xor	a			; control
	call	sasout
	pop	hl			; the buffer
	push	hl
	ld	bc,2			; 2 x 256 bytes
	ld	a,(rwflag)
	or	a
	jr	nz,srw
srr:	call	sasreq			; data in, until a control byte
	jr	nz,srst
	ld	a,(UDATAHS)
	ld	(hl),a
	inc	hl
	djnz	srr
	dec	c
	jr	nz,srr
	jr	srst0
srw:	call	sasreq
	jr	nz,srst
	ld	a,(hl)
	ld	(UDATAHS),a
	inc	hl
	djnz	srw
	dec	c
	jr	nz,srw
srst0:	call	sasreq			; the status byte
srst:	ld	a,(UDATA)
	ld	b,a
	call	sasack
	call	sasreq			; the message byte
	ld	a,(UDATA)
	call	sasack
sr1:	ld	a,(USTAT)		; wait for the bus to go free
	and	04h
	jr	nz,sr1
	ld	a,b
	or	a
	jp	z,fdfail		; good, A = 0
	ld	hl,fdtries
	dec	(hl)
	jr	nz,sr0
	jp	rwerr			; Disk I/O
srnr:	ld	a,E_BADDRV		; nothing answers the select
	jp	fdfail

; Select the controller, as Lobo's SETUP: reset it if busy, then put out
; the ID bit and SEL and wait for BSY. NZ if it never answers.
sassel:	ld	a,(USTAT)
	and	04h
	jr	z,sas_2
	ld	a,04h			; reset
	ld	(UCTRL),a
	ld	a,10
sas_1:	dec	a
	jr	nz,sas_1
	ld	(UCTRL),a
	jr	sassel
sas_2:	ld	bc,0
	inc	a
	ld	(UDATA),a		; ID 0
	inc	a
	ld	(UCTRL),a		; SEL
sas_3:	ld	a,(USTAT)
	and	04h
	jr	nz,sas_4
	dec	bc
	ld	a,b
	or	c
	jr	nz,sas_3
	ld	(UCTRL),a
	inc	a
	ret
sas_4:	xor	a
	ld	(UCTRL),a
	ret

; Wait for REQ. Z when it asks for data, NZ when for a control byte.
sasreq:	ld	a,(USTAT)
	rrca
	jr	nc,sasreq
	ld	a,(USTAT)
	and	10h
	ret

; Send A in the command phase, by hand as Lobo's TWOWAY
sasout:	push	af
	call	sasreq
	pop	af
	ld	(UDATA),a
	; fall into sasack

; ACK, wait for REQ to drop, release ACK. A = 0.
sasack:	ld	a,1
	ld	(UCTRL),a
sa1:	ld	a,(USTAT)
	rrca
	jr	c,sa1
	xor	a
	ld	(UCTRL),a
	ret

; ------------------------------------------------------------------
; HL = HL / C, A = remainder. C not 0.
div16x8: xor	a
	ld	b,16
dv1:	add	hl,hl
	rla
	jr	c,dv2
	cp	c
	jr	c,dv3
dv2:	sub	c
	inc	l
dv3:	djnz	dv1
	ret

; ------------------------------------------------------------------
; The cache. Four 512-byte buffers, write back, least recently used
; first out. A header is drive (FFh empty), LBA, dirty, age.
NBUF		equ	4
BH_DRV		equ	0
BH_LBA		equ	1
BH_DIRTY	equ	3
BH_AGE		equ	4
BHSZ		equ	5

; Get sector DE of drive IX into the cache. HL = its data, IY = its
; header. Z on success, else NZ and A = error. Keeps DE.
; newsec is the same, but the sector will be overwritten whole: no read.
newsec:	push	bc
	ld	c,1
	jr	gs0
getsec:	push	bc
	ld	c,0
gs0:	call	bfind
	jr	z,gs3			; there already
	push	bc			; C = 1: no read
	call	bvictim			; IY = the oldest, written out
	pop	bc
	jr	nz,gs4
	ld	a,(drvnum)
	ld	(iy+BH_DRV),a
	ld	(iy+BH_LBA),e
	ld	(iy+BH_LBA+1),d
	ld	(iy+BH_DIRTY),0
	dec	c
	jr	z,gs3			; newsec
	call	bdata
	call	rdsec
	jr	z,gs3
	ld	(iy+BH_DRV),0FFh
	jr	gs4
gs3:	call	btouch
	call	bdata
	xor	a
gs4:	pop	bc
	ret

; Mark the buffer at IY dirty
bdirty:	ld	(iy+BH_DIRTY),1
	ret

; IY = the header holding (drvnum, DE), Z if found. Uses HL.
bfind:	ld	hl,bufhdr
	ld	b,NBUF
bf1:	ld	a,(drvnum)
	cp	(hl)			; BH_DRV
	inc	hl
	jr	nz,bf2
	ld	a,e
	cp	(hl)			; BH_LBA
	jr	nz,bf2
	inc	hl
	ld	a,d
	cp	(hl)
	dec	hl
	jr	z,bf3
bf2:	inc	hl			; HL = header + 1 here
	inc	hl
	inc	hl
	inc	hl
	djnz	bf1
	or	1
	ret
bf3:	dec	hl
	push	hl
	pop	iy
	ret
	assert	BHSZ == 5 && BH_LBA == 1

; Make IY the newest: age every other used buffer. Keeps DE.
btouch:	push	de
	ld	hl,bufhdr+BH_AGE
	ld	b,NBUF
	ld	de,BHSZ
bt1:	ld	a,(hl)
	inc	a
	jr	z,bt2
	ld	(hl),a
bt2:	add	hl,de
	djnz	bt1
	pop	de
	ld	(iy+BH_AGE),0
	ret

; HL = data of the buffer at IY. Keeps DE.
bdata:	push	iy
	pop	hl
	ld	a,l
	sub	low bufhdr		; header offset = 5 * n
	ld	hl,bufdat-512
bd1:	inc	h			; + 512
	inc	h
	sub	BHSZ
	jr	nc,bd1
	ret
	assert	NBUF*BHSZ < 256

; IY = an empty buffer, or the oldest one, written out first
bvictim: push	de
	ld	iy,bufhdr
	push	iy
	pop	hl			; HL = best so far
	ld	c,0			; its age
	ld	b,NBUF
	ld	de,BHSZ
bv1:	ld	a,(iy+BH_DRV)
	inc	a
	jr	z,bv3
	ld	a,(iy+BH_AGE)
	cp	c
	jr	c,bv2
	ld	c,a
	push	iy
	pop	hl
bv2:	add	iy,de
	djnz	bv1
	push	hl
	pop	iy
bv3:	pop	de
	; fall into bflush1

; Write out the buffer at IY if dirty. A sector of the first FAT goes to
; the other FATs too. Z on success. Keeps IY.
bflush1: ld	a,(iy+BH_DIRTY)
	or	a
	ret	z
	push	bc
	push	de
	push	hl
	push	ix
	ld	a,(iy+BH_DRV)
	call	drvix
	ld	e,(iy+BH_LBA)
	ld	d,(iy+BH_LBA+1)
	call	bdata
	call	wrsec			; DE = LBA, HL = data
	jr	nz,bfl3
	push	hl			; a sector of the first FAT?
	ex	de,hl
	ld	e,(ix+D_FATSEC)
	ld	d,(ix+D_FATSEC+1)
	or	a
	sbc	hl,de			; LBA - FATSEC
	ld	c,(ix+D_SPF)		; BC = SPF
	ld	b,(ix+D_SPF+1)
	or	a
	sbc	hl,bc			; carry if below SPF
	pop	hl
	jr	nc,bfl2
	ld	e,(iy+BH_LBA)		; DE = the LBA again
	ld	d,(iy+BH_LBA+1)
	ld	a,(ix+D_NFATS)
bfl1:	dec	a			; the same sector in each other FAT
	jr	z,bfl2
	ex	de,hl
	add	hl,bc
	ex	de,hl
	push	af
	call	wrsec
	jr	nz,bfl5
	pop	af
	jr	bfl1
bfl2:	ld	(iy+BH_DIRTY),0
	xor	a
	jr	bfl4
bfl5:	pop	de			; drop the count, DE comes back below
bfl3:	push	af			; the write failed: what this drive's
	ld	a,(iy+BH_DRV)		; buffers hold can not reach the disk,
	inc	a			; on a write-protected one nothing
	ld	(wbdrv),a		; did. Forget them and the mount, so
	dec	a			; the error names this drive, not the
	call	bdrop			; one the call was for
	pop	af
bfl4:	pop	ix			; the disk is read again as it is
	pop	hl
	pop	de
	pop	bc
	ret

; Drop the buffers of drive A, written or not, and its mount (IX)
bdrop:	ld	(ix+D_MNT),0
	ld	c,a
	ld	hl,bufhdr
	ld	b,NBUF
bd_1:	ld	a,(hl)
	cp	c
	jr	nz,bd_2
	ld	(hl),0FFh		; BH_DRV
	push	hl
	inc	hl
	inc	hl
	inc	hl
	ld	(hl),0			; BH_DIRTY
	pop	hl
bd_2:	ld	de,BHSZ
	add	hl,de
	djnz	bd_1
	ret

; Write out every dirty buffer. Z if all went.
flushall: ld	iy,bufhdr
	ld	b,NBUF
	ld	de,BHSZ
fa1:	call	bflush1			; keeps BC and DE
	ret	nz
	add	iy,de			; leaves Z, and A = 0
	djnz	fa1
	ret

; Every buffer empty, what they held forgotten
bclear:	ld	hl,bufhdr
	ld	b,NBUF
bc1:	ld	(hl),0FFh
	ld	de,BHSZ
	add	hl,de
	djnz	bc1
	ret

; Forget the buffers of drive A, after writing them out
bforget: ld	c,a
	ld	iy,bufhdr
	ld	b,NBUF
bg1:	ld	a,(iy+BH_DRV)
	cp	c
	jr	nz,bg2
	call	bflush1			; keeps BC
	ld	(iy+BH_DRV),0FFh
bg2:	ld	de,BHSZ
	add	iy,de
	djnz	bg1
	ret
