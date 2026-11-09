/* strings for SDCC programs under CP/M, in lib/string.c */
#ifndef _CPM_STRINGS_H
#define _CPM_STRINGS_H
#include <_cconv.h>

#include <string.h>

void bzero(void *d, size_t n) __LIB;
void bcopy(const void *s, void *d, size_t n) __LIB;
int bcmp(const void *a, const void *b, size_t n) __LIB;
char *index(const char *s, int c) __LIB;
char *rindex(const char *s, int c) __LIB;
int ffs(int i) __LIB;

#endif
