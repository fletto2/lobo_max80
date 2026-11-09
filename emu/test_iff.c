/* An interrupt accepted right after LD A,I makes P/V read 0 on an NMOS
 * Z80, and iffget (xcpmz80/src/common.asm) must still see interrupts on.
 * plain[] reads P/V once and is fooled: it sees interrupts off. checked[]
 * is iffget as assembled, which reads P/V a second time when the first
 * says off, and sees them on. test.sh in xcpmz80 checks that these are
 * the bytes assembled. */
#include <stdio.h>
#include <string.h>
#include "z80.h"

static uint8_t mem[65536];

static uint8_t rd(void *ctx, uint16_t a) { (void)ctx; return mem[a]; }
static void wr(void *ctx, uint16_t a, uint8_t v) { (void)ctx; mem[a] = v; }

/* What the routine gives, with the interrupt right after its LD A,I */
static int run(const uint8_t *code, int n)
{
	z80 c;
	memset(&c, 0, sizeof(c));
	memset(mem, 0, sizeof(mem));
	c.read = rd;
	c.write = wr;
	z80_reset(&c);
	mem[0x38] = 0xfb;		/* EI */
	mem[0x39] = 0xed;		/* RETI */
	mem[0x3a] = 0x4d;
	memcpy(mem + 0x200, code, n);
	c.pc = 0x200;
	c.sp = 0x8000;
	c.im = 1;
	c.iff1 = c.iff2 = 1;
	mem[0x7fff] = 0x01;		/* back to a HALT at 0100h */
	mem[0x7ffe] = 0x00;
	c.sp = 0x7ffe;
	mem[0x100] = 0x76;
	z80_step(&c);			/* LD A,I */
	c.irq = 1;
	z80_step(&c);			/* the interrupt */
	c.irq = 0;
	for (int i = 0; i < 100 && !c.halted; i++)
		z80_step(&c);
	return c.halted ? c.r[7] : -1;
}

int main(void)
{
	static const uint8_t plain[] = { 0xed, 0x57, 0xf3, 0x3e, 0x00, 0xe0, 0x3d, 0xc9 };
	static const uint8_t checked[] = {
		0xed, 0x57, 0xea, 0x07, 0x02, 0xed, 0x57,
		0xf3, 0x3e, 0x00, 0xe0, 0x3d, 0xc9
	};
	int a = run(plain, sizeof(plain)), b = run(checked, sizeof(checked));
	printf("one read of P/V %d, iffget %d\n", a, b);
	return a == 0 && b == 0xff ? 0 : 1;
}
