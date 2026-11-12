; xcpmz80 common part. Runs in A1, always mapped at 8000h-FFFFh, so
; it is there whatever bank the low half shows. Holds what programs call
; and what must not move: the BDOS entry and the System Control Block,
; the BIOS jump table, copying to and from programs' memory, cold start,
; the console, the key ring and the tick.
;
; The behavior follows Lobo's CP/M 3 BIOS (XBOOT, XCHARIO, XMOVE); the
; code is our own.

; Common variables, in CVARS
VLCOPY		equ	CVARS+00h	; what we last wrote to VLATCH
CURROW		equ	CVARS+02h
CURCOL		equ	CVARS+03h
SCRST		equ	CVARS+04h	; CRTC start address, 2 bytes
UNDER		equ	CVARS+06h	; the character under the cursor
KFILL		equ	CVARS+07h	; key ring index to fill
KTAKE		equ	CVARS+08h	; key ring index to take from
KEY		equ	CVARS+09h	; last key pressed, before shift
RPTIME		equ	CVARS+0Ah	; ticks to the next repeat, 0 none
KBLOCK		equ	CVARS+0Bh	; new keys still taken this scan
RAMK		equ	CVARS+0Ch	; RAM found, in K
KPREV		equ	CVARS+10h	; 8 rows of T1, then 8 rows of T2
ISRSP		equ	CVARS+20h	; the stack the tick came in on
usersp		equ	CVARS+22h	; the program's stack, in the BDOS
kstk		equ	CVARS+24h	; the stack the BDOS runs on
shsp		equ	CVARS+26h	; the kernel's stack, in rsxcall
ESCST		equ	CVARS+28h	; 0, 1 after ESC, 2 after ESC =, 3 the column
ESCROW		equ	CVARS+29h	; ESC ='s row, + 20h
DIM		equ	CVARS+2Ah	; nonzero: ESC ) print, the second style
CURHID		equ	CVARS+2Bh	; nonzero: ESC 0, no cursor
UBANK		equ	CVARS+2Ch	; the caller's low bank, for ucopy
LIBIFF		equ	CVARS+2Dh	; 0 not in the C library, else 1 + its IFF
UIFF		equ	CVARS+2Eh	; the IFF under umap, 0 off
KCAPS		equ	CVARS+2Fh	; 0 Caps Lock on, as at boot, 20h off
CURHL		equ	CVARS+30h	; the cell curon last put the cursor on
TICKS		equ	CVARS+32h	; counts the ticks, for the blink
BDIFF		equ	CVARS+34h	; 1: the BDOS turned interrupts off
BLINKO		equ	CVARS+33h	; nonzero: the blink has the cursor off
RSXSTK		equ	CVARS+100h	; rsxcall's stack, from CVARS+80h
RSXSTUB		equ	0040h		; in page zero: call 0005h, jp rsxret

COMMON_LOAD:
	disp	0DF00h
COMMON_ORG:

; The BDOS entry, at xx06h as in CP/M. Page zero jumps here, and its
; address is the top of the TPA. C = function, DE = parameter. The
; result is in HL, and in A and B as CP/M returns it. IX and IY are kept.
; The caller's low bank, the TPA or the C library's B2, is mapped back
; and is the one ucopy, upeek and upoke reach, so the library's own FCBs
; and buffers work. Function LIBFN is a call into the C library.
	db	0,0,0,0,0,0		; serial number
bdosent: ld	a,c
	cp	7
	jp	c,bfast			; 2, 6 and 11 may not need the kernel
	cp	11
	jp	z,bf_11
be_0:	cp	LIBFN			; A = C
	jr	z,libent
	ld	(usersp),sp
	ld	sp,(kstk)
	push	ix
	push	iy
	ld	a,(UBANK)
	push	af
	call	bdioff			; before the kernel is mapped
	ld	a,(PIODA)
	ld	(UBANK),a
	ld	a,BANK_SYS
	ld	(PIODA),a
	call	kbdos
	jp	bdexit

; The C library: the program's thunk jumped to 0005h with DE = the
; function's number, its return address on the stack and its arguments
; above it, as SDCC put them. B2 has the library's dispatcher at 0000h,
; which runs the function on this stack and comes back by libout with
; the return address on top again. L, HL or DEHL is the result.
; Interrupts are off while B2 is mapped low, as a program's handler
; may be in the TPA, and are as they were again at libout.
libent:	call	iffget
	and	1
	inc	a
	ld	(LIBIFF),a
	ld	a,BANK_B2
	ld	(PIODA),a
	jp	0

; The rest of the page as CP/M 3's resident BDOS has it (RESBDOS3.SPR):
; its BIOS calls at xx68h, which GET and SUBMIT may patch,
; the BDOS entry past the RSXs at xx98h, which they call, and the SCB at
; xx9Ch, whose fields RSXs find by the low byte of the address. The
; kernel does not go through the BIOS calls here.
	assert	$ <= COMMON_ORG+68h
	block	COMMON_ORG+68h-$,0
	jp	biostab+3		; WBOOT
	jp	resredir
	jp	biostab+6		; CONST
	jp	resredir
	jp	biostab+9		; CONIN
	jp	resredir
	jp	biostab+12		; CONOUT
	jp	resredir
	jp	biostab+15		; LIST
	jp	resredir
	block	COMMON_ORG+98h-$,0
	dw	bdosent
	block	COMMON_ORG+9Ch-$,0

; The System Control Block of CP/M 3, read and set with function 49.
; The kernel keeps its console and file state in it.
SCB_VER		equ	05h
SCB_RETC	equ	10h		; program return code, 2 bytes (user flags)
SCB_CCPF	equ	18h		; CCP flags: bit 5 the CCP reads its line
SCB_WIDTH	equ	1Ah
SCB_COL		equ	1Bh
SCB_PAGE	equ	1Ch
SCB_PMODE	equ	2Ch
SCB_CMODE	equ	33h		; console mode, 2 bytes
SCB_DELIM	equ	37h		; function 9's end character
SCB_LIST	equ	38h		; ^P echo to the printer
SCB_DMA		equ	3Ch		; 2 bytes
SCB_DRV		equ	3Eh
SCB_USER	equ	44h
SCB_MULTI	equ	4Ah		; multi-sector count
SCB_ERMODE	equ	4Bh
SCB_PATH	equ	4Ch		; drive search path: 0 the current drive,
					; 1-16 A: to P:, FFh the end
SCB_ERDRV	equ	51h
SCB_DATE	equ	58h		; days since 1978, hour, minute, second
SCB_BASE	equ	3Ah		; the SCB's address
SCB_MXTPA	equ	62h		; top of the TPA, 2 bytes
SCBSZ		equ	64h
scb:	ds	SCBSZ
	assert	$ == 0E000h

