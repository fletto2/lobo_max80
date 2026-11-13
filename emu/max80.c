/*
 * Lobo MAX-80 emulator, in an SDL2 window or a terminal.
 *
 * The machine as read from the boot ROM source, Lobo's CP/M 2.2 BIOS,
 * the Technical Reference Manual and the schematics.
 *
 * Usage: max80 [-r rom] [-a|-b|-c|-d disk.imd] [-h hard.img] [-n drive]
 *              [-R drive] [-3 drive] [-w drive:file] [-D dips] [-f] [-T]
 *              [-k keys] [-e text] [-K] [-s sound.wav]
 *              [-t seconds [-p frame.pgm]] [-l printer.txt]
 *              [-o|-i|-I ch:file] [-S ch] [-F spec] [-x port]
 *              [-m 128|64|64f] [-C] [-B] [-V T] [-L] [-M] [-G fdc.log]
 *              [-g [-N name]]
 *
 *   -r  boot ROM, default ../reference/rom/max80.e12
 *   -a  drive A (and -b B, -c C, -d D), .imd files, never written to
 *   -h  a SASI hard disk, a raw image of 512-byte blocks, never written
 *       to. -w h:new.img saves it, -D 7 boots from it
 *   -n  a blank, unformatted disk in this drive (a to d), for FORMAT
 *   -R  write-protect this drive's disk (a to d): writes fail
 *   -3  this drive (a to d) is 3.5-inch, 300 rpm: on the 8-inch connector
 *       a 1.44M drive, 12500 bytes a track. A disk with 500 kbit/s tracks
 *       past cylinder 76 is taken as one without it
 *   -w  at exit, write a drive's disk to a new .imd, such as b:new.imd,
 *       never over or beside a loaded image
 *   -D  the DIP switch byte, default 2: boot from an 8-inch floppy. 1
 *       boots a 5-inch floppy, 0 makes the ROM beep for a boot device
 *   -f  run as fast as the host allows, not at 5 MHz
 *   -k  type these keys (\r is Enter, \e ESC, \U \D \L \R the arrows,
 *       \1 to \4 F1 to F4, \B BREAK, \E Enter with no wait, \P a
 *       second's pause) at the prompt, waiting for the prompt again
 *       after each Enter
 *   -e  the prompt, default "A>", or several such as "A>|B>"
 *   -K  type letters for an OS that boots with Caps Lock on, so -k
 *       scripts keep their case
 *   -T  draw in the terminal as text, not in a window
 *   -t  headless: run this many emulated seconds, print the screen, exit
 *   -p  with -t, also save the frame as dots, a PGM image
 *   -s  record the beeps to a WAV file, in emulated time
 *   -l  a printer on the parallel port, what it prints goes to this file
 *   -o  what a serial channel (a or b) sends goes to a file, as a:out.txt
 *   -i  a serial channel receives a file's bytes, as a:in.txt.
 *       a:in.txt@8 starts them 8 emulated seconds in, for a driver that
 *       must be set up before a byte comes. The remote waits
 *       while the SIO's FIFO is full, nothing is lost
 *   -I  the same, but the remote never waits: bytes not read in time are
 *       lost, as with no handshake
 *   -F  a bit stuck at 0 when the CPU reads video RAM (v), font RAM (f)
 *       or main RAM (m, offsets 0-1FFFF over A1, A2, B1, B2), as v:123:4
 *       for offset 123h bit 4. c:3:2 makes chunk 3 (B2) decode as chunk
 *       2 (B1). d:2:0 holds FDC status bit 0, busy, at 1 from emulated
 *       second 2 on, after the boot. For the diagnostic. s:3:0 hangs
 *       the SASI drive on its 3rd command (hex): it keeps BSY and never
 *       asks for a byte, until a bus reset
 *   -x  a card on the expansion bus at this port, in hex: it reads back
 *       the last byte written to it, 00h at the start. Every other port
 *       reads FFh. For the diagnostic
 *   -m  the RAM fitted: 128 (default), 64 with bank B missing and its
 *       chunks reading FFh, or 64f, where they read back the last byte
 *       written to them, as a floating bus might. For the diagnostic
 *   -S  nothing plugged into this serial channel (a or b): CTS and DCD
 *       read off, so auto enables hold its bytes
 *   -C  hold the clock chip's TIME SET button down for the whole run,
 *       so programs can set the clock
 *   -B  run the CRTC's counters a character at a time and draw each
 *       character as the beam passes it, so what changes while the beam
 *       is in the picture shows. Not measured against a machine
 *   -V  each CPU access to video or font RAM stretches the clock by 0
 *       to this many T-states, picked at random, a stand-in for the
 *       stretch the TRM calls unpredictable (TS-3)
 *   -L  at exit, print how many FDC commands had Lost Data
 *   -M  give the drives their mechanics: sectors on a turning track,
 *       bytes at the data rate, step times, head settle and motor
 *       spin-up, with a summary at exit
 *   -G  log each FDC command, with its emulated time, to this file
 *   -g  debug sockets, Linux only: /tmp/max80.sock answers with
 *       the registers, /tmp/max80_mem.sock takes "ADDR LEN [chunk]" in
 *       hex, chunk A1, A2, B1, B2 or V for video RAM, and answers with
 *       a dump, or "screen" and answers with the screen as text, or
 *       "disk b NEW.imd" and puts that disk in drive B (any of a to d)
 *       in place of the one there, as a disk swapped by hand,
 *       /tmp/max80_kbd.sock types what is written to it. Try
 *       socat - /tmp/max80.sock
 *   -N  with -g, an instance name appended to each socket's name,
 *       -N 2 opens /tmp/max80_2.sock, /tmp/max80_mem_2.sock and
 *       /tmp/max80_kbd_2.sock, so two emulators can run at once
 *
 * Interactive: Ctrl-] quits. Built without SDL2, the terminal is the
 * only display.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
#include <libgen.h>
#include <sys/stat.h>
#ifdef __linux__
#include <strings.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#endif
#include "z80.h"
#ifdef HAVE_SDL
#include <SDL.h>
#endif

#define CPU_HZ 5066667		/* 15.2 MHz / 3, TRM TS-3 */
#define TICK_T (CPU_HZ / 60)	/* one pass of the main loop, a frame */
/* The tick interrupt, 8.00 MHz / 2^17 = 61.035 Hz: tick n is
 * due at cycle n * IRQ_NUM / IRQ_DEN */
#define IRQ_NUM (CPU_HZ * 131072ULL)
#define IRQ_DEN 8000000ULL
/* Tick n's cycle, and the ticks before cycle c, in 128 bits: n * IRQ_NUM
   passes 2^64 after about 5 emulated days */
static unsigned long long tick_cycle(unsigned long long n)
{
	return (unsigned long long)((unsigned __int128)n * IRQ_NUM / IRQ_DEN);
}
static unsigned long long tick_count(unsigned long long c)
{
	return (unsigned long long)((unsigned __int128)c * IRQ_DEN / IRQ_NUM);
}

/* ---- Disks: an .imd file held in memory ---- */

struct sector {
	uint8_t id;
	uint8_t deleted;
	uint8_t missing;	/* IMD had no data for it, read as E5h */
	uint8_t bad;		/* IMD marks it as read with a data error */
	int size;
	uint8_t *data;
};

struct track {
	int present;
	int mfm;
	int fast;	/* 500 kbit/s MFM or 250 FM: an 8-inch drive */
	int cyl_id, head_id;
	int nsec;
	struct sector *sec;
	int rot;		/* next sector under the head, for READ ADDRESS */
};

#define MAXCYL 84

struct disk {
	int loaded;
	const char *path;	/* the .imd it came from, NULL for -n */
	const char *save;	/* -w: written here at exit */
	int wprot;		/* -R: the disk is write-protected */
	int three;		/* -3: a 3.5-inch drive, 300 rpm */
	int one;		/* single sided, SYSFLG bit 4 on the 8-inch connector */
	struct track trk[MAXCYL][2];
};

static int load_imd(struct disk *d, const char *path)
{
	FILE *f = fopen(path, "rb");
	long n;
	uint8_t *b;
	long i;

	if (!f) {
		perror(path);
		return -1;
	}
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	b = malloc(n);
	if (!b || fread(b, 1, n, f) != (size_t)n) {
		fprintf(stderr, "%s: read error\n", path);
		fclose(f);
		return -1;
	}
	fclose(f);
	for (i = 0; i < n && b[i] != 0x1a; i++)
		;
	i++;
	while (i + 5 <= n) {
		int mode = b[i], cyl = b[i + 1], head = b[i + 2];
		int ns = b[i + 3], size;
		uint8_t *smap, *cmap = NULL, *hmap = NULL;
		struct track *t;

		if (b[i + 4] > 6) {	/* FFh: a size table, not handled */
			fprintf(stderr, "%s: sector size code %02x\n", path,
			    b[i + 4]);
			return -1;
		}
		size = 128 << b[i + 4];

		i += 5;
		smap = b + i;
		i += ns;
		if (head & 0x80) {
			cmap = b + i;
			i += ns;
		}
		if (head & 0x40) {
			hmap = b + i;
			i += ns;
		}
		if (cyl >= MAXCYL || (head & 1) > 1) {
			fprintf(stderr, "%s: track %d out of range\n", path, cyl);
			return -1;
		}
		if (!ns)		/* a track with no sectors: as none */
			continue;
		t = &d->trk[cyl][head & 1];
		t->present = 1;
		t->mfm = mode >= 3;
		t->fast = mode % 3 == 0;
		t->cyl_id = cmap ? cmap[0] : cyl;
		t->head_id = hmap ? hmap[0] : (head & 1);
		t->nsec = ns;
		t->sec = calloc(ns, sizeof(struct sector));
		for (int s = 0; s < ns; s++) {
			int kind = b[i++];
			struct sector *sp = &t->sec[s];
			sp->id = smap[s];
			sp->size = size;
			sp->data = malloc(size);
			sp->missing = kind == 0;
			sp->bad = kind >= 5;
			if (kind == 0)
				memset(sp->data, 0xe5, size);
			else if (kind & 1) {
				memcpy(sp->data, b + i, size);
				i += size;
			} else
				memset(sp->data, b[i++], size);
			sp->deleted = kind == 3 || kind == 4 || kind == 7 || kind == 8;
		}
	}
	free(b);
	/* 500 kbit/s tracks past cylinder 76: no 8-inch disk has them, so a
	   1.44M disk, in a 3.5-inch drive */
	for (int c = 77; c < MAXCYL; c++)
		if (d->trk[c][0].present && d->trk[c][0].fast)
			d->three = 1;
	/* no side 1: a single sided disk, as an 8-inch drive's 2SIDED line
	   says */
	d->one = 1;
	for (int c = 0; c < MAXCYL; c++)
		if (d->trk[c][1].present)
			d->one = 0;
	d->loaded = 1;
	d->path = path;
	return 0;
}

/*
 * A disk as an .imd file. IMD modes 0-2 are FM at 500, 300 and 250
 * kbit/s, 3-5 MFM, and the 8-inch rates are 500. A sector filled with
 * one byte is stored compressed, as ImageDisk does, and the no-data and
 * data-error marks the source had are kept unless the sector was
 * written. A track whose sectors differ in size cannot be stored.
 */
/* The host's time, or SOURCE_DATE_EPOCH's in UTC when it is set, so a
 * build that writes a disk through the emulator makes the same bytes
 * each time: the IMD header and the clock chip's start */
static struct tm *host_time(void)
{
	static struct tm t;
	const char *s = getenv("SOURCE_DATE_EPOCH");
	char *end;
	time_t now;

	if (s && *s) {
		long long v = strtoll(s, &end, 10);
		if (!*end && v >= 0 && v <= 4102444799LL) {	/* to 2099 */
			now = (time_t)v;
			t = *gmtime(&now);
			return &t;
		}
	}
	now = time(NULL);
	t = *localtime(&now);
	return &t;
}

static int save_imd(const struct disk *d, const char *path)
{
	FILE *f = fopen(path, "wb");
	struct tm *tm = host_time();
	const char *src = d->path ? strrchr(d->path, '/') : NULL;
	int err = 0;

	if (!f) {
		perror(path);
		return 1;
	}
	fprintf(f, "IMD 1.18: %02d/%02d/%04d %02d:%02d:%02d\r\n"
	    "Written by the lobo_max80 emulator from %s\r\n\x1a",
	    tm->tm_mday, tm->tm_mon + 1, tm->tm_year + 1900,
	    tm->tm_hour, tm->tm_min, tm->tm_sec,
	    d->path ? (src ? src + 1 : d->path) : "a blank disk");
	for (int c = 0; c < MAXCYL; c++)
		for (int h = 0; h < 2; h++) {
			const struct track *t = &d->trk[c][h];
			if (!t->present)
				continue;
			int size = t->sec[0].size, code = 0;
			while ((128 << code) < size)
				code++;
			for (int s = 1; s < t->nsec; s++)
				if (t->sec[s].size != size) {
					fprintf(stderr, "%s: cylinder %d head %d has mixed "
					    "sector sizes, left out\n", path, c, h);
					err = 1;
					goto next;
				}
			int cmap = t->cyl_id != c, hmap = t->head_id != h;
			fputc(t->mfm * 3 + (t->fast ? 0 : 2), f);
			fputc(c, f);
			fputc(h | (cmap ? 0x80 : 0) | (hmap ? 0x40 : 0), f);
			fputc(t->nsec, f);
			fputc(code, f);
			for (int s = 0; s < t->nsec; s++)
				fputc(t->sec[s].id, f);
			for (int s = 0; cmap && s < t->nsec; s++)
				fputc(t->cyl_id, f);
			for (int s = 0; hmap && s < t->nsec; s++)
				fputc(t->head_id, f);
			for (int s = 0; s < t->nsec; s++) {
				const struct sector *sp = &t->sec[s];
				int same = 1;
				if (sp->missing) {
					fputc(0, f);
					continue;
				}
				for (int k = 1; k < size && same; k++)
					same = sp->data[k] == sp->data[0];
				int kind = (same ? 2 : 1) + (sp->deleted ? 2 : 0) + (sp->bad ? 4 : 0);
				fputc(kind, f);
				if (same)
					fputc(sp->data[0], f);
				else
					fwrite(sp->data, 1, size, f);
			}
		next:;
		}
	if (fclose(f) != 0) {
		perror(path);
		return 1;
	}
	return err;
}

/* ---- Floppy controller: MB8876, WD1791 commands ---- */

static z80 cpu;
static struct disk disks[4];

/*
 * Data moves at disk speed. A byte the CPU has not taken when the next
 * one comes is lost: the command carries on and ends with Lost Data, as
 * on the chip. Each byte waits a byte time from the CPU's last read or
 * write, so a CPU that keeps up never sees the clock. A read sector's
 * first byte comes by itself, some time after the command (FIND_T, in
 * place of the wait for the sector, not the same each time), and has a
 * byte time too. Other first bytes wait FIRST_T. A byte is 16 us MFM or 32 us FM at the 2 MHz clock of the
 * 8-inch connector, twice that at the 5-inch connector's 1 MHz
 * (Appendix D p.13).
 */
#define FIRST_T (CPU_HZ / 500)
#define FIND_T (2000 + cpu.cycles % 1024)
#define BYTE_T ((fdc.dd ? CPU_HZ / 62500 : CPU_HZ / 31250) * (fdc.eight ? 1 : 2))
/* 8-inch drives turn at 360 rpm, the index pulse is about 2 ms. A
   3.5-inch drive on the 8-inch connector turns at 300. */
#define REV_T (fdc.eight && !disks[fdc.drive].three ? CPU_HZ / 6 : CPU_HZ / 5)
#define INDEX_T (CPU_HZ / 500)

static unsigned long long motor_until;	/* 5-inch motors turn until then */

/*
 * -M gives the drives their mechanics, with the CPU running all
 * the while. Without it a sector is found at once and its bytes come as
 * fast as the CPU takes them. A track turns under the head from the
 * index pulse on, its sectors evenly spread in the image's order. A
 * command waits for its sector's ID to come round, a byte comes each
 * byte time from the start of the data field, and INTRQ comes after the
 * CRC. A sector that is not there takes 5 turns. A step takes its rate,
 * doubled at the 5-inch connector's 1 MHz, the head settles for SETTLE_T
 * after the last one, and a stopped 5-inch motor is up to speed after
 * SPIN_T. Those two are typical of the drives, not measured.
 */
#define SETTLE_T (CPU_HZ / 1000 * 15)
#define SPIN_T (CPU_HZ / 1000 * 500)
#define IDGAP 48	/* bytes from an ID's start to its first data byte */
static int mech;
static unsigned long long head_ok;	/* no ID can be read before this */
static unsigned long long motor_up;	/* nor on a 5-inch disk before this */
static FILE *fdlog;			/* -G, a line for each command */
static unsigned long mech_secs, mech_steps;
static unsigned long long mech_wait, mech_first, mech_last;

static struct {
	uint8_t status, track, sector, data;
	int drive, side, dd, eight;
	int pos[4];		/* head cylinder per drive */
	int dir;
	int busy, drq, intrq, type1, head_loaded;
	uint8_t *buf;
	int len, idx, writing, multi, lost;
	int wtrack;		/* the command is write track */
	int wdel;		/* write sector with the deleted data mark */
	unsigned long long deadline;	/* T-state the pending byte is lost */
	unsigned long long drq_at;	/* T-state a read's first byte comes */
	unsigned long long t0;		/* -M: T-state of the data's first byte */
	unsigned long long first_dl;	/* -M: the first byte's deadline, if not 0 */
	unsigned long long done_at;	/* -M: T-state the command ends */
	unsigned long long step_at;	/* -M: T-state a type I command ends */
	uint8_t done_status;
	int fi;			/* Force Interrupt's I3-I0 still waiting */
	int d8;			/* INTRQ held by D8 until a D0 (WD179x) */
	uint8_t t1err;		/* type I seek error (S4), kept till the
				   next command as type1_status rebuilds */
	int side_cmp;		/* S/C: the ID's head must be this, or -1 */
	struct sector *cur;	/* the sector being read or written */
	unsigned long long fi_index;	/* the next index pulse */
	uint8_t idbuf[6];
} fdc = { .drive = -1, .dir = 1 };

