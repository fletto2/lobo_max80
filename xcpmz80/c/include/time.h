/* time for SDCC programs under CP/M, in lib/time.c, lib/tm.c and
 * lib/strftime.c. The time is local, there are no zones, and time_t
 * counts seconds from 1970, unsigned, so it runs to 2106. */
#ifndef _CPM_TIME_H
#define _CPM_TIME_H
#include <_cconv.h>

#include <stddef.h>

typedef unsigned long time_t;
typedef long clock_t;
#define CLOCKS_PER_SEC	1

struct tm {
	int tm_sec;
	int tm_min;
	int tm_hour;
	int tm_mday;
	int tm_mon;
	int tm_year;		/* from 1900 */
	int tm_wday;		/* 0 Sunday */
	int tm_yday;
	int tm_isdst;
};

time_t time(time_t *t) __LIB;
clock_t clock(void) __LIB;
long difftime(time_t a, time_t b) __LIB;
time_t mktime(struct tm *t) __LIB;
struct tm *gmtime(const time_t *t) __LIB;
struct tm *localtime(const time_t *t) __LIB;
struct tm *gmtime_r(const time_t *t, struct tm *tm) __LIB;
struct tm *localtime_r(const time_t *t, struct tm *tm) __LIB;
char *asctime(const struct tm *t) __LIB;
char *ctime(const time_t *t) __LIB;
size_t strftime(char *buf, size_t n, const char *fmt, const struct tm *t) __LIB;

#endif
