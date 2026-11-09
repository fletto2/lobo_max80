/* The host test of the page module, built with cc: page.c with
 * PG_HOST, a BDOS on the host's files, and a small editor of its own.
 * It makes a file of numbered lines in a scratch folder, moves through
 * it, jumps, edits at random, saves, and checks the window and each
 * saved file against a model of what the file should be.
 *
 * Usage: page_host DIR [LINES [SEED [MEMORY]]]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>
#include "page.h"

static int fails;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); \
	printf(__VA_ARGS__); printf("\n"); fails++; return; } } while (0)

/* ---- A BDOS on the host's files, by the FCB's name ---- */

static struct { unsigned char *fcb; FILE *f; } open_[8];

static void fcbname(unsigned char *fcb, char *out)
{
	int i, n = 0;

	for (i = 1; i < 9 && fcb[i] != ' '; i++)
		out[n++] = fcb[i];
	out[n++] = '.';
	for (i = 9; i < 12 && fcb[i] != ' '; i++)
		out[n++] = fcb[i];
	out[n] = 0;
}

static FILE **slot(unsigned char *fcb, int make)
{
	int i;

	for (i = 0; i < 8; i++)
		if (open_[i].fcb == fcb && open_[i].f)
			return &open_[i].f;
	if (!make)
		return 0;
	for (i = 0; i < 8; i++)
		if (!open_[i].f) {
			open_[i].fcb = fcb;
			return &open_[i].f;
		}
	return 0;
}

unsigned char pg_bdos(unsigned char fn, unsigned char *fcb, unsigned int rec,
	unsigned char *buf)
{
	char name[16];
	FILE **f;
	long n;

	if (fn == 152) {	/* parse: the name at pf[0] into the FCB at pf[1] */
		char **pf = (char **)fcb, *s = pf[0];
		unsigned char *f2 = (unsigned char *)pf[1];
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
		return 0;
	}
	fcbname(fcb, name);
	switch (fn) {
	case 15:
	case 22:
		if ((f = slot(fcb, 0)))
			fclose(*f);
		f = slot(fcb, 1);
		*f = fopen(name, fn == 15 ? "r+b" : "w+b");
		return *f ? 0 : 0xFF;
	case 16:
		if ((f = slot(fcb, 0))) {
			fclose(*f);
			*f = 0;
		}
		return 0;
	case 35:
		f = slot(fcb, 0);
		fseek(*f, 0, SEEK_END);
		n = (ftell(*f) + 127) / 128;
		fcb[33] = n;
		fcb[34] = n >> 8;
		fcb[35] = n >> 16;
		return 0;
	case 33:
		if (!(f = slot(fcb, 0)))
			return 9;
		fseek(*f, (long)rec * 128, SEEK_SET);
		n = fread(buf, 1, 128, *f);
		if (n == 0)
			return 1;
		memset(buf + n, 0x1A, 128 - n);
		return 0;
	case 34:
		if (!(f = slot(fcb, 0)))
			return 9;
		fseek(*f, (long)rec * 128, SEEK_SET);
		fwrite(buf, 1, 128, *f);
		fflush(*f);
		return 0;
	}
	return 0xFF;
}

/* ---- The editor: a list of lines, the window ---- */

typedef struct L { struct L *next, *prev; unsigned char tag; char *s; } L;
static L head = { &head, &head, 0, 0 };
static L *anchor;
static int nlive;

void *ed_end(unsigned char down)
{
	L *l = down ? head.prev : head.next;

	return l == &head ? 0 : l;
}

void *ed_step(void *v, unsigned char down)
{
	L *l = v;

	l = down ? l->next : l->prev;
	return l == &head ? 0 : l;
}

unsigned char ed_tag(void *v) { return ((L *)v)->tag; }

char *ed_text(void *v, unsigned int *n)
{
	*n = strlen(((L *)v)->s);
	return ((L *)v)->s;
}

void ed_begin(unsigned char down)
{
	anchor = down ? &head : head.next;
}

static L *dot;			/* the editor's place */
static int dropped;		/* dot was dropped */

static void link_before(L *l, L *at)
{
	l->next = at;
	l->prev = at->prev;
	at->prev->next = l;
	at->prev = l;
}

static long mem, memlimit = 1000000;	/* the lines' memory, and all there is */

