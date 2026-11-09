/*
 * STEVIE - Simply Try this Editor for VI Enthusiasts
 *
 *
 * Code Contributions By : Jawaid Bayzar	  bazyar@cs.uiuc.edu
 *			   Tim Thompson           twitch!tjt
 *                         Tony Andrews           onecom!wldrdg!tony 
 *                         G. R. (Fred) Walter    watmath!grwalter 
 */

#include "stevie.h"

/*
 * Altered for xcpmz80: readfile() and writeit() read and write with
 * the C library's fread() and fputs() in place of GS/OS's calls and the
 * 65816 assembly. Bit 7 and nulls are dropped as before, but not
 * counted. A file that does not fit in memory, or with a line too long,
 * is read as far as it goes, and its name kept in Partial, so that
 * writeit() will not write the part over the whole file. A file read into
 * the text with :r goes in whole or not at all, and readfile()
 * gives 2 when it did not.
 */

char           *Partial = NULL;	/* the file read in part, or NULL */

/* left free while a file is read, for the editing after */
#define RESERVE 1024

void
filemess(char *s)
{
    sprintf(IObuff, "\"%s\" %s", ((Filename == NULL) ? "" : Filename), s);
    msg(IObuff);
}

void
renum(void) VI_ASM
{
    LPtr           *p;
    lineno_t        l = 0;

    for (p = Filemem; p != NULL; p = nextline(p), l += LINEINC)
	p->linep->num = l;

    Fileend->linep->num = LASTLINE;
}

bool_t
readfile(char *fname, LPtr *fromp, bool_t nochangename)
    /* nochangename: if TRUE, don't change the Filename */
{
    FILE           *f;
    LINE           *curr;
    int             c;
    unsigned        IObuffsize = 0;
    unsigned long   nchars = 0;
    unsigned int    linecnt = 0;
    bool_t          wasempty = bufempty();
    bool_t          incomplete = FALSE;	/* was the last line incomplete? */
    bool_t          toolong = FALSE;	/* a line was too long */
    bool_t          nomem = FALSE;	/* out of memory */
    char           *reserve;
    unsigned char   rbuf[128];
    unsigned        rlen = 0, rnext = 0;

    curr = fromp->linep;

    if (!nochangename) {
	Filename = strsave(fname);
	Partial = NULL;
	pg_close();		/* the work file of the last one goes */
    }

    f = fopen(fname, "r");
    if (f == NULL) {
	s_refresh(NOT_VALID);
	filemess("");
	return TRUE;
    }
    S_NOT_VALID;
    reserve = malloc(RESERVE);
    AllocQuiet = TRUE;

    for (;;) {
	if (rnext == rlen) {	/* a record at a time, one library call */
	    rlen = fread(rbuf, 1, sizeof rbuf, f);
	    rnext = 0;
	}
	c = (rnext < rlen) ? rbuf[rnext++] : EOF;
	if (c == EOF) {
	    if (IObuffsize == 0)/* normal loop termination */
		break;

	    /*
	     * If we get EOF in the middle of a line, note the fact and
	     * complete the line ourselves.
	     */
	    incomplete = TRUE;
	    c = NL;
	}
	c &= 0x7f;
	/*
	 * If we reached the end of the line, OR we ran out of space for it,
	 * then process the complete line.
	 */
	if (c == NL || IObuffsize == (IOSIZE - 1)) {
	    LINE           *lp;

	    if (c != NL) {
		toolong = TRUE;
		break;
	    }
	    IObuff[IObuffsize++] = NUL;
	    lp = newline(IObuffsize);
	    if (lp == NULL) {
		nomem = TRUE;
		break;
	    }
	    strcpy(lp->s, IObuff);

	    curr->next->prev = lp;	/* new line to next one */
	    lp->next = curr->next;

	    curr->next = lp;	/* new line to prior one */
	    lp->prev = curr;

	    curr = lp;		/* new line becomes current */
	    IObuffsize = 0;
	    linecnt++;
	    if (incomplete)
		break;
	} else if (c != NUL) {	/* nulls are dropped */
	    IObuff[IObuffsize++] = (char) c;	/* normal character */
	}

	nchars++;
    }

    AllocQuiet = FALSE;
    fclose(f);
    if (reserve != NULL)
	free(reserve);

#ifdef MAX80
    /* it does not fit: read through a window */
    if (nomem && wasempty && !nochangename && pgopen(fname)) {
	s_refresh(NOT_VALID);
	sprintf(IObuff, "\"%s\" %u lines, the rest paged from disk",
		fname, cntllines(Filemem, Fileend) - 1);
	msg(IObuff);
	return FALSE;
    }
#endif

    /* :r of what does not fit: the lines come out again */
    if (nochangename && (toolong || nomem)) {
	while (curr != fromp->linep) {
	    LINE           *lp = curr->prev;

	    lp->next = curr->next;
	    curr->next->prev = lp;
	    FREE_S(curr);
	    free((char *) curr);
	    curr = lp;
	}
	s_refresh(NOT_VALID);
	sprintf(IObuff, "\"%s\" %s, not read",
		fname, toolong ? "Line too long" : "Out of memory");
	emsg(IObuff);
	return 2;
    }

    /*
     * If the buffer was empty when we started, we have to go back and remove
     * the "dummy" line at Filemem and patch up the ptrs.
     */
    if (wasempty && linecnt != 0) {
	LINE           *dummy = Filemem->linep;	/* dummy line ptr */

	Filemem->linep = Filemem->linep->next;
	Filemem->linep->prev = Filetop->linep;
	Filetop->linep->next = Filemem->linep;

	Curschar->linep = Filemem->linep;
	Topchar->linep = Filemem->linep;

	FREE_S(dummy);		/* free string space */
	free((char *) dummy);	/* free LINE struct */
    }
    renum();
    s_refresh(NOT_VALID);

    if (toolong || nomem) {
	Partial = strsave(fname);
	sprintf(IObuff, "\"%s\" %s, %u lines read, not to be written",
		fname, toolong ? "Line too long" : "Out of memory", linecnt);
	emsg(IObuff);
	return FALSE;
    }

    sprintf(IObuff, "\"%s\" %s%u line%s, %lu character%s",
	    fname,
	    incomplete ? "[Incomplete last line] " : "",
	    linecnt, (linecnt > 1) ? "s" : "",
	    nchars, (nchars > 1) ? "s" : "");

    msg(IObuff);

    return FALSE;
}

