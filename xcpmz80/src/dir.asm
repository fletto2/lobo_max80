; xcpmz80 folders. Runs in A2. A folder is a FAT subdirectory: a
; cluster chain of 32-byte entries, with "." and ".." first. Each drive
; has a current folder, its first cluster in cwdcl (0 the root) and its
; path in cwdpth, as GAMES\INFOCOM. mount puts the drive's current
; folder in dircl, the folder the directory calls work in.

; HL = drive A's path
pthptr:	ld	hl,cwdpth
	ld	de,CWDLEN
	jr	dvoff
; HL = where drive A's current folder's cluster is
cwdptr:	ld	hl,cwdcl
	ld	de,2
dvoff:	or	a
	ret	z
	add	hl,de
	dec	a
	jr	dvoff

; dircl = the current folder of drive drvnum, the root when rootf is
; set, or dirov for drive dirovd, a path's. Keeps HL and DE. Z, A = 0.
setdir:	push	hl
	push	de
	ld	hl,0
	ld	a,(rootf)
	or	a
	jr	nz,sdr_1
	ld	hl,(dirov)
	ld	a,(dirovd)
	ld	e,a
	ld	a,(drvnum)
	cp	e
	jr	z,sdr_1
	call	cwdptr
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
sdr_1:	ld	(dircl),hl
	pop	de
	pop	hl
	xor	a
	ret

; After a drive is mounted: if its current folder is not a folder on
; this disk, which may have been changed, back to the root. Its first
; entry must be "." with the folder's own cluster, and the folder above
; must name it as its path ends: two disks made alike can have another
; folder at the same cluster. Leaves spat and dpos changed.
cwdchk:	ld	a,(drvnum)
	call	cwdptr
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	a,d
	or	e
	jr	z,cc_ok
	ex	de,hl
	call	fateoc
	jr	c,cc_bad
	push	hl
	call	clsec
	call	getsec
	pop	de
	jr	nz,cc_bad
	ld	a,(hl)
	cp	'.'
	jr	nz,cc_bad
	inc	hl
	ld	a,(hl)
	cp	' '
	jr	nz,cc_bad
	ld	bc,DE_CLUS-1
	add	hl,bc
	ld	a,(hl)
	cp	e
	jr	nz,cc_bad
	inc	hl
	ld	a,(hl)
	cp	d
	jr	nz,cc_bad
	ld	bc,31			; the folder above, from ".."
	add	hl,bc
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	(dircl),hl
	push	de
	ld	a,(drvnum)
	call	pthptr
	ld	d,h			; DE = its last part
	ld	e,l
cc_1:	ld	a,(hl)
	inc	hl
	or	a
	jr	z,cc_2
	cp	5Ch
	jr	nz,cc_1
	ld	d,h
	ld	e,l
	jr	cc_1
cc_2:	ex	de,hl
	call	pcomp
	call	z,wpfind		; HL = the cluster that name has
	pop	de
	jr	nz,cc_bad
	or	a
	sbc	hl,de
	jr	z,cc_ok
cc_bad:	pop	hl
	ld	a,(drvnum)
; Drive A's current folder back to the root. Z, A = 0.
cwdroot: push	af
	call	cwdptr
	xor	a
	ld	(hl),a
	inc	hl
	ld	(hl),a
	pop	af
	call	pthptr
	ld	(hl),0
	xor	a
	ret
cc_ok:	pop	hl
	xor	a
	ret

; Entry HL of folder dircl, not the root: as dirent. dlast is the last
; cluster of the chain walked, for dgrow. The walk goes on from where
; the last one in this folder ended when the entry is at or past it,
; so a scan is not a walk from the start for every sector.
dsub:	call	dxidx			; HL = the sector in the folder
	ld	a,(ix+D_SPC)
	dec	a
	and	l
	push	af			; its sector in its cluster
	ld	b,(ix+D_SPCSH)
	call	shrb			; HL = the cluster's place in the chain
	push	hl
	ld	b,h
	ld	c,l
	ld	hl,(dircl)		; the folder walked last, on this drive,
	ld	de,(dscdir)		; and not past here?
	or	a
	sbc	hl,de
	jr	nz,dsu_0
	push	ix
	pop	hl
	ld	de,(dscix)
	sbc	hl,de
	jr	nz,dsu_0
	ld	h,b
	ld	l,c
	ld	de,(dscord)
	sbc	hl,de
	jr	c,dsu_0
	ld	b,h			; on from there
	ld	c,l
	ld	hl,(dsccl)
	jr	dsu_1
