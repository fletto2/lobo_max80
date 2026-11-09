/*
 * Z80 CPU core for the MAX-80 emulator.
 *
 * Decodes with the x/y/z/p/q split of the opcode byte. Covers every
 * documented instruction, the undocumented IX/IY halves, SLL and the
 * DD CB / FD CB register copies, and the X/Y flag bits. Cycle counts are
 * the documented ones, approximate for some prefixed forms.
 */
#include "z80.h"

#define FC 0x01
#define FN 0x02
#define FP 0x04
#define FX 0x08
#define FH 0x10
#define FY 0x20
#define FZ 0x40
#define FS 0x80

#define A (c->r[7])
#define F (c->r[6])
#define BC ((uint16_t)(c->r[0] << 8 | c->r[1]))
#define DE ((uint16_t)(c->r[2] << 8 | c->r[3]))
#define HL ((uint16_t)(c->r[4] << 8 | c->r[5]))

static uint8_t sz53[256], sz53p[256];
static int tables_ready;

static const uint8_t cyc_main[256] = {
	4, 10, 7, 6, 4, 4, 7, 4, 4, 11, 7, 6, 4, 4, 7, 4,
	8, 10, 7, 6, 4, 4, 7, 4, 12, 11, 7, 6, 4, 4, 7, 4,
	7, 10, 16, 6, 4, 4, 7, 4, 7, 11, 16, 6, 4, 4, 7, 4,
	7, 10, 13, 6, 11, 11, 10, 4, 7, 11, 13, 6, 4, 4, 7, 4,
	4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
	4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
	4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
	7, 7, 7, 7, 7, 7, 4, 7, 4, 4, 4, 4, 4, 4, 7, 4,
	4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
	4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
	4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
	4, 4, 4, 4, 4, 4, 7, 4, 4, 4, 4, 4, 4, 4, 7, 4,
	5, 10, 10, 10, 10, 11, 7, 11, 5, 10, 10, 0, 10, 17, 7, 11,
	5, 10, 10, 11, 10, 11, 7, 11, 5, 4, 10, 11, 10, 0, 7, 11,
	5, 10, 10, 19, 10, 11, 7, 11, 5, 4, 10, 4, 10, 0, 7, 11,
	5, 10, 10, 4, 10, 11, 7, 11, 5, 6, 10, 4, 10, 0, 7, 11,
};

static void init_tables(void)
{
	for (int i = 0; i < 256; i++) {
		int p = 1;
		for (int b = 0; b < 8; b++)
			p ^= (i >> b) & 1;
		sz53[i] = (i & (FS | FX | FY)) | (i ? 0 : FZ);
		sz53p[i] = sz53[i] | (p ? FP : 0);
	}
	tables_ready = 1;
}

static inline uint8_t rd(z80 *c, uint16_t a)
{
	return c->read(c->ctx, a);
}

static inline void wr(z80 *c, uint16_t a, uint8_t v)
{
	c->write(c->ctx, a, v);
}

static inline uint8_t fetch(z80 *c)
{
	return rd(c, c->pc++);
}

static inline uint16_t fetch16(z80 *c)
{
	uint16_t l = fetch(c);
	return l | fetch(c) << 8;
}

static inline uint16_t rd16(z80 *c, uint16_t a)
{
	return rd(c, a) | rd(c, (uint16_t)(a + 1)) << 8;
}

static inline void wr16(z80 *c, uint16_t a, uint16_t v)
{
	wr(c, a, v & 0xff);
	wr(c, (uint16_t)(a + 1), v >> 8);
}

static inline void push(z80 *c, uint16_t v)
{
	c->sp -= 2;
	wr16(c, c->sp, v);
}

static inline uint16_t pop(z80 *c)
{
	uint16_t v = rd16(c, c->sp);
	c->sp += 2;
	return v;
}

static inline void inc_r(z80 *c)
{
	c->rr = (c->rr & 0x80) | ((c->rr + 1) & 0x7f);
}

/* x is the index mode: 0 HL, 1 IX, 2 IY */
static uint16_t get_hl(z80 *c, int x)
{
	return x == 0 ? HL : x == 1 ? c->ix : c->iy;
}

static void set_hl(z80 *c, int x, uint16_t v)
{
	if (x == 0) {
		c->r[4] = v >> 8;
		c->r[5] = v;
	} else if (x == 1)
		c->ix = v;
	else
		c->iy = v;
}

