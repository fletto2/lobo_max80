/* Inside the CP/M C library: what its modules share. Each module
 * is its own object in cpm.lib, so a program links only what it calls. */
#ifndef _CPMINT_H
#define _CPMINT_H
#include <_cconv.h>

#include <stdio.h>
#include <stdarg.h>

#define F_USED	0x01
#define F_READ	0x02
#define F_WRITE	0x04
#define F_TEXT	0x08
#define F_EOF	0x10
#define F_ERR	0x20
#define F_DIRTY	0x40
#define F_CON	0x80

struct _FILE {
	unsigned char flags;
	int unget;		/* a byte given back by ungetc, EOF none */
	unsigned char fcb[36];
	long pos;		/* the byte the next read or write is at */
	long rec;		/* the record in buf, -1 none */
	unsigned char buf[128];
};

extern FILE __files[FOPEN_MAX];
/* The console's three FILEs: only their flags and unget, as nothing
 * reads further into a FILE with F_CON */
struct _con {
	unsigned char flags;
	int unget;
};
extern struct _con __cons[3];
#define CON(i)	((FILE *)&__cons[i])

unsigned int bdos(unsigned char fn, unsigned int de) __LIB;
unsigned char getr(void) __LIB;

/* name to FCB, "B:NAME.EXT", upper case, * as ?s. 0, or -1 for a
 * name CP/M cannot have (no name, a drive past P:). */
int __mkfcb(unsigned char *fcb, const char *name);
int __flushrec(FILE *f);
int __loadrec(FILE *f);
int __getrec(FILE *f);
int __rawput(unsigned char c, FILE *f);
FILE *__fopen(FILE *f, const char *name, const char *mode);
void __closeall(void);
void __coninit(void);
FILE *__fd2file(int fd);
int __conin(void);
void __conout(char c);

/* printf's engine: out is called for each character */
int __vfmt(void (*out)(char, void *), void *arg, const char *fmt, va_list ap);

/* scanf's engine: get gives the next character or EOF, unget one back */
int __vscan(int (*get)(void *), void (*unget)(int, void *), void *arg,
	const char *fmt, va_list ap);

#endif
