/* assert for SDCC programs under CP/M, in lib/assert.c */
#ifndef _CPM_ASSERT_H
#define _CPM_ASSERT_H
#include <_cconv.h>

void __assert(const char *expr, const char *file, int line) __LIB;
#endif

#undef assert
#ifdef NDEBUG
#define assert(e) ((void)0)
#else
#define assert(e) ((e) ? (void)0 : __assert(#e, __FILE__, __LINE__))
#endif