/* rp table: BC DE HL SP */
static uint16_t rp_get(z80 *c, int p, int x)
{
	switch (p) {
	case 0: return BC;
	case 1: return DE;
	case 2: return get_hl(c, x);
	default: return c->sp;
	}
}

static void rp_set(z80 *c, int p, int x, uint16_t v)
{
	switch (p) {
	case 0: c->r[0] = v >> 8; c->r[1] = v; break;
	case 1: c->r[2] = v >> 8; c->r[3] = v; break;
	case 2: set_hl(c, x, v); break;
	default: c->sp = v; break;
	}
}

/* rp2 table: BC DE HL AF */
static uint16_t rp2_get(z80 *c, int p, int x)
{
	return p == 3 ? (uint16_t)(A << 8 | F) : rp_get(c, p, x);
}

static void rp2_set(z80 *c, int p, int x, uint16_t v)
{
	if (p == 3) {
		A = v >> 8;
		F = v;
	} else
		rp_set(c, p, x, v);
}

/* 8-bit register n (not 6), with H and L as the index halves when x */
static uint8_t r8_get(z80 *c, int n, int x)
{
	if (x && (n == 4 || n == 5)) {
		uint16_t v = get_hl(c, x);
		return n == 4 ? v >> 8 : v & 0xff;
	}
	return c->r[n];
}

static void r8_set(z80 *c, int n, int x, uint8_t v)
{
	if (x && (n == 4 || n == 5)) {
		uint16_t h = get_hl(c, x);
		h = n == 4 ? (h & 0x00ff) | v << 8 : (h & 0xff00) | v;
		set_hl(c, x, h);
		return;
	}
	c->r[n] = v;
}

/* Address of the (HL) operand, or (IX+d) / (IY+d), fetching d */
static uint16_t mem_addr(z80 *c, int x)
{
	if (!x)
		return HL;
	int8_t d = (int8_t)fetch(c);
	uint16_t a = get_hl(c, x) + d;
	c->wz = a;
	return a;
}

static int cond(z80 *c, int y)
{
	switch (y) {
	case 0: return !(F & FZ);
	case 1: return F & FZ;
	case 2: return !(F & FC);
	case 3: return F & FC;
	case 4: return !(F & FP);
	case 5: return F & FP;
	case 6: return !(F & FS);
	default: return F & FS;
	}
}

static void alu(z80 *c, int op, uint8_t v)
{
	unsigned a = A, r;
	int cy = F & FC;

	switch (op) {
	case 0:			/* ADD */
	case 1:			/* ADC */
		r = a + v + (op == 1 ? cy : 0);
		F = sz53[r & 0xff] | ((a ^ v ^ r) & FH) |
		    (((a ^ ~v) & (a ^ r) & 0x80) ? FP : 0) | ((r >> 8) & FC);
		A = r;
		break;
	case 2:			/* SUB */
	case 3:			/* SBC */
	case 7:			/* CP */
		r = a - v - (op == 3 ? cy : 0);
		F = FN | (sz53[r & 0xff] & (FS | FZ)) | ((a ^ v ^ r) & FH) |
		    (((a ^ v) & (a ^ r) & 0x80) ? FP : 0) | ((r >> 8) & FC);
		if (op == 7)
			F |= v & (FX | FY);
		else {
			F |= r & (FX | FY);
			A = r;
		}
		break;
	case 4:			/* AND */
		A &= v;
		F = sz53p[A] | FH;
		break;
	case 5:			/* XOR */
		A ^= v;
		F = sz53p[A];
		break;
	case 6:			/* OR */
		A |= v;
		F = sz53p[A];
		break;
	}
}

static uint8_t inc8(z80 *c, uint8_t v)
{
	uint8_t r = v + 1;
	F = (F & FC) | sz53[r] | ((v & 0x0f) == 0x0f ? FH : 0) |
	    (v == 0x7f ? FP : 0);
	return r;
}

static uint8_t dec8(z80 *c, uint8_t v)
{
	uint8_t r = v - 1;
	F = (F & FC) | FN | sz53[r] | ((v & 0x0f) == 0 ? FH : 0) |
	    (v == 0x80 ? FP : 0);
	return r;
}

static uint16_t add16(z80 *c, uint16_t a, uint16_t b)
{
	uint32_t r = a + b;
	F = (F & (FS | FZ | FP)) | ((r >> 8) & (FX | FY)) |
	    (((a ^ b ^ r) >> 8) & FH) | ((r >> 16) & FC);
	c->wz = a + 1;
	return r;
}