static struct track *cur_track(void)
{
	if (fdc.drive < 0 || !disks[fdc.drive].loaded)
		return NULL;
	struct track *t = &disks[fdc.drive].trk[fdc.pos[fdc.drive]][fdc.side];
	/* MLATCH bit 5 sets the data rate, a track read at the wrong one has no IDs */
	if (!t->present || t->mfm != fdc.dd || t->fast != fdc.eight)
		return NULL;
	return t;
}

/*
 * Write track and read track. A track holds this many bytes: 8-inch
 * drives turn at 360 rpm, 5-inch ones at 300 rpm at half the data rate.
 */
#define TRACK_MAX 12500	/* a 3.5-inch 1.44M track */
static uint8_t trackbuf[TRACK_MAX];

static int track_bytes(void)
{
	if (fdc.eight && !disks[fdc.drive].three)
		return fdc.dd ? 10416 : 5208;
	if (fdc.eight)		/* a 3.5-inch drive, 300 rpm */
		return fdc.dd ? 12500 : 6250;
	return fdc.dd ? 6250 : 3125;
}

/* CRC-CCITT as the FDC computes it, preset to FFFFh */
static uint16_t crc16(uint16_t crc, const uint8_t *p, int n)
{
	while (n--) {
		crc ^= *p++ << 8;
		for (int i = 0; i < 8; i++)
			crc = crc & 0x8000 ? crc << 1 ^ 0x1021 : crc << 1;
	}
	return crc;
}

static void free_track(struct track *t)
{
	for (int i = 0; i < t->nsec; i++)
		free(t->sec[i].data);
	free(t->sec);
	memset(t, 0, sizeof(*t));
}

/*
 * The bytes a write track command took, turned into sectors as the FDC
 * lays them down. In MFM, F5h writes the A1h sync and an ID or data mark
 * counts only after one. In FM every F8h-FEh is a mark. F7h writes the
 * CRC. An ID is FEh, cylinder, head, sector, size code and F7h. Its
 * data field is the next F8h (deleted) or FBh mark within 64 bytes,
 * 128 << size bytes, and F7h. Gaps are not kept.
 */
static void track_from_stream(struct track *t, const uint8_t *b, int n)
{
	struct sector sec[64];
	int ns = 0, cyl = 0, head = 0;

	memset(sec, 0, sizeof(sec));

	for (int i = 0; i + 6 < n && ns < 64; i++) {
		if (b[i] != 0xfe || (fdc.dd && (i == 0 || b[i - 1] != 0xf5)))
			continue;
		int size = 128 << (b[i + 4] & 3), j;
		for (j = i + 6; j < n && j < i + 6 + 64; j++)
			if ((b[j] == 0xfb || b[j] == 0xf8) && (!fdc.dd || b[j - 1] == 0xf5))
				break;
		if (j >= n || j >= i + 6 + 64 || j + 1 + size > n)
			continue;
		if (ns == 0) {
			cyl = b[i + 1];
			head = b[i + 2];
		}
		sec[ns].id = b[i + 3];
		sec[ns].deleted = b[j] == 0xf8;
		sec[ns].size = size;
		sec[ns].data = malloc(size);
		memcpy(sec[ns].data, b + j + 1, size);
		ns++;
		i = j + size;
	}
	free_track(t);
	if (!ns)
		return;		/* no IDs: the track reads as unformatted */
	t->present = 1;
	t->mfm = fdc.dd;
	t->fast = fdc.eight;
	t->cyl_id = cyl;
	t->head_id = head;
	t->nsec = ns;
	t->sec = malloc(ns * sizeof(struct sector));
	memcpy(t->sec, sec, ns * sizeof(struct sector));
}

/* A track as read track returns it: IBM gaps and marks with real CRCs */
static int stream_from_track(const struct track *t, uint8_t *b, int max)
{
	int n = 0, gap = fdc.dd ? 0x4e : 0xff, sync = fdc.dd ? 12 : 6;
#define PUT(v) do { if (n < max) b[n++] = (v); } while (0)
#define RUN(v, k) do { for (int r_ = 0; r_ < (k); r_++) PUT(v); } while (0)

	RUN(gap, fdc.dd ? 80 : 40);
	for (int s = 0; t && s < t->nsec; s++) {
		const struct sector *sp = &t->sec[s];
		int code = sp->size == 128 ? 0 : sp->size == 256 ? 1 : sp->size == 512 ? 2 : 3;
		uint8_t id[8] = { 0xa1, 0xa1, 0xa1, 0xfe, t->cyl_id, t->head_id, sp->id, code };
		uint8_t mark[4] = { 0xa1, 0xa1, 0xa1, sp->deleted ? 0xf8 : 0xfb };
		int pre = fdc.dd ? 0 : 3;	/* FM has no A1h syncs */
		uint16_t crc;

		RUN(0, sync);
		for (int k = pre; k < 8; k++)
			PUT(id[k]);
		crc = crc16(0xffff, id + pre, 8 - pre);
		PUT(crc >> 8);
		PUT(crc & 0xff);
		RUN(gap, fdc.dd ? 22 : 11);
		RUN(0, sync);
		for (int k = pre; k < 4; k++)
			PUT(mark[k]);
		crc = crc16(crc16(0xffff, mark + pre, 4 - pre), sp->data, sp->size);
		if (sp->bad)	/* read with a data error: its CRC fails */
			crc ^= 0xffff;
		for (int k = 0; k < sp->size; k++)
			PUT(sp->data[k]);
		PUT(crc >> 8);
		PUT(crc & 0xff);
		RUN(gap, fdc.dd ? 24 : 12);
	}
	while (n < max)
		PUT(gap);
#undef PUT
#undef RUN
	return n;
}

static void fdc_done(uint8_t status)
{
	fdc.busy = 0;
	fdc.drq = 0;
	fdc.drq_at = 0;
	fdc.intrq = 1;
	fdc.status = status | (fdc.lost ? 0x04 : 0);
	fdc.buf = NULL;
}

/*
 * The 8-inch and 5-inch drives hang on two connectors, picked by MLATCH
 * bit 5, with the same drive selects. A disk is on the connector of its
 * kind, from its tracks: 8-inch tracks are 500 kbit/s MFM or 250 FM. A
 * blank one (-n), with no track yet, is on both, so either can format
 * it.
 */
static int on_connector(void)
{
	if (fdc.drive < 0 || !disks[fdc.drive].loaded)
		return 0;
	for (int c = 0; c < MAXCYL; c++)
		for (int h = 0; h < 2; h++)
			if (disks[fdc.drive].trk[c][h].present)
				return disks[fdc.drive].trk[c][h].fast == fdc.eight;
	return 1;
}

/* A disk on the connector that turns: a 5-inch one only while its motor
   timer runs (TS-8, TS-32). It gives index pulses and IDs. */
static int turning(void)
{
	return on_connector() && (fdc.eight || cpu.cycles < motor_until);
}

/*
 * The 8-inch connector has READY. The 5-inch one has none, so the FDC
 * sees ready always (TRM, schematics): with no disk there a read
 * waits for an index pulse that never comes, until a force interrupt.
 */
static int fdc_ready(void)
{
	return fdc.eight ? on_connector() : 1;
}

static void type1_status(void)
{
	uint8_t s = 0;
	if (!fdc_ready())
		s |= 0x80;
	if (fdc.head_loaded)
		s |= 0x20;
	if (turning() && cpu.cycles % REV_T < INDEX_T)
		s |= 0x02;
	if (on_connector() && fdc.pos[fdc.drive] == 0)
		s |= 0x04;
	if (on_connector() && disks[fdc.drive].wprot)
		s |= 0x40;
	fdc.status = s | fdc.t1err;
}

static struct sector *find_sector(void)
{
	struct track *t = cur_track();
	if (!t || t->cyl_id != fdc.track)
		return NULL;
	if (fdc.side_cmp >= 0 && (t->head_id & 1) != fdc.side_cmp)
		return NULL;	/* side compare, Appendix D p.6 */
	for (int i = 0; i < t->nsec; i++)
		if (t->sec[i].id == fdc.sector)
			return &t->sec[i];
	return NULL;
}

/* -M: the T-state the ID of the track's sector I next comes to the head */
static unsigned long long next_id(struct track *t, int i)
{
	unsigned long long rev = REV_T, from = cpu.cycles;

	if (from < head_ok)
		from = head_ok;
	if (!fdc.eight && from < motor_up)
		from = motor_up;
	return from + (i * (rev / t->nsec) + rev - from % rev) % rev;
}

static void fdc_start_sector(void)
{
	struct sector *s = find_sector();
	/* IMD's "data unavailable" sector has an ID but no data field to
	   read: record not found */
	if (!s || (s->missing && !fdc.writing)) {
		if (mech) {	/* the FDC gives up after 5 index pulses */
			fdc.buf = NULL;
			fdc.drq = 0;
			fdc.status = 0x01;
			fdc.done_status = 0x10;
			fdc.done_at = cpu.cycles + 5 * REV_T;
			return;
		}
		fdc_done(0x10);	/* record not found */
		return;
	}
	fdc.cur = s;
	if (fdc.writing) {
		s->deleted = fdc.wdel;
		s->missing = s->bad = 0;
	}
	fdc.buf = s->data;
	fdc.len = s->size;
	fdc.idx = 0;
	if (mech) {
		struct track *t = cur_track();
		unsigned long long id = next_id(t, s - t->sec);

		mech_wait += id - cpu.cycles;
		mech_secs++;
		fdc.drq = 0;
		fdc.t0 = id + IDGAP * BYTE_T;
		/* a write's first DRQ comes just past the ID, 22 bytes to
		   answer it in (Appendix D); the data field follows */
		fdc.drq_at = fdc.writing ? id + 12 * BYTE_T : fdc.t0;
		fdc.first_dl = fdc.writing ? fdc.t0 : 0;
	} else if (fdc.writing) {
		fdc.drq = 1;
		fdc.deadline = cpu.cycles + FIRST_T;
	} else {
		fdc.drq = 0;
		fdc.drq_at = cpu.cycles + FIND_T;
	}
	fdc.status = 0x03 | (!fdc.writing && s->deleted ? 0x20 : 0);
}

static void fdc_command(uint8_t cmd)
{
	if (fdlog)
		fprintf(fdlog, "%.4f cmd %02x drive %d cyl %d side %d track %d sector %d\n",
		    (double)cpu.cycles / CPU_HZ, cmd, fdc.drive,
		    fdc.drive >= 0 ? fdc.pos[fdc.drive] : 0, fdc.side, fdc.track, fdc.sector);
	if (!mech_first)
		mech_first = cpu.cycles;
	mech_last = cpu.cycles;
	if (!fdc.d8)		/* after D8 only D0 and then a read or */
		fdc.intrq = 0;	/* a command clears it */
	fdc.t1err = 0;
	fdc.lost = 0;
	fdc.drq_at = 0;
	fdc.done_at = 0;
	fdc.step_at = 0;
	fdc.first_dl = 0;
	fdc.fi = 0;
	fdc.cur = NULL;
	fdc.side_cmp = -1;
	if ((cmd & 0xf0) == 0xd0) {	/* force interrupt */
		fdc.busy = fdc.drq = fdc.wtrack = 0;
		fdc.buf = NULL;
		fdc.type1 = 1;
		type1_status();
		/* Appendix D p.6: I3 at once, I2 at each index pulse, I1 on
		   ready to not ready, I0 on not ready to ready. A status read
		   leaves INTRQ set after one of these (p.5). */
		fdc.fi = cmd & 0x0f;
		if (!fdc.fi)
			fdc.d8 = 0;
		if (cmd & 0x08) {
			fdc.intrq = 1;
			fdc.d8 = 1;
		}
		fdc.fi_index = fdc.drive >= 0 ? (cpu.cycles / REV_T + 1) * REV_T : 0;
		return;
	}
	if (!(cmd & 0x80)) {	/* type I: restore, seek, step */
		int d = fdc.drive, move = 0, steps = 0;
		fdc.type1 = 1;
		fdc.head_loaded = (cmd & 0x08) != 0;	/* h = 0 unloads it */
		/* The FDC has no drive select, so the track register moves
		   with no drive selected too */
		switch (cmd >> 4) {
		case 0: fdc.track = 0; break;
		case 1: move = fdc.data - fdc.track; fdc.track = fdc.data; break;
		default:
			if ((cmd >> 5) == 2)
				fdc.dir = 1;
			else if ((cmd >> 5) == 3)
				fdc.dir = -1;
			move = fdc.dir;
			if (cmd & 0x10)
				fdc.track += fdc.dir;
			break;
		}
		if (d >= 0) {
			int to = (cmd >> 4) == 0 ? 0 : fdc.pos[d] + move;
			if (to < 0)
				to = 0;
			if (to >= MAXCYL)
				to = MAXCYL - 1;
			steps = abs(to - fdc.pos[d]);
			fdc.pos[d] = to;
		}
		/* no drive there: a restore gives up after 255 steps */
		if (!on_connector() && (cmd >> 4) == 0)
			fdc.t1err = 0x10;
		type1_status();
		if (mech && steps) {
			static const int rate[4] = { 3, 6, 10, 15 };
			unsigned long long t = (unsigned long long)steps *
			    rate[cmd & 3] * (fdc.eight ? 1 : 2) * (CPU_HZ / 1000);

			mech_steps += steps;
			fdc.busy = 1;
			fdc.step_at = cpu.cycles + t;
			head_ok = fdc.step_at + SETTLE_T;
			return;
		}
		fdc.busy = 0;
		fdc.intrq = 1;
		return;
	}
	fdc.type1 = 0;
	fdc.head_loaded = 1;
	if (!fdc_ready()) {
		fdc_done(0x80);
		return;
	}
	if (!turning()) {	/* 5-inch, no disk or stopped: busy until forced */
		fdc.busy = 1;
		fdc.drq = 0;
		fdc.buf = NULL;
		fdc.wtrack = 0;
		fdc.status = 0x01;
		return;
	}
	/* A write on a write-protected disk ends at once, status bit 6 */
	if (((cmd >> 5) == 5 || (cmd & 0xf0) == 0xf0) && disks[fdc.drive].wprot) {
		fdc_done(0x40);
		return;
	}
	switch (cmd >> 5) {
	case 4:			/* read sector */
	case 5:			/* write sector */
		fdc.busy = 1;
		fdc.writing = cmd & 0x20;
		fdc.wdel = fdc.writing && (cmd & 1);	/* a0: F8h mark */
		fdc.multi = cmd & 0x10;
		fdc.side_cmp = cmd & 0x02 ? (cmd >> 3) & 1 : -1;
		fdc_start_sector();
		break;
	case 6: {		/* read address */
		struct track *t = cur_track();
		if (!t) {
			fdc_done(0x10);
			break;
		}
		if (mech) {	/* the next ID to come round */
			unsigned long long best = ~0ULL;
			for (int i = 0; i < t->nsec; i++)
				if (next_id(t, i) < best) {
					best = next_id(t, i);
					t->rot = i;
				}
			fdc.t0 = best + 4 * BYTE_T;
		}
		struct sector *s = &t->sec[t->rot++ % t->nsec];
		int code = s->size == 128 ? 0 : s->size == 256 ? 1 : s->size == 512 ? 2 : 3;
		uint8_t id[8] = { 0xa1, 0xa1, 0xa1, 0xfe, t->cyl_id, t->head_id, s->id, code };
		int pre = fdc.dd ? 0 : 3;	/* FM has no A1h syncs */
		uint16_t crc = crc16(0xffff, id + pre, 8 - pre);
		memcpy(fdc.idbuf, id + 4, 4);	/* the ID field with its CRC */
		fdc.idbuf[4] = crc >> 8;
		fdc.idbuf[5] = crc & 0xff;
		fdc.buf = fdc.idbuf;
		fdc.len = 6;
		fdc.idx = 0;
		fdc.writing = 0;
		fdc.multi = 0;
		fdc.busy = 1;
		fdc.drq = !mech;
		fdc.deadline = cpu.cycles + FIRST_T;
		fdc.drq_at = mech ? fdc.t0 : 0;
		fdc.status = 0x03;
		fdc.sector = t->cyl_id;
		break;
	}
	case 7:			/* read track (E0h), write track (F0h) */
		fdc.len = track_bytes();
		fdc.idx = 0;
		fdc.writing = cmd & 0x10;
		fdc.wtrack = fdc.writing;
		fdc.multi = 0;
		if (!fdc.writing)
			stream_from_track(cur_track(), trackbuf, fdc.len);
		else
			memset(trackbuf, 0, fdc.len);
		fdc.buf = trackbuf;
		fdc.busy = 1;
		fdc.drq = !mech;
		fdc.deadline = cpu.cycles + FIRST_T;
		if (mech) {	/* from the next index pulse */
			fdc.t0 = (cpu.cycles / REV_T + 1) * REV_T;
			fdc.drq_at = fdc.t0;
		}
		fdc.status = 0x03;
		break;
	}
}

static void fdc_byte_done(int lost)
{
	/* A read keeps the record type (deleted data mark) in its status,
	   and an IMD data error sector ends with a CRC error */
	uint8_t rtype = fdc.writing ? 0 : (fdc.status & 0x20) |
	    (fdc.cur && fdc.cur->bad ? 0x08 : 0);

	if (++fdc.idx < fdc.len) {
		if (mech && !lost) {	/* the next byte is due at its place */
			unsigned long long at = fdc.t0 + fdc.idx * BYTE_T;

			if (cpu.cycles < at) {
				fdc.drq = 0;
				fdc.drq_at = at;
			} else
				fdc.deadline = at + BYTE_T;
			return;
		}
		fdc.deadline = lost ? fdc.deadline + BYTE_T
		    : cpu.cycles + BYTE_T;
		return;
	}
	if (fdc.wtrack) {	/* the index pulse ends the track */
		fdc.wtrack = 0;
		track_from_stream(&disks[fdc.drive].trk[fdc.pos[fdc.drive]][fdc.side],
		    trackbuf, fdc.len);
		fdc_done(0);
		return;
	}
	if (fdc.multi && !(rtype & 0x08)) {	/* a CRC error ends it */
		fdc.sector++;
		fdc_start_sector();
		/* past the last sector: record not found, at once
		   without -M, after 5 turns with it, as the FDC searches
		   for the next sector */
		return;
	}
	if (mech) {		/* the CRC bytes pass, then INTRQ */
		fdc.drq = 0;
		fdc.buf = NULL;
		fdc.done_status = rtype;
		fdc.done_at = fdc.t0 + (fdc.len + 2) * BYTE_T;
		return;
	}
	fdc_done(rtype);
}

