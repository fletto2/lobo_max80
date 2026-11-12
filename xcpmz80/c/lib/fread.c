#include <_cconv.h>
/* Blocks for the CP/M C library: fread and fwrite. fwrite goes a byte
 * at a time through fputc. fread takes the rest of a record from its
 * buffer at once, as fgets does, and the console, a byte put back or
 * the end through fgetc. The resident library's wrappers (clib/wrap.c)
 * call them 128 bytes at a time. */

#include "cpmint.h"

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *f) __LIB
{
	unsigned char *p = ptr;
	size_t want, got = 0;
	unsigned char k, c, text;
	int ch;

	if (!size || !nmemb)
		return 0;
	want = size * nmemb;
	text = f->flags & F_TEXT;
	while (got < want) {
		if (f->unget != EOF || (f->flags & (F_CON | F_EOF)) ||
		    !(f->flags & F_READ)) {
			if ((ch = fgetc(f)) == EOF)
				break;
			p[got++] = ch;
			continue;
		}
		/* as fgetc has them: a text file ends at ^Z and has no CRs */
		if (__loadrec(f) == EOF)
			break;
		k = (unsigned char)f->pos & 127;
		do {
			c = (unsigned char)f->buf[k++];
			if (text && c == 0x1a) {
				f->flags |= F_EOF;
				goto done;
			}
			f->pos++;
			if (text && c == '\r')
				continue;
			p[got++] = c;
		} while (k < 128 && got < want);
	}
done:
	return got / size;
}

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *f) __LIB
{
	const unsigned char *p = ptr;
	size_t want, put;

	if (!size || !nmemb)
		return 0;
	want = size * nmemb;
	for (put = 0; put < want; put++)
		if (fputc(*p++, f) == EOF)
			break;
	return put / size;
}