static uint16_t adc16(z80 *c, uint16_t a, uint16_t b)
{
	uint32_t r = a + b + (F & FC);
	F = ((r >> 8) & (FS | FX | FY)) | ((r & 0xffff) ? 0 : FZ) |
	    (((a ^ b ^ r) >> 8) & FH) |
	    ((~(a ^ b) & (a ^ r) & 0x8000) ? FP : 0) | ((r >> 16) & FC);
	c->wz = a + 1;
	return r;
}

static uint16_t sbc16(z80 *c, uint16_t a, uint16_t b)
{
	uint32_t r = a - b - (F & FC);
	F = FN | ((r >> 8) & (FS | FX | FY)) | ((r & 0xffff) ? 0 : FZ) |
	    (((a ^ b ^ r) >> 8) & FH) |
	    (((a ^ b) & (a ^ r) & 0x8000) ? FP : 0) | ((r >> 16) & FC);
	c->wz = a + 1;
	return r;
}

/* CB rotates and shifts, y selects the operation */
static uint8_t rot(z80 *c, int y, uint8_t v)
{
	uint8_t r, cy;
	switch (y) {
	case 0: cy = v >> 7; r = v << 1 | cy; break;		/* RLC */
	case 1: cy = v & 1; r = v >> 1 | cy << 7; break;	/* RRC */
	case 2: cy = v >> 7; r = v << 1 | (F & FC); break;	/* RL */
	case 3: cy = v & 1; r = v >> 1 | (F & FC) << 7; break;	/* RR */
	case 4: cy = v >> 7; r = v << 1; break;			/* SLA */
	case 5: cy = v & 1; r = (v >> 1) | (v & 0x80); break;	/* SRA */
	case 6: cy = v >> 7; r = v << 1 | 1; break;		/* SLL */
	default: cy = v & 1; r = v >> 1; break;			/* SRL */
	}
	F = sz53p[r] | cy;
	return r;
}

static void bit(z80 *c, int n, uint8_t v, uint8_t xy)
{
	uint8_t t = v & (1 << n);
	F = (F & FC) | FH | (xy & (FX | FY)) | (t ? 0 : FZ | FP) |
	    (t & FS);
}

static void daa(z80 *c)
{
	uint8_t a = A, corr = 0;
	int cy = F & FC, h;

	if ((F & FH) || (a & 0x0f) > 9)
		corr |= 0x06;
	if (cy || a > 0x99) {
		corr |= 0x60;
		cy = 1;
	}
	if (F & FN) {
		h = (F & FH) && (a & 0x0f) < 6;
		a -= corr;
	} else {
		h = (a & 0x0f) > 9;
		a += corr;
	}
	A = a;
	F = sz53p[a] | (F & FN) | (h ? FH : 0) | (cy ? FC : 0);
}

static int exec_cb(z80 *c, int x)
{
	uint16_t addr = 0;
	uint8_t v;
	int op, n;

	if (x) {
		addr = mem_addr(c, x);
		op = fetch(c);
	} else {
		op = fetch(c);
		inc_r(c);
	}
	int ox = op >> 6, y = (op >> 3) & 7, z = op & 7;

	if (x || z == 6) {
		if (!x)
			addr = HL;
		v = rd(c, addr);
		if (ox == 1) {
			bit(c, y, v, c->wz >> 8);
			return x ? 20 : 12;
		}
		if (ox == 0)
			v = rot(c, y, v);
		else if (ox == 2)
			v &= ~(1 << y);
		else
			v |= 1 << y;
		wr(c, addr, v);
		if (x && z != 6)
			c->r[z] = v;
		return x ? 23 : 15;
	}
	n = z;
	v = c->r[n];
	if (ox == 1) {
		bit(c, y, v, v);
		return 8;
	}
	if (ox == 0)
		v = rot(c, y, v);
	else if (ox == 2)
		v &= ~(1 << y);
	else
		v |= 1 << y;
	c->r[n] = v;
	return 8;
}

static uint8_t port_in(z80 *c, uint16_t port)
{
	return c->in ? c->in(c->ctx, port) : 0xff;
}

static void port_out(z80 *c, uint16_t port, uint8_t v)
{
	if (c->out)
		c->out(c->ctx, port, v);
}

/*
 * The flags of INI, IND, OUTI and OUTD and their repeats. Appendix A
 * gives only Z (B - 1 = 0) and N, and marks C "not affected". The NMOS
 * chip sets them all: S, Z, X, Y from B, N from bit 7 of the byte moved,
 * H and C when k, the byte plus C+-1 (in) or L (out), passes 255, and
 * P/V the parity of (k & 7) xor B (The Undocumented Z80 Documented, an
 * outside source checked on silicon).
 */
