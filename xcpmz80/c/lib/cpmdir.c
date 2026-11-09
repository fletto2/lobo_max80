#include <_cconv.h>
/* CP/M itself for the CP/M C library: the version, drive and user,
 * the directory search (functions 17 and 18) and a file's size. */

#include <string.h>
#include <cpm.h>
#include "cpmint.h"

unsigned char cpm_version(void) __LIB
{
	return bdos(12, 0);
}

int cpm_getdrive(void) __LIB
{
	return (unsigned char)bdos(25, 0);
}

void cpm_setdrive(int d) __LIB
{
	bdos(14, d);
}

int cpm_getuser(void) __LIB
{
	return (unsigned char)bdos(32, 0xff);
}

void cpm_setuser(int u) __LIB
{
	bdos(32, u);
}

static unsigned char sfcb[36];
static unsigned char dma[128];

/* the entry n of the record the search gave, as "NAME.EXT" */
static int entry(unsigned char n, char *name)
{
	unsigned char *e, i;

	if (n > 3)
		return -1;
	e = dma + 32 * n;
	for (i = 1; i < 9 && (e[i] & 127) != ' '; i++)
		*name++ = e[i] & 127;
	if ((e[9] & 127) != ' ') {
		*name++ = '.';
		for (i = 9; i < 12 && (e[i] & 127) != ' '; i++)
			*name++ = e[i] & 127;
	}
	*name = 0;
	return 0;
}

int cpm_findfirst(const char *pattern, char *name) __LIB
{
	if (__mkfcb(sfcb, pattern))
		return -1;
	bdos(26, (unsigned int)dma);
	return entry(bdos(17, (unsigned int)sfcb), name);
}

int cpm_findnext(char *name) __LIB
{
	bdos(26, (unsigned int)dma);
	return entry(bdos(18, (unsigned int)sfcb), name);
}

long cpm_filesize(const char *name) __LIB
{
	unsigned char fcb[36];

	if (__mkfcb(fcb, name))
		return -1;
	if ((unsigned char)bdos(15, (unsigned int)fcb) == 0xff)
		return -1;
	bdos(16, (unsigned int)fcb);
	bdos(35, (unsigned int)fcb);
	return ((long)fcb[33] | (long)fcb[34] << 8 | (long)fcb[35] << 16) << 7;
}
