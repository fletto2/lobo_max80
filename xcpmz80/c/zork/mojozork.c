/**
 * MojoZork; a simple, just-for-fun implementation of Infocom's Z-Machine.
 *
 * Please see the file LICENSE.txt in the source's root directory.
 *
 *  This file written by Ryan C. Gordon.
 */

/*
 * Altered for xcpmz80 on the Lobo MAX-80. This is not the original
 * MojoZork. What changed:
 *
 * - The story is not held in memory. Dynamic memory (bytes 0 up to the
 *   header's static memory base) is resident, and the rest is read from
 *   the story file through a cache of 512-byte pages. A page is found
 *   by its number, the address shifted right by 9, and the cache
 *   evicts by the clock rule. Pointers into the story became
 *   addresses: pages and offsets for the program counter and strings,
 *   16-bit addresses for data. The pages are read by BDOS calls, not
 *   by stdio.
 * - The program counter is a pointer into its page, so reading the
 *   next byte is one compare and one load. Its page is pinned in the
 *   cache, as are the pages of the strings being decoded.
 * - Version 3 only, as before. The opcodes run in one switch.
 * - Separators are words of their own when the input is split, the
 *   dictionary is searched by halves, and the shift to alphabet A2
 *   when encoding a word is 5, as the standard has it.
 * - Text is wrapped at word ends to fit 80 columns.
 * - SAVE and RESTORE ask for a file name. RESTORE of a missing file
 *   fails and the game goes on. VERIFY reads the story file.
 * - output_stream 3 (to memory) works. split_window, set_window,
 *   input_stream and sound_effect do nothing.
 * - The random numbers are xorshift, 16 bits.
 * - No status line, the scripts and #random of the original are gone.
 */

/* The Z-Machine specifications 1.1:
 *     https://inform-fiction.org/zmachine/standards/z1point1/index.html */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <cpm.h>

typedef unsigned char u8;
typedef signed char s8;
typedef unsigned int u16;
typedef signed int s16;
typedef unsigned long u32;

#define PSZ	512		/* bytes in a page */
#define MAXSLOT	72		/* cache pages at most */
#define STKSZ	1024		/* the Z-machine's stack, in words */
#define WIDTH	79		/* columns of text before a wrap */
#define NOSLOT	0xFF

/* ---- The story and its pages ---- */

static u8 fcb[36];		/* the story file's, read by BDOS calls */
static u8 *dyn;			/* dynamic memory, dynpages pages */
static u16 dynlen;		/* dynpages * PSZ */
static u8 dynpages;
static u16 statbase;		/* writes go below this only */

static u8 slotof[256];		/* the cache slot of each page, or NOSLOT */
static u8 *slotbuf[MAXSLOT];
static u8 slotpage[MAXSLOT];
static u8 slotref[MAXSLOT];
static u8 slotpin[MAXSLOT];
static u8 nslots, hand;

/* The header */

static u16 hdr_release, hdr_pcstart, hdr_dict, hdr_objtab, hdr_globals;
static u16 hdr_abbr, hdr_len, hdr_checksum;
static u8 hdr_serial[6];

static u8 *globals;		/* in dyn */
static u8 *objbase;		/* in dyn, object 0's place */

static void die(const char *msg);

/* Records of the story file, read by BDOS function 33 straight into
 * buf. The library's fread goes a byte at a time and is several times
 * slower. A record past the end of the file reads as zeros. */
static u8 readrecs(u16 rec, u8 *buf, u16 n)
{
	u8 bad = 0;

	for (; n; n--, rec++, buf += 128) {
		bdos(26, (u16)buf);
		fcb[33] = rec;
		fcb[34] = rec >> 8;
		fcb[35] = 0;
		if ((u8)bdos(33, (u16)fcb)) {
			memset(buf, 0, 128);
			bad = 1;
		}
	}
	return bad;
}

/* The story's FCB from its name, d:name.typ, and the file opened */
static u8 openstory(const char *name) __z88dk_fastcall
{
	u8 i, c;

	memset(fcb, 0, sizeof fcb);
	memset(fcb + 1, ' ', 11);
	if (name[0] && name[1] == ':') {
		fcb[0] = (name[0] & 0x1F);
		name += 2;
	}
	for (i = 1; *name && *name != '.'; name++)
		if (i < 9)
			fcb[i++] = *name;
	if (*name == '.')
		for (i = 9, name++; *name && i < 12; name++)
			fcb[i++] = *name;
	for (i = 1; i < 12; i++) {
		c = fcb[i];
		if (c >= 'a' && c <= 'z')
			fcb[i] = c - 'a' + 'A';
	}
	return (u8)bdos(15, (u16)fcb) != 0xFF;
}

