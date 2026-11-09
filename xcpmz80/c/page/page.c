/* A window over a file bigger than memory, for EMACS and VI. See
 * page.h.
 *
 * The file and the work file are read and written a 128-byte record at a
 * time by BDOS functions 33 and 34, straight into the buffers, as ZORK
 * does, since the library's fread goes a byte at a time. Built with
 * PG_HOST for the host test (host.c), which gives pg_bdos.
 *
 * The code keeps its working values in static variables, not in locals
 * and arguments, as SDCC makes much smaller code of them. */
#include <stdio.h>
#include <string.h>
#include "page.h"

typedef unsigned char u8;
typedef unsigned int u16;

#define FAST	PG_FAST

PIECE pg_tab[PG_NP];
PART pg_part[PG_NPART];
u8 pg_na, pg_nb, pg_np;
u16 pg_budget, pg_cost;
u8 pg_rows = 24;
u8 pg_on;
char pg_line[PG_LINE + 1];
const char *pg_err;

#define FN_OPEN		15
#define FN_CLOSE	16
#define FN_MAKE		22
#define FN_READ		33
#define FN_WRITE	34
#define FN_SIZE		35
#define FN_PARSE	152

#ifdef PG_HOST
u8 pg_bdos(u8 fn, u8 *fcb, u16 rec, u8 *buf);
#else
#include <cpm.h>
/* BDOS function fn on the FCB, record rec into or out of buf */
static u8 pg_bdos(u8 fn, u8 *fcb, u16 rec, u8 *buf)
{
	if (buf)
		bdos(26, (u16)buf);
	fcb[33] = rec;
	fcb[34] = rec >> 8;
	fcb[35] = 0;
	return bdos(fn, (u16)fcb);
}
#endif

static char fname[16], wname[16];	/* the file, the work file */
static u8 ofcb[36], wfcb[36], sfcb[36];	/* the file, work, save */
static u8 w_open;			/* the work file was made */

static PART *pt;			/* the part at hand */
static PIECE pc;			/* a piece being made */
static u8 dn;				/* the side: 1 below, 0 above */
static u8 tg;				/* a part's tag */

/* ---- Names ---- */

/* name with its type replaced by type, into out */
static void mkname(char *out, const char *name, const char *type)
{
	u8 i = 0;

	while (*name && *name != '.' && i < 10)
		out[i++] = *name++;
	out[i++] = '.';
	strcpy(out + i, type);
}

/* the FCB for name, by BDOS function 152 */
static void mkfcb(u8 *fcb, char *name)
{
	char *pf[2];

	pf[0] = name;
	pf[1] = (char *)fcb;
	memset(fcb, 0, 36);
#ifdef PG_HOST
	pg_bdos(FN_PARSE, (u8 *)pf, 0, 0);
#else
	bdos(FN_PARSE, (u16)pf);	/* not pg_bdos, which writes pf[33] */
#endif
}

/* ---- Reading: one record cached, a stream over a piece ---- */

static u8 rbuf[128];
static u16 r_rec = 0xFFFF;		/* the record in rbuf, FFFFh none */
static u8 r_w;				/* of the work file */

static u16 s_rec, s_er;			/* the stream's record, its end's */
static u8 *s_p;				/* the next byte, in rbuf */
static u8 s_n;				/* bytes there */
static u8 s_eo, s_w;			/* the end's place, the work file */
static u16 s_raw;			/* bytes the last line took */
static u8 s_lf;				/* and it ended with LF */

static void sopen(PIECE *p) FAST
{
	s_w = p->o & PG_WORK;
	s_rec = p->r;
	s_p = rbuf + (p->o & 127);
	s_n = 0;
	s_er = p->er;
	s_eo = p->eo;
	s_lf = 0;
}

/* the stream's place, the next byte, as the start of pc */
static void here(void)
{
	u8 i = s_p - rbuf;

	pc.r = s_rec;
	if (i == 128) {
		pc.r++;
		i = 0;
	}
	pc.o = i | s_w;
}

/* the next part of the stream into rbuf, 0 at its end */
static u8 refill(void)
{
	u8 i = s_p - rbuf, e;

	if (i == 128) {
		s_rec++;
		s_p = rbuf;
		i = 0;
	}
	e = s_rec == s_er ? s_eo : 128;
	if (i >= e || s_rec > s_er)
		return 0;
	if (r_rec != s_rec || r_w != s_w) {
		r_rec = 0xFFFF;
		if (pg_bdos(FN_READ, s_w ? wfcb : ofcb, s_rec, rbuf)) {
			pg_err = "Read error";
			return 0;
		}
		r_rec = s_rec;
		r_w = s_w;
	}
	s_n = e - i;
	return 1;
}