/*
 * writeit - write to file 'fname' lines 'start' through 'end'
 *
 * If either 'start' or 'end' contain null line pointers, the default is to use
 * the start or end of the file respectively.
 */
bool_t
writeit(char *fname, LPtr *start, LPtr *end)
{
    FILE           *f;
    char           *s;
    long            nchars;
    int             lines;
    LPtr           *p;
    bool_t          bad;

    if (Partial != NULL && strcasecmp(fname, Partial) == 0) {
	emsg("Only part of the file was read, not written (:q! quits)");
	return FALSE;
    }
#ifdef MAX80
    /* the whole of a paged file, through the page module */
    if (pg_on && (start == NULL || start->linep == NULL))
	return pgsave(fname, P(P_BK));
#endif
    sprintf(IObuff, "\"%s\"", fname);
    msg(IObuff);

    /*
     * Form the backup file name - change foo.* to foo.bak - use IObuff to
     * hold the backup file name
     */
    strcpy(IObuff, fname);
    for (s = IObuff; *s && *s != '.'; s++);
    *s = NUL;
    strcat(IObuff, ".bak");

    /*
     * Delete any existing backup and move the current version to the backup.
     * For safety, we don't remove the backup until the write has finished
     * successfully. And if the 'backup' option is set, leave it around.
     */
    remove(IObuff);
    rename(fname, IObuff);

    f = P(P_CR) ? fopen(fname, "w") : fopenb(fname, "w");
    if (f == NULL) {
	emsg("Can't open file for writing!");
	return FALSE;
    }
    /*
     * If we were given a bound, start there. Otherwise just start at the
     * beginning of the file.
     */
    if (start == NULL || start->linep == NULL)
	p = Filemem;
    else
	p = start;

    lines = 0;
    nchars = 0;

    do {
	fputs(p->linep->s, f);
	putc('\n', f);
	lines++;
	nchars += strlen(p->linep->s) + 1;
	/*
	 * If we were given an upper bound, and we just did that line, then
	 * bag it now.
	 */
	if (end != NULL && end->linep != NULL) {
	    if (end->linep == p->linep)
		break;
	}
    } while ((p = nextline(p)) != NULL);
    bad = ferror(f);
    if (fclose(f) != 0)
	bad = TRUE;
    if (bad) {
	emsg("Write error, the old file is in the .BAK file");
	return FALSE;
    }

    /*
     * Remove the backup unless they want it left around
     */
    if (!P(P_BK))
	remove(IObuff);

    sprintf(IObuff, "\"%s\" %d line%s, %ld character%s", fname,
	    lines, (lines > 1) ? "s" : "",
	    nchars, (nchars > 1) ? "s" : "");
    msg(IObuff);
    UNCHANGED;

    return TRUE;
}