static unsigned long fdc_lost;	/* commands with Lost Data, for -L */

/* Pass over the bytes the CPU was too late for. */
static void fdc_tick(void)
{
	if ((fdc.fi & 0x04) && turning() && cpu.cycles >= fdc.fi_index) {
		fdc.intrq = 1;
		fdc.fi_index += (cpu.cycles - fdc.fi_index) / REV_T * REV_T + REV_T;
	}
	if (fdc.step_at && cpu.cycles >= fdc.step_at) {
		fdc.step_at = 0;
		fdc.busy = 0;
		fdc.intrq = 1;
	}
	if (fdc.done_at && cpu.cycles >= fdc.done_at) {
		fdc.done_at = 0;
		fdc_done(fdc.done_status);
	}
	if (fdc.drq_at && cpu.cycles >= fdc.drq_at) {
		fdc.drq = 1;
		fdc.deadline = fdc.first_dl ? fdc.first_dl : fdc.drq_at + BYTE_T;
		fdc.first_dl = 0;
		fdc.drq_at = 0;
	}
	while (fdc.drq && fdc.buf && cpu.cycles > fdc.deadline) {
		if (!fdc.lost)
			fdc_lost++;
		fdc.lost = 1;
		fdc.status |= 0x04;
		if (fdc.writing)
			fdc.buf[fdc.idx] = 0;
		fdc_byte_done(1);
	}
}

static uint8_t fdc_stuck;	/* -F d: FDC status bits stuck at 1 */
static unsigned long long fdc_stuck_at;	/* from this cycle on */
#define STUCK (cpu.cycles >= fdc_stuck_at ? fdc_stuck : 0)

static uint8_t fdc_read(int reg)
{
	fdc_tick();
	switch (reg) {
	case 0:
		if (!fdc.fi && !fdc.d8)
			fdc.intrq = 0;
		if (fdc.type1) {
			type1_status();	/* bit 1 is the index pulse */
			return fdc.status | (fdc.busy ? 1 : 0) | STUCK;
		}
		/* S7 is the Ready input as it is now */
		return (fdc.status & ~0x83) | (fdc_ready() ? 0 : 0x80) |
		    (fdc.busy ? 1 : 0) |
		    (fdc.drq ? 2 : 0) | STUCK;
	case 1: return fdc.track;
	case 2: return fdc.sector;
	default:
		if (fdc.drq && fdc.buf && !fdc.writing) {
			fdc.data = fdc.buf[fdc.idx];
			fdc_byte_done(0);
		}
		return fdc.data;
	}
}

static void fdc_write(int reg, uint8_t v)
{
	fdc_tick();
	switch (reg) {
	case 0: fdc_command(v); break;
	case 1: fdc.track = v; break;
	case 2: fdc.sector = v; break;
	default:
		fdc.data = v;
		if (fdc.drq && fdc.buf && fdc.writing) {
			fdc.buf[fdc.idx] = v;
			fdc_byte_done(0);
		}
		break;
	}
}

static void mlatch_write(uint8_t v)
{
	int was_ready = fdc_ready();

	switch (v & 0x0f) {
	case 1: fdc.drive = 0; break;
	case 2: fdc.drive = 1; break;
	case 4: fdc.drive = 2; break;
	case 8: fdc.drive = 3; break;
	default: fdc.drive = -1; break;
	}
	fdc.side = (v >> 4) & 1;
	fdc.dd = (v >> 6) & 1;
	fdc.eight = (v >> 5) & 1;
	/* any 5-inch select starts the motor timer, 192 ticks, 3.15 s */
	if (!fdc.eight) {
		if (cpu.cycles >= motor_until)
			motor_up = cpu.cycles + SPIN_T;
		motor_until = cpu.cycles + CPU_HZ / 1000 * 3146;
	}
	/* Force Interrupt I1 and I0: ready changes with the select */
	if (((fdc.fi & 0x02) && was_ready && !fdc_ready()) ||
	    ((fdc.fi & 0x01) && !was_ready && fdc_ready()))
		fdc.intrq = 1;
}

/* ---- The rest of the machine ---- */

static uint8_t ram[4][0x8000];
static uint8_t rom[512];
static uint8_t video[2048], font1[1024], font2[1024];
static uint8_t *fault_at, fault_mask;	/* -F */
static int alias_from = -1, alias_to;	/* -F c: */
static int bank_b = 1;			/* -m: 1 fitted, 0 reads FFh, 2 holds the last write */
static uint8_t no_ram;			/* what a missing chunk reads */
static int xport = -1;			/* -x */
static uint8_t xlatch;
static int font_dirty = 1;	/* font RAM written since the style was read */
static uint8_t vlatch, pio_a, pio_b, pio_mask[2], pio_mpend[2];
static uint8_t crtc[18], crtc_idx;
static uint8_t tick_flag;
static int tick_fault = -1;	/* -F t:0 or t:1, SYSFLG's tick stuck */
static int sio_gone;		/* -F u:0, no SIO: its registers read FFh */
/*
 * The DIP switches at block+7F8h, bit 7 switch 1 to bit 0 switch 8, set
 * when up (TRM). The boot ROM takes bits 2-0, switches 6-8, as the boot
 * device (Lobo's ROM source, maxrom13.mac): 0 none, 1 5-inch floppy, 2 8-inch floppy, 3 and
 * 4 a 5- and 8-inch UVC winchester, 5 and 6 a 5- and 8-inch UVC backup
 * floppy, 7 SASI drive 0. The floppies and SASI are emulated, not the
 * UVC. With 0 the ROM beeps and reads the switches again, forever.
 */
static uint8_t dipsw = 2;

/*
 * A SASI hard disk on the UVC/SASI port, a raw image of 512-byte
 * blocks, as Lobo's boot ROM and his hard disk driver, XWINI.MAC, drive it. Nothing measured.
 * USTAT (block+7F4h) bits 0 REQ, 1 MSG, 2 BSY, 3 I/O, 4 C/D, each 1 when
 * the line is asserted. UCTRL bits 0 ACK, 1 SEL, 2 RST. Select: the ID
 * bit, 01h, on UDATA, then SEL. The target takes BSY and asks for six
 * command bytes, then moves data, then a status byte (0 good, 02h check
 * condition) and a message byte (0), then frees the bus. A byte moves
 * when ACK is set, and REQ comes back when ACK is cleared. UDATAHS does
 * the ACK itself. Commands: 00h test unit ready, 01h recalibrate, 03h
 * request sense (4 bytes), 04h format, 08h read, 0Ah write, 0Ch drive
 * parameters (8 bytes, ignored). Anything else is check condition.
 */
enum { S_FREE, S_CMD, S_DIN, S_DOUT, S_STATUS, S_MSG, S_HUNG };
static long sasi_hang, sasi_ncmd;	/* -F s: the command that hangs */
static struct {
	uint8_t *img;		/* NULL: nothing attached */
	long nblk;
	const char *path, *save;
	int phase, req, ack, sel, ci, idx, len;
	long lba;
	uint8_t out, status, sense[4], cmd[6], buf[256 * 512];
} sasi;

static void sasi_status(uint8_t st, uint8_t code)
{
	sasi.status = st;
	sasi.sense[0] = code;
	sasi.sense[1] = sasi.lba >> 16 & 0x1f;
	sasi.sense[2] = sasi.lba >> 8;
	sasi.sense[3] = sasi.lba;
	sasi.phase = S_STATUS;
}

static void sasi_command(void)
{
	uint8_t *c = sasi.cmd;
	int n = c[4] ? c[4] : 256;

	sasi.lba = (long)(c[1] & 0x1f) << 16 | c[2] << 8 | c[3];
	sasi.idx = 0;
	if (sasi_hang && ++sasi_ncmd == sasi_hang) {
		sasi.phase = S_HUNG;	/* BSY, and no REQ again */
		return;
	}
	if (c[1] >> 5 && c[0] != 0x03) {	/* only LUN 0 */
		sasi_status(0x02, 0x04);	/* drive not ready */
		return;
	}
	switch (c[0]) {
	case 0x00: case 0x01:
		sasi_status(0, 0);
		break;
	case 0x03:
		memcpy(sasi.buf, sasi.sense, 4);
		sasi.len = 4;
		sasi.phase = S_DIN;
		sasi.sense[0] = 0;
		break;
	case 0x04:
		memset(sasi.img, 0, sasi.nblk * 512);
		sasi_status(0, 0);
		break;
	case 0x08: case 0x0a:
		if (sasi.lba + n > sasi.nblk) {
			sasi_status(0x02, 0x21);	/* illegal block address */
			break;
		}
		sasi.len = n * 512;
		if (c[0] == 0x08) {
			memcpy(sasi.buf, sasi.img + sasi.lba * 512, sasi.len);
			sasi.phase = S_DIN;
		} else
			sasi.phase = S_DOUT;
		break;
	case 0x0c:
		sasi.len = 8;
		sasi.phase = S_DOUT;
		break;
	default:
		sasi_status(0x02, 0x20);	/* invalid command */
		break;
	}
}

/* The byte on the bus has been taken: move on to the next one */
static void sasi_byte(void)
{
	switch (sasi.phase) {
	case S_CMD:
		sasi.cmd[sasi.ci++] = sasi.out;
		if (sasi.ci == 6)
			sasi_command();
		break;
	case S_DIN:
		if (++sasi.idx == sasi.len)
			sasi_status(0, 0);
		break;
	case S_DOUT:
		sasi.buf[sasi.idx] = sasi.out;
		if (++sasi.idx == sasi.len) {
			if (sasi.cmd[0] == 0x0a)
				memcpy(sasi.img + sasi.lba * 512, sasi.buf, sasi.len);
			sasi_status(0, 0);
		}
		break;
	case S_STATUS:
		sasi.phase = S_MSG;
		break;
	case S_MSG:
		sasi.phase = S_FREE;
		break;
	}
}

static uint8_t sasi_in(void)
{
	switch (sasi.phase) {
	case S_DIN: return sasi.buf[sasi.idx];
	case S_STATUS: return sasi.status;
	case S_MSG: return 0;
	default: return 0xff;
	}
}

static uint8_t sasi_ustat(void)
{
	static const uint8_t bits[] = {
		[S_FREE] = 0, [S_CMD] = 0x10, [S_DIN] = 0x08, [S_DOUT] = 0,
		[S_STATUS] = 0x18, [S_MSG] = 0x1a, [S_HUNG] = 0,
	};
	if (sasi.phase == S_FREE)
		return 0;
	return bits[sasi.phase] | 0x04 | (sasi.req ? 0x01 : 0);
}

static void sasi_ctrl(uint8_t v)
{
	if (v & 4) {		/* reset */
		sasi.phase = S_FREE;
		sasi.req = sasi.ack = sasi.sel = 0;
		return;
	}
	if (v & 2 && !sasi.sel && sasi.img && sasi.phase == S_FREE && sasi.out & 1) {
		sasi.phase = S_CMD;
		sasi.ci = 0;
		sasi.req = 1;
	}
	sasi.sel = v & 2;
	if (v & 1 && !sasi.ack && sasi.req) {
		sasi_byte();
		sasi.req = 0;
	}
	if (!(v & 1) && sasi.ack && sasi.phase != S_FREE && sasi.phase != S_HUNG)
		sasi.req = 1;
	sasi.ack = v & 1;
}

/* UDATAHS: the byte moves and the handshake is done in one access */
static void sasi_auto(void)
{
	if (!sasi.req)
		return;
	sasi_byte();
	sasi.req = sasi.phase != S_FREE && sasi.phase != S_HUNG;
}

static int load_hd(const char *path)
{
	FILE *f = fopen(path, "rb");
	long n;

	if (!f || fseek(f, 0, SEEK_END) || (n = ftell(f)) <= 0 || n % 512 ||
	    n > 0x200000L * 512) {
		fprintf(stderr, "%s: not a hard disk image of 512-byte blocks\n", path);
		if (f)
			fclose(f);
		return 1;
	}
	sasi.img = malloc(n);
	rewind(f);
	if (!sasi.img || fread(sasi.img, 1, n, f) != (size_t)n) {
		fprintf(stderr, "%s: cannot read\n", path);
		fclose(f);
		return 1;
	}
	fclose(f);
	sasi.nblk = n / 512;
	sasi.path = path;
	return 0;
}

static int save_hd(const char *path)
{
	FILE *f = fopen(path, "wb");
	if (!f || fwrite(sasi.img, 512, sasi.nblk, f) != (size_t)sasi.nblk ||
	    fclose(f)) {
		fprintf(stderr, "%s: cannot write\n", path);
		return 1;
	}
	return 0;
}
static uint8_t keyrow[8];
static uint8_t keyheld[8];	/* keys held down in the window */
static int video_dirty = 1;

/*
 * The beep: any write to block+7F8h sounds the speaker, "about two
 * kiloHertz ... about 1/15 second" (TRM TS-14). The schematics give the
 * tone as 500 kHz / 256 = 1953.125 Hz, free running, and the length as
 * a counter of ticks, so a beep ends at the fourth tick after the write,
 * 3 to 4 tick periods, 49 to 66 ms. A write during a beep is taken to
 * restart the count, which the schematics do not show. Beeps are kept as spans of CPU
 * cycles, and the sound is made from them each tick.
 */
#define BEEP_NUM 15625ULL	/* the tone, BEEP_NUM / BEEP_DEN Hz */
#define BEEP_DEN 8ULL
#define NBEEP 16
static struct { unsigned long long start, end; } beeps[NBEEP];
static int nbeeps;
static unsigned long beep_count;

/* The cycle of the fourth tick after cycle c */
static unsigned long long beep_end(unsigned long long c)
{
	unsigned long long k = tick_count(c) + 1;	/* next tick */
	return tick_cycle(k + 3);
}

static void beep(void)
{
	unsigned long long now = cpu.cycles;

	beep_count++;
	if (nbeeps && beeps[nbeeps - 1].end >= now) {
		beeps[nbeeps - 1].end = beep_end(now);
		return;
	}
	if (nbeeps == NBEEP)
		memmove(beeps, beeps + 1, --nbeeps * sizeof(beeps[0]));
	beeps[nbeeps].start = now;
	beeps[nbeeps].end = beep_end(now);
	nbeeps++;
}

static uint8_t *chunk_ram(int chunk, uint16_t a)
{
	if (chunk == alias_from)
		chunk = alias_to;
	if (chunk >= 2 && bank_b != 1) {
		if (bank_b == 0)
			no_ram = 0xff;
		return &no_ram;
	}
	return &ram[chunk][a & 0x7fff];
}

static uint8_t *ram_at(uint16_t a)
{
	return chunk_ram(a & 0x8000 ? (pio_a >> 6) & 3 : (pio_a >> 4) & 3, a);
}

/*
 * /4K BANK forces the bank and chunk bits to 0 in the block, so its RAM
 * is A1 at the address less A15, whatever the PIO selects (schematic
 * sheets 1 and 2, TRM TS-28).
 */
static uint8_t *block_ram(uint16_t a)
{
	return chunk_ram(0, a);
}

/*
 * The MSM5832 clock chip (Appendix E), behind PIO port B: bits 3-0 the
 * register, 4 WRITE, 5 READ, 6 HOLD. Port A bits 3-0 carry the digit.
 * It keeps 13 digits, seconds units to years tens, and counts them once
 * a second with its own carries, so a digit written out of range stays
 * until a carry passes it, as the button test of Lobo's TIMESET program needs. It starts at
 * the host's time and counts emulated seconds. HOLD and WRITE go
 * through the rear TIME SET button (schematics), held with -C.
 * HOLD stops the count, a write needs HOLD, and writing either seconds
 * digit clears both. With READ low the open drain data lines read 1111.
 */
#define RTC_TRA (CPU_HZ * 6 / 1000000)	/* MSM5832 access time, 6 us */
static uint64_t rtc_t;		/* when the address last changed */
static uint8_t rtc_old;		/* and what it was */
static uint8_t rtc_reg[13];
static int rtc_set;		/* rtc_reg holds a time */
static uint64_t rtc_sec;	/* the emulated second rtc_reg is at */
static int time_set;		/* -C: TIME SET held */