/* A page that is not in dynamic memory, read into the cache */
static u8 *loadpage(u8 page)
{
	u8 s;
	u8 *buf;

	for (;;) {
		s = hand;
		if (++hand == nslots)
			hand = 0;
		if (slotpin[s])
			continue;
		if (slotref[s]) {
			slotref[s] = 0;
			continue;
		}
		break;
	}
	if (slotpage[s] != NOSLOT)
		slotof[slotpage[s]] = NOSLOT;
	buf = slotbuf[s];
	readrecs((u16)page << 2, buf, PSZ / 128);
	slotpage[s] = page;
	slotof[page] = s;
	slotref[s] = 1;
	return buf;
}

/* The bytes of a page */
static u8 *pagebuf(u8 page) __z88dk_fastcall
{
	u8 s;

	if (page < dynpages)
		return dyn + ((u16)page << 9);
	s = slotof[page];
	if (s != NOSLOT) {
		slotref[s] = 1;
		return slotbuf[s];
	}
	return loadpage(page);
}

static void pin(u8 page) __z88dk_fastcall
{
	if (page >= dynpages)
		slotpin[slotof[page]]++;
}

static void unpin(u8 page) __z88dk_fastcall
{
	if (page >= dynpages)
		slotpin[slotof[page]]--;
}

/* A byte and a word at a 16-bit address */
static u8 rb(u16 a) __z88dk_fastcall
{
	if (a < dynlen)
		return dyn[a];
	return pagebuf((u8)(a >> 9))[a & (PSZ - 1)];
}

static u16 rw(u16 a) __z88dk_fastcall
{
	if (a < dynlen - 1)
		return ((u16)dyn[a] << 8) | dyn[a + 1];
	return ((u16)rb(a) << 8) | rb(a + 1);
}

/* Writes, to dynamic memory only */
static void wb(u16 a, u8 v)
{
	if (a >= statbase)
		die("Write past dynamic memory");
	dyn[a] = v;
}

static void ww(u16 a, u16 v)
{
	if (a + 1 >= statbase)
		die("Write past dynamic memory");
	dyn[a] = v >> 8;
	dyn[a + 1] = v;
}

/* ---- The program counter: a pointer into its pinned page ---- */

static u8 pcpage;
static u8 *pcbase, *pcp, *pcend;

static void pc_go(u8 page, u16 off)
{
	u8 old = pcpage;

	pcbase = pagebuf(page);
	pin(page);
	unpin(old);
	pcpage = page;
	pcp = pcbase + off;
	pcend = pcbase + PSZ;
}

static u8 pc_cross(void)
{
	pc_go(pcpage + 1, 0);
	return *pcp++;
}

#define FETCH()	(pcp != pcend ? *pcp++ : pc_cross())

/* pc += d */
static void pc_rel(s16 d)
{
	s16 o = pcp - pcbase;
	long t;

	if (d >= -o && d <= PSZ - o) {
		pcp += d;
		return;
	}
	t = ((long)pcpage << 9) + o + d;
	pc_go((u8)(t >> 9), (u16)t & (PSZ - 1));
}

/* ---- A cursor for reading strings, its page pinned ---- */

typedef struct {
	u8 page;
	u8 *p, *end;
} Cur;

static void cur_set(Cur *c, u8 page, u16 off)
{
	u8 *b = pagebuf(page);

	pin(page);
	c->page = page;
	c->p = b + off;
	c->end = b + PSZ;
}

static void cur_done(Cur *c) __z88dk_fastcall
{
	unpin(c->page);
}

static u8 cur_byte(Cur *c) __z88dk_fastcall
{
	if (c->p == c->end) {
		u8 page = c->page + 1;
		u8 *b = pagebuf(page);
		pin(page);
		unpin(c->page);
		c->page = page;
		c->p = b;
		c->end = b + PSZ;
	}
	return *c->p++;
}

/* ---- Text out, wrapped at word ends ---- */

static char word[WIDTH + 1];
static u8 wlen, col, spaces;
static u16 s3table;		/* output_stream 3's table, or 0 */
static u16 s3len;

static void rawc(char c) __z88dk_fastcall
{
	bdos(2, (u8)c);
}

static void newline(void)
{
	rawc('\r');
	rawc('\n');
	col = 0;
	spaces = 0;
}

static void flushword(void)
{
	u8 i;

	if (col + spaces + wlen > WIDTH)
		newline();
	else
		for (; spaces; spaces--, col++)
			rawc(' ');
	spaces = 0;
	for (i = 0; i < wlen; i++)
		rawc(word[i]);
	col += wlen;
	wlen = 0;
}

