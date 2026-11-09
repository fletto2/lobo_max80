; xcpmz80 kernel variables, in A2 over the font and common part
; copies, which the boot sector has moved out by the time the kernel
; runs. kmain zeroes them. Each is the one before plus its size.
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
; clock
clk		equ	linebuf+130
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
PZLEN		equ	0B0h
pzbuf		equ	prdest+2
argfcb		equ	pzbuf+PZLEN
argend		equ	argfcb+12
ncount		equ	argend+2
lsattr		equ	ncount+1
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
namebuf		equ	cpeof+1
nameptr		equ	namebuf+NAMEMAX*11
sublines		equ	nameptr+2
argc		equ	sublines+2
argbuf		equ	argc+1
SUBMAX		equ	2048
subbuf		equ	argbuf+130
; FORMAT and SYS
fmtdrv		equ	subbuf+SUBMAX+1
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
; The cache's sectors, last
rsxtop		equ	fmtpc+1	; what 0006h holds: bdosent or the lowest RSX
rsxlink		equ	rsxtop+2	; rsxfree: where the link to this RSX is
rsxn		equ	rsxlink+2	; rsxload: RSXs left in the header
rsxent		equ	rsxn+1		; rsxload: the header entry
rsxbias		equ	rsxent+2	; rsxload: the page to add, and the base
rsxhdr		equ	chainbuf	; a .COM file's header record, 128 bytes:
					; only while the shell loads, after
					; kwboot has taken a 47 command
bufdat		equ	rsxbias+2
fmtbuf		equ	FMTBUF			; a track, FMTSZ bytes
BSSEND		equ	bufdat+NBUF*512
	assert	BSSEND <= 8000h
