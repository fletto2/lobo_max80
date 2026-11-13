#include <_cconv.h>
/* The C library resident in B2: reaching the program's memory,
 * and the arguments of each call.
 *
 * While the library runs, B2 is mapped at 0000h-7FFFh and A1 above it.
 * A program's pointer at 8000h or above is in A1 and used as it is.
 * One under 8000h is in B1, which is not mapped: __lcopy reaches it,
 * by lcopy in common memory, which maps B1 for the copy. Bytes go
 * between B1 and the library through a buffer on the stack, which is
 * the program's, in A1, seen by both.
 *
 * Each function in the table has a signature, which says what its
 * arguments are, so __clib_pre copies what they point to into the
 * arena and points the argument there, and
 * __clib_post copies back what the function wrote and the result
 * that points into it. The signature is the result, a space, then a
 * letter for each argument:
 *
 *   result: v as it is, pN a pointer into argument N, given back as the
 *     program's address, r a string of the library's, copied to the
 *     program's string buffer, t a struct tm of the library's, copied
 *     to the program's, f a FILE
 *   c 1 byte, i 2 bytes, l 4 bytes, as they are
 *   f a FILE: 1, 2 and 3 are stdin, stdout and stderr
 *   s a string read, S a string read and written, d a string written
 *   bN, BN, xN a buffer read, written, both, of the size in argument N
 *   I4 4 bytes read, o4 and o2 4 or 2 bytes written, T a struct tm
 *     read and written, e a char ** written, pointing into argument 0
 *   F a printf format, its arguments after it, V their va_list
 *   G a scanf format, its pointers after it, W their va_list
 *
 * NULL stays NULL.
 *
 * The arena is the program's stack, in A1: from STACKROOM under the
 * arguments, which the function's own stack needs, down towards the
 * top of the heap. So a copy costs no memory in B2, and lcopy moves it
 * between the program's memory and the arena in one go. */

#include <string.h>
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include "../lib/cpmint.h"
#include "clib.h"

#define STACKROOM	768	/* for the function, under its arguments */
#define NSLOT	16

static unsigned char *abot;		/* the arena's lowest byte so far */
static unsigned char *afloor;		/* how far down it may go */

/* One argument copied: where its slot is, what it held, its copy */
struct slot {
	unsigned char kind;	/* 0 none to copy back, 'S' 'd' 'B' 'x' 'o' 'T' 'e' 'g' 'G',
				   'h' a scanf pointer used as it is, counted */
	unsigned char arg;	/* its number, for pN */
	unsigned char *where;	/* the argument's place on the stack */
	unsigned int user;	/* the program's address */
	unsigned char *copy;	/* the copy in the arena */
	unsigned int len;	/* bytes copied in, or to copy out */
};

static struct slot slots[NSLOT];
static unsigned char nslot;
static const char *csig;
static int cerrno;			/* errno before the call */

/* The program's places for errno, strings and a struct tm, from crt0 */
static unsigned int uerrno, ustr, utm;

/* ---- The program's memory ---- */

#define CHUNK	64

void __uget(void *d, unsigned int us, unsigned int n) __LIB
{
	unsigned char tmp[CHUNK], k;
	unsigned char *p = d;

	if (us >= 0x8000u || !n) {
		memcpy(d, (void *)us, n);
		return;
	}
	if ((unsigned int)d >= 0x8000u) {	/* both seen by lcopy */
		__lcopy((void *)us, d, n);
		return;
	}
	while (n) {
		k = n > CHUNK ? CHUNK : n;
		__lcopy((void *)us, tmp, k);
		memcpy(p, tmp, k);
		p += k;
		us += k;
		n -= k;
	}
}

void __uput(unsigned int ud, const void *s, unsigned int n) __LIB
{
	unsigned char tmp[CHUNK], k;
	const unsigned char *p = s;

	if (ud >= 0x8000u || !n) {
		memcpy((void *)ud, s, n);
		return;
	}
	if ((unsigned int)s >= 0x8000u) {
		__lcopy(s, (void *)ud, n);
		return;
	}
	while (n) {
		k = n > CHUNK ? CHUNK : n;
		memcpy(tmp, p, k);
		__lcopy(tmp, (void *)ud, k);
		p += k;
		ud += k;
		n -= k;
	}
}

