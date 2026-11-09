#include <_cconv.h>
/* assert's message for the CP/M C library */

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

void __assert(const char *expr, const char *file, int line) __LIB {
	fprintf(stderr, "Assertion failed: %s, %s line %d\n", expr, file, line);
	abort();
}
