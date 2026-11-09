/* BASE64 for xcpmz80: files to and from a host as text, LZSS
 * compressed, then base64. The stream is agfa9000's BASE64 v2.0, which
 * its host tool host.c reads and writes: 4 bytes of the size, big
 * endian, then groups of a flag byte and 8 items, a set bit a literal
 * byte, a clear one a match of 2 bytes (length - 3 in the top 4 bits,
 * offset - 1 in 12 bits, a 4K window, 3 to 18 bytes).
 *
 *   BASE64 FILE            FILE to the screen as base64
 *   BASE64 -D FILE         base64 typed or pasted, to FILE, ended by
 *                          a '.' alone on a line
 *   BASE64 -D FILE TEXT    the same, read from the file TEXT
 *
 * agfa9000's version holds the whole file in memory and searches all
 * of the window for each byte. This one streams both ways and finds
 * matches through hash chains, so any size of file goes, at the Z80's
 * speed. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <conio.h>

#define WINSZ	4096
#define MINM	3
#define MAXM	18
#define RING	8192		/* the window and the look-ahead */
#define RMASK	(RING - 1)
#define HSIZE	1024
#define DEPTH	24		/* matches tried a byte */

static unsigned char ring[RING];
static unsigned int head[HSIZE];
static unsigned int prev[WINSZ];

/* ---- base64 out, 76 columns ---- */

