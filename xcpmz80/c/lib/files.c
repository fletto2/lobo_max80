#include <_cconv.h>
/* Files for the CP/M C library: the FILE table, names to FCBs,
 * the record buffer, fopen, freopen, fclose and fflush.
 *
 * Files are read and written a 128-byte record at a time by the random
 * record calls (33, 34), so fseek goes anywhere at once. A file opened
 * without "b" is text: CR is dropped and ^Z ends it on reading, and
 * '\n' goes out as CR LF. The console is stdin, stdout and stderr. */

#include <string.h>
#include <ctype.h>
#include <errno.h>
#include "cpmint.h"

FILE __files[FOPEN_MAX];
struct _con __cons[3];		/* set by __coninit */
FILE *stdin = CON(0);
FILE *stdout = CON(1);
FILE *stderr = CON(2);
int errno;

/* the console's FILEs, from the start-up */
void __coninit(void)
{
	__cons[0].flags = F_USED | F_CON | F_READ;
	__cons[1].flags = __cons[2].flags = F_USED | F_CON | F_WRITE;
	__cons[0].unget = __cons[1].unget = __cons[2].unget = EOF;
}

static void field(unsigned char *d, const char **sp, unsigned char n)
{
	const char *s = *sp;
	unsigned char i;

	for (i = 0; *s && *s != '.' && i < n; i++) {
		if (*s == '*') {
			for (; i < n; i++)
				d[i] = '?';
			break;
		}
		d[i] = toupper((unsigned char)*s++);
	}
	while (*s && *s != '.')
		s++;
	*sp = s;
}

int __mkfcb(unsigned char *fcb, const char *s)
{
	memset(fcb, 0, 36);
	memset(fcb + 1, ' ', 11);
	if (s[0] && s[1] == ':') {
		unsigned char d = toupper((unsigned char)s[0]) - 'A';
		if (d > 15)
			return -1;
		fcb[0] = d + 1;
		s += 2;
	}
	if (!*s)
		return -1;
	field(fcb + 1, &s, 8);
	if (*s == '.') {
		s++;
		field(fcb + 9, &s, 3);
	}
	/* ".TXT" has no name, and a path, a second colon or a character
	 * CP/M keeps out of names would be in the FCB's (I291) */
	if (fcb[1] == ' ')
		return -1;
	{
		unsigned char i, c;
		for (i = 1; i < 12; i++) {
			c = fcb[i];
			if (c < ' ' || strchr("\\/:<>,;=[]|\"+", c))
				return -1;
		}
	}
	return 0;
}

/* random read (33) or write (34) of record f->rec to buf, 0 when done */
static unsigned char recio(FILE *f, unsigned char fn)
{
	f->fcb[33] = f->rec;
	f->fcb[34] = f->rec >> 8;
	f->fcb[35] = f->rec >> 16;
	bdos(26, (unsigned int)f->buf);
	return bdos(fn, (unsigned int)f->fcb);
}

int __flushrec(FILE *f)
{
	if (f->flags & F_DIRTY) {
		f->flags &= ~F_DIRTY;
		if (recio(f, 34)) {
			f->flags |= F_ERR;
			errno = ENOSPC;
			return EOF;
		}
	}
	return 0;
}

/* buf = the record f->pos is in. Past the end it is ^Z, so a write
 * there starts a new record and a text read finds the end. */
int __loadrec(FILE *f)
{
	long r = f->pos >> 7;

	if (r == f->rec)
		return 0;
	if (__flushrec(f))
		return EOF;
	f->rec = r;
	if (recio(f, 33)) {
		memset(f->buf, 0x1a, 128);
		return 1;
	}
	return 0;
}

/* __loadrec for a read: a binary file ends after its last record,
 * which it forgets, so a read after a seek asks again */
int __getrec(FILE *f)
{
	int r = __loadrec(f);

	if (r == 1 && !(f->flags & F_TEXT)) {
		f->rec = -1;
		f->flags |= F_EOF;
		return EOF;
	}
	return r;
}

static unsigned char isopen(unsigned char *fcb)
{
	return (unsigned char)bdos(15, (unsigned int)fcb) != 0xff;
}

/* mode: r, w or a, then + and b in any order */
FILE *__fopen(FILE *f, const char *name, const char *mode)
{
	unsigned char plus = strchr(mode, '+') != NULL;

	if (__mkfcb(f->fcb, name) || strchr(name, '?') || strchr(name, '*')) {
		errno = EINVAL;
		return NULL;
	}
	f->pos = 0;
	f->rec = -1;
	f->unget = EOF;
	f->flags = strchr(mode, 'b') ? 0 : F_TEXT;
	switch (mode[0]) {
	case 'r':
		if (!isopen(f->fcb)) {
			errno = ENOENT;
			return NULL;
		}
		f->flags |= F_READ | (plus ? F_WRITE : 0);
		break;
	case 'a':
		if (isopen(f->fcb)) {
			f->flags |= F_USED | F_WRITE | (plus ? F_READ : 0);
			fseek(f, 0, SEEK_END);
			if ((f->flags & F_TEXT) && f->pos) {
				/* a text file goes on at its ^Z */
				unsigned char k = 0;

				f->pos -= 128;
				if (!__loadrec(f)) {
					while (k < 128 && f->buf[k] != 0x1a)
						k++;
					/* what was after the ^Z, from another
					 * program, not shown after the new
					 * text (I290) */
					memset(f->buf + k, 0x1a, 128 - k);
				} else
					k = 128;
				f->pos += k;
			}
			return f;
		}
		/* no file: as "w" */
	case 'w':
		bdos(19, (unsigned int)f->fcb);
		f->fcb[12] = f->fcb[32] = 0;
		if ((unsigned char)bdos(22, (unsigned int)f->fcb) == 0xff) {
			errno = ENOSPC;
			return NULL;
		}
		f->flags |= F_WRITE | (plus ? F_READ : 0);
		break;
	default:
		errno = EINVAL;
		return NULL;
	}
	f->flags |= F_USED;
	return f;
}

FILE *fopen(const char *name, const char *mode) __LIB
{
	unsigned char i;

	for (i = 0; i < FOPEN_MAX; i++)
		if (!(__files[i].flags & F_USED))
			return __fopen(&__files[i], name, mode);
	errno = EMFILE;
	return NULL;
}

int fclose(FILE *f) __LIB
{
	int r;

	if (f->flags & F_CON)
		return 0;
	if (!(f->flags & F_USED))
		return EOF;
	r = __flushrec(f);
	if ((f->flags & F_WRITE) && (unsigned char)bdos(16, (unsigned int)f->fcb) == 0xff)
		r = EOF;
	f->flags = 0;
	return r;
}

/* freopen(NULL, ...) of the console changes nothing */
FILE *freopen(const char *name, const char *mode, FILE *f) __LIB
{
	if (f->flags & F_CON)
		return name ? NULL : f;
	fclose(f);
	return name ? __fopen(f, name, mode) : NULL;
}

int fflush(FILE *f) __LIB
{
	unsigned char i;
	int r = 0;

	if (!f) {
		for (i = 0; i < FOPEN_MAX; i++)
			if ((__files[i].flags & F_USED) && __flushrec(&__files[i]))
				r = EOF;
		return r;
	}
	return f->flags & F_CON ? 0 : __flushrec(f);
}

void __closeall(void)
{
	unsigned char i;

	for (i = 0; i < FOPEN_MAX; i++)
		if (__files[i].flags & F_USED)
			fclose(&__files[i]);
}
