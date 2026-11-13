#include <_cconv.h>
/* POSIX-style calls for the CP/M C library: open, read, write,
 * close, lseek on stdio files, and unlink, access, isatty, sleep,
 * chdir and getcwd. A file descriptor is 0, 1 or 2 for the console, or
 * 3 on for the FILE table, and files are binary unless O_TEXT. */

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include "cpmint.h"

int open(const char *name, int flags, ...) __LIB
{
	char mode[4], *m = mode;
	unsigned char fcb[36];
	unsigned char there;
	FILE *f;

	if (__mkfcb(fcb, name)) {
		errno = EINVAL;
		return -1;
	}
	there = (unsigned char)bdos(15, (unsigned int)fcb) != 0xff;
	if (there)
		bdos(16, (unsigned int)fcb);
	if ((flags & O_CREAT) && (flags & O_EXCL) && there) {
		errno = EEXIST;
		return -1;
	}
	if (!there && !(flags & O_CREAT)) {
		errno = ENOENT;
		return -1;
	}
	if (!there || (flags & O_TRUNC))
		*m++ = 'w';
	else if (flags & O_APPEND)
		*m++ = 'a';
	else
		*m++ = 'r';
	if ((flags & O_ACCMODE) != O_RDONLY && m[-1] == 'r')
		*m++ = '+';
	else if ((flags & O_ACCMODE) == O_RDWR)
		*m++ = '+';
	if (!(flags & O_TEXT))
		*m++ = 'b';
	*m = 0;
	f = fopen(name, mode);
	return f ? fileno(f) : -1;
}

int creat(const char *name, int mode) __LIB
{
	(void)mode;
	return open(name, O_WRONLY | O_CREAT | O_TRUNC);
}

static FILE *fd(int n)
{
	FILE *f = __fd2file(n);

	if (!f)
		errno = EBADF;
	return f;
}

ssize_t read(int n, void *buf, size_t len) __LIB
{
	FILE *f = fd(n);
	unsigned char *p = buf;
	size_t i;
	int c;

	if (!f)
		return -1;
	if (!(f->flags & F_CON))
		return fread(buf, 1, len, f);
	/* the console gives one line at most, as a terminal does */
	for (i = 0; i < len; ) {
		if ((c = fgetc(f)) == EOF)
			break;
		p[i++] = c;
		if (c == '\n')
			break;
	}
	return i;
}

ssize_t write(int n, const void *buf, size_t len) __LIB
{
	FILE *f = fd(n);

	return f ? (ssize_t)fwrite(buf, 1, len, f) : -1;
}

int close(int n) __LIB
{
	FILE *f = fd(n);

	return f ? fclose(f) : -1;
}

off_t lseek(int n, off_t off, int whence) __LIB
{
	FILE *f = fd(n);

	if (!f || fseek(f, off, whence))
		return -1;
	return ftell(f);
}

int unlink(const char *name) __LIB
{
	return remove(name);
}

/* CP/M 3's R/O attribute, t1 bit 7, says the file cannot be written */
int access(const char *name, int mode) __LIB
{
	unsigned char fcb[36];

	if (__mkfcb(fcb, name)) {
		errno = EINVAL;
		return -1;
	}
	if ((unsigned char)bdos(15, (unsigned int)fcb) == 0xff) {
		errno = ENOENT;
		return -1;
	}
	bdos(16, (unsigned int)fcb);
	if ((mode & W_OK) && (fcb[9] & 0x80)) {
		errno = EACCES;
		return -1;
	}
	return 0;
}

int isatty(int n) __LIB
{
	FILE *f = __fd2file(n);

	return f && (f->flags & F_CON);
}

/* A loop timed for the MAX-80's 5 MHz */
static void spin(unsigned int ms)
{
	volatile unsigned int i;

	while (ms--)
		for (i = 0; i < 140; i++)
			;
}

/* By the clock call where there is one, else spin() */
unsigned int sleep(unsigned int sec) __LIB
{
	time_t end = time(NULL);

	if (!end) {
		while (sec--)
			spin(1000);
		return 0;
	}
	if (sec)		/* whole seconds: one more, so never less */
		end += sec + 1;
	while (time(NULL) < end)
		;
	return 0;
}

int usleep(unsigned long usec) __LIB
{
	spin(usec / 1000);
	return 0;
}

/* "B:" as the current drive */
int chdir(const char *d) __LIB
{
	unsigned char n = (d[0] | 32) - 'a';

	if (!d[0] || d[1] != ':' || n > 15) {
		errno = ENOENT;
		return -1;
	}
	bdos(14, n);
	return 0;
}

char *getcwd(char *buf, size_t n) __LIB
{
	if (n < 3) {
		errno = ERANGE;
		return NULL;
	}
	buf[0] = 'A' + (unsigned char)bdos(25, 0);
	buf[1] = ':';
	buf[2] = 0;
	return buf;
}
