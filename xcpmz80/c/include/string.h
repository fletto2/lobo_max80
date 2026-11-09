/* string for SDCC programs under CP/M. The functions are
   the library's own, in lib/*.s and lib/string.c. */
#ifndef _CPM_STRING_H
#define _CPM_STRING_H
#include <_cconv.h>

#include <stddef.h>

void *memcpy(void *d, const void *s, size_t n) __LIB;
void *memmove(void *d, const void *s, size_t n) __LIB;
void *memset(void *d, int c, size_t n) __LIB;
int memcmp(const void *a, const void *b, size_t n) __LIB;
void *memchr(const void *s, int c, size_t n) __LIB;
size_t strlen(const char *s) __LIB;
char *strcpy(char *d, const char *s) __LIB;
char *strncpy(char *d, const char *s, size_t n) __LIB;
char *strcat(char *d, const char *s) __LIB;
char *strncat(char *d, const char *s, size_t n) __LIB;
int strcmp(const char *a, const char *b) __LIB;
int strncmp(const char *a, const char *b, size_t n) __LIB;
char *strchr(const char *s, int c) __LIB;
char *strrchr(const char *s, int c) __LIB;
size_t strspn(const char *s, const char *set) __LIB;
size_t strcspn(const char *s, const char *set) __LIB;
char *strpbrk(const char *s, const char *set) __LIB;
char *strstr(const char *s, const char *sub) __LIB;
char *strtok(char *s, const char *delim) __LIB;
size_t strxfrm(char *d, const char *s, size_t n) __LIB;

/* lib/string.c */
int strcoll(const char *a, const char *b) __LIB;
char *strerror(int err) __LIB;
char *strdup(const char *s) __LIB;
char *strndup(const char *s, size_t n) __LIB;
size_t strnlen(const char *s, size_t n) __LIB;
char *stpcpy(char *d, const char *s) __LIB;
char *stpncpy(char *d, const char *s, size_t n) __LIB;
size_t strlcpy(char *d, const char *s, size_t n) __LIB;
size_t strlcat(char *d, const char *s, size_t n) __LIB;
char *strsep(char **sp, const char *delim) __LIB;
char *strtok_r(char *s, const char *delim, char **save) __LIB;
char *strchrnul(const char *s, int c) __LIB;
char *strcasestr(const char *s, const char *sub) __LIB;
char *strupr(char *s) __LIB;
char *strlwr(char *s) __LIB;
char *strrev(char *s) __LIB;
void *memccpy(void *d, const void *s, int c, size_t n) __LIB;
void *memrchr(const void *s, int c, size_t n) __LIB;
void *mempcpy(void *d, const void *s, size_t n) __LIB;
int strcasecmp(const char *a, const char *b) __LIB;
int strncasecmp(const char *a, const char *b, size_t n) __LIB;

#endif
