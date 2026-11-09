/*
 * The SASI hard disk, driven through the I/O block offsets the way
 * Lobo's hard disk driver, XWINI.MAC, does it: select, six command bytes, data, status and
 * message, with ACK by hand (TWOWAY) and by UDATAHS. Built with max80.c
 * itself, its main renamed.
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

static int timeout;

/* XWINI SETUP: select code 01h, SEL, wait for BSY, drop SEL */
static int sel(void)
{
	io_write(0x7f0, 1);
	io_write(0x7f4, 2);
	for (int i = 0; i < 1000; i++)
		if (io_read(0x7f4) & 4) {
			io_write(0x7f4, 0);
			return 1;
		}
	io_write(0x7f4, 0);
	return 0;
}

/* XWINI TWOWAY: wait for REQ, put the byte out, take one in, ACK */
static uint8_t twoway(uint8_t v, int *ctl)
{
	int n = 0;
	while (!(io_read(0x7f4) & 1))
		if (++n > 1000) {
			timeout = 1;
			return 0;
		}
	io_write(0x7f0, v);
	*ctl = io_read(0x7f4) & 0x10;
	uint8_t r = io_read(0x7f0);
	io_write(0x7f4, 1);
	while (io_read(0x7f4) & 1)
		;
	io_write(0x7f4, 0);
	return r;
}

/* One command. Data in goes to buf (by hand), data out comes from buf
 * (by UDATAHS). Returns the status byte, or -1. */
static int command(uint8_t op, long lba, int n, uint8_t *buf, int len)
{
	uint8_t c[6] = { op, lba >> 16 & 0x1f, lba >> 8, lba, n, 0 };
	int ctl, got = 0;

	if (!sel())
		return -1;
	for (int i = 0; i < 6; i++)
		twoway(c[i], &ctl);
	if (op == 0x0a) {
		for (int i = 0; i < len; i++) {
			while (!(io_read(0x7f4) & 1))
				;
			io_write(0x7f1, buf[i]);
		}
	}
	for (;;) {
		uint8_t b = twoway(0, &ctl);
		if (timeout)
			return -1;
		if (ctl) {
			int st = b;
			twoway(0, &ctl);		/* the message byte */
			if (io_read(0x7f4) & 4)
				return -1;
			return st || got == len || op == 0x0a ? st : -1;
		}
		if (got < len)
			buf[got] = b;
		got++;
	}
}

int main(void)
{
	static uint8_t img[64 * 512], b[1024];

	expect(!sel(), "no image: select times out");

	sasi.img = img;
	sasi.nblk = 64;
	for (int i = 0; i < 64 * 512; i++)
		img[i] = i / 512 ^ i;

	expect(command(0x08, 5, 1, b, 512) == 0 && b[0] == 5 && b[511] == (uint8_t)(5 ^ 511),
	    "read block 5");
	expect(command(0x08, 62, 2, b, 1024) == 0 && b[0] == 62 && b[512] == 63,
	    "read two blocks");
	for (int i = 0; i < 512; i++)
		b[i] = 0xa5 ^ i;
	expect(command(0x0a, 7, 1, b, 512) == 0 && img[7 * 512] == 0xa5 &&
	    img[7 * 512 + 300] == (uint8_t)(0xa5 ^ 300), "write block 7 by UDATAHS");
	memset(b, 0, 512);
	expect(command(0x08, 7, 1, b, 512) == 0 && b[300] == (uint8_t)(0xa5 ^ 300),
	    "read back block 7");
	expect(command(0x08, 64, 1, b, 512) == 2, "read past the end: check condition");
	expect(command(0x03, 0, 4, b, 4) == 0 && b[0] == 0x21 && b[3] == 64,
	    "request sense: illegal block address 64");
	expect(command(0x03, 0, 4, b, 4) == 0 && b[0] == 0, "sense is cleared once read");
	expect(command(0x00, 0, 0, b, 0) == 0, "test unit ready");
	expect(command(0x07, 0, 0, b, 0) == 2, "unknown command: check condition");
	expect(!(io_read(0x7f4) & 0x3f), "bus free after each command");

	io_write(0x7f0, 1);		/* reset in the middle of a command */
	io_write(0x7f4, 2);
	io_write(0x7f4, 0);
	io_write(0x7f4, 4);
	io_write(0x7f4, 0);
	expect(!(io_read(0x7f4) & 0x3f), "RST frees the bus");
	expect(command(0x08, 1, 1, b, 512) == 0 && b[0] == 1, "works after a reset");

	/* The boot ROM with DIP setting 7 reads block 0 to 0400h and runs
	 * it. This one reads block 1 with the ROM's READ at 0003h and puts
	 * its text in video RAM. */
	static const uint8_t boot[] = {
		0x21, 0x00, 0x10,	/* ld hl,1000h, clear of the ROM's stack */
		0xaf,			/* xor a: block MSB */
		0x11, 0x00, 0x00,	/* ld de,0 */
		0x01, 0x01, 0x01,	/* ld bc,0101h: block +1 to +1 */
		0xcd, 0x03, 0x00,	/* call 0003h */
		0x21, 0x00, 0x10,	/* ld hl,1000h */
		0x11, 0x00, 0x0c,	/* ld de,0C00h: video RAM */
		0x01, 0x0c, 0x00,	/* ld bc,12 */
		0xed, 0xb0,		/* ldir */
		0x18, 0xfe,		/* jr $ */
	};
	FILE *f = fopen("../reference/rom/max80.e12", "rb");
	if (!f || fread(rom, 1, 512, f) != 512)
		return printf("FAIL no boot ROM\n"), 1;
	fclose(f);
	memset(img, 0, sizeof(img));
	memcpy(img, boot, sizeof(boot));
	memcpy(img + 512, "SASI BOOT OK", 12);
	sasi_ctrl(4);
	sasi_ctrl(0);
	dipsw = 7;
	cpu.read = mem_read;
	cpu.write = mem_write;
	z80_reset(&cpu);
	while (cpu.cycles < 5 * CPU_HZ)
		z80_step(&cpu);
	expect(!memcmp(video, "SASI BOOT OK", 12), "the boot ROM boots from it");
	if (memcmp(video, "SASI BOOT OK", 12))
		printf("     PC %04X\n", cpu.pc);

	return fails != 0;
}
