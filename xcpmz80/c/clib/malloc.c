#include <_cconv.h>
/* malloc in the C library resident in B2: lib/malloc.c's first
 * fit, on the program's heap, from where its crt0 says it starts up to
 * 1K under the stack. The heap is the program's memory, so each 2-byte
 * block header is read and written through __ugetw and __uputw. */

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "clib.h"

#define USED	1u
#define STACK	1024

static unsigned int top;
/* No free block starts below low: a program that allocates line after
 * line, as the editors do, finds its room at once, not by reading every
 * header from the heap's start, each through the bank switch */
static unsigned int low;
/* No free block below top holds nofit bytes or more: a walk from low
 * found none, and only free makes a free block bigger. A request that
 * size or more goes to the top at once, past a small hole that keeps
 * low down, as VI's freed first line does */
static unsigned int nofit = 0xFFFF;

void __clib_heap(unsigned int start) __LIB
{
	top = low = (start + 1) & ~1u;
	nofit = 0xFFFF;
}

unsigned int __clib_heaptop(void) __LIB
{
	return top;
}

static unsigned int limit(void)
{
	unsigned char here;

	return (unsigned int)&here - STACK;
}

#define HDR(b)		__ugetw(b)
#define SETHDR(b, v)	__uputw(b, v)
#define NEXTB(b)	((b) + (HDR(b) & ~USED))

static void merge(unsigned int b)
{
	unsigned int n, h = HDR(b);

	while ((n = b + (h & ~USED)) < top && !(HDR(n) & USED)) {
		h += HDR(n);
		SETHDR(b, h);
	}
	if (n == top && !(h & USED))
		top = b;
}

void *malloc(size_t n) __LIB
{
	unsigned int b, sz, h;

	if (!n || n > 0x7ff0) {
		errno = ENOMEM;
		return NULL;
	}
	sz = (n + 3) & ~1u;
	if (sz >= nofit)
		goto attop;
	for (b = low; b < top; b += h & ~USED) {
		h = HDR(b);
		if (h & USED) {
			if (b == low)
				low = b + (h & ~USED);
			continue;
		}
		merge(b);
		if (b >= top)
			break;
		h = HDR(b);
		if (h >= sz) {
			if (h - sz >= 4) {
				SETHDR(b + sz, h - sz);
				h = sz;
			}
			SETHDR(b, h | USED);
			if (b == low)
				low = b + h;
			return (void *)(b + 2);
		}
	}
	nofit = sz;
attop:
	if (top > limit() || sz > limit() - top) {
		errno = ENOMEM;
		return NULL;
	}
	b = top;
	SETHDR(b, sz | USED);
	top = b + sz;
	if (low == b)
		low = top;
	return (void *)(b + 2);
}

void free(void *p) __LIB
{
	unsigned int b;

	if (!p)
		return;
	b = (unsigned int)p - 2;
	SETHDR(b, HDR(b) & ~USED);
	if (b < low)
		low = b;
	nofit = 0xFFFF;
	merge(b);
}

void *calloc(size_t n, size_t size) __LIB
{
	void *p;

	if (size && n > 0x7ff0 / size)
		return NULL;
	p = malloc(n * size);
	if (p)
		__umemset((unsigned int)p, 0, n * size);
	return p;
}

void *realloc(void *p, size_t n) __LIB
{
	unsigned int b, have, h;
	void *q;

	if (!p)
		return malloc(n);
	if (!n) {
		free(p);
		return NULL;
	}
	b = (unsigned int)p - 2;
	have = (HDR(b) & ~USED) - 2;
	if (n <= have)
		return p;
	if (n > 0x7ff0) {	/* as malloc: its size would wrap */
		errno = ENOMEM;
		return NULL;
	}
	/* free for a moment, and the free blocks after it merged in: low,
	 * which may be one of them, comes down to it, or malloc would find
	 * a free block inside the one grown here */
	if (b < low)
		low = b;
	SETHDR(b, HDR(b) & ~USED);
	merge(b);
	if (b == top) {
		unsigned int sz = (n + 3) & ~1u;
		if (b <= limit() && sz <= limit() - b) {
			SETHDR(b, sz | USED);
			top = b + sz;
			return p;
		}
		SETHDR(b, (have + 2) | USED);
		top = b + have + 2;
	} else {
		h = HDR(b);
		SETHDR(b, h | USED);
		if ((h & ~USED) - 2 >= n)
			return p;
	}
	q = malloc(n);
	if (!q)
		return NULL;
	__lcopy(p, q, have);		/* both the program's */
	free(p);
	return q;
}

size_t __heapfree(void) __LIB
{
	unsigned int l = limit();

	return top < l ? l - top : 0;
}