/* the next line of the stream into pg_line, CR dropped, its length or
   -1 at the end. s_raw is the bytes it took, s_lf whether LF ended it */
static int sgetl(void)
{
	u16 i = 0;
	u8 c;

	s_raw = 0;
	s_lf = 0;
	for (;;) {
		if (!s_n && !refill())
			break;
		c = *s_p++;
		s_n--;
		s_raw++;
		if (c == '\n') {
			s_lf = 1;
			break;
		}
		if (c != '\r') {
			pg_line[i++] = c;
			if (i == PG_LINE)
				break;
		}
	}
	pg_line[i] = 0;
	return s_raw ? (int)i : -1;
}

/* the stream's lines counted, and with cp set copied to the writer */
static u8 cp;
static void wput(const char *s, u16 n);

static u16 scount(void)
{
	u16 n = 0;
	u8 *b;

	while (s_n || refill()) {
		if (cp)
			wput((char *)s_p, s_n);
		for (b = s_p; s_n; s_n--)
			if (*b++ == '\n' && n < PG_UNK - 1)
				n++;
		s_p = b;
	}
	return n;
}

/* ---- Writing: the work file, or the file being saved ---- */

static u8 wbuf[128];
static u8 *w_fcb;			/* the file wbuf is for */
static u16 w_rec;			/* its record */
static u8 w_n;				/* bytes in it */
static u8 w_bad;			/* a write failed */
static u16 wk_rec;			/* the work file's end */
static u8 wk_n;

static void wflush(void)
{
	if (pg_bdos(FN_WRITE, w_fcb, w_rec, wbuf))
		w_bad = 1;
	if (w_fcb == wfcb && r_w && r_rec == w_rec)
		r_rec = 0xFFFF;
}

static void wput(const char *s, u16 n)
{
	while (n--) {
		wbuf[w_n++] = *s++;
		if (w_n == 128) {
			wflush();
			w_rec++;
			w_n = 0;
		}
	}
}

/* pc starts where the writer is */
static void wstart(void)
{
	pc.r = w_rec;
	pc.o = w_n | (w_fcb == wfcb ? PG_WORK : 0);
	pc.nl = 0;
}

/* and ends there, the last record written */
static void wend(void)
{
	if (w_n)
		wflush();
	pc.er = w_rec;
	pc.eo = w_n;
}

/* p copied to the writer, its lines counted */
static void copy(PIECE *p) FAST
{
	sopen(p);
	cp = 1;
	p->nl = scount();
	cp = 0;
}

/* the lines from l down while their tag is tg: their count */
static u16 wlines(void *l) FAST
{
	char *s;
	u16 n, nl = 0;

	for (; l && ed_tag(l) == tg; l = ed_step(l, 1)) {
		s = ed_text(l, &n);
		wput(s, n);
		wput("\r\n", 2);
		nl++;
	}
	return nl;
}

/* the writer on the work file's end, the file made the first time */
static u8 wwork(void)
{
	if (!w_open) {
		remove(wname);
		mkfcb(wfcb, wname);
		if (pg_bdos(FN_MAKE, wfcb, 0, 0) == 0xFF) {
			pg_err = "Cannot make the work file";
			return 0;
		}
		w_open = 1;
		wk_rec = 0;
		wk_n = 0;
	}
	if (w_fcb != wfcb) {	/* wbuf was the save's */
		w_fcb = wfcb;
		if (wk_n)
			pg_bdos(FN_READ, wfcb, wk_rec, wbuf);
	}
	w_rec = wk_rec;
	w_n = wk_n;
	w_bad = 0;
	wstart();
	return 1;
}

/* the writer done on the work file, pc ended: 0 if it failed */
static u8 wdone(void)
{
	wend();
	if (w_bad) {
		pg_err = "Work file write error";
		return 0;
	}
	wk_rec = w_rec;
	wk_n = w_n;
	return 1;
}

/* ---- The lists ---- */

static u8 empty(PIECE *p) FAST
{
	return p->r == p->er && (p->o & 127) == p->eo;
}

