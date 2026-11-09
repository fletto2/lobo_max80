#include <_cconv.h>
/* getopt for the CP/M C library, as POSIX has it. CP/M gives the
 * command line in upper case, so a program that wants -v should also
 * take -V, or list both. */

#include <stdio.h>
#include <string.h>
#include <unistd.h>

char *optarg;
int optind = 1, opterr = 1, optopt;
static char *next;

int getopt(int argc, char *const argv[], const char *opts) __LIB
{
	const char *o;
	char c;

	optarg = NULL;
	if (!next || !*next) {
		if (optind >= argc || argv[optind][0] != '-' || !argv[optind][1])
			return -1;
		if (!strcmp(argv[optind], "--")) {
			optind++;
			return -1;
		}
		next = argv[optind] + 1;
	}
	c = *next++;
	o = strchr(opts, c);
	if (!o || c == ':') {
		optopt = c;
		if (opterr && *opts != ':')
			fprintf(stderr, "unknown option -%c\n", c);
		if (!*next)
			optind++;
		return '?';
	}
	if (o[1] == ':') {
		if (*next)
			optarg = next;
		else if (optind + 1 < argc)
			optarg = argv[++optind];
		else {
			optopt = c;
			next = NULL;
			optind++;
			if (*opts == ':')
				return ':';
			if (opterr)
				fprintf(stderr, "option -%c needs a value\n", c);
			return '?';
		}
		next = NULL;
		optind++;
	} else if (!*next)
		optind++;
	return c;
}
