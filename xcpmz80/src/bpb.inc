; The BPB of the xcpmz80 floppy, boot sector bytes 0Bh to 3Dh: the
; one definition of the disk format, used by the boot sector and FORMAT.
; mkdisk.py reads it from the assembled boot sector.
	macro	FLOPPYBPB
	dw	512			; bytes per sector
	db	2			; sectors per cluster, 1K
	dw	RSVD			; reserved: the boot sector and system
	db	2			; FATs
	dw	64			; root directory entries
	dw	TRACKS*SPT		; total sectors
	db	0F0h			; media
	dw	2			; sectors per FAT
	dw	SPT			; sectors per track
	dw	1			; heads
	dd	0			; hidden sectors
	dd	0			; total sectors, 32 bit
	db	0			; drive number
	db	0			; 1: two sides, sectors from 0
	db	29h			; extended boot signature
	dd	4D583830h		; serial
	db	"XCPMZ80    "		; volume label
	db	"FAT12   "
	endm
