/*
 * Devices driven through the I/O block and the PIO the way programs do
 * it: the clock chip's count across a HOLD pulse with -C, the
 * SIO taken out with -F u:0 taking no writes, a HOLD under a second
 * keeping time and the leap flag at start, and a byte in the
 * SIO's transmit buffer sent when the last one ends. Built with
 * max80.c itself, its main renamed.
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

/* A clock digit: its address on PB3-0 with READ (PB5), past tRA */
static int rd(int reg)
{
	pio_write(2, 0x20 | reg);
	cpu.cycles += 100;
	return pio_read(0) & 0x0f;
}

/* Minutes and seconds, as seconds into the hour */
static int secs(void)
{
	int u = rd(0), t = rd(1), m = rd(2), mt = rd(3);

	return (mt * 10 + m) * 60 + t * 10 + u;
}

/* The clock moves over 100 emulated seconds with a HOLD pulse at the
   end, nothing read in between */
static int moved(int hold_set)
{
	time_set = hold_set;
	int s0 = secs();
	cpu.cycles += 100ULL * CPU_HZ;
	pio_write(2, 0x40);	/* HOLD up */
	pio_write(2, 0x00);	/* and down, nothing written */
	cpu.cycles += 100;
	return (secs() - s0 + 3600) % 3600;
}

int main(void)
{
	pio_mask[0] = 0x0f;	/* PA3-0 inputs, as the BIOS sets them */
	expect(moved(1) == 100,
	    "with -C a HOLD pulse keeps the seconds before it");
	expect(moved(0) == 100, "and without -C");

	/* -F u:0: a byte and Tx interrupts written to channel A reach no
	   SIO: nothing sent, no interrupt it could not clear */
	FILE *out = tmpfile();
	sio_gone = 1;
	sio[0].out = out;
	io_write(0x7e5, 5);
	io_write(0x7e5, 0x68);	/* WR5: Tx on, 8 bits */
	io_write(0x7e5, 1);
	io_write(0x7e5, 0x02);	/* WR1: Tx interrupts */
	io_write(0x7e4, 'X');
	cpu.cycles += CPU_HZ;
	sio_service();
	expect(ftell(out) == 0, "with no SIO a byte written is not sent");
	expect(!sio_int(), "and Tx interrupts are not turned on");
	sio[0].out = NULL;
	fclose(out);
	sio_gone = 0;

	/* HOLD up at x.9 s and down at (x+1).1 s, read at (x+2).5 s:
	   two seconds' edges passed, both counted */
	time_set = 1;
	cpu.cycles = (cpu.cycles / CPU_HZ + 10) * CPU_HZ - CPU_HZ / 10;
	int s0 = secs();
	pio_write(2, 0x40);
	cpu.cycles += CPU_HZ / 5;
	pio_write(2, 0x00);
	cpu.cycles += CPU_HZ * 14 / 10;
	expect((secs() - s0 + 3600) % 3600 == 2,
	    "a HOLD under a second across an edge keeps time");
	time_set = 0;

	/* the clock starts with the leap flag only up to February */
	setenv("SOURCE_DATE_EPOCH", "1857600000", 1);	/* 2028-11-12 */
	rtc_set = 0;
	rtc_sync();
	expect(!(rtc_reg[8] & 4), "no leap flag in November of a leap year");
	setenv("SOURCE_DATE_EPOCH", "1833667200", 1);	/* 2028-02-09 */
	rtc_set = 0;
	rtc_sync();
	expect(rtc_reg[8] & 4, "and the flag in February");
	unsetenv("SOURCE_DATE_EPOCH");

	/* two bytes written back to back, then nothing touched: the
	   second starts when the first ends, so after ten character times
	   RR1 says all sent */
	out = tmpfile();
	sio[0].out = out;
	io_write(0x7e5, 0x18);	/* channel reset */
	io_write(0x7e5, 4);
	io_write(0x7e5, 0x44);	/* WR4: x16, 1 stop bit */
	io_write(0x7e5, 5);
	io_write(0x7e5, 0x68);	/* WR5: Tx on, 8 bits */
	io_write(0x7e4, 'A');
	io_write(0x7e4, 'B');
	unsigned long long t = sio_char_t(&sio[0], 1);
	unsigned long long first = sio[0].shift_end;
	cpu.cycles += 10 * t;
	io_write(0x7e5, 1);
	expect(io_read(0x7e5) & 1, "RR1 all sent ten characters after two bytes");
	expect(sio[0].shift_end == first + t,
	    "and the second began as the first ended");
	expect(ftell(out) == 2, "both sent");
	sio[0].out = NULL;
	fclose(out);

	return fails != 0;
}
