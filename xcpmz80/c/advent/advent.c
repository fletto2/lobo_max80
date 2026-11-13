
/*	program ADVENT.C					*\
\*	WARNING: "advent.c" allocates GLOBAL storage space by	*\
\*		including "advdef.h".				*\
\*		All other modules use "advdec.h"		*/

#include <err.h>
#include <stdio.h> /* drv = 1.1st file 2.def 3.A	*/
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

#include "advent.h"  /* #define preprocessor equates	*/
#include "advword.h" /* definition of "word" array	*/
#include "advcave.h" /* definition of "cave" array	*/
#ifndef BUILTIN
#include "advtext.h" /* definition of "text" arrays	*/
#endif
#include "advdef.h"

#define setmem(l, s, c) memset(l, c, s)

int main(int argc, char *argv[])
{
	int rflag; /* user restore request option	*/

	rflag = 0;
	dbugflg = 0;
	while (--argc > 0) {
		++argv;
		if (**argv != '-')
			break;
		switch (tolower(argv[0][1])) {
		case 'r':
			++rflag;
			continue;
		case 'd':
			++dbugflg;
			continue;
		default:
			printf("unknown flag: %c\n", argv[0][1]);
			continue;
		}
	}

	if (dbugflg < 2)
		dbugflg = 0; /* must request three times	*/
	opentxt();
	initplay();
	if (rflag)
		restore();
	else if (yes(65, 1, 0))
		limit = 1000;
	else
		limit = 330;
	saveflg = 0;
	srand(511); /* seed random	*/
	for (;;) {	/* a SAVE that fails plays on */
		while (!saveflg)
			turn();
		if (saveadv())
			break;
		saveflg = 0;
	}
#ifndef BUILTIN
	fclose(fd1);
	fclose(fd2);
	fclose(fd3);
	fclose(fd4);
#endif
	return 0;
}

/* ************************************************************	*/

/*
	Initialize integer arrays with sscanf
*/
void scanint(int *pi, char *str)
{
	while (*str) {
		if ((sscanf(str, "%d,", pi++)) < 1)
			bug(41);      /* failed before EOS	*/
		while (*str++ != ',') /* advance str pointer	*/
			;
	}
}

/*
	Initialization of adventure play variables
*/
void initplay(void)
{
	turns = 0;

	/* initialize location status array */
	setmem(cond, (sizeof(int)) * MAXLOC, 0);
	scanint(&cond[1], "5,1,5,5,1,1,5,17,1,1,");
	scanint(&cond[13], "32,0,0,2,0,0,64,2,");
	scanint(&cond[21], "2,2,0,6,0,2,");
	scanint(&cond[31], "2,2,0,0,0,0,0,4,0,2,");
	scanint(&cond[42], "128,128,128,128,136,136,136,128,128,");
	scanint(&cond[51], "128,128,136,128,136,0,8,0,2,");
	scanint(&cond[79], "2,128,128,136,0,0,8,136,128,0,2,2,");
	scanint(&cond[95], "4,0,0,0,0,1,");
	scanint(&cond[113], "4,0,1,1,");
	scanint(&cond[122], "8,8,8,8,8,8,8,8,8,");

	/* initialize object locations */
	setmem(place, (sizeof(int)) * MAXOBJ, 0);
	scanint(&place[1], "3,3,8,10,11,0,14,13,94,96,");
	scanint(&place[11], "19,17,101,103,0,106,0,0,3,3,");
	scanint(&place[23], "109,25,23,111,35,0,97,");
	scanint(&place[31], "119,117,117,0,130,0,126,140,0,96,");
	scanint(&place[50], "18,27,28,29,30,");
	scanint(&place[56], "92,95,97,100,101,0,119,127,130,");

	/* initialize second (fixed) locations */
	setmem(fixed, (sizeof(int)) * MAXOBJ, 0);
	scanint(&fixed[3], "9,0,0,0,15,0,-1,");
	scanint(&fixed[11], "-1,27,-1,0,0,0,-1,");
	scanint(&fixed[23], "-1,-1,67,-1,110,0,-1,-1,");
	scanint(&fixed[31], "121,122,122,0,-1,-1,-1,-1,0,-1,");
	scanint(&fixed[62], "121,-1,");

	/* initialize default verb messages */
	scanint(actmsg, "0,24,29,0,33,0,33,38,38,42,14,");
	scanint(&actmsg[11], "43,110,29,110,73,75,29,13,59,59,");
	scanint(&actmsg[21], "174,109,67,13,147,155,195,146,110,13,13,");

	/* initialize various flags and other variables */
	setmem(visited, (sizeof(int)) * MAXLOC, 0);
	setmem(prop, (sizeof(int)) * MAXOBJ, 0);
	setmem(&prop[50], (sizeof(int)) * (MAXOBJ - 50), 0xff);
	wzdark = closed = closing = holding = detail = 0;
	limit = 100;
	tally = 15;
	tally2 = 0;
	newloc = 1;
	loc = oldloc = oldloc2 = 3;
	knfloc = 0;
	chloc = 114;
	chloc2 = 140;
	/*	dloc[DWARFMAX-1] = chloc				*/
	scanint(dloc, "0,19,27,33,44,64,114,");
	scanint(odloc, "0,0,0,0,0,0,0,");
	dkill = 0;
	scanint(dseen, "0,0,0,0,0,0,0,");
	clock1 = 30;
	clock2 = 50;
	panic = 0;
	bonus = 0;
	numdie = 0;
	daltloc = 18;
	lmwarn = 0;
	foobar = 0;
	dflag = 0;
	gaveup = 0;
	saveflg = 0;
}

