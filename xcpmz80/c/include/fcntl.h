/* open() for SDCC programs under CP/M, in lib/unistd.c */
#ifndef _CPM_FCNTL_H
#define _CPM_FCNTL_H
#include <_cconv.h>

#define O_RDONLY	0
#define O_WRONLY	1
#define O_RDWR		2
#define O_ACCMODE	3
#define O_CREAT		0x10
#define O_TRUNC		0x20
#define O_APPEND	0x40
#define O_EXCL		0x80
#define O_BINARY	0
#define O_TEXT		0x100

int open(const char *name, int flags, ...) __LIB;
int creat(const char *name, int mode) __LIB;

#endif
