#include <_cconv.h>
/* time and clock for the CP/M C library, from CP/M 3's clock,
 * function 105: days from 1 January 1978 and the time in BCD. xcpmz80
 * gives it from the clock chip. Under CP/M 2.2, with no clock call,
 * time gives 0 and clock -1. */

#include <time.h>
#include "cpmint.h"

static unsigned char bcd(unsigned char b)
{
	return (b >> 4) * 10 + (b & 15);
}

time_t time(time_t *t) __LIB
{
	unsigned char dt[4] = { 0, 0, 0, 0 };
	unsigned char sec;
	time_t v = 0;

	if ((unsigned char)bdos(12, 0) >= 0x30) {
		sec = bdos(105, (unsigned int)dt);
		v = (unsigned int)(dt[0] | dt[1] << 8);
		if (v)	/* 1970 to 1978 is 2922 days, day 1 is 1 January 1978 */
			v = (v + 2921) * 86400UL + bcd(dt[2]) * 3600UL
				+ bcd(dt[3]) * 60 + bcd(sec);
	}
	if (t)
		*t = v;
	return v;
}

/* Seconds since the first call: the clock call gives whole seconds */
clock_t clock(void) __LIB
{
	static time_t start;
	time_t now = time(NULL);

	if (!now)
		return (clock_t)-1;
	if (!start)
		start = now;
	return (now - start) * CLOCKS_PER_SEC;
}

long difftime(time_t a, time_t b) __LIB
{
	return (long)(a - b);
}
