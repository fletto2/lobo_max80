/* A window over a file bigger than memory, for EMACS and VI.
 *
 * The editor keeps a window of whole lines in its own list. The rest of
 * the file is pieces: runs of whole lines in the file or in the work
 * file NAME.$$W, a list above the window and a list below it. The
 * window is loaded in parts of about PG_PARTSZ bytes. Each line carries
 * the tag of its part, and a part changed is written to the work file
 * when it leaves the window. An unchanged part goes back as the piece it
 * came from.
 *
 * The editor gives the module its lines through the ed_ functions, in
 * its glue. "down" is toward the end of the file. */
#ifndef PAGE_H
#define PAGE_H

/* A piece runs from byte o of record r to byte eo of record er, not
   included. eo and o are 0 to 127. */
typedef struct {
	unsigned int r;		/* its first byte's record */
	unsigned char o;	/* and place in it, PG_WORK set in the work file */
	unsigned int er;	/* the record of the byte after its last */
	unsigned char eo;	/* and its place */
	unsigned int nl;	/* lines, PG_UNK while not counted */
} PIECE;

#define PG_WORK		0x80
#define PG_UNK		0xFFFFu

#ifndef PG_NP
#define PG_NP		48	/* pieces, above and below */
#endif
#ifndef PG_PARTSZ
#define PG_PARTSZ	512	/* bytes of the file a part */
#endif
#ifndef PG_NPART
#define PG_NPART	16	/* parts in the window */
#endif
#define PG_LINE		256	/* the longest line, a longer one is split */

typedef struct {
	PIECE o;		/* where it came from */
	unsigned int cost;	/* the memory its lines took */
	unsigned char tag;	/* the tag of its lines, 1 to 255 */
	unsigned char dirty;	/* changed since it was loaded */
} PART;

/* above: pg_tab[0] to pg_tab[pg_na - 1], top first. below:
   pg_tab[PG_NP - pg_nb] to pg_tab[PG_NP - 1], the nearest first */
extern PIECE pg_tab[PG_NP];
extern PART pg_part[PG_NPART];	/* the window's parts, top first */
extern unsigned char pg_na, pg_nb, pg_np;
extern unsigned int pg_budget;	/* memory the window may take */
extern unsigned int pg_cost;	/* memory it takes, as loaded */
extern unsigned char pg_rows;	/* lines kept on each side of keep */
extern unsigned char pg_on;	/* a file is open */
extern char pg_line[PG_LINE + 1];	/* a line read, with a NUL */
extern const char *pg_err;	/* what went wrong, or 0 */

#define PG_BELOW	(&pg_tab[PG_NP - pg_nb])

/* page.s takes its arguments on the stack and calls the ed_ functions
   so, the old convention under SDCC 4 */
#ifdef PG_HOST
#define PG_CC
#define PG_FAST
#else
#include <_cconv.h>
#define PG_CC		__LIB
#define PG_FAST		__z88dk_fastcall __LIB
#endif

/* The editor's side */
void *ed_end(unsigned char down) PG_CC;	/* the last line, or the first, or 0 */
void *ed_step(void *l, unsigned char down) PG_CC;	/* the next or previous, 0 past the end */
unsigned char ed_tag(void *l) PG_CC;
char *ed_text(void *l, unsigned int *n) PG_CC;
void ed_begin(unsigned char down) PG_CC;	/* where ed_add puts lines: the end, or the top */
unsigned int ed_add(char *s, unsigned int n, unsigned char tag) PG_CC;	/* its cost, 0 no memory */
void ed_drop(void *l, unsigned char down) PG_CC;	/* a line at that end leaves */

/* name opened, the window may take budget bytes. 0 if it is not there */
unsigned char pg_open(const char *name, unsigned int budget) PG_CC;
void pg_close(void) PG_CC;			/* the work file deleted */
/* a part more on that side, keeping the lines near keep. 0 if none */
unsigned char pg_slide(unsigned char down, void *keep) PG_CC;
/* a part away from keep out of the window, to free memory. 0 if none */
unsigned char pg_free(void *keep) PG_FAST;
void pg_touch(unsigned char tag) PG_FAST;	/* a line of the part was changed */
unsigned char pg_newtag(void) PG_CC;		/* a tag for a line with no neighbor */
/* the window loaded at line n (0 the first), its line given, 0 at the end */
void *pg_goto(unsigned int n) PG_FAST;
unsigned int pg_above(void) PG_CC;		/* the lines above the window */
/* the file written to name, NAME.BAK kept if bak: its lines, or -1 */
long pg_save(const char *name, unsigned char bak) PG_CC;

#endif
