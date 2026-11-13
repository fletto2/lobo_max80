#include <_cconv.h>
/* The C library resident in B2: the functions a signature cannot
 * describe. Each takes the program's pointers as they are, unsigned
 * int here, and reaches the memory through clib.h. Bulk copies go in
 * pieces through a buffer on the stack, which is in A1. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <conio.h>
#include "../lib/cpmint.h"
#include "clib.h"

#define PIECE	128

static unsigned char ugetc(unsigned int p)
{
	unsigned char c;

	__uget(&c, p, 1);
	return c;
}

static void uputc(unsigned int p, unsigned char c)
{
	__uput(p, &c, 1);
}

/* ---- memory ---- */

unsigned int __r_memcpy(unsigned int d, unsigned int s, unsigned int n) __LIB
{
	if (n)
		__lcopy((void *)s, (void *)d, n);
	return d;
}

unsigned int __r_memmove(unsigned int d, unsigned int s, unsigned int n) __LIB
{
	unsigned char tmp[PIECE];
	unsigned int k;

	if (!n)
		return d;
	if (d <= s || d >= s + n) {
		__lcopy((void *)s, (void *)d, n);
		return d;
	}
	while (n) {			/* from the end, d above s */
		k = n > PIECE ? PIECE : n;
		n -= k;
		__lcopy((void *)(s + n), tmp, k);
		__lcopy(tmp, (void *)(d + n), k);
	}
	return d;
}

/* memcmp and bcmp in pieces: both copied whole, two buffers over the
 * arena's room gave 0, equal */
int __r_memcmp(unsigned int a, unsigned int b, unsigned int n) __LIB
{
	unsigned char x[PIECE / 2], y[PIECE / 2];
	unsigned int k, i;

	while (n) {
		k = n > PIECE / 2 ? PIECE / 2 : n;
		__lcopy((void *)a, x, k);
		__lcopy((void *)b, y, k);
		for (i = 0; i < k; i++)
			if (x[i] != y[i])
				return x[i] < y[i] ? -1 : 1;
		a += k;
		b += k;
		n -= k;
	}
	return 0;
}

unsigned int __r_memset(unsigned int d, int c, unsigned int n) __LIB
{
	__umemset(d, c, n);
	return d;
}

void __r_bzero(unsigned int d, unsigned int n) __LIB
{
	__umemset(d, 0, n);
}

void __r_bcopy(unsigned int s, unsigned int d, unsigned int n) __LIB
{
	__r_memmove(d, s, n);
}

/* ---- strings ---- */

unsigned int __r_strlen(unsigned int s) __LIB
{
	return __ustrlen(s);
}

unsigned int __r_strcpy(unsigned int d, unsigned int s) __LIB
{
	__lcopy((void *)s, (void *)d, __ustrlen(s) + 1);
	return d;
}

/* strtok, strtok_r and strsep work on the program's string where it
 * is, a byte at a time, as strtok keeps its place between calls.
 * delim is the library's copy. */
static unsigned int tok(unsigned int s, const char *delim, unsigned int *save)
{
	unsigned char c;
	unsigned int start;

	if (!s)
		s = *save;
	if (!s)
		return 0;
	while ((c = ugetc(s)) && strchr(delim, c))
		s++;
	if (!c) {
		*save = s;
		return 0;
	}
	start = s;
	while ((c = ugetc(s)) && !strchr(delim, c))
		s++;
	if (c) {
		uputc(s, 0);
		s++;
	}
	*save = s;
	return start;
}

unsigned int __r_strtok(unsigned int s, const char *delim) __LIB
{
	static unsigned int save;

	return tok(s, delim, &save);
}

unsigned int __r_strtok_r(unsigned int s, const char *delim, unsigned int psave) __LIB
{
	unsigned int save = __ugetw(psave), r;

	r = tok(s, delim, &save);
	__uputw(psave, save);
	return r;
}