unsigned int __ustrlen(unsigned int us) __LIB
{
	unsigned char tmp[CHUNK], i;
	unsigned int n = 0;

	if (us >= 0x8000u)
		return strlen((char *)us);
	for (;;) {
		__lcopy((void *)us, tmp, CHUNK);
		for (i = 0; i < CHUNK; i++)
			if (!tmp[i])
				return n + i;
		n += CHUNK;
		us += CHUNK;
	}
}

unsigned int __ugetw(unsigned int up) __LIB
{
	unsigned int v;

	__uget(&v, up, 2);
	return v;
}

void __uputw(unsigned int up, unsigned int v) __LIB
{
	__uput(up, &v, 2);
}

void __umemset(unsigned int ud, unsigned char c, unsigned int n) __LIB
{
	unsigned char tmp[CHUNK], k;

	if (ud >= 0x8000u) {
		memset((void *)ud, c, n);
		return;
	}
	memset(tmp, c, CHUNK);
	while (n) {
		k = n > CHUNK ? CHUNK : n;
		__lcopy(tmp, (void *)ud, k);
		ud += k;
		n -= k;
	}
}

/* ---- The arena ---- */

static unsigned char *take(unsigned int n)
{
	if (n > (unsigned int)(abot - afloor))
		return NULL;
	abot -= n;
	return abot;
}

/* Point the argument at w, kept for __clib_post, to a copy of n bytes
 * of what it points to, read in when rd */
static struct slot *copyarg(unsigned char kind, unsigned char arg,
	unsigned char *w, unsigned int n, unsigned char rd)
{
	struct slot *s;
	unsigned int u = *(unsigned int *)w;

	if (nslot == NSLOT)
		return NULL;
	s = &slots[nslot];
	s->kind = kind;
	s->arg = arg;
	s->where = w;
	s->user = u;
	s->len = n;
	/* used as it is, but an end pointer, which must be translated */
	if ((u >= 0x8000u && kind != 'e') || !u) {
		s->copy = (unsigned char *)u;
		/* a scanf pointer still counts among those stored */
		s->kind = kind == 'g' || kind == 'G' ? 'h' : 0;
		nslot++;
		return s;
	}
	if (!(s->copy = take(n)))
		return NULL;
	if (rd)
		__uget(s->copy, u, n);
	*(unsigned char **)w = s->copy;
	nslot++;
	return s;
}

#define word(w)	(*(unsigned int *)(w))

/* a string's copy: its length and the 0, and room for the string at
 * more, which is to be added to it */
static struct slot *strarg(unsigned char kind, unsigned char arg, unsigned char *w,
	unsigned int more)
{
	unsigned int u = word(w), n;
	struct slot *s;

	if (!u || u >= 0x8000u)
		return copyarg(kind, arg, w, 0, 1);
	n = __ustrlen(u) + 1;
	if (more)
		more = more < 0x8000u ? __ustrlen(more) : strlen((char *)more);
	if (!(s = copyarg(kind, arg, w, n + more, 0)))
		return NULL;
	__uget(s->copy, u, n);
	return s;
}

/* the places of the arguments, by their sizes, to find argument N */
static unsigned char *argp[12];

