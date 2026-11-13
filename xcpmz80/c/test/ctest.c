/* CTEST.COM: checks the CP/M C library in lib/. Each line it
 * prints is checked by test.sh, which reads them from CTEST.LOG, as
 * they are more than a screen. */

#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <setjmp.h>
#include <time.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <cpm.h>

static jmp_buf jb;
static FILE *logf;

/* a line to the screen and the log */
static void say(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	va_start(ap, fmt);
	vfprintf(logf, fmt, ap);
	va_end(ap);
}

static void jump(int v)
{
	longjmp(jb, v);
}

static int icmp(const void *a, const void *b)
{
	return *(const int *)a - *(const int *)b;
}

/* 1 if interrupts are on (IFF2), for the check that the resident
 * library gives them back as it found them */
static unsigned char iffon(void) __naked
{
	__asm
	ld	a,i			; P/V = IFF2
	ld	a,#0			; the result in A and in L, for
	ld	l,a			; sdcccall 1 and 0
	ret	po
	inc	a
	ld	l,a
	ret
	__endasm;
}

static volatile int sink;
/* buffers under 8000h, in the program's bank, which the library copies */
static char sb[800], sb2[800];

/* a call from 400 bytes deeper than the mallocs that filled the heap,
 * with nothing to copy: it runs */
static unsigned int deep(void)
{
	char b[400];
	unsigned int k;

	for (k = 0; k < 399; k++)
		b[k] = 'd';
	b[399] = 0;
	return strlen(b);
}

/* the heap filled up to its limit, a call from deeper, the heap freed */
static unsigned int fullheap(void)
{
	void *last = NULL, *p;
	unsigned int n, sz;

	for (sz = 4096; sz >= 4; sz /= 2)
		while ((p = malloc(sz)) != NULL) {
			*(void **)p = last;
			last = p;
		}
	n = deep();
	while (last) {
		p = *(void **)last;
		free(last);
		last = p;
	}
	return n;
}

static int initd = 1234;	/* initialized data, copied by crt0 */
static int zero;		/* zeroed by crt0 */

