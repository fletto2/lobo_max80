; xcpmz80: MAX-80 hardware and the memory plan.
; Addresses from the MAX-80 Technical Reference Manual. The I/O block
; sits at F000h once the boot sector has moved it. Before that it is at
; 0000h, and the boot sector uses the offsets alone (B_ names).

; I/O block at F000h
BLK		equ	0F000h
MLATCH		equ	BLK+7D8h	; floppy select
VLATCH		equ	BLK+7DCh	; block address, 40 columns, window
SYSCLR		equ	BLK+7E0h	; read: flags, and clears the tick
CRTREG		equ	BLK+7E0h	; write: CRTC register number
SYSFLG		equ	BLK+7E1h	; read: flags, clears nothing
CRTBYT		equ	BLK+7E1h	; write: CRTC register value
PSTAT		equ	BLK+7E8h	; printer: bit 7 busy
PDATA		equ	BLK+7E8h
SIODA		equ	BLK+7E4h	; SIO channel A data
SIOCA		equ	BLK+7E5h	; SIO channel A control, RR0
SIODB		equ	BLK+7E6h	; SIO channel B data
SIOCB		equ	BLK+7E7h	; SIO channel B control
BAUDA		equ	BLK+7D0h	; COM8116 rate code, channel A
BAUDB		equ	BLK+7D4h	; and B
FSTAT		equ	BLK+7ECh	; FDC, every byte complemented
FCTRL		equ	BLK+7ECh
FTRACK		equ	BLK+7EDh
FSECTOR		equ	BLK+7EEh
FDATA		equ	BLK+7EFh
UDATA		equ	BLK+7F0h	; SASI data
UDATAHS		equ	BLK+7F1h	; SASI data, ACK done by the hardware
USTAT		equ	BLK+7F4h	; 7 DRQ-, 6 INTRQ-, 4 C/D, 2 BSY, 0 REQ
UCTRL		equ	BLK+7F4h	; 2 RST, 1 SEL, 0 ACK
PIODB		equ	BLK+7FEh	; clock register and control
PIOCA		equ	BLK+7FDh
PIOCB		equ	BLK+7FFh
BEEP		equ	BLK+7F8h	; any write beeps
DIPSW		equ	BLK+7F8h
PIODA		equ	BLK+7FCh	; bank select, bits 7-4
MATRIX		equ	BLK+800h	; key rows at +1, +2, +4 ... +80h
VIDLO		equ	BLK+0C00h	; video RAM 000h-3FFh
VIDWIN		equ	BLK		; video RAM 400h-7FFh, window 2

; The same registers with the block at 0000h, as the boot ROM leaves it
B_VLATCH	equ	07DCh
B_PIODA		equ	07FCh
ROMREAD		equ	0003h		; the boot ROM's sector read
MLCOPY		equ	07D8h		; and its RAM copy of MLATCH, at boot

VL_ROM		equ	0F0h		; VLATCH: block at F000h, window = ROM
VL_VIDEO	equ	0F2h		; the same, window = video RAM 400h-7FFh

; PIO port A: the high half is always A1, common memory. Bits 5-4 pick
; the low half, as Lobo's CP/M 3 ?BANK does: A2 for the system, B1 for
; programs, B2 spare.
BANK_SYS	equ	10h
BANK_TPA	equ	20h
BANK_B2		equ	30h
LIBFN		equ	200		; BDOS function: a call into the C library

; Common RAM in the holes of the I/O block, A1's own DRAM
CBUF		equ	0F400h		; 128-byte bounce buffer, kernel <-> user
CFCB		equ	0F480h		; the caller's FCB, copied in, 36 bytes
CVARS		equ	0F500h		; common variables, 256 bytes
STKTOP		equ	0F700h		; system stack, F600h-F6FFh
ISRSTK		equ	0F7C0h		; the tick's stack, from F700h
FMTBUF		equ	8000h		; FORMAT's track, in the TPA's common part
KRING		equ	0F900h		; key ring, 128 bytes, page aligned
ALV		equ	0F980h		; allocation vector for function 27
ALVSZ		equ	512
DPB		equ	0FB80h		; the made-up DPB for function 31
XDPH		equ	0FBA0h		; DRVTBL's DPHs, 16 bytes a drive
IVPAGE		equ	0FBh		; I register, the vector is at FBFEh

; Floppy format: 8-inch, single sided, 77 tracks of 17 x 512, MFM, as
; Lobo's CP/M 3. Tracks 0-3 are the FAT reserved sectors and hold the
; boot sector and the system.
SPT		equ	17
TRACKS		equ	77
RSVD		equ	4*SPT

; Screen
COLS		equ	80
ROWS		equ	24
CURSOR		equ	7Fh		; a shade in our font
