/*
 * The routines in this file are called to create a subjob running a command
 * interpreter. CP/M runs one program at a time, so under xcpmz80 they only
 * say so. The other systems' code of MicroEMACS 3.6 is left out.
 */
#include        <stdio.h>
#include	"estruct.h"
#include        "edef.h"

/* ^X C, i-shell */
int spawncli(int f, int n)
{
	(void)f;
	(void)n;
	mlwrite("[Not available under CP/M]");
	return (FALSE);
}

/* ^X !, shell-command */
int spawn(int f, int n)
{
	(void)f;
	(void)n;
	mlwrite("[Not available under CP/M]");
	return (FALSE);
}
