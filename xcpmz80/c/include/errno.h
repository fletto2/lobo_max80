/* errno for SDCC programs under CP/M. strerror gives the text. */
#ifndef _CPM_ERRNO_H
#define _CPM_ERRNO_H

extern int errno;
#define EPERM	1
#define ENOENT	2
#define EIO	5
#define EBADF	9
#define ENOMEM	12
#define EACCES	13
#define EEXIST	17
#define EINVAL	22
#define EMFILE	24
#define ENOSPC	28
#define EROFS	30
#define EDOM	33
#define ERANGE	34
#define ENOSYS	38

#endif