; The BIOS jump table, CP/M 3 order. Page zero's 0001h points at WBOOT.
biostab: jp	bcold			; 0 BOOT
	jp	wboot			; 1 WBOOT
	jp	const			; 2 CONST
	jp	conin			; 3 CONIN
	jp	conout			; 4 CONOUT
	jp	list			; 5 LIST
	jp	auxout			; 6 AUXOUT (PUNCH)
	jp	auxin			; 7 AUXIN (READER)
	jp	bnone			; 8 HOME
	jp	bseldsk			; 9 SELDSK
	jp	bnone			; 10 SETTRK
	jp	bnone			; 11 SETSEC
	jp	bnone			; 12 SETDMA
	jp	bfail			; 13 READ
	jp	bfail			; 14 WRITE
	jp	listst			; 15 LISTST
	jp	bsectran		; 16 SECTRAN
	jp	conost			; 17 CONOST
	jp	auxist			; 18 AUXIST
	jp	auxost			; 19 AUXOST
	jp	bdevtbl			; 20 DEVTBL
	jp	bdevini			; 21 DEVINI
	jp	bdrvtbl			; 22 DRVTBL
	jp	bnone			; 23 MULTIO
	jp	bok			; 24 FLUSH
	jp	bmove			; 25 MOVE
	jp	btime			; 26 TIME
	jp	bnone			; 27 SELMEM
	jp	bnone			; 28 SETBNK
	jp	bnone			; 29 XMOVE
	jp	bnone			; 30 USERF
	jp	bnone			; 31 reserved
	jp	bnone			; 32 reserved
BIOSN		equ	33

; The disk entries: the disks are FAT, not CP/M, so a program that goes
; to the BIOS for sectors finds no drive.
bseldsk: ld	hl,0
bnone:	ret
bfail:	ld	a,1
	ret
bok:	xor	a
	ret
bnull:	ld	hl,0
	ret
; DRVTBL, as Lobo's CP/M 3 gives it, so Lobo's COPIER finds each
; drive's kind: 16 DPH addresses, each DPH with two type bytes before it
; (XDATA.MAC, and COPIER.MAC's DVINI and GDTBL). The first is 0 for an
; 8-inch drive, 1 for a 5-inch one of 40 tracks, 2 of 80, the second the
; drive's MLATCH bits, 10h set when its disk has two sides. 0 and 0 is no
; drive, which the SASI disk is. Of the DPH only the DPB address
; is filled, the DPB of function 31. A floppy not found yet takes A:'s
; kind, 8-inch when A: is not a floppy. Puts back the bank it found,
; since function 50 calls it with the system mapped. The stack is not
; used while the system is in, since a program's stack is in the TPA.
bdrvtbl: push	bc
	push	de
	push	ix
	ld	a,(PIODA)
	ld	c,a
	ld	a,BANK_SYS
	ld	(PIODA),a
	ld	ix,drvtab
	ld	hl,XDPH
	ld	b,NDRV
xd_1:	ld	de,0
	ld	a,(ix+D_TYPE)
	cp	DT_FLOPPY
	jr	nz,xd_4
	ld	a,(ix+D_KIND)
	or	a
	jr	nz,xd_2
	ld	a,(drvtab+D_KIND)
	or	a
	jr	nz,xd_2
	inc	a
xd_2:	ld	d,FD_LATCH
	dec	a
	jr	z,xd_3
	ld	d,FD5_LATCH
	inc	e			; 5-inch: 80 tracks from 1024 sectors
	ld	a,(ix+D_TOTAL+1)
	cp	4
	jr	c,xd_3
	inc	e
xd_3:	ld	a,(ix+D_UNIT)
	or	d
	ld	d,a
	ld	a,(ix+D_HEADS)
	cp	2
	jr	nz,xd_4
	set	4,d
xd_4:	ld	(hl),e
	inc	hl
	ld	(hl),d
	ld	de,13			; past the DPH's first 12 bytes
	add	hl,de
	ld	(hl),low DPB
	inc	hl
	ld	(hl),high DPB
	inc	hl
	ld	de,DSZ
	add	ix,de
	djnz	xd_1
	ld	a,c
	ld	(PIODA),a
	pop	ix
	pop	de
	pop	bc
	ld	hl,dtbl
	ret

dtbl:	dw	XDPH+2,XDPH+18,XDPH+34
	dup	13
	dw	dtnone+2
	edup
dtnone:	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0
	dw	DPB
	assert	XDPH+NDRV*16 <= IVPAGE*256+0FEh
bsectran: ld	h,b
	ld	l,c
	ret
; TIME, C = 0: the date and time into the SCB, by BDOS function 105
btime:	ld	a,c
	or	a
	ret	nz
	push	bc
	push	de
	push	hl
	ld	c,105
	ld	de,scb+SCB_DATE
	call	bdosent
	pop	hl
	pop	de
	pop	bc
	ret
bmove:	ex	de,hl			; CP/M 3: DE = source, HL = dest
	ldir
	ex	de,hl
	ret

; The caller's bank low, with interrupts off while it is there, as at
; libent, and usys SYS back with them as they were. usys keeps A.
umap:	call	iffget
	ld	(UIFF),a
	ld	a,(UBANK)
	ld	(PIODA),a
	ret

; A = the program's byte at HL
upeek:	call	umap
	ld	a,(hl)
	jr	usys

; The program's byte at HL = A
upoke:	push	af
	call	umap
	pop	af
	ld	(hl),a
	jr	usys

; Copy BC bytes from HL to DE with the caller's bank (UBANK, the TPA
; but in a call from the C library) mapped low, for the kernel: one end
; is a program's address, the other in common memory. BC must not be 0.
ucopy:	call	umap
	ldir
					; and on into usys
usys:	push	af
	ld	a,BANK_SYS
	ld	(PIODA),a
	ld	a,(UIFF)
	or	a
	jr	z,uy_1
	ei
uy_1:	pop	af
	ret

; The C library's way back and its copy, past the first page
libout:	ld	a,BANK_TPA
	ld	(PIODA),a
	ld	a,(LIBIFF)
	cp	2			; C: they were off
	ld	a,0
	ld	(LIBIFF),a
	ret	c
	ei
	ret
; Interrupts off, A = FFh if they were on, 0 if not
iffget:	ld	a,i			; P/V = IFF2
	jp	pe,if_1
	ld	a,i			; an NMOS Z80 taking an interrupt just
if_1:	di				; after it reads 0, so look again
	ld	a,0
	ret	po
	dec	a
	ret
; The library's copy: BC bytes, not 0, from HL to DE with the TPA mapped
; low, so both ends are as the program sees them, then B2 again
lcopy:	ld	a,BANK_TPA
	ld	(PIODA),a
	ldir
	ld	a,BANK_B2
	ld	(PIODA),a
	ret

