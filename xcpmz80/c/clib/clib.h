/* The C library resident in B2: what its own parts share */
#ifndef _CLIB_H
#define _CLIB_H
#include <_cconv.h>

#define CLIB_VERSION	1
#define CLIB_STRLEN	80	/* the program's buffer for the library's strings */

/* the function table, made by tools/clibgen.py from clib.lst */
struct clibfn {
	void *fn;
	const char *sig;
};

extern unsigned int __clib_res[2];	/* hdr.s: the result, HL then DE */
void __clib_reset(void) __LIB;
void __lcopy(const void *from, void *to, unsigned int n) __LIB;
void __clib_heap(unsigned int start) __LIB;
unsigned int __clib_heaptop(void) __LIB; /* the heap's end so far */

/* the program's memory, at any address */
void __uget(void *d, unsigned int us, unsigned int n) __LIB;
void __uput(unsigned int ud, const void *s, unsigned int n) __LIB;
unsigned int __ustrlen(unsigned int us) __LIB;
unsigned int __ugetw(unsigned int up) __LIB;
void __uputw(unsigned int up, unsigned int v) __LIB;
void __umemset(unsigned int ud, unsigned char c, unsigned int n) __LIB;
unsigned int __clib_ustr(void) __LIB; /* the program's string buffer */

#endif
