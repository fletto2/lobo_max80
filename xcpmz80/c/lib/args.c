/* main's arguments for the CP/M C library: argc and argv from the
 * command tail at 0080h, split at spaces, in the upper case CP/M gives.
 * "two words" in quotes is one argument. argv[0] is "", CP/M keeps no
 * program name. crt0 calls cpmargs. */

#include <string.h>

#define MAXARGS 16
int cpmargc;
static char *argv[MAXARGS + 1];
static char tail[128];

char **cpmargs(void)
{
	unsigned char n = *(unsigned char *)0x80;
	char *p = tail, *d;

	if (n > 127)
		n = 127;
	memcpy(tail, (char *)0x81, n);
	tail[n] = 0;
	argv[0] = "";
	cpmargc = 1;
	for (;;) {
		while (*p == ' ' || *p == '\t')
			p++;
		if (!*p || cpmargc == MAXARGS)
			break;
		if (*p == '"') {
			argv[cpmargc++] = d = ++p;
			while (*p && *p != '"')
				*d++ = *p++;
			if (*p)
				p++;
			*d = 0;
			continue;
		}
		argv[cpmargc++] = p;
		while (*p && *p != ' ' && *p != '\t')
			p++;
		if (*p)
			*p++ = 0;
	}
	argv[cpmargc] = NULL;
	return argv;
}