; Start a program: TPA mapped, a stack under the BDOS that returns to
; 0000h (warm boot), and jump to 0100h
golaunch: di
	ld	a,BANK_TPA
	ld	(PIODA),a
	ld	hl,(0006h)		; under the BDOS or the lowest RSX
	ld	l,0
	ld	sp,hl
	ld	hl,progret		; RET goes back to the shell, as
	push	hl			; to CP/M 2.2's CCP
	ei
	jp	0100h

; A patched BIOS call above (LD HL,entry for JP entry) comes here, as
; CP/M 3's goes to the TPA bank: programs see the TPA bank already
resredir: jp	(hl)

; Console status and input for the BDOS and the shell, through the BIOS
; jump table as CP/M 2.2's BDOS goes, so a program that patches CONST
; or CONIN there, as QWIKKEY does, is called, with the TPA mapped
; as it expects. As const and conin: A, Z when xconst finds no key, the
; other registers kept.
xconst:	push	hl
	ld	hl,(biostab+7)
	push	de
	ld	de,const
	jr	xc_1
xconin:	push	hl
	ld	hl,(biostab+10)
	push	de
	ld	de,conin
xc_1:	or	a			; our own: straight there
	sbc	hl,de
	add	hl,de
	pop	de
	jr	nz,xc_2
	ex	(sp),hl
	ret
xc_2:	push	bc			; patched: in the TPA bank
	push	de
	ld	a,BANK_TPA
	ld	(PIODA),a
	call	resredir
	ld	b,a
	ld	a,BANK_SYS
	ld	(PIODA),a
	ld	a,b
	or	a
	pop	de
	pop	bc
	pop	hl
	ret

; A CP/M 2.2 CCP's two entries, at BIOS-1600h and +3, which the kernel
; puts in the TPA for programs that go back to the CCP there
CCP22	equ	biostab-1600h
ccpjp:	jp	progret
	jp	progret

; Call the BDOS through page zero's 0005h, as a program does, so the
; RSXs see the call: C = function, DE = parameter in the TPA. For the
; kernel, with A2 mapped. Returns A and HL. The call is made from
; RSXSTUB, below the RSXs, so they take it for a program's. The BDOS
; runs on the stack under the caller's.
rsxcall: ld	(shsp),sp
	ld	(kstk),sp
	ld	sp,RSXSTK
	ld	a,BANK_TPA
	ld	(PIODA),a
	jp	RSXSTUB
rsxret:	ld	b,a
	ld	a,BANK_SYS
	ld	(PIODA),a
	ld	sp,(shsp)
	push	hl
	ld	hl,STKTOP
	ld	(kstk),hl
	pop	hl
	ld	a,b
	ret


; A program's RET: back to the kernel's command line by kret
progret: ld	hl,kret
	jr	wb_1

; Cold boot through the table: as a warm boot
bcold:
; Warm boot: back to the kernel's command line
; Both: the kernel's stack and bank, and out of the C library, which a
; program may have left by a warm boot inside a call
wboot:	ld	hl,kwboot
wb_1:	di
	ld	sp,STKTOP
	ld	(kstk),sp
	ld	a,BANK_SYS
	ld	(PIODA),a
	xor	a
	ld	(LIBIFF),a
	ld	(BDIFF),a
	ld	a,IVPAGE		; the system's tick again, whatever
	ld	i,a			; table a program left
	ei
	jp	(hl)

; At 0000h in B2 when there is no library: HL = 0, back to the program.
; Here, not in the kernel, so ucopy reaches it with B2 low.
clibstub: ld	hl,0
	ld	d,h
	ld	e,l
	jp	libout
clibsl	equ	$-clibstub

; ------------------------------------------------------------------
; Character devices, as Lobo's CP/M 3 BIOS (XCHARIO and XDATA): 0 CRT,
; 1 SIOA, 2 SIOB, 3 PPRT. The SCB's
; vectors pick them, bit 15 device 0: output goes to every device in
; its vector, input comes from the first one with a byte.
NDEV		equ	4
SCB_CIVEC	equ	22h
SCB_COVEC	equ	24h
SCB_AIVEC	equ	26h
SCB_AOVEC	equ	28h
SCB_LOVEC	equ	2Ah

; Each device: input status, input, output status, output. Status:
; A = FFh and NZ ready, 0 and Z not. Output: C = the character.
devtab:	dw	kbdst,kbdin,crtost,crtout
	dw	siaist,siain,siaost,siaout
	dw	sibist,sibin,sibost,sibout
	dw	nost,nulin,ppost,ppout

; The table DEVTBL gives and DEVICE shows: name, mode, DRI's baud code.
; Mode bits: 1 input, 2 output, 4 the rate can be set, 8 serial.
devtbl:	db	"CRT   ",3,0
	db	"SIOA  ",15,14			; 9600
	db	"SIOB  ",15,14
	db	"PPRT  ",2,0
	db	0

; The BIOS entries: through the SCB's vectors. Every register but AF is
; kept. The console on the CRT alone, as it nearly always is, goes
; straight there, as fast as before the vectors.
const:	ld	a,(scb+SCB_CIVEC+1)
	cp	80h
	jr	nz,cst_v
	ld	a,(scb+SCB_CIVEC)
	or	a
	jr	nz,cst_v
	push	bc
	call	kbdst
	pop	bc
	ret
cst_v:	push	de
	ld	de,scb+SCB_CIVEC
	jr	vist
conin:	ld	a,(scb+SCB_CIVEC+1)
	cp	80h
	jr	nz,cin_v
	ld	a,(scb+SCB_CIVEC)
	or	a
	jp	z,kbdin
cin_v:	push	de
	ld	de,scb+SCB_CIVEC
	jr	vin
conout:	push	af
	ld	a,(scb+SCB_COVEC+1)
	cp	80h
	jr	nz,cot_v
	ld	a,(scb+SCB_COVEC)
	or	a
	jr	nz,cot_v
	pop	af
	jp	crtout
cot_v:	pop	af
	push	de
	ld	de,scb+SCB_COVEC
	jr	vout
conost:	push	de
	ld	de,scb+SCB_COVEC
	jr	vost
auxist:	push	de
	ld	de,scb+SCB_AIVEC
	jr	vist
auxin:	push	de
	ld	de,scb+SCB_AIVEC
	jr	vin
auxost:	push	de
	ld	de,scb+SCB_AOVEC
	jr	vost
auxout:	push	de
	ld	de,scb+SCB_AOVEC
	jr	vout
listst:	push	de
	ld	de,scb+SCB_LOVEC
	jr	vost
list:	push	de
	ld	de,scb+SCB_LOVEC
	; fall into vout

; These take the vector's address in DE and the caller's DE on the
; stack, which they pop at the end.
; C out on every device of the vector
vout:	ld	a,6
	jr	vgo

; Every device of the vector ready for output? A = FFh, NZ
vost:	ld	a,4
	jr	vgo

