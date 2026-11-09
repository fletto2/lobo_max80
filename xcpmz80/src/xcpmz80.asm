; xcpmz80: a FAT-native CP/M compatible OS for the Lobo MAX-80.
; Build: sjasmplus --raw=build/xcpmz80.sys src/xcpmz80.asm
;
; The output is the boot sector (512 bytes), then the system image the
; boot sector loads to A2 at 1000h: the kernel, the font, and the common
; part, which the boot sector copies to A1 at DF00h.

	include	"hw.inc"
	include	"bpb.inc"
	include	"boot.asm"		; file offset 0, runs at 0400h
	include	"kernel.asm"		; file offset 200h, runs at 1000h
FONT_LOAD:
	incbin	"../build/font.bin"	; 2K, to font RAM
	include	"common.asm"		; runs at DF00h
IMAGE_END:
	include	"vars.inc"		; kernel variables, over the font copy

SYSSEC	equ	(IMAGE_END-1000h+511)/512
	assert	IMAGE_END <= 8000h		; the load stays in the low half
	assert	SYSSEC <= RSVD-1		; and in the reserved tracks
	assert	19+SYSSEC <= RSVD		; after a 1.44M floppy's copy too
