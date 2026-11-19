/* A quad buffer GLX child of a top level that is mapped late, as Tk does for Netgen's drawing area: the child is mapped
   inside the unmapped window, drawn and swapped once, and the window is mapped MAP_MS later; the child keeps swapping
   every GAP_MS. REMAP=N then unmaps the window, swaps while it is away and maps it again, N times. EARLY_MAP=1 maps the window first
   (the control: a child of a window that is mapped from the start). */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <GL/glx.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static Display *d;
static void show(const char *when, Window w, const char *name)
{
    Atom a = XInternAtom(d, name, False), t; int f; unsigned long n, r; unsigned char *p = NULL;
    if (XGetWindowProperty(d, w, a, 0, 4, False, AnyPropertyType, &t, &f, &n, &r, &p) == Success && p && n) {
        printf("%s %s:", when, name); for (unsigned long i = 0; i < n; i++) printf(" %lu", ((unsigned long *)p)[i]); printf("\n");
    } else printf("%s %s: none\n", when, name);
    if (p) XFree(p);
    fflush(stdout);
}
static long env(const char *k, long def) { const char *v = getenv(k); return v ? atol(v) : def; }
static Window child;
static void swaps(long n, long gap)
{
    for (long i = 0; i < n; i++) {
        glViewport(0, 0, 640, 400);
        glDrawBuffer(GL_BACK_LEFT); glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glDrawBuffer(GL_BACK_RIGHT); glClearColor(0, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glXSwapBuffers(d, child);
        usleep(gap * 1000);
    }
}
int main(void)
{
    d = XOpenDisplay(NULL); if (!d) return 2;
    int attr[] = { GLX_RGBA, GLX_DOUBLEBUFFER, GLX_STEREO, GLX_RED_SIZE, 8, GLX_DEPTH_SIZE, 16, None };
    XVisualInfo *vi = glXChooseVisual(d, DefaultScreen(d), attr);
    if (!vi) { printf("no stereo visual\n"); return 3; }
    XSetWindowAttributes sa = { .colormap = XCreateColormap(d, RootWindow(d, vi->screen), vi->visual, AllocNone), .border_pixel = 0, .event_mask = ExposureMask | StructureNotifyMask };
    Window top = XCreateSimpleWindow(d, RootWindow(d, vi->screen), 0, 0, 800, 560, 0, 0, 0x808080);
    XStoreName(d, top, "glx-child-late-map");
    child = XCreateWindow(d, top, 40, 40, 640, 400, 0, vi->depth, InputOutput, vi->visual, CWColormap | CWBorderPixel | CWEventMask, &sa);
    GLXContext ctx = glXCreateContext(d, vi, NULL, True);
    glXMakeCurrent(d, child, ctx);
    long gap = env("GAP_MS", 100);
    XMapWindow(d, child);
    if (env("EARLY_MAP", 0)) XMapWindow(d, top);
    XFlush(d);
    usleep(env("FIRST_SWAP_MS", 500) * 1000);
    swaps(1, 0);
    printf("first swap done, window viewable: %d\n", (int)env("EARLY_MAP", 0)); fflush(stdout);
    usleep(env("MAP_MS", 700) * 1000);
    if (!env("EARLY_MAP", 0)) { XMapWindow(d, top); XFlush(d); printf("window mapped\n"); fflush(stdout); }
    swaps(env("SWAPS", 40), gap);
    show("after map", child, "_KDE_NET_WM_STEREO_CONTENT");
    show("after map", top, "_KDE_NET_WM_STEREO_CONTENT_CHILDREN");
    for (long r = 1; r <= env("REMAP", 0); r++) {
        XUnmapWindow(d, top); XFlush(d); usleep(300000);
        swaps(10, gap);
        printf("window unmapped, swapped\n"); fflush(stdout);
        XMapWindow(d, top); XFlush(d);
        swaps(env("SWAPS", 40), gap);
        printf("after remap %ld ", r); show("", child, "_KDE_NET_WM_STEREO_CONTENT");
    }
    usleep(env("HOLD_MS", 6000) * 1000);
    return 0;
}