static int rtc_days(void)	/* in the month the digits hold */
{
	static const uint8_t d[13] = { 31, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
	int m = rtc_reg[10] * 10 + rtc_reg[9];
	if (m == 2 && (rtc_reg[8] & 4))	/* date tens bit 2, the leap year */
		return 29;
	return m <= 12 ? d[m] : 31;
}

/* One second on, digit by digit as the chip carries */
static void rtc_tick(void)
{
	uint8_t *r = rtc_reg;
	if (++r[0] < 10) return;
	r[0] = 0;
	if (++r[1] < 6) return;
	r[1] = 0;
	if (++r[2] < 10) return;
	r[2] = 0;
	if (++r[3] < 6) return;
	r[3] = 0;
	int h24 = r[5] & 8, pm = r[5] & 4, h = (r[5] & 3) * 10 + r[4];
	h++;
	if (h24) {
		if (h < 24) { r[4] = h % 10; r[5] = (h / 10) | 8; return; }
		h = 0;
		r[4] = 0; r[5] = 8;
	} else {
		if (h == 12) pm ^= 4;
		if (h == 13) h = 1;
		r[4] = h % 10; r[5] = (h / 10) | pm;
		if (h != 12 || pm) return;	/* a new day at 12 AM */
	}
	r[6] = (r[6] + 1) % 7;
	int leap = r[8] & 4, d = (r[8] & 3) * 10 + r[7] + 1;
	if (d <= rtc_days()) { r[7] = d % 10; r[8] = (d / 10) | leap; return; }
	r[7] = 1;
	r[8] = r[9] == 2 && r[10] == 0 ? 0 : leap;	/* cleared past 29 Feb */
	int m = r[10] * 10 + r[9] + 1, y;
	if (m <= 12) { r[9] = m % 10; r[10] = m / 10; return; }
	r[9] = 1; r[10] = 0;
	y = (r[12] * 10 + r[11] + 1) % 100;
	r[11] = y % 10; r[12] = y / 10;
}

static int rtc_held(void)
{
	return time_set && (pio_b & 0x40);
}

/* Bring the digits up to the emulated time */
static void rtc_sync(void)
{
	uint64_t sec = cpu.cycles / CPU_HZ;

	if (!rtc_set) {
		struct tm *tm = host_time();
		uint8_t v[13] = { tm->tm_sec % 10, tm->tm_sec / 10,
			tm->tm_min % 10, tm->tm_min / 10, tm->tm_hour % 10,
			(tm->tm_hour / 10) | 8, tm->tm_wday, tm->tm_mday % 10,
			(tm->tm_mday / 10) | (tm->tm_year % 4 ? 0 : 4),
			(tm->tm_mon + 1) % 10, (tm->tm_mon + 1) / 10,
			tm->tm_year % 10, (tm->tm_year / 10) % 10 };
		memcpy(rtc_reg, v, 13);
		rtc_set = 1;
		rtc_sec = sec;
	}
	if (rtc_held()) {	/* the count stands while HOLD is high */
		rtc_sec = sec;
		return;
	}
	while (rtc_sec < sec) {
		rtc_tick();
		rtc_sec++;
	}
}

static uint8_t rtc_read(void)
{
	if (!(pio_b & 0x20))	/* READ low: the data lines float high */
		return 0x0f;
	rtc_sync();
	/* a read within tRA of an address change gives the old digit */
	int a = cpu.cycles - rtc_t < RTC_TRA ? rtc_old : pio_b & 0x0f;
	return a < 13 ? rtc_reg[a] : 0x0f;
}

/* Port B changed from old to pio_b: WRITE and HOLD high together store
   the digit, whichever came first. TIMESET raises HOLD then WRITE, LDOS
   SETTIME WRITE then HOLD */
static void rtc_port_b(uint8_t old)
{
	uint8_t now = pio_b;
	pio_b = old;		/* the seconds up to now count as HOLD was */
	rtc_sync();		/* before this write */
	pio_b = now;
	if ((old & 0x50) != 0x50 && (pio_b & 0x50) == 0x50 && rtc_held()) {
		int a = pio_b & 0x0f;
		if (a == 0 || a == 1) {	/* either seconds digit clears both */
			rtc_reg[0] = rtc_reg[1] = 0;
		} else if (a < 13)	/* PA3-0 that are inputs float to
					   their pull-ups (PIO-23): 1s */
			rtc_reg[a] = (pio_a | pio_mask[0]) & 0x0f;
	}
}

static void pio_write(int reg, uint8_t v)
{
	int port = reg >> 1;

	if (reg & 1) {		/* control */
		if (pio_mpend[port]) {
			pio_mask[port] = v;
			pio_mpend[port] = 0;
		} else if ((v & 0x0f) == 0x0f && (v >> 6) == 3)
			pio_mpend[port] = 1;
		return;
	}
	if (port == 0)
		pio_a = v;
	else {
		uint8_t old = pio_b;
		if ((v ^ pio_b) & 0x0f) {
			rtc_old = pio_b & 0x0f;
			rtc_t = cpu.cycles;
		}
		pio_b = v;
		rtc_port_b(old);
	}
}

static uint8_t pio_read(int reg)
{
	if (reg & 1)
		return 0xff;
	if (reg == 0)
		return (pio_a & ~pio_mask[0]) | (rtc_read() & pio_mask[0]);
	return pio_b;
}

/*
 * The serial ports and the printer. A Z80 SIO (Appendix C): data A
 * at 7E4h, control A 7E5h, data B 7E6h, control B 7E7h. A control write
 * to WR0 picks the next register, or gives a command. A control read
 * gives RR0, or RR1 or RR2 when picked. The rate is the COM8116 code at
 * 7D0h (A) and 7D4h (B), a bit 16 x the Appendix B divisor in CPU
 * T-states, as the COM8116 runs on the CPU's clock, 15.2 MHz / 3
 * (schematics). A character is a start bit, the data bits of WR5 (send)
 * or WR3 (receive), a parity bit if WR4 asks, and 1, 1.5 or 2 stop bits
 * from WR4.
 *
 * Sending: a byte written goes to the shift register when it is free,
 * else waits in the buffer, and RR0 bit 2 is the buffer empty. It waits
 * there while WR5 bit 3 is off, or while auto enables (WR3 bit 5) wait
 * for CTS. Break (WR5 bit 4) sends no bytes. Fewer than 8 data bits drop
 * the high bits. A byte sent goes to the -o file.
 *
 * Receiving: the -i file is a remote that starts sending when the
 * receiver is first enabled, or at its @ time if that is later, a byte a
 * character time apart. It waits while the SIO's 3-byte FIFO is full and
 * sends again a character after a read, as a remote with handshaking
 * would, so scripted input is not lost, and it sends again what a channel
 * reset threw out of the FIFO, so a program that sets the SIO up after
 * the remote started still gets every byte. With -I it never waits: bytes
 * land in the FIFO whether read or not, a fourth overwrites the last,
 * and RR1 bit 5 shows the overrun until WR0's error reset, and bytes
 * are lost while the receiver is off (or DCD with auto enables), where
 * -i waits. Bytes pass whole, parity is not made or checked.
 *
 * CTS and DCD read on, a remote that is ready, or off with -S, nothing
 * plugged in. The printer reads 30h when ready, B0h for 0.5 ms after
 * each byte, F0h with no printer file.
 */
static const unsigned baud_div[16] = {	/* COM8116, 16x clock, App B */
	6336, 4224, 2880, 2355, 2112, 1056, 528, 264,
	176, 158, 132, 88, 66, 44, 33, 16,
};

static struct sio_chan {
	uint8_t ptr, wr[8], baud;
	FILE *in, *out;
	unsigned long long shift_end;	/* the character being sent ends */
	int buf;		/* a byte waiting to be sent + 1, or 0 */
	unsigned long long rx_at;	/* -i a:file@s: the remote starts then */
	unsigned long long rx_next;	/* the next byte has arrived */
	int rx_on, rx_eof;	/* the remote has started, has no more */
	uint8_t fifo[3], last;
	int n, overrun;
	int first;		/* WR1 Rx mode 01: the next character interrupts */
	int tx_ie;		/* a byte was sent, Tx empty may interrupt */
	int nopeer;		/* -S: nothing plugged in, CTS and DCD off */
	int raw;		/* -I: the remote never waits for the FIFO */
	int stalled;		/* the remote waits for room in the FIFO */
	uint8_t again[3];	/* -i: bytes a reset threw out, sent again */
	int nagain;
} sio[2] = { { .baud = 14, .first = 1 }, { .baud = 14, .first = 1 } };
static int sio_ie;		/* some channel's WR1 asks for interrupts */
static FILE *prn;
static unsigned long long prn_busy;

#define PRN_T (CPU_HZ / 2000)

static int sio_bits(uint8_t code)	/* WR3 D7-D6 or WR5 D6-D5 */
{
	static const int b[4] = { 5, 7, 6, 8 };
	return b[code & 3];
}

/* A character's T-states, send (tx) or receive */
static unsigned long long sio_char_t(struct sio_chan *ch, int tx)
{
	int data = sio_bits(tx ? ch->wr[5] >> 5 : ch->wr[3] >> 6);
	int stop2 = (ch->wr[4] >> 2) & 3;	/* stop bits x 2: 1, 1.5, 2 */
	int half = 2 * (1 + data + (ch->wr[4] & 1)) + (stop2 ? stop2 + 1 : 2);
	return 16ULL * baud_div[ch->baud & 15] * half / 2;
}

/* Send what the buffer holds when the shift register frees */
static void sio_tx_pump(struct sio_chan *ch)
{
	int cts = !ch->nopeer || !(ch->wr[3] & 0x20);

	while (ch->buf && cpu.cycles >= ch->shift_end && (ch->wr[5] & 8) && cts) {
		uint8_t v = ch->buf - 1;
		int data = sio_bits(ch->wr[5] >> 5);
		unsigned long long from = ch->shift_end > cpu.cycles ? ch->shift_end : cpu.cycles;
		ch->buf = 0;
		ch->shift_end = from + sio_char_t(ch, 1);
		if (ch->out && !(ch->wr[5] & 0x10)) {	/* no break */
			putc(data < 8 ? v & ((1 << data) - 1) : v, ch->out);
			fflush(ch->out);
		}
	}
}

/* The bytes the remote has sent by now, into the FIFO */
static void sio_rx_pump(struct sio_chan *ch)
{
	if (!ch->in || ch->rx_eof)
		return;
	if (!ch->rx_on) {
		if (!(ch->wr[3] & 1))
			return;
		ch->rx_on = 1;
		ch->rx_next = (ch->rx_at > cpu.cycles ? ch->rx_at : cpu.cycles) +
		    sio_char_t(ch, 0);
	}
	/* -i waits while the FIFO is full or the receiver is off */
	int off = !(ch->wr[3] & 1) || (ch->nopeer && (ch->wr[3] & 0x20));
	if (ch->stalled && ch->n < 3 && !off) {	/* room again: the next comes */
		ch->stalled = 0;
		ch->rx_next = cpu.cycles + sio_char_t(ch, 0);
	}
	while (cpu.cycles >= ch->rx_next) {
		if (!ch->raw && (ch->n == 3 || off)) {
			ch->stalled = 1;
			return;
		}
		int c;
		if (ch->nagain) {
			c = ch->again[0];
			memmove(ch->again, ch->again + 1, --ch->nagain);
		} else if ((c = getc(ch->in)) == EOF) {
			ch->rx_eof = 1;
			return;
		}
		ch->rx_next += sio_char_t(ch, 0);
		if (!(ch->wr[3] & 1) || (ch->nopeer && (ch->wr[3] & 0x20)))
			continue;	/* receiver off, or no DCD: lost */
		if (ch->n == 3) {
			ch->fifo[2] = c;
			ch->overrun = 1;
		} else
			ch->fifo[ch->n++] = c;
	}
}

/*
 * The SIO's /INT, ANDed with the tick on the board (TS-23,
 * schematics). Its /M1 is tied high, so it never sees an acknowledge or
 * RETI: the line follows the conditions. WR1 D4-D3 01 interrupts on the
 * first character after a reset or WR0's "enable int on next Rx
 * character", 10 and 11 on every character, D1 when the transmit buffer
 * has emptied after a byte, until WR0's "reset Tx int pending" or the
 * next byte. External/status interrupts (D0) are left out: CTS and DCD
 * never change here.
 */
static int sio_chan_int(struct sio_chan *ch)
{
	int rx = (ch->wr[1] >> 3) & 3;

	sio_rx_pump(ch);
	sio_tx_pump(ch);
	if (rx && (rx != 1 || ch->first) && ch->n)
		return 1;
	return (ch->wr[1] & 2) && ch->tx_ie && !ch->buf;
}

static int sio_int(void)
{
	return sio_ie && (sio_chan_int(&sio[0]) || sio_chan_int(&sio[1]));
}

static uint8_t sio_read(int reg)
{
	struct sio_chan *ch = &sio[reg >> 1];
	uint8_t r;

	sio_rx_pump(ch);
	sio_tx_pump(ch);
	if (!(reg & 1)) {		/* data, the last byte again if none */
		if (ch->n) {
			ch->last = ch->fifo[0];
			memmove(ch->fifo, ch->fifo + 1, --ch->n);
			ch->first = 0;
		}
		return ch->last;
	}
	switch (ch->ptr) {
	case 0:			/* bit 1, an interrupt pending, on A only */
		r = (ch->n ? 0x01 : 0) | (ch->buf ? 0 : 0x04) |
		    (ch->nopeer ? 0 : 0x28) |
		    (ch == &sio[0] && sio_int() ? 0x02 : 0);
		break;
	case 1:			/* all sent, overrun */
		r = (!ch->buf && cpu.cycles >= ch->shift_end ? 0x01 : 0) |
		    (ch->overrun ? 0x20 : 0);
		break;
	case 2:			/* the vector, channel B's WR2 */
		r = sio[1].wr[2];
		break;
	default:
		r = 0;
	}
	ch->ptr = 0;
	return r;
}

static void sio_write(int reg, uint8_t v)
{
	struct sio_chan *ch = &sio[reg >> 1];

	sio_rx_pump(ch);
	sio_tx_pump(ch);
	if (!(reg & 1)) {		/* data: into the buffer, the last wins */
		ch->buf = v + 1;
		ch->tx_ie = 1;
		sio_tx_pump(ch);
		return;
	}
	ch->wr[ch->ptr] = v;
	if (ch->ptr) {
		ch->ptr = 0;
		sio_rx_pump(ch);	/* WR3 may have turned the receiver on */
		sio_tx_pump(ch);	/* WR5 the sender */
		sio_ie = (sio[0].wr[1] | sio[1].wr[1]) & 0x1a;
		cpu.irq = tick_flag || sio_int();
		return;
	}
	ch->ptr = v & 7;
	switch (v & 0x38) {
	case 0x18:		/* channel reset */
		if (!ch->raw && ch->n) {	/* -i sends them again */
			memmove(ch->again + ch->n, ch->again, ch->nagain);
			memcpy(ch->again, ch->fifo, ch->n);
			ch->nagain += ch->n;
			ch->rx_eof = 0;
		}
		memset(ch->wr, 0, sizeof(ch->wr));
		ch->ptr = 0;
		ch->buf = 0;
		ch->shift_end = 0;
		ch->n = ch->overrun = 0;
		ch->stalled = 0;
		ch->first = 1;
		ch->tx_ie = 0;
		sio_ie = (sio[0].wr[1] | sio[1].wr[1]) & 0x1a;
		cpu.irq = tick_flag || sio_int();
		break;
	case 0x20:		/* enable int on next Rx character */
		ch->first = 1;
		break;
	case 0x28:		/* reset Tx int pending */
		ch->tx_ie = 0;
		break;
	case 0x30:		/* error reset */
		ch->overrun = 0;
		break;
	}
}

/* Each frame: a byte left in a buffer goes out when its turn comes */
static void sio_service(void)
{
	sio_tx_pump(&sio[0]);
	sio_tx_pump(&sio[1]);
}

/* At exit: what the buffers hold would be sent a character later */
static void sio_flush(void)
{
	for (int i = 0; i < 2; i++) {
		cpu.cycles = sio[i].shift_end > cpu.cycles ? sio[i].shift_end : cpu.cycles;
		sio_tx_pump(&sio[i]);
	}
}

static uint8_t prn_status(void)
{
	/* bits 7-4 BUSY, OUTPAPER, UNITSELCT, FAULT, as the port reads
	 * them: selected with FAULT high when ready, F0h with nothing
	 * plugged in, since the inputs float high */
	if (!prn)
		return 0xf0;
	return cpu.cycles < prn_busy ? 0xb0 : 0x30;
}

static void prn_write(uint8_t v)
{
	if (!prn || cpu.cycles < prn_busy)	/* busy: the byte is lost */
		return;
	putc(v, prn);
	fflush(prn);
	prn_busy = cpu.cycles + PRN_T;
}

/*
 * SYSFLG bit 6, the CRTC's DISPTMG: on while the beam is in the picture.
 * A character clock is 8 dots of 15.2 MHz, 8/3 CPU T-states. Interlace
 * is not modeled, every field is taken as a frame.
 */
static int raster;		/* -B, the beam-raced CRTC */
static int vstretch;		/* -V, the most T a video access stretches */
static int raster_dsptmg(void);
static void raster_run(void);

static int dsptmg(void)
{
	if (raster)
		return raster_dsptmg();
	int htotal = crtc[0] + 1, lines = (crtc[9] & 0x1f) + 1;
	int fh = ((crtc[4] & 0x7f) + 1) * lines + (crtc[5] & 0x1f);
	unsigned long long ch = cpu.cycles * 3 / 8, line = ch / htotal;

	return ch % htotal < crtc[1] &&
	    line % fh < (unsigned)((crtc[6] & 0x7f) * lines);
}

static uint8_t io_read(int off)
{
	uint8_t r;

	switch (off & ~3) {
	case 0x7e0:		/* system flags */
		r = ((tick_fault >= 0 ? tick_fault : tick_flag) ? 0x80 : 0) |
		    (dsptmg() ? 0x40 : 0) |
		    (cpu.cycles < motor_until ? 0x20 : 0);
		if (fdc.eight && fdc.drive >= 0 && disks[fdc.drive].loaded &&
		    disks[fdc.drive].one)
			r |= 0x10;
		if (!(off & 1)) {
			tick_flag = 0;
			cpu.irq = sio_int();
		}
		return r;
	case 0x7e4:
		if (sio_gone)
			return 0xff;
		return sio_read(off & 3);
	case 0x7e8:
		return prn_status();
	case 0x7ec:
		return ~fdc_read(off & 3);
	case 0x7f0:		/* SASI data, 7F1h with the handshake */
		r = sasi_in();
		if (off & 1)
			sasi_auto();
		return r;
	case 0x7f4:		/* DRQ- and INTRQ-, and the SASI lines */
		fdc_tick();
		return (fdc.drq ? 0 : 0x80) | (fdc.intrq ? 0 : 0x40) | sasi_ustat();
	case 0x7f8:
		return dipsw;
	default:		/* 7FC PIO */
		return pio_read(off & 3);
	}
}

static void io_write(int off, uint8_t v)
{
	switch (off & ~3) {
	case 0x7d0: sio[0].baud = v & 15; break;
	case 0x7d4: sio[1].baud = v & 15; break;
	case 0x7d8: mlatch_write(v); break;
	case 0x7dc:
		if (raster)
			raster_run();
		vlatch = v;
		video_dirty = 1;
		break;
	case 0x7e0:
		if (off & 1) {
			if (raster)
				raster_run();
			if (crtc_idx < sizeof(crtc)) {
				crtc[crtc_idx] = v;
				video_dirty = 1;
			}
		} else
			crtc_idx = v & 0x1f;	/* a 5-bit register, App G p.65 */
		break;
	case 0x7ec: fdc_write(off & 3, ~v); break;
	case 0x7f0:
		sasi.out = v;
		if (off & 1)
			sasi_auto();
		break;
	case 0x7f4: sasi_ctrl(v); break;
	case 0x7f8: beep(); break;
	case 0x7fc: pio_write(off & 3, v); break;
	case 0x7e4:	/* -F u:0: no SIO to take it */
		if (!sio_gone)
			sio_write(off & 3, v);
		break;
	case 0x7e8: prn_write(v); break;
	default: break;
	}
}

static uint8_t *window(int off)
{
	switch (vlatch & 7) {
	case 0: return NULL;	/* the ROM */
	case 1: return NULL;	/* RAM */
	case 2:
	case 3: return &video[0x400 + off];
	case 4:
	case 5: return &font1[off];
	default: return &font2[off];
	}
}

/*
 * TRM TS-3: every device register access adds two wait states, except
 * USTAT. Taken as the latches and devices at 7D0h-7FFh. The video RAM
 * stretch and SLORAM's slowness are not measured and left out.
 * Only the CPU's own accesses count, it passes a ctx.
 */
static void dev_wait(void *ctx, int off)
{
	if (ctx && off >= 0x7d0 && off < 0x800 && (off & ~3) != 0x7f4)
		cpu.cycles += 2;
}

/* -V: a video or font RAM access by the CPU waits 0 to vstretch T */
static void video_wait(void *ctx)
{
	static uint32_t seed = 1;

	if (ctx && vstretch) {
		seed = seed * 1103515245 + 12345;
		cpu.cycles += (seed >> 16) % (vstretch + 1);
	}
}

static uint8_t mem_read(void *ctx, uint16_t a)
{
	if ((a >> 12) == (vlatch >> 4)) {
		int off = a & 0xfff;
		dev_wait(ctx, off);
		if (off < 0x400) {
			uint8_t *w = window(off);
			if (w) {
				video_wait(ctx);
				return w == fault_at ? *w & ~fault_mask : *w;
			}
			if ((vlatch & 7) == 0)
				return rom[off & 0x1ff];
		} else if (off >= 0xc00) {
			uint8_t *v = &video[(off - 0xc00) & 0x3ff];
			video_wait(ctx);
			return v == fault_at ? *v & ~fault_mask : *v;
		}
		else if (off >= 0x800 && off < 0x900) {
			uint8_t r = 0;
			for (int i = 0; i < 8; i++)
				if (off & (1 << i))
					r |= keyrow[i] | keyheld[i];
			return r;
		} else if (off >= 0x7e0 && off < 0x800)
			return io_read(off);
		uint8_t *b = block_ram(a);
		return b == fault_at ? *b & ~fault_mask : *b;
	}
	uint8_t *r = ram_at(a);
	return r == fault_at ? *r & ~fault_mask : *r;
}

static void mem_write(void *ctx, uint16_t a, uint8_t v)
{
	if ((a >> 12) == (vlatch >> 4)) {
		int off = a & 0xfff;
		dev_wait(ctx, off);
		if (off < 0x400) {
			uint8_t *w = window(off);
			if (w) {
				video_wait(ctx);
				if (raster)
					raster_run();
				*w = v;
				video_dirty = 1;
				if ((vlatch & 7) >= 4)
					font_dirty = 1;
				return;
			}
			if ((vlatch & 7) == 0)
				return;
		} else if (off >= 0xc00) {
			video_wait(ctx);
			if (raster)
				raster_run();
			video[off - 0xc00] = v;
			video_dirty = 1;
			return;
		}
		/* The RAM first: a write to VLATCH may move the block. The
		   keyboard is read only, and its RAM is written, as MultiDOS's
		   boot sector needs. A device write lands too */
		*block_ram(a) = v;
		if (off >= 0x7d0 && off < 0x800)
			io_write(off, v);
		return;
	}
	*ram_at(a) = v;
}

/*
 * The expansion bus gets every IN and OUT, by the low 8 address bits.
 * No card reads FFh, a guess at the floating data lines. The -x
 * card is a latch that reads back what was written.
 */
static uint8_t bus_in(void *ctx, uint16_t port)
{
	(void)ctx;
	return (port & 0xff) == xport ? xlatch : 0xff;
}

static void bus_out(void *ctx, uint16_t port, uint8_t v)
{
	(void)ctx;
	if ((port & 0xff) == xport)
		xlatch = v;
}

/* ---- Screen ---- */

static int screen_cols(void)
{
	return crtc[1] && crtc[1] <= 80 ? crtc[1] : 80;
}

static int screen_rows(void)
{
	return crtc[6] && crtc[6] <= 25 ? crtc[6] : 24;
}

/*
 * Codes outside 20h-7Eh. The CP/M BIOSes print a second style of each
 * character by writing 20h-3Fh as 80h-9Fh, 40h-5Fh as 00h-1Fh and
 * 60h-7Fh as A0h-BFh (C0h-FFh show the shapes of 80h-BFh). What that
 * style looks like is the font's choice: thin letters in the CP/M 2.2
 * font, inverse video in the CP/M 3 one. The LDOS font has TRS-80 2x3
 * block graphics in 80h-BFh instead, and accented letters in 00h-1Fh. The style is read from the font
 * RAM whenever it changes: block graphics if 80h-BFh follow the 2x3
 * pattern, else inverse or plain, whichever the second-style shapes as
 * a whole are closer to.
 */
enum { STYLE_PLAIN, STYLE_INVERSE, STYLE_BLOCKS };
static int font_style;

static uint8_t glyph_row(uint8_t b, int r)
{
	if (b < 0x80)
		return r < 8 ? font1[b * 8 + r] : 0;
	return r < 8 ? font2[(b & 0x3f) * 8 + r] : font2[512 + (b & 0x3f) * 8 + r - 8];
}

/* The character a second-style code stands for in Lobo's fonts */
static uint8_t lobo_base(uint8_t b)
{
	if (b < 0x20)
		return b + 0x40;
	b &= 0x3f;
	return b < 0x20 ? b + 0x20 : b + 0x40;
}

/* xcpmz80's second style: 20h-5Fh at 80h-BFh, 60h-7Fh at 00h-1Fh */
static uint8_t xcpm_base(uint8_t b)
{
	return b < 0x20 ? b + 0x60 : (b & 0x3f) + 0x20;
}

/* 1 when code b draws a as it is, inverted, or thin as xcpmz80's second
 * style draws it: the rightmost dot of each run of two or more cleared */
static int same_shape(uint8_t b, uint8_t a)
{
	int plain = 1, inv = 1, thin = 1;
	for (int r = 0; r < 8; r++) {
		uint8_t g = glyph_row(b, r), h = glyph_row(a, r);
		plain &= g == h;
		inv &= (g ^ h) == 0xff;
		thin &= g == (uint8_t)(h & ~(h & h >> 1 & ~(h << 1)));
	}
	return plain || inv || thin;
}

/* 00h-1Fh then 80h-BFh: the character each code stands for, found by
 * font_check from the shapes in font RAM */
static uint8_t base_map[0x60];

static uint8_t base_char(uint8_t b)
{
	return base_map[b < 0x20 ? b : 0x20 + (b & 0x3f)];
}

/* A 2x3 block pattern, bit 0 top left to bit 5 bottom right, 12 rows */
static int block_bits(uint8_t b)
{
	int bits = 0;
	for (int band = 0; band < 3; band++) {
		int left = 0, right = 0;
		for (int r = band * 4; r < band * 4 + 4; r++) {
			uint8_t g = glyph_row(b, r);
			left += __builtin_popcount(g & 0xf0);
			right += __builtin_popcount(g & 0x0f);
		}
		if (left > 8)
			bits |= 1 << (band * 2);
		if (right > 8)
			bits |= 2 << (band * 2);
	}
	return bits;
}

static void font_check(void)
{
	int blocks = 0, lobo = 0, xcpm = 0;
	long plain = 0, inverse = 0;

	if (!font_dirty)
		return;
	font_dirty = 0;
	/* The layout most codes match, Lobo's or xcpmz80's, so a glyph
	 * drawn by hand still reads as its code says */
	for (int i = 0; i < 0x60; i++) {
		uint8_t b = i < 0x20 ? i : 0x60 + i;
		lobo += same_shape(b, lobo_base(b));
		xcpm += same_shape(b, xcpm_base(b));
	}
	/* that layout unless the code draws another character exactly */
	for (int i = 0; i < 0x60; i++) {
		uint8_t b = i < 0x20 ? i : 0x60 + i;
		uint8_t a = xcpm > lobo ? xcpm_base(b) : lobo_base(b);
		base_map[i] = a;
		if (same_shape(b, a))
			continue;
		for (int c = 0x20; c < 0x80; c++)
			if (same_shape(b, c)) {
				base_map[i] = c;
				break;
			}
	}
	for (int n = 0; n < 64; n++)
		blocks += block_bits(0x80 + n) == n;
	for (int b = 0; b < 0xc0; b++) {
		if (b == 0x20)
			b = 0x80;
		uint8_t a = base_char(b);
		if (a == 0x7f)
			continue;
		for (int r = 0; r < 8; r++) {
			uint8_t g = glyph_row(b, r), h = glyph_row(a, r);
			plain += __builtin_popcount(g ^ h);
			inverse += __builtin_popcount((g ^ 0xff) ^ h);
		}
	}
	font_style = blocks >= 60 ? STYLE_BLOCKS
	    : inverse < plain ? STYLE_INVERSE : STYLE_PLAIN;
}

static int put_utf8(char *o, unsigned cp)
{
	if (cp < 0x80) {
		o[0] = cp;
		return 1;
	}
	if (cp < 0x800) {
		o[0] = 0xc0 | cp >> 6;
		o[1] = 0x80 | (cp & 0x3f);
		return 2;
	}
	if (cp < 0x10000) {
		o[0] = 0xe0 | cp >> 12;
		o[1] = 0x80 | (cp >> 6 & 0x3f);
		o[2] = 0x80 | (cp & 0x3f);
		return 3;
	}
	o[0] = 0xf0 | cp >> 18;
	o[1] = 0x80 | (cp >> 12 & 0x3f);
	o[2] = 0x80 | (cp >> 6 & 0x3f);
	o[3] = 0x80 | (cp & 0x3f);
	return 4;
}

/* The LDOS font's 00h-1Fh, the TRS-80 Model III set. 0Dh and 1Bh have
 * no Unicode match */
static const unsigned ldos_low[32] = {
	' ', 0xa3, '|', 0xe9, 0xdc, 0xc5, 0xac, 0xf6,
	0xd8, 0xf9, 0xf1, '`', 0x101, '.', 0xc4, 0xc3,
	0xd1, 0xd6, 0xd8, 0xd5, 0xdf, 0xfc, 0xf5, 0xe6,
	0xe4, 0xe0, 0x227, '.', 0xc9, 0xc6, 0xc7, 0x2dc,
};

/* Unicode for a 2x3 block: the sextants, which leave out the four that
 * are ordinary block elements */
static unsigned block_char(int bits)
{
	switch (bits) {
	case 0: return ' ';
	case 21: return 0x258c;		/* left half */
	case 42: return 0x2590;		/* right half */
	case 63: return 0x2588;		/* full */
	}
	return 0x1fb00 + bits - 1 - (bits > 21) - (bits > 42);
}

/*
 * One row of the screen as UTF-8 text, at most 4 bytes a cell. rev, if
 * given, is set for each cell shown in inverse video. Byte 7Fh is the
 * BIOS cursor.
 */
static void screen_row(int row, char *out, uint8_t *rev, int *cursor_col)
{
	int cols = screen_cols();
	int start = (crtc[12] << 8 | crtc[13]) + row * cols;

	font_check();
	*cursor_col = -1;
	for (int c = 0; c < cols; c++) {
		uint8_t b = video[(start + c) & 0x7ff];
		unsigned cp = b;
		int inv = 0;
		if (b == 0x7f) {
			*cursor_col = c;
			cp = ' ';
		} else if (b >= 0x20 && b < 0x7f) {
			cp = b;
		} else if (font_style == STYLE_BLOCKS) {
			cp = b >= 0x80 ? block_char(b & 0x3f) : ldos_low[b];
		} else {
			cp = base_char(b);
			if (cp == 0x7f)
				cp = 0x2588;
			inv = font_style == STYLE_INVERSE;
		}
		out += put_utf8(out, cp);
		if (rev)
			rev[c] = inv;
	}
	*out = 0;
}

/* The cells of a row that are neither blank nor the cursor */
static int row_marks(int row, int *last)
{
	int cols = screen_cols();
	int start = (crtc[12] << 8 | crtc[13]) + row * cols, n = 0;

	for (int c = 0; c < cols; c++) {
		uint8_t b = video[(start + c) & 0x7ff];
		if (b != ' ' && b != 0x7f) {
			n++;
			*last = b;
		}
	}
	return n;
}

static void screen_text(char *buf, size_t size)
{
	char line[400];
	int cc;
	size_t n = 0;

	buf[0] = 0;
	for (int r = 0; r < screen_rows(); r++) {
		screen_row(r, line, NULL, &cc);
		int len = strlen(line);
		while (len && line[len - 1] == ' ')
			line[--len] = 0;
		n += snprintf(buf + n, size - n, "%s\n", line);
		if (n >= size)
			break;
	}
}

static void screen_draw(void)
{
	char line[400];
	uint8_t rev[96];
	int cc, cur_r = -1, cur_c = 0;

	printf("\x1b[H");
	for (int r = 0; r < screen_rows(); r++) {
		screen_row(r, line, rev, &cc);
		/* walk the UTF-8 cells, switching reverse video on and off */
		const char *p = line;
		int on = 0;
		for (int c = 0; *p; c++) {
			if (rev[c] != on) {
				fputs(rev[c] ? "\x1b[7m" : "\x1b[27m", stdout);
				on = rev[c];
			}
			int len = (*p & 0x80) == 0 ? 1 : (*p & 0xe0) == 0xc0 ? 2
			    : (*p & 0xf0) == 0xe0 ? 3 : 4;
			fwrite(p, 1, len, stdout);
			p += len;
		}
		printf("%s\x1b[K\r\n", on ? "\x1b[27m" : "");
		if (cc >= 0) {
			cur_r = r;
			cur_c = cc;
		}
	}
	if (cur_r >= 0)
		printf("\x1b[%d;%dH", cur_r + 1, cur_c + 1);
	fflush(stdout);
}

/* ---- Video frame: the CRTC timing drawn as dots ---- */

/*
 * The whole frame as the CRTC times it, one byte a dot, 1 lit, 0 dark.
 * Everything comes from the registers: R0 and R4/R5/R9 give the frame
 * size, R1 and R6 the displayed part, R2/R3/R7 the syncs. The picture
 * starts where a monitor's beam does, at the end of each sync, so the
 * borders and the picture position follow the registers. The sync time
 * itself is left out.
 *
 * R8 interlace: mode 1 (sync only) draws each scan line on two image
 * lines, as both fields show the same thing. Mode 3 (sync and video)
 * draws a row's R9+1 raster lines once, split over the two fields.
 *
 * VLATCH bit 3 shows every second character twice as wide. Which of
 * each pair shows depends on the hsync phase; with the
 * BIOS values (R2 + HSW = 103) it is the even ones.
 *
 * Raster lines past 15 repeat the glyph rows (only RA0-RA3 are taken
 * to reach the font), and codes 00h-7Fh are blank past row 7. Neither is
 * measured. The CRTC cursor is not drawn: none of Lobo's OS disks uses it.
 */
#define DOT_HZ 15200000		/* 8 dots a 1.9 MHz character clock */
#define FRAME_W 2048
#define FRAME_H 4224
static uint8_t frame[FRAME_W * FRAME_H];

struct geom {
	int w, h;		/* image size in dots and lines */
	int x0, y0;		/* where the first displayed cell starts */
	int cell_w, cell_h;	/* one character cell in the image */
	int cols, rows;		/* displayed cells */
	double aspect;		/* width / height the picture would have */
};

/*
 * -B: the CRTC as counters stepped one character clock at a
 * time, caught up to the CPU before every write that changes the
 * picture, so each character is drawn from the registers, video RAM and
 * font RAM as they are when the beam passes it. Read from the HD6845
 * data sheet (App G), not measured on the HD46505R:
 *
 * - The horizontal counter runs 0 to R0. Display is on from 0 and off
 *   at R1. Hsync starts at R2 for R3 (bits 3-0) characters. The beam
 *   places what follows from the hsync that happened, so an R2 write
 *   moves the next line, not the rest of its own.
 * - At the end of a line the raster counter (5 bits) steps, and at R9
 *   it goes back to 0 and the row counter (7 bits) steps. Each compare
 *   is for equality, so a register written below its counter is passed
 *   and the counter wraps.
 * - Display goes off when the row counter reaches R6. After row R4,
 *   R5 adjust lines, then a new frame starts, reloading the start
 *   address from R12/R13. Mid-frame writes to R12/R13 wait for it.
 * - Vsync starts at the first line of row R7 and lasts 16 lines.
 *
 * The image is laid out as frame_draw's: x from the end of hsync, y
 * from the end of vsync, and a frame is shown from the end of each
 * vsync. A CPU write lands at the start of its instruction, a few
 * characters early. Interlace (R8 bit 0) falls back to frame_draw.
 */
#define RAST_H 1024
static uint8_t rast_img[2][FRAME_W * RAST_H];
static struct {
	unsigned long long at;	/* character clocks done */
	int hc, ra, vc, adj, in_adj, hdisp, vdisp, ma_row;
	int hs_left, vs_left, in_vs;
	int hs_end;		/* R2 + R3 as at the last hsync's start */
	int y, w;		/* the line being drawn, the widest line */
	int cur;		/* rast_img being drawn */
	int shown_w, shown_h;	/* the last whole frame, in rast_img[!cur] */
	int started;
} rs;

static void raster_frame(void)
{
	rs.vc = rs.ra = rs.adj = rs.in_adj = 0;
	rs.ma_row = (crtc[12] << 8 | crtc[13]) & 0x3fff;
	rs.vdisp = (crtc[6] & 0x7f) != 0;
}

static void raster_line(void)
{
	int lines_end = rs.ra == (crtc[9] & 0x1f);

	if (rs.in_vs && --rs.vs_left == 0) {	/* the end of vsync */
		rs.in_vs = 0;
		rs.shown_w = rs.w;
		rs.shown_h = rs.y < RAST_H ? rs.y : RAST_H;
		rs.cur ^= 1;
		rs.y = rs.w = 0;
	} else if (!rs.in_vs)
		rs.y++;
	if (rs.in_adj) {
		if (++rs.adj >= (crtc[5] & 0x1f))
			raster_frame();
	} else if (lines_end) {
		rs.ra = 0;
		rs.ma_row = (rs.ma_row + crtc[1]) & 0x3fff;
		if (rs.vc == (crtc[4] & 0x7f)) {
			if (crtc[5] & 0x1f)
				rs.in_adj = 1, rs.adj = 0;
			else
				raster_frame();
		} else
			rs.vc = (rs.vc + 1) & 0x7f;
		if (!rs.in_adj && rs.vc == (crtc[6] & 0x7f) && rs.vc)
			rs.vdisp = 0;
	} else
		rs.ra = (rs.ra + 1) & 0x1f;
	if (!rs.in_adj && rs.ra == 0 && rs.vc == (crtc[7] & 0x7f) && !rs.in_vs) {
		rs.in_vs = 1;
		rs.vs_left = 16;	/* fixed in the HD46505R */
	}
}

static void raster_run(void)
{
	unsigned long long to = cpu.cycles * 3 / 8;

	if (!rs.started) {	/* a frame starts at cycle 0, as dsptmg's formula */
		rs.started = 1;
		raster_frame();
		rs.hdisp = 1;
		rs.hs_end = crtc[2] + (crtc[3] & 0x0f);
	}

	for (; rs.at < to; rs.at++) {
		int htotal = crtc[0] + 1, hsw = crtc[3] & 0x0f;
		int hs_end = rs.hs_end;
		int c = rs.hc;

		if (c == crtc[1])
			rs.hdisp = 0;
		int x = ((c - hs_end) % htotal + htotal) % htotal;
		if (!rs.in_vs && x < htotal - hsw && x < FRAME_W / 8 && rs.y < RAST_H) {
			uint8_t *p = &rast_img[rs.cur][(size_t)rs.y * FRAME_W + x * 8];
			uint8_t bits = 0;
			int half = 0;
			if (rs.hdisp && rs.vdisp && !rs.in_adj) {
				int shown = c;
				if (vlatch & 8) {
					shown = (c + hs_end + 1) & 1 ? c - 1 : c;
					half = c != shown;
				}
				if (shown >= 0)
					bits = glyph_row(video[(rs.ma_row + shown) & 0x7ff], rs.ra & 15);
			}
			for (int d = 0; d < 8; d++) {
				int bit = vlatch & 8 ? 7 - (half * 8 + d) / 2 : 7 - d;
				p[d] = bits >> bit & 1;
			}
			if (x + 1 > rs.w)
				rs.w = x + 1;
		}
		if (rs.hs_left)
			rs.hs_left--;
		else if (c == crtc[2]) {
			rs.hs_left = hsw;
			rs.hs_end = crtc[2] + hsw;
		}
		if (c >= crtc[0]) {	/* the end of the line */
			rs.hc = 0;
			rs.hdisp = 1;
			raster_line();
		} else
			rs.hc++;
	}
}

static int raster_dsptmg(void)
{
	raster_run();
	return rs.hdisp && rs.hc < crtc[1] && rs.vdisp && !rs.in_adj;
}

/* The last whole frame into frame[], g->w x g->h */
static void raster_copy(const struct geom *g)
{
	raster_run();
	int w = rs.shown_w * 8 < g->w ? rs.shown_w * 8 : g->w;
	int h = rs.shown_h < g->h ? rs.shown_h : g->h;
	for (int y = 0; y < h; y++)
		memcpy(&frame[(size_t)y * g->w], &rast_img[!rs.cur][(size_t)y * FRAME_W], w);
}

static int frame_draw(struct geom *g)
{
	int htotal = crtc[0] + 1, hdisp = crtc[1], hsw = crtc[3] & 0x0f;
	int vtotal = (crtc[4] & 0x7f) + 1, vadj = crtc[5] & 0x1f;
	int vdisp = crtc[6] & 0x7f, vpos = crtc[7] & 0x7f;
	int mode = crtc[8] & 3, lines = (crtc[9] & 0x1f) + 1;
	int vsw = 16;		/* fixed in the HD46505R, R3 is HSYNC only */
	int il = mode & 1;		/* two fields to a frame */
	int rowh = mode == 1 ? lines * 2 : lines;
	int hs_end = crtc[2] + hsw, vs_start = vpos * rowh, vs_lines = vsw << il;
	int fh = vtotal * rowh + (vadj << il);
	int start = crtc[12] << 8 | crtc[13];

	/* -B: the frame drawn, whatever the registers say now: a program
	   that changes R4, R6 or R9 mid-frame leaves them describing a part
	   of it. The cell layout is the registers' still. */
	if (raster && !il) {
		raster_run();
		if (rs.shown_w > 0 && rs.shown_h > 0) {
			g->w = rs.shown_w * 8;
			g->h = rs.shown_h;
			g->cols = hdisp < htotal ? hdisp : htotal;
			g->rows = vdisp < vtotal ? vdisp : vtotal;
			g->cell_w = 8;
			g->cell_h = rowh;
			g->x0 = htotal > 1 ? ((0 - hs_end) % htotal + htotal) % htotal * 8 : 0;
			g->y0 = fh > 0 ? ((0 - vs_start - vs_lines) % fh + fh) % fh : 0;
			g->aspect = (double)g->w / DOT_HZ / 52.6e-6 * 4
			    / ((double)g->h / 242 * 3);
			memset(frame, 0, (size_t)g->w * g->h);
			raster_copy(g);
			return 1;
		}
	}
	if (htotal < 2 || hdisp == 0 || vdisp == 0)
		return 0;
	g->w = (htotal - hsw) * 8;
	g->h = fh - vs_lines;
	if (g->w <= 0 || g->w > FRAME_W || g->h > FRAME_H || g->h <= 0)
		return 0;
	memset(frame, 0, (size_t)g->w * g->h);
	g->cols = hdisp < htotal ? hdisp : htotal;
	g->rows = vdisp < vtotal ? vdisp : vtotal;
	g->cell_w = 8;
	g->cell_h = rowh;
	g->x0 = ((0 - hs_end) % htotal + htotal) % htotal * 8;
	g->y0 = ((0 - vs_start - vs_lines) % fh + fh) % fh;
	/* A monitor scans about 52.6 us of each line across 4 units, and
	   242 lines of each field down 3 */
	g->aspect = (double)g->w / DOT_HZ / 52.6e-6 * 4
	    / ((double)g->h / (1 + il) / 242 * 3);

	for (int r = 0; r < g->rows; r++)
		for (int c = 0; c < g->cols; c++) {
			int x = ((c - hs_end) % htotal + htotal) % htotal * 8;
			if (x >= g->w)
				continue;	/* during hsync */
			int shown = c, half = 0;
			if (vlatch & 8) {
				shown = (c + hs_end + 1) & 1 ? c - 1 : c;
				half = c != shown;
				if (shown < 0)
					continue;
			}
			uint8_t b = video[(start + r * hdisp + shown) & 0x7ff];
			for (int l = 0; l < rowh; l++) {
				int y = ((r * rowh + l - vs_start - vs_lines) % fh + fh) % fh;
				if (y >= g->h)
					continue;	/* during vsync */
				int ra = (mode == 1 ? l / 2 : l) & 15;
				uint8_t bits = glyph_row(b, ra);
				uint8_t *p = &frame[(size_t)y * g->w + x];
				for (int d = 0; d < 8; d++) {
					int bit = vlatch & 8 ? 7 - (half * 8 + d) / 2 : 7 - d;
					p[d] = bits >> bit & 1;
				}
			}
		}
	return 1;
}

/* The frame as a PGM file, with the cell layout in a comment */
static int frame_save(const char *path)
{
	struct geom g;
	FILE *f;

	if (!frame_draw(&g)) {
		fprintf(stderr, "%s: the CRTC is not set up, no frame\n", path);
		return 1;
	}
	f = fopen(path, "wb");
	if (!f) {
		perror(path);
		return 1;
	}
	fprintf(f, "P5\n# cells %d %d %d %d %d %d aspect %.4f\n%d %d\n255\n",
	    g.x0, g.y0, g.cell_w, g.cell_h, g.cols, g.rows, g.aspect, g.w, g.h);
	for (size_t i = 0; i < (size_t)g.w * g.h; i++)
		fputc(frame[i] ? 255 : 0, f);
	return fclose(f) != 0;
}

/* ---- Sound: the beep as 16-bit samples ---- */

#define RATE 48000
#define TICK_SAMPLES (RATE / 60)

/* One tick of sound, the CPU cycles from..from+TICK_T */
static void sound_tick(unsigned long long from, int16_t *out)
{
	for (int i = 0; i < TICK_SAMPLES; i++) {
		unsigned long long c = from + (unsigned long long)i * TICK_T / TICK_SAMPLES;
		int on = 0;
		for (int b = 0; b < nbeeps; b++)
			if (c >= beeps[b].start && c < beeps[b].end)
				on = 1;
		out[i] = on ? (c * 2 * BEEP_NUM / (BEEP_DEN * CPU_HZ) & 1 ? 6000 : -6000) : 0;
	}
	/* drop the beeps that are over */
	int keep = 0;
	for (int b = 0; b < nbeeps; b++)
		if (beeps[b].end > from + TICK_T)
			beeps[keep++] = beeps[b];
	nbeeps = keep;
}

/* A mono 16-bit WAV file of the whole run, in emulated time */
static FILE *wav;
static unsigned long wav_samples;

static int wav_open(const char *path)
{
	static const uint8_t head[44] = { 'R', 'I', 'F', 'F', 0, 0, 0, 0,
	    'W', 'A', 'V', 'E', 'f', 'm', 't', ' ', 16, 0, 0, 0, 1, 0, 1, 0,
	    RATE & 0xff, RATE >> 8 & 0xff, 0, 0, (RATE * 2) & 0xff,
	    (RATE * 2) >> 8 & 0xff, (RATE * 2) >> 16 & 0xff, 0, 2, 0, 16, 0,
	    'd', 'a', 't', 'a', 0, 0, 0, 0 };

	wav = fopen(path, "wb");
	if (!wav || fwrite(head, 1, 44, wav) != 44) {
		perror(path);
		return 1;
	}
	return 0;
}

static void put32(FILE *f, long at, uint32_t v)
{
	uint8_t b[4] = { v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24 };
	fseek(f, at, SEEK_SET);
	fwrite(b, 1, 4, f);
}

static void wav_close(void)
{
	if (!wav)
		return;
	put32(wav, 4, 36 + wav_samples * 2);
	put32(wav, 40, wav_samples * 2);
	fclose(wav);
	wav = NULL;
}

/* ---- Keyboard: host characters to matrix presses ---- */

struct key { int row, bit, shift, ctrl; };

/* Keys with no character, queued as codes 80h and up */
enum { K_UP = 0x80, K_DOWN, K_LEFT, K_RIGHT, K_F1, K_F2, K_F3, K_F4,
       K_BREAK, K_ENTER, K_PAUSE };

/*
 * -K: type letters in the case written under xcpmz80, which boots with
 * Caps Lock on: SHIFT for lower case while it is on. Its flag is KCAPS,
 * F52Fh in the I/O block, so A1's 752Fh, 0 on and 20h off (VI turns it
 * off while it runs), read as each key goes down.
 */
static int caps_swap;

static int caps_on(void)
{
	return caps_swap && ram[0][0x752f] != 0x20;
}

static int key_for(int ch, struct key *k)
{
	static const char *row3 = "[\\]^_";
	static const char *row5 = "89:;,-./";
	static const char *shifted = "!\"#$%&'()*+<=>?";
	static const char *unshift = "1234567890:;,-./";

	memset(k, 0, sizeof(*k));
	if (ch >= K_UP && ch <= K_RIGHT) {	/* row 6, bits 3-6 */
		k->row = 6;
		k->bit = 3 + ch - K_UP;
		return 1;
	}
	if (ch == K_BREAK || ch == K_ENTER) {	/* row 6, bits 2 and 0 */
		k->row = 6;
		k->bit = ch == K_BREAK ? 2 : 0;
		return 1;
	}
	if (ch >= K_F1 && ch <= K_F4) {		/* row 7, bits 1-4 */
		k->row = 7;
		k->bit = 1 + ch - K_F1;
		return 1;
	}
	if (ch >= 'a' && ch <= 'z') {
		k->row = (ch - 'a' + 1) / 8;
		k->bit = (ch - 'a' + 1) % 8;
		k->shift = caps_on();
		return 1;
	}
	if (ch >= 'A' && ch <= 'Z') {
		key_for(ch - 'A' + 'a', k);
		k->shift = !caps_on();
		return 1;
	}
	if (ch >= 1 && ch <= 26 && ch != '\r' && ch != '\n' && ch != '\b' &&
	    ch != 3) {	/* LF types ENTER, as CR does */
		key_for(ch - 1 + 'a', k);
		k->shift = 0;
		k->ctrl = 1;
		return 1;
	}
	if (ch == '@') { k->row = 0; k->bit = 0; return 1; }
	if (ch && strchr("`{|}~", ch)) {	/* SHIFT on @ [ \\ ] ^ */
		key_for(ch ^ 0x20, k);
		k->shift = 1;
		return 1;
	}
	if (ch >= '0' && ch <= '7') { k->row = 4; k->bit = ch - '0'; return 1; }
	if (strchr(row5, ch) && ch) {
		k->row = 5;
		k->bit = strchr(row5, ch) - row5;
		return 1;
	}
	if (strchr(row3, ch) && ch) {
		k->row = 3;
		k->bit = 3 + (strchr(row3, ch) - row3);
		return 1;
	}
	if (strchr(shifted, ch) && ch) {
		/* TRS-80 layout: shift 1-9 give !"#$%&'(), shift :;,-./ give *+<=>? */
		int i = strchr(shifted, ch) - shifted;
		key_for(unshift[i < 9 ? i : i + 1], k);
		k->shift = 1;
		return 1;
	}
	switch (ch) {
	case '\r': case '\n': k->row = 6; k->bit = 0; return 1;
	case '\b': case 0x7f: k->row = 6; k->bit = 1; return 1;
	case 3: k->row = 6; k->bit = 2; return 1;
	case ' ': k->row = 6; k->bit = 7; return 1;
	case 0x1b: k->row = 7; k->bit = 5; return 1;
	}
	return 0;
}

#define KEYQ 4096
static char keyq[KEYQ];
static int keyq_head, keyq_tail;
static int key_phase;		/* ticks left in the current press or gap */
static struct key key_down;
static int key_pressed;

#define HOLD_TICKS 3
#define GAP_TICKS 3

/* Scripted keys (-k) wait after each Enter until the cursor line shows
   the prompt again, so nothing is typed ahead of the program. */
static int scripted, script_wait;
static const char *prompt = "A>";

/* The screen when Enter was pressed: a prompt counts only once the
   screen has changed since */
static uint32_t enter_sig;
static int entered;

/*
 * The prompt is up when the last line with text on it is the prompt. A
 * line holding only a cursor does not count: CP/M's 7Fh, or the one
 * graphics character LDOS blinks under the prompt. After an Enter the
 * screen must have changed first, so a prompt still showing from
 * before the Enter is not taken for the next one.
 */
static int last_line(char *line, int *row)
{
	int cc;

	for (int r = screen_rows() - 1; r >= 0; r--) {
		screen_row(r, line, NULL, &cc);
		int len = strlen(line);
		while (len && line[len - 1] == ' ')
			line[--len] = 0;
		int start = 0;
		while (line[start] == ' ')
			start++;
		if (len == 0)
			continue;
		int mark = 0;
		if (row_marks(r, &mark) == 1 && mark >= 0x80)
			continue;	/* a graphics cursor, not text */
		*row = r;
		return 1;
	}
	line[0] = 0;
	*row = -1;
	return 0;
}

/* A hash of the screen as shown, each row less its trailing blanks and
   cursor (7Fh, or a graphics code at the end of the text) */
static uint32_t screen_sig(void)
{
	int cols = screen_cols();
	int start = crtc[12] << 8 | crtc[13];
	uint32_t h = 2166136261u;

	for (int r = 0; r < screen_rows(); r++) {
		const int base = start + r * cols;
		int end = cols;
		while (end > 0) {
			uint8_t b = video[(base + end - 1) & 0x7ff];
			if (b != ' ' && b != 0x7f && b < 0x80)
				break;
			end--;
		}
		for (int c = 0; c < end; c++)
			h = (h ^ video[(base + c) & 0x7ff]) * 16777619u;
		h = (h ^ '\n') * 16777619u;
	}
	return h;
}

static void note_enter(void)
{
	enter_sig = screen_sig();
	entered = 1;
}

static int prompt_ready(void)
{
	char line[400];
	int row;

	if (!last_line(line, &row))
		return 0;
	if (entered && screen_sig() == enter_sig)
		return 0;	/* nothing new since the Enter */
	/* -e may list several prompts, such as "A>|B>" */
	for (const char *p = prompt; *p; ) {
		size_t n = strcspn(p, "|");
		if (strlen(line) == n && !strncmp(line, p, n))
			return 1;
		p += n + (p[n] == '|');
	}
	return 0;
}

static void key_queue(const char *s, int n)
{
	for (int i = 0; i < n; i++) {
		int next = (keyq_tail + 1) % KEYQ;
		if (next == keyq_head)
			break;
		keyq[keyq_tail] = s[i];
		keyq_tail = next;
	}
}

static void key_tick(void)
{
	if (key_phase > 0 && --key_phase > 0)
		return;
	memset(keyrow, 0, sizeof(keyrow));
	if (key_pressed) {
		key_pressed = 0;
		key_phase = GAP_TICKS;
		return;
	}
	if (script_wait) {
		if (!prompt_ready())
			return;
		script_wait = 0;
		/* a pause after the prompt, as a typist's, since a program
		 * may still be clearing type-ahead when it shows */
		key_phase = GAP_TICKS;
		return;
	}
	while (keyq_head != keyq_tail) {
		int ch = (unsigned char)keyq[keyq_head];
		keyq_head = (keyq_head + 1) % KEYQ;
		if (ch == K_PAUSE) {
			key_phase = 61;		/* a second */
			return;
		}
		if (!key_for(ch, &key_down))
			continue;
		keyrow[key_down.row] |= 1 << key_down.bit;
		if (key_down.shift)
			keyrow[7] |= 0x01;
		if (key_down.ctrl)
			keyrow[7] |= 0x80;
		key_pressed = 1;
		key_phase = HOLD_TICKS;
		if (scripted && ch == '\r') {
			script_wait = 1;
			note_enter();
		}
		return;
	}
}

/* ---- Terminal ---- */

static struct termios saved_tio;
static int tty;

static void tty_restore(void)
{
	if (tty) {
		tcsetattr(0, TCSANOW, &saved_tio);
		printf("\x1b[?25h\r\n");
		fflush(stdout);
	}
}

static void tty_raw(void)
{
	struct termios t;

	if (tcgetattr(0, &saved_tio) != 0)
		return;
	tty = 1;
	atexit(tty_restore);
	t = saved_tio;
	t.c_lflag &= ~(ICANON | ECHO | ISIG | IEXTEN);
	t.c_iflag &= ~(ICRNL | IXON | INLCR);
	t.c_cc[VMIN] = 0;
	t.c_cc[VTIME] = 0;
	tcsetattr(0, TCSANOW, &t);
	fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);
	printf("\x1b[2J");
}