static void blkio_flags(z80 *c, uint8_t v, unsigned k)
{
	uint8_t b = c->r[0];
	F = (sz53[b] & (FS | FZ | FX | FY)) | (v & 0x80 ? FN : 0) |
	    (k > 255 ? FH | FC : 0) | (sz53p[(k & 7) ^ b] & FP);
}

static int block_op(z80 *c, int y, int z)
{
	int dir = (y & 1) ? -1 : 1, rep = y >= 6;
	uint16_t bc;
	uint8_t v, n;

	switch (z) {
	case 0:			/* LDI LDD LDIR LDDR */
		v = rd(c, HL);
		wr(c, DE, v);
		set_hl(c, 0, HL + dir);
		rp_set(c, 1, 0, DE + dir);
		bc = BC - 1;
		rp_set(c, 0, 0, bc);
		n = v + A;
		F = (F & (FS | FZ | FC)) | (bc ? FP : 0) | (n & FX) |
		    ((n & 0x02) ? FY : 0);
		if (rep && bc) {
			c->pc -= 2;
			return 21;
		}
		return 16;
	case 1: {		/* CPI CPD CPIR CPDR */
		v = rd(c, HL);
		uint8_t r = A - v;
		int h = (A ^ v ^ r) & FH;
		set_hl(c, 0, HL + dir);
		bc = BC - 1;
		rp_set(c, 0, 0, bc);
		n = r - (h ? 1 : 0);
		F = (F & FC) | FN | (r & FS) | (r ? 0 : FZ) | h |
		    (bc ? FP : 0) | (n & FX) | ((n & 0x02) ? FY : 0);
		if (rep && bc && r) {
			c->pc -= 2;
			return 21;
		}
		return 16;
	}
	case 2:			/* INI IND INIR INDR, flags by blkio_flags */
		v = port_in(c, BC);
		wr(c, HL, v);
		set_hl(c, 0, HL + dir);
		c->r[0]--;
		blkio_flags(c, v, v + ((c->r[1] + dir) & 0xff));
		if (rep && c->r[0]) {
			c->pc -= 2;
			return 21;
		}
		return 16;
	default:		/* OUTI OUTD OTIR OTDR */
		v = rd(c, HL);
		c->r[0]--;
		port_out(c, BC, v);
		set_hl(c, 0, HL + dir);
		blkio_flags(c, v, v + (HL & 0xff));
		if (rep && c->r[0]) {
			c->pc -= 2;
			return 21;
		}
		return 16;
	}
}

static int exec_ed(z80 *c)
{
	int op = fetch(c);
	inc_r(c);
	int x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1;
	uint8_t v;

	if (x == 2 && z <= 3 && y >= 4)
		return block_op(c, y, z);
	if (x != 1)
		return 8;	/* NONI */

	switch (z) {
	case 0:			/* IN r,(C) */
		v = port_in(c, BC);
		if (y != 6)
			c->r[y] = v;
		F = (F & FC) | sz53p[v];
		return 12;
	case 1:			/* OUT (C),r */
		port_out(c, BC, y == 6 ? 0 : c->r[y]);
		return 12;
	case 2:
		set_hl(c, 0, q ? adc16(c, HL, rp_get(c, p, 0))
			  : sbc16(c, HL, rp_get(c, p, 0)));
		return 15;
	case 3: {
		uint16_t nn = fetch16(c);
		if (q)
			rp_set(c, p, 0, rd16(c, nn));
		else
			wr16(c, nn, rp_get(c, p, 0));
		return 20;
	}
	case 4:			/* NEG */
		v = A;
		A = 0;
		alu(c, 2, v);
		return 8;
	case 5:			/* RETN, RETI */
		c->pc = pop(c);
		c->iff1 = c->iff2;
		return 14;
	case 6: {
		static const int ims[8] = { 0, 0, 1, 2, 0, 0, 1, 2 };
		c->im = ims[y];
		return 8;
	}
	default:
		switch (y) {
		case 0: c->i = A; return 9;
		case 1: c->rr = A; return 9;
		case 2:
		case 3:
			A = y == 2 ? c->i : c->rr;
			F = (F & FC) | sz53[A] | (c->iff2 ? FP : 0);
			c->ld_air = 1;
			return 9;
		case 4:		/* RRD */
			v = rd(c, HL);
			wr(c, HL, (uint8_t)(A << 4 | v >> 4));
			A = (A & 0xf0) | (v & 0x0f);
			F = (F & FC) | sz53p[A];
			return 18;
		case 5:		/* RLD */
			v = rd(c, HL);
			wr(c, HL, (uint8_t)(v << 4 | (A & 0x0f)));
			A = (A & 0xf0) | (v >> 4);
			F = (F & FC) | sz53p[A];
			return 18;
		default:
			return 8;
		}
	}
}

