/*
 * Write track and read track: a track written as a formatter writes
 * it, MFM and FM, must come back from read track with its IDs, data and
 * valid CRCs. Then the 8-inch and 5-inch connectors and the 5-inch motor
 * timer. Built with max80.c itself, its main renamed.
 */
#define main max80_main
#include "max80.c"
#undef main

static int fails;

static void expect(int ok, const char *what)
{
	printf("%s %s\n", ok ? "ok  " : "FAIL", what);
	fails += !ok;
}

/* A formatter's stream for n sectors of 128 << code bytes, data byte s */
static int format_stream(uint8_t *b, int mfm, int cyl, int n, int code)
{
	int k = 0, gap = mfm ? 0x4e : 0xff;
#define W(v, r) for (int i_ = 0; i_ < (r); i_++) b[k++] = (v)
	W(gap, 40);
	for (int s = 0; s < n; s++) {
		W(0, mfm ? 12 : 6);
		if (mfm)
			W(0xf5, 3);
		W(0xfe, 1);
		W(cyl, 1); W(0, 1); W(s, 1); W(code, 1);
		W(0xf7, 1);
		W(gap, 22);
		W(0, mfm ? 12 : 6);
		if (mfm)
			W(0xf5, 3);
		W(s == 1 ? 0xf8 : 0xfb, 1);
		W(s, 128 << code);
		W(0xf7, 1);
		W(gap, 24);
	}
	while (k < track_bytes())
		b[k++] = gap;
#undef W
	return k;
}

/* Walk a read track stream: every ID and data field must have a good CRC */
static int check_stream(const uint8_t *b, int n, int mfm, int want)
{
	int ids = 0, bad = 0, size = 0;
	for (int i = 0; i < n - 8; i++) {
		int at = mfm ? i + 3 : i;	/* past the A1h syncs */
		if (mfm && (b[i] != 0xa1 || b[i + 1] != 0xa1 || b[i + 2] != 0xa1))
			continue;
		if (b[at] == 0xfe) {
			uint16_t c = crc16(0xffff, b + i, at - i + 7);
			bad += c != 0;
			size = 128 << (b[at + 4] & 3);
			ids++;
			i = at + 6;
		} else if ((b[at] == 0xfb || b[at] == 0xf8) && size) {
			uint16_t c = crc16(0xffff, b + i, at - i + 1 + size + 2);
			bad += c != 0;
			i = at + size + 2;
			size = 0;
		}
	}
	return ids == want && !bad;
}

static void round_trip(int mfm, int eight, int n, int code, const char *what)
{
	struct track t = { 0 };
	static uint8_t b[TRACK_MAX], back[TRACK_MAX];

	fdc.dd = mfm;
	fdc.eight = eight;
	int len = format_stream(b, mfm, 7, n, code);
	track_from_stream(&t, b, len);
	int ok = t.present && t.nsec == n && t.cyl_id == 7 && t.mfm == mfm;
	for (int s = 0; ok && s < n; s++)
		ok = t.sec[s].id == s && t.sec[s].size == 128 << code &&
		    t.sec[s].data[0] == s && t.sec[s].deleted == (s == 1);
	expect(ok, what);
	stream_from_track(&t, back, len);
	expect(check_stream(back, len, mfm, n), "  read track gives the IDs with good CRCs");
	free_track(&t);
}

/* Read sector 1 with MLATCH m, a data register read every us
   microseconds, and say whether it ended with Lost Data */
static int read_lost(uint8_t m, int us)
{
	mlatch_write(m);
	fdc_command(0xd0);
	fdc.sector = 1;
	fdc_command(0x80);
	for (int i = 0; i < 4096 && fdc.busy; i++) {
		cpu.cycles += (unsigned long long)CPU_HZ * us / 1000000;
		fdc_read(3);
	}
	return fdc.busy || (fdc.status & 0x04);
}

/* Type I status shows the index pulse at some point in a revolution */
static int index_seen(void)
{
	for (int i = 0; i < 100; i++) {
		cpu.cycles += CPU_HZ / 5 / 100;
		if (fdc_read(0) & 0x02)
			return 1;
	}
	return 0;
}