unsigned int ed_add(char *s, unsigned int n, unsigned char tag)
{
	L *l;

	if (mem + n + 16 > memlimit)
		return 0;
	mem += n + 16;
	l = malloc(sizeof *l);
	l->s = malloc(n + 1);
	memcpy(l->s, s, n);
	l->s[n] = 0;
	l->tag = tag;
	link_before(l, anchor);
	nlive++;
	return n + 16;
}

static void unlink_free(L *l)
{
	l->prev->next = l->next;
	l->next->prev = l->prev;
	mem -= strlen(l->s) + 16;
	free(l->s);
	free(l);
	nlive--;
}

void ed_drop(void *v, unsigned char down)
{
	L *l = v;

	if (l == dot) {
		dot = down ? l->prev : l->next;
		dropped = 1;
	}
	unlink_free(l);
}

/* ---- The model: the lines the file should have ---- */

static char **model;
static int mlen, mcap;
static int mdot;		/* dot's line in the model */

static void minsert(int at, const char *s)
{
	if (mlen == mcap) {
		mcap = mcap ? mcap * 2 : 1024;
		model = realloc(model, mcap * sizeof *model);
	}
	memmove(model + at + 1, model + at, (mlen - at) * sizeof *model);
	model[at] = strdup(s);
	mlen++;
}

static void mdelete(int at)
{
	free(model[at]);
	memmove(model + at, model + at + 1, (mlen - at - 1) * sizeof *model);
	mlen--;
}

/* the window holds the model's lines from pg_above() on */
static void checkwindow(const char *what)
{
	int i = pg_above();
	L *l;
	unsigned char lt = 0;
	int pi = -1;

	if (getenv("PGTRACE")) {	/* the tables, to compare page.c and page.s */
		printf("%s: na %d nb %d np %d cost %u\n", what, pg_na, pg_nb, pg_np, pg_cost);
		for (pi = 0; pi < PG_NP; pi++)
			if (pi < pg_na || pi >= PG_NP - pg_nb)
				printf(" %d: %u.%u-%u.%u %u\n", pi, pg_tab[pi].r, pg_tab[pi].o,
					pg_tab[pi].er, pg_tab[pi].eo, pg_tab[pi].nl);
		for (pi = 0; pi < pg_np; pi++)
			printf(" p%d: %u.%u-%u.%u %u c%u t%d d%d\n", pi, pg_part[pi].o.r,
				pg_part[pi].o.o, pg_part[pi].o.er, pg_part[pi].o.eo, pg_part[pi].o.nl,
				pg_part[pi].cost, pg_part[pi].tag, pg_part[pi].dirty);
		pi = -1;
	}

	for (l = head.next; l != &head; l = l->next, i++) {
		CHECK(i < mlen, "%s: window past the end at %d", what, i);
		CHECK(!strcmp(l->s, model[i]), "%s: line %d is '%s', not '%s'", what, i,
			l->s, model[i]);
		if (l->tag != lt) {
			/* the tags run in the parts' order */
			do
				pi++;
			while (pi < pg_np && pg_part[pi].tag != l->tag);
			CHECK(pi < pg_np, "%s: line %d's tag %d is no part's, in order", what, i,
				l->tag);
			lt = l->tag;
		}
	}
}

static void checkfile(const char *name, const char *what)
{
	FILE *f = fopen(name, "rb");
	long n = 0, len;
	int i, c;
	char *want, *got;

	CHECK(f, "%s: no %s", what, name);
	for (i = 0; i < mlen; i++)
		n += strlen(model[i]) + 2;
	len = (n + 127) / 128 * 128;
	want = malloc(len + 1);
	got = malloc(len + 200);
	for (n = 0, i = 0; i < mlen; i++) {
		strcpy(want + n, model[i]);
		n += strlen(model[i]);
		want[n++] = '\r';
		want[n++] = '\n';
	}
	memset(want + n, 0x1A, len - n);
	c = fread(got, 1, len + 200, f);
	fclose(f);
	CHECK(c == len, "%s: %s is %d bytes, not %ld", what, name, c, len);
	for (i = 0; i < len; i++)
		CHECK(want[i] == got[i], "%s: %s differs at byte %d", what, name, i);
	free(want);
	free(got);
}

static int exists(const char *name)
{
	return access(name, 0) == 0;
}

/* ---- Moves ---- */

static void down1(void)
{
	if (dot->next == &head) {
		if (!pg_nb)
			return;
		if (!pg_slide(1, dot)) {
			printf("FAIL slide down: %s\n", pg_err ? pg_err : "?");
			fails++;
			return;
		}
		if (dot->next == &head)
			return;
	}
	dot = dot->next;
	mdot++;
}

