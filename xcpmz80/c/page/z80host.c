/* The host test of page.s, the page module in Z80 code: host.c's
 * test, with its pg_ functions run on the emulator's Z80 core.
 *
 * page.s is linked at 0100h with its data at 9000h, and its calls out,
 * to the ed_ functions, remove, rename and the BDOS at 5, go to fixed
 * addresses that this file catches and answers from host.c. Each line
 * is a 16-bit number on the Z80 side. Each call out clobbers every
 * register but the result, as SDCC's code may, and each call in checks
 * that IX and the stack come back as they were.
 *
 * Built by c/Makefile as build/page_z80host, which reads the code and
 * its map from PZ, the path of build/page/pz without .ihx or .map. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include "page.h"
#include "../../../emu/z80.h"

#ifndef PZ
#define PZ "build/page/pz"
#endif

typedef unsigned char u8;
typedef unsigned short u16;

u8 pg_bdos(u8 fn, u8 *fcb, unsigned int rec, u8 *buf);	/* host.c's */

PIECE pg_tab[PG_NP];
PART pg_part[PG_NPART];
u8 pg_na, pg_nb, pg_np;
unsigned int pg_budget, pg_cost;
u8 pg_rows = 24;
u8 pg_on;
char pg_line[PG_LINE + 1];
const char *pg_err;

static u8 M[65536];
static z80 cpu;
static u16 dma = 0x80;

#define STACK	0xEF00
#define TEXT	0xF000		/* ed_text's line */
#define NAME	0xFE00		/* a name passed in */
#define T_END	0x10		/* the calls out */
#define T_STEP	0x11
#define T_TAG	0x12
#define T_TEXT	0x13
#define T_BEGIN	0x14
#define T_ADD	0x15
#define T_DROP	0x16
#define T_RM	0x17
#define T_REN	0x18

static struct { const char *name; u16 a; } sym[] = {
	{ "_pg_tab" }, { "_pg_part" }, { "_pg_na" }, { "_pg_nb" }, { "_pg_np" },
	{ "_pg_budget" }, { "_pg_cost" }, { "_pg_rows" }, { "_pg_on" },
	{ "_pg_err" }, { "_pg_open" }, { "_pg_close" }, { "_pg_slide" },
	{ "_pg_free" }, { "_pg_touch" }, { "_pg_newtag" }, { "_pg_goto" },
	{ "_pg_above" }, { "_pg_save" },
};
enum { S_TAB, S_PART, S_NA, S_NB, S_NP, S_BUDGET, S_COST, S_ROWS, S_ON,
	S_ERR, S_OPEN, S_CLOSE, S_SLIDE, S_FREE, S_TOUCH, S_NEWTAG, S_GOTO,
	S_ABOVE, S_SAVE, NSYM };

static int cur = -1;		/* the function called */

static void die(const char *m)
{
	printf("FAIL z80: %s, in %s, PC %04X SP %04X\n", m,
		cur >= 0 ? sym[cur].name : "-", cpu.pc, cpu.sp);
	exit(1);
}

static u8 rd(void *c, u16 a) { (void)c; return M[a]; }
static void wr(void *c, u16 a, u8 v) { (void)c; M[a] = v; }
static u8 in(void *c, u16 p) { (void)c; (void)p; return 0xFF; }
static void out(void *c, u16 p, u8 v) { (void)c; (void)p; (void)v; }

static u16 rd16(u16 a) { return M[a] | M[(u16)(a + 1)] << 8; }
static void wr16(u16 a, u16 v) { M[a] = v; M[(u16)(a + 1)] = v >> 8; }

static void load(void)
{
	char line[600], name[64];
	FILE *f;
	unsigned a, n, i, t, b;
	int got = 0;

	if (!(f = fopen(PZ ".ihx", "r")))
		die("no " PZ ".ihx");
	while (fgets(line, sizeof line, f))
		if (sscanf(line, ":%2x%4x%2x", &n, &a, &t) == 3 && t == 0)
			for (i = 0; i < n; i++) {
				sscanf(line + 9 + 2 * i, "%2x", &b);
				M[(u16)(a + i)] = b;
			}
	fclose(f);
	if (!(f = fopen(PZ ".map", "r")))
		die("no " PZ ".map");
	while (fgets(line, sizeof line, f))
		if (sscanf(line, " %x %63s", &a, name) == 2)
			for (i = 0; i < NSYM; i++)
				if (!strcmp(name, sym[i].name) && !sym[i].a) {
					sym[i].a = a;
					got++;
				}
	fclose(f);
	if (got != NSYM)
		die("a symbol is not in the map");
	z80_reset(&cpu);
	cpu.read = rd;
	cpu.write = wr;
	cpu.in = in;
	cpu.out = out;
}

