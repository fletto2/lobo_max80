/* CP/M itself, for SDCC programs, in lib/bdos.s and lib/cpmdir.c */
#ifndef _CPM_CPM_H
#define _CPM_CPM_H
#include <_cconv.h>

/* BDOS function fn with DE, giving back HL (A in L) */
unsigned int bdos(unsigned char fn, unsigned int de) __LIB;

/* BIOS entry n (0 BOOT, 1 WBOOT, 2 CONST, ...) with BC and DE, by the
   jump table page zero points at, giving back A, or HL for SELDSK,
   SECTRAN and the CP/M 3 tables */
unsigned int bios(unsigned char n, unsigned int bc, unsigned int de) __LIB;

unsigned char cpm_version(void) __LIB; /* 22h CP/M 2.2, 31h CP/M 3 */
int cpm_getdrive(void) __LIB; /* 0 A: */
void cpm_setdrive(int drive) __LIB;
int cpm_getuser(void) __LIB;
void cpm_setuser(int user) __LIB;

/* The directory: cpm_findfirst("B:*.TXT", name) gives the first match as
   "NAME.EXT" in name (13 bytes), 0 when found, cpm_findnext the next */
int cpm_findfirst(const char *pattern, char *name) __LIB;
int cpm_findnext(char *name) __LIB;

/* A file's size in bytes, by its records, -1 when it is not there */
long cpm_filesize(const char *name) __LIB;

#endif
