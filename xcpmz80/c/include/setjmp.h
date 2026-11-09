/* setjmp for SDCC programs under CP/M, in lib/setjmp.s */
#ifndef _CPM_SETJMP_H
#define _CPM_SETJMP_H
#include <_cconv.h>

typedef unsigned char jmp_buf[6];
int setjmp(jmp_buf b) __LIB;
void longjmp(jmp_buf b, int v) __LIB;

#endif
