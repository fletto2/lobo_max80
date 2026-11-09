#include <_cconv.h>
/* printf to a file for the CP/M C library: printf, fprintf,
 * vprintf and vfprintf, through __vfmt */

#include "cpmint.h"

static void fout(char c, void *f)
{
	fputc(c, (FILE *)f);
}

int vfprintf(FILE *f, const char *fmt, va_list ap) __LIB
{
	return __vfmt(fout, f, fmt, ap);
}

int vprintf(const char *fmt, va_list ap) __LIB
{
	return __vfmt(fout, stdout, fmt, ap);
}

int fprintf(FILE *f, const char *fmt, ...) __LIB
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = __vfmt(fout, f, fmt, ap);
	va_end(ap);
	return n;
}

int printf(const char *fmt, ...) __LIB
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = __vfmt(fout, stdout, fmt, ap);
	va_end(ap);
	return n;
}