static void outc(char c) __z88dk_fastcall
{
	if (s3table) {
		if (c == '\n')
			c = 13;
		wb(s3table + 2 + s3len++, c);
		return;
	}
	if (c == '\n') {
		flushword();
		newline();
	} else if (c == ' ') {
		flushword();
		spaces++;
	} else {
		word[wlen++] = c;
		if (wlen == WIDTH)
			flushword();
	}
}

/* All of the text out, the spaces too, before input */
static void flushall(void)
{
	flushword();
	for (; spaces && col < WIDTH; spaces--, col++)
		rawc(' ');
	spaces = 0;
}

static void outs(const char *s) __z88dk_fastcall
{
	while (*s)
		outc(*s++);
}

static void die(const char *msg)
{
	flushall();
	printf("\r\nERROR: %s (pc=%lX)\r\n", msg,
		((long)pcpage << 9) + (pcp - pcbase));
	exit(1);
}

/* ---- Strings ---- */

static const char a2table[] = "\n0123456789.,!?_#'\"/\\-:()";

static void zchar_out(u16 z) __z88dk_fastcall
{
	if (z >= 32 && z <= 126)
		outc((char)z);
	else if (z == 13)
		outc('\n');
	else if (z)
		outc('?');
}

/* Decode the string at the cursor, leaving the cursor after it */
static void decode(Cur *c, u8 abbr)
{
	u16 code;
	s8 i;
	u8 ch, alphabet = 0, useabbr = 0, collect = 0;
	u16 zscii = 0;

	do {
		code = (u16)cur_byte(c) << 8;
		code |= cur_byte(c);
		for (i = 10; i >= 0; i -= 5) {
			ch = (code >> i) & 0x1F;
			if (collect) {
				if (collect == 2)
					zscii = (u16)ch << 5;
				else
					zscii |= ch;
				if (!--collect) {
					zchar_out(zscii);
					alphabet = 0;
				}
				continue;
			}
			if (useabbr) {
				u16 a;
				Cur ac;
				if (abbr)
					die("Abbreviation in an abbreviation");
				a = rw(hdr_abbr + ((32 * (useabbr - 1) + ch) << 1));
				cur_set(&ac, a >> 8, (a & 0xFF) << 1);
				decode(&ac, 1);
				cur_done(&ac);
				useabbr = 0;
				alphabet = 0;
				continue;
			}
			switch (ch) {
			case 0:
				outc(' ');
				alphabet = 0;
				break;
			case 1:
			case 2:
			case 3:
				useabbr = ch;
				break;
			case 4:
			case 5:
				alphabet = ch - 3;
				break;
			default:
				if (alphabet == 0)
					outc('a' + ch - 6);
				else if (alphabet == 1)
					outc('A' + ch - 6);
				else if (ch == 6)
					collect = 2;
				else
					outc(a2table[ch - 7]);
				if (ch != 6 || alphabet != 2)
					alphabet = 0;
				break;
			}
		}
	} while (!(code & 0x8000));
}

/* The string at a byte address */
static void print_at(u16 a) __z88dk_fastcall
{
	Cur c;

	cur_set(&c, a >> 9, a & (PSZ - 1));
	decode(&c, 0);
	cur_done(&c);
}

/* The string at a packed address */
static void print_packed(u16 p) __z88dk_fastcall
{
	Cur c;

	cur_set(&c, p >> 8, (p & 0xFF) << 1);
	decode(&c, 0);
	cur_done(&c);
}

/* The string after the opcode, and the pc after it */
static void print_inline(void)
{
	Cur c;

	if (pcp == pcend)
		pc_go(pcpage + 1, 0);
	cur_set(&c, pcpage, pcp - pcbase);
	decode(&c, 0);
	pc_go(c.page, c.p - (c.end - PSZ));
	cur_done(&c);
}

static void print_num(s16 n) __z88dk_fastcall
{
	char buf[7];
	u8 i = 0;
	u16 u;

	if (n < 0) {
		outc('-');
		u = -n;
	} else
		u = n;
	do {
		buf[i++] = '0' + u % 10;
		u /= 10;
	} while (u);
	while (i)
		outc(buf[--i]);
}

/* ---- Variables and the stack ---- */

static u16 stack[STKSZ];
static u16 *sp;
static u16 bp;			/* the frame's locals, an index in stack */
static u16 *locals;

static u16 getvar(u8 v) __z88dk_fastcall
{
	u8 *g;

	if (v == 0) {
		if (sp == stack)
			die("Stack underflow");
		return *--sp;
	}
	if (v < 16)
		return locals[v - 1];
	g = globals + ((u16)(v - 16) << 1);
	return ((u16)g[0] << 8) | g[1];
}

static void setvar(u8 v, u16 x)
{
	u8 *g;

	if (v == 0) {
		if (sp == stack + STKSZ)
			die("Stack overflow");
		*sp++ = x;
	} else if (v < 16)
		locals[v - 1] = x;
	else {
		g = globals + ((u16)(v - 16) << 1);
		g[0] = x >> 8;
		g[1] = x;
	}
}

