/* ctype for SDCC programs under CP/M, in lib/ctype.c, ASCII */
#ifndef _CPM_CTYPE_H
#define _CPM_CTYPE_H
#include <_cconv.h>

int isalnum(int c) __LIB;
int isalpha(int c) __LIB;
int isascii(int c) __LIB;
int isblank(int c) __LIB;
int iscntrl(int c) __LIB;
int isdigit(int c) __LIB;
int isgraph(int c) __LIB;
int islower(int c) __LIB;
int isprint(int c) __LIB;
int ispunct(int c) __LIB;
int isspace(int c) __LIB;
int isupper(int c) __LIB;
int isxdigit(int c) __LIB;
int tolower(int c) __LIB;
int toupper(int c) __LIB;
int toascii(int c) __LIB;

#endif
