/* sdltest.c (ORDER 22): what SDL3 (and so SDL2 through sdl2-compat) says about the guest's virtual joystick.
 * Prints LAB|sdl|...|buttons=N|axes=N|hats=N|pressed=N. Needs the device from hidtest. */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main(void)
{
	if (!SDL_Init(SDL_INIT_JOYSTICK)) {
		printf("LAB|sdl|error|SDL_Init: %s\n", SDL_GetError());
		return 2;
	}
	int n = 0;
	SDL_JoystickID *ids = NULL;
	for (int t = 0; t < 50; t++) {
		SDL_UpdateJoysticks();
		ids = SDL_GetJoysticks(&n);
		if (n > 0)
			break;
		SDL_free(ids);
		SDL_Delay(100);
	}
	if (n <= 0) {
		printf("LAB|sdl|error|SDL listed no joystick\n");
		return 3;
	}
	SDL_Joystick *j = SDL_OpenJoystick(ids[0]);
	if (!j) {
		printf("LAB|sdl|error|SDL_OpenJoystick: %s\n", SDL_GetError());
		return 3;
	}
	close(open("/tmp/sdl.open", O_CREAT | O_WRONLY, 0644));
	for (int t = 0; t < 40 && access("/tmp/hid.resent", F_OK) != 0; t++)
		SDL_Delay(100);
	for (int t = 0; t < 6; t++) {
		SDL_UpdateJoysticks();
		SDL_Delay(100);
	}
	int nb = SDL_GetNumJoystickButtons(j), pressed = 0;
	for (int i = 0; i < nb; i++)
		pressed += SDL_GetJoystickButton(j, i) ? 1 : 0;
	printf("LAB|sdl|%s|buttons=%d|axes=%d|hats=%d|pressed=%d|sdl_version=%d\n", SDL_GetJoystickName(j), nb,
	       SDL_GetNumJoystickAxes(j), SDL_GetNumJoystickHats(j), pressed, SDL_GetVersion());
	return 0;
}