/* b follows a in the same file */
static u8 joins(PIECE *a, PIECE *b)
{
	return a->er == b->r && a->eo == (b->o & 127) &&
	    !((a->o ^ b->o) & PG_WORK);
}

/* the piece nearest the window on side dn */
static PIECE *nearest(void)
{
	return dn ? PG_BELOW : pg_tab + pg_na - 1;
}

/* the count of pieces on side dn */
static u8 *side(void)
{
	return dn ? &pg_nb : &pg_na;
}

/* pc onto the list on side dn, merged with its neighbor there when they
   are one run of the same file. 0 if there is no room */
static u8 push(void)
{
	PIECE *q;
	u16 n;

	if (empty(&pc))
		return 1;
	if (*side()) {
		q = nearest();
		n = q->nl + pc.nl;
		if (q->nl == PG_UNK || pc.nl == PG_UNK)
			n = PG_UNK;
		else if (n < q->nl || n == PG_UNK)
			goto apart;
		if (dn ? joins(&pc, q) : joins(q, &pc)) {
			if (dn) {
				q->r = pc.r;
				q->o = pc.o;
			} else {
				q->er = pc.er;
				q->eo = pc.eo;
			}
			q->nl = n;
			return 1;
		}
	}
apart:
	if (pg_na + pg_nb == PG_NP) {
		pg_err = "Too many pieces, save the file";
		return 0;
	}
	++*side();
	*nearest() = pc;
	return 1;
}

/* the piece nearest the window on side dn moved to the other */
static void move(void)
{
	pc = *nearest();
	--*side();
	dn = !dn;
	push();
	dn = !dn;
}

/* the pieces on the side with more of them copied to the work file as
   one piece: 0 if that failed */
static u8 compact(void)
{
	u8 d = dn, n, ok = 0;
	PIECE *p;

	dn = pg_na < pg_nb;
	n = *side();
	p = dn ? PG_BELOW : pg_tab;
	if (wwork()) {
		for (; n--; p++) {
			copy(p);
			pc.nl += p->nl;
		}
		if (wdone()) {
			*side() = 0;
			ok = push();
		}
	}
	dn = d;
	return ok;
}

/* two pieces free in the table, made by compact if need be. 0 if not */
static u8 room(void)
{
	if (pg_na + pg_nb + 2 <= PG_NP)
		return 1;
	return compact();
}

unsigned int pg_above(void)
{
	u16 n = 0;
	u8 i;

	for (i = 0; i < pg_na; i++)
		n += pg_tab[i].nl;
	return n;
}

/* ---- The window ---- */

static u8 lasttag;

/* a tag no part has */
static u8 newtag(void)
{
	u8 i;

again:
	if (!++lasttag)
		lasttag = 1;
	for (i = 0; i < pg_np; i++)
		if (pg_part[i].tag == lasttag)
			goto again;
	return lasttag;
}

void pg_touch(unsigned char tag) FAST
{
	u8 i;

	for (i = 0; i < pg_np; i++)
		if (pg_part[i].tag == tag)
			pg_part[i].dirty = 1;
}

unsigned char pg_newtag(void)
{
	if (!pg_np) {
		memset(pg_part, 0, sizeof(PART));
		pg_part[0].tag = newtag();
		pg_part[0].dirty = 1;
		pg_np = 1;
	}
	return pg_part[pg_np - 1].tag;
}

/* the lines with tag tg at side dn of the window dropped */
static void unload(void)
{
	void *l;

	while ((l = ed_end(dn)) && ed_tag(l) == tg)
		ed_drop(l, dn);
}