/* T-states of one instruction op nn at 0100h */
static long instr_t(uint8_t op, uint16_t nn)
{
	uint8_t *m = ram_at(0x100);
	m[0] = op;
	m[1] = nn & 0xff;
	m[2] = nn >> 8;
	cpu.pc = 0x100;
	unsigned long long c0 = cpu.cycles;
	z80_step(&cpu);
	return (long)(cpu.cycles - c0);
}

/* Read sector n with command cmd, every byte, and give the end status */
static int sector_status(uint8_t cmd, int n)
{
	fdc_write(2, n);
	fdc_write(0, cmd);
	for (int i = 0; i < 4096 && fdc.busy; i++) {
		cpu.cycles += CPU_HZ / 100000;
		fdc_read(3);
	}
	return fdc_read(0);
}

/* The clock chip through the PIO, as Lobo's TIMESET program drives it */
static void rtc_w(int a, int v)
{
	uint8_t m = pio_mask[0];

	pio_mask[0] = 0;		/* port A all outputs for the write */
	pio_a = (pio_a & 0xf0) | v;
	pio_write(2, a | 0x40);		/* register, HOLD */
	pio_write(2, a | 0x50);		/* WRITE */
	pio_write(2, a | 0x40);
	pio_mask[0] = m;
}

static int rtc_r(int a)
{
	pio_write(2, a | 0x20 | (pio_b & 0x40));	/* READ, HOLD as it was */
	cpu.cycles += RTC_TRA + 1;
	return pio_read(0) & 0x0f;
}

/* Set the clock: s holds the 13 digits, then release HOLD */
static void rtc_setall(const uint8_t *s)
{
	for (int a = 2; a < 13; a++)
		rtc_w(a, s[a]);
	rtc_w(0, 0);
	pio_write(2, 0);
}

/* T-states of the n bytes of code at 0100h */
static long code_t(const uint8_t *code, int n)
{
	memcpy(ram_at(0x100), code, n);
	cpu.pc = 0x100;
	unsigned long long c0 = cpu.cycles;
	z80_step(&cpu);
	return (long)(cpu.cycles - c0);
}