/*
	Open advent?.txt files
*/
#ifdef CPM	/* xcpmz80: the text files on the current drive */
#define ADV1 "ADVENT1.TXT"
#define ADV2 "ADVENT2.TXT"
#define ADV3 "ADVENT3.TXT"
#define ADV4 "ADVENT4.TXT"
#else
#ifndef DATADIR
#define DATADIR "/usr/local/lib/games"
#endif

#define ADV1 DATADIR "/advent1.txt"
#define ADV2 DATADIR "/advent2.txt"
#define ADV3 DATADIR "/advent3.txt"
#define ADV4 DATADIR "/advent4.txt"
#endif

void opentxt(void)
{
#ifndef BUILTIN
	fd1 = fopen(ADV1, "r");
	if (!fd1) {
		printf("Sorry, I cannot open %s...\n", ADV1);
		exit(-1);
	}
	fd2 = fopen(ADV2, "r");
	if (!fd2) {
		printf("Sorry, I cannot open %s...\n", ADV2);
		exit(-1);
	}
	fd3 = fopen(ADV3, "r");
	if (!fd3) {
		printf("Sorry, I cannot open %s...\n", ADV3);
		exit(-1);
	}
	fd4 = fopen(ADV4, "r");
	if (!fd4) {
		printf("Sorry, I cannot open %s...\n", ADV4);
		exit(-1);
	}
#endif
}

/* What a saved game holds, in order: SAVE writes it and RESTORE reads
   it all before it changes any of it */
static struct { int *p; int n; } savetab[] = {
	{ &turns, 1 },
	{ &loc, 1 },
	{ &oldloc, 1 },
	{ &oldloc2, 1 },
	{ &newloc, 1 },
	{ &cond[0], MAXLOC },
	{ &place[0], MAXOBJ },
	{ &fixed[0], MAXOBJ },
	{ &visited[0], MAXLOC },
	{ &prop[0], MAXOBJ },
	{ &tally, 1 },
	{ &tally2, 1 },
	{ &limit, 1 },
	{ &lmwarn, 1 },
	{ &wzdark, 1 },
	{ &closing, 1 },
	{ &closed, 1 },
	{ &holding, 1 },
	{ &detail, 1 },
	{ &knfloc, 1 },
	{ &clock1, 1 },
	{ &clock2, 1 },
	{ &panic, 1 },
	{ &dloc[0], DWARFMAX },
	{ &dflag, 1 },
	{ &dseen[0], DWARFMAX },
	{ &odloc[0], DWARFMAX },
	{ &daltloc, 1 },
	{ &dkill, 1 },
	{ &chloc, 1 },
	{ &chloc2, 1 },
	{ &bonus, 1 },
	{ &numdie, 1 },
	{ &object1, 1 },
	{ &gaveup, 1 },
	{ &foobar, 1 },
};
#define NSAVE (sizeof(savetab) / sizeof(savetab[0]))

