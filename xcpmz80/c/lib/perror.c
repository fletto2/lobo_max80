#include <_cconv.h>
/* perror for the CP/M C library */

#include <string.h>
#include <errno.h>
#include "cpmint.h"

void perror(const char *s) __LIB
{
	if (s && *s) {
		fputs(s, stderr);
		fputs(": ", stderr);
	}
	fputs(strerror(errno), stderr);
	fputc('\n', stderr);
}