int main(void)
{
	FILE *f;
	char buf[80];
	int i, n, c;
	long l;
	const char *ra, *rb;

	{
		/* realloc grows a block over the lowest free one, or at the
		 * top: a malloc after it must not land inside it. First, with
		 * no hole below, as the heap is now */
		char *p2, *p3, *p5, *t1, *t2, *p6;

		malloc(10);
		p2 = malloc(10);
		p3 = malloc(10);
		malloc(10);
		free(p3);
		p2 = realloc(p2, 20);
		p5 = malloc(10);
		ra = p5 >= p2 + 20 || p5 + 10 <= p2 ? "apart" : "inside";
		t1 = malloc(10);
		t2 = malloc(10);
		free(t2);
		t1 = realloc(t1, 30);
		p6 = malloc(10);
		rb = p6 >= t1 + 30 || p6 + 10 <= t1 ? "apart" : "inside";
	}
	logf = fopen("CTEST.LOG", "w");
	say("init %d zero %d\n", initd, zero);
	say("regrow %s %s\n", ra, rb);
	say("fmt [%5d] [%-4d] [%04x] [%ld] [%s] [%.3s] [%c] [%u]\n",
		-42, 7, 0xbe, 123456789L, "str", "abcdef", 'Z', 65535u);
	sprintf(buf, "%d-%s", 99, "ok");
	say("sprintf %s\n", buf);
	/* the copy of a buffer under 8000h kept above 8000h, off the
	 * library's own bank, while the heap is still low */
	memset(sb2, 'c', 700);
	sb2[700] = 0;
	sprintf(sb, "%s-%d", sb2, 7);
	/* and the library's code where the copy went before still runs:
	 * functions from there, for CTEST's heap */
	say("lowbuf %d %s %d %s %d\n", (int)strlen(sb), sb + 698,
		strncasecmp("AbC", "abd", 2), stpcpy(sb2, "st") - sb2 == 2 ? "stp" : "bad",
		!!isblank(' '));
	n = sscanf("  17 abc -5", "%d %s %d", &i, buf, &c);
	say("sscanf %d %d %s %d\n", n, i, buf, c);

	/* a text file of 300 lines, past several records */
	f = fopen("CTEST.TXT", "w");
	for (i = 0; i < 300; i++)
		fprintf(f, "line %d\n", i);
	fclose(f);
	f = fopen("ctest.txt", "r");
	n = 0;
	while (fgets(buf, sizeof(buf), f))
		n++;
	say("lines %d\n", n);
	fseek(f, 0, SEEK_SET);
	fgets(buf, sizeof(buf), f);
	say("first %s", buf);
	fclose(f);

	/* the same file by fread, 50 bytes at a time: every line's bytes
	   and no CR, as fgetc gives them */
	f = fopen("ctest.txt", "r");
	{
		long t = 0;
		int cr = 0, k;

		while ((n = fread(buf, 1, 50, f)) > 0) {
			for (k = 0; k < n; k++)
				if (buf[k] == '\r')
					cr++;
			t += n;
		}
		say("fread %ld %d\n", t, cr);
	}
	fclose(f);

	/* binary: seek to a byte and read it, write in the middle */
	f = fopen("CTEST.BIN", "wb");
	for (i = 0; i < 1000; i++)
		fputc(i & 0xff, f);
	fclose(f);
	f = fopen("CTEST.BIN", "r+b");
	fseek(f, 700, SEEK_SET);
	c = fgetc(f);
	fseek(f, 300, SEEK_SET);
	fputc(0x55, f);
	fclose(f);
	f = fopen("CTEST.BIN", "rb");
	fseek(f, 300, SEEK_SET);
	n = fgetc(f);
	l = ftell(f);
	fseek(f, 0, SEEK_END);
	say("bin %d %d %ld %ld\n", c, n, l, ftell(f));
	fclose(f);
	say("missing %s\n", fopen("NOFILE.XYZ", "r") ? "found" : "null");

	/* a binary read ends after the last record, "a" on a text file goes
	 * on at its ^Z, SEEK_END counts a record still buffered, rename
	 * will not take a name that is there */
	{
		char tb[16];
		long nb, ne;
		int eof, app, rn, ex;

		f = fopen("CTEST.BIN", "rb");
		for (nb = 0; nb < 3000 && fgetc(f) != EOF; nb++)
			;
		eof = feof(f) != 0;
		fclose(f);
		f = fopen("CTEST.APP", "w");
		fputs("hi\n", f);
		fclose(f);
		f = fopen("CTEST.APP", "a");
		fputs("more\n", f);
		fclose(f);
		f = fopen("CTEST.APP", "r");
		tb[fread(tb, 1, sizeof tb - 1, f)] = 0;
		fclose(f);
		app = !strcmp(tb, "hi\nmore\n");
		f = fopen("CTEST.SK", "w+b");
		fwrite("0123456789", 1, 10, f);
		fseek(f, 0, SEEK_END);
		ne = ftell(f);
		fclose(f);
		f = fopen("CTEST.R1", "w");
		fputc('a', f);
		fclose(f);
		errno = 0;
		rn = rename("CTEST.R1", "CTEST.SK");
		ex = errno == EEXIST;
		say("ends %ld %d %d %ld %d %d\n", nb, eof, app, ne, rn, ex);
		remove("CTEST.APP");
		remove("CTEST.SK");
		remove("CTEST.R1");
	}

	/* the library's string and ctype functions */
	strcpy(buf, "abc");
	strcat(buf, "def");
	say("str %d %d %d %s %s %s %d\n", (int)strlen(buf), strcmp("abc", "abd"),
		strncmp("abcx", "abcy", 3), strchr(buf, 'd'), strrchr("a/b/c", '/'),
		strstr(buf, "cd"), (int)strspn("aab", "a"));
	say("ctype %d%d%d%d %c%c\n", !!isalpha('q'), !!isdigit('q'), !!isspace('\t'),
		!!isxdigit('F'), toupper('a'), tolower('Z'));
	strcpy(buf, "abcdefgh");
	memmove(buf + 1, buf, 3);
	memmove(buf + 4, buf + 5, 3);
	memset(buf + 7, 'x', 1);
	say("mem %s %d\n", buf, memcmp("ab", "ac", 2));
	say("num %d %ld %lx %ld %u\n", atoi("-12"), atol("100000"),
		strtoul("ff", NULL, 16), strtol("-0x10", NULL, 0), (unsigned)abs(-5));
	{
		int a[6] = { 5, 3, 9, 1, 7, 2 }, k = 7;
		qsort(a, 6, sizeof(int), icmp);
		say("qsort %d%d%d%d%d%d %d\n", a[0], a[1], a[2], a[3], a[4], a[5],
			*(int *)bsearch(&k, a, 6, sizeof(int), icmp));
	}
	if ((n = setjmp(jb)) == 0)
		jump(42);
	say("longjmp %d\n", n);
	{
		char *p = strdup("dup"), *q = malloc(100), *r;
		free(q);
		r = malloc(50);
		say("heap %s %s %s\n", p, r == q ? "reused" : "new",
			realloc(p, 200) ? "grown" : "null");
	}
	{
		/* a small hole keeps the search low; a block freed after a
		 * search found nothing is still found */
		char *h = malloc(6), *x = malloc(6), *a = malloc(40), *y = malloc(6), *s, *r;
		free(h);
		s = malloc(40);
		free(a);
		r = malloc(40);
		say("hole %s %s\n", r == a ? "refit" : "top",
			s > y && x ? "above" : "below");
	}
	say("malloc %s\n", malloc(20000) ? "ok" : "null");
	{
		char w[20];
		int x, y;
		unsigned u;
		n = sscanf("12,0x1f abc:def", "%d,%i %[a-z]:%3s%n", &x, &y, w, buf, &c);
		say("scan %d %d %d %s %s %d\n", n, x, y, w, buf, c);
		n = sscanf("  77 ", "%*d%n", &x);
		sscanf("777", "%o", &u);
		say("scan2 %d %u\n", x, u);
		/* EOF when the input ends before the first conversion */
		say("scan3 %d %d %d %d\n", sscanf("   ", "%d", &x),
			sscanf("ab", "ab"), sscanf("ab", "ab%d", &x),
			sscanf("7 ", "%d %d", &x, &y));
	}
	snprintf(buf, 8, "%s", "truncated text");
	say("snprintf %s %d\n", buf, snprintf(NULL, 0, "%d", 12345));
	say("fmt2 [%+d] [% d] [%#x] [%#o] [%-6s] [%*d] [%.2d] [%p]\n",
		5, 5, 255, 8, "ab", 4, 7, 3, (void *)0x1234);
	{
		struct tm tm = { 56, 34, 12, 1, 10, 126 };
		time_t t = mktime(&tm);
		strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S %a %j", &tm);
		say("time %lu %s\n", t, buf);
		say("asctime %s", asctime(gmtime(&t)));
	}
	say("errno %s\n", strerror(ENOENT));

	/* POSIX calls on a file */
	n = open("CTEST.FD", O_WRONLY | O_CREAT | O_TRUNC);
	write(n, "hello fd", 8);
	close(n);
	n = open("CTEST.FD", O_RDONLY);
	lseek(n, 6, SEEK_SET);
	i = read(n, buf, 2);
	buf[i] = 0;
	close(n);
	say("fd %d %s %d\n", i, buf, access("CTEST.FD", F_OK));
	say("size %ld\n", cpm_filesize("CTEST.BIN"));
	{
		char nm[13];
		n = 0;
		if (!cpm_findfirst("CTEST.*", nm))
			do
				n++;
			while (!cpm_findnext(nm));
		say("find %d\n", n);
	}
	rename("CTEST.FD", "CTEST.FD2");
	say("rename %d %d\n", access("CTEST.FD", F_OK), access("CTEST.FD2", F_OK));
	remove("CTEST.FD2");
	f = fopen("CTEST.TXT", "r");
	c = fgetc(f);
	ungetc(c, f);
	fscanf(f, "line %d", &i);
	say("fscanf %c %d\n", c, i);
	fclose(f);
	n = iffon();
	sink = strlen("abc");
	i = iffon();
	__asm__("di");
	sink = strlen("abc");
	c = iffon();
	__asm__("ei");
	say("iff %d %d %d\n", n, i, c);
	{
		/* a pointer on the stack and one under 8000h, one stored: the
		 * other keeps what it had */
		int k = 0, j;
		char *p, *q;

		strcpy(sb, "kept");
		n = sscanf("5", "%d %19s", &k, sb);
		say("mixed %d %d %s\n", n, k, sb);
		/* %s with no width, longer than 256 */
		memset(sb, 'a', 300);
		strcpy(sb + 300, " 7");
		n = sscanf(sb, "%s %d", sb2, &k);
		say("long %d %d %d\n", n, (int)strlen(sb2), k);
		/* strcat onto a short string, 780 bytes */
		memset(sb2, 'b', 780);
		sb2[780] = 0;
		strcpy(sb, "ab");
		strcat(sb, sb2);
		say("cat %d %c\n", (int)strlen(sb), sb[781]);
		/* fgets leaves the bytes after the line as they were, and
		 * with room for the 0 alone gives an empty string */
		memset(sb, 'X', 20);
		sb[20] = 0;
		f = fopen("CTEST.TXT", "r");
		fgets(sb, 10, f);
		strcpy(sb2, "Q");
		j = fgets(sb2, 1, f) == sb2 && !sb2[0];
		fclose(f);
		say("tail %c %d\n", sb[8], j);
		/* realloc to near 64K at the top of the heap */
		p = malloc(1000);
		q = realloc(p, 65534);
		say("big %s\n", q ? "got" : "null");
		/* fread's size times count past 64K: the items there are */
		p = malloc(3000);
		f = fopen("CTEST.TXT", "r");
		say("fread2 %u\n", (unsigned)fread(p, 128, 513, f));
		fclose(f);
	}
	n = fullheap();
	say("full %u\n", n);
	say("name? ");
	fgets(buf, sizeof(buf), stdin);
	say("got %s", buf);
	fclose(logf);
	return 0;
}
