; xcpmz80 kernel variables. Each is the one before plus its size. They
; are in three places, to leave 5E00h-7FFFh in A2 to the track buffer:
; - BSS to BSSEND in A2, over the font and common part copies, which
;   the boot sector has moved out by the time the kernel runs,
; - CBSS to CBSSEND in common memory, from the end of the common part
;   to the I/O block,
; - the batch buffer and the cache in A2 at 0000h-0FFFh, free once the
;   boot sector has run there.
; kmain zeroes the first two.
BSS		equ	FONT_LOAD
drvtab		equ	BSS
bufhdr		equ	drvtab+NDRV*DSZ
; block layer
rwflag		equ	bufhdr+NBUF*BHSZ
fdsec		equ	rwflag+1
fdcyl		equ	fdsec+1
fdside		equ	fdcyl+1
fdtries		equ	fdside+1
fdlast		equ	fdtries+1
fdload		equ	fdlast+1
fdwdly		equ	fdload+1		; nonzero: a write waits for the head
drvnum		equ	fdwdly+1
sassp		equ	fdcyl			; SASI: the stack to give up to, in
					; fdcyl and fdside, the floppy's
; FAT
fodd		equ	drvnum+1
fbyte		equ	fodd+1
fsecn		equ	fbyte+2
fstart		equ	fsecn+2
; files
fdrive		equ	fstart+2
dpos		equ	fdrive+1
dsec		equ	dpos+2
didx		equ	dsec+2
spat		equ	didx+1
frec		equ	spat+11
fwflag		equ	frec+2
fsin		equ	fwflag+1
ford		equ	fsin+1
fsect		equ	ford+2
foff		equ	fsect+2
fres		equ	foff+2
; folders
CWDLEN		equ	48
dircl		equ	fres+1		; the folder the directory calls use
dlast		equ	dircl+2		; its last cluster walked
dsdirs		equ	dlast+2		; A_DIR: searches find folders too
rootf		equ	dsdirs+1	; 1: mount gives the root, not the folder
wlast		equ	rootf+1		; walk leaves the last part in spat
dcl		equ	wlast+1
rmpos		equ	dcl+2
rmpar		equ	rmpos+2
cwdcl		equ	rmpar+2		; each drive's folder, 0 the root
cwdpth		equ	cwdcl+NDRV*2	; and its path
wpath		equ	cwdpth+NDRV*CWDLEN
dirov		equ	wpath+CWDLEN	; a path's folder, for drive dirovd,
dirovd		equ	dirov+2		; FFh none
ppfcb		equ	dirovd+1
srcdir		equ	ppfcb+2		; COPY's two folders
srcdrv		equ	srcdir+2
dstdir		equ	srcdrv+1
dstdrv		equ	dstdir+2
srcreal		equ	dstdrv+1
; numbers and names
qcount		equ	srcreal+2
dvlo		equ	qcount+1
dvhi		equ	dvlo+2
; BDOS
bparam		equ	dvhi+2
bfunc		equ	bparam+2
bret		equ	bfunc+1
xdma		equ	bret+2
sdrive		equ	xdma+2
sexmode		equ	sdrive+1
sspat		equ	sexmode+1
sdpos		equ	sspat+11
sext		equ	sdpos+2
; COPY and MV in batches of NAMEMAX use 17 and 18's place: the shell
; runs no program meanwhile
cppat		equ	sspat		; the source pattern
cppos		equ	sdpos		; the directory place a batch ended at
cpstate		equ	sext		; bit 0 more to come, bit 1 a later batch
dirblks		equ	sext+1
blkk		equ	dirblks+1	; DPB block: 2K << blkk
entk		equ	blkk+1		; an entry holds 16K << entk
bnsz		equ	entk+1		; block numbers: 1 or 2 bytes
slast		equ	bnsz+1		; search: the file's last extent
sfirst		equ	slast+2		; and the entry's first
sfcba		equ	sfirst+2	; the FCB 17 was given
sall		equ	sfcba+2		; 17 had '?' in its drive byte
ldown		equ	sall+1		; the shell's 59 to the RSXs
blkdev		equ	ldown+1
errcode		equ	blkdev+1
chainf		equ	errcode+1
chainbuf		equ	chainf+1
pbuf		equ	chainbuf+128
; line input
lnmax		equ	pbuf+128
lnlen		equ	lnmax+1
lnstart		equ	lnlen+1
lnend		equ	lnstart+1
linebuf		equ	lnend+1
lnhist		equ	linebuf+255	; not 0: UP brings back the last line
histlen		equ	lnhist+1	; the shell's last line, its length
histbuf		equ	histlen+1	; and its text
; clock
clk		equ	histbuf+128
clk2		equ	clk+13
cyear		equ	clk2+13
cmon		equ	cyear+2
cday		equ	cmon+1
chour		equ	cday+1
cmin		equ	chour+1
csec		equ	cmin+1
; shell and loader
shdrv		equ	csec+1
subact		equ	shdrv+1
cmdfcb		equ	subact+1
cmdtail		equ	cmdfcb+12
tailp		equ	cmdtail+2
progdrv		equ	tailp+2
prrecs		equ	progdrv+1
prfrom		equ	prrecs+2
prdest		equ	prfrom+2
BSSEND		equ	prdest+2
PZLEN		equ	0B0h
CBSS		equ	COMMON_END
pzbuf		equ	CBSS
argfcb		equ	pzbuf+PZLEN
argend		equ	argfcb+12
ncount		equ	argend+2	; 16 bits for DIR and LS, 8 for COPY
lsattr		equ	ncount+2
renew		equ	lsattr+1
reold		equ	renew+12
savepg		equ	reold+12
cpsrc		equ	savepg+1
cpdst		equ	cpsrc+12
cpdst2		equ	cpdst+12
srcfcb		equ	cpdst2+12
dstfcb		equ	srcfcb+36
cprec		equ	dstfcb+36
cptop		equ	cprec+2		; COPY's TPA buffer: its end,
cpptr		equ	cptop+2		; where the next record goes,
cpn		equ	cpptr+2		; the records in it, and
cpeof		equ	cpn+2		; 1 at the end of the source
NAMEMAX		equ	64
nameptr		equ	cpeof+1
sublines		equ	nameptr+2
argc		equ	sublines+2
argbuf		equ	argc+1
SUBMAX		equ	2048
subtot		equ	argbuf+130	; a batch run from subbuf: its lines,
subnext		equ	subtot+2	; and the next one
; FORMAT and SYS
fmtdrv		equ	subnext+2
fmttrk		equ	fmtdrv+1
fmtmb		equ	fmttrk+1
fmtf16		equ	fmtmb+1
fmtmed		equ	fmtf16+1
fmtcl		equ	fmtmed+1
fmtspf		equ	fmtcl+2
fmtroot		equ	fmtspf+2
fmtk		equ	fmtroot+2		; floppy: its fmtab row, or 0 its kind
fmtsd		equ	fmtk+2			; the side being written
fmtcyl		equ	fmtsd+1			; cylinders
fmtrot		equ	fmtcyl+1		; the track's first slot
fmtgap		equ	fmtrot+1		; the gap after each sector
fmtpc		equ	fmtgap+1		; 1 for PC after the size
fmtilv		equ	fmtpc+1			; ILV n, or 0 for the default
fmtslt		equ	fmtilv+1		; the sector in each slot, 18 bytes
; MV
mvflag		equ	fmtslt+18		; not 0: COPY's loop moves
mvsrc		equ	mvflag+1	; fmove: the source folder
mvdst		equ	mvsrc+2		; the destination folder
mvpos		equ	mvdst+2		; the source entry's number
mvbuf		equ	mvpos+2		; and the entry, 32 bytes
; The cache's sectors, last
rsxtop		equ	mvbuf+32	; what 0006h holds: bdosent or the lowest RSX
rsxlink		equ	rsxtop+2	; rsxfree: where the link to this RSX is
rsxn		equ	rsxlink+2	; rsxload: RSXs left in the header
rsxent		equ	rsxn+1		; rsxload: the header entry
rsxbias		equ	rsxent+2	; rsxload: the page to add, and the base
rsxhdr		equ	chainbuf	; a .COM file's header record, 128 bytes:
					; only while the shell loads, after
					; kwboot has taken a 47 command
