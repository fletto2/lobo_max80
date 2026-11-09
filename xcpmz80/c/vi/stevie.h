/*
 * STEVIE - Simply Try this Editor for VI Enthusiasts
 *
 * Code Contributions By : Tim Thompson           twitch!tjt
 *                         Tony Andrews           onecom!wldrdg!tony 
 *                         G. R. (Fred) Walter    watmath!grwalter 
 */

#ifdef __ORCAC__
#ifndef MAINSEG
#pragma noroot
#endif
#pragma optimize 9
#endif

#include "env.h"

#include <stdio.h>
#ifndef ATARI
# ifndef UNIX
#   include <stdlib.h>
# endif
#endif
#include <ctype.h>
#ifndef MWC
# include <string.h>
#endif

/* The functions vpage.s calls, and its own, take their arguments on
   the stack, the old convention under SDCC 4 */
#ifdef MAX80
#include <_cconv.h>
#define VI_ASM	__LIB
#else
#define VI_ASM
#endif
#include "ascii.h"
#include "keymap.h"
#include "param.h"
#include "term.h"
#include "macros.h"

#ifdef AMIGA
/*
 * This is used to disable break signal handling.
 */
#include <signal.h>
#endif

/*extern char    *strchr();*/

#define NORMAL			 0
#define CMDLINE			 1
#define INSERT			 2
#define REPLACE			 3
#define APPEND			 4
#define UNDO			 5
#define REDO			 6
#define PUT			 7
#define FORWARD			 8
#define BACKWARD		 9
#define VALID			10
#define NOT_VALID		11
#define VALID_TO_CURSCHAR	12
#define UPDATE_CURSOR           13
#define UPDATE_ALL              14

/*
 * Boolean type definition and constants 
 */
#ifdef MAX80
typedef char    bool_t;	/* altered for xcpmz80, less code */
#else
typedef int     bool_t;
#endif

#ifndef	TRUE
# define	FALSE	(0)
# define	TRUE	(1)
#endif
#define	SORTOF	(2)
#define YES      TRUE
#define NO       FALSE
#define MAYBE    SORTOF

/*
 * Maximum screen dimensions
 */
#ifdef MAX80
#define MAX_COLUMNS 81		/* an int, the Z80 is slow with longs */
#else
#define MAX_COLUMNS 140L
#endif

/*
 * Buffer sizes
 */
#define CMDBUFFSIZE MAX_COLUMNS	/* size of the command processing buffer */

#ifdef MAX80
#define LSIZE        256	/* max. size of a line in the tags file */
#else
#define LSIZE        512	/* max. size of a line in the tags file */
#endif

#ifdef MAX80
/*
 * Altered for xcpmz80: IObuff is cut to fit the TPA, and a longer
 * line is not read. The other buffers start at BUFSTART bytes and grow
 * up to these sizes, while there is memory (growbuf() in alloc.c).
 */
#define IOSIZE     (256+1)	/* file i/o and sprintf buffer size */
#define BUFSTART    64
#else
#define IOSIZE     (1024+1)	/* file i/o and sprintf buffer size */
#endif

#define YANKSIZE    5200	/* yank buffer size */
#define INSERT_SIZE 5300	/* insert, redo and undo buffer size must be
				 * bigger than YANKSIZE */
#define REDO_UNDO_SIZE 5400	/* redo, undo and (undo an undo) buffer size
				 * must be bigger than INSERT_SIZE */
#define READSIZE    5500	/* read buffer size must be bigger than
				 * YANKSIZE and REDO_UNDO_SIZE */

/*
 * SLOP is the amount of extra space we get for text on a line during editing
 * operations that need more space. This keeps us from calling alloc every
 * time we get a character during insert mode. No extra space is allocated
 * when the file is initially read. 
 */
#define	SLOP	10

/*
 * LINEINC is the gap we leave between the artificial line numbers. This
 * helps to avoid renumbering all the lines every time a new line is
 * inserted. 
 *
 * Since line numbers are stored in longs (32 bits), a LINEINC of 10000
 * lets us have > 200,000 lines and we won't have to renumber very often.
 */
#ifdef MAX80
/*
 * Altered for xcpmz80: the line numbers are 16 bits, as the Z80
 * handles them in far less code, and LINEINC is 16. The memory holds
 * well under the 4095 lines that allows.
 */
#define	LINEINC	16
#define	LASTLINE 0xffffU
typedef unsigned int lineno_t;
#else
#define	LINEINC	10000
#define	LASTLINE 0xffffffffL
typedef unsigned long lineno_t;
#endif

#ifdef MAX80
#define CHANGED    pgchanged()	/* and the window's part */
/* the line is the last of the file, the window is at its top */
#define ATEND(l)   ((l)->next == Fileend->linep && !pg_nb)
#define ATTOP      (!pg_na)
#else
#define ATEND(l)   ((l)->next == Fileend->linep)
#define ATTOP      TRUE
#define CHANGED    Changed = TRUE
#endif
#define UNCHANGED  Changed = FALSE

