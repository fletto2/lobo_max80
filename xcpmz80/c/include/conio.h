/* The console without stdio, for SDCC programs under CP/M, in
   lib/conio.c: keys one at a time with no echo, as an editor wants. */
#ifndef _CPM_CONIO_H
#define _CPM_CONIO_H
#include <_cconv.h>

int kbhit(void) __LIB; /* nonzero when a key is waiting */
int getch(void) __LIB; /* a key, waiting for it, no echo */
int getche(void) __LIB; /* the same, echoed */
int putch(int c) __LIB; /* a character as it is, no CR added */
int cputs(const char *s) __LIB;
int cprintf(const char *fmt, ...) __LIB;
char *cgets(char *buf) __LIB; /* buf[0] = room, line from buf+2 */

#endif
