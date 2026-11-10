#include <_cconv.h>
/* Lines for the CP/M C library: fgets and gets */

#include "cpmint.h"

char *fgets(char *buf, int n, FILE *f) __LIB
{
	int c, i = 0;
	unsigned char k;

	while (i < n - 1) {
		/* The console, a byte put back, the end or a file not open
		   for reading: a byte at a time, as fgetc has them */
		if (f->unget != EOF || (f->flags & (F_CON | F_EOF)) ||
		    !(f->flags & F_READ)) {
			c = fgetc(f);
			if (c == EOF)
				break;
			buf[i++] = c;
			if (c == '\n')
				break;
			continue;
		}
		/* A file: the rest of the record in its buffer at once, the
		   record checked once, not for every byte, as fgetc reads */
		if (__loadrec(f) == EOF)
			break;
		k = (unsigned char)f->pos & 127;
		do {
			c = (unsigned char)f->buf[k++];
			if ((f->flags & F_TEXT) && c == 0x1a) {
				f->flags |= F_EOF;
				goto done;
			}
			f->pos++;
			if ((f->flags & F_TEXT) && c == '\r')
				continue;
			buf[i++] = c;
			if (c == '\n')
				goto done;
		} while (k < 128 && i < n - 1);
	}
done:
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
