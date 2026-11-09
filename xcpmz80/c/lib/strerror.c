#include <_cconv.h>
/* strerror for the CP/M C library */

#include <errno.h>
#include <string.h>

static const struct { unsigned char n; const char *s; } msgs[] = {
	{ 0, "No error" },
	{ EPERM, "Not permitted" },
	{ ENOENT, "No such file" },
	{ EIO, "I/O error" },
	{ EBADF, "Bad file number" },
	{ ENOMEM, "Out of memory" },
	{ EACCES, "Access denied" },
	{ EEXIST, "File exists" },
	{ EINVAL, "Invalid argument" },
	{ EMFILE, "Too many open files" },
	{ ENOSPC, "Disk full" },
	{ EROFS, "Read-only disk" },
	{ EDOM, "Out of domain" },
	{ ERANGE, "Out of range" },
	{ ENOSYS, "Not implemented" },
};

char *strerror(int e) __LIB
{
	unsigned char i;

	for (i = 0; i < sizeof(msgs) / sizeof(msgs[0]); i++)
		if (msgs[i].n == e)
			return (char *)msgs[i].s;
	return "Unknown error";
}
