/*
 * STEVIE - Simply Try this Editor for VI Enthusiasts
 *
 * Code Contributions By : Tim Thompson           twitch!tjt
 *                         Tony Andrews           onecom!wldrdg!tony 
 *                         G. R. (Fred) Walter    watmath!grwalter 
 */

#include "stevie.h"
#ifdef AMIGA
# include <proto/exec.h>
# include <exec/memory.h>
# define PANIC_FACTOR_CHIP 40000
#endif
#ifdef GSOS
#include <stdlib.h>
#endif

/*
 * Altered for xcpmz80: alloc() says nothing when AllocQuiet is set,
 * as it is while readfile() reads a file until the memory is full.
 */
bool_t          AllocQuiet = FALSE;


/*
 * This file contains various routines dealing with allocation and
 * deallocation of data structures. 
 */

char *alloc(unsigned size)
{
    char           *p;		/* pointer to new storage space */

    p = malloc(size);
#ifdef MAX80
    while (p == (char *) NULL && pgfree())	/* a part of the window out */
	p = malloc(size);
#endif
    if (p == (char *) NULL && !AllocQuiet) {	/* if there is no more room... */
	emsg("alloc() is unable to find memory!");
	sleep(5);
    }
#ifdef AMIGA
    if (AvailMem(MEMF_CHIP) < PANIC_FACTOR_CHIP) {
	free(p);
	p = (char *) NULL;
	emsg("alloc() - not enough CHIP memory!");
	sleep(5);
    }
#endif

    return (p);
}

char *strsave(char *string)
{
    char           *s;

    s = alloc((unsigned) (strlen(string) + 1));
    if (s != (char *) NULL)
	strcpy(s, string);
    return (s);
}

void screenalloc(void)
{
    int             i;

    /*
     * If we're changing the size of the screen, free the old arrays 
     */
    if (LinePointers != (LINE **) NULL)
	free((char *) LinePointers);
    if (LineSizes != (char *) NULL)
	free(LineSizes);

    LinePointers = (LINE **) malloc((unsigned) (Rows * sizeof(LINE *)));
    LineSizes = malloc((unsigned) Rows);
    if (LinePointers == (LINE **) NULL || LineSizes == (char *) NULL) {
	fprintf(stderr, "Unable to allocate screen memory!\n");
	getout(1);
    }
    for (i = 0; i < Rows; i++) {
	LinePointers[i] = (LINE *) NULL;
	LineSizes[i] = (char) 0;
    }
    NumLineSizes = -1;
}

/*
 * Allocate and initialize a new line structure with room for 'nchars'
 * characters. 
 */
LINE *newline(int nchars) VI_ASM
{
    register LINE  *l;

    if (nchars == 0)
	nchars = 1;

#ifdef MAX80
    l = (LINE *) alloc((unsigned) sizeof(LINE) + nchars);
    if (l != (LINE *) NULL) {
	l->s = (char *) (l + 1);
	l->s[0] = NUL;
	l->size = nchars;
	l->tag = 0;			/* new, for the window */
	l->prev = (LINE *) NULL;	/* should be initialized by caller */
	l->next = (LINE *) NULL;
    }
#else
    l = (LINE *) alloc((unsigned) sizeof(LINE));
    if (l != (LINE *) NULL) {
	l->s = alloc((unsigned) nchars);	/* the line is empty */
	if (l->s != (char *) NULL) {
	    l->s[0] = NUL;
	    l->size = nchars;

	    l->prev = (LINE *) NULL;	/* should be initialized by caller */
	    l->next = (LINE *) NULL;
	} else {
	    free((char *) l);
	    l = (LINE *) NULL;
	}
    }
#endif
    return l;
}

#ifdef MAX80
/* free the text of line l, when it is not in the block of l itself */
void
freetext(LINE *l) VI_ASM
{
    if (l->s != (char *) (l + 1))
	free(l->s);
}

/*
 * growbuf(buf, size, need) - make the buffer *buf, of *size bytes, hold
 * need bytes, moving it if it must. FALSE if there is no memory.
 */
