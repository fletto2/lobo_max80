#include <_cconv.h>
/* The stdlib functions for the CP/M C library: numbers, sorting
 * and random numbers. Built once for each function, L_name picks it,
 * so a program links only those it calls. */

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>

#ifdef L_abs
int abs(int n) __LIB { return n < 0 ? -n : n; }
#endif

#ifdef L_labs
long labs(long n) __LIB { return n < 0 ? -n : n; }
#endif

#ifdef L_strtoul
/* the engine of strtol and strtoul: sets *neg, 1 in *over past
 * ULONG_MAX */
unsigned long __strtoul(const char *s, char **end, int base,
	unsigned char *neg, unsigned char *over)
{
	const char *p = s, *start;
	unsigned long v = 0, lim;
	unsigned char d;

	*neg = *over = 0;
	while (isspace((unsigned char)*p))
		p++;
	if (*p == '-' || *p == '+')
		*neg = *p++ == '-';
	if ((base == 0 || base == 16) && p[0] == '0' && (p[1] | 32) == 'x'
	    && isxdigit((unsigned char)p[2])) {
		p += 2;
		base = 16;
	} else if (base == 0)
		base = *p == '0' ? 8 : 10;
	start = p;
	lim = ULONG_MAX / base;
	for (;; p++) {
		if (*p >= '0' && *p <= '9')
			d = *p - '0';
		else if ((*p | 32) >= 'a' && (*p | 32) <= 'z')
			d = (*p | 32) - 'a' + 10;
		else
			break;
		if (d >= base)
			break;
		if (v > lim || v * base > ULONG_MAX - d)
			*over = 1;
		v = v * base + d;
	}
	if (end)
		*end = (char *)(p == start ? s : p);
	return v;
}

unsigned long strtoul(const char *s, char **end, int base) __LIB
{
	unsigned char neg, over;
	unsigned long v = __strtoul(s, end, base, &neg, &over);

	if (over) {
		errno = ERANGE;
		return ULONG_MAX;
	}
	return neg ? -v : v;
}
#endif

#ifdef L_strtol
unsigned long __strtoul(const char *s, char **end, int base,
	unsigned char *neg, unsigned char *over);

long strtol(const char *s, char **end, int base) __LIB
{
	unsigned char neg, over;
	unsigned long v = __strtoul(s, end, base, &neg, &over);

	if (over || v > (neg ? (unsigned long)LONG_MAX + 1 : LONG_MAX)) {
		errno = ERANGE;
		return neg ? LONG_MIN : LONG_MAX;
	}
	return neg ? -(long)v : (long)v;
}
#endif

#ifdef L_atoi
int atoi(const char *s) __LIB
{
	int v = 0;
	unsigned char neg = 0;

	while (isspace((unsigned char)*s))
		s++;
	if (*s == '-' || *s == '+')
		neg = *s++ == '-';
	while (*s >= '0' && *s <= '9')
		v = v * 10 + *s++ - '0';
	return neg ? -v : v;
}
#endif

#ifdef L_atol
long atol(const char *s) __LIB
{
	long v = 0;
	unsigned char neg = 0;

	while (isspace((unsigned char)*s))
		s++;
	if (*s == '-' || *s == '+')
		neg = *s++ == '-';
	while (*s >= '0' && *s <= '9')
		v = v * 10 + *s++ - '0';
	return neg ? -v : v;
}
#endif

#ifdef L_ultoa
char *ultoa(unsigned long v, char *buf, int base) __LIB
{
	char tmp[33], *p = tmp + sizeof(tmp) - 1;

	*p = 0;
	do {
		unsigned char d = v % base;
		*--p = d < 10 ? '0' + d : 'a' + d - 10;
		v /= base;
	} while (v);
	return strcpy(buf, p);
}
#endif

#ifdef L_ltoa
char *ltoa(long v, char *buf, int base) __LIB
{
	if (v < 0 && base == 10) {
		*buf = '-';
		ultoa(-v, buf + 1, base);
		return buf;
	}
	return ultoa(v, buf, base);
}
#endif

#ifdef L_utoa
char *utoa(unsigned int v, char *buf, int base) __LIB
{
	return ultoa(v, buf, base);
}
#endif

#ifdef L_itoa
char *itoa(int v, char *buf, int base) __LIB
{
	if (v < 0 && base == 10) {
		*buf = '-';
		ultoa((unsigned int)-v, buf + 1, base);
		return buf;
	}
	return ultoa((unsigned int)v, buf, base);
}
#endif

#ifdef L_qsort
static void swap(unsigned char *a, unsigned char *b, size_t n)
{
	unsigned char t;

	while (n--) {
		t = *a;
		*a++ = *b;
		*b++ = t;
	}
}

/* Shell sort: small, no recursion, no extra memory */
void qsort(void *base, size_t n, size_t size,
	int (*cmp)(const void *, const void *)) __LIB
{
	unsigned char *b = base;
	size_t gap, i, j;

	for (gap = n / 2; gap; gap /= 2)
		for (i = gap; i < n; i++)
			for (j = i; j >= gap
			     && cmp(b + (j - gap) * size, b + j * size) > 0; j -= gap)
				swap(b + (j - gap) * size, b + j * size, size);
}
#endif

#ifdef L_bsearch
void *bsearch(const void *key, const void *base, size_t n, size_t size,
	int (*cmp)(const void *, const void *)) __LIB
{
	const unsigned char *b = base;
	size_t lo = 0, hi = n, mid;
	int r;

	while (lo < hi) {
		mid = (lo + hi) / 2;
		r = cmp(key, b + mid * size);
		if (!r)
			return (void *)(b + mid * size);
		if (r < 0)
			hi = mid;
		else
			lo = mid + 1;
	}
	return NULL;
}
#endif

#ifdef L_rand
/* A 32-bit xorshift, 15 bits out, as RAND_MAX has it */
static unsigned long seed = 1;

void srand(unsigned int s) __LIB
{
	seed = s ? s : 1;
}

int rand(void) __LIB
{
	seed ^= seed << 13;
	seed ^= seed >> 17;
	seed ^= seed << 5;
	return (int)(seed >> 9) & RAND_MAX;
}

long random(void) __LIB
{
	return (long)rand() << 16 | (unsigned int)rand() << 1 | (rand() & 1);
}

void srandom(unsigned int s) __LIB
{
	srand(s);
}
#endif