/* ---- Window (SDL2): the frame as dots, keys typed into it ---- */

#ifdef HAVE_SDL
static SDL_Window *win;
static SDL_Renderer *ren;
static SDL_Texture *tex;
static int tex_w, tex_h;
static uint32_t pixels[FRAME_W * FRAME_H];
static uint8_t shown[FRAME_W * FRAME_H];	/* the frame in the texture */
static int shown_w, shown_h;

static SDL_AudioDeviceID audio;

static int win_open(void)
{
	SDL_AudioSpec want = { 0 };

	if (SDL_Init(SDL_INIT_VIDEO) != 0) {
		fprintf(stderr, "SDL: %s\n", SDL_GetError());
		return 1;
	}
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");
	win = SDL_CreateWindow("MAX-80", SDL_WINDOWPOS_CENTERED,
	    SDL_WINDOWPOS_CENTERED, 1024, 768,
	    SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
	ren = win ? SDL_CreateRenderer(win, -1, 0) : NULL;
	if (!ren) {
		fprintf(stderr, "SDL: %s\n", SDL_GetError());
		return 1;
	}
	SDL_StartTextInput();
	/* no sound device is no reason to stop */
	if (SDL_InitSubSystem(SDL_INIT_AUDIO) == 0) {
		want.freq = RATE;
		want.format = AUDIO_S16SYS;
		want.channels = 1;
		want.samples = 512;
		audio = SDL_OpenAudioDevice(NULL, 0, &want, NULL, 0);
		if (audio)
			SDL_PauseAudioDevice(audio, 0);
	}
	if (!audio)
		fprintf(stderr, "SDL: no sound, %s\n", SDL_GetError());
	return 0;
}

/* One tick of sound to the device. Silence is queued too, to keep the
   timing, but never more than a tenth of a second ahead, so -f and a
   slow host drop sound rather than lag. */
static void win_sound(const int16_t *snd)
{
	if (audio && SDL_GetQueuedAudioSize(audio) < RATE / 10 * 2)
		SDL_QueueAudio(audio, snd, TICK_SAMPLES * 2);
}

static void win_draw(void)
{
	struct geom g;
	int ww, wh;

	SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
	SDL_RenderClear(ren);
	if (frame_draw(&g)) {
		if (!tex || g.w != tex_w || g.h != tex_h) {
			if (tex)
				SDL_DestroyTexture(tex);
			tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_ARGB8888,
			    SDL_TEXTUREACCESS_STREAMING, g.w, g.h);
			tex_w = g.w;
			tex_h = g.h;
			shown_w = 0;
		}
		/* an upload can take 20 ms on some hosts: only a
		   changed picture is sent */
		size_t n = (size_t)g.w * g.h;
		if (g.w != shown_w || g.h != shown_h || memcmp(frame, shown, n)) {
			for (size_t i = 0; i < n; i++)
				pixels[i] = frame[i] ? 0xffe8e8e8 : 0xff000000;
			SDL_UpdateTexture(tex, NULL, pixels, g.w * 4);
			memcpy(shown, frame, n);
			shown_w = g.w;
			shown_h = g.h;
		}
		/* the largest picture of the right shape that fits */
		SDL_GetRendererOutputSize(ren, &ww, &wh);
		SDL_Rect dst = { 0, 0, ww, (int)(ww / g.aspect) };
		if (dst.h > wh) {
			dst.h = wh;
			dst.w = (int)(wh * g.aspect);
		}
		dst.x = (ww - dst.w) / 2;
		dst.y = (wh - dst.h) / 2;
		SDL_RenderCopy(ren, tex, NULL, &dst);
	}
	SDL_RenderPresent(ren);
}