static void up1(void)
{
	if (dot->prev == &head) {
		if (!pg_na)
			return;
		if (!pg_slide(0, dot)) {
			int j;
			printf("FAIL slide up: %s np %d na %d nb %d cost %u\n", pg_err ? pg_err : "?", pg_np, pg_na, pg_nb, pg_cost);
			for (j = 0; j < pg_na; j++) printf("  above %d: %u.%u - %u.%u nl %u\n", j, pg_tab[j].r, pg_tab[j].o, pg_tab[j].er, pg_tab[j].eo, pg_tab[j].nl);
			for (j = 0; j < pg_np; j++) printf("  part %d: %u.%u - %u.%u nl %u tag %d\n", j, pg_part[j].o.r, pg_part[j].o.o, pg_part[j].o.er, pg_part[j].o.eo, pg_part[j].o.nl, pg_part[j].tag);
			fails++;
			return;
		}
		if (dot->prev == &head)
			return;
	}
	dot = dot->prev;
	mdot--;
}

static void jump(int n)
{
	L *l;

	l = pg_goto(n);
	if (pg_err) {
		int j;
		printf("FAIL goto %d: %s, na %d nb %d np %d\n", n, pg_err, pg_na, pg_nb, pg_np);
		for (j = 0; j < PG_NP; j++)
			printf("  %s %d: %u.%u - %u.%u nl %u\n", j < pg_na ? "above" :
				j >= PG_NP - pg_nb ? "below" : "free", j, pg_tab[j].r, pg_tab[j].o,
				pg_tab[j].er, pg_tab[j].eo, pg_tab[j].nl);
		fails++;
		return;
	}
	if (!l) {
		dot = head.prev;
		mdot = mlen - 1;
	} else {
		dot = l;
		mdot = n;
	}
}

static unsigned rnd(unsigned n)
{
	return (unsigned)random() % n;
}

static void edit(int k)
{
	char buf[300];
	L *l;
	int n;

	switch (rnd(4)) {
	case 0:		/* change the line */
		if (strlen(dot->s) < 150)
			snprintf(buf, sizeof buf, "%s [edit %d]", dot->s, k);
		else
			snprintf(buf, sizeof buf, "Edited %d", k);
		mem += strlen(buf) - strlen(dot->s);
		free(dot->s);
		dot->s = strdup(buf);
		free(model[mdot]);
		model[mdot] = strdup(buf);
		pg_touch(dot->tag);
		break;
	case 1:		/* a line after it */
	case 2:
		snprintf(buf, sizeof buf, "New line %d", k);
		l = malloc(sizeof *l);
		l->s = strdup(buf);
		mem += strlen(buf) + 16;
		l->tag = dot->tag;
		link_before(l, dot->next);
		nlive++;
		pg_touch(dot->tag);
		minsert(mdot + 1, buf);
		break;
	case 3:		/* the line deleted, dot to the next or previous */
		l = dot;
		n = mdot;
		if (l->next != &head)
			dot = l->next;
		else if (l->prev != &head) {
			dot = l->prev;
			mdot--;
		} else
			break;
		pg_touch(l->tag);
		unlink_free(l);
		mdelete(n);
		break;
	}
}

