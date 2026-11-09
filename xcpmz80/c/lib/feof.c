#include <_cconv.h>
/* A file's state for the CP/M C library: feof, ferror, clearerr,
 * fileno, and setbuf and setvbuf, which change nothing, every file has
 * its record buffer and the console none. */

#include "cpmint.h"

int feof(FILE *f) __LIB
{
	return f->flags & F_EOF;
}

int ferror(FILE *f) __LIB
{
	return f->flags & F_ERR;
}

void clearerr(FILE *f) __LIB
{
	f->flags &= ~(F_EOF | F_ERR);
}

/* 0, 1 and 2 the console, 3 on the files in their table */
int fileno(FILE *f) __LIB
{
	if ((struct _con *)f >= __cons && (struct _con *)f < __cons + 3)
		return (struct _con *)f - __cons;
	return f - __files + 3;
}

FILE *__fd2file(int fd)
{
	if (fd >= 0 && fd < 3)
		return CON(fd);
	fd -= 3;
	if (fd >= 0 && fd < FOPEN_MAX && (__files[fd].flags & F_USED))
		return &__files[fd];
	return NULL;
}

void setbuf(FILE *f, char *buf) __LIB
{
	(void)f;
	(void)buf;
}

int setvbuf(FILE *f, char *buf, int mode, size_t size) __LIB
{
	(void)f;
	(void)buf;
	(void)mode;
	(void)size;
	return 0;
}

/* the FILE of a descriptor from open(), which already is one */
FILE *fdopen(int fd, const char *mode) __LIB
{
	(void)mode;
	return __fd2file(fd);
}
