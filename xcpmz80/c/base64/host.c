/*
 * base64_host - Linux counterpart to CP/M-68K BASE64.
 * Compress + base64 encode/decode for serial file transfer.
 *
 * Encode: base64_host file           (file -> LZSS -> base64 -> stdout)
 * Decode: base64_host -d file        (stdin -> base64 -> LZSS decompress -> file)
 *
 * The LZSS format is identical to the CP/M version:
 *   4 bytes big-endian uncompressed size, then flag-byte groups.
 *   Flag bit=1: literal. Flag bit=0: 2-byte match (4KB window, len 3-18).
 *
 * Typical workflow:
 *   Host->CP/M:  base64_host file.bin | send_to_serial
 *                On CP/M: BASE64 -D FILE.BIN, paste, '.'
 *   CP/M->Host:  capture serial output from BASE64 FILE.BIN
 *                base64_host -d file.bin < captured.txt
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===== LZSS (4KB window, match len 3-18) ===== */

#define WINSZ    4096
#define MINMATCH 3
#define MAXMATCH 18

static long lzss_compress(const unsigned char *in, long inlen,
                          unsigned char *out, long outmax)
{
    long ip = 0, op = 0;
    long flag_pos;
    int flag_bit;
    unsigned char flags;

    /* 4-byte big-endian uncompressed size */
    out[op++] = (inlen >> 24) & 0xFF;
    out[op++] = (inlen >> 16) & 0xFF;
    out[op++] = (inlen >>  8) & 0xFF;
    out[op++] =  inlen        & 0xFF;

    while (ip < inlen) {
        flag_pos = op++;
        flags = 0;

        for (flag_bit = 0; flag_bit < 8 && ip < inlen; flag_bit++) {
            int best_len = 0;
            long best_off = 0;
            long search_start = ip - WINSZ;
            long sp;

            if (search_start < 0) search_start = 0;

            for (sp = search_start; sp < ip; sp++) {
                int len = 0;
                while (len < MAXMATCH && ip + len < inlen &&
                       in[sp + len] == in[ip + len])
                    len++;
                if (len > best_len) {
                    best_len = len;
                    best_off = ip - sp;
                }
            }

            if (best_len >= MINMATCH) {
                int enc_len = best_len - MINMATCH;
                long enc_off = best_off - 1;
                out[op++] = (enc_len << 4) | ((enc_off >> 8) & 0x0F);
                out[op++] = enc_off & 0xFF;
                ip += best_len;
            } else {
                flags |= (1 << flag_bit);
                out[op++] = in[ip++];
            }
        }

        out[flag_pos] = flags;
    }

    return op;
}

static long lzss_decompress(const unsigned char *in, long inlen,
                            unsigned char *out, long outmax)
{
    long ip = 4, op = 0;
    long orig_size;

    orig_size = ((long)in[0] << 24) | ((long)in[1] << 16) |
                ((long)in[2] << 8)  |  (long)in[3];
    if (orig_size > outmax)
        return -1;

    while (op < orig_size && ip < inlen) {
        unsigned char flags = in[ip++];
        int bit;

        for (bit = 0; bit < 8 && op < orig_size && ip < inlen; bit++) {
            if (flags & (1 << bit)) {
                out[op++] = in[ip++];
            } else {
                unsigned char b1 = in[ip++];
                unsigned char b2 = in[ip++];
                int length = (b1 >> 4) + MINMATCH;
                long offset = ((b1 & 0x0F) << 8 | b2) + 1;
                int j;
                for (j = 0; j < length && op < orig_size; j++) {
                    out[op] = out[op - offset];
                    op++;
                }
            }
        }
    }

    return op;
}

/* ===== Base64 ===== */

