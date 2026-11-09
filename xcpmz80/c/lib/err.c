#include <_cconv.h>
/* err and warn for the CP/M C library. CP/M keeps no program
 * name, so the message has no program name in front. warn and err add strerror. */

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <err.h>
#include "cpmint.h"

static void vwarn(unsigned char e, const char *fmt, va_list ap)
{
	if (fmt)
		vfprintf(stderr, fmt, ap);
	if (e) {
		if (fmt)
			fputs(": ", stderr);
		fputs(strerror(errno), stderr);
	}
	fputc('\n', stderr);
}

void warn(const char *fmt, ...) __LIB
{
	va_list ap;

	va_start(ap, fmt);
	vwarn(1, fmt, ap);
	va_end(ap);
}

void warnx(const char *fmt, ...) __LIB
{
	va_list ap;

	va_start(ap, fmt);
	vwarn(0, fmt, ap);
	va_end(ap);
}

void err(int code, const char *fmt, ...) __LIB
{
	va_list ap;

	va_start(ap, fmt);
	vwarn(1, fmt, ap);
	va_end(ap);
	exit(code);
}

void errx(int code, const char *fmt, ...) __LIB
{
	va_list ap;

	va_start(ap, fmt);
	vwarn(0, fmt, ap);
	va_end(ap);
	exit(code);
}