#define S_NOT_VALID NumLineSizes = -1

#define S_LINE_NOT_VALID LineNotValid = TRUE

#define S_CHECK_TOPCHAR_AND_BOTCHAR CheckTopcharAndBotchar = TRUE

#define S_MUST_UPDATE_BOTCHAR MustUpdateBotchar = TRUE

#define S_VALID_TO_CURSCHAR ValidToCurschar = TRUE

struct line {
    struct line    *next;	/* next line */
    struct line    *prev;	/* previous line */
    char           *s;		/* text for this line */
    int             size;	/* actual size of space at 's' */
    lineno_t        num;	/* line "number" */
#ifdef MAX80
    unsigned char   tag;	/* its part of the window, 0 new */
#endif
};

#define	LINEOF(x)	((x)->linep->num)

#ifdef MAX80
/*
 * Altered for xcpmz80: newline() gets a line's struct and its text
 * in one block, which saves a block header a line. FREE_S frees the text
 * only when it has been moved to a block of its own.
 */
#define	FREE_S(l)	freetext(l)
#else
#define	FREE_S(l)	free((l)->s)
#endif

struct lptr {
    struct line    *linep;	/* line we're referencing */
    int             index;	/* position within that line */
};

typedef struct line LINE;
typedef struct lptr LPtr;

struct charinfo {
    char            ch_size;
    char           *ch_str;
};

#ifdef MAX80
/* altered for xcpmz80: worked out by charset.c, not a table */
int             ch_size(char c);
char           *ch_str(char c);
#define CH_SIZE(c)	ch_size(c)
#define CH_STR(c)	ch_str(c)
#else
extern struct charinfo chars[];
#define CH_SIZE(c)	(chars[c].ch_size)
#define CH_STR(c)	(chars[c].ch_str)
#endif

#ifdef AMIGA
extern int      Aux_Device;
#endif
extern int      State;
extern int      Rows;
extern int      Columns;
extern int      CheckTopcharAndBotchar;
extern int      MustUpdateBotchar;
extern int      ValidToCurschar;
extern int      LineNotValid;
extern int      NumLineSizes;
extern LINE   **LinePointers;
extern char    *LineSizes;
extern char    *Filename;
#ifdef MAX80
/*
 * Altered for xcpmz80: the position pointers point at static
 * structures, which the Z80 reaches in less code than through a pointer.
 */
extern LPtr     Filemem_s;
extern LPtr     Filetop_s;
extern LPtr     Fileend_s;
extern LPtr     Topchar_s;
extern LPtr     Botchar_s;
extern LPtr     Curschar_s;
extern LPtr     Insstart_s;
#define Filemem (&Filemem_s)
#define Filetop (&Filetop_s)
#define Fileend (&Fileend_s)
#define Topchar (&Topchar_s)
#define Botchar (&Botchar_s)
#define Curschar (&Curschar_s)
#define Insstart (&Insstart_s)
#else
extern LPtr    *Filemem;
extern LPtr    *Filetop;
extern LPtr    *Fileend;
extern LPtr    *Topchar;
extern LPtr    *Botchar;
extern LPtr    *Curschar;
extern LPtr    *Insstart;
#endif
extern int      Cursrow;
extern int      Curscol;
extern int      Cursvcol;
extern int      Curswant;
extern bool_t   set_want_col;
extern int      Prenum;
extern bool_t   Changed;
extern bool_t   RedrawingDisabled;
extern bool_t   UndoInProgress;
extern char    *IObuff;
extern char    *Insbuffptr;
extern char    *Insbuff;
extern char    *Readbuffptr;
extern char    *Readbuff;
extern char    *Redobuffptr;
extern char    *Redobuff;
extern char    *Undobuffptr;
extern char    *Undobuff;
extern char    *UndoUndobuffptr;
extern char    *UndoUndobuff;
extern char    *Yankbuffptr;
extern char    *Yankbuff;
#ifdef MAX80
extern unsigned InsbuffSize, ReadbuffSize, RedobuffSize;
extern unsigned UndobuffSize, UndoUndobuffSize, YankbuffSize;
#endif
extern char     last_command;
extern char     last_command_char;
extern bool_t   AllocQuiet;
extern char    *Partial;

/* alloc.c */
char  *alloc(unsigned size);
char  *strsave(char *);
void   screenalloc(void);
void   filealloc(void) VI_ASM;
void   freeall(void) VI_ASM;
LINE  *newline(int) VI_ASM;
#ifdef MAX80
void   freetext(LINE *) VI_ASM;
bool_t growbuf(char **, unsigned *, unsigned);
void   shrinkbuf(char **, unsigned *);
#endif
bool_t canincrease(int);

