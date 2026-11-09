/* scanf's engine for the CP/M C library. A width, * to skip, h,
 * hh and l, and the conversions d i u o x X c s [ n and %. No floating
 * point. Gives the number of fields stored, or EOF when the input ends
 * before the first. */

#include <ctype.h>
#include "cpmint.h"

static unsigned char digit(int c, unsigned char base)
{
	unsigned char d;

	if (c >= '0' && c <= '9')
		d = c - '0';
	else if (c >= 'a' && c <= 'z')
		d = c - 'a' + 10;
	else if (c >= 'A' && c <= 'Z')
		d = c - 'A' + 10;
	else
		return 255;
	return d < base ? d : 255;
}

/* the input: one function, so the calls to get are not repeated */
static int (*sget)(void *);
static void *sarg;
static int c, count;

static void next(void)
{
	c = sget(sarg);
	count++;
}

#define NEXT() next()

/* the next pointer argument, or NULL for a field with * */
static unsigned char *vap;
static unsigned char skip;

static void *getp(void)
{
	void *v;

	if (skip)
		return NULL;
	v = *(void **)vap;
	vap += 2;
	return v;
}

int __vscan(int (*get)(void *), void (*unget)(int, void *), void *arg,
	const char *fmt, va_list ap)
{
	int n = 0, width;
	unsigned char size, base, neg, any;
	unsigned long v;
	char *d;

	sget = get;
	sarg = arg;
	vap = (unsigned char *)ap;
	count = 0;
	next();
	if (c == EOF)
		return EOF;
	for (; *fmt; fmt++) {
		if (isspace((unsigned char)*fmt)) {
			while (c != EOF && isspace(c))
				NEXT();
			continue;
		}
		if (*fmt != '%' || fmt[1] == '%') {
			if (*fmt == '%')
				fmt++;
			if (c != (unsigned char)*fmt)
				break;
			NEXT();
			continue;
		}
		fmt++;
		skip = 0;
		if (*fmt == '*') {
			skip = 1;
			fmt++;
		}
		width = 0;
		while (*fmt >= '0' && *fmt <= '9')
			width = width * 10 + *fmt++ - '0';
		if (!width)
			width = 32767;
		size = 2;		/* int */
		while (*fmt == 'h' || *fmt == 'l' || *fmt == 'z') {
			if (*fmt == 'l')
				size = 4;
			else if (*fmt == 'h' && fmt[1] == 'h') {
				size = 1;
				fmt++;
			}
			fmt++;
		}
		if (*fmt == 'n') {
			if (!skip)
				*(int *)getp() = count - 1;
			continue;
		}
		if (*fmt != 'c' && *fmt != '[')
			while (c != EOF && isspace(c))
				NEXT();
		if (c == EOF)
			break;
		switch (*fmt) {
		case 'c':
			if (width == 32767)
				width = 1;
			d = getp();
			for (; width && c != EOF; width--) {
				if (d)
					*d++ = c;
				NEXT();
			}
			if (width)
				goto done;
			break;
		case 's':
			d = getp();
			for (; width && c != EOF && !isspace(c); width--) {
				if (d)
					*d++ = c;
				NEXT();
			}
			if (d)
				*d = 0;
			break;
		case '[': {
			const char *set = ++fmt;
			unsigned char inv = 0, in, got = 0;
			const char *p;
			if (*set == '^') {
				inv = 1;
				set = ++fmt;
			}
			if (*fmt == ']')
				fmt++;
			while (*fmt && *fmt != ']')
				fmt++;
			d = getp();
			for (; width && c != EOF; width--) {
				in = 0;
				for (p = set; p < fmt; p++)
					if (p[1] == '-' && p + 2 < fmt) {
						if (c >= (unsigned char)p[0] && c <= (unsigned char)p[2])
							in = 1;
						p += 2;
					} else if (c == (unsigned char)*p)
						in = 1;
				if (in == inv)
					break;
				if (d)
					*d++ = c;
				got = 1;
				NEXT();
			}
			if (d)
				*d = 0;
			if (!got)
				goto done;
			if (!*fmt)
				fmt--;
			break;
		}
		default:
			switch (*fmt) {
			case 'd':
			case 'u':
				base = 10;
				break;
			case 'o':
				base = 8;
				break;
			case 'x':
			case 'X':
			case 'p':
				base = 16;
				break;
			case 'i':
				base = 0;
				break;
			default:
				goto done;
			}
			neg = 0;
			if ((c == '-' || c == '+') && width) {
				neg = c == '-';
				NEXT();
				width--;
			}
			if (c == '0' && width && (base == 0 || base == 16)) {
				NEXT();
				width--;
				if ((c == 'x' || c == 'X') && width) {
					NEXT();
					width--;
					base = 16;
				} else if (!base)
					base = 8;
				any = 1;
			} else
				any = 0;
			if (!base)
				base = 10;
			for (v = 0; width && c != EOF && digit(c, base) != 255; width--) {
				v = v * base + digit(c, base);
				any = 1;
				NEXT();
			}
			if (!any)
				goto done;
			if (neg)
				v = -v;
			if (!skip) {
				void *p = getp();
				if (size == 4)
					*(unsigned long *)p = v;
				else if (size == 1)
					*(unsigned char *)p = v;
				else
					*(unsigned int *)p = v;
			}
			break;
		}
		if (!skip)
			n++;
	}
done:
	if (c != EOF)
		unget(c, arg);
	return n;
}
