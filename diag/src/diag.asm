; MAX-80 diagnostic disk: boots with no OS and tests the hardware
; from a menu. The output is the boot sector (512 bytes), then the
; program it loads to 1000h. Addresses are xcpmz80's (its src/hw.inc).

	include	"../../xcpmz80/src/hw.inc"
	include	"vars.inc"
	include	"boot.asm"		; file offset 0, runs at 0400h
	org	1000h			; file offset 200h
	include	"main.asm"
	include	"setup.asm"
	include	"cons.asm"
	include	"keys.asm"
	include	"memtest.asm"
	include	"mainram.asm"
	include	"screens.asm"
	include	"keytest.asm"
	include	"disktest.asm"
	include	"vtime.asm"
	include	"dipsw.asm"
	include	"serial.asm"
	include	"printer.asm"
	include	"rtc.asm"
	include	"bus.asm"
	include	"wthru.asm"
	include	"memtime.asm"
FONT:	incbin	"../../xcpmz80/src/font.bin"	; 2K, font RAM 1 then 2
PROG_END:

PROGSEC	equ	(PROG_END-1000h+511)/512
	assert	PROG_END <= SIG