int main(void)
{
	expect(crc16(0xffff, (const uint8_t *)"123456789", 9) == 0x29b1,
	    "CRC-CCITT check value 29B1h");
	round_trip(1, 1, 30, 1, "8-inch MFM, 30 x 256, as CP/M 2.2 and LDOS");
	round_trip(1, 1, 17, 2, "8-inch MFM, 17 x 512, as CP/M 3");
	round_trip(0, 1, 26, 0, "8-inch FM, 26 x 128, IBM 3740");
	round_trip(1, 0, 10, 2, "5-inch MFM, 10 x 512");

	struct track t = { 0 };
	static uint8_t junk[TRACK_MAX];
	fdc.dd = 1;
	memset(junk, 0x4e, sizeof(junk));
	track_from_stream(&t, junk, track_bytes());
	expect(!t.present, "a track with no IDs reads as unformatted");

	/* a disk is on the connector of its kind. Drive 1 holds a
	   5-inch disk, drive 2 nothing. */
	static uint8_t b[TRACK_MAX];
	disks[0].loaded = 1;
	fdc.dd = 1;
	fdc.eight = 0;
	track_from_stream(&disks[0].trk[0][0], b, format_stream(b, 1, 0, 9, 2));
	mlatch_write(0x41);
	expect(fdc_ready() && on_connector(), "a 5-inch disk is on the 5-inch connector");
	fdc.sector = 1;
	fdc_command(0x88);
	cpu.cycles += FIRST_T;	/* a read's first DRQ comes later */
	fdc_tick();
	expect(fdc.drq && fdc.busy, "  and reads there");
	fdc_command(0xd0);
	mlatch_write(0x61);
	expect(!fdc_ready(), "  and is not ready on the 8-inch one");
	fdc_command(0x88);
	expect(fdc.intrq && !fdc.busy && (fdc.status & 0x80), "  where a read ends Not Ready");
	mlatch_write(0x41);
	expect(!(fdc_read(0) & 0x80), "  and S7 goes when a ready drive is picked again");
	mlatch_write(0x42);
	expect(fdc_ready(), "5-inch with no disk: ready, there is no READY line");
	fdc_command(0x88);
	cpu.cycles += CPU_HZ;
	fdc_tick();
	expect(fdc.busy && !fdc.drq && !fdc.intrq, "  a read waits a second and more");
	fdc_command(0xd8);
	expect(!fdc.busy && fdc.intrq, "  until a force interrupt");
	fdc_command(0x00);
	expect((fdc.status & 0x14) == 0x10, "  a restore ends with seek error, no track 0");
	expect((fdc_read(0) & 0x14) == 0x10, "  and the CPU reads the seek error");
	expect(fdc.intrq, "  INTRQ from the D8 is held through the restore and a read");
	fdc_command(0xd0);
	expect(fdc.intrq, "  and through a D0");
	fdc_read(0);
	expect(!fdc.intrq, "  which lets the next status read clear it");
	mlatch_write(0x42);
	expect(io_read(0x7e1) & 0x20, "the 5-inch motor timer runs after a 5-inch select");
	cpu.cycles += CPU_HZ * 3;
	expect(io_read(0x7e1) & 0x20, "  for 3 s");
	cpu.cycles += CPU_HZ / 4;
	expect(!(io_read(0x7e1) & 0x20), "  and stops by 3.25 s");
	mlatch_write(0x61);
	expect(!(io_read(0x7e1) & 0x20), "  an 8-inch select does not start it");

	/* the CPU has one byte time per byte, 16 us MFM at the 8-inch
	   connector's 2 MHz, 32 us at the 5-inch connector's 1 MHz. Drive
	   2 gets an 8-inch disk. */
	disks[1].loaded = 1;
	fdc.dd = 1;
	fdc.eight = 1;
	track_from_stream(&disks[1].trk[0][0], b, format_stream(b, 1, 0, 30, 1));
	expect(!read_lost(0x62, 14), "8-inch MFM, a byte every 14 us keeps up");
	expect(read_lost(0x62, 20), "  a byte every 20 us loses data");
	expect(!read_lost(0x41, 20), "5-inch MFM, a byte every 20 us keeps up");
	expect(!read_lost(0x41, 30), "  and every 30 us");
	expect(read_lost(0x41, 40), "  a byte every 40 us loses data");

	/* the FDC has no drive select input */
	mlatch_write(0x20);
	fdc_write(1, 2);
	fdc_write(3, 5);
	fdc_write(0, 0x10);
	expect(fdc.track == 5, "no drive selected: a seek still sets the track register");
	fdc_write(0, 0x50);
	expect(fdc.track == 6, "  a step in with u = 1 counts");
	fdc_write(0, 0x00);
	expect(fdc.track == 0, "  a restore zeroes it");

	/* Force Interrupt conditions (Appendix D p.5, p.6) */
	mlatch_write(0x62);
	fdc_write(0, 0xd4);
	expect(!fdc.intrq, "Force Interrupt on index: no INTRQ at once");
	cpu.cycles += CPU_HZ / 6 + 1;
	io_read(0x7f4);
	expect(fdc.intrq, "  INTRQ at the next index pulse");
	fdc_read(0);
	expect(fdc.intrq, "  and a status read leaves it set");
	fdc_write(0, 0xd0);
	expect(!fdc.intrq, "  until the next command");
	fdc_write(0, 0xd2);
	mlatch_write(0x20);
	expect(fdc.intrq, "Force Interrupt on ready to not ready");
	fdc_write(0, 0xd1);
	expect(!fdc.intrq, "Force Interrupt on not ready to ready: none while not ready");
	mlatch_write(0x62);
	expect(fdc.intrq, "  INTRQ when the drive comes ready");

	/* Read Address gives the ID field's CRC */
	fdc_write(0, 0xd0);
	fdc_write(0, 0xc0);
	uint8_t idf[10] = { 0xa1, 0xa1, 0xa1, 0xfe };
	for (int i = 0; i < 6; i++)
		idf[4 + i] = fdc_read(3);
	expect(fdc.drq == 0 && crc16(0xffff, idf, 10) == 0,
	    "Read Address gives the ID with a good CRC");

	/* a write with the deleted mark does not show S5 */
	fdc_write(2, 1);
	fdc_write(0, 0xa1);
	expect(fdc.busy && !(fdc_read(0) & 0x20), "a deleted-mark write does not show S5");
	while (fdc.busy) {
		cpu.cycles += CPU_HZ / 100000;
		fdc_write(3, 0);
	}

	/* LF types ENTER, as CR does; the tick's cycle past 2^64 */
	{
		struct key k = { 0 };

		key_for('\n', &k);
		expect(k.row == 6 && k.bit == 0 && !k.ctrl, "LF types ENTER");
		expect(tick_cycle(30000000ULL) > tick_cycle(29000000ULL) &&
		    tick_cycle(30000000ULL) / 30000000ULL == tick_cycle(1000) / 1000,
		    "the tick's cycle does not wrap after 5 days");
	}

	/* a multi-sector read past the last sector: record not found */
	mlatch_write(0x62);
	fdc_write(0, 0xd0);
	fdc_write(1, 0);
	expect((sector_status(0x90, 28) & 0x1c) == 0x10,
	    "a multi-sector read past the last sector ends Record Not Found");

	/* an IMD track with no sectors is no track; a size table refused */
	{
		static struct disk dz;
		static const uint8_t im[] = { 'I', 'M', 'D', ' ', 0x1a,
		    5, 0, 0, 0, 2,			/* cylinder 0: none */
		    5, 1, 0, 1, 1, 0, 2, 0xe5 };	/* 1: one sector */
		char path[] = "/tmp/test_track_XXXXXX";
		int fd = mkstemp(path);
		FILE *f = fdopen(fd, "wb");

		fwrite(im, 1, sizeof im, f);
		fclose(f);
		expect(load_imd(&dz, path) == 0 && !dz.trk[0][0].present &&
		    dz.trk[1][0].present && dz.trk[1][0].nsec == 1,
		    "an IMD track with no sectors loads as no track");
		f = fopen(path, "wb");
		fwrite(im, 1, sizeof im, f);
		fputc(5, f); fputc(2, f); fputc(0, f); fputc(1, f);
		fputc(0xff, f);
		fclose(f);
		free_tracks(&dz);
		memset(&dz, 0, sizeof dz);
		expect(load_imd(&dz, path) < 0, "  a sector size table is refused");
		/* a bad or short file refused, never read past */
		static const struct { const char *what; int n; uint8_t b[12]; } bad[] = {
			{ "a track cut short", 7, { 5, 0, 0, 30, 1, 0, 1 } },
			{ "a sector map past the end", 7, { 5, 0, 0, 255, 1, 0, 1 } },
			{ "a sector's data past the end", 9, { 5, 0, 0, 1, 1, 0, 1, 0xe5, 0xe5 } },
			{ "a mode over 5", 8, { 6, 0, 0, 1, 1, 0, 2, 0xe5 } },
			{ "a sector kind over 8", 8, { 5, 0, 0, 1, 1, 0, 9, 0xe5 } },
			{ "head byte bits 1-5", 8, { 5, 0, 2, 1, 1, 0, 2, 0xe5 } },
		};
		for (unsigned k = 0; k < sizeof bad / sizeof bad[0]; k++) {
			f = fopen(path, "wb");
			fwrite(im, 1, 5, f);
			fwrite(bad[k].b, 1, bad[k].n, f);
			fclose(f);
			free_tracks(&dz);
			memset(&dz, 0, sizeof dz);
			char what[80];
			snprintf(what, sizeof what, "  %s is refused", bad[k].what);
			expect(load_imd(&dz, path) < 0, what);
		}
		f = fopen(path, "wb");
		fwrite(im, 1, sizeof im, f);
		fwrite(im + 10, 1, sizeof im - 10, f);	/* cylinder 1 again */
		fclose(f);
		free_tracks(&dz);
		memset(&dz, 0, sizeof dz);
		expect(load_imd(&dz, path) < 0, "  a track given twice is refused");
		free_tracks(&dz);
		remove(path);
	}

	/* the 5-inch disk stops when the motor timer runs out */
	mlatch_write(0x41);
	fdc_write(0, 0xd0);
	expect(index_seen(), "5-inch motor on: index pulses");
	cpu.cycles += CPU_HZ * 7 / 2;
	expect(!index_seen(), "  3.5 s after the last select: none");
	fdc_write(2, 1);
	fdc_write(0, 0x80);
	cpu.cycles += CPU_HZ;
	fdc_tick();
	expect(fdc.busy && !fdc.drq, "  and a read waits");
	fdc_write(0, 0xd0);
	mlatch_write(0x41);
	fdc_write(0, 0x80);
	cpu.cycles += FIRST_T;
	fdc_tick();
	expect(fdc.drq, "  a select starts the motor and the read goes");
	fdc_write(0, 0xd0);

	/* a beep lasts to the fourth tick after the write */
	double tick = (double)IRQ_NUM / IRQ_DEN;
	int bok = 1;
	for (int i = 0; i < 10; i++) {
		cpu.cycles = (unsigned long long)(1000 * tick + i * tick / 10);
		nbeeps = 0;
		beep();
		double d = (double)(beeps[0].end - beeps[0].start);
		bok &= d >= 3 * tick - 1 && d <= 4 * tick + 1;
	}
	expect(bok, "a beep lasts 3 to 4 ticks, whatever the tick phase");
	unsigned long long first = beeps[0].end;
	cpu.cycles += (unsigned long long)tick;
	beep();
	expect(nbeeps == 1 && beeps[0].end > first, "  a write during it restarts the count");

	/* the CRTC address register has 5 bits */
	io_write(0x7e0, 0x21);
	io_write(0x7e1, 64);
	expect(crtc[1] == 64, "CRTC index 21h selects R1");
	io_write(0x7e0, 0x13);
	io_write(0x7e1, 99);
	expect(crtc[1] == 64, "  index 13h selects nothing");

	/* two wait states on a device register, none on USTAT */
	cpu.read = mem_read;
	cpu.write = mem_write;
	cpu.ctx = &cpu;
	vlatch = 0xf0;
	expect(instr_t(0x3a, 0xf7e1) == 15, "LD A,(SYSFLG) takes 13 T and two waits");
	expect(instr_t(0x3a, 0xf7f4) == 13, "LD A,(USTAT) takes 13 T, no waits");
	expect(instr_t(0x32, 0xf7f8) == 15, "LD (BEEP),A takes two waits");
	expect(instr_t(0x3a, 0xf400) == 13, "LD A,(RAM400) takes none");
	expect(instr_t(0x3a, 0x8000) == 13, "LD A,(8000h) takes none");

	/* IMD bad and missing sectors, side compare. Drive 2, the
	   8-inch disk, track 0, IDs head 0, sectors 0-29 */
	mlatch_write(0x62);
	fdc_write(0, 0xd0);
	fdc_write(1, 0);
	disks[1].trk[0][0].sec[3].bad = 1;
	disks[1].trk[0][0].sec[4].missing = 1;
	expect(sector_status(0x80, 3) & 0x08, "an IMD data error sector reads with CRC error");
	expect(!(sector_status(0x80, 2) & 0x18), "  a good one without");
	expect(sector_status(0x80, 4) & 0x10, "an IMD no-data sector gives record not found");
	expect(sector_status(0x8a, 2) & 0x10, "side compare for side 1 on head 0 IDs: not found");
	expect(!(sector_status(0x82, 2) & 0x10), "  for side 0: found");
	disks[1].trk[0][0].sec[3].bad = 0;
	disks[1].trk[0][0].sec[4].missing = 0;

	/* the SIO's timing, buffer, FIFO and lines. Channel A */
	struct sio_chan *ch = &sio[0];
	ch->out = tmpfile();
	ch->in = tmpfile();
	fputs("0123456789", ch->in);
	rewind(ch->in);
	sio_write(1, 0x18);
	sio_write(1, 4); sio_write(1, 0x44);	/* x16, 1 stop, no parity */
	sio_write(1, 5); sio_write(1, 0xea);	/* 8 bits, Tx on */
	ch->baud = 15;
	expect(sio_char_t(ch, 1) == 2560, "SIO 19200 8N1: 10 bits of 16 x 16 T");
	sio_write(1, 4); sio_write(1, 0x48);	/* Lobo's 1.5 stop bits */
	ch->baud = 14;
	expect(sio_char_t(ch, 1) == 5544, "  9600 with 1.5 stop bits: 10.5 bits of 16 x 33 T");
	sio_write(0, 'A');
	sio_write(0, 'B');
	cpu.cycles += 3 * sio_char_t(ch, 1);
	sio_read(1);
	expect(ftell(ch->out) == 2, "  two bytes written back to back are both sent");
	sio_write(1, 5); sio_write(1, 0xfa);	/* break */
	sio_write(0, 'C');
	cpu.cycles += 3 * sio_char_t(ch, 1);
	sio_read(1);
	expect(ftell(ch->out) == 2, "  break sends nothing");
	sio_write(1, 5); sio_write(1, 0xea);
	sio_write(1, 3); sio_write(1, 0xc1);	/* Rx 8 bits on: the remote starts */
	cpu.cycles += 8 * sio_char_t(ch, 0);
	sio_write(1, 1);
	expect(!(sio_read(1) & 0x20) && ch->n == 3, "  -i waits while the FIFO is full");
	char got[11] = { 0 };
	for (int i = 0; i < 10; i++) {
		cpu.cycles += 2 * sio_char_t(ch, 0);
		got[i] = sio_read(0);
	}
	expect(!strcmp(got, "0123456789"), "  and loses nothing");
	rewind(ch->in);
	ch->raw = 1;			/* -I */
	ch->rx_on = ch->rx_eof = 0;
	sio_write(1, 0x18);
	sio_write(1, 4); sio_write(1, 0x48);
	sio_write(1, 5); sio_write(1, 0xea);
	sio_write(1, 3); sio_write(1, 0xc1);
	cpu.cycles += 8 * sio_char_t(ch, 0);
	sio_write(1, 1);
	expect((sio_read(1) & 0x20) && ch->n == 3, "-I: unread bytes fill the 3-byte FIFO, then overrun");
	expect(sio_read(0) == '0' && sio_read(0) == '1' && sio_read(0) == '7',
	    "  the FIFO keeps the first two, the last overwritten");
	sio_write(1, 0x30);
	sio_write(1, 1);
	expect(!(sio_read(1) & 0x20), "  error reset clears the overrun");
	ch->nopeer = 1;
	sio_write(1, 3); sio_write(1, 0xe1);	/* auto enables */
	long before = ftell(ch->out);
	sio_write(0, 'D');
	cpu.cycles += 3 * sio_char_t(ch, 1);
	expect(!(sio_read(1) & 0x28) && ftell(ch->out) == before,
	    "-S: CTS and DCD off, and auto enables hold the byte");
	ch->nopeer = ch->raw = 0;
	sio_write(1, 0x18);
	fclose(ch->in);
	fclose(ch->out);
	ch->in = ch->out = NULL;

	/* the clock chip and its TIME SET button */
	pio_mask[0] = 0x0f;
	pio_write(2, 0x03);
	expect((pio_read(0) & 0x0f) == 0x0f, "clock: READ low reads 1111");
	int m10 = rtc_r(3);
	rtc_w(3, 6);
	pio_write(2, 0);
	expect(rtc_r(3) == m10, "  TIME SET up: a write does not take");
	time_set = 1;
	rtc_w(3, 6);
	expect(rtc_r(3) == 6, "  TIME SET held: an illegal 6 reads back, TIMESET's test");
	pio_a = (pio_a & 0xf0) | 2;	/* PA3-0 still inputs: the pull-ups */
	pio_write(2, 0x43);
	pio_write(2, 0x53);
	pio_write(2, 0x43);
	expect(rtc_r(3) == 15, "  a write with PA3-0 inputs stores the pull-ups' 1111");
	pio_mask[0] = 0;		/* LDOS SETTIME's order: WRITE, then HOLD */
	pio_a = (pio_a & 0xf0) | 4;
	pio_write(2, 0x13);
	pio_write(2, 0x53);
	pio_write(2, 0x13);
	pio_write(2, 0);
	pio_mask[0] = 0x0f;
	expect(rtc_r(3) == 4, "  WRITE before HOLD stores too, as LDOS writes");
	rtc_w(3, 6);
	rtc_w(3, m10);
	int s1 = rtc_r(0) + 10 * rtc_r(1);
	pio_write(2, 0x40);
	cpu.cycles += CPU_HZ * 3;
	expect(rtc_r(0) + 10 * rtc_r(1) == s1, "  HOLD stops the count");
	pio_write(2, 0);
	cpu.cycles += CPU_HZ * 2;
	expect(rtc_r(0) + 10 * rtc_r(1) != s1, "  and it counts again after");
	rtc_setall((uint8_t[]){ 0, 0, 9, 5, 3, 2 | 8, 4, 8, 2 | 4, 2, 0, 4, 2 });
	cpu.cycles += CPU_HZ * 60;
	expect(rtc_r(7) == 9 && rtc_r(8) == (2 | 4) && rtc_r(6) == 5,
	    "  23:59 on 28 Feb with the leap flag goes to 29 Feb");
	rtc_setall((uint8_t[]){ 0, 0, 9, 5, 3, 2 | 8, 5, 9, 2 | 4, 2, 0, 4, 2 });
	cpu.cycles += CPU_HZ * 60;
	expect(rtc_r(7) == 1 && rtc_r(8) == 0 && rtc_r(9) == 3,
	    "  23:59 on 29 Feb goes to 1 Mar, the leap flag cleared");
	rtc_setall((uint8_t[]){ 0, 0, 9, 5, 1, 1 | 4, 0, 1, 0, 1, 0, 6, 2 });
	cpu.cycles += CPU_HZ * 60;
	expect(rtc_r(4) == 2 && rtc_r(5) == 1 && rtc_r(7) == 2,
	    "  11:59 PM in 12-hour mode goes to 12 AM, the next day");
	time_set = 0;
	pio_write(2, 0);

	/* Z80 corner cases */
	z80_reset(&cpu);	/* fills the flag tables */
	expect(code_t((uint8_t[]){ 0xdd, 0xdd, 0x21, 0, 0 }, 5) == 18,
	    "DD DD 21 nn takes 18 T, 4 a prefix");
	expect(code_t((uint8_t[]){ 0xdd, 0xed, 0x44 }, 3) == 12, "DD ED 44 takes 12 T");
	cpu.in = bus_in;
	cpu.r[0] = 1;		/* B */
	cpu.r[1] = 0x10;	/* C */
	cpu.r[4] = 0x80;	/* HL 8000h */
	cpu.r[5] = 0;
	code_t((uint8_t[]){ 0xed, 0xa2 }, 2);	/* INI reads FFh from no card */
	expect(cpu.r[6] == 0x57, "INI: Z, N, H, C and P/V as the NMOS chip sets them");
	cpu.iff1 = cpu.iff2 = 1;
	uint8_t r0 = cpu.rr;
	cpu.nmi = 1;
	z80_step(&cpu);
	expect(!cpu.iff1 && cpu.iff2 && cpu.rr != r0, "NMI keeps IFF1 in IFF2 and counts R");
	cpu.nmi = 1;
	z80_step(&cpu);
	expect(!cpu.iff2, "  a nested NMI clears IFF2");

	/* -B draws each character as the beam passes it */
	static const uint8_t lobo[16] = { 0x77, 0x50, 0x61, 0x06, 0x1b, 0x0c,
	    0x18, 0x1a, 0, 8, 0, 0, 0, 0, 0, 0 };
	memcpy(crtc, lobo, 16);
	vlatch = 0xf4;
	memset(&rs, 0, sizeof(rs));	/* the beam back to cycle 0 */
	int same = 1;
	for (unsigned long long c = 0; c < 2 * 84480; c += 7) {
		cpu.cycles = c;
		raster = 0;
		int a = dsptmg();
		raster = 1;
		same &= a == dsptmg();
	}
	expect(same, "-B: the display enable follows the formula over two frames");
	memset(video, 1, sizeof(video));
	memset(&font1[8], 0xff, 8);
	cpu.cycles = 3 * 84480 + 108ULL * 120 * 8 / 3;	/* picture line 108 */
	raster_run();
	memset(&font1[8], 0, 8);			/* glyph 1 goes blank */
	cpu.cycles = 4 * 84480 + 10;
	struct geom g;
	frame_draw(&g);
	expect(g.x0 == 136 && g.y0 == 14 && frame[(50 + 14) * g.w + 140] &&
	    !frame[(150 + 14) * g.w + 140],
	    "  a font write at line 108 shows below it only");
	cpu.cycles = 5 * 84480 + 10;
	frame_draw(&g);
	expect(!frame[(50 + 14) * g.w + 140], "  and in the whole next frame");
	memset(&font1[8], 0xff, 8);
	cpu.cycles = 5 * 84480 + 100ULL * 120 * 8 / 3;
	raster_run();
	crtc[12] = 2;		/* start address 200h, from the next frame */
	video[0x200] = 0;
	cpu.cycles = 6 * 84480 + 10;
	frame_draw(&g);
	expect(frame[(50 + 14) * g.w + 136 + 9] && frame[(2 + 14) * g.w + 136 + 9],
	    "  R12 written mid-frame waits for the next frame");
	cpu.cycles = 7 * 84480 + 10;
	frame_draw(&g);
	expect(!frame[(2 + 14) * g.w + 137] && frame[(2 + 14) * g.w + 136 + 9],
	    "  where it moves the start");
	crtc[12] = 0;
	/* a saved frame is the frame drawn, whatever the registers
	   say when it is saved */
	cpu.cycles = 8 * 84480 + 10;
	crtc[4] = 0;
	crtc[9] = 0;
	expect(frame_draw(&g) && g.w == 912 && g.h == 248,
	    "  R4 = R9 = 0 after the frame: it is saved at its own size");
	memcpy(crtc, lobo, 16);
	raster = 0;

	/* -V stretches video accesses */
	vlatch = 0xf0;
	vstretch = 3;
	int tmin = 99, tmax = 0;
	for (int i = 0; i < 200; i++) {
		int t = instr_t(0x3a, 0xfc00);
		tmin = t < tmin ? t : tmin;
		tmax = t > tmax ? t : tmax;
	}
	expect(tmin == 13 && tmax == 16, "-V 3: LD A,(FC00h) takes 13 to 16 T");
	expect(instr_t(0x3a, 0x8000) == 13, "  LD A,(8000h) still 13");
	vstretch = 0;

	/* a write track whose drive is deselected on the way keeps
	   no track, on no drive: it crashed, writing disks[-1] */
	fdc.dd = 1;
	fdc.eight = 0;
	disks[0].loaded = 1;
	disks[0].wprot = 0;
	mlatch_write(0x41);
	fdc_command(0xd0);
	fdc_command(0xf0);
	int fed = 0;
	while (fdc.busy && fed < TRACK_MAX + 100) {
		if (fed == 10)
			mlatch_write(0x40);
		fdc_write(3, 0x4e);
		cpu.cycles += BYTE_T;
		fdc_tick();
		fed++;
	}
	expect(!fdc.busy, "write track with the drive deselected ends");
	expect(disks[0].trk[0][0].present && disks[0].trk[0][0].nsec == 9,
	    "  and leaves drive A's track as it was");
	struct track was1 = disks[1].trk[0][0];
	mlatch_write(0x41);
	fdc_command(0xd0);
	fdc_command(0xf0);
	fed = 0;
	while (fdc.busy && fed < TRACK_MAX + 100) {
		if (fed == 10)
			mlatch_write(0x42);
		fdc_write(3, 0x4e);
		cpu.cycles += BYTE_T;
		fdc_tick();
		fed++;
	}
	expect(!fdc.busy && disks[0].trk[0][0].present &&
	    !memcmp(&was1, &disks[1].trk[0][0], sizeof was1),
	    "  another drive picked on the way gets no track either");

	/* a force interrupt during a read clears BUSY and leaves
	   Lost Data; one when idle gives type I status */
	mlatch_write(0x41);
	fdc_command(0xd0);
	fdc.sector = 1;
	fdc_command(0x88);
	cpu.cycles += FIRST_T + 5 * BYTE_T;
	fdc_tick();
	uint8_t st = fdc_read(0);
	expect((st & 0x05) == 0x05, "a read left alone: busy and Lost Data");
	fdc_command(0xd0);
	st = fdc_read(0);
	expect((st & 0x05) == 0x04 && !fdc.type1,
	    "  a force interrupt then clears busy and keeps Lost Data");
	fdc_read(3);
	expect(!(fdc_read(0) & 0x02), "  and a data read drops DRQ");
	fdc_command(0xd0);
	expect(fdc.type1, "  a second, idle, gives type I status");

	/* verify. Cylinder 2 formatted with the IDs of 7 */
	track_from_stream(&disks[0].trk[2][0], b, format_stream(b, 1, 7, 9, 2));
	fdc_command(0x00);
	fdc.data = 2;
	fdc_command(0x10);
	expect(!(fdc_read(0) & 0x10), "a seek with no verify to IDs of 7 at 2: no error");
	fdc_command(0x00);
	fdc_command(0x14);
	expect(fdc_read(0) & 0x10, "  with verify: seek error");
	fdc.data = 3;
	fdc_command(0x14);
	expect(fdc_read(0) & 0x10, "  and to an unformatted cylinder");
	fdc_command(0x04);
	expect(!(fdc_read(0) & 0x10), "  a restore with verify to cylinder 0's IDs: none");
	return fails != 0;
}
