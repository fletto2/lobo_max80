/*
 * Lobo MAX-80 machine-dependent routines, under xcpmz80, in place
 * of gsos.h.
 */

#include <unistd.h>
/*
 */

void flushbuf(void);

int  inchar(void);
int  outchar(char);
void outstr(char *);
void toutstr(char *);
void beep(void);
void windinit(void);
void windexit(int);
void windgoto(int,int);
void delay(void);
void nosuspend(void);
void dosuspend(void);
FILE *fopenb(char *, char *);
