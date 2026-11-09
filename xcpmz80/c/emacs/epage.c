/*
 * EMACS's side of the page module (../page/page.h): a file bigger
 * than the memory is edited through a window of its lines. One buffer at
 * a time is paged, pgbp. Its lines carry the tag of their part in l_pg.
 * Moves, searches and jumps slide the window, the editing marks the part
 * changed, and a save writes the whole file through the module.
 */
#include        <stdio.h>
#include	"estruct.h"
#include        "edef.h"
#include	"../page/page.h"

#define RESERVE	1536		/* left free for the editing	*/

BUFFER	*pgbp;			/* the paged buffer, or NULL	*/
static LINE *anchor;		/* new lines go in before it	*/
static char marklost;		/* a mark was in a line dropped	*/

/* ---- The lines, for the module ---- */

void *ed_end(unsigned char down) PG_CC
{
	register LINE *h = pgbp->b_linep;
	register LINE *lp = down ? lback(h) : lforw(h);

	return lp == h ? NULL : lp;
}

void *ed_step(void *l, unsigned char down) PG_CC
{
	register LINE *lp = down ? lforw((LINE *)l) : lback((LINE *)l);

	return lp == pgbp->b_linep ? NULL : lp;
}

unsigned char ed_tag(void *l) PG_CC
{
	return ((LINE *)l)->l_pg;
}

char *ed_text(void *l, unsigned int *n) PG_CC
{
	*n = llength((LINE *)l);
	return ((LINE *)l)->l_text;
}

void ed_begin(unsigned char down) PG_CC
{
	anchor = down ? pgbp->b_linep : lforw(pgbp->b_linep);
}

unsigned int ed_add(char *s, unsigned int n, unsigned char tag) PG_CC
{
	register LINE *lp;
	register int size;

	size = (n + 7) & ~7;		/* as lalloc, without its message */
	if (size == 0)
		size = 8;
	if ((lp = (LINE *) malloc(sizeof(LINE) + size)) == NULL)
		return 0;
	lp->l_size = size;
	lp->l_used = n;
	lp->l_pg = tag;
	memcpy(lp->l_text, s, n);
	lp->l_fp = anchor;
	lp->l_bp = lback(anchor);
	lback(anchor)->l_fp = lp;
	anchor->l_bp = lp;
	return sizeof(LINE) + size + 2;
}

/* As lfree, but dot moves toward the window, and the mark is dropped */
void ed_drop(void *l, unsigned char down) PG_CC
{
	register LINE *lp = l;
	register LINE *to = down ? lback(lp) : lforw(lp);
	register WINDOW *wp;

	for (wp = wheadp; wp != NULL; wp = wp->w_wndp) {
		if (wp->w_bufp != pgbp)
			continue;
		if (wp->w_linep == lp) {
			wp->w_linep = to;
			wp->w_flag |= WFHARD;
		}
		if (wp->w_dotp == lp) {
			wp->w_dotp = to;
			wp->w_doto = 0;
			wp->w_flag |= WFHARD;
		}
		if (wp->w_markp == lp) {
			wp->w_markp = NULL;
			marklost = TRUE;
		}
	}
	if (pgbp->b_nwnd == 0) {
		if (pgbp->b_dotp == lp) {
			pgbp->b_dotp = to;
			pgbp->b_doto = 0;
		}
		if (pgbp->b_markp == lp) {
			pgbp->b_markp = NULL;
			marklost = TRUE;
		}
	}
	lback(lp)->l_fp = lforw(lp);
	lforw(lp)->l_bp = lback(lp);
	free((char *) lp);
}

/* ---- The editor's calls ---- */

static unsigned int slides;	/* the window slid, so many times	*/
static unsigned int fromline;	/* where a search started		*/
static int fromoff;
static unsigned int fromslides;

/* what went wrong, or the mark dropped */
static void pgdone(void)
{
	if (pg_err)
		mlwrite("[%s]", pg_err);
	else if (marklost)
		mlwrite("[Mark dropped, the window moved]");
	marklost = FALSE;
	pg_err = NULL;
}

/* The file read into bp through the window, if it is there and no other
   buffer is paged. TRUE if it was, with the lines read in nline */
int pgopen(BUFFER *bp, char *fname, int *nline)
{
	register LINE *lp;
	unsigned int b;

	if (pgbp != NULL)
		return FALSE;
	b = __heapfree();
	if (b < RESERVE + 2048)
		return FALSE;
	if (!pg_open(fname, b - RESERVE))
		return FALSE;
	pgbp = bp;
	pg_rows = term.t_nrow;
	pg_goto(0);
	pgdone();
	*nline = 0;
	for (lp = lforw(bp->b_linep); lp != bp->b_linep; lp = lforw(lp))
		++*nline;
	if (pg_na == 0 && pg_nb == 0)
		pgclose();		/* all of it fits: an ordinary buffer */
	return TRUE;
}