dsu_0:	ld	hl,(dircl)		; from the start
dsu_1:	ld	(dlast),hl
	ld	a,b
	or	c
	jr	z,dsu_2
	push	bc
	call	fatget
	pop	bc
	jr	nz,dsu_e
	call	fateoc
	jr	c,dsu_x			; past the end of the folder
	dec	bc
	jr	dsu_1
dsu_2:	ld	(dsccl),hl		; kept for the next
	pop	de
	ld	(dscord),de
	ld	de,(dircl)
	ld	(dscdir),de
	push	ix
	pop	de
	ld	(dscix),de
	call	clsec
	pop	af
	ld	l,a
	ld	h,0
	jp	de_s			; on as dirent
dsu_x:	ld	a,R_NOFILE		; past the end, as ds_end
dsu_e:	ld	b,a
	pop	af
	pop	af
	ld	a,b
	or	a
	ret

; A free entry in folder dircl, made from spat: the name, archive, no
; data. HL = it, dpos its number. A folder that is full grows by a
; cluster. NZ, A = R_NOFILE when there is no room, or an error.
dnew:	ld	hl,0
dn_0:	ld	(dpos),hl
	call	dirent
	jr	z,dn_2
	cp	R_NOFILE
	ret	nz
	ld	hl,(dircl)		; the root is full
	ld	a,h
	or	l
	jr	z,dn_full
	call	dgrow
	jr	nz,dn_full
	ld	hl,(dpos)
	jr	dn_0
dn_1:	ld	hl,(dpos)
	inc	hl
	ld	a,h			; past entry FFFFh: a full folder
	or	l			; whose chain goes round
	jr	z,dn_full
	jr	dn_0
dn_2:	ld	a,(hl)
	or	a
	jr	z,dn_3
	cp	0E5h
	jr	nz,dn_1
dn_3:	ld	de,spat
	ld	a,A_ARC
	call	mkent
	xor	a
	ret
dn_full: ld	a,R_NOFILE
	or	a
	ret

; One more cluster, empty, on the end of folder dircl: after dlast
dgrow:	ld	hl,(dlast)
	call	fatgrow
	ret	nz
; Fill cluster HL with zeros
zclus:	call	clsec
	ld	b,(ix+D_SPC)
zc_1:	call	newsec			; keeps BC and DE
	ret	nz
	push	bc
	push	de
	ld	bc,511
	call	zfill
	call	bdirty
	pop	de
	pop	bc
	inc	de
	djnz	zc_1
	xor	a
	ret

; ------------------------------------------------------------------
; Paths. A path is parts split by \ or /, after an optional drive
; letter: a leading \ starts at the root, . is the folder itself and
; .. the one above.

; Walk the path at HL. Z: fdrive mounted, dircl the folder reached,
; wpath its path. With wlast set the last part is not walked but left
; in spat, blank if there is none. NZ, A = error.
walk:	call	skipsp
	inc	hl
	ld	a,(hl)
	dec	hl
	cp	':'
	ld	a,(scb+SCB_DRV)
	jr	nz,wk_1
	ld	a,(hl)
	sub	'A'
	inc	hl
	inc	hl
wk_1:	ld	(fdrive),a
	push	hl
	call	mount
	jr	nz,wk_e
	ld	a,' '			; after mount, which may have used it
	ld	(spat),a
	ld	a,(drvnum)
	call	pthptr
	ld	de,wpath
	ld	bc,CWDLEN
	ldir
	pop	hl
	ld	a,(hl)
	cp	5Ch
	jr	z,wk_r
	cp	'/'
	jr	nz,wk_2
