#include <_cconv.h>
/* The string functions for the CP/M C library that are not in
 * assembly. Built once for each function, L_name picks it, so a program
 * links only those it calls. */

#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <ctype.h>

#ifdef L_memcmp
int memcmp(const void *a, const void *b, size_t n) __LIB
{
	const unsigned char *p = a, *q = b;

	for (; n; n--, p++, q++)
		if (*p != *q)
			return *p < *q ? -1 : 1;
	return 0;
}
#endif

#ifdef L_memchr
void *memchr(const void *s, int c, size_t n) __LIB
{
	const unsigned char *p = s;

	for (; n; n--, p++)
		if (*p == (unsigned char)c)
			return (void *)p;
	return NULL;
}
#endif

#ifdef L_memrchr
void *memrchr(const void *s, int c, size_t n) __LIB
{
	const unsigned char *p = (const unsigned char *)s + n;

	while (n--)
		if (*--p == (unsigned char)c)
			return (void *)p;
	return NULL;
}
#endif

#ifdef L_memccpy
void *memccpy(void *d, const void *s, int c, size_t n) __LIB
{
	unsigned char *p = d;
	const unsigned char *q = s;

	for (; n; n--)
		if ((*p++ = *q++) == (unsigned char)c)
			return p;
	return NULL;
}
#endif

#ifdef L_mempcpy
void *mempcpy(void *d, const void *s, size_t n) __LIB
{
	return (unsigned char *)memcpy(d, s, n) + n;
}
#endif

#ifdef L_strncpy
char *strncpy(char *d, const char *s, size_t n) __LIB
{
	char *p = d;

	for (; n && *s; n--)
		*p++ = *s++;
	for (; n; n--)
		*p++ = 0;
	return d;
}
#endif

#ifdef L_strcat
char *strcat(char *d, const char *s) __LIB
{
	strcpy(d + strlen(d), s);
	return d;
}
#endif

#ifdef L_strncat
char *strncat(char *d, const char *s, size_t n) __LIB
{
	char *p = d + strlen(d);

	for (; n && *s; n--)
		*p++ = *s++;
	*p = 0;
	return d;
}
#endif

#ifdef L_strncmp
int strncmp(const char *a, const char *b, size_t n) __LIB
{
	for (; n; n--, a++, b++) {
		if (*a != *b)
			return (unsigned char)*a < (unsigned char)*b ? -1 : 1;
		if (!*a)
			break;
	}
	return 0;
}
#endif

#ifdef L_strcasecmp
int strcasecmp(const char *a, const char *b) __LIB
{
	int c, d;

	do {
		c = tolower((unsigned char)*a++);
		d = tolower((unsigned char)*b++);
	} while (c == d && c);
	return c - d;
}
#endif

#ifdef L_strncasecmp
int strncasecmp(const char *a, const char *b, size_t n) __LIB
{
	int c = 0, d = 0;

	for (; n; n--) {
		c = tolower((unsigned char)*a++);
		d = tolower((unsigned char)*b++);
		if (c != d || !c)
			break;
	}
	return n ? c - d : 0;
}
#endif

#ifdef L_strcoll
int strcoll(const char *a, const char *b) __LIB
{
	return strcmp(a, b);
}
#endif

#ifdef L_strxfrm
size_t strxfrm(char *d, const char *s, size_t n) __LIB
{
	size_t len = strlen(s);

	if (n) {
		strncpy(d, s, n - 1);
		d[n - 1] = 0;
	}
	return len;
}
#endif

#ifdef L_strrchr
char *strrchr(const char *s, int c) __LIB
{
	const char *r = NULL;

	do
		if (*s == (char)c)
			r = s;
	while (*s++);
	return (char *)r;
}
#endif

#ifdef L_strchrnul
char *strchrnul(const char *s, int c) __LIB
{
	while (*s && *s != (char)c)
		s++;
	return (char *)s;
}
#endif

#ifdef L_strspn
size_t strspn(const char *s, const char *set) __LIB
{
	size_t n = 0;

	while (s[n] && strchr(set, s[n]))
		n++;
	return n;
}
#endif

#ifdef L_strcspn
size_t strcspn(const char *s, const char *set) __LIB
{
	size_t n = 0;

	while (s[n] && !strchr(set, s[n]))
		n++;
	return n;
}
#endif

#ifdef L_strpbrk
char *strpbrk(const char *s, const char *set) __LIB
{
	for (; *s; s++)
		if (strchr(set, *s))
			return (char *)s;
	return NULL;
}
#endif

