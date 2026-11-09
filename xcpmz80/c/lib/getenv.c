#include <_cconv.h>
/* getenv and system for the CP/M C library. CP/M has no
 * environment and no way to run a command and come back. */

#include <stdlib.h>
#include <errno.h>

char *getenv(const char *name) __LIB
{
	(void)name;
	return NULL;
}

int system(const char *cmd) __LIB
{
	(void)cmd;
	if (!cmd)
		return 0;	/* no command processor to call */
	errno = ENOSYS;
	return -1;
}
