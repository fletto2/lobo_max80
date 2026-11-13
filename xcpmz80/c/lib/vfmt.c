/* printf's engine for the CP/M C library. Flags - + space # 0,
 * a width and precision, * for either, h, hh, l and z, and the
 * conversions d i u o x X c s p n and %. No floating point: %e %f %g
 * print as "?". Written small for the resident library: the
 * state is static and one routine pads and puts out each field. */

#include "cpmint.h"

#define FL_LEFT	0x01
#define FL_PLUS	0x02
#define FL_SPACE 0x04
#define FL_ALT	0x08
#define FL_ZERO	0x10

static void (*fout)(char, void *);
static void *farg;
static int count;
static unsigned char *vap;	/* the next argument */
static const char *f;		/* the format */

/* the arguments: SDCC's va_list is a pointer to them */
static int geti(void)
{
	int v = *(int *)vap;

	vap += 2;
	return v;
}

static unsigned char lng;

/* a long, or the low half of a long long, whose high half is passed
 * over: it took the next argument's place before */
static long getl(void)
{
	long v = *(long *)vap;

	vap += lng > 1 ? 8 : 4;
	return v;
}

/* a number in the format, or * for the next argument */
static int getnum(void)
{
	int v = 0;

	if (*f == '*') {
		f++;
		return geti();
	}
	while (*f >= '0' && *f <= '9')
		v = v * 10 + *f++ - '0';
	return v;
}

static void rep(char c, int n)
{
	for (; n > 0; n--, count++)
		fout(c, farg);
}

/* a field: pre (sign, 0x) and zeros, then len bytes of s, in width */
static void field(const char *pre, int zeros, const char *s, int len,
	int width, unsigned char left)
{
	int plen = 0;

	while (pre[plen])
		plen++;
	width -= plen + zeros + len;
	if (!left)
		rep(' ', width);
	for (; *pre; pre++, count++)
		fout(*pre, farg);
	rep('0', zeros);
	for (; len > 0; len--, count++)
		fout(*s++, farg);
	if (left)
		rep(' ', width);
}

int __vfmt(void (*out)(char, void *), void *arg, const char *fmt, va_list ap)
{
	char tmp[12], pre[3], *s;
	int width, prec, len, zeros;
	unsigned long u;
	unsigned char base, fl, c;

	fout = out;
	farg = arg;
	count = 0;
	vap = (unsigned char *)ap;
	f = fmt;
#define fmt f
	for (; *fmt; fmt++) {
		if (*fmt != '%') {
			rep(*fmt, 1);
			continue;
		}
		fl = 0;
		for (;;) {
			c = *++fmt;
			if (c == '-')
				fl |= FL_LEFT;
			else if (c == '+')
				fl |= FL_PLUS;
			else if (c == ' ')
				fl |= FL_SPACE;
			else if (c == '#')
				fl |= FL_ALT;
			else if (c == '0')
				fl |= FL_ZERO;
			else
				break;
		}
		width = getnum();
		if (width < 0) {
			fl |= FL_LEFT;
			width = -width;
		}
		prec = -1;
		if (*fmt == '.') {
			fmt++;
			prec = getnum();
		}
		lng = 0;
		while (*fmt == 'l' || *fmt == 'h' || *fmt == 'z' || *fmt == 't')
			if (*fmt++ == 'l')
				lng++;	/* 2: long long, 8 bytes */
		c = *fmt;
		pre[0] = 0;
		switch (c) {
		case 'd':
		case 'i':
			u = lng ? getl() : (long)geti();
			if ((long)u < 0) {
				u = -u;
				pre[0] = '-';
			} else if (fl & FL_PLUS)
				pre[0] = '+';
			else if (fl & FL_SPACE)
				pre[0] = ' ';
			pre[1] = 0;
			base = 10;
			break;
		case 'p':
			u = (unsigned int)geti();
			base = 16;
			if (prec < 4)
				prec = 4;
			c = 'X';
			break;
		case 'o':
		case 'u':
		case 'x':
		case 'X':
			u = lng ? (unsigned long)getl() : (unsigned int)geti();
			base = c == 'o' ? 8 : c == 'u' ? 10 : 16;
			if ((fl & FL_ALT) && base == 16 && u) {
				pre[0] = '0';
				pre[1] = c;
				pre[2] = 0;
			}
			break;
		case 'c':
			tmp[0] = geti();
			field("", 0, tmp, 1, width, fl & FL_LEFT);
			continue;
		case 's':
			s = (char *)geti();
			if (!s)
				s = "(null)";
			for (len = 0; s[len] && (prec < 0 || len < prec); len++)
				;
			field("", 0, s, len, width, fl & FL_LEFT);
			continue;
		case 'n':
			*(int *)geti() = count;
			continue;
		case 'e':
		case 'E':
		case 'f':
		case 'F':
		case 'g':
		case 'G':
			vap += 4;		/* SDCC's double is a float */
			field("", 0, "?", 1, width, fl & FL_LEFT);
			continue;
		case 0:
			return count;
		default:		/* %% and anything unknown */
			field("", 0, fmt, 1, width, fl & FL_LEFT);
			continue;
		}
		/* a number: its digits from the end of tmp */
		s = tmp + sizeof(tmp);
		while (u) {
			unsigned char d = u % base;
			*--s = d < 10 ? '0' + d : (c == 'X' ? 'A' : 'a') + d - 10;
			u /= base;
		}
		if (s == tmp + sizeof(tmp) && prec)	/* 0, unless %.0d */
			*--s = '0';
		len = tmp + sizeof(tmp) - s;
		zeros = prec > len ? prec - len : 0;
		if ((fl & FL_ALT) && base == 8 && !zeros && *s != '0')
			zeros = 1;
		if (prec < 0 && (fl & (FL_ZERO | FL_LEFT)) == FL_ZERO) {
			int w = width - len;
			for (len = 0; pre[len]; len++)
				w--;
			len = tmp + sizeof(tmp) - s;
			if (w > zeros)
				zeros = w;
		}
		field(pre, zeros, s, len, width, fl & FL_LEFT);
	}
	return count;
}
