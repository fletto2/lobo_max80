/*
 * What the Mac app (mac/app.m) calls in the emulator, and what the
 * emulator calls in the app. The app's
 * calls come from menu items, which run inside SDL's event loop on the
 * main thread, so always between ticks.
 */
#ifndef MAX80_APP_H
#define MAX80_APP_H

#include <stdint.h>

#ifdef MAX80_START
#define MAX80_APP_NAME "MAX-80 Start"
#else
#define MAX80_APP_NAME "MAX-80"
#endif

/* Drives are 0 to 3, A: to D: */

/* Puts an .imd in drive d. 0 done, 1 busy (the FDC has a command
   going: try again next tick), -1 not loaded or not allowed. */
int app_insert(int d, const char *path);
/* Takes the disk out. 0 done, 1 busy. */
int app_eject(int d);
/* Writes drive d's disk to path, which then is the drive's file. Never
   over another loaded image, nor over this one unless the app saved it.
   0 done, -1 not written, the reason in why. */
int app_save(int d, const char *path, char *why, int whylen);
/* The disk's file, or NULL for none */
const char *app_disk(int d);
/* 1 when the disk has writes not saved */
int app_changed(int d);
/* The disk's kind, read from its tracks: 8 for 8-inch, 5 for 5.25-inch,
   0 for no disk or none formatted yet */
int app_kind(int d);
/* Write-protect, at once */
void app_set_wprot(int d, int on);
/* The DIP switch byte, as the machine reads it */
void app_set_dips(int v);
int app_dips(void);
/* Fast: no pacing to real time, at once */
void app_set_fast(int on);
int app_fast(void);

#ifdef GUI_APP
/* The emulator calls these, from main() and the window code. A GUI
   front end, built with GUI_APP, fills them */
void gui_args(int *argc, char ***argv);	/* the saved settings, at launch */
void gui_init(void);			/* once the window is open */
void gui_tick(void);			/* each tick: inserts that were busy */
int gui_quit(void);			/* 1 to quit: unsaved disks asked about */
void gui_drop(const char *path);	/* a file dropped on the window */
int gui_on(void);			/* 0 while the machine is switched off */
#endif

#endif