/* A key down in the window with no Shift, Ctrl, Alt or Cmd is held in
   the matrix until it comes up, as on the machine, and the host's
   auto repeat is left out: programs that read the matrix see it held,
   and the BIOS repeats it itself. Its scancode keeps the matrix
   bit to let go. Other keys still go through the key queue, so a
   shifted symbol comes out as typed. Returns 1 when held. */
static uint8_t held_at[SDL_NUM_SCANCODES];	/* row x 8 + bit + 1 */

static int key_hold(const SDL_KeyboardEvent *ev)
{
	int sym = ev->keysym.sym, ch = 0;
	struct key k;

	if (ev->keysym.mod & (KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI))
		return 0;
	if ((ev->keysym.mod & KMOD_CAPS) && sym >= SDLK_a && sym <= SDLK_z)
		return 0;	/* the capital comes through the queue */
	switch (sym) {
	case SDLK_RETURN: case SDLK_KP_ENTER: ch = '\r'; break;
	case SDLK_BACKSPACE: ch = '\b'; break;
	case SDLK_ESCAPE: ch = 0x1b; break;
	case SDLK_UP: ch = K_UP; break;
	case SDLK_DOWN: ch = K_DOWN; break;
	case SDLK_LEFT: ch = K_LEFT; break;
	case SDLK_RIGHT: ch = K_RIGHT; break;
	case SDLK_F1: case SDLK_F2: case SDLK_F3: case SDLK_F4:
		ch = K_F1 + sym - SDLK_F1;
		break;
	default:
		if (sym >= ' ' && sym < 0x7f)
			ch = sym;
	}
	if (!ch || !key_for(ch, &k) || k.shift || k.ctrl)
		return 0;
	if (!ev->repeat) {
		keyheld[k.row] |= 1 << k.bit;
		held_at[ev->keysym.scancode] = k.row * 8 + k.bit + 1;
	}
	return 1;
}

