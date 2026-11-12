/*
 * format_line() 
 *
 * Return a pointer to a string buffer containing a formated screen line.
 *
 * By G. R. (Fred) Walter    watmath!grwalter 
 */

#include "stevie.h"

char           *tab_expand = "                ";

#ifdef MAX80
/*
 * Added for the MAX-80: the run of printable characters, 20h to 7Eh,
 * copied in Z80 code, from fl_s to fl_d, at most fl_n of them (1 to
 * 255), both moved on. It gives back the count. SDCC's loop takes
 * some 400 T-states a character, this one 70, and every scroll
 * formats a line or two.
 */
static char    *fl_s;
static char    *fl_d;
static unsigned char fl_n;

static unsigned char
fl_run(void) __naked
{
    __asm
	ld	hl,(_fl_s)
	ld	de,(_fl_d)
	ld	a,(_fl_n)
	ld	b,a
	ld	c,#0
1$:	ld	a,(hl)
	cp	#0x20
	jr	c,2$
	cp	#0x7f
	jr	nc,2$
	ld	(de),a
	inc	hl
	inc	de
	inc	c
	djnz	1$
2$:	ld	(_fl_s),hl
	ld	(_fl_d),de
	ld	a,c
	ld	l,a
	ret
    __endasm;
}
#endif

char           *
format_line(char *ptr, int *len)
{
    register char  *dest;
    register char   c;
    register int    col;
    char           *p_extra;
    int             n_extra;
    int             coff;	/* column offset */

    dest = IObuff;
    col = 0;

    coff = NU_ON ? 8 : 0;

    n_extra = 0;
    p_extra = NULL;

    for (;;) {
	if (n_extra > 0) {
	    c = *p_extra++;
	    n_extra--;
	} else {
	    c = *ptr++;
#ifdef MAX80
	    while (c >= 32 && c < 127) {
		int             room = IOSIZE - col;

		fl_s = ptr - 1;
		fl_d = dest;
		fl_n = room > 255 ? 255 : room;
		col += fl_run();
		ptr = fl_s;
		dest = fl_d;
		if (col >= IOSIZE)
		    goto DONE_FORMAT_LINE;
		c = *ptr++;
	    }
#else
	    while (c >= 32 && c < 127) {
		*dest++ = c;
		col++;
		if (col >= IOSIZE)
		    goto DONE_FORMAT_LINE;
		c = *ptr++;
	    }
#endif
	    if (!P(P_LS)) {
		if (c == TAB) {
		    /* tab amount depends on current column */
		    p_extra = tab_expand;
		    n_extra = (P(P_TS) - 1) - (col - coff) % P(P_TS);
		    c = ' ';
		    goto I_HATE_GOTOS;
		} else if (c == NUL) {
		    break;
		}
	    } else if (c == NUL) {
		*dest++ = '$';
		col++;
		break;
	    }
	    if ((n_extra = CH_SIZE(c) - 1) > 0) {
		p_extra = CH_STR(c);
		c = *p_extra++;
	    }
	}
I_HATE_GOTOS:
	*dest++ = c;
	col++;
	if (col >= IOSIZE)
	    break;
    }
DONE_FORMAT_LINE:
    if (col >= IOSIZE) {
	dest--;
	col--;
    }
    *dest = NUL;

    if (len != NULL)
	*len = col + coff;

    return (IObuff);
}
