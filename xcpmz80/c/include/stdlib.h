/* stdlib for SDCC programs under CP/M, in lib/. atof is SDCC's
   own, with its floating point. No div or ldiv: no program here
   uses them. */
#ifndef _CPM_STDLIB_H
#define _CPM_STDLIB_H
#include <_cconv.h>

#include <stddef.h>

#define RAND_MAX	32767
#define EXIT_SUCCESS	0
#define EXIT_FAILURE	1

void *malloc(size_t n) __LIB;
void *calloc(size_t n, size_t size) __LIB;
void *realloc(void *p, size_t n) __LIB;
void free(void *p) __LIB;
size_t __heapfree(void) __LIB;

void exit(int code) __LIB;
void _exit(int code) __LIB;
void abort(void) __LIB;
int atexit(void (*fn)(void)) __LIB;
char *getenv(const char *name) __LIB;
int system(const char *cmd) __LIB;

int abs(int n) __LIB;
long labs(long n) __LIB;
int atoi(const char *s) __LIB;
long atol(const char *s) __LIB;
float atof(const char *s) __LIB;
long strtol(const char *s, char **end, int base) __LIB;
unsigned long strtoul(const char *s, char **end, int base) __LIB;
char *itoa(int v, char *buf, int base) __LIB;
char *utoa(unsigned int v, char *buf, int base) __LIB;
char *ltoa(long v, char *buf, int base) __LIB;
char *ultoa(unsigned long v, char *buf, int base) __LIB;

int rand(void) __LIB;
void srand(unsigned int seed) __LIB;
long random(void) __LIB;
void srandom(unsigned int seed) __LIB;

void qsort(void *base, size_t n, size_t size,
	int (*cmp)(const void *, const void *)) __LIB;
void *bsearch(const void *key, const void *base, size_t n, size_t size,
	int (*cmp)(const void *, const void *)) __LIB;

#endif
