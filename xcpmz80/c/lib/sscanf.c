#include <_cconv.h>
/* scanf from a string for the CP/M C library: sscanf, vsscanf */

#include "cpmint.h"

static int sget(void *a)
{
	const char **s = a;

	return **s ? (unsigned char)*(*s)++ : EOF;
}

static void sunget(int c, void *a)
{
	const char **s = a;

	(void)c;
	(*s)--;
}

int vsscanf(const char *s, const char *fmt, va_list ap) __LIB
{
	return __vscan(sget, sunget, &s, fmt, ap);
}

int sscanf(const char *s, const char *fmt, ...) __LIB
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = __vscan(sget, sunget, &s, fmt, ap);
	va_end(ap);
	return n;
}
