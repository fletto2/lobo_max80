#include <_cconv.h>
/* Strings out for the CP/M C library: fputs and puts */

#include "cpmint.h"

int fputs(const char *s, FILE *f) __LIB
{
	while (*s)
		if (fputc(*s++, f) == EOF)
			return EOF;
	return 0;
}

int puts(const char *s) __LIB
{
	if (fputs(s, stdout) == EOF)
		return EOF;
	return fputc('\n', stdout);
}
