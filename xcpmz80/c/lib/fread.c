#include <_cconv.h>
/* Blocks for the CP/M C library: fread and fwrite, a byte at a
 * time through fgetc and fputc. The resident library's wrappers
 * (clib/wrap.c) call them 128 bytes at a time. */

#include "cpmint.h"

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *f) __LIB
{
	unsigned char *p = ptr;
	size_t want, got;
	int c;

	if (!size || !nmemb)
		return 0;
	want = size * nmemb;
	for (got = 0; got < want; got++) {
		if ((c = fgetc(f)) == EOF)
			break;
		*p++ = c;
	}
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
