#include <_cconv.h>
/* Broken-down time for the CP/M C library: mktime, gmtime,
 * localtime and their _r forms. Local time is the same as UTC. Written
 * small for the resident library: three long divisions, the rest
 * in ints, and mktime lets gmtime bring the fields into range. */

#include <time.h>

static const unsigned char mdays[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

static unsigned char leap(unsigned int y)
{
	return !(y & 3) && (y % 100 || !(y % 400));
}

static unsigned char monlen(unsigned int y, unsigned char m)
{
	return mdays[m] + (m == 1 && leap(y));
}

struct tm *gmtime_r(const time_t *tp, struct tm *tm) __LIB
{
	unsigned long t = *tp, m = t / 60, h = m / 60;
	unsigned int d = h / 24, y = 1970, n;
	unsigned char mon = 0;

	tm->tm_sec = (unsigned int)t - (unsigned int)m * 60;
	tm->tm_min = (unsigned int)m - (unsigned int)h * 60;
	tm->tm_hour = (unsigned int)h - d * 24;
	tm->tm_wday = (d + 4) % 7;		/* 1 January 1970 was a Thursday */
	while (d >= (n = 365 + leap(y))) {
		d -= n;
		y++;
	}
	tm->tm_year = y - 1900;
	tm->tm_yday = d;
	while (d >= (n = monlen(y, mon))) {
		d -= n;
		mon++;
	}
	tm->tm_mon = mon;
	tm->tm_mday = d + 1;
	tm->tm_isdst = 0;
	return tm;
}

struct tm *localtime_r(const time_t *t, struct tm *tm) __LIB
{
	return gmtime_r(t, tm);
}

static struct tm stm;

struct tm *gmtime(const time_t *t) __LIB
{
	return gmtime_r(t, &stm);
}

struct tm *localtime(const time_t *t) __LIB
{
	return gmtime_r(t, &stm);
}

/* Fields out of range are brought in, as C has it: 32 January is
 * 1 February. Fills in tm_wday and tm_yday. */
time_t mktime(struct tm *tm) __LIB
{
	int mon = tm->tm_mon;
	unsigned int y = tm->tm_year + 1900, i;
	long days;
	time_t t;

	y += mon / 12;
	mon %= 12;
	if (mon < 0) {
		mon += 12;
		y--;
	}
	if (y < 1970)
		return (time_t)-1;
	days = tm->tm_mday - 1;
	for (i = 1970; i < y; i++)
		days += 365 + leap(i);
	for (i = 0; i < (unsigned int)mon; i++)
		days += monlen(y, i);
	t = ((days * 24 + tm->tm_hour) * 60 + tm->tm_min) * 60 + tm->tm_sec;
	gmtime_r(&t, tm);
	return t;
}