/* The indirect forms: the top of the stack is read and written in place */
static u16 getvar_ind(u8 v) __z88dk_fastcall
{
	if (v == 0) {
		if (sp == stack)
			die("Stack underflow");
		return sp[-1];
	}
	return getvar(v);
}

static void setvar_ind(u8 v, u16 x)
{
	if (v == 0) {
		if (sp == stack)
			die("Stack underflow");
		sp[-1] = x;
	} else
		setvar(v, x);
}

#define STORE(x)	setvar(FETCH(), (x))

static void doreturn(u16 val) __z88dk_fastcall
{
	u8 page, storeid;
	u16 off;

	if (bp == 0)
		die("Return from the main routine");
	sp = stack + bp;
	sp--;			/* the count of locals */
	bp = *--sp;
	off = *--sp;
	page = (u8)*--sp;
	storeid = (u8)*--sp;
	locals = stack + bp;
	pc_go(page, off);
	setvar(storeid, val);
}

static void branch(u8 truth) __z88dk_fastcall
{
	u8 b = FETCH();
	s16 off;

	if (b & 0x40)
		off = b & 0x3F;
	else {
		off = ((u16)(b & 0x3F) << 8) | FETCH();
		if (b & 0x20)
			off |= 0xC000;
	}
	if (((b & 0x80) != 0) != (truth != 0))
		return;
	if (off == 0)
		doreturn(0);
	else if (off == 1)
		doreturn(1);
	else
		pc_rel(off - 2);
}

static u16 ops[4];
static u8 nops;

static void call(void)
{
	u8 storeid = FETCH();
	u8 nl, i, page;
	u16 off;
	u16 *frame;
	Cur c;

	if (ops[0] == 0) {
		setvar(storeid, 0);
		return;
	}
	page = ops[0] >> 8;
	off = (ops[0] & 0xFF) << 1;
	cur_set(&c, page, off);
	nl = cur_byte(&c);
	if (nl > 15)
		die("Too many locals");
	if (sp + 5 + nl > stack + STKSZ)
		die("Stack overflow");
	*sp++ = storeid;
	*sp++ = pcpage;
	*sp++ = pcp - pcbase;
	*sp++ = bp;
	*sp++ = nl;
	bp = sp - stack;
	frame = sp;
	locals = sp;
	for (i = 0; i < nl; i++) {
		off = (u16)cur_byte(&c) << 8;
		*sp++ = off | cur_byte(&c);
	}
	for (i = 1; i < nops && i <= nl; i++)
		frame[i - 1] = ops[i];
	pc_go(c.page, c.p - (c.end - PSZ));
	cur_done(&c);
}

/* ---- Objects, version 3: 9 bytes each ---- */

static u8 *obj(u16 id) __z88dk_fastcall
{
	if (id == 0 || id > 255)
		die("Bad object number");
	return objbase + (id << 3) + id;
}

/* The object's first property, its size byte */
static u8 *props(u16 id) __z88dk_fastcall
{
	u8 *o = obj(id);
	u16 a = ((u16)o[7] << 8) | o[8];

	if (a >= dynlen)
		die("Property table not in dynamic memory");
	return dyn + a + 1 + (dyn[a] << 1);
}

/* The property's size byte, or NULL */
static u8 *findprop(u16 id, u8 prop)
{
	u8 *p = props(id);
	u8 n;

	while ((n = *p & 0x1F) > prop)
		p += (*p >> 5) + 2;
	return n == prop && n ? p : NULL;
}

static void unparent(u8 id) __z88dk_fastcall
{
	u8 *o = obj(id);
	u8 *p;

	if (!o[4])
		return;
	p = obj(o[4]) + 6;
	while (*p != id)
		p = obj(*p) + 5;
	*p = o[5];
	o[4] = 0;
	o[5] = 0;
}

/* ---- Input ---- */

static char line[130];

static void readline(void)
{
	flushall();
	if (!fgets(line, sizeof line, stdin))
		exit(0);
	col = 0;
	spaces = 0;
}

static u8 isep(u8 c, u8 nseps, u16 seps)
{
	u8 i;

	for (i = 0; i < nseps; i++)
		if (rb(seps + i) == c)
			return 1;
	return 0;
}

/* Look up a word of 6 Z-characters, encoded */
static u16 lookup(u16 w0, u16 w1, u16 dict, u16 count, u8 entlen)
{
	u16 lo = 0, hi = count, mid, a, e;
	u8 less;

	while (lo < hi) {
		mid = (lo + hi) >> 1;
		a = dict + mid * entlen;
		e = rw(a);
		if (e == w0) {
			e = rw(a + 2);
			if (e == w1)
				return a;
			less = e < w1;
		} else
			less = e < w0;
		if (less)
			lo = mid + 1;
		else
			hi = mid;
	}
	return 0;
}