/* cmdline.c */
void   readcmdline(char,char *);
#ifndef MAX80
void   dotag(char *, bool_t);
#endif
void   msg(char *s) VI_ASM;
void   emsg(char *) VI_ASM;
void   smsg(char *s,...);
void   gotocmdline(bool_t, char);
void   wait_return(void);

/* dec.c */
int    dec(LPtr *lp);

/* edit.c */
void   edit(void);
void   insertchar(char);
void   getout(int);
void   scrollup(int);
void   scrolldown(int);
void   beginline(bool_t);
bool_t oneright(void);
bool_t oneleft(void);
bool_t oneup(int);
bool_t onedown(int);

/* fileio.c */
void   filemess(char *);
void   renum(void) VI_ASM;
bool_t readfile(char *,LPtr *,bool_t);
bool_t writeit(char *, LPtr *, LPtr *);

/* s_io.c */
void   s_cursor_off(void);
void   s_cursor_on(void);
void   s_clear(void);
void   s_refresh(int);
void   NotValidFromCurschar(void);
void   Update_Botchar(void);

/* help.c */
#ifndef MAX80
bool_t help(void);
#endif

/* inc.c */
int    inc(LPtr *);

/* linefunc.c */
LPtr  *nextline(LPtr *) VI_ASM;
LPtr  *prevline(LPtr *) VI_ASM;
void   coladvance(LPtr *,int);

/* main.c */
void   stuffReadbuff(char *);
void   stuffnumReadbuff(int);
char   vgetc(void);
char   vpeekc(void);

/* mark.c */
void   setpcmark(void);
void   clrall(void);
void   clrmark(LINE *) VI_ASM;
bool_t setmark(char);
LPtr  *getmark(char);

/* misccmds.c */
bool_t OpenForward(int);
bool_t OpenBackward(int);
void   fileinfo(void);
void   inschar(char);
void   insstr(char *);
void   delline(int);
bool_t delchar(bool_t, bool_t);
int    cntllines(LPtr *, LPtr *) VI_ASM;
int    plines(char *);
LPtr  *gotoline(int) VI_ASM;

/* normal.c */
void   normal(char);
void   ResetBuffers(void);
void   AppendToInsbuff(char *);
void   AppendToRedobuff(char *);
void   AppendNumberToRedobuff(int);
void   AppendToUndobuff(char *);
void   AppendNumberToUndobuff(int);
void   AppendPositionToUndobuff(int,int);
void   AppendToUndoUndobuff(char *);
void   AppendNumberToUndoUndobuff(int);
void   AppendPositionToUndoUndobuff(int,int);
bool_t linewhite(LPtr *);

/* mk.c */
char  *mkstr(char);
#ifndef MAX80
char  *mkline(int);
#endif

/* param.c */
void   doset(char *,bool_t);

/* screen.c */
void   cursupdate(int);

/* search.c */
#ifndef MAX80
void   doglob(LPtr *,LPtr *,char *);
#endif
void   dosub(LPtr *,LPtr *,char *);
void   searchagain(int);
bool_t dosearch(int,char *);
bool_t repsearch(bool_t);
bool_t searchc(char,int,int);
bool_t crepsearch(int);
#ifndef MAX80
bool_t findfunc(int);
#endif
LPtr  *showmatch(void);
LPtr  *fwd_word(LPtr *,int);
LPtr  *bck_word(LPtr *,int);
LPtr  *end_word(LPtr *,int);

#ifdef MAX80
/* vpage.s, the window over a file bigger than memory */
#include "../page/page.h"
extern bool_t   pgfixed, pgbig;
extern LINE    *pglo, *pghi;
void   pgchanged(void) VI_ASM;
bool_t pgopen(char *) VI_ASM;
bool_t pgcheck(void) VI_ASM;
bool_t pgcur(char) __z88dk_fastcall VI_ASM;
void   pgtop(int) __z88dk_fastcall VI_ASM;
LPtr  *pgnext(LPtr *, char) VI_ASM;
bool_t pgfree(void) VI_ASM;
void   pgload(void) VI_ASM;
LPtr  *pggoto(unsigned) __z88dk_fastcall VI_ASM;
int    pgtotal(void) VI_ASM;
bool_t pgsave(char *, char) VI_ASM;
void   pgfrom(void) VI_ASM;
unsigned pgfromline(void) VI_ASM;
void   pgback(void) VI_ASM;
#endif

/* format_l.c */
char *format_line(char *, int *);

/*
 * Machine-dependent routines. 
 */
#ifdef AMIGA
# include "amiga.h"
#endif
#ifdef BSD
# include "bsd.h"
#endif
#ifdef UNIX
# include "unix.h"
#endif
#ifdef TOS
# include "tos.h"
#endif
#ifdef OS2
# include "os2.h"
#endif
#ifdef DOS
# include "dos.h"
#endif
#ifdef GSOS
# include "gsos.h"
#endif
#ifdef MAX80
# include "max80.h"
#endif
