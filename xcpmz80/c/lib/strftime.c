#include <_cconv.h>
/* strftime for the CP/M C library: %a %A %b %B %c %d %e %H %I %j
 * %m %M %n %p %S %t %u %w %y %Y %D %F %T %R %% in the C locale, and
 * asctime and ctime by it. 0 when the text does not fit. */

#include <time.h>
#include <string.h>

static const char *const wdays[7] = { "Sunday", "Monday", "Tuesday",
	"Wednesday", "Thursday", "Friday", "Saturday" };
static const char *const mons[12] = { "January", "February", "March",
	"April", "May", "June", "July", "August", "September", "October",
	"November", "December" };

/* the conversions that are others put together */
static const char *const compound[] = {
	"c%a %b %e %H:%M:%S %Y", "D%m/%d/%y", "F%Y-%m-%d", "T%H:%M:%S", "R%H:%M"
};

static char *out, *end;		/* where the text goes, its last byte */

static void put(const char *s, unsigned char n)
{
	while (n-- && *s) {
		if (out == end) {
			out = NULL;
			return;
		}
		*out++ = *s++;
	}
}

/* v in w digits, 0 or space in front */
static void num(unsigned int v, unsigned char w, char pad)
{
	char d[5];
	unsigned char i = 5;

	do {
		d[--i] = '0' + v % 10;
		v /= 10;
	} while (v && i);
	while (5 - i < w)
		d[--i] = pad;
	put(d + i, 5 - i);
}

static void fmt(const char *f, const struct tm *t)
{
	unsigned char i;

	for (; *f && out; f++) {
		if (*f != '%') {
			put(f, 1);
			continue;
		}
		switch (*++f) {
		case 'a': put(wdays[t->tm_wday % 7], 3); break;
		case 'A': put(wdays[t->tm_wday % 7], 255); break;
		case 'b':
		case 'h': put(mons[t->tm_mon % 12], 3); break;
		case 'B': put(mons[t->tm_mon % 12], 255); break;
		case 'd': num(t->tm_mday, 2, '0'); break;
		case 'e': num(t->tm_mday, 2, ' '); break;
		case 'H': num(t->tm_hour, 2, '0'); break;
		case 'I': num((t->tm_hour + 11) % 12 + 1, 2, '0'); break;
		case 'j': num(t->tm_yday + 1, 3, '0'); break;
		case 'm': num(t->tm_mon + 1, 2, '0'); break;
		case 'M': num(t->tm_min, 2, '0'); break;
		case 'S': num(t->tm_sec, 2, '0'); break;
		case 'u': num(t->tm_wday ? t->tm_wday : 7, 1, '0'); break;
		case 'w': num(t->tm_wday, 1, '0'); break;
		case 'y': num(t->tm_year % 100, 2, '0'); break;
		case 'Y': num(t->tm_year + 1900, 1, '0'); break;
		case 'p': put(t->tm_hour < 12 ? "AM" : "PM", 2); break;
		case 'n': put("\n", 1); break;
		case 't': put("\t", 1); break;
		case 0:
			f--;
			/* fall through */
		default:
			for (i = 0; i < sizeof(compound) / sizeof(compound[0]); i++)
				if (compound[i][0] == *f) {
					fmt(compound[i] + 1, t);
					break;
				}
			if (i == sizeof(compound) / sizeof(compound[0]))
				put("%", 1);
			break;
		}
	}
}

size_t strftime(char *buf, size_t n, const char *f, const struct tm *t) __LIB
{
	if (!n)
		return 0;
	out = buf;
	end = buf + n - 1;
	fmt(f, t);
	if (!out)
		return 0;
	*out = 0;
	return out - buf;
}

/* "Sun Nov  1 12:34:56 2026\n" */
char *asctime(const struct tm *t) __LIB
{
	static char buf[26];

	strftime(buf, sizeof(buf), "%a %b %e %H:%M:%S %Y\n", t);
	return buf;
}

char *ctime(const time_t *t) __LIB
{
	return asctime(localtime(t));
}
