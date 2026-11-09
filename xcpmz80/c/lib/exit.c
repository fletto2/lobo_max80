#include <_cconv.h>
/* The end of a program for the CP/M C library: exit, _exit,
 * abort and atexit. exit runs the atexit functions last first, closes
 * the files and warm boots. A code other than 0 is kept for SUBMIT in
 * CP/M 3's program return code (function 108). */

#include <stdlib.h>
#include "cpmint.h"

#define NATEXIT 8
static void (*fns[NATEXIT])(void);
static unsigned char nfns;

int atexit(void (*fn)(void)) __LIB
{
	if (nfns == NATEXIT)
		return -1;
	fns[nfns++] = fn;
	return 0;
}

void _exit(int code) __LIB
{
	/* FF00h is CP/M 3's "failed", 0 success */
	bdos(108, code ? 0xff00 : 0);
	bdos(0, 0);
	for (;;)
		;
}

void exit(int code) __LIB
{
	while (nfns)
		fns[--nfns]();
	__closeall();
	_exit(code);
}

void abort(void) __LIB
{
	fputs("Abnormal program end\n", stderr);
	_exit(1);
}
