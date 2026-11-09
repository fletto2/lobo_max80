#include <_cconv.h>
/* ctype for the CP/M C library, ASCII. Built once for each
 * function, L_name picks it, so a program links only those it calls. */

#include <ctype.h>

#define R(c, a, b) ((unsigned int)((c) - (a)) <= (unsigned int)((b) - (a)))

#ifdef L_isalnum
int isalnum(int c) __LIB { return R(c, '0', '9') || R(c | 32, 'a', 'z'); }
#endif
#ifdef L_isalpha
int isalpha(int c) __LIB { return R(c | 32, 'a', 'z'); }
#endif
#ifdef L_isascii
int isascii(int c) __LIB { return (unsigned int)c < 128; }
#endif
#ifdef L_isblank
int isblank(int c) __LIB { return c == ' ' || c == '\t'; }
#endif
#ifdef L_iscntrl
int iscntrl(int c) __LIB { return (unsigned int)c < 32 || c == 127; }
#endif
#ifdef L_isdigit
int isdigit(int c) __LIB { return R(c, '0', '9'); }
#endif
#ifdef L_isgraph
int isgraph(int c) __LIB { return R(c, '!', '~'); }
#endif
#ifdef L_islower
int islower(int c) __LIB { return R(c, 'a', 'z'); }
#endif
#ifdef L_isprint
int isprint(int c) __LIB { return R(c, ' ', '~'); }
#endif
#ifdef L_ispunct
int ispunct(int c) __LIB
{
	return R(c, '!', '~') && !R(c, '0', '9') && !R(c | 32, 'a', 'z');
}
#endif
#ifdef L_isspace
int isspace(int c) __LIB { return c == ' ' || R(c, '\t', '\r'); }
#endif
#ifdef L_isupper
int isupper(int c) __LIB { return R(c, 'A', 'Z'); }
#endif
#ifdef L_isxdigit
int isxdigit(int c) __LIB { return R(c, '0', '9') || R(c | 32, 'a', 'f'); }
#endif
#ifdef L_tolower
int tolower(int c) __LIB { return R(c, 'A', 'Z') ? c + 32 : c; }
#endif
#ifdef L_toupper
int toupper(int c) __LIB { return R(c, 'a', 'z') ? c - 32 : c; }
#endif
#ifdef L_toascii
int toascii(int c) __LIB { return c & 127; }
#endif
