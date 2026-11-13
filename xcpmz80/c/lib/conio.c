#include <_cconv.h>
/* The console without stdio for the CP/M C library: keys one at
 * a time with no echo by function 6, as an editor wants, and output as
 * it is, with no CR added. */

#include <stdio.h>
#include <stdarg.h>
#include "cpmint.h"

static int held = -1;	/* a key kbhit read with function 6 */

int kbhit(void) __LIB {
	if (held < 0) {
		unsigned char c = bdos(6, 0xff);
		if (c)
			held = c;
	}
	return held >= 0;
}

int getch(void) __LIB
{
	unsigned char c;

	if (held >= 0) {
		c = held;
		held = -1;
		return c;
	}
	while (!(c = bdos(6, 0xff)))
		;
	return c;
}

int putch(int c) __LIB
{
	/* function 6 reads a key for FFh (and FEh in CP/M 3) */
	bdos((unsigned char)c >= 0xfe ? 2 : 6, (unsigned char)c);
	return (unsigned char)c;
}

int getche(void) __LIB
{
	return putch(getch());
}

int cputs(const char *s) __LIB
{
	while (*s)
		putch(*s++);
	return 0;
}

static void cout(char c, void *a)
{
	(void)a;
	putch(c);
}

int cprintf(const char *fmt, ...) __LIB
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = __vfmt(cout, NULL, fmt, ap);
	va_end(ap);
	return n;
}

/* function 10 into buf: buf[0] the room, buf[1] the length read, the
 * text from buf+2 with a 0 after it. At most buf[0] - 1 characters,
 * so the 0 fits in buf[0] + 2 bytes, as DOS has it */
char *cgets(char *buf) __LIB
{
	unsigned char room = buf[0];

	if (room)
		buf[0] = room - 1;
	bdos(10, (unsigned int)buf);
	buf[0] = room;
	buf[2 + (unsigned char)buf[1]] = 0;
	return buf + 2;
}