wk_r:	inc	hl
	xor	a
	ld	(wpath),a
	ld	d,a
	ld	e,a
	ld	(dircl),de
wk_2:	ld	a,(hl)
	call	pcend
	jr	z,wk_ok
	call	pcomp
	ret	nz
	ld	a,(wlast)
	or	a
	jr	z,wk_3
	ld	a,(hl)
	call	pcend
	jr	z,wk_ok
wk_3:	push	hl
	call	wkpart
	pop	hl
	ret	nz
	jr	wk_2
wk_e:	pop	hl
	ret
wk_ok:	xor	a
	ret

; Z at the end of a part: NUL, space, \ or /. Keeps A.
pcend:	or	a
	ret	z
	cp	' '
	ret	z
	cp	5Ch
	ret	z
	cp	'/'
	ret

; One part of a path at HL into spat as a FAT name. HL ends past it
; and past a \ or / after it. NZ, A = E_BADNAME for a name that does
; not fit or has a wildcard.
pcomp:	ld	de,spat
	push	de
	ld	b,11
	ld	a,' '
pc_0:	ld	(de),a
	inc	de
	djnz	pc_0
	pop	de
	ld	b,8
	ld	a,(hl)			; . and .., and nothing after
	cp	'.'
	jr	nz,pc_1
	ld	(de),a
	inc	hl
	cp	(hl)
	jr	nz,pc_d
	inc	de
	ld	(de),a
	inc	hl
pc_d:	ld	a,(hl)
	call	pcend
	jr	z,pc_9
	jr	pc_bad
pc_1:	ld	a,(hl)
	call	pcend
	jr	z,pc_9
	inc	hl
	cp	'.'
	jr	z,pc_x
	call	pcch
	ret	nz
	jr	pc_1
pc_x:	ld	de,spat+8
	ld	b,3
pc_2:	ld	a,(hl)
	call	pcend
	jr	z,pc_9
	inc	hl
	call	pcch
	ret	nz
	jr	pc_2
pc_9:	or	a
	jr	z,pc_10
	cp	' '
	jr	z,pc_10
	inc	hl			; past the \ or /
pc_10:	ld	a,(spat)
	cp	' '
	jr	z,pc_bad
	xor	a
	ret
; A into the name at DE, if B places are left
pcch:	ld	c,a
	ld	a,b
	or	a
	jr	z,pc_bad
	ld	a,c
	cp	'*'
	jr	z,pc_bad
	cp	'?'
	jr	z,pc_bad
	cp	'.'
	jr	z,pc_bad
	call	upper
	ld	(de),a
	inc	de
	dec	b
	xor	a
	ret
pc_bad:	ld	a,E_BADNAME
	or	a
	ret

; Into the folder spat names, in dircl, and onto the end of wpath.
; . stays, .. goes up.
wkpart:	ld	a,(spat)
	cp	'.'
	jr	nz,wp_1
	ld	a,(spat+1)
	cp	'.'
	jr	z,wp_up
	xor	a
	ret
wp_up:	ld	hl,(dircl)
	ld	a,h
	or	l
	ret	z			; above the root is the root
	call	wpfind
	ret	nz
	ld	(dircl),hl
	ld	hl,wpath		; the path less its last part
	ld	d,h
	ld	e,l
wu_1:	ld	a,(hl)
	or	a
	jr	z,wu_2
	inc	hl
	cp	5Ch
	jr	nz,wu_1
	ld	d,h
	ld	e,l
	dec	de
	jr	wu_1
wu_2:	ld	(de),a
	ret
wp_1:	call	wpfind
	ret	nz
	ld	(dircl),hl
	ld	hl,wpath
	xor	a
	ld	bc,CWDLEN
	cpir
	dec	hl
	ex	de,hl			; DE = the end of the path
	ld	hl,-(wpath+CWDLEN-14)
	add	hl,de
	ld	a,E_LONG
	jr	c,wp_e
	ld	a,(wpath)
	or	a
	jr	z,wp_2
	ld	a,5Ch
	ld	(de),a
	inc	de
wp_2:	ld	hl,spat
	ld	b,11
