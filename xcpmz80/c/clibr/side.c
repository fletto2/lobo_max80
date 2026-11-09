#include <_cconv.h>
/* The program's side of the resident C library: what has to be in
 * the program. The variables the library writes for it, the FILEs by
 * their numbers, and exit, which runs the atexit functions, here since
 * they are the program's. */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int errno;
char __clibstr[80];		/* CLIB_STRLEN */
struct tm __clibtm;
FILE *stdin = (FILE *)1;
FILE *stdout = (FILE *)2;
FILE *stderr = (FILE *)3;

#define NATEXIT 8
static void (*fns[NATEXIT])(void);
static unsigned char nfns;

void __clib_exit(int code);

int atexit(void (*fn)(void)) __LIB
{
	if (nfns == NATEXIT)
		return -1;
	fns[nfns++] = fn;
	return 0;
}

void exit(int code) __LIB
{
	while (nfns)
		fns[--nfns]();
	__clib_exit(code);
}
