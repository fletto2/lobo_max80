#include <_cconv.h>
/* malloc for the CP/M C library. The heap runs from the end of
 * the program up to 1K under the stack. Each block has a 2-byte header,
 * its size with bit 0 set while it is in use. malloc takes the first
 * free block large enough, splitting it, free merges a block with the
 * free ones after it, and the heap grows only at its top. */

#include <stdlib.h>
#include <string.h>
#include <errno.h>

extern unsigned char __heap;	/* crt0: after everything else */

#define USED	1u
#define STACK	1024		/* left for the stack */

static unsigned int *first = (unsigned int *)&__heap;
static unsigned int *top = (unsigned int *)&__heap;	/* the end */

/* the room under the stack, below SP less STACK */
static unsigned char *limit(void)
{
	unsigned char here;

	return &here - STACK;
}

#define NEXTB(b) ((unsigned int *)((unsigned char *)(b) + (*(b) & ~USED)))

/* joins b with the free blocks right after it */
static void merge(unsigned int *b)
{
	unsigned int *n;

	while ((n = NEXTB(b)) < top && !(*n & USED))
		*b += *n;
	if (n == top && !(*b & USED))
		top = b;		/* a free block at the top gives it back */
}

void *malloc(size_t n) __LIB
{
	unsigned int *b, sz;

	if (!n || n > 0x7ff0) {
		errno = ENOMEM;
		return NULL;
	}
	sz = (n + 3) & ~1u;		/* header, even */
	for (b = first; b < top; b = NEXTB(b)) {
		if (*b & USED)
			continue;
		merge(b);
		if (b >= top)
			break;
		if (*b >= sz) {
			if (*b - sz >= 4) {	/* split */
				unsigned int *r = (unsigned int *)((unsigned char *)b + sz);
				*r = *b - sz;
				*b = sz;
			}
			*b |= USED;
			return b + 1;
		}
	}
	if ((unsigned char *)top > limit() || sz > (unsigned int)(limit() - (unsigned char *)top)) {
		errno = ENOMEM;
		return NULL;
	}
	b = top;
	*b = sz | USED;
	top = NEXTB(b);
	return b + 1;
}

void free(void *p) __LIB
{
	unsigned int *b;

	if (!p)
		return;
	b = (unsigned int *)p - 1;
	*b &= ~USED;
	merge(b);
}

void *calloc(size_t n, size_t size) __LIB
{
	void *p;

	if (size && n > 0x7ff0 / size)
		return NULL;
	p = malloc(n * size);
	if (p)
		memset(p, 0, n * size);
	return p;
}

void *realloc(void *p, size_t n) __LIB
{
	unsigned int *b, have;
	void *q;

	if (!p)
		return malloc(n);
	if (!n) {
		free(p);
		return NULL;
	}
	b = (unsigned int *)p - 1;
	have = (*b & ~USED) - 2;
	if (n <= have)
		return p;
	if (n > 0x7ff0) {	/* as malloc: its size would wrap */
		errno = ENOMEM;
		return NULL;
	}
	/* grow in place into a free block after it, or at the top */
	*b &= ~USED;
	merge(b);
	if (b == top) {
		unsigned int sz = (n + 3) & ~1u;
		if ((unsigned char *)b <= limit() &&
		    sz <= (unsigned int)(limit() - (unsigned char *)b)) {
			*b = sz | USED;
			top = NEXTB(b);
			return p;
		}
		*b = (have + 2) | USED;	/* no room: b stays as it was */
		top = (unsigned int *)((unsigned char *)b + have + 2);
	} else if ((*b & ~USED) - 2 >= n) {
		*b |= USED;
		return p;
	} else
		*b |= USED;
	q = malloc(n);
	if (!q)
		return NULL;
	memcpy(q, p, have);
	free(p);
	return q;
}

/* the bytes malloc could still give from the top */
size_t __heapfree(void) __LIB
{
	unsigned char *l = limit();

	return (unsigned char *)top < l ? l - (unsigned char *)top : 0;
}