static void tokenize(u16 text, u16 parse)
{
	u16 seps = hdr_dict + 1;
	u8 nseps = rb(hdr_dict);
	u16 d = seps + nseps;
	u8 entlen = rb(d);
	u16 count = rw(d + 1);
	u8 maxtok = dyn[parse];
	u8 ntok = 0, pos = 1, start, len, n, i, k;
	u8 z[10];
	u16 w0, w1, a;
	char ch;
	const char *q;

	d += 3;
	while (ntok < maxtok) {
		while (dyn[text + pos] == ' ')
			pos++;
		ch = dyn[text + pos];
		if (!ch)
			break;
		start = pos;
		if (isep(ch, nseps, seps))
			pos++;
		else
			while ((ch = dyn[text + pos]) && ch != ' '
			    && !isep(ch, nseps, seps))
				pos++;
		len = pos - start;
		n = 0;
		for (i = 0; i < len && n < 6; i++) {
			ch = dyn[text + start + i];
			if (ch >= 'a' && ch <= 'z')
				z[n++] = ch - 'a' + 6;
			else if ((q = strchr(a2table + 1, ch)) != NULL) {
				z[n++] = 5;
				z[n++] = q - a2table + 7;
			} else {
				z[n++] = 5;
				z[n++] = 6;
				z[n++] = ch >> 5;
				z[n++] = ch & 0x1F;
			}
		}
		for (k = n; k < 6; k++)
			z[k] = 5;
		w0 = (z[0] << 10) | (z[1] << 5) | z[2];
		w1 = (z[3] << 10) | (z[4] << 5) | z[5] | 0x8000;
		a = lookup(w0, w1, d, count, entlen);
		ww(parse + 2 + (ntok << 2), a);
		dyn[parse + 4 + (ntok << 2)] = len;
		dyn[parse + 5 + (ntok << 2)] = start;
		ntok++;
	}
	dyn[parse + 1] = ntok;
}

static void sread(void)
{
	u16 text = ops[0], parse = ops[1];
	u8 max, n, i;
	char ch;

	if (text + 2 >= statbase || parse + 2 >= statbase)
		die("Read buffers not in dynamic memory");
	max = dyn[text];
	if (max < 3)
		die("Text buffer too small");
	readline();
	n = strlen(line);
	if (n && line[n - 1] == '\n')
		n--;
	if (n > max - 1)
		n = max - 1;
	for (i = 0; i < n; i++) {
		ch = line[i];
		if (ch >= 'A' && ch <= 'Z')
			ch += 'a' - 'A';
		dyn[text + 1 + i] = ch;
	}
	dyn[text + 1 + n] = 0;
	tokenize(text, parse);
}

/* ---- Save, restore, restart, verify ---- */

static const char magic[4] = { 'M', 'Z', '8', '0' };

/* A file name from the player, .SAV when it has no type */
static u8 askname(const char *what)
{
	char *p;
	u8 n;

	outs(what);
	outs(" file name: ");
	readline();
	n = strlen(line);
	while (n && (line[n - 1] == '\n' || line[n - 1] == ' '))
		line[--n] = 0;
	p = line;
	while (*p == ' ')
		p++;
	if (!*p)
		return 0;
	if (p != line)
		memmove(line, p, strlen(p) + 1);
	if (!strchr(line, '.') && strlen(line) <= 8)
		strcat(line, ".SAV");
	return 1;
}

static const char *storyname;	/* argv[1], for zsave's check */

/* The name after its drive or folder */
static const char *basename_of(const char *n)
{
	const char *b = n;
	for (; *n; n++)
		if (*n == ':' || *n == '\\' || *n == '/')
			b = n + 1;
	return b;
}

static u8 savehdr[14];

static void makehdr(void)
{
	memcpy(savehdr, magic, 4);
	savehdr[4] = hdr_release >> 8;
	savehdr[5] = hdr_release;
	memcpy(savehdr + 6, hdr_serial, 6);
	savehdr[12] = hdr_checksum >> 8;
	savehdr[13] = hdr_checksum;
}

static void zsave(void)
{
	FILE *f;
	u8 ok = 0;
	u16 st[4];

	if (askname("Save") &&	/* not over the story itself (I287) */
	    strcasecmp(basename_of(line), basename_of(storyname)) != 0) {
		makehdr();
		st[0] = pcpage;
		st[1] = pcp - pcbase;
		st[2] = sp - stack;
		st[3] = bp;
		if ((f = fopen(line, "wb")) != NULL) {
			ok = fwrite(savehdr, 1, 14, f) == 14
			    && fwrite(dyn, 1, statbase, f) == statbase
			    && fwrite(st, 1, 8, f) == 8
			    && fwrite(stack, 2, st[2], f) == st[2];
			if (fclose(f))
				ok = 0;
			if (!ok)
				remove(line);
		}
	}
	branch(ok);
}