static const char b64[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static unsigned char tri[3];
static unsigned char ntri, col;

static void b64out(void)
{
	char o[4];
	unsigned char i;

	o[0] = b64[tri[0] >> 2];
	o[1] = b64[((tri[0] & 3) << 4) | (ntri > 1 ? tri[1] >> 4 : 0)];
	o[2] = ntri > 1 ? b64[((tri[1] & 15) << 2) | (ntri > 2 ? tri[2] >> 6 : 0)] : '=';
	o[3] = ntri > 2 ? b64[tri[2] & 63] : '=';
	for (i = 0; i < 4; i++) {
		putchar(o[i]);
		if (++col == 76) {
			putchar('\n');
			col = 0;
		}
	}
	ntri = 0;
}

static void emit(unsigned char c)
{
	tri[ntri++] = c;
	if (ntri == 3)
		b64out();
}

/* ---- encode ---- */

static unsigned char grp[1 + 16], ngrp, nitem;

static void item_end(void)
{
	if (++nitem == 8) {
		unsigned char i;

		for (i = 0; i < ngrp; i++)
			emit(grp[i]);
		ngrp = 1;
		nitem = 0;
		grp[0] = 0;
	}
}

static unsigned int hash(unsigned int p)
{
	return ((ring[p & RMASK] << 5) ^ (ring[(p + 1) & RMASK] << 2) ^
		ring[(p + 2) & RMASK]) & (HSIZE - 1);
}

static int encode(const char *name)
{
	FILE *f = fopen(name, "rb");
	long size, ip, got;
	unsigned int i;

	if (!f) {
		printf("BASE64: no file %s\n", name);
		return 1;
	}
	fseek(f, 0, SEEK_END);
	size = ftell(f);
	fseek(f, 0, SEEK_SET);
	emit(size >> 24);
	emit(size >> 16);
	emit(size >> 8);
	emit(size);
	for (i = 0; i < HSIZE; i++)
		head[i] = 0x8000;	/* far back: no match */
	ngrp = 1;
	nitem = 0;
	grp[0] = 0;
	got = 0;
	for (ip = 0; ip < size; ) {
		unsigned int p, best = 0, boff = 0, dist, last = 0;
		unsigned char look, n;
		unsigned char depth = DEPTH;

		while (got < size && got < ip + MAXM) {
			int c = getc(f);

			if (c == EOF) {
				size = got;	/* shorter than it said */
				break;
			}
			ring[(unsigned int)got & RMASK] = c;
			got++;
		}
		if (ip >= size)
			break;
		look = size - ip > MAXM ? MAXM : size - ip;
		if (look >= MINM) {
			p = head[hash(ip)];
			while (depth--) {
				dist = (unsigned int)ip - p;
				if (dist == 0 || dist > WINSZ || dist <= last ||
				    dist > ip)
					break;
				last = dist;
				for (n = 0; n < look &&
				     ring[(p + n) & RMASK] == ring[((unsigned int)ip + n) & RMASK]; n++)
					;
				if (n > best) {
					best = n;
					boff = dist;
					if (n == look)
						break;
				}
				p = prev[p & (WINSZ - 1)];
			}
		}
		if (best >= MINM) {
			grp[ngrp++] = ((best - MINM) << 4) | ((boff - 1) >> 8);
			grp[ngrp++] = boff - 1;
		} else {
			best = 1;
			grp[0] |= 1 << nitem;
			grp[ngrp++] = ring[(unsigned int)ip & RMASK];
		}
		item_end();
		/* each byte passed goes into its chain */
		for (n = best; n; n--, ip++)
			if (ip + MINM <= size && ip + MINM <= got) {
				unsigned int h = hash(ip);

				prev[(unsigned int)ip & (WINSZ - 1)] = head[h];
				head[h] = ip;
			}
	}
	fclose(f);
	if (nitem)
		for (i = 0; i < ngrp; i++)
			emit(grp[i]);
	if (ntri)
		b64out();
	if (col)
		putchar('\n');
	return 0;
}

/* ---- decode ---- */

static FILE *out;
static long dsize, dgot;
static unsigned char hdr, dflags, dbit, dhalf, db1;
static unsigned int rpos;

/* one byte of the LZSS stream */
static void lzbyte(unsigned char c)
{
	if (hdr < 4) {
		dsize = dsize << 8 | c;
		hdr++;
		return;
	}
	if (dgot >= dsize)
		return;
	if (dbit == 8) {
		dflags = c;
		dbit = 0;
		return;
	}
	if (dflags & (1 << dbit)) {
		ring[rpos++ & (WINSZ - 1)] = c;
		putc(c, out);
		dgot++;
		dbit++;
		return;
	}
	if (!dhalf) {
		db1 = c;
		dhalf = 1;
		return;
	}
	dhalf = 0;
	dbit++;
	{
		unsigned char len = (db1 >> 4) + MINM;
		unsigned int from = rpos - ((((unsigned int)db1 & 15) << 8 | c) + 1);

		while (len-- && dgot < dsize) {
			unsigned char b = ring[from++ & (WINSZ - 1)];

			ring[rpos++ & (WINSZ - 1)] = b;
			putc(b, out);
			dgot++;
		}
	}
}

static int b64val(int c)
{
	if (c >= 'A' && c <= 'Z')
		return c - 'A';
	if (c >= 'a' && c <= 'z')
		return c - 'a' + 26;
	if (c >= '0' && c <= '9')
		return c - '0' + 52;
	if (c == '+')
		return 62;
	if (c == '/')
		return 63;
	return -1;
}

static int decode(const char *name, const char *text)
{
	FILE *in = 0;
	unsigned char quad[4], nq = 0, pads = 0, sol = 1;
	int c, v;

	if (text && !(in = fopen(text, "r"))) {
		printf("BASE64: no file %s\n", text);
		return 1;
	}
	out = fopen(name, "wb");
	if (!out) {
		printf("BASE64: cannot make %s\n", name);
		return 1;
	}
	dbit = 8;
	if (!in)
		puts("Paste base64, then '.' alone on a line:");
	for (;;) {
		if (in) {
			c = getc(in);
			if (c == EOF || c == 0x1A)
				break;
		} else {
			c = getch();
			if (c == 3) {
				fclose(out);
				remove(name);
				puts("\nStopped.");
				return 1;
			}
		}
		if (c == '\r' || c == '\n') {
			sol = 1;
			continue;
		}
		if (c == '.' && sol)
			break;
		sol = 0;
		if (c == '=') {
			v = 0;
			pads++;
		} else if ((v = b64val(c)) < 0)
			continue;
		quad[nq++] = v;
		if (nq == 4) {
			lzbyte(quad[0] << 2 | quad[1] >> 4);
			if (pads < 2)
				lzbyte(quad[1] << 4 | quad[2] >> 2);
			if (pads < 1)
				lzbyte(quad[2] << 6 | quad[3]);
			if (pads)
				break;
			nq = 0;
		}
	}
	if (in)
		fclose(in);
	if (fclose(out) || hdr < 4 || dgot != dsize) {
		printf("BASE64: %s is short, %ld of %ld bytes\n", name, dgot, dsize);
		return 1;
	}
	printf("%ld bytes to %s\n", dgot, name);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 2 && argv[1][0] != '-')
		return encode(argv[1]);
	if ((argc == 3 || argc == 4) && (argv[1][0] == '-') &&
	    (argv[1][1] == 'D' || argv[1][1] == 'd') && !argv[1][2])
		return decode(argv[2], argc == 4 ? argv[3] : 0);
	puts("BASE64 FILE: FILE to the screen as base64\n"
	     "BASE64 -D FILE [TEXT]: base64 from the keys, or TEXT, to FILE");
	return 1;
}