/* a part read in from the nearest piece on side dn */
static u8 load(void)
{
	PIECE *p;
	u16 c, cost = 0, used = 0, nl = 0;
	int n;

	if (pg_np == PG_NPART || !*side())
		return 0;
	p = nearest();
	pc = *p;
	if (!dn && p->er - p->r > PG_PARTSZ / 128) {
		/* the tail of the piece, from a line's start */
		pc.r = p->er - PG_PARTSZ / 128;
		pc.o = p->eo | (p->o & PG_WORK);
		sopen(&pc);
		do
			n = sgetl();
		while (n >= 0 && !s_lf);
		if (n >= 0 && (s_n || refill()))
			here();		/* unless one line ends it */
	}
	tg = newtag();
	sopen(&pc);
	ed_begin(dn);
	for (;;) {
		if (dn && s_lf && (used >= PG_PARTSZ ||
		    (cost && pg_cost + cost >= pg_budget)))
			break;
		if ((n = sgetl()) < 0)
			break;
		if (!(c = ed_add(pg_line, n, tg)))
			goto fail;
		cost += c;
		used += s_raw;
		nl += s_lf;
	}
	if (pg_err || !used)
		goto fail;
	/* the part: from pc's start to the stream's place */
	c = pc.r;
	n = pc.o;
	here();
	pc.er = pc.r;
	pc.eo = pc.o & 127;
	if (dn) {
		pt = &pg_part[pg_np];
		p->r = pc.r;
		p->o = pc.o;
	} else {
		memmove(pg_part + 1, pg_part, pg_np * sizeof(PART));
		pt = pg_part;
		p->er = c;
		p->eo = n & 127;
	}
	pc.r = c;
	pc.o = n;
	pc.nl = nl;
	pg_np++;
	pt->o = pc;
	pt->cost = cost;
	pt->tag = tg;
	pt->dirty = 0;
	pg_cost += cost;
	if (p->nl != PG_UNK)
		p->nl -= nl;
	if (empty(p))
		--*side();
	return 1;
fail:
	unload();
	return 0;
}

/* the part at side dn of the window out to the list there, unless it is
   within pg_rows lines of keep. Written to the work file if changed */
static u8 evict(void *keep) FAST
{
	void *l, *m;
	u8 i;

	if (!pg_np)
		return 0;
	pt = dn ? &pg_part[pg_np - 1] : pg_part;
	tg = pt->tag;
	for (i = pg_rows; keep; keep = ed_step(keep, dn)) {
		if (ed_tag(keep) == tg)
			return 0;
		if (!i--)
			break;
	}
	if (!room())
		return 0;
	pc = pt->o;
	if (pt->dirty) {
		pc.er = pc.r;
		pc.eo = pc.o & 127;	/* none, if all its lines went */
		l = ed_end(dn);
		if (l && ed_tag(l) == tg) {
			/* written from its first line */
			if (dn)
				while ((m = ed_step(l, 0)) && ed_tag(m) == tg)
					l = m;
			if (!wwork())
				return 0;
			pc.nl = wlines(l);
			if (!wdone())
				return 0;
		}
	}
	unload();
	push();
	pg_cost -= pt->cost;
	pg_np--;
	if (!dn)
		memmove(pg_part, pg_part + 1, pg_np * sizeof(PART));
	return 1;
}

unsigned char pg_free(void *keep) FAST
{
	dn = 0;
	if (evict(keep))
		return 1;
	dn = 1;
	return evict(keep);
}

unsigned char pg_slide(unsigned char down, void *keep)
{
	pg_err = 0;
	for (;;) {
		dn = down;
		if (load())
			break;
		if (pg_err || !*side())
			return 0;
		dn = !down;
		if (!evict(keep)) {
			if (!pg_err)
				pg_err = "Out of memory";
			return 0;
		}
	}
	dn = !down;
	while (pg_cost > pg_budget && evict(keep))
		;
	return 1;
}

/* the window loaded from above while it is short of lines above, then
   both ways up to the budget */
static void fill(void)
{
	u16 k;

	for (k = 0, dn = 0; k < pg_rows && load(); )
		k += pg_part[0].o.nl;
	for (dn = 1; pg_cost < pg_budget && load(); )
		;
	for (dn = 0; pg_cost < pg_budget && load(); )
		;
}

void *pg_goto(unsigned int n) FAST
{
	PIECE *p;
	u16 a, k;
	void *t;

	pg_err = 0;
	for (dn = 0; pg_np; )
		if (!evict(0))
			return 0;
	while (pg_na && pg_above() > n)
		move();
	a = pg_above();
	for (dn = 1; pg_nb; ) {
		p = PG_BELOW;
		if (p->nl == PG_UNK) {
			sopen(p);
			p->nl = scount();
		}
		if (a + p->nl > n || a + p->nl < a)
			break;
		a += p->nl;
		move();
	}
	if (pg_nb && n > a && room()) {
		/* the piece split at the line */
		p = PG_BELOW;
		sopen(p);
		for (k = n - a; k && sgetl() >= 0; )
			k -= s_lf;
		here();
		pc.er = pc.r;
		pc.eo = pc.o & 127;
		pc.r = p->r;
		pc.o = p->o;
		pc.nl = n - a;
		dn = 0;
		if (!pg_err && push()) {
			p->r = pc.er;
			p->o = pc.eo | (p->o & PG_WORK);
			if (p->nl != PG_UNK)
				p->nl -= pc.nl;
			if (empty(p))
				pg_nb--;
		}
	}
	if (pg_err)
		return 0;
	dn = 1;
	t = load() ? ed_end(0) : 0;
	fill();
	return t;
}