; Has a device of the vector a byte? A = FFh, NZ
vist:	xor	a
vgo:	push	bc
	push	hl
	ex	de,hl
	ld	e,a
	call	vscan
	pop	hl
	pop	bc
	pop	de
	ret

; The next byte from the first device of the vector that has one. An
; empty vector gives 1Ah, end of file.
vin:	push	bc
	push	hl
	ex	de,hl
	ld	a,(hl)
	inc	hl
	or	(hl)
	dec	hl
	ld	a,1Ah
	jr	z,vn_9
vn_1:	push	hl
	ld	e,0
	call	vscan			; B = the device that has one
	pop	hl
	jr	z,vn_1
	ld	a,b
	ld	e,2
	call	devgo
vn_9:	pop	hl
	pop	bc
	pop	de
	ret

; Routine E (0, 4, 6) of each device in the vector at HL. Outputs go
; to all. Input status stops at the first ready, with B = it, A = FFh.
; Output status stops at the first not ready, A = 0. Z as A.
vscan:	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	b,0
vs_1:	add	hl,hl
	jr	nc,vs_2
	push	hl
	push	de
	push	bc
	ld	a,b
	call	devgo
	pop	bc
	pop	de
	pop	hl
	ld	d,a
	ld	a,e
	cp	4
	jr	z,vs_ost
	or	a
	jr	nz,vs_2
	ld	a,d			; input status: the first ready
	or	a
	ret	nz
	jr	vs_2
vs_ost:	ld	a,d			; output status: the first not ready
	or	a
	ret	z
vs_2:	inc	b
	ld	a,b
	cp	NDEV
	jr	c,vs_1
	ld	a,e			; none stopped it: output status
	cp	4			; ready, input status not
	ld	a,0FFh
	jr	z,vs_9
	xor	a
vs_9:	or	a
	ret

; Device A's routine E. Keeps C.
devgo:	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	d,0
	add	hl,de
	ld	de,devtab
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	jp	(hl)

; DEVTBL: the table. DEVINI, C = device: a serial channel's rate from
; its entry, DRI's code to the COM8116's, which has 2000 baud at 9 and
; DRI's has not, as Lobo's INIAB does.
bdevtbl: ld	hl,devtbl
	ret
bdevini: ld	a,c
	dec	a
	cp	2
	ret	nc
	ld	l,c
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	de,devtbl+7
	add	hl,de
	ld	a,(hl)
	cp	10
	jr	nc,di_1
	dec	a
di_1:	ld	hl,BAUDA
	dec	c
	jr	z,di_2
	ld	hl,BAUDB
di_2:	ld	(hl),a
	ret

; The printer, as Lobo's: wait for not busy, then the byte. Status:
; A = FFh and NZ when ready, 0 and Z when busy
ppost:	ld	a,(PSTAT)
	rla
	sbc	a,a			; FFh busy
	cpl
	or	a
	ret
ppout:	call	ppost
	jr	z,ppout
	ld	a,c
	ld	(PDATA),a
	ret
nost:	xor	a			; no input there
	ret
nulin:	ld	a,1Ah
	ret
crtost:	ld	a,0FFh
	or	a
	ret

; The SIO, polled, as Lobo's: RR0 bit 0 a byte in, bit 2 room to send.
; Channel B's parity bit is dropped. A has 8 data bits and keeps them,
; where Lobo's drops bit 7 on both, so a binary file comes in whole.
siaist:	ld	hl,SIOCA
	jr	sist
sibist:	ld	hl,SIOCB
sist:	ld	a,(hl)
	and	01h
	ret	z
	ld	a,0FFh
	ret
siain:	call	siaist
	jr	z,siain
	ld	a,(SIODA)
	ret
sibin:	call	sibist
	jr	z,sibin
	ld	a,(SIODB)
	and	7Fh
	ret
siaost:	ld	hl,SIOCA
	jr	sost
sibost:	ld	hl,SIOCB
sost:	ld	a,(hl)
	and	04h
	ret	z
	ld	a,0FFh
	ret
siaout:	call	siaost
	jr	z,siaout
	ld	a,c
	ld	(SIODA),a
	ret
sibout:	call	sibost
	jr	z,sibout
	ld	a,c
	ld	(SIODB),a
	ret

; Count the RAM into RAMK: 64K, plus 32K for each of B1 and B2 that
; holds a test pattern. Interrupts are off. In common memory, as it maps
; B1 and B2 low.
ramtest: ld	b,64
	ld	a,BANK_TPA
	call	rt1
	ld	a,BANK_B2
	call	rt1
	ld	a,BANK_SYS
	ld	(PIODA),a
	ld	a,b
	ld	(RAMK),a
	ret
rt1:	ld	(PIODA),a
	ld	hl,0
	ld	c,(hl)
	ld	a,55h
	ld	(hl),a
	cp	(hl)
	jr	nz,rt2
	cpl
	ld	(hl),a
	cp	(hl)
	jr	nz,rt2
	ld	a,b
	add	a,32
	ld	b,a
rt2:	ld	(hl),c
	ret

; Functions 2 and 6 writing a character, the most called, done here
; without the kernel mapped in, as its f2 and f6 do them. A tab, which
; kputc expands, and a ^S waiting go there.
bfast:	cp	2
	jr	z,bf_2
	cp	6
	jr	nz,bf_k
	ld	a,e
	cp	0FDh
	jp	c,bf_6o			; FDh-FFh read
	inc	a
	jp	z,bf_6i			; FFh with no key: 0, here
bf_k:	ld	a,c
	jp	be_0
bf_2:	ld	a,e
	cp	09h
	jr	z,bf_k
	ld	a,(scb+SCB_CMODE)	; as brkchk, with kpeek's look at the
	and	02h			; key ring here, nothing on the
	jr	nz,bf_out		; program's stack
	ld	a,(KTAKE)
	ld	l,a
	ld	a,(KFILL)
	cp	l
	jr	z,bf_out
	ld	h,high KRING
	ld	a,(hl)
	cp	13h
	jr	z,bf_k
bf_out:	ld	(usersp),sp		; on the BDOS's stack, as CP/M's: a
	ld	sp,(kstk)		; program may keep only a few bytes
	ld	c,e
	call	kraw
	jr	bf_ret
; 11 from here, nothing on the program's stack, when the kernel would
; only look at the key ring: not ^C-only status (mode bit 0), the
; console in from the keyboard alone, CONST not patched
bf_11:	ld	a,(scb+SCB_CMODE)
	rra
	jr	c,bf_k
	ld	a,(scb+SCB_CIVEC+1)
	cp	80h
	jr	nz,bf_k
	ld	a,(scb+SCB_CIVEC)
	or	a
	jr	nz,bf_k
	ld	hl,(biostab+7)
	ld	a,l
	cp	low const
	jr	nz,bf_k
	ld	a,h
	cp	high const
	jr	nz,bf_k
	ld	a,(KTAKE)
	ld	b,a
	ld	a,(KFILL)
	sub	b
	jr	z,bf_11z
	ld	a,1