wp_3:	ld	a,b
	cp	3
	jr	nz,wp_4
	ld	a,(hl)
	cp	' '
	jr	z,wp_5
	ld	a,'.'
	ld	(de),a
	inc	de
wp_4:	ld	a,(hl)
	inc	hl
	cp	' '
	jr	z,wp_6
	ld	(de),a
	inc	de
wp_6:	djnz	wp_3
wp_5:	xor	a
	ld	(de),a
	ret
wp_e:	or	a
	ret

; dsfirst for files and folders alike
dsany:	call	dsdir
; dsdirs back to 0, files only. Keeps AF.
dsdone:	push	af
	xor	a
	ld	(dsdirs),a
	pop	af
	ret
; dsfirst with dsdirs set: folders found too
dsdir:	ld	a,A_DIR
	ld	(dsdirs),a
	jp	dsfirst

; HL = the first cluster of the folder spat names in dircl, Z. dpos is
; its entry. NZ, A = E_NOPATH if there is none, or its cluster is out of
; range on a damaged disk. 0 is the root, as ".." has it.
wpfind:	call	dsdir
	jr	wf_2
wf_1:	call	dsnext
wf_2:	jr	nz,wf_no
	ld	b,A_DIR
	call	isattr
	jr	z,wf_1			; a file of that name
	ld	de,DE_CLUS
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	or	h
	jr	z,wf_9			; the root: Z, A = 0
	call	fateoc
	ld	a,R_NOFILE
	jr	c,wf_no
	xor	a
	jr	wf_9
wf_no:	cp	R_NOFILE
	jr	nz,wf_9
	ld	a,E_NOPATH
	or	a
wf_9:	jr	dsdone

; Parse a file name at HL into the FCB at DE, as parsefn, after a
; folder path if there is one: GAMES\X.COM, \X.COM, B:\GAMES\X.COM. A
; path sets dirov to its folder. Carry for a bad name, and an error
; in the path goes to sherr.
parsep:	ld	(ppfcb),de
	call	skipsp
	ld	d,h
	ld	e,l
	ld	bc,0
pps_1:	ld	a,(hl)			; BC = past the last \ or /
	or	a
	jr	z,pps_2
	cp	' '
	jr	z,pps_2
	cp	'='
	jr	z,pps_2
	inc	hl
	cp	5Ch
	jr	z,pps_s
	cp	'/'
	jr	nz,pps_1
pps_s:	ld	b,h
	ld	c,l
	jr	pps_1
pps_2:	ex	de,hl
	ld	a,b
	or	c
	ld	de,(ppfcb)
	jp	z,parsefn
	ld	a,(bc)			; the path alone, for walk
	push	af
	push	bc
	xor	a
	ld	(bc),a
	ld	(wlast),a
	call	walk
	pop	hl
	pop	bc
	ld	(hl),b
	jp	nz,sherr
	ld	de,(dircl)
	ld	(dirov),de
	ld	a,(drvnum)
	ld	(dirovd),a
	ld	de,(ppfcb)		; then the name
	call	parsefn
	ret	c
	push	hl
	ld	hl,(ppfcb)		; on the path's drive
	ld	a,(drvnum)
	inc	a
	ld	(hl),a
	pop	hl
	or	a
	ret

; COPY's source folder, or its destination's, for setdir
cpsrcd:	ld	hl,(srcdir)
	ld	a,(srcdrv)
	jr	cpset
cpdstd:	ld	hl,(dstdir)
	ld	a,(dstdrv)
cpset:	ld	(dirov),hl
	ld	(dirovd),a
	ret

; Make drive drvnum's current folder dircl, its path wpath
cdset:	ld	a,(drvnum)
	call	cwdptr
	ld	de,(dircl)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ld	a,(drvnum)
	call	pthptr
	ex	de,hl
	ld	hl,wpath
	ld	bc,CWDLEN
	ldir
	ret

; Print drive A and its current folder, as A:\GAMES
pcwd:	push	af
	call	pdcol
	ld	a,5Ch
	call	kputc
	pop	af

	call	pthptr
	jp	pstr

