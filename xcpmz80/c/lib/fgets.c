#include <_cconv.h>
/* Lines for the CP/M C library: fgets and gets */

#include "cpmint.h"

char *fgets(char *buf, int n, FILE *f) __LIB
{
	int c, i = 0;

	while (i < n - 1) {
		c = fgetc(f);
		if (c == EOF)
			break;
		buf[i++] = c;
		if (c == '\n')
			break;
	}
	if (i == 0)
		return NULL;
	buf[i] = 0;
	return buf;
}

/* No room given, as C has it: the line without its '\n' */
char *gets(char *buf) __LIB
{
	int c;
	char *p = buf;

	while ((c = fgetc(stdin)) != EOF && c != '\n')
		*p++ = c;
	if (c == EOF && p == buf)
		return NULL;
	*p = 0;
	return buf;
}