bf_11z:	ld	l,a
	ld	h,0
	ld	b,h
	ret
; 6 with FFh when no key waits, as 11, and on its conditions but mode
; bit 0: 0 at once. A key waiting goes to the kernel, which takes it
bf_6i:	ld	a,(scb+SCB_CIVEC+1)
	cp	80h
	jp	nz,bf_k
	ld	a,(scb+SCB_CIVEC)
	or	a
	jp	nz,bf_k
	ld	hl,(biostab+7)
	ld	a,l
	cp	low const
	jp	nz,bf_k
	ld	a,h
	cp	high const
	jp	nz,bf_k
	ld	a,(KTAKE)
	ld	b,a
	ld	a,(KFILL)
	cp	b
	jp	nz,bf_k
	xor	a
	ld	l,a
	ld	h,a
	ld	b,a
	ret
bf_6o:	ld	(usersp),sp		; 6 writes as CP/M's: to the console
	ld	sp,(kstk)		; alone, not the printer, and the
	ld	c,e			; column is left as it is
	call	conout
bf_ret:	ld	sp,(usersp)
	ld	hl,0
	ld	a,l
	ld	b,h
	ret

; The interrupts while the kernel is mapped, set before it is. A
; program's own vector table or handler below 8000h would run the
; kernel's bytes: off then, and the program's tick waits. From the
; library, whose interrupts are off: on again, if they were and the
; vector is safe, for the keys. Uses A and HL
bdioff:	ld	a,i
	jp	pe,bdi_2		; on now
	ld	a,i			; as iffget: an NMOS Z80 reads 0 when
	jp	pe,bdi_2		; an interrupt comes right after
	ld	h,a
	ld	a,(LIBIFF)
	cp	2
	ret	c			; off, and stay off
	ld	a,h
	call	bdbad
	ret	c
	ei
	ret
bdi_2:	call	bdbad
	ret	nc
	di
	ld	a,1
	ld	(BDIFF),a
	ret
; Carry if the vector for I = A, or the handler it holds, is below 8000h
bdbad:	cp	80h
	ret	c
	ld	h,a
	ld	l,0FFh			; the handler's high byte, at I:FFh
	ld	a,(hl)
	cp	80h
	ret
; Out of the BDOS: the program's bank, and its interrupts as they were,
; on only once the kernel is no longer mapped
bdexit:	ld	a,(LIBIFF)		; back to the library: off
	or	a
	jr	z,bdx_1
	di
bdx_1:	ld	a,(UBANK)
	ld	(PIODA),a
	pop	af
	ld	(UBANK),a
	pop	iy
	pop	ix
	ld	sp,(usersp)
	ld	a,(BDIFF)
	or	a
	jr	z,bdx_2
	xor	a
	ld	(BDIFF),a
	ei
bdx_2:	ld	a,l
	ld	b,h
	ret

; C to the console and, with ^P on, the printer. Keeps the column.
kraw:	push	af
	call	conout
	ld	a,(scb+SCB_LIST)
	or	a
	call	nz,list
	ld	a,c
	cp	' '
	jr	nc,krw_1
	cp	0Dh
	jr	z,krw_cr
	cp	08h
	jr	nz,krw_9
	ld	a,(scb+SCB_COL)
	or	a
	jr	z,krw_9
	dec	a
	jr	krw_2
krw_cr:	xor	a
	jr	krw_2
krw_1:	cp	7Fh
	jr	z,krw_9
	ld	a,(scb+SCB_COL)
	inc	a
krw_2:	ld	(scb+SCB_COL),a
krw_9:	pop	af
	ret

