/*
 * The app's interface (app.h): insert, eject, the disk's kind,
 * the changed flag a write sets, and Save Disk As, which never writes
 * over a loaded image but over the file the app saved. Built with
 * max80.c itself, its main renamed.
 */
#define main max80_main
#include "max80.c"
#undef main
#ifdef _WIN32
#include <direct.h>	/* _mkdir */
#endif

static int fails;

static void expect(int ok, const char *what)
{
	printf("%s %s\n", ok ? "ok  " : "FAIL", what);
	fails += !ok;
}

/* A formatter's MFM stream for n sectors of 256 bytes, data byte s */
static int format_stream(uint8_t *b, int cyl, int n)
{
	int k = 0;
#define W(v, r) for (int i_ = 0; i_ < (r); i_++) b[k++] = (v)
	W(0x4e, 40);
	for (int s = 0; s < n; s++) {
		W(0, 12); W(0xf5, 3); W(0xfe, 1);
		W(cyl, 1); W(0, 1); W(s, 1); W(1, 1); W(0xf7, 1);
		W(0x4e, 22);
		W(0, 12); W(0xf5, 3); W(0xfb, 1);
		W(s, 256); W(0xf7, 1);
		W(0x4e, 24);
	}
#undef W
	return k;
}

/* An image of kind eight (1 8-inch, 0 5.25-inch), 2 cylinders */
static void make_image(const char *path, int eight)
{
	static struct disk d;
	static uint8_t b[TRACK_MAX];

	memset(&d, 0, sizeof(d));
	d.loaded = 1;
	fdc.dd = 1;
	fdc.eight = eight;
	for (int c = 0; c < 2; c++)
		track_from_stream(&d.trk[c][0], b, format_stream(b, c, eight ? 30 : 18));
	if (save_imd(&d, path))
		exit(2);
	free_tracks(&d);
}

int main(void)
{
	char a[300], b[300], c[300], why[200];
#ifdef _WIN32
	/* no /tmp and no mkdtemp on Windows */
	char dir[MAX_PATH];
	snprintf(dir, sizeof dir, "%s\\max80_test_app_XXXXXX",
	    getenv("TEMP") ? getenv("TEMP") : ".");
	if (!_mktemp(dir) || _mkdir(dir) != 0)
		return perror("mkdir"), 2;
#else
	char dir[] = "/tmp/max80_test_app_XXXXXX";
	if (!mkdtemp(dir))
		return perror("mkdtemp"), 2;
#endif

	mech = 0;
	quick = 1;
	snprintf(a, sizeof a, "%s/eight.imd", dir);
	snprintf(b, sizeof b, "%s/five.imd", dir);
	snprintf(c, sizeof c, "%s/saved.imd", dir);
	make_image(a, 1);
	make_image(b, 0);

	expect(!app_disk(0) && app_kind(0) == 0, "an empty drive has no disk and no kind");
	expect(app_insert(0, a) == 0 && app_disk(0) && !strcmp(app_disk(0), a),
	    "a disk goes in drive A:");
	expect(app_kind(0) == 8, "  and reads as 8-inch");
	expect(!app_changed(0), "  with no changes");
	expect(app_insert(1, b) == 0 && app_kind(1) == 5, "a 5.25-inch disk reads as 5.25-inch");
	expect(app_insert(2, "/nonexistent/x.imd") == -1 && !app_disk(2),
	    "a file that is not there leaves the drive empty");

	/* a write sector command on drive A: marks the disk changed */
	mlatch_write(0x61);	/* 8-inch, drive A:, double density */
	fdc_write(1, 0);
	fdc_write(2, 3);
	fdc_write(0, 0xa0);
	for (int i = 0; i < 4096 && fdc.busy; i++) {
		cpu.cycles += CPU_HZ / 100000;
		fdc_tick();
		if (fdc.drq)
			fdc_write(3, 0x5a);
	}
	expect(!fdc.busy && !(fdc.status & 0x5c), "a sector written to drive A:");
	expect(app_changed(0), "  marks the disk changed");
	expect(!app_changed(1), "  and not the one in B:");

	/* the FDC busy: no eject, no insert */
	mlatch_write(0x61);
	fdc_write(2, 3);
	fdc_write(0, 0x80);
	expect(fdc.busy && app_eject(0) == 1 && app_insert(0, b) == 1,
	    "while a command runs, eject and insert wait");
	fdc_write(0, 0xd0);
	expect(!fdc.busy, "  until it ends");

	expect(app_save(0, a, why, sizeof why) == -1, "Save As over the loaded image is refused");
	expect(app_save(0, b, why, sizeof why) == -1, "  and over the image in another drive");
	expect(app_changed(0), "  and the disk keeps its changes");
	expect(app_save(0, c, why, sizeof why) == 0, "Save As to a new file writes it");
	expect(!app_changed(0) && !strcmp(app_disk(0), c), "  which is then the drive's file, saved");
	expect(app_save(0, c, why, sizeof why) == 0, "  and may be saved over again");

	expect(app_insert(3, c) == 0, "the saved file loads");
	expect(disks[3].trk[0][0].present && disks[3].trk[0][0].sec[3].data[0] == 0x5a,
	    "  with the sector written");
	expect(disks[3].trk[0][0].sec[4].data[0] == 4, "  and the others as they were");
	expect(app_eject(3) == 0 && !app_disk(3) && app_kind(3) == 0, "eject leaves the drive empty");

	app_set_wprot(1, 1);
	expect(disks[1].wprot, "write-protect goes on");
	app_set_wprot(1, 0);
	expect(!disks[1].wprot, "  and off");
	app_set_dips(0x81);
	expect(app_dips() == 0x81 && dipsw == 0x81, "the DIP switches are set");
	app_set_dips(2);
	app_set_fast(1);
	expect(app_fast(), "fast goes on");
	app_set_fast(0);
	expect(!app_fast(), "  and off");

	remove(a);
	remove(b);
	remove(c);
	rmdir(dir);
	printf(fails ? "%d FAILED\n" : "all passed\n", fails);
	return fails != 0;
}