/* printf's arguments: each %s copied, each %n written back */
static unsigned char *fmtargs(const char *fmt, unsigned char *a)
{
	for (; *fmt; fmt++) {
		if (*fmt != '%')
			continue;
		fmt++;
		while (*fmt && strchr("-+ #0", *fmt))
			fmt++;
		if (*fmt == '*') {
			a += 2;
			fmt++;
		}
		while (*fmt >= '0' && *fmt <= '9')
			fmt++;
		if (*fmt == '.') {
			fmt++;
			if (*fmt == '*') {
				a += 2;
				fmt++;
			}
			while (*fmt >= '0' && *fmt <= '9')
				fmt++;
		}
		{
			unsigned char lng = 0;
			while (*fmt == 'l' || *fmt == 'h' || *fmt == 'z' || *fmt == 't')
				if (*fmt++ == 'l')
					lng = 1;
			switch (*fmt) {
			case 0:
				return a;
			case 's':
				if (!strarg(0, 0xff, a, 0))
					return NULL;
				a += 2;
				break;
			case 'n':
				if (!copyarg('o', 0xff, a, 2, 0))
					return NULL;
				a += 2;
				break;
			case 'e': case 'E': case 'f': case 'F': case 'g': case 'G':
				a += 4;
				break;
			case '%':
				break;
			default:
				a += lng ? 4 : 2;
				break;
			}
		}
	}
	return a;
}

/* A string written with no size known, sprintf's or scanf's %s with
 * no width: its copy is given at the end, a share of the arena that is
 * left, or it is used as it is at 8000h or above */
static struct slot *later(unsigned char kind, unsigned char arg, unsigned char *w)
{
	struct slot *s;

	if (nslot == NSLOT)
		return NULL;
	s = &slots[nslot++];
	s->kind = kind;
	s->arg = arg;
	s->where = w;
	s->user = word(w);
	s->copy = (unsigned char *)s->user;
	s->len = 0;
	if (s->user && s->user < 0x8000u)
		s->copy = NULL;	/* given its room below */
	else
		s->kind = kind == 'g' && s->user ? 'h' : 0;
	return s;
}

/* scanf's pointers: a copy for each, written back if it was stored */
static unsigned char *scanargs(const char *fmt, unsigned char *a)
{
	unsigned int width;
	unsigned char size, skip, conv;

	for (; *fmt; fmt++) {
		if (*fmt != '%')
			continue;
		fmt++;
		if (*fmt == '%')
			continue;
		skip = *fmt == '*';
		if (skip)
			fmt++;
		width = 0;
		while (*fmt >= '0' && *fmt <= '9')
			width = width * 10 + *fmt++ - '0';
		size = 2;
		while (*fmt == 'h' || *fmt == 'l' || *fmt == 'z') {
			if (*fmt == 'l')
				size = 4;
			else if (fmt[1] == 'h') {
				size = 1;
				fmt++;
			}
			fmt++;
		}
		conv = *fmt;
		if (conv == '[') {
			if (fmt[1] == '^')
				fmt++;
			if (fmt[1] == ']')
				fmt++;
			while (fmt[1] && fmt[1] != ']')
				fmt++;
			if (fmt[1])
				fmt++;
		}
		if (!conv)
			return a;
		if (skip)
			continue;
		switch (conv) {
		case 's':
		case '[':
			if (width) {
				if (!copyarg('g', 0xff, a, width + 1, 0))
					return NULL;
			} else if (!later('g', 0xff, a))
				return NULL;	/* the rest of the arena, as 'd' */
			break;
		case 'c':
			if (!copyarg('G', 0xff, a, width ? width : 1, 1))
				return NULL;
			break;
		case 'n':
			if (!copyarg('o', 0xff, a, 2, 1))
				return NULL;
			break;
		default:
			if (!copyarg('G', 0xff, a, size, 1))
				return NULL;
			break;
		}
		a += 2;
	}
	return a;
}

/* 1, 2, 3: the console */
static void filearg(unsigned char *w)
{
	unsigned int u = word(w);

	if (u >= 1 && u <= 3) {
		*(FILE **)w = CON(u - 1);
	}
}

/* ---- The call ---- */

extern const struct clibfn __clib_tab[];
extern const unsigned int __clib_n;

/* The function n, its arguments at a: copies what they point to under
 * 8000h, gives its address, 0 for an unknown n or no room */
