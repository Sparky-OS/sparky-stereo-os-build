/* Test aid, not part of any package: glFinish() before every glXSwapBuffers, the flush the Mesa pack of the two eyes lacks. */
#define _GNU_SOURCE
#include <dlfcn.h>
typedef void (*fin_t)(void);
typedef void (*swap_t)(void *, unsigned long);
void glXSwapBuffers(void *dpy, unsigned long drawable)
{
    static swap_t real; static fin_t fin;
    if (!real) { real = (swap_t)dlsym(RTLD_NEXT, "glXSwapBuffers"); fin = (fin_t)dlsym(RTLD_DEFAULT, "glFinish"); }
    if (fin) fin();
    real(dpy, drawable);
}