void pgclose(void)
{
	if (pgbp != NULL)
		pg_close();
	pgbp = NULL;
}

/* the tag for a new line next to lp, or lp's when it is the header */
int pgtag(LINE *lp)
{
	if (lp != curbp->b_linep)
		return lp->l_pg;
	if (lback(lp) != lp)
		return lback(lp)->l_pg;
	return curbp == pgbp ? pg_newtag() : 0;
}

/* lp, or the line before the header, was changed */
void pgtouch(LINE *lp)
{
	if (curbp == pgbp)
		pg_touch(pgtag(lp));
}

/* a line not the header to keep, near lp */
static LINE *keeper(LINE *lp)
{
	if (lp == pgbp->b_linep)
		lp = lback(lp);
	return lp == pgbp->b_linep ? NULL : lp;
}

/* lp is the last line of the window, or the first: slide it, TRUE if
   there are lines after it, or before it, now */
static int slide(int down, LINE *lp)
{
	register int s;

	s = pg_slide(down, keeper(lp));
	slides += s;
	pgdone();
	return s;
}

int pgnext(LINE *lp)
{
	if (curbp != pgbp || pg_nb == 0 || lforw(lp) != curbp->b_linep)
		return FALSE;
	return slide(1, lp);
}

int pgprev(LINE *lp)
{
	if (curbp != pgbp || pg_na == 0 || lback(lp) != curbp->b_linep)
		return FALSE;
	return slide(0, lp);
}

/* A search starts: where dot is. It failed: dot back there, if the
   window slid */
void pgfrom(void)
{
	if (curbp != pgbp)
		return;
	fromline = pgline();
	fromoff = curwp->w_doto;
	fromslides = slides;
}

void pgback(void)
{
	if (curbp != pgbp || fromslides == slides)
		return;
	pggoto(fromline);
	curwp->w_doto = fromoff;
}

/* Before the screen is drawn: a screen of lines on each side of dot,
   when the file has them */
void pgcheck(void)
{
	register LINE *lp;
	register LINE *h;
	register int i;

	if (curbp != pgbp)
		return;
	h = curbp->b_linep;
	if (curwp->w_dotp == h && pg_nb != 0) {
		/* the end of the window is not the end of the file */
		lp = lback(h);
		slide(1, lp);
		if (lp == h)
			lp = lforw(h);
		else
			lp = lforw(lp);
		curwp->w_dotp = lp;
		curwp->w_doto = 0;
		curwp->w_flag |= WFHARD;
	}
	for (;;) {
		for (i = 0, lp = curwp->w_dotp; i < term.t_nrow && lp != h; i++)
			lp = lforw(lp);
		if (lp != h || pg_nb == 0 || !slide(1, curwp->w_dotp))
			break;
	}
	for (;;) {
		for (i = 0, lp = curwp->w_dotp; i < term.t_nrow && lback(lp) != h; i++)
			lp = lback(lp);
		if (lback(lp) != h || pg_na == 0 || !slide(0, curwp->w_dotp))
			break;
	}
}

/* dot's line in the file */
unsigned int pgline(void)
{
	register LINE *lp;
	register unsigned int n;

	n = pg_above();
	for (lp = lforw(curbp->b_linep); lp != curwp->w_dotp && lp != curbp->b_linep;
	    lp = lforw(lp))
		++n;
	return n;
}

/* The window loaded at line n of the file, 0 the first, and dot there,
   or at the end when n is past it */
void pggoto(unsigned int n)
{
	register LINE *lp;

	lp = pg_goto(n);
	pgdone();
	curwp->w_linep = lp;
	if (lp == NULL) {		/* the end: the screen reframed on it */
		lp = curbp->b_linep;
		curwp->w_linep = lforw(lp);
	}
	curwp->w_dotp = lp;
	curwp->w_doto = 0;
	curwp->w_flag |= WFHARD;
}

/* lalloc found no memory: a part away from dot out of the window */
int pgfree(void)
{
	if (curbp != pgbp || curwp->w_bufp != pgbp)
		return FALSE;
	return pg_free(keeper(curwp->w_dotp));
}

/* The paged buffer written to fn, its lines, or -1 */
long pgsave(char *fn)
{
	long n;

	n = pg_save(fn, 0);
	pgdone();
	return n;
}