void *__clib_pre(unsigned int n, unsigned char *a) __LIB
{
	const char *sig;
	unsigned char i = 0;
	struct slot *s;
	const char *fmt = NULL;
	unsigned char fsc = 0;

	nslot = 0;
	csig = NULL;
	/* the arena: in A1, above the heap and its margin */
	abot = a - STACKROOM;
	afloor = (unsigned char *)__clib_heaptop() + 64;
	/* never under 8000h: there the library sees itself, B2 */
	if ((unsigned int)afloor < 0x8000u)
		afloor = (unsigned char *)0x8000u;
	if ((unsigned int)a < 0x8000u + STACKROOM)
		goto full;
	/* the heap up to under the arguments, as an editor that takes all
	 * there is has it: a call with nothing to copy still runs, on the
	 * stack as the program's own code would */
	if (abot < afloor)
		afloor = abot;
	if (n >= __clib_n || !__clib_tab[n].fn)
		return 0;
	sig = __clib_tab[n].sig;
	while (*sig && *sig != ' ')
		sig++;
	if (*sig)
		sig++;
	/* where each argument is, for the sizes in other arguments */
	{
		const char *p;
		unsigned char *q = a;
		for (p = sig; *p && i < 12; p++) {
			if (*p >= '0' && *p <= '9')
				continue;
			argp[i++] = q;
			q += *p == 'c' ? 1 : *p == 'l' ? 4 : 2;
		}
		i = 0;
	}
	for (; *sig; sig++, i++) {
		switch (*sig) {
		case 'c':
			a += 1;
			break;
		case 'l':
			a += 4;
			break;
		case 'i':
			a += 2;
			break;
		case 'f':
			filearg(a);
			a += 2;
			break;
		case 's':
			if (!strarg(0, i, a, 0))
				goto full;
			a += 2;
			break;
		case 'S':
			/* strcat's: room for the string after it as well */
			if (!(s = strarg('S', i, a, sig[1] == 's' ? word(a + 2) : 0)))
				goto full;
			a += 2;
			break;
		case 'd':
			/* written: the rest of the arena, known at the end */
			if (!later('d', i, a))
				goto full;
			a += 2;
			break;
		case 'b':
		case 'B':
		case 'x':
			{
				unsigned int len = word(argp[sig[1] - '0']);
				if (!copyarg(*sig == 'b' ? 0 : *sig, i, a, len, 1))
					goto full;
				sig++;
				a += 2;
			}
			break;
		case 'I':
			if (!copyarg(0, i, a, sig[1] - '0', 1))
				goto full;
			sig++;
			a += 2;
			break;
		case 'o':
			if (!copyarg('o', i, a, sig[1] - '0', 0))
				goto full;
			sig++;
			a += 2;
			break;
		case 'T':
			if (!copyarg('T', i, a, sizeof(struct tm), 1))
				goto full;
			a += 2;
			break;
		case 'e':
			if (!copyarg('e', i, a, 2, 0))
				goto full;
			a += 2;
			break;
		case 'F':
		case 'G':
			if (!strarg(0, i, a, 0))
				goto full;
			fmt = (const char *)word(a);
			fsc = *sig;
			a += 2;
			if (sig[1] == 0) {	/* the arguments follow */
				a = fsc == 'F' ? fmtargs(fmt, a) : scanargs(fmt, a);
				if (!a)
					goto full;
			}
			break;
		case 'V':
		case 'W':
			/* a va_list: the arguments it points to. One under
			 * 8000h is not handled: SDCC's stack is in A1. */
			{
				unsigned char *va = (unsigned char *)word(a);
				if ((unsigned int)va < 0x8000u
				    || !(fsc == 'F' ? fmtargs(fmt, va) : scanargs(fmt, va)))
					goto full;
				a += 2;
			}
			break;
		}
	}
	/* the strings written with no size get what is left, shared */
	{
		unsigned char k = 0;
		unsigned int n;

		for (i = 0; i < nslot; i++)
			if ((slots[i].kind == 'd' || slots[i].kind == 'g') && !slots[i].copy)
				k++;
		n = k ? (unsigned int)(abot - afloor) / k : 0;
		for (i = 0; i < nslot; i++)
			if ((slots[i].kind == 'd' || slots[i].kind == 'g') && !slots[i].copy) {
				if (n < 2)
					goto full;
				slots[i].copy = take(n);
				slots[i].copy[0] = 0;
				slots[i].len = n;
				*(unsigned char **)slots[i].where = slots[i].copy;
			}
	}
	csig = __clib_tab[n].sig;
	cerrno = errno;
	return __clib_tab[n].fn;
full:
	errno = ENOMEM;
	__clib_res[0] = 0;
	__clib_res[1] = 0;
	return 0;
}

