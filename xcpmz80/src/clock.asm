; xcpmz80 clock. Runs in A2. The MSM5832 behind the PIO, as the MAX-80
; Technical Reference Manual and Lobo's TIMESET.MAC describe it: write
; 20h + register to port B, read the digit from port A bits 3-0.
; Registers 0-12 are seconds, minutes, hours, day of week, date, month
; and year, units then tens. A clock that reads nonsense gives 1 Jan 2026, 00:00.

; Read the clock into clk (13 digits), twice until two reads agree
rdclk:	ld	hl,clk			; clk, then clk2 just after it
	call	rdclk1
	call	rdclk1
	ld	hl,clk
	ld	de,clk2
	ld	b,13
rk_1:	ld	a,(de)
	cp	(hl)
	jr	nz,rdclk
	inc	hl
	inc	de
	djnz	rk_1
	ret
rdclk1:	ld	b,20h			; READ and the register
rk_2:	ld	a,b
	ld	(PIODB),a
	ld	a,4			; the digit takes up to 6 us after the
rk_3:	dec	a			; address (Appendix E tRA), wait 12
	jr	nz,rk_3
	ld	a,(PIODA)
	and	0Fh
	ld	(hl),a
	inc	hl
	inc	b
	ld	a,b
	cp	20h+13
	jr	c,rk_2
	xor	a
	ld	(PIODB),a
	ret

; From clk: year (full), month, day, hour (24), minute, second, binary,
; into cyear, cmon, cday, chour, cmin, csec. Nonsense gives 2026-01-01.
clkget:	call	rdclk
	ld	hl,clk+12		; year tens, then each field down
	call	digits
	cp	78			; 78 to 99 are 19xx
	jr	nc,cg_1
	add	a,100
cg_1:	add	a,low 1900
	ld	(cyear),a
	ld	a,high 1900
	adc	a,0
	ld	(cyear+1),a
	call	digits			; month
	ld	(cmon),a
	dec	a
	cp	12
	jr	nc,cg_bad
	ld	a,(hl)			; date tens: bit 2 is the leap flag
	and	03h
	ld	(hl),a
	call	digits
	ld	(cday),a
	dec	a
	cp	31
	jr	nc,cg_bad
	dec	hl			; past the day of the week
	ld	a,(hl)			; hours tens: bit 3 24-hour, bit 2 PM
	ld	b,a
	and	03h
	ld	(hl),a
	call	digits
	bit	3,b
	jr	nz,cg_2
	cp	12			; 12-hour: 12 AM is 0
	jr	nz,cg_3
	xor	a
cg_3:	bit	2,b
	jr	z,cg_2
	add	a,12
cg_2:	ld	(chour),a
	cp	24
	jr	nc,cg_bad
	call	digits			; minute
	ld	(cmin),a
	cp	60
	jr	nc,cg_bad
	call	digits			; second
	ld	(csec),a
	cp	60
	ret	c
cg_bad:	ld	hl,cg_def
	ld	de,cyear
	ld	bc,7
	ldir
	ret
cg_def:	dw	2026			; cyear, cmon, cday, chour, cmin, csec
	db	1,1,0,0,0

; A = the two digits at HL (tens) and HL-1 (units), HL down 2. Keeps B.
digits:	ld	a,(hl)
	ld	c,a			; tens * 10
	add	a,a
	add	a,a
	add	a,c
	add	a,a
	dec	hl
	add	a,(hl)
	dec	hl
	ret

; FAT date in DE, time in BC, now
fatnow:	call	clkget
	ld	hl,(cyear)		; ((year - 1980) * 16 + month) * 32 + day
	ld	de,-1980
	add	hl,de
	jr	c,fnw_1
	ld	hl,0
fnw_1:	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,(cmon)
	or	l
	ld	l,a
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,(cday)
	or	l
	ld	l,a
	ex	de,hl
	ld	a,(chour)		; (hour * 64 + minute) * 32 + second / 2
	rrca
	rrca
	ld	h,a
	and	0C0h
	ld	l,a
	xor	h
	ld	h,a
	ld	a,(cmin)
	or	l
	ld	l,a
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,(csec)
	srl	a
	or	l
	ld	c,a
	ld	b,h
	ret

; CP/M 3's time now: HL = days since 31 Dec 1977, B = hour, C = minute,
; A = second, all three BCD
cpmnow:	call	clkget
	call	f2c_1
	ld	a,(csec)
	jp	bcd

; A FAT date DE and time BC as CP/M 3's: HL = days, B hour, C minute
fat2cpm: ld	a,e			; day
	and	1Fh
	ld	(cday),a
	ld	h,d			; month: bits 8-5
	ld	l,e
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,h
	and	0Fh
	ld	(cmon),a
	jr	z,f2c_0			; a date of 0: no stamp
	ld	a,d			; year: bits 15-9
	srl	a
	ld	l,a
	ld	h,0
	ld	de,1980
	add	hl,de
	ld	(cyear),hl
	ld	a,b			; hour: bits 15-11
	rrca
	rrca
	rrca
	and	1Fh
	ld	(chour),a
	ld	h,b			; minute: bits 10-5
	ld	l,c
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	a,h
	and	3Fh
	ld	(cmin),a
f2c_1:	call	days
	ld	a,(chour)
	call	bcd
	ld	b,a
	ld	a,(cmin)
	call	bcd
	ld	c,a
	ret
f2c_0:	ld	hl,0
	ld	b,h
	ld	c,l
	ret

; HL = days from 31 Dec 1977 to cyear-cmon-cday (1 Jan 1978 is 1)
days:	ld	a,(cyear)
	sub	low 1978		; n = the whole years before this one
	ld	hl,0
	ld	de,365
	ld	b,a
	inc	b
	jr	dy_2
dy_1:	add	hl,de
dy_2:	djnz	dy_1
	ld	c,a			; and the leap days: (n + 1) / 4, or
	ld	a,(cmon)		; (n + 2) / 4 from March on
	ld	b,a
	cp	3
	ld	a,c
	sbc	a,-2
	srl	a
	srl	a
	ld	c,a
	ld	de,mdays		; whole months before this one
dy_3:	dec	b
	jr	z,dy_4
	ld	a,(de)
	add	a,l
	ld	l,a
	jr	nc,dy_5
	inc	h
dy_5:	inc	de
	jr	dy_3
dy_4:	ld	a,(cday)
	add	a,c
	ld	e,a
	ld	d,0
	add	hl,de
	ret
mdays:	db	31,28,31,30,31,30,31,31,30,31,30,31

; A (0-99) to BCD. Keeps BC.
bcd:	push	bc
	ld	b,a
	inc	b
	xor	a
	jr	bc_2
bc_1:	inc	a
	daa
bc_2:	djnz	bc_1
	pop	bc
	ret