bool_t
growbuf(char **buf, unsigned *size, unsigned need)
{
    char           *p;

    if (need <= *size)
	return TRUE;
    need = (need + BUFSTART - 1) & ~(BUFSTART - 1);
    while ((p = realloc(*buf, need)) == NULL)
	if (!pgfree())		/* a part of the window out */
	    return FALSE;
    *buf = p;
    *size = need;
    return TRUE;
}

/* shrinkbuf(buf, size) - give back what an emptied buffer grew to */
void
shrinkbuf(char **buf, unsigned *size)
{
    char           *p;

    if (*size > BUFSTART && (p = realloc(*buf, BUFSTART)) != NULL) {
	*buf = p;
	*size = BUFSTART;
    }
}

#endif
/*
 * filealloc() - construct an initial empty file buffer 
 */
void
filealloc(void) VI_ASM
{
    Filemem->linep = newline(1);
    Filetop->linep = newline(1);
    Fileend->linep = newline(1);
    if (Filemem->linep == (LINE *) NULL ||
	Filetop->linep == (LINE *) NULL ||
	Fileend->linep == (LINE *) NULL) {
	fprintf(stderr, "Unable to allocate file memory!\n");
	getout(1);
    }
    Filemem->index = 0;
    Filetop->index = 0;
    Fileend->index = 0;

    Filetop->linep->prev = (LINE *) NULL;
    Filetop->linep->next = Filemem->linep;	/* connect Filetop to Filemem */
    Filemem->linep->prev = Filetop->linep;

    Filemem->linep->next = Fileend->linep;	/* connect Filemem to Fileend */
    Fileend->linep->prev = Filemem->linep;
    Fileend->linep->next = (LINE *) NULL;

    *Curschar = *Filemem;
    *Topchar = *Filemem;

    Filemem->linep->num = 0;
    Fileend->linep->num = LASTLINE;

    clrall();			/* clear all marks */
}

/*
 * freeall() - free the current buffer 
 *
 * Free all lines in the current buffer. 
 */
void
freeall(void) VI_ASM
{
    LINE           *lp;
    LINE           *xlp;
    int             i;

    for (lp = Filetop->linep; lp != (LINE *) NULL; lp = xlp) {
	if (lp->s != (char *) NULL)
	    FREE_S(lp);
	xlp = lp->next;
	free((char *) lp);
    }

    Curschar->linep = (LINE *) NULL;	/* clear pointers */
    Filemem->linep = (LINE *) NULL;
    Filetop->linep = (LINE *) NULL;
    Fileend->linep = (LINE *) NULL;

    for (i = 0; i < Rows; i++) {/* clear screen information */
	LinePointers[i] = (LINE *) NULL;
	LineSizes[i] = (char) 0;
    }
    NumLineSizes = -1;
}

/*
 * canincrease(n) - returns TRUE if the current line can be increased 'n'
 * bytes 
 *
 * This routine returns immediately if the requested space is available. If not,
 * it attempts to allocate the space and adjust the data structures
 * accordingly. If everything fails it returns FALSE. 
 */
bool_t canincrease(int n)
{
    register int    nsize;
    register char  *s;		/* pointer to new space */

    nsize = strlen(Curschar->linep->s) + 1 + n;	/* size required */

    if (nsize <= Curschar->linep->size)
	return TRUE;

    /*
     * Need to allocate more space for the string. Allow some extra space on
     * the assumption that we may need it soon. This avoids excessive numbers
     * of calls to malloc while entering new text. 
     */
    s = alloc((unsigned) (nsize + SLOP));
    if (s == (char *) NULL) {
	emsg("Can't add anything, file is too big!");
	State = NORMAL;
	return FALSE;
    }
    Curschar->linep->size = nsize + SLOP;
    strcpy(s, Curschar->linep->s);
    FREE_S(Curschar->linep);
    Curschar->linep->s = s;

    return TRUE;
}
