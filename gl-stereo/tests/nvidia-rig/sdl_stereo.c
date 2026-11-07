/* LEFT eye red, RIGHT eye blue, through SDL_GL_STEREO. Build: -DSDL3 or SDL 2 (sdl2-compat). */
#include <stdio.h>
#include <stdlib.h>
#ifdef SDL3
#include <SDL3/SDL.h>
#else
#include <SDL2/SDL.h>
#endif
#include <GL/gl.h>
int main(int argc, char **argv)
{
    int seconds = argc > 1 ? atoi(argv[1]) : 8;
    if (SDL_Init(SDL_INIT_VIDEO) != 0 && 0) {}
    int mono = getenv("MONO") != NULL;
    if (!mono) SDL_GL_SetAttribute(SDL_GL_STEREO, 1);
#ifdef SDL3
    SDL_Window *w = SDL_CreateWindow("stereo", 400, 300, SDL_WINDOW_OPENGL);
#else
    SDL_Window *w = SDL_CreateWindow("stereo", 100, 100, 400, 300, SDL_WINDOW_OPENGL);
#endif
    if (!w) { printf("RESULT window-failed %s\n", SDL_GetError()); return 2; }
    SDL_GLContext c = SDL_GL_CreateContext(w);
    if (!c) { printf("RESULT context-failed %s\n", SDL_GetError()); return 2; }
    int st = -1;
    SDL_GL_GetAttribute(SDL_GL_STEREO, &st);
    printf("RESULT driver=%s stereo-attr=%d renderer=%s\n", SDL_GetCurrentVideoDriver(), st, glGetString(GL_RENDERER));
    fflush(stdout);
    Uint64 t0 = SDL_GetTicks();
    while (SDL_GetTicks() - t0 < (Uint64)seconds * 1000) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {}
        if (mono) { glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT); SDL_GL_SwapWindow(w); SDL_Delay(16); continue; }
        int swap = getenv("SWAP_EYES") != NULL;
        glDrawBuffer(GL_BACK_LEFT);  glClearColor(swap ? 0 : 1, 0, swap ? 1 : 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glDrawBuffer(GL_BACK_RIGHT); glClearColor(swap ? 1 : 0, 0, swap ? 0 : 1, 1); glClear(GL_COLOR_BUFFER_BIT);
        SDL_GL_SwapWindow(w);
        SDL_Delay(16);
    }
    return 0;
}