/*
		save adventure game: 1 if it was saved
*/
int saveadv(void)
{
	char nm[64];
	FILE *fp;
	int i, bad = 0;

	savefile(1, nm, sizeof(nm));

	fp = fopen(nm, "wb");
	if (!fp) {	/* the game goes on, to try another name */
		warn("Sorry, I cannot save your game to %s", nm);
		return 0;
	}
	for (i = 0; i < NSAVE; i++)
		if (fwrite(savetab[i].p, sizeof(int), savetab[i].n, fp) != savetab[i].n)
			bad = 1;
	if (fclose(fp) == -1 || bad) {
		remove(nm);
		warn("Sorry, I cannot write the save game file %s", nm);
		return 0;
	}

	printf("Game saved to %s -- see you later!\n", nm);
	return 1;
}

void restore(void)
{
	char nm[64];
	FILE *fp;
	int *buf, *q, i, total = 0;

	savefile(0, nm, sizeof(nm));

	fp = fopen(nm, "rb");
	if (fp == NULL) {
		warn("Sorry, cannot find any saved game to load from %s", nm);
		return;
	}
	for (i = 0; i < NSAVE; i++)
		total += savetab[i].n;
	buf = malloc(total * sizeof(int));
	if (!buf || fread(buf, sizeof(int), total, fp) != total) {
		warn("Failed reading saved gave file, %s, data format error", nm);
		free(buf);
		fclose(fp);
		return;	/* the game as it was */
	}
	fclose(fp);
	for (q = buf, i = 0; i < NSAVE; q += savetab[i].n, i++)
		memcpy(savetab[i].p, q, savetab[i].n * sizeof(int));
	free(buf);

	printf("Game restored from %s\n", nm);
	describe();
}

char *savefile(int save, char *path, size_t len)
{
	char *home;

#ifndef SAVEDIR
	(void)save;

	home = getenv("HOME");
	if (!home)
		home = ".";
	snprintf(path, len, "%s/.adventure", home);
#else
	char fn[32];

	if (save)
		printf("What do you want to name the saved game? ");
	else
		printf("What is the name of the saved game? ");
	fflush(stdout);

	if (!fgets(fn, 32, stdin)) {
		home = getenv("LOGNAME");
		snprintf(fn, sizeof(fn), "%s", home ? home : "advent");
	} else {
		char *sptr;

		if ((sptr = strchr(fn, '\n')))
			*sptr = '\0';
		if ((sptr = strchr(fn, '\r')))
			*sptr = '\0';
		if ((sptr = strchr(fn, '.')))
			*sptr = '\0'; /* kill extension	*/
	}

	{	/* max 8 char filename, after a drive or folder */
		char *base = fn, *sp;
		for (sp = fn; *sp; sp++)
			if (*sp == ':' || *sp == '\\' || *sp == '/')
				base = sp + 1;
		if (!*base)	/* no name: advent */
			snprintf(base, sizeof(fn) - (base - fn), "advent");
		if (strlen(base) > 8)
			base[8] = '\0';
	}
	strcat(fn, ".adv");

#ifdef CPM
	snprintf(path, len, "%s", fn);
#else
	snprintf(path, len, "%s/%s", SAVEDIR, fn);
#endif

#endif

	return path;
}