dfree		equ	rsxbias+2	; each drive's free clusters, FFFFh not
					; counted since the mount, NDRV * 2
dscdir		equ	dfree+NDRV*2	; dsub's place in a folder's chain: the
dscix		equ	dscdir+2	; folder, its drive's IX (0 none),
dscord		equ	dscix+2		; the cluster's place in the chain,
dsccl		equ	dscord+2	; and the cluster
frdrv		equ	dsccl+2		; the fresh cluster's drive + 1, 0 none
frcl		equ	frdrv+1		; the cluster last allocated to a file
frnext		equ	frcl+2		; its first sector not yet zeroed
fdiff		equ	frnext+1	; the IFF before an FDC transfer
wbdrv		equ	fdiff+1		; a failed write-back's drive + 1, 0 none
fnpos		equ	wbdrv+1		; frename: the entry being renamed
fnbuf		equ	fnpos+2		; and its new name, 11 bytes
fdrun		equ	fnbuf+11	; sectors in a run read, 0 a single one
fdrend		equ	fdrun+1		; FSECTOR as read on its last sector
tbix		equ	fdrend+1	; the track buffer: its drive's IX, low
tblba		equ	tbix+1		; byte, its first sector, 2 bytes,
tbcnt		equ	tblba+2		; and how many it holds, 0 empty
tbmode		equ	tbcnt+1		; each drive: 0 interleave not known,
					; 1 runs, 2 a sector at a time, NDRV