; Walk the path at HL but its last part, then lastok
wklast:	ld	a,1
	ld	(wlast),a
	call	walk
	ret	nz
; The last part of a path, in spat, for MKDIR and RMDIR: Z if it is a
; name, else NZ, A = E_BADNAME. NZ, A = E_WRPROT on a protected disk.
lastok:	ld	a,(spat)
	cp	' '
	jp	z,pc_bad
	cp	'.'
	jp	z,pc_bad
	jp	wrprot

; ------------------------------------------------------------------
; Make the folder the path at HL names. Z, or NZ and A = error.
xmkdir:	call	wklast
	ret	nz
	call	dsany			; a file or folder of that name?
	jr	z,mkd_ex
	cp	R_NOFILE
	ret	nz
	call	fatalloc		; its cluster, empty
	ret	nz
	ld	(dcl),hl
	call	zclus
	ret	nz
	call	dnew			; its entry
	jr	z,mkd_1
	push	af			; none: the cluster goes back
	ld	hl,(dcl)
	call	fatfree
	pop	bc
	ret	nz
	ld	a,b
	cp	R_NOFILE
	ret	nz
	ld	hl,(dircl)		; no entry: the root has no more, a
	ld	a,h			; folder could not grow
	or	l
	ld	a,E_FULL
	jr	nz,mkd_f
	ld	a,E_DIRFULL
mkd_f:	or	a
	ret
mkd_ex:	ld	a,E_EXISTS
	or	a
	ret
mkd_1:	ld	de,spat
	call	dentry
	ld	hl,(dcl)		; then . and .. in it
	call	clsec
	call	getsec
	ret	nz
	push	hl
	ld	de,dotnm
	call	dentry
	pop	hl
	ld	de,32
	add	hl,de
	ld	de,(dircl)
	ld	(dcl),de
	ld	de,dotdot
	call	dentry
	jp	flushall

; The folder entry at HL: the 11-byte name at DE, cluster dcl, the time
dentry:	ld	a,A_DIR
	call	mkent
	push	hl
	ld	de,DE_CLUS
	add	hl,de
	ld	de,(dcl)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	pop	hl
	jp	stamp

; An entry at HL: the 11-byte name at DE, attribute A, the rest 0.
; Keeps HL.
mkent:	push	hl
	push	af
	ex	de,hl
	ld	bc,11
	ldir
	ex	de,hl
	pop	af
	ld	(hl),a
	inc	hl
	ld	b,20
mke_1:	ld	(hl),c			; C = 0 after the ldir
	inc	hl
	djnz	mke_1
	pop	hl
	ret

dotdot:	db	'.'
dotnm:	db	".          "

; Remove the empty folder the path at HL names. Z, or NZ and A = error.
xrmdir:	call	wklast
	ret	nz
	call	wpfind
	ret	nz
	ld	(dcl),hl
	ld	a,(drvnum)		; the current folder?
	call	cwdptr
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	de,(dcl)
	or	a
	sbc	hl,de
	ld	a,E_INUSE
	jp	z,wp_e
	ld	hl,(dpos)		; its entry, for after
	ld	(rmpos),hl
	ld	hl,(dircl)
	ld	(rmpar),hl
	ld	(dircl),de		; empty but for . and ..?
	ld	hl,spat
	ld	b,11
rm_0:	ld	(hl),'?'
	inc	hl
	djnz	rm_0
	call	dsdir
rm_1:	jr	nz,rm_2
	ld	a,(hl)
	cp	'.'
	ld	a,E_NOTEMPTY
	jr	nz,rm_2
	call	dsnext
	jr	rm_1
rm_2:	call	dsdone
	cp	R_NOFILE
	jp	nz,wp_e
	ld	hl,(rmpar)		; it is: off with its entry and chain
	ld	(dircl),hl
	ld	hl,(rmpos)
	call	dirent
	ret	nz
	ld	(hl),0E5h
	call	bdirty
	ld	hl,(dcl)
	call	fatfree
	ret	nz
	ld	hl,(rmpos)
	call	lfndel
	jp	flushall
