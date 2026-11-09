; MAX-80 boot disk monitor: boots with no
; OS, for looking at RAM by hand and for loading small programs over
; serial. The boot sector, console, keys and setup are the diag's. The
; output is the boot sector (512 bytes), then the program it loads to
; 1000h.

	include	"../../xcpmz80/src/hw.inc"
	include	"../../diag/src/vars.inc"
	include	"vars.inc"
	include	"../../diag/src/boot.asm"	; file offset 0, runs at 0400h
	org	1000h				; file offset 200h
	include	"main.asm"
	include	"cmds.asm"
	include	"srec.asm"
	include	"../../diag/src/setup.asm"
	include	"../../diag/src/cons.asm"
	include	"../../diag/src/keys.asm"
FONT:	incbin	"../../xcpmz80/src/font.bin"	; 2K, font RAM 1 then 2
PROG_END:

PROGSEC	equ	(PROG_END-1000h+511)/512
	assert	PROG_END <= 3800h
