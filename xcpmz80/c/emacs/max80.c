/*
 * The routines in this file provide support for the Lobo MAX-80's
 * screen, as Lobo's BIOS and xcpmz80 drive it: ESC = row+20h col+20h
 * moves the cursor, ESC T erases to the end of the line, ESC Y to the
 * end of the screen. Under xcpmz80 ESC ) and ESC ( pick the second
 * style of the font and back, used for the mode line. Made from the
 * VT52 driver of MicroEMACS 3.6 for xcpmz80. The serial I/O
 * services are provided by routines in "termio.c".
 */
#define	termdef	1			/* don't define "term" external */

#include        <stdio.h>
#include        "estruct.h"
#include	"edef.h"

#if     MAX80

#define NROW    24                      /* Screen size.                 */
#define NCOL    80
#define	MARGIN	8			/* size of minimim margin and	*/
#define	SCRSIZ	64			/* scroll size for extended lines */
#define BIAS    0x20                    /* Origin 0 coordinate bias.    */
#define ESC     0x1B                    /* ESC character.               */
#define BEL     0x07                    /* ascii bell character         */


/*
 * Dispatch table. All the
 * hard fields just point into the
 * terminal I/O code.
 */
TERM    term    = {
        NROW-1,
        NCOL,
	MARGIN,
	SCRSIZ,
        &m80open,
        &ttclose,
        &ttgetc,
        &ttputc,
        &ttflush,
        &m80move,
        &m80eeol,
        &m80eeop,
        &m80beep,
        &m80rev
};

int m80move(int row, int col)
{
        ttputc(ESC);
        ttputc('=');
        ttputc(row+BIAS);
        ttputc(col+BIAS);
        return (TRUE);
}

int m80eeol(void)
{
        ttputc(ESC);
        ttputc('T');
        return (TRUE);
}

int m80eeop(void)
{
        ttputc(ESC);
        ttputc('Y');
        return (TRUE);
}

int m80rev(int status)
	/* set the reverse video state */
	/* TRUE = reverse video, FALSE = normal video */
{
	/* the second style of the font stands in for reverse video */
	ttputc(ESC);
	ttputc(status ? ')' : '(');
	return (TRUE);
}

int m80beep(void)
{
        ttputc(BEL);
        ttflush();
        return (TRUE);
}

int m80open(void)
{
	revexist = TRUE;
        ttopen();
        return (TRUE);
}

#endif
