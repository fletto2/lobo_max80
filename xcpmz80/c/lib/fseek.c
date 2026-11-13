#include <_cconv.h>
/* Positions for the CP/M C library: fseek, ftell, rewind, fgetpos
 * and fsetpos. SEEK_END is the end of the last record, CP/M keeps no
 * byte count, and a text file ends earlier at its ^Z. */

#include "cpmint.h"

int fseek(FILE *f, long off, int whence) __LIB
{
	if (f->flags & F_CON)
		return -1;
	if (whence == SEEK_CUR)
		off += f->pos;
	else if (whence == SEEK_END) {
		if (__flushrec(f))	/* the size with what is buffered */
			return -1;
		bdos(35, (unsigned int)f->fcb);	/* the size in records */
		off += ((long)f->fcb[33] | (long)f->fcb[34] << 8
			| (long)f->fcb[35] << 16) << 7;
	}
	if (off < 0)
		return -1;
	f->pos = off;
	f->unget = EOF;
	f->flags &= ~F_EOF;
	return 0;
}

long ftell(FILE *f) __LIB
{
	return f->flags & F_CON ? -1 : f->pos;
}

void rewind(FILE *f) __LIB
{
	fseek(f, 0, SEEK_SET);
	f->flags &= ~F_ERR;
}

int fgetpos(FILE *f, fpos_t *pos) __LIB
{
	*pos = ftell(f);
	return *pos < 0 ? -1 : 0;
}

int fsetpos(FILE *f, const fpos_t *pos) __LIB
{
	return fseek(f, *pos, SEEK_SET);
}