/* Execute one instruction whose first byte (after DD/FD) is op */
static int exec(z80 *c, int op, int x)
{
	int ox = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1;
	int t = cyc_main[op] + (x ? 4 : 0);
	uint16_t a, nn;
	uint8_t v;

	switch (ox) {
	case 0:
		switch (z) {
		case 0:
			switch (y) {
			case 0:
				break;
			case 1: {
				uint8_t ta = A, tf = F;
				A = c->alt[7];
				F = c->alt[6];
				c->alt[7] = ta;
				c->alt[6] = tf;
				break;
			}
			case 2: {	/* DJNZ */
				int8_t d = (int8_t)fetch(c);
				if (--c->r[0]) {
					c->pc += d;
					t += 5;
				}
				break;
			}
			case 3: {
				int8_t d = (int8_t)fetch(c);
				c->pc += d;
				break;
			}
			default: {
				int8_t d = (int8_t)fetch(c);
				if (cond(c, y - 4)) {
					c->pc += d;
					t += 5;
				}
				break;
			}
			}
			break;
		case 1:
			if (q)
				set_hl(c, x, add16(c, get_hl(c, x), rp_get(c, p, x)));
			else
				rp_set(c, p, x, fetch16(c));
			break;
		case 2:
			switch (y) {
			case 0: wr(c, BC, A); break;
			case 1: A = rd(c, BC); break;
			case 2: wr(c, DE, A); break;
			case 3: A = rd(c, DE); break;
			case 4: wr16(c, fetch16(c), get_hl(c, x)); break;
			case 5: set_hl(c, x, rd16(c, fetch16(c))); break;
			case 6: wr(c, fetch16(c), A); break;
			default: A = rd(c, fetch16(c)); break;
			}
			break;
		case 3:
			rp_set(c, p, x, rp_get(c, p, x) + (q ? -1 : 1));
			break;
		case 4:
		case 5:
			if (y == 6) {
				a = mem_addr(c, x);
				v = rd(c, a);
				wr(c, a, z == 4 ? inc8(c, v) : dec8(c, v));
				if (x)
					t += 8;
			} else {
				v = r8_get(c, y, x);
				r8_set(c, y, x, z == 4 ? inc8(c, v) : dec8(c, v));
			}
			break;
		case 6:
			if (y == 6) {
				a = mem_addr(c, x);
				wr(c, a, fetch(c));
				if (x)
					t += 5;
			} else
				r8_set(c, y, x, fetch(c));
			break;
		default:
			switch (y) {
			case 0:
			case 1:
			case 2:
			case 3: {
				uint8_t cy;
				v = A;
				if (y == 0) { cy = v >> 7; v = v << 1 | cy; }
				else if (y == 1) { cy = v & 1; v = v >> 1 | cy << 7; }
				else if (y == 2) { cy = v >> 7; v = v << 1 | (F & FC); }
				else { cy = v & 1; v = v >> 1 | (F & FC) << 7; }
				A = v;
				F = (F & (FS | FZ | FP)) | (v & (FX | FY)) | cy;
				break;
			}
			case 4: daa(c); break;
			case 5:
				A = ~A;
				F = (F & (FS | FZ | FP | FC)) | FH | FN | (A & (FX | FY));
				break;
			case 6:
				F = (F & (FS | FZ | FP)) | FC | (A & (FX | FY));
				break;
			default:
				F = (F & (FS | FZ | FP)) | ((F & FC) ? FH : FC) |
				    (A & (FX | FY));
				break;
			}
			break;
		}
		break;
	case 1:
		if (y == 6 && z == 6) {
			c->halted = 1;
			c->pc--;
		} else if (y == 6) {
			wr(c, mem_addr(c, x), c->r[z]);
			if (x)
				t += 8;
		} else if (z == 6) {
			c->r[y] = rd(c, mem_addr(c, x));
			if (x)
				t += 8;
		} else
			r8_set(c, y, x, r8_get(c, z, x));
		break;
	case 2:
		if (z == 6) {
			v = rd(c, mem_addr(c, x));
			if (x)
				t += 8;
		} else
			v = r8_get(c, z, x);
		alu(c, y, v);
		break;
	default:
		switch (z) {
		case 0:
			if (cond(c, y)) {
				c->pc = pop(c);
				t += 6;
			}
			break;
		case 1:
			if (!q)
				rp2_set(c, p, x, pop(c));
			else if (p == 0)
				c->pc = pop(c);
			else if (p == 1) {
				for (int i = 0; i < 6; i++) {
					uint8_t s = c->r[i];
					c->r[i] = c->alt[i];
					c->alt[i] = s;
				}
			} else if (p == 2)
				c->pc = get_hl(c, x);
			else
				c->sp = get_hl(c, x);
			break;
		case 2:
			nn = fetch16(c);
			if (cond(c, y))
				c->pc = nn;
			break;
		case 3:
			switch (y) {
			case 0: c->pc = fetch16(c); break;
			case 1: return exec_cb(c, x);
			case 2: v = fetch(c); port_out(c, (uint16_t)(A << 8 | v), A); break;
			case 3: v = fetch(c); A = port_in(c, (uint16_t)(A << 8 | v)); break;
			case 4:
				nn = rd16(c, c->sp);
				wr16(c, c->sp, get_hl(c, x));
				set_hl(c, x, nn);
				break;
			case 5:
				for (int i = 2; i < 4; i++) {
					uint8_t s = c->r[i];
					c->r[i] = c->r[i + 2];
					c->r[i + 2] = s;
				}
				break;
			case 6: c->iff1 = c->iff2 = 0; break;
			default: c->iff1 = c->iff2 = 1; c->ei_wait = 1; break;
			}
			break;
		case 4:
			nn = fetch16(c);
			if (cond(c, y)) {
				push(c, c->pc);
				c->pc = nn;
				t += 7;
			}
			break;
		case 5:
			if (!q)
				push(c, rp2_get(c, p, x));
			else if (p == 0) {
				nn = fetch16(c);
				push(c, c->pc);
				c->pc = nn;
			} else if (p == 2)	/* a DD or FD before keeps its 4 T */
				return (x ? 4 : 0) + exec_ed(c);
			else {
				/* DD or FD prefix: the next opcode uses IX or IY */
				int op2 = fetch(c);
				inc_r(c);
				return (x ? 4 : 0) + exec(c, op2, p == 1 ? 1 : 2);
			}
			break;
		case 6:
			alu(c, y, fetch(c));
			break;
		default:
			push(c, c->pc);
			c->pc = y * 8;
			break;
		}
		break;
	}
	return t;
}

