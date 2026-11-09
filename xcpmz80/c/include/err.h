/* err and warn for SDCC programs under CP/M, in lib/err.c: the
   message to stderr, err then ends the program */
#ifndef _CPM_ERR_H
#define _CPM_ERR_H
#include <_cconv.h>

void err(int code, const char *fmt, ...) __LIB;
void errx(int code, const char *fmt, ...) __LIB;
void warn(const char *fmt, ...) __LIB;
void warnx(const char *fmt, ...) __LIB;

#endif
