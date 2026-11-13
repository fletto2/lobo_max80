/*
 * Devices driven through the I/O block and the PIO the way programs do
 * it: the clock chip's count across a HOLD pulse with -C, and
 * the SIO taken out with -F u:0 taking no writes. Built with max80.c
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
	return fails != 0;
}