/* ---- Open, close, save ---- */

/* the file name, and the work file's */
static void named(const char *name) FAST
{
	strncpy(fname, name, sizeof fname - 1);
	mkname(wname, fname, "$$W");
	mkfcb(ofcb, fname);
	r_rec = 0xFFFF;
}

unsigned char pg_open(const char *name, unsigned int budget)
{
	u16 n;
	u8 i;

	pg_close();
	named(name);
	if (pg_bdos(FN_OPEN, ofcb, 0, 0) == 0xFF)
		return 0;
	pg_bdos(FN_SIZE, ofcb, 0, 0);
	n = ofcb[33] | ofcb[34] << 8;
	memset(&pc, 0, sizeof pc);
	pc.nl = PG_UNK;
	if (n) {
		/* the text ends at the first ^Z of the last record */
		if (pg_bdos(FN_READ, ofcb, --n, rbuf))
			return 0;
		for (i = 0; i < 128 && rbuf[i] != 0x1A; i++)
			;
		if (i == 128) {
			n++;
			i = 0;
		}
		pc.er = n;
		pc.eo = i;
	}
	pg_budget = budget;
	pg_on = 1;
	dn = 1;
	push();
	return 1;
}

static void wclose(void)
{
	if (w_open) {
		pg_bdos(FN_CLOSE, wfcb, 0, 0);
		remove(wname);
		w_open = 0;
	}
	w_fcb = 0;
}

void pg_close(void)
{
	if (pg_on)
		pg_bdos(FN_CLOSE, ofcb, 0, 0);
	wclose();
	pg_on = 0;
	pg_na = pg_nb = pg_np = 0;
	pg_cost = 0;
}

long pg_save(const char *name, unsigned char bak)
{
	char tmp[16];
	PIECE *p, ab;
	void *l;
	long total;

	pg_err = 0;
	mkname(tmp, name, "$$S");
	remove(tmp);
	mkfcb(sfcb, tmp);
	if (pg_bdos(FN_MAKE, sfcb, 0, 0) == 0xFF) {
		pg_err = "Cannot make the file";
		return -1;
	}
	w_fcb = sfcb;
	w_rec = 0;
	w_n = 0;
	w_bad = 0;
	/* the pieces above, the window's parts, the pieces below */
	wstart();
	for (p = pg_tab; p < pg_tab + pg_na; p++) {
		copy(p);
		pc.nl += p->nl;
	}
	wend();
	ab = pc;
	total = pc.nl;
	l = ed_end(0);
	for (pt = pg_part; pt < pg_part + pg_np; pt++) {
		tg = pt->tag;
		wstart();
		if (pt->dirty)
			pc.nl = wlines(l);
		else {
			copy(&pt->o);
			pc.nl = pt->o.nl;
		}
		while (l && ed_tag(l) == tg)
			l = ed_step(l, 1);
		wend();
		pt->o = pc;
		pt->dirty = 0;
		total += pc.nl;
	}
	wstart();
	for (p = PG_BELOW; p < pg_tab + PG_NP; p++) {
		copy(p);
		pc.nl += p->nl;
	}
	wend();
	total += pc.nl;
	if (w_n) {
		memset(wbuf + w_n, 0x1A, 128 - w_n);
		wflush();
	}
	pg_bdos(FN_CLOSE, sfcb, 0, 0);
	if (w_bad || pg_err) {
		remove(tmp);
		w_fcb = 0;
		if (!pg_err)
			pg_err = "Write error";
		return -1;
	}
	/* the new file takes the name */
	pg_bdos(FN_CLOSE, ofcb, 0, 0);
	if (bak) {
		mkname(fname, name, "BAK");
		remove(fname);
		rename(name, fname);
	} else
		remove(name);
	rename(tmp, name);
	/* and the pieces are its */
	wclose();
	named(name);
	pg_bdos(FN_OPEN, ofcb, 0, 0);
	pg_na = pg_nb = 0;
	dn = 1;
	push();
	pc = ab;
	dn = 0;
	push();
	return total;
}
