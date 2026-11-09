#include <_cconv.h>
/* Reading bytes for the CP/M C library: the console's line, fgetc,
 * getchar and ungetc. stdin is read a line at a time by function 10, so
 * the CCP's editing keys work, as in any CP/M program. */

#include "cpmint.h"

static char line[130];
static unsigned char lpos, llen, lgot;

int __conin(void)
{
	if (!lgot) {
		line[0] = 128;
		bdos(10, (unsigned int)line);
		bdos(2, '\r');
		bdos(2, '\n');
		llen = line[1];
		lpos = 0;
		lgot = 1;
		/* ^Z alone on a line is the end of the input */
		if (llen == 1 && line[2] == 0x1a) {
			lgot = 0;
			return EOF;
		}
	}
	if (lpos < llen)
		return (unsigned char)line[2 + lpos++];
	lgot = 0;
	return '\n';
}

int fgetc(FILE *f) __LIB
{
	int c;

	if (f->unget != EOF) {
		c = f->unget;
		f->unget = EOF;
		if (!(f->flags & F_CON))
			f->pos++;
		return c;
	}
	if (f->flags & F_CON) {
		c = __conin();
		if (c == EOF)
			f->flags |= F_EOF;
		return c;
	}
	if (!(f->flags & F_READ) || (f->flags & F_EOF))
		return EOF;
	for (;;) {
		if (__loadrec(f) == EOF)
			return EOF;
		c = f->buf[(unsigned char)f->pos & 127];
		if ((f->flags & F_TEXT) && c == 0x1a) {
			f->flags |= F_EOF;
			return EOF;
		}
		f->pos++;
		if (!(f->flags & F_TEXT) || c != '\r')
			return c;
	}
}

int getchar(void) __LIB
{
	return fgetc(stdin);
}

/* One byte back. A file's position goes back one with it. */
int ungetc(int c, FILE *f) __LIB
{
	if (c == EOF || f->unget != EOF)
		return EOF;
	f->unget = (unsigned char)c;
	f->flags &= ~F_EOF;
	if (!(f->flags & F_CON))
		f->pos--;
	return (unsigned char)c;
}