; ------------------------------------------------------------------
; Console output. C = character. Keeps every register. The codes of
; Lobo's CP/M 3 BIOS (XCHARIO), a Soroc IQ-120's, which
; is the terminal WordStar was installed for: BEL, BS, TAB, LF, 0Bh up,
; 0Ch right, CR, 1Ah clear, 1Eh home, and ESC with * clear, Y erase to
; the end of the screen, T to the end of the line, E insert a line, R
; delete one, ) and ( the second style on and off, 0 and 1 the cursor
; off and on, = row col, each + 20h. Bit 7 is dropped, as Lobo's does.
crtout:	push	af
	push	bc
	push	de
	push	hl
	ld	a,VL_VIDEO		; window on video RAM 400h-7FFh
	ld	(VLATCH),a
	call	curoff
	res	7,c
	ld	a,(ESCST)
	or	a
	jp	nz,co_esc
	ld	a,c
	cp	20h
	jr	c,co_ctl
	ld	a,(DIM)			; the second style: 20h-5Fh to
	or	a			; 80h-BFh, 60h-7Fh to 00h-1Fh
	ld	a,c
	jr	z,co_pr
	sub	60h
	jr	nc,co_pr
	add	a,0C0h
co_pr:	ld	(hl),a			; HL is the cursor cell, from curoff
	ld	a,(CURCOL)
	inc	a
	cp	COLS
	jr	nc,co_wrap
	ld	(CURCOL),a
	inc	hl			; the next cell is the cursor's, with
	ld	a,h			; no need to work it out again: F3FFh
	cp	0F4h			; goes on at FC00h, FFFFh at F000h
	jr	nz,co_pr1
	ld	h,0FCh
co_pr1:	or	a
	jr	nz,co_pr2
	ld	h,0F0h
co_pr2:	call	curonh
	jr	co_end
co_wrap: xor	a
	ld	(CURCOL),a
	call	linefeed
	jr	co_done
co_ctl:	ld	hl,co_done		; the control codes return to co_done
	push	hl
	cp	0Dh
	jr	z,co_cr
	cp	0Ah
	jp	z,linefeed
	cp	08h
	jr	z,co_bs
	cp	09h
	jr	z,co_tab
	cp	07h
	jr	z,co_bel
	cp	0Bh
	jr	z,co_up
	cp	0Ch
	jr	z,co_rt
	cp	1Ah
	jp	z,clsbody
	cp	1Eh
	jr	z,co_home
	cp	1Bh
	ret	nz
	ld	a,1
	ld	(ESCST),a
	ret
co_cr:	xor	a
	ld	(CURCOL),a
	ret
co_bs:	ld	a,(CURCOL)
	or	a
	ret	z
	dec	a
	ld	(CURCOL),a
	ret
co_tab:	ld	a,(CURCOL)		; to the next multiple of 8
	or	7
	inc	a
	cp	COLS
	ret	nc
	ld	(CURCOL),a
	ret
co_bel:	ld	(BEEP),a
	ret
co_up:	ld	a,(CURROW)
	or	a
	ret	z
	dec	a
	ld	(CURROW),a
	ret
co_rt:	ld	a,(CURCOL)
	inc	a
	cp	COLS
	ret	nc
	ld	(CURCOL),a
	ret
co_home: xor	a
	ld	(CURROW),a
	ld	(CURCOL),a
	ret
co_done: call	curon
co_end:	ld	a,(VLCOPY)
	ld	(VLATCH),a
	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

; The bytes after ESC
co_esc:	ld	hl,co_done
	push	hl
	cp	2
	jr	z,co_row
	jr	nc,co_col
	xor	a			; the second byte
	ld	(ESCST),a
	ld	a,c
	cp	'='
	jr	z,co_eq
	cp	'*'
	jp	z,clsbody
	cp	'Y'
	jr	z,eos
	cp	'T'
	jr	z,eol
	cp	'E'
	jp	z,insline
	cp	'R'
	jp	z,delline
	cp	'('
	jr	z,co_nrm
	cp	')'
	jr	z,co_dim
	cp	'0'
	jr	z,co_hide
	cp	'1'
	ret	nz
	xor	a			; ESC 1: the cursor shows
	jr	co_cur
co_hide: ld	a,0FFh			; ESC 0: hidden
co_cur:	ld	(CURHID),a
	ret
co_nrm:	xor	a			; ESC (: the first style
	jr	co_sty
co_dim:	ld	a,1			; ESC ): the second
co_sty:	ld	(DIM),a
	ret
co_eq:	ld	a,2
	jr	co_st
co_row:	ld	a,c
	ld	(ESCROW),a
	ld	a,3
co_st:	ld	(ESCST),a
	ret
co_col:	xor	a
	ld	(ESCST),a
	ld	a,(ESCROW)		; out of range: ignored, as Lobo's
	sub	20h
	ret	c
	cp	ROWS
	ret	nc
	ld	b,a
	ld	a,c
	sub	20h
	ret	c
	cp	COLS
	ret	nc
	ld	(CURCOL),a
	ld	a,b
	ld	(CURROW),a
	ret

; Erase to the end of the screen, or of the line
eos:	call	eol
	ld	a,(CURROW)
eos_1:	inc	a
	cp	ROWS
	ret	nc
	call	rowblank		; keeps C, the row
	ld	a,c
	jr	eos_1
eol:	ld	de,(CURROW)		; E = the row, D = the column
	call	celloff
	ld	a,(CURCOL)
	ld	b,a
	ld	a,COLS
	sub	b
	ld	b,a			; B = the cells to the end of the row
	push	hl
	ld	e,b
	dec	e
	ld	d,0
	add	hl,de			; the last one's offset
	ld	a,h
	pop	hl
	xor	h
	and	04h
	jr	nz,eol_1		; across a 1K half: a cell at a time
	call	vaddr
	ld	(hl),' '
	dec	b
	ret	z
	ld	d,h
	ld	e,l
	inc	de
	ld	c,b
	ld	b,0
	ldir
	ret
eol_1:	push	hl
	call	vaddr
	ld	(hl),' '
	pop	hl
	inc	hl
	djnz	eol_1
	ret

; Insert a blank line at the cursor row, the rows below it down one;
; delete the cursor row, the rows below it up one. Above the middle row
; the rows above the cursor are fewer: they move instead, and the
; CRTC's start address moves a row, the 2K of video RAM a ring.
insline: ld	a,(CURROW)
	cp	ROWS/2
	jr	c,il_up
	ld	b,ROWS-1		; row B = row B - 1, from the bottom
il_1:	ld	a,(CURROW)
	cp	b
	jr	nc,rowblank		; the cursor row, in A
	ld	c,b
	dec	b
	call	rowcopy
	jr	il_1
il_up:	call	rscroll			; every row down one, then
	ld	b,0			; row B = row B + 1 down to the cursor's
il_2:	ld	a,(CURROW)
	cp	b
	ld	a,b
	jr	z,rowblank
	ld	c,b
	inc	b
	call	rowcopy
	jr	il_2
delline: ld	a,(CURROW)
	cp	ROWS/2
	jr	c,dl_dn
	ld	b,a			; row B = row B + 1, from the cursor down
dl_1:	ld	a,b
	cp	ROWS-1
	jr	nc,rowblank		; A = B = ROWS-1, the bottom row
	ld	c,b
	inc	b
	call	rowcopy
	jr	dl_1
dl_dn:	ld	b,a			; row B = row B - 1, from the cursor up,
dl_2:	ld	a,b			; then every row up one
	or	a
	jp	z,scroll
	ld	c,b
	dec	b
	call	rowcopy
	jr	dl_2

; Blank screen row A
rowblank: ld	c,a
	ld	b,0FFh
	; fall into rowcopy

; Screen row C = screen row B, or blanks if B is FFh. Keeps BC. A row
; that stays inside one 1K half of video RAM, most do, goes by LDIR.
rowcopy: push	bc
	ld	a,c
	call	rowoff
	ex	de,hl			; DE = the row written
	ld	a,b
	inc	a
	jr	z,rcp_bl
	dec	a
	call	rowoff			; HL = the row read
	call	rowx
	jr	c,rcp_sl
	ex	de,hl
	call	rowx
	ex	de,hl
	jr	c,rcp_sl
	ex	de,hl
	call	vaddr
	ex	de,hl
	call	vaddr
	ld	bc,COLS
	ldir
	pop	bc
	ret
rcp_sl:	ld	b,COLS			; across a half: a cell at a time
rcp_1:	push	hl
	push	de
	call	vaddr
	ld	c,(hl)
	ex	de,hl
	call	vaddr
	ld	(hl),c
	pop	de
	pop	hl
	inc	hl
	inc	de
	djnz	rcp_1
	pop	bc
	ret
rcp_bl:	ex	de,hl
	call	rowx
	jr	c,rcp_bs
	call	vaddr
	ld	(hl),' '
	ld	d,h
	ld	e,l
	inc	de
	ld	bc,COLS-1
	ldir
	pop	bc
	ret
rcp_bs:	ld	b,COLS
rcp_2:	push	hl
	call	vaddr
	ld	(hl),' '
	pop	hl
	inc	hl
	djnz	rcp_2
	pop	bc
	ret

; Carry set if the row at 2K offset HL runs over the end of its 1K
; half, at 400h or 800h. Keeps everything but A and the flags.
rowx:	ld	a,h
	and	03h
	xor	03h
	ret	nz			; NC: under 300h in its half
	ld	a,l
	cp	(400h-COLS+1) & 0FFh
	ccf
	ret

; HL = the 2K offset of screen row A. Keeps BC and DE.
rowoff:	push	de
	ld	e,a
	ld	d,0
	call	celloff
	pop	de
	ret

; The start a row back, every row down one, a row of whatever was in
; video RAM coming in at the top
rscroll: ld	hl,(SCRST)
	ld	de,-COLS
	add	hl,de
	ld	a,h
	and	07h
	ld	h,a
	ld	(SCRST),hl
	jp	setstart

; The window must be on video RAM
clsbody: ld	hl,VIDLO		; all 2K
	ld	de,VIDLO+1
	ld	bc,3FFh
	ld	(hl),' '
	ldir
	ld	hl,VIDWIN
	ld	de,VIDWIN+1
	ld	bc,3FFh
	ld	(hl),' '
	ldir
	ld	hl,0
	ld	(SCRST),hl
	call	setstart
	xor	a
	ld	(CURROW),a
	ld	(CURCOL),a
	ld	a,' '
	ld	(UNDER),a
	ret

linefeed: ld	a,(CURROW)
	cp	ROWS-1
	jr	nc,scroll
	inc	a
	ld	(CURROW),a
	ret

; Hardware scroll: blank the row about to come in, then move the start
; up a row. The cursor row stays the bottom row.
scroll:	ld	a,ROWS			; the row below the bottom one
	call	rowblank
	ld	hl,(SCRST)
	ld	de,COLS
	add	hl,de
	ld	a,h
	and	07h
	ld	h,a
	ld	(SCRST),hl
	; fall into setstart

; CRTC R12:R13 = SCRST, written during display timing so the CRTC never
; sees half of it
setstart: ld	hl,SYSFLG
ss1:	bit	6,(hl)
	jr	z,ss1
	ld	hl,(SCRST)
	ld	a,12
	ld	(CRTREG),a
	ld	a,h
	ld	(CRTBYT),a
	ld	a,13
	ld	(CRTREG),a
	ld	a,l
	ld	(CRTBYT),a
	ret

; HL = CPU address of the cursor cell
curaddr: ld	de,(CURROW)		; E = CURROW, D = CURCOL
	assert	CURCOL == CURROW+1
	; fall into celladdr

; HL = CPU address of screen row E, column D. Keeps BC.
celladdr: call	celloff
	jr	vaddr

; HL = the 2K offset of screen row E, column D. Keeps BC.
celloff: ld	a,e			; HL = row * 5 * 16, the row under 52
	add	a,a
	add	a,a
	add	a,e
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	e,d			; + column
	ld	d,0
	add	hl,de
	ld	de,(SCRST)
	add	hl,de
	ld	a,h
	and	07h
	ld	h,a
	ret

; The 2K screen offset in HL to its CPU address: 0-3FFh in VIDLO,
; 400h-7FFh in the window. Keeps BC and DE.
vaddr:	ld	a,h			; 0-3 to FCh-FFh, 4-7 to F0h-F3h
	and	07h
	add	a,0Ch
	or	0F0h
	ld	h,a
	ret
	assert	VIDLO == 0FC00h && VIDWIN == 0F000h

curon:	call	curaddr
curonh:	ld	(CURHL),hl		; HL = the cursor cell
	xor	a
	ld	(BLINKO),a
	ld	a,(hl)
	ld	(UNDER),a
	ld	a,(CURHID)		; ESC 0: none shown
	or	a
	ret	nz
	ld	(hl),CURSOR
	ret

; HL = the cursor cell, which crtout's co_pr uses. Only the console
; moves the cursor or the start, and between its calls the cell is
; the one curon used.
curoff:	ld	hl,(CURHL)
	ld	a,(UNDER)
	ld	(hl),a
	ret

; ------------------------------------------------------------------
; Console input. const: A = FFh and NZ if a key is waiting, else 0 and Z.
; conin: A = the next key, waiting for one.
kbdst:	ld	a,(KTAKE)
	ld	b,a
	ld	a,(KFILL)
	sub	b
	ret	z
	ld	a,0FFh
	ret

; A = the next key without taking it, or 0
kpeek:	push	hl
	ld	a,(KTAKE)
	ld	l,a
	ld	a,(KFILL)
	cp	l
	ld	a,0
	jr	z,kk_1
	ld	h,high KRING
	ld	a,(hl)
kk_1:	pop	hl
	ret

kbdin:	push	bc
	push	hl
ci1:	call	kbdst
	jr	nz,ci2
	call	blink
	jr	ci1
ci2:	call	blinkon			; shown again for the program
	ld	a,(KTAKE)
	ld	l,a
	ld	h,high KRING
	inc	a
	and	7Fh
	ld	(KTAKE),a
	ld	a,(hl)
	pop	hl
	pop	bc
	ret

; While conin waits for a key, the cursor cell goes between the cursor
; and the character under it, 16 ticks each, about 2 Hz. Only here, not
; from the tick: a program that draws its own screen or font polls, and
; is left alone. A cell that no longer holds what the console put there
; is not changed. Not with ESC 0.
blink:	ld	a,(CURHID)
	or	a
	ret	nz
	ld	a,(TICKS)
	and	10h
	jr	z,blinkon
	ld	a,(BLINKO)
	or	a
	ret	nz			; off already
	ld	b,CURSOR
	ld	a,(UNDER)
	ld	c,a
	call	blsw
	ret	nz
	ld	a,1
	ld	(BLINKO),a
	ret
blinkon: ld	a,(BLINKO)
	or	a
	ret	z
	xor	a
	ld	(BLINKO),a
	ld	a,(UNDER)
	ld	b,a
	ld	c,CURSOR
	; fall into blsw

; The cursor cell to C if it holds B, Z if it did
blsw:	ld	a,VL_VIDEO
	ld	(VLATCH),a
	ld	hl,(CURHL)
	ld	a,(hl)
	cp	b
	jr	nz,bls_1
	ld	(hl),c
bls_1:	push	af
	ld	a,(VLCOPY)
	ld	(VLATCH),a
	pop	af
	ret

; ------------------------------------------------------------------
; The tick, 61 Hz, mode 2. Clears the tick and scans the keys.
; It runs on its own stack: the program's may have no room for it.
tick:	ld	(ISRSP),sp
	ld	sp,ISRSTK
	push	af
	push	bc
	push	de
	push	hl
	push	ix
	ld	hl,TICKS
	inc	(hl)
	ld	a,(SYSCLR)		; and on into kscan, which returns

; Key scan, as Lobo's: each row is compared with the two scans before it
; (T1, T2). A key is new when down now but in neither, and up when it was
; down only in T2. A held key repeats after 44 ticks, then every 3. At
; most two new keys are taken a scan.
kscan:	ld	hl,RPTIME
	ld	a,(hl)
	or	a
	jr	z,ks0
	dec	(hl)
	jr	nz,ks0
	ld	(hl),3
	ld	a,(KEY)
	call	kdo
ks0:	ld	a,2
	ld	(KBLOCK),a
	ld	hl,keytab
	ld	ix,KPREV
	ld	de,MATRIX+1
ks1:	ld	a,(de)
	ld	b,a			; T0
	ld	c,(ix+0)		; T1
	cp	c
	jr	nz,ks2
	cp	(ix+8)
	jr	z,ks3
ks2:	and	(ix+8)
	or	c
	ld	c,a			; T1 also gets keys down in T0 and T2
	ld	a,(ix+8)
	or	c
	cpl
	and	b
	call	nz,kpress
	ld	a,c
	or	b
	cpl
	and	(ix+8)
	call	nz,krelease
	ld	(ix+8),c
	ld	(ix+0),b
ks3:	inc	ix
	ld	bc,8
	add	hl,bc
	rlc	e
	jr	nc,ks1
	pop	ix
	pop	hl
	pop	de
	pop	bc
	pop	af
	ld	sp,(ISRSP)
	ei
	reti

; A = keys newly down in this row, HL = the row in keytab
kpress:	push	hl
kp1:	srl	a
	jr	nc,kp3
	push	af
	ld	a,(KBLOCK)
	or	a
	jr	z,kp2
	ld	a,(hl)
	or	a
	jr	z,kp2
	cp	K_CAPS			; F1, Caps Lock, no repeat
	jr	nz,kp1a
	ld	a,(KCAPS)
	xor	20h
	ld	(KCAPS),a
	jr	kp2
kp1a:	ld	(KEY),a
	call	kdo
	ld	a,44
	ld	(RPTIME),a
	ld	a,(KBLOCK)
	dec	a
	ld	(KBLOCK),a
kp2:	pop	af
kp3:	inc	hl
	or	a
	jr	nz,kp1
	pop	hl
	ret

; A = keys newly up in this row: stop the repeat if one is the last key
krelease: push	hl
kr1:	srl	a
	jr	nc,kr3
	push	af
	ld	a,(KEY)
	cp	(hl)
	jr	nz,kr2
	xor	a
	ld	(RPTIME),a
kr2:	pop	af
kr3:	inc	hl
	or	a
	jr	nz,kr1
	pop	hl
	ret

; A = key from keytab. Apply CTRL and SHIFT (row 7 bits 7 and 0) and put
; it in the ring. CTRL with SHIFT gives nothing. SHIFT flips letters and
; @[\]^_ by bit 5, and the digits and punctuation by bit 4, the TRS-80
; layout. Caps Lock flips letters alone, after SHIFT, as Lobo's BIOS.
kdo:	push	bc
	push	hl
	ld	hl,MATRIX+80h
	ld	c,(hl)
	bit	7,c
	jr	z,kd1
	bit	0,c
	jr	nz,kd5
	cp	'@'
	jr	c,kd1
	and	1Fh
	jr	kd4
kd1:	bit	0,c
	jr	z,kd4
	cp	'!'
	jr	c,kd4
	cp	'0'
	jr	z,kd4
	cp	'@'
	jr	nc,kd2
	xor	10h
	jr	kd4
kd2:	xor	20h
kd4:	ld	c,a
	and	0DFh
	cp	'A'
	jr	c,kd4a
	cp	'Z'+1
	jr	nc,kd4a
	ld	a,(KCAPS)
	xor	20h
	xor	c
	ld	c,a
kd4a:	ld	a,(KFILL)
	ld	l,a
	ld	h,high KRING
	ld	(hl),c
	inc	a
	and	7Fh
	ld	b,a
	ld	a,(KTAKE)
	cp	b
	jr	z,kd5			; ring full, drop the key
	ld	a,b
	ld	(KFILL),a
kd5:	pop	hl
	pop	bc
	ret

; The key matrix, as the Technical Reference Manual lays it out. 0 is no key.
keytab:	db	'@','a','b','c','d','e','f','g'
	db	'h','i','j','k','l','m','n','o'
	db	'p','q','r','s','t','u','v','w'
	db	'x','y','z','[',5Ch,']','^','_'
	db	'0','1','2','3','4','5','6','7'
	db	'8','9',':',';',',','-','.','/'
	db	0Dh,08h,03h,1Ch,1Dh,1Eh,1Fh,' '	; ENTER CLEAR BREAK UP DOWN LEFT RIGHT SPACE,
					; the arrows as Lobo's BIOSes
	db	0,K_CAPS,0,0,0,1Bh,0,0		; SHIFT F1-F4 ESC - CTRL
K_CAPS	equ	0FCh				; Lobo's code for it

COMMON_END:
	ent
COMMON_LEN	equ	COMMON_END-COMMON_ORG
	assert	COMMON_ORG+COMMON_LEN <= BLK

; Cold start, from the boot sector: block at F000h, A2 low, A1 high.
; It runs in A2, where the boot sector loaded it after the common part,
; so it takes no common memory. kmain clears the kernel's variables
; over it once it is done with.
cold:	di
	ld	sp,STKTOP
	ld	hl,CVARS
	ld	de,CVARS+1
	ld	bc,255
	ld	(hl),0
	ldir
	ld	(kstk),sp
	ld	a,VL_ROM
	ld	(VLCOPY),a

	ld	hl,crtctab		; 80 x 24, 9-line cells
	ld	c,0
crt1:	ld	a,c
	ld	(CRTREG),a
	ld	a,(hl)
	ld	(CRTBYT),a
	inc	hl
	inc	c
	ld	a,c
	cp	16
	jr	c,crt1

	ld	a,0Eh			; the SIO as Lobo's BIOS sets it: 9600
	ld	(BAUDA),a		; baud, the boot ROM leaves it reset
	ld	(BAUDB),a
	ld	hl,siotab
	ld	de,SIOCA
	call	sioset
	ld	de,SIOCB
	call	sioset

	call	ramtest
	ld	a,VL_VIDEO		; clear the screen
	ld	(VLATCH),a
	call	clsbody
	call	curon
	ld	a,VL_ROM
	ld	(VLATCH),a

	ld	a,IVPAGE		; the tick, in mode 2, vector FEh
	ld	i,a
	ld	hl,tick
	ld	(IVPAGE*256+0FEh),hl
	im	2
	ld	a,(SYSCLR)		; drop a tick already waiting
	ei
	jp	kmain

; 10 bytes at HL to the SIO control port at DE
sioset:	ld	b,10
sio_1:	ld	a,(hl)
	ld	(de),a
	inc	hl
	djnz	sio_1
	ret

; Lobo's SIO tables (XDATA.MAC in its CP/M 3 BIOS): reset, x16
; clock and 1.5 stop bits, receiver and transmitter on with auto
; enables, DTR and RTS on, no interrupts. A 8 bits no parity, B 7 bits
; odd parity.
siotab:	db	18h,18h,14h,48h,13h,0E1h,15h,0EAh,11h,0
	db	18h,18h,14h,49h,13h,61h,15h,0AAh,11h,0

; Lobo's CRTC table, 80 x 24
crtctab: db	119,80,97,6,27,12,24,26,0,8,0,0,0,0,0,0