/* ---- Lines as numbers ---- */

#define HN	(1 << 18)
static void *hk[HN];
static u16 hv[HN];
static void *idp[65536];
static unsigned nid = 1;

static u16 id(void *p)
{
	size_t h;

	if (!p)
		return 0;
	h = (size_t)(((uintptr_t)p >> 4) * 2654435761u) & (HN - 1);
	for (; hk[h]; h = (h + 1) & (HN - 1))
		if (hk[h] == p)
			return hv[h];
	if (nid == 65536)
		die("out of line numbers");
	hk[h] = p;
	hv[h] = nid;
	idp[nid] = p;
	return nid++;
}

static void *ptr(u16 i)
{
	if (i >= nid)
		die("a line number never given");
	return i ? idp[i] : 0;
}

/* ---- Calls out ---- */

enum { B, C, D, E, H, L, F, A };

/* not junk(), which would move host.c's random() */
static unsigned junk(void)
{
	static uint32_t x = 12345;

	x = x * 1103515245 + 12345;
	return x >> 16;
}

static void clobber(void)
{
	cpu.r[B] = junk();
	cpu.r[C] = junk();
	cpu.r[D] = junk();
	cpu.r[E] = junk();
	cpu.r[H] = junk();
	cpu.r[L] = junk();
	cpu.r[A] = junk();
	cpu.r[F] = junk();
}

static void ret16(u16 v)
{
	cpu.r[H] = v >> 8;
	cpu.r[L] = v;
}

static void bdos(void)
{
	u8 fn = cpu.r[C];
	u16 de = cpu.r[D] << 8 | cpu.r[E];
	u8 r = 0;

	if (fn == 26)
		dma = de;
	else if (fn == 152) {
		char *s = (char *)&M[rd16(de)];
		u8 *f2 = &M[rd16(de + 2)];
		int i;

		memset(f2 + 1, ' ', 11);
		if (s[0] && s[1] == ':') {
			f2[0] = s[0] & 0x1F;
			s += 2;
		}
		for (i = 1; *s && *s != '.'; s++)
			if (i < 9)
				f2[i++] = toupper(*s);
		if (*s == '.')
			for (i = 9, s++; *s && i < 12; s++)
				f2[i++] = toupper(*s);
	} else {
		if (fn == 33 || fn == 34)
			if (M[de + 35])
				die("record over FFFFh");
		r = pg_bdos(fn, &M[de], rd16(de + 33), &M[dma]);
	}
	clobber();
	cpu.r[A] = cpu.r[L] = r;
}

static void callout(u16 pc)
{
	u16 sp = cpu.sp;
	unsigned int n;
	u16 v = 0;
	char *s;

	switch (pc) {
	case T_END:
		v = id(ed_end(M[sp + 2]));
		break;
	case T_STEP:
		v = id(ed_step(ptr(rd16(sp + 2)), M[sp + 4]));
		break;
	case T_TAG:
		v = ed_tag(ptr(rd16(sp + 2)));
		break;
	case T_TEXT:
		s = ed_text(ptr(rd16(sp + 2)), &n);
		if (n > 0xE00)
			die("a line too long for TEXT");
		memcpy(&M[TEXT], s, n);
		wr16(rd16(sp + 4), n);
		v = TEXT;
		break;
	case T_BEGIN:
		ed_begin(M[sp + 2]);
		break;
	case T_ADD:
		n = rd16(sp + 4);
		if (rd16(sp + 2) + n > 0x10000)
			die("ed_add past the top");
		v = ed_add((char *)&M[rd16(sp + 2)], n, M[sp + 6]);
		break;
	case T_DROP:
		ed_drop(ptr(rd16(sp + 2)), M[sp + 4]);
		break;
	case T_RM:
		remove((char *)&M[rd16(sp + 2)]);
		break;
	case T_REN:
		rename((char *)&M[rd16(sp + 2)], (char *)&M[rd16(sp + 4)]);
		break;
	}
	clobber();
	ret16(v);
}

/* ---- Calls in ---- */

static void push16(u16 v)
{
	cpu.sp -= 2;
	wr16(cpu.sp, v);
}

