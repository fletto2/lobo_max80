#include <_cconv.h>
/* scanf from a file for the CP/M C library: scanf, fscanf,
 * vscanf and vfscanf, through __vscan */

#include "cpmint.h"

static int fget(void *f)
{
	return fgetc((FILE *)f);
}

static void funget(int c, void *f)
{
	ungetc(c, (FILE *)f);
}

int vfscanf(FILE *f, const char *fmt, va_list ap) __LIB
{
	return __vscan(fget, funget, f, fmt, ap);
}

int vscanf(const char *fmt, va_list ap) __LIB
{
	return __vscan(fget, funget, stdin, fmt, ap);
}

int fscanf(FILE *f, const char *fmt, ...) __LIB
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = __vscan(fget, funget, f, fmt, ap);
	va_end(ap);
	return n;
}

int scanf(const char *fmt, ...) __LIB
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = __vscan(fget, funget, stdin, fmt, ap);
	va_end(ap);
	return n;
}