static void key_unhold(SDL_Scancode sc)
{
	int at = held_at[sc];

	if (!at)
		return;
	held_at[sc] = 0;
	for (int i = 0; i < SDL_NUM_SCANCODES; i++)
		if (held_at[i] == at)
			return;		/* another key holds the same bit */
	keyheld[(at - 1) / 8] &= ~(1 << ((at - 1) % 8));
}

/* Window events into the key matrix or the key queue. Returns 1 to
   quit. */
static int win_events(void)
{
	SDL_Event e;
	char ch;
	static int text_held;	/* the next text is a held key's: skip it */

	while (SDL_PollEvent(&e)) {
		switch (e.type) {
		case SDL_QUIT:
			return 1;
		case SDL_WINDOWEVENT:
			if (e.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
				memset(held_at, 0, sizeof(held_at));
				memset(keyheld, 0, sizeof(keyheld));
			}
			break;
		case SDL_KEYUP:
			key_unhold(e.key.keysym.scancode);
			break;
		case SDL_TEXTINPUT:
			if (text_held) {
				text_held = 0;
				break;
			}
			for (const char *p = e.text.text; *p; p++)
				if (!(*p & 0x80))
					key_queue(p, 1);
			break;
		case SDL_KEYDOWN:
			text_held = key_hold(&e.key);
			if (text_held) {
				/* only printable keys bring a text event */
				int sym = e.key.keysym.sym;
				if (sym < ' ' || sym >= 0x7f)
					text_held = 0;
				break;
			}
			ch = 0;
			switch (e.key.keysym.sym) {
			case SDLK_RETURN: case SDLK_KP_ENTER: ch = '\r'; break;
			case SDLK_BACKSPACE: ch = '\b'; break;
			case SDLK_ESCAPE: ch = 0x1b; break;
			case SDLK_UP: ch = K_UP; break;
			case SDLK_DOWN: ch = K_DOWN; break;
			case SDLK_LEFT: ch = K_LEFT; break;
			case SDLK_RIGHT: ch = K_RIGHT; break;
			case SDLK_F1: case SDLK_F2: case SDLK_F3: case SDLK_F4:
				ch = K_F1 + e.key.keysym.sym - SDLK_F1;
				break;
			default:
				if (e.key.keysym.mod & KMOD_CTRL) {
					int k = e.key.keysym.sym;
					if (k == SDLK_RIGHTBRACKET)
						return 1;
					if (k >= SDLK_a && k <= SDLK_z)
						ch = k - SDLK_a + 1;
				}
			}
			if (ch)
				key_queue(&ch, 1);
			break;
		}
	}
	return 0;
}
#endif

/* Terminal input into the key queue. The arrows (ESC [ A-D) and F1-F4
   (ESC O P-S) arrive as escape sequences, other bytes as they are. */
static void tty_keys(const char *in, int n)
{
	for (int i = 0; i < n; i++) {
		char ch = in[i];
		if (ch == 0x1b && i + 2 < n && (in[i + 1] == '[' || in[i + 1] == 'O')) {
			const char *p = in[i + 2] ? strchr(in[i + 1] == '[' ? "ABDC" : "PQRS", in[i + 2]) : NULL;
			if (p) {
				ch = in[i + 1] == '[' ? K_UP + (p - "ABDC") : K_F1 + (p - "PQRS");
				i += 2;
			}
		} else if (ch & 0x80)
			continue;
		key_queue(&ch, 1);
	}
}

/* The folder a file is in, resolved, or "" */
static void folder_of(const char *path, char *out)
{
	char tmp[PATH_MAX];

	snprintf(tmp, sizeof(tmp), "%s", path);
	if (!realpath(dirname(tmp), out))
		out[0] = 0;
}

/*
 * -w never writes over a loaded image, or into the folder one came from,
 * so an archived disk is never changed.
 */
static int save_allowed(const char *path)
{
	char dir[PATH_MAX], other[PATH_MAX];
	struct stat a, b;

	folder_of(path, dir);
	if (!dir[0]) {
		fprintf(stderr, "%s: no such folder\n", path);
		return 0;
	}
	for (int i = 0; i < 5; i++) {	/* drives A-D, then the hard disk */
		const char *p = i < 4 ? disks[i].path : sasi.path;
		int name = i < 4 ? 'A' + i : 'H';
		if (!p)
			continue;
		if (stat(path, &a) == 0 && stat(p, &b) == 0 &&
		    a.st_dev == b.st_dev && a.st_ino == b.st_ino) {
			fprintf(stderr, "%s: that is the image in drive %c, -w "
			    "writes a new file\n", path, name);
			return 0;
		}
		folder_of(p, other);
		if (!strcmp(dir, other)) {
			fprintf(stderr, "%s: the folder of the image in drive %c, "
			    "-w writes elsewhere\n", path, name);
			return 0;
		}
	}
	return 1;
}

static void sleep_until(struct timespec *t)
{
	clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, t, NULL);
}

static const char *unescape(const char *s, int *n)
{
	static char out[KEYQ];
	int j = 0;
	for (int i = 0; s[i] && j < KEYQ - 1; i++) {
		if (s[i] == '\\' && s[i + 1]) {
			i++;
			const char *sp = strchr("UDLR1234", s[i]);
			out[j++] = s[i] == 'r' ? '\r' : s[i] == 'n' ? '\r' :
			    s[i] == 'e' ? 0x1b : s[i] == 'B' ? K_BREAK :
			    s[i] == 'E' ? K_ENTER : s[i] == 'P' ? K_PAUSE :
			    sp ? K_UP + (sp - "UDLR1234") : s[i];
		} else
			out[j++] = s[i];
	}
	*n = j;
	return out;
}

#ifdef __linux__
/*
 * Debug sockets. Polled once a tick, so
 * a dump always sees the machine between two instructions.
 */
static char DBG_REGS[64] = "/tmp/max80.sock";
static char DBG_MEM[64] = "/tmp/max80_mem.sock";
static char DBG_KBD[64] = "/tmp/max80_kbd.sock";
static int dbg_regs = -1, dbg_mem = -1, dbg_kbd = -1, dbg_kbdcl = -1;
static volatile sig_atomic_t dbg_stop;	/* SIGTERM: end the run as usual */

static void dbg_term(int sig)
{
	(void)sig;
	dbg_stop = 1;
}

static int dbg_listen(const char *path)
{
	struct sockaddr_un addr;
	int s = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
	if (s < 0)
		return -1;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
	unlink(path);
	if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(s, 4) < 0) {
		perror(path);
		close(s);
		return -1;
	}
	return s;
}

static void dbg_close(void)
{
	if (dbg_regs >= 0)
		unlink(DBG_REGS);
	if (dbg_mem >= 0)
		unlink(DBG_MEM);
	if (dbg_kbd >= 0)
		unlink(DBG_KBD);
}

/* -N: the sockets' names with the instance name appended */
static void dbg_name(const char *inst)
{
	snprintf(DBG_REGS, sizeof(DBG_REGS), "/tmp/max80_%s.sock", inst);
	snprintf(DBG_MEM, sizeof(DBG_MEM), "/tmp/max80_mem_%s.sock", inst);
	snprintf(DBG_KBD, sizeof(DBG_KBD), "/tmp/max80_kbd_%s.sock", inst);
}

static int dbg_open(void)
{
	dbg_regs = dbg_listen(DBG_REGS);
	dbg_mem = dbg_listen(DBG_MEM);
	dbg_kbd = dbg_listen(DBG_KBD);
	atexit(dbg_close);
	signal(SIGTERM, dbg_term);
	/* a client gone before its answer is a failed write, not the end
	   of the emulator and its -w saves */
	signal(SIGPIPE, SIG_IGN);
	if (dbg_regs < 0 || dbg_mem < 0 || dbg_kbd < 0)
		return 1;
	fprintf(stderr, "debug sockets: %s, %s, %s\n", DBG_REGS, DBG_MEM, DBG_KBD);
	return 0;
}

static void dbg_send(int cl, const char *buf, int n)
{
	while (n > 0) {
		int w = write(cl, buf, n);
		if (w <= 0)
			break;
		buf += w;
		n -= w;
	}
}

static const char *chunk_name[4] = { "A1", "A2", "B1", "B2" };

/* A byte as the CPU sees it now, without the side effects of reading
   the I/O registers at block+7E0h-7FFh: the RAM under them is shown */
static uint8_t dbg_peek(uint16_t a)
{
	if ((a >> 12) == (vlatch >> 4) && (a & 0xfff) >= 0x7e0 && (a & 0xfff) < 0x800)
		return *block_ram(a);
	return mem_read(NULL, a);
}

static void dbg_regdump(int cl)
{
	char buf[1024];
	int n = 0;
	uint8_t *r = cpu.r, *x = cpu.alt;
	n += sprintf(buf + n, "PC=%04X SP=%04X AF=%02X%02X BC=%02X%02X DE=%02X%02X HL=%02X%02X\n",
	    cpu.pc, cpu.sp, r[7], r[6], r[0], r[1], r[2], r[3], r[4], r[5]);
	n += sprintf(buf + n, "IX=%04X IY=%04X AF'=%02X%02X BC'=%02X%02X DE'=%02X%02X HL'=%02X%02X\n",
	    cpu.ix, cpu.iy, x[7], x[6], x[0], x[1], x[2], x[3], x[4], x[5]);
	n += sprintf(buf + n, "I=%02X IM=%d IFF1=%d IFF2=%d halted=%d cycles=%llu\n",
	    cpu.i, cpu.im, cpu.iff1, cpu.iff2, cpu.halted, cpu.cycles);
	n += sprintf(buf + n, "VLATCH=%02X (I/O block %X000h) PIO A=%02X (%s low, %s high)\n",
	    vlatch, vlatch >> 4, pio_a, chunk_name[(pio_a >> 4) & 3], chunk_name[(pio_a >> 6) & 3]);
	n += sprintf(buf + n, "at PC:");
	for (int i = 0; i < 8; i++)
		n += sprintf(buf + n, " %02X", dbg_peek(cpu.pc + i));
	n += sprintf(buf + n, "\nstack:");
	for (int i = 0; i < 8; i++)
		n += sprintf(buf + n, " %04X", dbg_peek(cpu.sp + 2 * i) | dbg_peek(cpu.sp + 2 * i + 1) << 8);
	n += sprintf(buf + n, "\n");
	dbg_send(cl, buf, n);
}

static void free_tracks(struct disk *k)
{
	for (int c = 0; c < MAXCYL; c++)
		for (int h = 0; h < 2; h++) {
			struct track *t = &k->trk[c][h];
			for (int i = 0; t->sec && i < t->nsec; i++)
				free(t->sec[i].data);
			free(t->sec);
		}
	memset(k->trk, 0, sizeof(k->trk));
}

/* A disk swapped: the new image loaded aside, and only when it loads
   are drive d's tracks freed and the new ones put in. Not while the FDC
   has a command going, which may hold a sector of the old disk.
   -w still saves the drive at exit, now this disk. 1 busy, -1 no disk */
static int swap_disk(int d, const char *path)
{
	static struct disk tmp;
	struct disk *k = &disks[d];
	char *p;

	if (fdc.busy)
		return 1;
	p = strdup(path);
	memset(&tmp, 0, sizeof(tmp));
	tmp.three = k->three;	/* -3 stays as it was: a drive, not a disk */
	if (!p || load_imd(&tmp, p)) {
		free_tracks(&tmp);
		free(p);
		return -1;
	}
	free_tracks(k);
	fdc.cur = NULL;
	memcpy(k->trk, tmp.trk, sizeof(k->trk));
	k->three = tmp.three;
	k->one = tmp.one;
	k->loaded = 1;
	k->path = p;
	return 0;
}

/* "ADDR LEN" in hex: as the CPU sees it now. "ADDR LEN chunk", chunk
   A1, A2, B1 or B2: that 32K chunk of RAM, ADDR from 0 to 7FFF. Chunk V:
   video RAM, ADDR from 0 to 7FF. "screen": the screen as text, as -t
   prints it. "disk b NEW.imd": a disk swapped, "ok" or why not */