static void zrestore(void)
{
	FILE *f;
	u8 h[14];
	u16 st[4];
	u8 ok = 0;

	if (askname("Restore") && (f = fopen(line, "rb")) != NULL) {
		makehdr();
		if (fread(h, 1, 14, f) == 14 && !memcmp(h, savehdr, 14)) {
			/* past here a short file leaves the game broken */
			if (fread(dyn, 1, statbase, f) != statbase
			    || fread(st, 1, 8, f) != 8 || st[2] > STKSZ
			    || fread(stack, 2, st[2], f) != st[2])
				die("The save file is cut short");
			sp = stack + st[2];
			bp = st[3];
			locals = stack + bp;
			pc_go((u8)st[0], st[1]);
			ok = 1;
		} else
			outs("That is not a save of this story.\n");
		fclose(f);
	}
	branch(ok);
}

/* The header as the interpreter sets it */
static void sethdr(void)
{
	dyn[1] |= 0x10;		/* no status line */
	dyn[1] &= ~0x20;	/* no split screen */
}

static void loaddyn(void)
{
	if (readrecs(0, dyn, dynlen / 128))
		die("The story file is too short");
	sethdr();
}

static void restart(void)
{
	u8 flags2 = dyn[0x11];

	loaddyn();
	dyn[0x11] = (dyn[0x11] & ~3) | (flags2 & 3);
	sp = stack;
	bp = 0;
	locals = stack;
	pc_go(hdr_pcstart >> 9, hdr_pcstart & (PSZ - 1));
}

static u8 verified;		/* 0 not yet, 1 good, 2 bad */

static void verify(void)
{
	u8 buf[128];
	u32 left;
	u16 sum = 0, n, i, rec;

	if (!verified) {
		left = (u32)hdr_len << 1;
		for (rec = 0; left; rec++) {
			if (readrecs(rec, buf, 1))
				break;
			n = left > 128 ? 128 : left;
			for (i = rec ? 0 : 64; i < n; i++)
				sum += buf[i];
			left -= n;
		}
		verified = (!left && sum == hdr_checksum) ? 1 : 2;
	}
	branch(verified == 1);
}

/* ---- Random numbers ---- */

static u16 rnd = 1;

static u16 random16(void)
{
	rnd ^= rnd << 7;
	rnd ^= rnd >> 9;
	rnd ^= rnd << 8;
	return rnd;
}

static u16 zrandom(s16 range) __z88dk_fastcall
{
	if (range > 0)
		return random16() % (u16)range + 1;
	if (range == 0)
		rnd = (u16)time(NULL) | 1;
	else
		rnd = -range;
	return 0;
}

/* ---- The interpreter ---- */

