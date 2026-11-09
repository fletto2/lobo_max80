/* The C library's calling convention. The resident library is
   entered by the dispatcher in clib/hdr.s with the program's stack
   frame, and the assembly functions take their arguments on the stack,
   so under SDCC 4 their prototypes keep the old convention,
   __sdcccall(0). The rest of a program passes arguments in registers. */
#ifndef _CPM_CCONV_H
#define _CPM_CCONV_H
#if defined(__SDCC_VERSION_MAJOR) && __SDCC_VERSION_MAJOR >= 4
#define __LIB __sdcccall(0)
#else
#define __LIB
#endif
#endif
