#include <_cconv.h>
/* bios() for the CP/M C library, apart from cpmdir.c since a
 * resident program keeps it in itself */

#include <cpm.h>
#include "cpmint.h"

unsigned int __bios22(unsigned char n, unsigned int bc, unsigned int de);

/* Under CP/M 3, and xcpmz80, through function 50, which maps the BIOS
 * in. Under CP/M 2.2 straight to the jump table. */
unsigned int bios(unsigned char n, unsigned int bc, unsigned int de) __LIB {
	unsigned char pb[8];

	if ((unsigned char)bdos(12, 0) < 0x30)
		return __bios22(n, bc, de);
	pb[0] = n;
	pb[1] = bc;		/* A */
	pb[2] = bc;
	pb[3] = bc >> 8;
	pb[4] = de;
	pb[5] = de >> 8;
	pb[6] = pb[7] = 0;
	return bdos(50, (unsigned int)pb);
}