static void run(void)
{
	u8 op, t, i;
	u16 a, b;
	u8 *p;

	for (;;) {
		op = FETCH();
		if (op < 0x80) {		/* 2OP, long form */
			ops[0] = (op & 0x40) ? getvar(FETCH()) : FETCH();
			ops[1] = (op & 0x20) ? getvar(FETCH()) : FETCH();
			nops = 2;
			op &= 0x1F;
		} else if (op < 0xB0) {		/* 1OP */
			t = op & 0x30;
			if (t == 0) {
				a = (u16)FETCH() << 8;
				ops[0] = a | FETCH();
			} else if (t == 0x10)
				ops[0] = FETCH();
			else
				ops[0] = getvar(FETCH());
			nops = 1;
			op = 0x20 | (op & 0x0F);
		} else if (op < 0xC0) {		/* 0OP */
			nops = 0;
			op = 0x30 | (op & 0x0F);
		} else {			/* VAR */
			t = FETCH();
			for (i = 0; i < 4; i++, t <<= 2) {
				switch (t & 0xC0) {
				case 0x00:
					a = (u16)FETCH() << 8;
					ops[i] = a | FETCH();
					continue;
				case 0x40:
					ops[i] = FETCH();
					continue;
				case 0x80:
					ops[i] = getvar(FETCH());
					continue;
				}
				break;
			}
			nops = i;
			op = op < 0xE0 ? op & 0x1F : 0x40 | (op & 0x1F);
		}
		a = ops[0];
		b = ops[1];

		switch (op) {
		/* 2OP */
		case 0x01:	/* je */
			t = 0;
			for (i = 1; i < nops; i++)
				if (a == ops[i])
					t = 1;
			branch(t);
			break;
		case 0x02:	/* jl */
			branch((s16)a < (s16)b);
			break;
		case 0x03:	/* jg */
			branch((s16)a > (s16)b);
			break;
		case 0x04:	/* dec_chk */
			a = getvar_ind((u8)ops[0]) - 1;
			setvar_ind((u8)ops[0], a);
			branch((s16)a < (s16)b);
			break;
		case 0x05:	/* inc_chk */
			a = getvar_ind((u8)ops[0]) + 1;
			setvar_ind((u8)ops[0], a);
			branch((s16)a > (s16)b);
			break;
		case 0x06:	/* jin */
			branch(a && obj(a)[4] == b);
			break;
		case 0x07:	/* test */
			branch((a & b) == b);
			break;
		case 0x08:	/* or */
			STORE(a | b);
			break;
		case 0x09:	/* and */
			STORE(a & b);
			break;
		case 0x0A:	/* test_attr */
			branch(obj(a)[b >> 3] & (0x80 >> (b & 7)));
			break;
		case 0x0B:	/* set_attr */
			obj(a)[b >> 3] |= 0x80 >> (b & 7);
			break;
		case 0x0C:	/* clear_attr */
			if (a)
				obj(a)[b >> 3] &= ~(0x80 >> (b & 7));
			break;
		case 0x0D:	/* store */
			setvar_ind((u8)a, b);
			break;
		case 0x0E:	/* insert_obj */
			unparent((u8)a);
			p = obj(b);
			obj(a)[4] = (u8)b;
			obj(a)[5] = p[6];
			p[6] = (u8)a;
			break;
		case 0x0F:	/* loadw */
			STORE(rw(a + (b << 1)));
			break;
		case 0x10:	/* loadb */
			STORE(rb(a + b));
			break;
		case 0x11:	/* get_prop */
			p = findprop(a, (u8)b);
			if (!p)
				a = rw(hdr_objtab + ((b - 1) << 1));
			else if (*p < 0x20)
				a = p[1];
			else
				a = ((u16)p[1] << 8) | p[2];
			STORE(a);
			break;
		case 0x12:	/* get_prop_addr */
			p = findprop(a, (u8)b);
			STORE(p ? (u16)(p + 1 - dyn) : 0);
			break;
		case 0x13:	/* get_next_prop */
			if (b == 0)
				p = props(a);
			else {
				p = findprop(a, (u8)b);
				if (!p)
					die("get_next_prop of a missing property");
				p += (*p >> 5) + 2;
			}
			STORE(*p & 0x1F);
			break;
		case 0x14:	/* add */
			STORE(a + b);
			break;
		case 0x15:	/* sub */
			STORE(a - b);
			break;
		case 0x16:	/* mul */
			STORE(a * b);
			break;
		case 0x17:	/* div */
			if (!b)
				die("Division by zero");
			STORE((s16)a / (s16)b);
			break;
		case 0x18:	/* mod */
			if (!b)
				die("Division by zero");
			STORE((s16)a % (s16)b);
			break;

		/* 1OP */
		case 0x20:	/* jz */
			branch(a == 0);
			break;
		case 0x21:	/* get_sibling */
			t = obj(a)[5];
			STORE(t);
			branch(t);
			break;
		case 0x22:	/* get_child */
			t = obj(a)[6];
			STORE(t);
			branch(t);
			break;
		case 0x23:	/* get_parent */
			STORE(obj(a)[4]);
			break;
		case 0x24:	/* get_prop_len */
			STORE(a ? (rb(a - 1) >> 5) + 1 : 0);
			break;
		case 0x25:	/* inc */
			setvar_ind((u8)a, getvar_ind((u8)a) + 1);
			break;
		case 0x26:	/* dec */
			setvar_ind((u8)a, getvar_ind((u8)a) - 1);
			break;
		case 0x27:	/* print_addr */
			print_at(a);
			break;
		case 0x29:	/* remove_obj */
			unparent((u8)a);
			break;
		case 0x2A:	/* print_obj */
			p = obj(a);
			b = ((u16)p[7] << 8) | p[8];
			if (dyn[b])
				print_at(b + 1);
			break;
		case 0x2B:	/* ret */
			doreturn(a);
			break;
		case 0x2C:	/* jump */
			pc_rel((s16)a - 2);
			break;
		case 0x2D:	/* print_paddr */
			print_packed(a);
			break;
		case 0x2E:	/* load */
			STORE(getvar_ind((u8)a));
			break;
		case 0x2F:	/* not */
			STORE(~a);
			break;

		/* 0OP */
		case 0x30:	/* rtrue */
			doreturn(1);
			break;
		case 0x31:	/* rfalse */
			doreturn(0);
			break;
		case 0x32:	/* print */
			print_inline();
			break;
		case 0x33:	/* print_ret */
			print_inline();
			outc('\n');
			doreturn(1);
			break;
		case 0x34:	/* nop */
			break;
		case 0x35:	/* save */
			zsave();
			break;
		case 0x36:	/* restore */
			zrestore();
			break;
		case 0x37:	/* restart */
			outc('\n');
			restart();
			break;
		case 0x38:	/* ret_popped */
			doreturn(getvar(0));
			break;
		case 0x39:	/* pop */
			getvar(0);
			break;
		case 0x3A:	/* quit */
			flushall();
			return;
		case 0x3B:	/* new_line */
			outc('\n');
			break;
		case 0x3C:	/* show_status */
			break;
		case 0x3D:	/* verify */
			verify();
			break;

		/* VAR */
		case 0x40:	/* call */
			call();
			break;
		case 0x41:	/* storew */
			ww(a + (b << 1), ops[2]);
			break;
		case 0x42:	/* storeb */
			wb(a + b, (u8)ops[2]);
			break;
		case 0x43:	/* put_prop */
			p = findprop(a, (u8)b);
			if (!p)
				die("put_prop of a missing property");
			if ((u16)(p + 3 - dyn) > statbase)
				die("Write past dynamic memory");
			if (*p < 0x20)
				p[1] = (u8)ops[2];
			else {
				p[1] = ops[2] >> 8;
				p[2] = (u8)ops[2];
			}
			break;
		case 0x44:	/* sread */
			sread();
			break;
		case 0x45:	/* print_char */
			zchar_out(a);
			break;
		case 0x46:	/* print_num */
			print_num((s16)a);
			break;
		case 0x47:	/* random */
			STORE(zrandom((s16)a));
			break;
		case 0x48:	/* push */
			setvar(0, a);
			break;
		case 0x49:	/* pull */
			b = getvar(0);
			setvar_ind((u8)a, b);
			break;
		case 0x4A:	/* split_window */
		case 0x4B:	/* set_window */
		case 0x54:	/* input_stream */
		case 0x55:	/* sound_effect */
			break;
		case 0x53:	/* output_stream */
			if ((s16)a == 3) {
				s3table = b;
				s3len = 0;
			} else if ((s16)a == -3 && s3table) {
				ww(s3table, s3len);
				s3table = 0;
			}
			break;
		default:
			die("Unknown opcode");
		}
	}
}

