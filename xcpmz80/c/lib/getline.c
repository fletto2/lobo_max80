#include <_cconv.h>
/* getline and getdelim for the CP/M C library: a whole line in a
 * buffer from malloc, made larger as it fills */

#include <stdlib.h>
#include "cpmint.h"

long getdelim(char **line, size_t *n, int delim, FILE *f) __LIB
{
	size_t i = 0;
	int c;
	char *p;

	if (!*line || !*n) {
		*n = 80;
		if (!(*line = malloc(*n)))
			return -1;
	}
	while ((c = fgetc(f)) != EOF) {
		if (i + 2 > *n) {
			if (!(p = realloc(*line, *n * 2)))
				return -1;
			*line = p;
			*n *= 2;
		}
		(*line)[i++] = c;
		if (c == delim)
			break;
	}
	if (!i)
		return -1;
	(*line)[i] = 0;
	return i;
}

long getline(char **line, size_t *n, FILE *f) __LIB
{
	return getdelim(line, n, '\n', f);
}
