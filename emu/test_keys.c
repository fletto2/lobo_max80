/*
 * The window's keys: a key down with no modifier is held in the
 * matrix until it comes up, the host's auto repeat left out, and its
 * text not typed again. Shifted keys still go through the key queue.
 * SDL events are pushed and read by win_events itself, with no window.
 * Built with max80.c itself, its main renamed, and SDL2.
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

static void key(int type, SDL_Keycode sym, SDL_Scancode sc, Uint16 mod, int repeat)
{
	SDL_Event e;

	memset(&e, 0, sizeof(e));
	e.type = type;
	e.key.state = type == SDL_KEYDOWN ? SDL_PRESSED : SDL_RELEASED;
	e.key.repeat = repeat;
	e.key.keysym.sym = sym;
	e.key.keysym.scancode = sc;
	e.key.keysym.mod = mod;
	SDL_PushEvent(&e);
}

static void text(const char *s)
{
	SDL_Event e;

	memset(&e, 0, sizeof(e));
	e.type = SDL_TEXTINPUT;
	snprintf(e.text.text, sizeof(e.text.text), "%s", s);
	SDL_PushEvent(&e);
}

static int queued(void)
{
	return (keyq_tail - keyq_head + KEYQ) % KEYQ;
}

static int held(int row, int bit)
{
	return keyheld[row] >> bit & 1;
}

int main(void)
{
	if (SDL_Init(SDL_INIT_EVENTS) != 0) {
		printf("FAIL SDL_Init: %s\n", SDL_GetError());
		return 1;
	}

	/* DOWN held, the host repeating it, then let go */
	key(SDL_KEYDOWN, SDLK_DOWN, SDL_SCANCODE_DOWN, 0, 0);
	win_events();
	expect(held(6, 4), "DOWN down: row 6 bit 4 held");
	for (int i = 0; i < 20; i++)
		key(SDL_KEYDOWN, SDLK_DOWN, SDL_SCANCODE_DOWN, 0, 1);
	win_events();
	expect(held(6, 4) && queued() == 0, "DOWN repeated by the host: still held, nothing queued");
	key(SDL_KEYUP, SDLK_DOWN, SDL_SCANCODE_DOWN, 0, 0);
	win_events();
	expect(!held(6, 4) && queued() == 0, "DOWN up: let go at once");

	/* A letter: held, its text not typed again */
	key(SDL_KEYDOWN, SDLK_z, SDL_SCANCODE_Z, 0, 0);
	text("z");
	win_events();
	expect(held(3, 2) && queued() == 0, "z down: row 3 bit 2 held, its text left out");
	key(SDL_KEYDOWN, SDLK_z, SDL_SCANCODE_Z, 0, 1);
	text("z");
	win_events();
	expect(queued() == 0, "z repeated by the host: its text left out");
	key(SDL_KEYUP, SDLK_z, SDL_SCANCODE_Z, 0, 0);
	win_events();
	expect(!held(3, 2), "z up");

	/* Shifted: through the queue as typed, nothing held */
	key(SDL_KEYDOWN, SDLK_a, SDL_SCANCODE_A, KMOD_LSHIFT, 0);
	text("A");
	win_events();
	expect(!held(0, 1) && queued() == 1 && keyq[keyq_head] == 'A', "Shift a: A queued, not held");
	keyq_head = keyq_tail;
	key(SDL_KEYUP, SDLK_a, SDL_SCANCODE_A, KMOD_LSHIFT, 0);
	win_events();

	/* Caps Lock on: a letter as the capital typed, a digit still held */
	key(SDL_KEYDOWN, SDLK_a, SDL_SCANCODE_A, KMOD_CAPS, 0);
	text("A");
	win_events();
	expect(!held(0, 1) && queued() == 1 && keyq[keyq_head] == 'A', "Caps Lock a: A queued, not held");
	keyq_head = keyq_tail;
	key(SDL_KEYUP, SDLK_a, SDL_SCANCODE_A, KMOD_CAPS, 0);
	win_events();
	key(SDL_KEYDOWN, SDLK_1, SDL_SCANCODE_1, KMOD_CAPS, 0);
	text("1");
	win_events();
	expect(queued() == 0, "Caps Lock 1: held, its text left out");
	key(SDL_KEYUP, SDLK_1, SDL_SCANCODE_1, KMOD_CAPS, 0);
	win_events();

	/* ENTER and ESC held, no text for them */
	key(SDL_KEYDOWN, SDLK_RETURN, SDL_SCANCODE_RETURN, 0, 0);
	key(SDL_KEYDOWN, SDLK_ESCAPE, SDL_SCANCODE_ESCAPE, 0, 0);
	text("q");
	win_events();
	expect(held(6, 0) && held(7, 5), "ENTER and ESC down: held");
	expect(queued() == 1 && keyq[keyq_head] == 'q', "text after them still typed");
	keyq_head = keyq_tail;

	/* Two keys on one matrix bit: up only when both are */
	key(SDL_KEYDOWN, SDLK_KP_ENTER, SDL_SCANCODE_KP_ENTER, 0, 0);
	key(SDL_KEYUP, SDLK_RETURN, SDL_SCANCODE_RETURN, 0, 0);
	win_events();
	expect(held(6, 0), "ENTER up, keypad ENTER still down: held");
	key(SDL_KEYUP, SDLK_KP_ENTER, SDL_SCANCODE_KP_ENTER, 0, 0);
	win_events();
	expect(!held(6, 0), "both up: let go");

	/* The window loses the keyboard: nothing stays held */
	{
		SDL_Event e;

		memset(&e, 0, sizeof(e));
		e.type = SDL_WINDOWEVENT;
		e.window.event = SDL_WINDOWEVENT_FOCUS_LOST;
		SDL_PushEvent(&e);
	}
	win_events();
	expect(!held(7, 5), "focus lost: ESC let go");

	/* Ctrl-] still quits */
	key(SDL_KEYDOWN, SDLK_RIGHTBRACKET, SDL_SCANCODE_RIGHTBRACKET, KMOD_LCTRL, 0);
	expect(win_events() == 1, "Ctrl-] quits");

	SDL_Quit();
	return fails != 0;
}
