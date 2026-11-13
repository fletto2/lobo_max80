# MAX-80 emulator. make, then make test.
# The window needs SDL2, found with pkg-config. make SDL=0 builds
# the terminal-only version.
CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra
SDL ?= 1

ifeq ($(SDL),1)
SDL_LIBS := $(shell pkg-config --libs sdl2 2>/dev/null)
ifneq ($(SDL_LIBS),)
SDL_CFLAGS := -DHAVE_SDL $(shell pkg-config --cflags sdl2)
endif
endif

ifneq ($(SDL_CFLAGS),)
TEST_KEYS := test_keys
endif

all: max80 cpmtest test_track test_sasi test_iff test_dev $(TEST_KEYS)

max80: max80.c z80.c z80.h
	$(CC) $(CFLAGS) $(SDL_CFLAGS) -o $@ max80.c z80.c $(SDL_LIBS)

cpmtest: cpmtest.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ cpmtest.c z80.c

test_track: test_track.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_track.c z80.c

test_iff: test_iff.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_iff.c z80.c

test_sasi: test_sasi.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_sasi.c z80.c

test_dev: test_dev.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_dev.c z80.c

test_keys: test_keys.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) $(SDL_CFLAGS) -o $@ test_keys.c z80.c $(SDL_LIBS)

test: all
	./test.sh

clean:
	rm -f max80 cpmtest test_track test_sasi test_iff test_dev test_keys

.PHONY: all test clean
