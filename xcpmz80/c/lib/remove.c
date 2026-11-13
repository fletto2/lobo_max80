#include <_cconv.h>
/* Names for the CP/M C library: remove, rename, tmpnam and
 * tmpfile. remove takes wildcards, as ERA does. */

#include <string.h>
#include <errno.h>
#include "cpmint.h"

int remove(const char *name) __LIB
{
	unsigned char fcb[36];

	if (__mkfcb(fcb, name)) {
		errno = EINVAL;
		return -1;
	}
	if ((unsigned char)bdos(19, (unsigned int)fcb) == 0xff) {
		errno = ENOENT;
		return -1;
	}
	return 0;
}

/* The new name must not be there, as C has it */
int rename(const char *from, const char *to) __LIB
{
	unsigned char fcb[16 + 36];	/* the new name's FCB from fcb+16 */

	/* the old name first: __mkfcb clears 36 bytes */
	if (__mkfcb(fcb, from) || __mkfcb(fcb + 16, to)) {
		errno = EINVAL;
		return -1;
	}
	fcb[16] = fcb[0];
	if ((unsigned char)bdos(15, (unsigned int)(fcb + 16)) != 0xff) {
		bdos(16, (unsigned int)(fcb + 16));
		errno = EEXIST;
		return -1;
	}
	__mkfcb(fcb + 16, to);
	fcb[16] = fcb[0];
	if ((unsigned char)bdos(23, (unsigned int)fcb) == 0xff) {
		errno = ENOENT;
		return -1;
	}
	return 0;
}

/* $TMPnn.$$$ on the current drive, the first one not there */
char *tmpnam(char *buf) __LIB
{
	static char name[L_tmpnam];
	static unsigned char next;
	unsigned char fcb[36], i;

	if (!buf)
		buf = name;
	for (i = 0; i < TMP_MAX; i++) {
		strcpy(buf, "$TMP00.$$$");
		buf[4] = '0' + next / 10;
		buf[5] = '0' + next % 10;
		if (++next == TMP_MAX)
			next = 0;
		__mkfcb(fcb, buf);
		if ((unsigned char)bdos(15, (unsigned int)fcb) == 0xff)
			return buf;
		bdos(16, (unsigned int)fcb);
	}
	return NULL;
}

/* Not removed by itself at the end: CP/M has no such call */
FILE *tmpfile(void) __LIB
{
	char *n = tmpnam(NULL);

	return n ? fopen(n, "w+b") : NULL;
}