static const char b64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static int b64val(int c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

/* ===== Encode: file -> compress -> base64 -> stdout ===== */

static int do_encode(const char *filename)
{
    FILE *f;
    unsigned char *filebuf, *compbuf;
    long filesz, compsz;
    unsigned char triple[3];
    int col, tpos;
    long i;

    f = fopen(filename, "rb");
    if (!f) { perror(filename); return 1; }

    fseek(f, 0, SEEK_END);
    filesz = ftell(f);
    fseek(f, 0, SEEK_SET);

    filebuf = malloc(filesz);
    compbuf = malloc(filesz + filesz / 8 + 256);  /* worst case: all literals */
    if (!filebuf || !compbuf) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    fread(filebuf, 1, filesz, f);
    fclose(f);

    compsz = lzss_compress(filebuf, filesz, compbuf, filesz + filesz / 8 + 256);

    fprintf(stderr, "%ld -> %ld bytes (%ld%%)\n",
            filesz, compsz, filesz > 0 ? (compsz * 100) / filesz : 0);

    /* Base64 encode to stdout */
    col = 0;
    tpos = 0;
    for (i = 0; i < compsz; i++) {
        triple[tpos++] = compbuf[i];
        if (tpos == 3) {
            putchar(b64[triple[0] >> 2]);
            putchar(b64[((triple[0] & 3) << 4) | (triple[1] >> 4)]);
            putchar(b64[((triple[1] & 0xF) << 2) | (triple[2] >> 6)]);
            putchar(b64[triple[2] & 0x3F]);
            col += 4;
            if (col >= 76) { putchar('\n'); col = 0; }
            tpos = 0;
        }
    }
    if (tpos > 0) {
        if (tpos < 3) triple[2] = 0;
        if (tpos < 2) triple[1] = 0;
        putchar(b64[triple[0] >> 2]);
        putchar(b64[((triple[0] & 3) << 4) | (triple[1] >> 4)]);
        putchar(tpos > 1 ? b64[((triple[1] & 0xF) << 2) | (triple[2] >> 6)] : '=');
        putchar(tpos > 2 ? b64[triple[2] & 0x3F] : '=');
        col += 4;
    }
    if (col > 0) putchar('\n');

    /* Terminator line for CP/M decode */
    putchar('.');
    putchar('\n');

    free(filebuf);
    free(compbuf);
    return 0;
}

/* ===== Decode: stdin -> base64 decode -> decompress -> file ===== */

static int do_decode(const char *filename)
{
    FILE *f;
    unsigned char *compbuf, *filebuf;
    long compsz, filesz, orig_size;
    unsigned char quad[4];
    int qpos, pads, c, v;

    /* First pass: base64 decode from stdin into compbuf.
     * Allocate generously; resize after. */
    long bufmax = 16 * 1024 * 1024;
    compbuf = malloc(bufmax);
    if (!compbuf) { fprintf(stderr, "Out of memory\n"); return 1; }

    compsz = 0;
    qpos = 0;
    pads = 0;

    while ((c = getchar()) != EOF) {
        /* Stop at '.' on a line by itself (but stdin usually just ends) */
        /* Skip CR/LF/whitespace */
        if (c == '\r' || c == '\n' || c == ' ' || c == '\t')
            continue;

        /* '.' at any point means end (CP/M terminator) */
        if (c == '.')
            break;

        if (c == '=') {
            quad[qpos++] = 0;
            pads++;
        } else {
            v = b64val(c);
            if (v < 0) continue;
            quad[qpos++] = v;
        }

        if (qpos == 4) {
            int nbytes = 3 - pads;
            if (nbytes >= 1 && compsz < bufmax)
                compbuf[compsz++] = (quad[0] << 2) | (quad[1] >> 4);
            if (nbytes >= 2 && compsz < bufmax)
                compbuf[compsz++] = (quad[1] << 4) | (quad[2] >> 2);
            if (nbytes >= 3 && compsz < bufmax)
                compbuf[compsz++] = (quad[2] << 6) | quad[3];

            if (pads) break;
            qpos = 0;
            pads = 0;
        }
    }

    if (compsz < 4) {
        fprintf(stderr, "No data received\n");
        free(compbuf);
        return 1;
    }

    /* Read original size from LZSS header to allocate output buffer */
    orig_size = ((long)compbuf[0] << 24) | ((long)compbuf[1] << 16) |
                ((long)compbuf[2] << 8)  |  (long)compbuf[3];

    fprintf(stderr, "Received %ld compressed bytes, original size %ld\n",
            compsz, orig_size);

    filebuf = malloc(orig_size);
    if (!filebuf) { fprintf(stderr, "Out of memory\n"); free(compbuf); return 1; }

    filesz = lzss_decompress(compbuf, compsz, filebuf, orig_size);
    free(compbuf);

    if (filesz < 0) {
        fprintf(stderr, "Decompression error\n");
        free(filebuf);
        return 1;
    }

    f = fopen(filename, "wb");
    if (!f) { perror(filename); free(filebuf); return 1; }
    fwrite(filebuf, 1, filesz, f);
    fclose(f);
    free(filebuf);

    fprintf(stderr, "%ld bytes written to %s\n", filesz, filename);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "base64_host - compressed file transfer (LZSS+base64)\n");
        fprintf(stderr, "Usage: base64_host file          (compress+encode to stdout)\n");
        fprintf(stderr, "       base64_host -d file        (decode+decompress stdin to file)\n");
        return 1;
    }

    if (argc >= 3 && strcmp(argv[1], "-d") == 0)
        return do_decode(argv[2]);
    else
        return do_encode(argv[1]);
}
