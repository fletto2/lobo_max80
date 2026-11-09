/* stdio for SDCC programs under CP/M, in lib/. No floating point
   in printf and scanf. */
#ifndef _CPM_STDIO_H
#define _CPM_STDIO_H
#include <_cconv.h>

#include <stddef.h>
#include <stdarg.h>

#define EOF	(-1)
#define SEEK_SET	0
#define SEEK_CUR	1
#define SEEK_END	2
#define FOPEN_MAX	6
#define FILENAME_MAX	15
#define BUFSIZ	128
#define L_tmpnam	13
#define TMP_MAX	100
#define _IOFBF	0
#define _IOLBF	1
#define _IONBF	2

typedef struct _FILE FILE;
typedef long fpos_t;
extern FILE *stdin, *stdout, *stderr;

FILE *fopen(const char *name, const char *mode) __LIB;
FILE *freopen(const char *name, const char *mode, FILE *f) __LIB;
FILE *fdopen(int fd, const char *mode) __LIB;
int fclose(FILE *f) __LIB;
int fflush(FILE *f) __LIB;
int fgetc(FILE *f) __LIB;
int fputc(int c, FILE *f) __LIB;
int ungetc(int c, FILE *f) __LIB;
char *fgets(char *buf, int n, FILE *f) __LIB;
char *gets(char *buf) __LIB;
int fputs(const char *s, FILE *f) __LIB;
int puts(const char *s) __LIB;
int putchar(int c) __LIB;
int getchar(void) __LIB;
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *f) __LIB;
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *f) __LIB;
int feof(FILE *f) __LIB;
int ferror(FILE *f) __LIB;
void clearerr(FILE *f) __LIB;
int fileno(FILE *f) __LIB;
int fseek(FILE *f, long offset, int whence) __LIB;
long ftell(FILE *f) __LIB;
void rewind(FILE *f) __LIB;
int fgetpos(FILE *f, fpos_t *pos) __LIB;
int fsetpos(FILE *f, const fpos_t *pos) __LIB;
void setbuf(FILE *f, char *buf) __LIB;
int setvbuf(FILE *f, char *buf, int mode, size_t size) __LIB;
long getline(char **line, size_t *n, FILE *f) __LIB;
long getdelim(char **line, size_t *n, int delim, FILE *f) __LIB;

int printf(const char *fmt, ...) __LIB;
int fprintf(FILE *f, const char *fmt, ...) __LIB;
int sprintf(char *buf, const char *fmt, ...) __LIB;
int snprintf(char *buf, size_t n, const char *fmt, ...) __LIB;
int vprintf(const char *fmt, va_list ap) __LIB;
int vfprintf(FILE *f, const char *fmt, va_list ap) __LIB;
int vsprintf(char *buf, const char *fmt, va_list ap) __LIB;
int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap) __LIB;
int scanf(const char *fmt, ...) __LIB;
int fscanf(FILE *f, const char *fmt, ...) __LIB;
int sscanf(const char *s, const char *fmt, ...) __LIB;
int vscanf(const char *fmt, va_list ap) __LIB;
int vfscanf(FILE *f, const char *fmt, va_list ap) __LIB;
int vsscanf(const char *s, const char *fmt, va_list ap) __LIB;

void perror(const char *s) __LIB;
int remove(const char *name) __LIB;
int rename(const char *from, const char *to) __LIB;
char *tmpnam(char *buf) __LIB;
FILE *tmpfile(void) __LIB;

#define getc(f) fgetc(f)
#define putc(c, f) fputc(c, f)

#endif
