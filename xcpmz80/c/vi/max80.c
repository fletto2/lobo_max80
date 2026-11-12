/*
 * STEVIE - Simply Try this Editor for VI Enthusiasts
 *
 * Lobo MAX-80 system-dependent code, under xcpmz80, in place of
 * gsos.c. The console is read with BDOS function 6, with no echo and no
 * ^C or ^S checks, and written by the BIOS's CONOUT, as function 6 does.
 * The screen codes are in term.h. The arrow keys give 1Ch to 1Fh: up,
 * down, left and right.
 */

#include "stevie.h"
#include <cpm.h>
#include <unistd.h>

#define OBUFSIZE 256

static char     outbuf[OBUFSIZE];
static int      indbuf = 0;

/*
 * The buffer to the screen by the BIOS's CONOUT, the jump table's entry
 * 9 bytes past WBOOT, which 0001h points at. It is what function 6 ends
 * in, without the BDOS's way in and out for every byte: a scroll's
 * redraw takes a third of the time. CONOUT keeps IX, as xcpmz80's does.
 */
static void
biosout(void) __naked
{
    __asm
	ld	de,(_indbuf)
	ld	a,d
	or	e
	ret	z
	push	ix
	ld	ix,(1)
	ld	bc,#9
	add	ix,bc
	ld	hl,#_outbuf
1$:	push	hl
	push	de
	ld	c,(hl)
	call	2$
	pop	de
	pop	hl
	inc	hl
	dec	de
	ld	a,d
	or	e
	jr	nz,1$
	pop	ix
	ret
2$:	jp	(ix)
    __endasm;
}

void
flushbuf(void)
{
    biosout();
    indbuf = 0;
}

static void
toutchar(char c)
{
    outbuf[indbuf++] = c;
    if (indbuf == OBUFSIZE)
	flushbuf();
}

/* '\n' goes out as CR LF */
int
outchar(char c)
{
    if (c == '\n')
	toutchar('\r');
    toutchar(c);
    return c;
}

void
outstr(char *s)
{
    while (*s)
	outchar(*s++);
}

/* a terminal sequence, as it is */
void
toutstr(char *s)
{
    while (*s)
	toutchar(*s++);
}

int
inchar(void)
{
    int             c;

    flushbuf();
    while ((c = bdos(6, 0xFF) & 0xFF) == 0)
	;
    switch (c) {
      case 0x1c:
	return K_UARROW;
      case 0x1d:
	return K_DARROW;
      case 0x1e:
	return K_LARROW;
      case 0x1f:
	return K_RARROW;
      case 0x7f:
	return BS;
    }
    return c & 0x7f;
}

void
beep(void)
{
    outchar(7);
    flushbuf();
}

void
windinit(void)
{
    Columns = 80;
    P(P_LI) = Rows = 24;
}

void
windexit(int r)
{
    toutstr(T_TP);
    toutstr(T_CV);
    flushbuf();
    exit(r);
}

/* ESC = row+20h col+20h */
void
windgoto(int r, int c)
{
    toutchar(ESC);
    toutchar('=');
    toutchar((char) (r + 0x20));
    toutchar((char) (c + 0x20));
}

void
delay(void)
{
    flushbuf();
    sleep(1);
}

/* no job control under CP/M */
void
nosuspend(void)
{
}

void
dosuspend(void)
{
}

FILE *
fopenb(char *fname, char *mode)
{
    char            modestr[10];

    sprintf(modestr, "%sb", mode);
    return fopen(fname, modestr);
}
