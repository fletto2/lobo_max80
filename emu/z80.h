/* Z80 CPU core for the MAX-80 emulator. */
#ifndef Z80_H
#define Z80_H

#include <stdint.h>

typedef struct z80 {
	/* Main and alternate registers, Z80 encoding order B C D E H L F A */
	uint8_t r[8], alt[8];
	uint16_t ix, iy, sp, pc;
	uint8_t i, rr;		/* I and R */
	uint16_t wz;		/* MEMPTR, for BIT n,(HL) flags */
	int iff1, iff2, im, halted;
	int ei_wait;		/* EI takes effect after the next instruction */
	int ld_air;		/* the last instruction was LD A,I or LD A,R */
	int irq;		/* INT line held low */
	uint8_t irq_vector;	/* data bus during interrupt acknowledge */
	int nmi;		/* NMI edge pending */
	unsigned long long cycles;

	void *ctx;
	uint8_t (*read)(void *ctx, uint16_t addr);
	void (*write)(void *ctx, uint16_t addr, uint8_t val);
	uint8_t (*in)(void *ctx, uint16_t port);
	void (*out)(void *ctx, uint16_t port, uint8_t val);
} z80;

void z80_reset(z80 *cpu);
/* Run one instruction or accept one interrupt. Returns T-states. */
int z80_step(z80 *cpu);

#endif
