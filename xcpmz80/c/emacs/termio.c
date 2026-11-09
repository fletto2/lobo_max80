/*
 * CP/M terminal I/O for MicroEMACS 3.6, agfa9000's CP/M-68K version on
 * the C library's bdos() for xcpmz80:
 *   Function 6:  Direct console I/O (no wait, no echo)
 *   Function 11: Console status
 */

#include "estruct.h"
#include "edef.h"
#include <cpm.h>

/* Output buffer for efficiency */
#define OBUF_SIZE 256
static char obuf[OBUF_SIZE];
static int obuf_len = 0;

static void flush_obuf(void)
{
    int i;
    for (i = 0; i < obuf_len; i++)
        bdos(6, obuf[i] & 0xFF);
    obuf_len = 0;
}

/*
 * ttopen - Initialize terminal. No-op for CP/M-68K.
 */
int ttopen(void)
{
    return (TRUE);
}

/*
 * ttclose - Restore terminal. No-op for CP/M-68K.
 */
int ttclose(void)
{
    return (TRUE);
}

/*
 * ttputc - Write a character to the display.
 * Buffered for performance.
 */
int ttputc(int c)
{
    obuf[obuf_len++] = c;
    if (obuf_len >= OBUF_SIZE)
        flush_obuf();
    return (c);
}

/*
 * ttflush - Flush output buffer.
 */
int ttflush(void)
{
    flush_obuf();
    return (TRUE);
}

/*
 * ttgetc - Read a character from the terminal.
 * Uses BDOS function 6 (direct I/O) to avoid echo.
 */
int ttgetc(void)
{
    int c;

    ttflush();  /* flush pending output first */

    /* Poll with BDOS 6, 0xFF until a character arrives */
    while ((c = bdos(6, 0xFF)) == 0)
        ;
    return (c & 0xFF);
}

#if TYPEAH
/*
 * typahead - Check if keyboard input is waiting.
 * Uses BDOS function 11 (console status).
 */
int typahead(void)
{
    return (bdos(11, 0) != 0);
}
#endif
