/* POSIX-style calls for SDCC programs under CP/M, in lib/unistd.c
   and lib/getopt.c. A file descriptor is a stdio FILE: 0, 1 and 2 are
   the console, the others files opened by open(). */
#ifndef _CPM_UNISTD_H
#define _CPM_UNISTD_H
#include <_cconv.h>

#include <stddef.h>

#define STDIN_FILENO	0
#define STDOUT_FILENO	1
#define STDERR_FILENO	2
#define F_OK	0
#define R_OK	4
#define W_OK	2
#define X_OK	1

typedef int ssize_t;
typedef long off_t;

ssize_t read(int fd, void *buf, size_t n) __LIB;
ssize_t write(int fd, const void *buf, size_t n) __LIB;
int close(int fd) __LIB;
off_t lseek(int fd, off_t off, int whence) __LIB;
int unlink(const char *name) __LIB;
int access(const char *name, int mode) __LIB;
int isatty(int fd) __LIB;
unsigned int sleep(unsigned int sec) __LIB;
int usleep(unsigned long usec) __LIB;
int chdir(const char *drive) __LIB;
char *getcwd(char *buf, size_t n) __LIB;

extern char *optarg;
extern int optind, opterr, optopt;
int getopt(int argc, char *const argv[], const char *opts) __LIB;

#endif