static void push8(u8 v)
{
	cpu.sp -= 1;
	M[cpu.sp] = v;
}

static void tozc(void)
{
	M[sym[S_ROWS].a] = pg_rows;
}

static void fromz(void)
{
	int i;
	u16 a, e;

	for (i = 0; i < PG_NP; i++) {
		a = sym[S_TAB].a + 8 * i;
		pg_tab[i].r = rd16(a);
		pg_tab[i].o = M[a + 2];
		pg_tab[i].er = rd16(a + 3);
		pg_tab[i].eo = M[a + 5];
		pg_tab[i].nl = rd16(a + 6);
	}
	for (i = 0; i < PG_NPART; i++) {
		a = sym[S_PART].a + 12 * i;
		pg_part[i].o.r = rd16(a);
		pg_part[i].o.o = M[a + 2];
		pg_part[i].o.er = rd16(a + 3);
		pg_part[i].o.eo = M[a + 5];
		pg_part[i].o.nl = rd16(a + 6);
		pg_part[i].cost = rd16(a + 8);
		pg_part[i].tag = M[a + 10];
		pg_part[i].dirty = M[a + 11];
	}
	pg_na = M[sym[S_NA].a];
	pg_nb = M[sym[S_NB].a];
	pg_np = M[sym[S_NP].a];
	pg_budget = rd16(sym[S_BUDGET].a);
	pg_cost = rd16(sym[S_COST].a);
	pg_on = M[sym[S_ON].a];
	e = rd16(sym[S_ERR].a);
	pg_err = e ? (char *)&M[e] : 0;
	if (pg_na + pg_nb > PG_NP || pg_np > PG_NPART)
		die("the counts are past the tables");
}

static unsigned long long steps;

/* the function at sym s called with the arguments pushed */
static void call(int s)
{
	u16 sp = cpu.sp, pc;

	cur = s;
	tozc();
	push16(0);
	cpu.pc = sym[s].a;
	cpu.ix = 0x5A5A;
	for (;;) {
		pc = cpu.pc;
		if (pc == 0)
			break;
		if (pc == 5 || (pc >= T_END && pc <= T_REN)) {
			if (pc == 5)
				bdos();
			else
				callout(pc);
			cpu.pc = rd16(cpu.sp);
			cpu.sp += 2;
			continue;
		}
		if (pc < 0x100 || cpu.sp < 0xC000)
			die("lost: a jump or the stack out of place");
		z80_step(&cpu);
		steps++;
	}
	if (cpu.sp != sp)
		die("the stack is not as it was");
	if (cpu.ix != 0x5A5A)
		die("IX changed");
	cpu.sp = STACK;
	fromz();
}

static void args(void)
{
	if (!sym[S_TAB].a)
		load();
	cpu.sp = STACK;
}

unsigned char pg_open(const char *name, unsigned int budget)
{
	args();
	strcpy((char *)&M[NAME], name);
	push16(budget);
	push16(NAME);
	call(S_OPEN);
	return cpu.r[L];
}

void pg_close(void)
{
	args();
	call(S_CLOSE);
}

unsigned char pg_slide(unsigned char down, void *keep)
{
	args();
	push16(id(keep));
	push8(down);
	call(S_SLIDE);
	return cpu.r[L];
}

unsigned char pg_free(void *keep)
{
	args();
	ret16(id(keep));
	call(S_FREE);
	return cpu.r[L];
}

void pg_touch(unsigned char tag)
{
	args();
	cpu.r[H] = junk();
	cpu.r[L] = tag;
	call(S_TOUCH);
}

unsigned char pg_newtag(void)
{
	args();
	call(S_NEWTAG);
	return cpu.r[L];
}

void *pg_goto(unsigned int n)
{
	args();
	ret16(n);
	call(S_GOTO);
	return ptr(cpu.r[H] << 8 | cpu.r[L]);
}

unsigned int pg_above(void)
{
	args();
	call(S_ABOVE);
	return cpu.r[H] << 8 | cpu.r[L];
}

long pg_save(const char *name, unsigned char bak)
{
	uint32_t r;

	args();
	strcpy((char *)&M[NAME], name);
	push8(bak);
	push16(NAME);
	call(S_SAVE);
	r = (uint32_t)(cpu.r[D] << 8 | cpu.r[E]) << 16 | cpu.r[H] << 8 | cpu.r[L];
	return (int32_t)r;
}