tbstop		equ	tbmode+NDRV	; the run's end page
tbsplit		equ	tbstop+1	; sectors in its second part, 0 none
fdcmdb		equ	tbsplit+1	; the read command
fdid		equ	fdcmdb+1	; an ID read by Read Address, 6 bytes
sastm		equ	fdid+6		; SASI: looks left in a wait
namebuf		equ	sastm+2		; COPY's names, NAMEMAX * 11
	ifdef	RUNLOG			; the test build's record of a run
rlid1		equ	namebuf+NAMEMAX*11	; the last ID, rlid2 the one before
rlid2		equ	rlid1+1
rlf1		equ	rlid2+1		; the sector register at the last stop,
rlf2		equ	rlf1+1		; rlf2 at the one before
rlk		equ	rlf2+1		; where the run started
rlsp		equ	rlk+1		; and its second part
rlpn		equ	rlsp+1		; looks at the sector register, counting,
rlp1		equ	rlpn+1		; at the last stop,
rlp2		equ	rlp1+1		; and the one before
rlhd		equ	rlp2+1		; 1 once the line has started
rls		equ	rlhd+1		; the run's first sector
rln		equ	rls+1		; and length
rlcyl		equ	rln+1		; its cylinder and side
rlpg		equ	rlcyl+2		; its first page in the buffer
rlst		equ	rlpg+1		; the last status, true form
CBSSEND		equ	rlst+1
	else
CBSSEND		equ	namebuf+NAMEMAX*11
	endif
	assert	CBSSEND <= BLK
; Below the kernel, in A2
subbuf		equ	0000h		; a batch file, SUBMAX bytes, and its ^Z
bufdat		equ	subbuf+SUBMAX	; when it is shorter
	assert	bufdat+NBUF*512 <= 1000h
fmtbuf		equ	FMTBUF			; a track, FMTSZ bytes
	assert	BSSEND <= TBEND-TBMAX*512	; the track buffer above
	ifdef	RUNLOG
	assert	BSSEND <= RLSCR
	endif