unsigned int __r_strsep(unsigned int sp, const char *delim) __LIB
{
	unsigned int s = __ugetw(sp), p;
	unsigned char c;

	if (!s)
		return 0;
	for (p = s; (c = ugetc(p)) && !strchr(delim, c); p++)
		;
	if (c) {
		uputc(p, 0);
		__uputw(sp, p + 1);
	} else
		__uputw(sp, 0);
	return s;
}

/* s is the library's copy, the new string the program's heap */
unsigned int __r_strdup(const char *s) __LIB
{
	unsigned int n = strlen(s) + 1;
	void *p = malloc(n);

	if (p)
		__uput((unsigned int)p, s, n);
	return (unsigned int)p;
}

unsigned int __r_strndup(const char *s, unsigned int n) __LIB
{
	unsigned int len = strnlen(s, n);
	unsigned char *p = malloc(len + 1);

	if (p) {
		__uput((unsigned int)p, s, len);
		uputc((unsigned int)p + len, 0);
	}
	return (unsigned int)p;
}

/* ---- files ---- */

unsigned int __r_fread(unsigned int p, unsigned int size, unsigned int nmemb, FILE *f) __LIB
{
	unsigned char tmp[PIECE];
	unsigned int want, got = 0, k, n;

	if (!size || !nmemb)
		return 0;
	if (nmemb > 0xFFFFu / size)	/* not past 64K, which would wrap */
		nmemb = 0xFFFFu / size;
	want = size * nmemb;
	while (got < want) {
		k = want - got > PIECE ? PIECE : want - got;
		n = fread(tmp, 1, k, f);
		if (n)
			__uput(p + got, tmp, n);
		got += n;
		if (n < k)
			break;
	}
	return got / size;
}

unsigned int __r_fwrite(unsigned int p, unsigned int size, unsigned int nmemb, FILE *f) __LIB
{
	unsigned char tmp[PIECE];
	unsigned int want, put = 0, k, n;

	if (!size || !nmemb)
		return 0;
	if (nmemb > 0xFFFFu / size)	/* not past 64K, which would wrap */
		nmemb = 0xFFFFu / size;
	want = size * nmemb;
	while (put < want) {
		k = want - put > PIECE ? PIECE : want - put;
		__uget(tmp, p + put, k);
		n = fwrite(tmp, 1, k, f);
		put += n;
		if (n < k)
			break;
	}
	return put / size;
}

int __r_read(int fd, unsigned int p, unsigned int len) __LIB
{
	unsigned char tmp[PIECE];
	unsigned int got = 0, k;
	int n;

	while (got < len) {
		k = len - got > PIECE ? PIECE : len - got;
		n = read(fd, tmp, k);
		if (n < 0)
			return got ? (int)got : -1;
		if (n)
			__uput(p + got, tmp, n);
		got += n;
		if ((unsigned int)n < k)
			break;
	}
	return got;
}

int __r_write(int fd, unsigned int p, unsigned int len) __LIB
{
	unsigned char tmp[PIECE];
	unsigned int put = 0, k;
	int n;

	while (put < len) {
		k = len - put > PIECE ? PIECE : len - put;
		__uget(tmp, p + put, k);
		n = write(fd, tmp, k);
		if (n < 0)
			return put ? (int)put : -1;
		put += n;
		if ((unsigned int)n < k)
			break;
	}
	return put;
}

/* tmpnam(NULL) gives the program's string buffer */
unsigned int __r_tmpnam(unsigned int buf) __LIB
{
	char *n = tmpnam(NULL);

	if (!n)
		return 0;
	if (!buf)
		buf = __clib_ustr();
	__uput(buf, n, strlen(n) + 1);
	return buf;
}

/* cgets: buf[0] the room, the line from buf + 2 */
unsigned int __r_cgets(unsigned int buf) __LIB
{
	char tmp[258];

	tmp[0] = ugetc(buf);
	cgets(tmp);
	__uput(buf, tmp, (unsigned char)tmp[1] + 3);
	return buf + 2;
}