static void usage(void)
{
	printf("Usage: ZORK STORY.DAT, a Z-machine version 3 story\r\n");
	exit(1);
}

int main(int argc, char **argv)
{
	u8 h[0x20];
	u8 i;

	if (argc < 2)
		usage();
	storyname = argv[1];
	if (!openstory(argv[1])) {
		printf("Cannot open %s\r\n", argv[1]);
		exit(1);
	}
	readrecs(0, (u8 *)line, 1);
	memcpy(h, line, sizeof h);
	if (h[0] != 3) {
		printf("%s is not a version 3 story\r\n", argv[1]);
		exit(1);
	}

	hdr_release = (h[2] << 8) | h[3];
	hdr_pcstart = (h[6] << 8) | h[7];
	hdr_dict = (h[8] << 8) | h[9];
	hdr_objtab = (h[0x0A] << 8) | h[0x0B];
	hdr_globals = (h[0x0C] << 8) | h[0x0D];
	statbase = (h[0x0E] << 8) | h[0x0F];
	memcpy(hdr_serial, h + 0x12, 6);
	hdr_abbr = (h[0x18] << 8) | h[0x19];
	hdr_len = (h[0x1A] << 8) | h[0x1B];
	hdr_checksum = (h[0x1C] << 8) | h[0x1D];

	dynpages = (statbase + PSZ - 1) >> 9;
	dynlen = (u16)dynpages << 9;
	dyn = malloc(dynlen);
	if (!dyn) {
		printf("Not enough memory for %u bytes of dynamic memory\r\n",
			dynlen);
		exit(1);
	}
	/* The cache: what memory is left, less 2K for the library */
	for (nslots = 0; nslots < MAXSLOT; nslots++) {
		slotbuf[nslots] = malloc(PSZ);
		if (!slotbuf[nslots])
			break;
	}
	for (i = 0; i < 4 && nslots > 8; i++)
		free(slotbuf[--nslots]);
	if (nslots < 8) {
		printf("Not enough memory for the page cache\r\n");
		exit(1);
	}
	memset(slotof, NOSLOT, sizeof slotof);
	memset(slotpage, NOSLOT, sizeof slotpage);

	globals = dyn + hdr_globals;
	objbase = dyn + hdr_objtab + 62 - 9;
	zrandom(0);
	pcpage = 0;		/* in dyn, so pc_go unpins nothing */
	restart();
	run();
	return 0;
}
