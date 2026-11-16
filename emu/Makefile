# MAX-80 emulator. make, then make test.
# The window needs SDL2, found with pkg-config. make SDL=0 builds
# the terminal-only version. sdl2-config is used when pkg-config is not there.
CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra
SDL ?= 1

ifeq ($(OS),Windows_NT)
# Windows, MinGW-w64 and mingw32-make: SDL2's MinGW development
# release unpacked in win/sdl2 (its x86_64-w64-mingw32 folder), not in
# git. The window only, no terminal mode. SDL2.dll goes beside max80.exe
CC = gcc
WIN_LIBS := -lwinmm
ifeq ($(SDL),1)
ifneq ($(wildcard win/sdl2/include/SDL2/SDL.h),)
SDL_CFLAGS := -DHAVE_SDL -Iwin/sdl2/include/SDL2
SDL_LIBS := -Lwin/sdl2/lib -lmingw32 -lSDL2main -lSDL2
endif
endif
else ifeq ($(SDL),1)
SDL_LIBS := $(shell pkg-config --libs sdl2 2>/dev/null)
ifneq ($(SDL_LIBS),)
SDL_CFLAGS := -DHAVE_SDL $(shell pkg-config --cflags sdl2)
else
# no pkg-config, as on a Mac with Homebrew's SDL2 only
SDL_LIBS := $(shell sdl2-config --libs 2>/dev/null)
ifneq ($(SDL_LIBS),)
SDL_CFLAGS := -DHAVE_SDL $(shell sdl2-config --cflags)
endif
endif
endif

ifneq ($(SDL_CFLAGS),)
TEST_KEYS := test_keys
endif

all: max80 cpmtest test_track test_sasi test_iff test_dev test_app $(TEST_KEYS)

max80: max80.c z80.c z80.h app.h
	$(CC) $(CFLAGS) $(SDL_CFLAGS) -o $@ max80.c z80.c $(SDL_LIBS) $(WIN_LIBS)

cpmtest: cpmtest.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ cpmtest.c z80.c

test_track: test_track.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_track.c z80.c $(WIN_LIBS)

test_iff: test_iff.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_iff.c z80.c

test_sasi: test_sasi.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_sasi.c z80.c $(WIN_LIBS)

test_dev: test_dev.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) -o $@ test_dev.c z80.c $(WIN_LIBS)

test_app: test_app.c max80.c z80.c z80.h app.h
	$(CC) $(CFLAGS) -o $@ test_app.c z80.c $(WIN_LIBS)

test_keys: test_keys.c max80.c z80.c z80.h
	$(CC) $(CFLAGS) $(SDL_CFLAGS) -o $@ test_keys.c z80.c $(SDL_LIBS) $(WIN_LIBS)

test: all
	./test.sh


clean:
	rm -f max80 cpmtest test_track test_sasi test_iff test_dev test_app test_keys
	rm -rf build

.PHONY: all test clean
