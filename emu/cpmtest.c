/*
 * Run a CP/M .COM program on the bare Z80 core, for CPU tests such as
 * ZEXDOC. Flat 64K RAM, BDOS functions 2 and 9 only, exits when the
 * program jumps to 0.
 *
 * Usage: cpmtest PROGRAM.COM
 */
#include <stdio.h>
#include <stdlib.h>
#include "z80.h"

static uint8_t mem[65536];

static uint8_t rd(void *ctx, uint16_t a)
{
	(void)ctx;
	return mem[a];
}

static void wr(void *ctx, uint16_t a, uint8_t v)
{
	(void)ctx;
	mem[a] = v;
}

int main(int argc, char **argv)
{
	z80 cpu = { 0 };
	FILE *f;

	if (argc != 2) {
		fprintf(stderr, "usage: cpmtest PROGRAM.COM\n");
		return 2;
	}
	f = fopen(argv[1], "rb");
	if (!f) {
		perror(argv[1]);
		return 2;
	}
	fread(mem + 0x100, 1, 0xfe00, f);
	fclose(f);

	cpu.read = rd;
	cpu.write = wr;
	z80_reset(&cpu);
	cpu.pc = 0x100;
	cpu.sp = 0xf000;
	/* BDOS entry at 5 is a RET, the call is handled below */
	mem[5] = 0xc9;
	mem[6] = 0x00;
	mem[7] = 0xf0;

	for (;;) {
		if (cpu.pc == 0)
			break;
		if (cpu.pc == 5) {
			uint8_t fn = cpu.r[1];
			if (fn == 2)
				putchar(cpu.r[3]);
			else if (fn == 9) {
				uint16_t a = cpu.r[2] << 8 | cpu.r[3];
				while (mem[a] != '$')
					putchar(mem[a++]);
			}
			fflush(stdout);
		}
		z80_step(&cpu);
	}
	printf("\n%llu T-states\n", cpu.cycles);
	return 0;
}