#ifdef L_strstr
char *strstr(const char *s, const char *sub) __LIB
{
	size_t n = strlen(sub);

	if (!n)
		return (char *)s;
	for (; *s; s++)
		if (*s == *sub && !strncmp(s, sub, n))
			return (char *)s;
	return NULL;
}
#endif

#ifdef L_strcasestr
char *strcasestr(const char *s, const char *sub) __LIB
{
	size_t n = strlen(sub);

	if (!n)
		return (char *)s;
	for (; *s; s++)
		if (!strncasecmp(s, sub, n))
			return (char *)s;
	return NULL;
}
#endif

#ifdef L_strtok_r
char *strtok_r(char *s, const char *delim, char **save) __LIB
{
	char *e;

	if (!s)
		s = *save;
	s += strspn(s, delim);
	if (!*s) {
		*save = s;
		return NULL;
	}
	e = s + strcspn(s, delim);
	if (*e)
		*e++ = 0;
	*save = e;
	return s;
}
#endif

#ifdef L_strtok
char *strtok(char *s, const char *delim) __LIB
{
	static char *save;

	return strtok_r(s, delim, &save);
}
#endif

#ifdef L_strsep
char *strsep(char **sp, const char *delim) __LIB
{
	char *s = *sp, *e;

	if (!s)
		return NULL;
	e = s + strcspn(s, delim);
	if (*e)
		*e++ = 0;
	else
		e = NULL;
	*sp = e;
	return s;
}
#endif

#ifdef L_strdup
char *strdup(const char *s) __LIB
{
	size_t n = strlen(s) + 1;
	char *d = malloc(n);

	return d ? memcpy(d, s, n) : NULL;
}
#endif

#ifdef L_strndup
char *strndup(const char *s, size_t n) __LIB
{
	char *d;

	n = strnlen(s, n);
	if (!(d = malloc(n + 1)))
		return NULL;
	memcpy(d, s, n);
	d[n] = 0;
	return d;
}
#endif

#ifdef L_strnlen
size_t strnlen(const char *s, size_t n) __LIB
{
	size_t i = 0;

	while (i < n && s[i])
		i++;
	return i;
}
#endif

#ifdef L_stpcpy
char *stpcpy(char *d, const char *s) __LIB
{
	while ((*d = *s++))
		d++;
	return d;
}
#endif

#ifdef L_stpncpy
char *stpncpy(char *d, const char *s, size_t n) __LIB
{
	for (; n && *s; n--)
		*d++ = *s++;
	memset(d, 0, n);
	return d;
}
#endif

#ifdef L_strlcpy
size_t strlcpy(char *d, const char *s, size_t n) __LIB
{
	size_t len = strlen(s);

	if (n) {
		size_t c = len < n ? len : n - 1;
		memcpy(d, s, c);
		d[c] = 0;
	}
	return len;
}
#endif

#ifdef L_strlcat
size_t strlcat(char *d, const char *s, size_t n) __LIB
{
	size_t dl = strnlen(d, n);

	if (dl == n)
		return n + strlen(s);
	return dl + strlcpy(d + dl, s, n - dl);
}
#endif

#ifdef L_strupr
char *strupr(char *s) __LIB
{
	char *p;

	for (p = s; *p; p++)
		*p = toupper((unsigned char)*p);
	return s;
}
#endif

#ifdef L_strlwr
char *strlwr(char *s) __LIB
{
	char *p;

	for (p = s; *p; p++)
		*p = tolower((unsigned char)*p);
	return s;
}
#endif

#ifdef L_strrev
char *strrev(char *s) __LIB
{
	char *a = s, *b = s + strlen(s), t;

	while (a < --b) {
		t = *a;
		*a++ = *b;
		*b = t;
	}
	return s;
}
#endif

#ifdef L_bzero
void bzero(void *d, size_t n) __LIB {
	memset(d, 0, n);
}
#endif

#ifdef L_bcopy
void bcopy(const void *s, void *d, size_t n) __LIB
{
	memmove(d, s, n);
}
#endif

#ifdef L_bcmp
int bcmp(const void *a, const void *b, size_t n) __LIB
{
	return memcmp(a, b, n);
}
#endif

#ifdef L_index
char *index(const char *s, int c) __LIB
{
	return strchr(s, c);
}
#endif

#ifdef L_rindex
char *rindex(const char *s, int c) __LIB
{
	return strrchr(s, c);
}
#endif

#ifdef L_ffs
int ffs(int i) __LIB
{
	int n;

	if (!i)
		return 0;
	for (n = 1; !(i & 1); n++)
		i = (unsigned int)i >> 1;
	return n;
}
#endif
