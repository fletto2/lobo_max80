#include <_cconv.h>
/* Writing bytes for the CP/M C library: fputc and putchar. On the
 * console '\n' goes out as CR LF, by function 2. */

#include "cpmint.h"

void __conout(char c)
{
	if (c == '\n')
		bdos(2, '\r');
	bdos(2, (unsigned char)c);
}

int __rawput(unsigned char c, FILE *f)
{
	if (__loadrec(f) == EOF)
		return EOF;
	f->buf[(unsigned char)f->pos & 127] = c;
	f->flags |= F_DIRTY;
	f->pos++;
	return c;
}

int fputc(int c, FILE *f) __LIB
{
	if (f->flags & F_CON) {
		__conout(c);
		return (unsigned char)c;
	}
	if (!(f->flags & F_WRITE)) {
		f->flags |= F_ERR;
		return EOF;
	}
	f->unget = EOF;
	if ((f->flags & F_TEXT) && c == '\n' && __rawput('\r', f) == EOF)
		return EOF;
	return __rawput(c, f);
}

int putchar(int c) __LIB
{
	return fputc(c, stdout);
}