/* the copy of argument k as the program's address */
static unsigned int back(unsigned char k, unsigned int p)
{
	unsigned char i;
	struct slot *s;

	if (!p)
		return 0;
	for (i = 0; i < nslot; i++) {
		s = &slots[i];
		if (s->arg == k && s->copy && (unsigned int)s->copy <= p
		    && p <= (unsigned int)s->copy + s->len)
			return s->user + (p - (unsigned int)s->copy);
	}
	return p;
}

void __clib_post(void) __LIB
{
	unsigned char i, stored = 0xff;
	unsigned int r = __clib_res[0], n;
	struct slot *s;
	const char *sig = csig;

	if (!sig)
		return;
	/* scanf: only what it stored is copied back */
	if (strchr(sig, 'G'))
		stored = r;
	for (i = 0; i < nslot; i++) {
		s = &slots[i];
		/* the argument back as the program had it */
		*(unsigned int *)s->where = s->user;
		if (s->kind == 'h') {	/* used as it is, but one stored */
			if (stored && stored != 0xff)
				stored--;
			continue;
		}
		if (!s->kind || !s->user)
			continue;
		switch (s->kind) {
		case 'S':
			__uput(s->user, s->copy, strlen((char *)s->copy) + 1);
			break;
		case 'd':
			__uput(s->user, s->copy, strlen((char *)s->copy) + 1);
			break;
		case 'g':
		case 'G':
			if (stored && stored != 0xff) {
				if (s->kind == 'g')
					__uput(s->user, s->copy, strlen((char *)s->copy) + 1);
				else
					__uput(s->user, s->copy, s->len);
				stored--;
			}
			break;
		case 'e':
			/* a pointer into argument 0's copy */
			__uputw(s->user, back(0, word(s->copy)));
			break;
		default:	/* B x o T */
			__uput(s->user, s->copy, s->len);
			break;
		}
	}
	switch (sig[0]) {
	case 'p':
		__clib_res[0] = back(sig[1] - '0', r);
		break;
	case 'r':
		if (r && ustr) {
			n = strlen((char *)r) + 1;
			__uput(ustr, (void *)r, n > CLIB_STRLEN ? CLIB_STRLEN : n);
			__clib_res[0] = ustr;
		}
		break;
	case 't':
		if (r && utm) {
			__uput(utm, (void *)r, sizeof(struct tm));
			__clib_res[0] = utm;
		}
		break;
	case 'f':
		if (r >= (unsigned int)__cons && r < (unsigned int)(__cons + 3))
			__clib_res[0] = (struct _con *)r - __cons + 1;
		break;
	}
	if (errno != cerrno && uerrno)
		__uputw(uerrno, errno);
	nslot = 0;
	csig = NULL;
}

unsigned int __clib_ustr(void) __LIB
{
	return ustr;
}

/* Function 0: a program's crt0 starts the library. heap is where the
 * program's heap starts, the others its errno, a CLIB_STRLEN-byte
 * buffer for strings the library gives, and a struct tm. Gives the
 * version, which a stub without the library gives as 0. */
int __clib_init(unsigned int heap, unsigned int perr, unsigned int pstr,
	unsigned int ptm) __LIB
{
	__clib_reset();
	__coninit();
	uerrno = perr;
	ustr = pstr;
	utm = ptm;
	__clib_heap(heap);
	return CLIB_VERSION;
}