static void run(int lines, unsigned seed)
{
	FILE *f;
	int i, k, n;
	long len = 0;
	char buf[100];
	unsigned char pad[128];

	srandom(seed);
	f = fopen("BIG.TXT", "wb");
	for (i = 0; i < lines; i++) {
		snprintf(buf, sizeof buf, "Line %04d of the big file, some words to fill it out.", i);
		minsert(mlen, buf);
		len += fprintf(f, "%s\r\n", buf);
	}
	memset(pad, 0x1A, 128);
	fwrite(pad, 1, (128 - len % 128) % 128, f);
	fclose(f);
	remove("BIG.$$W");

	CHECK(pg_open("BIG.TXT", 3000), "open");
	pg_rows = 22;
	jump(0);
	CHECK(dot && !strcmp(dot->s, model[0]), "the first line loaded");
	CHECK(pg_nb > 0, "the file does not all fit");
	checkwindow("open");

	/* to the end and back, line by line */
	for (i = 0; i < lines + 10; i++)
		down1();
	CHECK(mdot == lines - 1, "down reaches the last line, %d", mdot);
	CHECK(!strcmp(dot->s, model[lines - 1]), "at the last line");
	checkwindow("at the end");
	for (i = 0; i < lines + 10; i++)
		up1();
	CHECK(mdot == 0, "up reaches the first line, %d", mdot);
	checkwindow("back at the top");
	CHECK(!exists("BIG.$$W"), "reading writes no work file");
	printf("ok   down and up through %d lines, no work file\n", lines);

	/* jumps */
	for (k = 0; k < 20; k++) {
		n = rnd(lines);
		jump(n);
		CHECK(!strcmp(dot->s, model[n]), "goto %d", n);
		checkwindow("goto");
	}
	jump(0xFFFF);
	CHECK(!strcmp(dot->s, model[lines - 1]), "goto the end");
	checkwindow("goto the end");
	printf("ok   goto\n");

	/* edits at random, with moves and jumps */
	for (k = 0; k < 3000; k++) {
		switch (rnd(10)) {
		case 0: case 1: case 2:
			edit(k);
			break;
		case 3: case 4: case 5:
			for (n = rnd(80); n--; )
				down1();
			break;
		case 6: case 7:
			for (n = rnd(80); n--; )
				up1();
			break;
		case 8:
			if (rnd(4) == 0)
				jump(rnd(mlen));
			break;
		case 9:
			if (rnd(30) == 0) {
				long r = pg_save("BIG.TXT", 1);
				CHECK(r == mlen, "save says %ld lines, not %d", r, mlen);
				checkfile("BIG.TXT", "save");
				CHECK(!exists("BIG.$$W"), "no work file after the save");
				CHECK(!exists("BIG.$$S"), "no temporary file after the save");
				CHECK(exists("BIG.BAK"), "the .BAK kept");
			}
			break;
		}
		if (fails)
			return;
		CHECK(!strcmp(dot->s, model[mdot]), "step %d: dot is '%s', not line %d '%s'",
			k, dot->s, mdot, model[mdot]);
		checkwindow("edit");
		if (fails)
			return;
	}
	CHECK(pg_save("BIG.TXT", 0) == mlen, "the last save");
	checkfile("BIG.TXT", "the last save");
	printf("ok   3000 edits, moves, jumps and saves, %d lines, the file as the model\n", mlen);
	pg_close();
	CHECK(!exists("BIG.$$W"), "no work file after close");
}

/* A file of LF lines, a line of 700 characters and no LF at the end:
   moved through and saved with no change, it is the same, ^Z padded */
static void verbatim(void)
{
	FILE *f;
	int i;
	long len;
	char *want, *got;

	want = malloc(40000);
	got = malloc(40000);
	len = 0;
	for (i = 0; i < 500; i++) {
		if (i == 250) {
			memset(want + len, 'x', 700);
			len += 700;
			want[len++] = '\n';
		}
		len += sprintf(want + len, "Line %d, with LF only\n", i);
	}
	len += sprintf(want + len, "The last, with no LF");
	f = fopen("LF.TXT", "wb");
	fwrite(want, 1, len, f);
	fclose(f);
	while (head.next != &head)
		unlink_free(head.next);
	CHECK(pg_open("LF.TXT", 3000), "open LF.TXT");
	dot = pg_goto(0);
	for (i = 0; i < 1000; i++)
		down1();
	CHECK(!strcmp(dot->s, "The last, with no LF"), "LF.TXT: the last line, '%s'", dot->s);
	for (i = 0; i < 1000; i++)
		up1();
	pg_goto(300);
	CHECK(pg_save("LF.TXT", 0) > 0, "LF.TXT saved");
	memset(want + len, 0x1A, (128 - len % 128) % 128);
	len += (128 - len % 128) % 128;
	f = fopen("LF.TXT", "rb");
	i = fread(got, 1, 40000, f);
	fclose(f);
	CHECK(i == len && !memcmp(want, got, len), "LF.TXT is as it was, %d bytes for %ld", i, len);
	pg_close();
	printf("ok   LF lines, a long line, no LF at the end: saved as they were\n");
}

int main(int argc, char **argv)
{
	int lines = argc > 2 ? atoi(argv[2]) : 600;
	unsigned seed = argc > 3 ? atoi(argv[3]) : 1;

	if (argc > 4)
		memlimit = atol(argv[4]);

	if (argc < 2 || chdir(argv[1])) {
		fprintf(stderr, "Usage: page_host DIR [LINES [SEED]]\n");
		return 2;
	}
	run(lines, seed);
	if (!fails)
		verbatim();
	if (fails)
		return 1;
	return 0;
}