static void dbg_memdump(int cl)
{
	char req[600], name[8] = "", buf[20000];
	unsigned addr = 0, len = 16;
	int nr, n = 0, chunk = -1;
	for (int tries = 0; tries < 100; tries++) {	/* the request may lag */
		nr = read(cl, req, sizeof(req) - 1);
		if (nr > 0 || nr == 0)
			break;
		struct timespec ts = { 0, 1000000 };
		nanosleep(&ts, NULL);
	}
	if (nr <= 0)
		return;
	req[nr] = 0;
	if (!strncmp(req, "screen", 6)) {
		static char text[16384];
		screen_text(text, sizeof(text));
		dbg_send(cl, text, strlen(text));
		return;
	}
	if (!strncmp(req, "disk ", 5)) {
		char *path = req + 7;
		int r;
		if (nr >= 8)	/* else path is past the request's end */
			path[strcspn(path, "\r\n")] = 0;
		if (nr < 8 || req[5] < 'a' || req[5] > 'd' || req[6] != ' ' ||
		    !*path) {
			dbg_send(cl, "usage: disk a|b|c|d NEW.imd\n", 28);
			return;
		}
		r = swap_disk(req[5] - 'a', path);
		if (r > 0)
			dbg_send(cl, "busy, try again\n", 16);
		else if (r)
			dbg_send(cl, "no disk swapped\n", 16);
		else
			dbg_send(cl, "ok\n", 3);
		return;
	}
	if (sscanf(req, "%x %x %7s", &addr, &len, name) < 1) {
		dbg_send(cl, "usage: ADDR LEN [A1|A2|B1|B2|V], in hex\n", 40);
		return;
	}
	for (int i = 0; i < 4; i++)
		if (!strcasecmp(name, chunk_name[i]))
			chunk = i;
	if (!strcasecmp(name, "V"))
		chunk = 4;	/* video RAM, ADDR from 0 to 7FF */
	if (name[0] && chunk < 0) {
		dbg_send(cl, "the chunk is A1, A2, B1, B2 or V\n", 33);
		return;
	}
	if (len > 4096)
		len = 4096;
	for (unsigned i = 0; i < len; i += 16) {
		n += sprintf(buf + n, "%04X:", (addr + i) & 0xffff);
		for (unsigned j = 0; j < 16 && i + j < len; j++) {
			uint16_t a = addr + i + j;
			n += sprintf(buf + n, " %02X", chunk < 0 ? dbg_peek(a) :
			    chunk == 4 ? video[a & 0x7ff] : ram[chunk][a & 0x7fff]);
		}
		n += sprintf(buf + n, "\n");
	}
	dbg_send(cl, buf, n);
}

static void dbg_poll(void)
{
	int cl;
	if (dbg_regs >= 0 && (cl = accept(dbg_regs, NULL, NULL)) >= 0) {
		dbg_regdump(cl);
		close(cl);
	}
	if (dbg_mem >= 0 && (cl = accept(dbg_mem, NULL, NULL)) >= 0) {
		fcntl(cl, F_SETFL, O_NONBLOCK);	/* never wait long on a client */
		dbg_memdump(cl);
		close(cl);
	}
	if (dbg_kbd >= 0 && dbg_kbdcl < 0 && (dbg_kbdcl = accept(dbg_kbd, NULL, NULL)) >= 0)
		fcntl(dbg_kbdcl, F_SETFL, O_NONBLOCK);
	/* read only while the key queue has room, so the socket holds the
	   rest and nothing is lost */
	if (dbg_kbdcl >= 0 && (keyq_head - keyq_tail - 1 + KEYQ) % KEYQ >= 64) {
		char in[64];
		int n = read(dbg_kbdcl, in, sizeof(in));
		if (n > 0)
			tty_keys(in, n);
		else if (n == 0) {
			close(dbg_kbdcl);
			dbg_kbdcl = -1;
		}
	}
}
#endif

int main(int argc, char **argv)
{
	const char *rompath = "../reference/rom/max80.e12";
	const char *keys = NULL, *pgm = NULL, *wavpath = NULL, *inst = NULL;
	double seconds = 0;
	int fast = 0, opt, typed = 0, window = 0, debug = 0, show_lost = 0;
	FILE *f;

#ifdef HAVE_SDL
	window = 1;
#endif
	while ((opt = getopt(argc, argv, "r:a:b:c:d:h:n:R:3:w:D:fk:e:t:Tp:s:gl:o:i:I:F:x:m:CBV:S:LKMG:N:")) != -1) {
		switch (opt) {
		case 'r': rompath = optarg; break;
		case 'a': case 'b': case 'c': case 'd':
			if (load_imd(&disks[opt - 'a'], optarg))
				return 1;
			break;
		case 'h':	/* SASI hard disk, raw 512-byte blocks */
			if (load_hd(optarg))
				return 1;
			break;
		case 'n':	/* a blank, unformatted disk */
			if (optarg[0] < 'a' || optarg[0] > 'd' || optarg[1])
				return fprintf(stderr, "-n takes a drive, a to d\n"), 2;
			disks[optarg[0] - 'a'].loaded = 1;
			break;
		case '3':	/* a 3.5-inch drive, 300 rpm */
			if (optarg[0] < 'a' || optarg[0] > 'd' || optarg[1])
				return fprintf(stderr, "-3 takes a drive, a to d\n"), 2;
			disks[optarg[0] - 'a'].three = 1;
			break;
		case 'R':	/* a write-protected disk */
			if (optarg[0] < 'a' || optarg[0] > 'd' || optarg[1])
				return fprintf(stderr, "-R takes a drive, a to d\n"), 2;
			disks[optarg[0] - 'a'].wprot = 1;
			break;
		case 'w':	/* drive:file.imd, or h:file.img */
			if (optarg[0] == 'h' && optarg[1] == ':' && optarg[2]) {
				sasi.save = optarg + 2;
				break;
			}
			if (optarg[0] < 'a' || optarg[0] > 'd' || optarg[1] != ':' || !optarg[2])
				return fprintf(stderr, "-w takes a drive and a file, "
				    "such as b:new.imd or h:new.img\n"), 2;
			disks[optarg[0] - 'a'].save = optarg + 2;
			break;
		case 'D': {
			char *end;
			long v = strtol(optarg, &end, 0);
			if (*end || v < 0 || v > 255)
				return fprintf(stderr, "-D takes the DIP switch byte, "
				    "0 to 255, such as 1 for a 5-inch boot\n"), 2;
			dipsw = v;
			break;
		}
		case 'f': fast = 1; break;
		case 'k': {	/* the queue holds KEYQ - 1 */
			int n;
			unescape(optarg, &n);
			if (n >= KEYQ - 1) {
				fprintf(stderr, "-k: more than %d keys\n", KEYQ - 2);
				return 2;
			}
			keys = optarg;
			break;
		}
		case 'e': prompt = optarg; break;
		case 't':
			seconds = atof(optarg);
			fast = 1;
			/* 0 was taken and ran for ever */
			if (!(seconds > 0 && seconds <= 1e7))
				return fprintf(stderr, "-t: seconds, more than 0, "
				    "10000000 at most\n"), 2;
			break;
		case 'T': window = 0; break;
		case 'p': pgm = optarg; break;
		case 's': wavpath = optarg; break;
		case 'g': debug = 1; break;
		case 'N':
			/* goes in a file name: letters, digits, '-', '_' and '.' */
			if (!*optarg || strlen(optarg) > 32
			    || strspn(optarg, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
				"abcdefghijklmnopqrstuvwxyz0123456789-_.") != strlen(optarg))
				return fprintf(stderr, "-N takes a name of up to 32 letters, "
					"digits, '-', '_' and '.'\n"), 2;
			inst = optarg;
			break;
		case 'l':
			if (!(prn = fopen(optarg, "wb")))
				return perror(optarg), 1;
			break;
		case 'o': case 'i': case 'I': {
			struct sio_chan *ch;

			if ((optarg[0] != 'a' && optarg[0] != 'b') || optarg[1] != ':' || !optarg[2])
				return fprintf(stderr, "-%c takes a channel and a file, "
				    "such as a:serial.txt\n", opt), 2;
			ch = &sio[optarg[0] - 'a'];
			if (opt == 'I') {	/* a remote that never waits */
				ch->raw = 1;
				opt = 'i';
			}
			char *at = opt == 'i' ? strrchr(optarg + 2, '@') : NULL;
			char *end = NULL;
			double t = at ? strtod(at + 1, &end) : 0;
			if (at && (end == at + 1 || *end))
				at = NULL;	/* not a time: part of the name */
			if (at) {	/* a:file@seconds: the first byte comes then */
				if (!(t >= 0 && t <= 1e7))	/* NaN too */
					return fprintf(stderr, "-i: a time of 0 to "
					    "10000000 seconds\n"), 2;
				*at = 0;
				ch->rx_at = (unsigned long long)(t * CPU_HZ);
			}
			if (opt == 'o' ? !(ch->out = fopen(optarg + 2, "wb"))
			    : !(ch->in = fopen(optarg + 2, "rb")))
				return perror(optarg + 2), 1;
			break;
		}
		case 'F': {
			unsigned addr, bit;
			char kind;

			if (optarg[0] == 't' && optarg[1] == ':' &&
			    (optarg[2] == '0' || optarg[2] == '1') && !optarg[3]) {
				tick_fault = optarg[2] - '0';	/* as read */
				break;
			}
			if (!strcmp(optarg, "u:0")) {
				sio_gone = 1;
				break;
			}
			/* d's second is decimal, read so before the range
			   check */
			int dec = optarg[0] == 'd' && optarg[1] == ':';
			if (dec ? sscanf(optarg, "%c:%u:%u", &kind, &addr, &bit) != 3 ||
			    bit > 7 :
			    sscanf(optarg, "%c:%x:%u", &kind, &addr, &bit) != 3 ||
			    !strchr("vfmcs", kind) || bit > (kind == 'c' ? 3u : 7u) ||
			    addr > (kind == 'm' ? 0x1ffffu : kind == 'c' ? 3u : 0x7ffu))
				return fprintf(stderr, "-F takes v, f or m, an offset "
				    "and a bit, such as v:123:4, c and two chunks, "
				    "such as c:3:2, d, a second and an FDC status bit, or "
				    "t:0 or t:1, the tick stuck, or u:0, no SIO\n"), 2;
			if (kind == 's') {
				sasi_hang = addr;
				break;
			}
			if (kind == 'd') {	/* the second in decimal */
				fdc_stuck |= 1 << bit;
				fdc_stuck_at = (unsigned long long)addr * CPU_HZ;
				break;
			}
			if (kind == 'c') {
				alias_from = addr;
				alias_to = bit;
				break;
			}
			fault_at = kind == 'v' ? &video[addr] : kind == 'm' ?
			    &ram[addr >> 15][addr & 0x7fff] : addr < 0x400 ?
			    &font1[addr] : &font2[addr - 0x400];
			fault_mask = 1 << bit;
			break;
		}
		case 'm':
			if (!strcmp(optarg, "64"))
				bank_b = 0;
			else if (!strcmp(optarg, "64f"))
				bank_b = 2;
			else if (strcmp(optarg, "128"))
				return fprintf(stderr, "-m takes 128, 64 or 64f\n"), 2;
			break;
		case 'C':
			time_set = 1;
			break;
		case 'B':
			raster = 1;
			break;
		case 'L':
			show_lost = 1;
			break;
		case 'M':
			mech = 1;
			break;
		case 'G':
			fdlog = fopen(optarg, "w");
			if (!fdlog) {
				perror(optarg);
				return 2;
			}
			break;
		case 'K':
			caps_swap = 1;
			break;
		case 'V':
			vstretch = atoi(optarg);
			if (vstretch < 0 || vstretch > 20)
				return fprintf(stderr, "-V takes 0 to 20 T-states\n"), 2;
			break;
		case 'S':	/* nothing plugged into this serial port */
			if ((optarg[0] != 'a' && optarg[0] != 'b') || optarg[1])
				return fprintf(stderr, "-S takes a channel, a or b\n"), 2;
			sio[optarg[0] - 'a'].nopeer = 1;
			break;
		case 'x': {
			unsigned port;

			if (sscanf(optarg, "%x", &port) != 1 || port > 0xff)
				return fprintf(stderr, "-x takes a port, 00 to ff\n"), 2;
			xport = port;
			break;
		}
		default:
			fprintf(stderr, "usage: max80 [-r rom] [-a|-b|-c|-d disk.imd] "
				"[-h hard.img] [-n drive] [-R drive] [-3 drive]\n"
				"\t[-w drive:file] [-D dips] [-f] [-T] [-k keys] [-e text] [-K]\n"
				"\t[-s sound.wav] [-t seconds [-p frame.pgm]] [-l printer.txt]\n"
				"\t[-o|-i|-I ch:file[@secs]] [-S ch] [-F v|f|m:offset:bit]\n"
				"\t[-F c:chunk:chunk] [-F d:secs:bit] [-x port] [-m 128|64|64f]\n"
				"\t[-C] [-B] [-V T] [-L] [-M] [-G fdc.log] [-g [-N name]]\n");
			return 2;
		}
	}
	for (int i = 0; i < 4; i++) {
		if (!disks[i].save)
			continue;
		if (!disks[i].loaded)
			return fprintf(stderr, "-w: no disk in drive %c\n", 'A' + i), 2;
		if (!save_allowed(disks[i].save))
			return 2;
	}
	if (sasi.save && !sasi.img)
		return fprintf(stderr, "-w h: no hard disk, give -h\n"), 2;
	if (sasi.save && !save_allowed(sasi.save))
		return 2;
	f = fopen(rompath, "rb");
	if (!f || fread(rom, 1, 512, f) != 512) {
		fprintf(stderr, "%s: cannot read the 512-byte boot ROM\n", rompath);
		return 1;
	}
	fclose(f);

	cpu.read = mem_read;
	cpu.write = mem_write;
	cpu.ctx = &cpu;		/* marks the CPU's accesses for dev_wait */
	cpu.in = bus_in;
	cpu.out = bus_out;
	cpu.irq_vector = 0xfe;
	z80_reset(&cpu);
	if (seconds)
		window = 0;
	if (wavpath && wav_open(wavpath))
		return 1;
	atexit(wav_close);
	atexit(sio_flush);
#ifdef HAVE_SDL
	if (window && win_open())
		return 1;
#endif
	if (inst && !debug)
		return fprintf(stderr, "-N names the debug sockets, it needs -g\n"), 2;
	if (debug) {
#ifdef __linux__
		if (inst)
			dbg_name(inst);
		if (dbg_open())
			return 1;
#else
		return fprintf(stderr, "-g: debug sockets are built on Linux only\n"), 2;
#endif
	}
	if (!seconds && !window)
		tty_raw();

	struct timespec next;
	clock_gettime(CLOCK_MONOTONIC, &next);
	unsigned long long ticks = 0, max_ticks = seconds * 60, irqs = 1;
	char text[16384];

	/* Each tick ends TICK_T cycles after the last, counted on cpu.cycles,
	   which takes the wait states and -V's stretch too, so the sound
	   and the run time keep step with the CPU */
	unsigned long long tick_end = cpu.cycles;
	for (;;) {
		unsigned long long from = tick_end;
		unsigned long beeps_before = beep_count;
		int16_t snd[TICK_SAMPLES];
		tick_end += TICK_T;
		while (cpu.cycles < tick_end) {
			z80_step(&cpu);
			if (sio_ie)	/* /INT is the tick and the SIO */
				cpu.irq = tick_flag || sio_int();
			if (cpu.cycles >= tick_cycle(irqs)) {
				tick_flag = 1;
				cpu.irq = 1;
				irqs++;
			}
		}
		sio_service();
		sound_tick(from, snd);
		if (wav) {
			fwrite(snd, 2, TICK_SAMPLES, wav);
			wav_samples += TICK_SAMPLES;
		}
#ifdef HAVE_SDL
		if (window)
			win_sound(snd);
#endif
		if (tty && beep_count != beeps_before)
			fputc('\a', stdout);	/* the terminal bell */
		key_tick();
		ticks++;
#ifdef __linux__
		if (debug) {
			dbg_poll();
			if (dbg_stop)
				break;
		}
#endif

		if (keys && !typed && ticks % 6 == 0 && prompt_ready()) {
			int n;
			const char *k = unescape(keys, &n);
			scripted = 1;
			key_queue(k, n);
			typed = 1;
		}
		if (seconds) {
			if (ticks >= max_ticks)
				break;
			continue;
		}
#ifdef HAVE_SDL
		if (window) {
			/* in fast mode too, draw at most 60 frames a real second */
			struct timespec now;
			clock_gettime(CLOCK_MONOTONIC, &now);
			long late = (now.tv_sec - next.tv_sec) * 1000000000L
			    + now.tv_nsec - next.tv_nsec;
			if (fast && late < 1000000000L / 60)
				continue;
			if (fast)
				next = now;
			if (win_events())
				break;
			/* every frame, since the window system may drop what it
			   showed, but a frame behind time skips up to 3 draws so
			   the CPU keeps time on a slow host */
			static int skipped;
			if (!fast && late > 1000000000L / 60 && skipped < 3)
				skipped++;
			else {
				skipped = 0;
				win_draw();
			}
		}
#endif
		if (!window) {
			char in[64];
			int n = read(0, in, sizeof(in));
			if (n > 0) {
				if (memchr(in, 0x1d, n))
					break;
				tty_keys(in, n);
			}
			if (video_dirty && ticks % 2 == 0) {
				video_dirty = 0;
				screen_draw();
			}
		}
		if (!fast) {
			next.tv_nsec += 1000000000L / 60;
			if (next.tv_nsec >= 1000000000L) {
				next.tv_nsec -= 1000000000L;
				next.tv_sec++;
			}
			sleep_until(&next);
		}
	}
	if (seconds) {
		screen_text(text, sizeof(text));
		fputs(text, stdout);
	}
	int bad = 0;
	if (seconds && pgm && frame_save(pgm))
		bad = 1;	/* and the disks are still saved */
	if (show_lost)
		printf("Lost Data: %lu\n", fdc_lost);
	if (mech)
		printf("Drives: %lu sectors, %lu steps, %.2f s waiting for sectors, "
		    "first command to last %.2f s\n", mech_secs, mech_steps,
		    (double)mech_wait / CPU_HZ,
		    (double)(mech_last - mech_first) / CPU_HZ);
	for (int i = 0; i < 4; i++)
		if (disks[i].save)
			bad |= save_imd(&disks[i], disks[i].save);
	if (sasi.save)
		bad |= save_hd(sasi.save);
	return bad;
}