void z80_reset(z80 *c)
{
	if (!tables_ready)
		init_tables();
	c->pc = 0;
	c->i = c->rr = 0;
	c->iff1 = c->iff2 = 0;
	c->im = 0;
	c->halted = 0;
	c->ei_wait = 0;
	c->sp = 0xffff;
	c->r[6] = c->r[7] = 0xff;
}

int z80_step(z80 *c)
{
	int t, wait = c->ei_wait, air = c->ld_air;

	c->ei_wait = 0;
	c->ld_air = 0;
	if (c->nmi) {
		c->nmi = 0;
		if (c->halted) {
			c->halted = 0;
			c->pc++;
		}
		c->iff2 = c->iff1;	/* App A Table 2, so a nested NMI clears it */
		c->iff1 = 0;
		inc_r(c);		/* the acknowledge is an M1 */
		push(c, c->pc);
		c->pc = 0x66;
		c->cycles += 11;
		return 11;
	}
	if (c->irq && c->iff1 && !wait) {
		if (c->halted) {
			c->halted = 0;
			c->pc++;
		}
		if (air)	/* NMOS Z80: P/V reads 0 after all */
			F &= ~FP;
		c->iff1 = c->iff2 = 0;
		inc_r(c);
		if (c->im == 2) {
			push(c, c->pc);
			c->pc = rd16(c, (uint16_t)(c->i << 8 | c->irq_vector));
			t = 19;
		} else if (c->im == 1 || (c->irq_vector & 0xc7) != 0xc7) {
			push(c, c->pc);
			c->pc = 0x38;
			t = 13;
		} else {
			/* IM 0 with an RST on the bus */
			push(c, c->pc);
			c->pc = c->irq_vector & 0x38;
			t = 13;
		}
		c->cycles += t;
		return t;
	}
	inc_r(c);
	t = exec(c, fetch(c), 0);
	c->cycles += t;
	return t;
}
