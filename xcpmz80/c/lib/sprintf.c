#include <_cconv.h>
/* printf to a string for the CP/M C library: sprintf, snprintf,
 * vsprintf and vsnprintf. snprintf gives the length the whole text
 * would have had. */

#include "cpmint.h"

struct sbuf {
	char *p;
	size_t room;		/* left, less the 0 */
};

static void sout(char c, void *a)
{
	struct sbuf *b = a;

	if (b->room) {
		*b->p++ = c;
		b->room--;
	}
}

int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap) __LIB
{
	struct sbuf b;
	int r;

	b.p = buf;
	b.room = n ? n - 1 : 0;
	r = __vfmt(sout, &b, fmt, ap);
	if (n)
		*b.p = 0;
	return r;
}

int vsprintf(char *buf, const char *fmt, va_list ap) __LIB
{
	return vsnprintf(buf, 0x7fff, fmt, ap);
}

int snprintf(char *buf, size_t n, const char *fmt, ...) __LIB
{
	va_list ap;
	int r;

	va_start(ap, fmt);
	r = vsnprintf(buf, n, fmt, ap);
	va_end(ap);
	return r;
}

int sprintf(char *buf, const char *fmt, ...) __LIB
{
	va_list ap;
	int r;

	va_start(ap, fmt);
	r = vsnprintf(buf, 0x7fff, fmt, ap);
	va_end(ap);
	return r;
}
