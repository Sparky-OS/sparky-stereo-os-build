/* glx-covered.c: a GLX quad buffer window with a plain child window over part of it, as a toolkit puts a tool bar or a
 * button over its 3D area.  Left eye red, right eye blue, a green rectangle in the middle of both, a white square that
 * moves 16 pixels with every swap at the same place in both eyes, and a 60x60 child window at 30, H/2 (grey; yellow after
 * CHILD_PAINT_AT).  The X server cannot flip the presented pixmap of a window that a child clips.
 *   COVER_AT=N        map the child before swap N (default 0: from the start; -1: never)
 *   UNCOVER_AT=N      unmap it before swap N (default: never)
 *   CHILD_PAINT_AT=N  paint the child yellow before swap N, through the X server, not OpenGL (default: never)
 *   STILL_AT=N        make no swap from swap N on, stay HOLD_S seconds (a program that draws once)
 *   FRAMES=N          swaps (default 200), PERIOD_MS apart (default 50); HOLD_S seconds after the last (default 0)
 *   W, H              the window's size (default 800x600)
 *   ANNOUNCE_STEREO=N stand in for the compositor: the root window announces stereo declaration version N (a test on a
 *                     plain X server, where every present is copied)
 *   READBACK=1        at the end print three pixels of the X window itself: 1/8 from its left, its middle, 1/8 from its right
 * It prints GL_STEREO, the renderer and, at every swap whose number is in REPORT (comma separated), the window's
 * _KDE_NET_WM_STEREO_CONTENT (0 when it is not set).
 * Build: cc -O1 -o glx-covered glx-covered.c -lGL -lX11
 * SPDX-License-Identifier: MIT */
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int num(const char *name, int def)
{
    return getenv(name) ? atoi(getenv(name)) : def;
}

static long declared(Display *d, Window w)
{
    Atom type; int format; unsigned long n, left; unsigned char *data = NULL; long v = 0;
    if (XGetWindowProperty(d, w, XInternAtom(d, "_KDE_NET_WM_STEREO_CONTENT", False), 0, 1, False, XA_CARDINAL, &type, &format, &n, &left,
                           &data) == Success && data && n == 1 && format == 32)
        v = *(long *)data;
    if (data)
        XFree(data);
    return v;
}

static int listed(const char *list, int i)
{
    char key[16], *copy, *tok; int hit = 0;
    if (!list)
        return 0;
    snprintf(key, sizeof key, "%d", i);
    copy = strdup(list);
    for (tok = strtok(copy, ","); tok; tok = strtok(NULL, ","))
        hit |= !strcmp(tok, key);
    free(copy);
    return hit;
}

int main(void)
{
    int w = num("W", 800), h = num("H", 600), frames = num("FRAMES", 200), period = num("PERIOD_MS", 50) * 1000, n = 0;
    int cover_at = num("COVER_AT", 0), uncover_at = num("UNCOVER_AT", -1), paint_at = num("CHILD_PAINT_AT", -1), still_at = num("STILL_AT", -1);
    Display *d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "glx-covered: no display\n"); return 2; }
    if (getenv("ANNOUNCE_STEREO")) {
        unsigned long version = atoi(getenv("ANNOUNCE_STEREO"));
        XChangeProperty(d, DefaultRootWindow(d), XInternAtom(d, "_KDE_NET_WM_STEREO_CONTENT_SUPPORTED", False), XA_CARDINAL, 32, PropModeReplace,
                        (unsigned char *)&version, 1);
        XSync(d, False);
    }
    int att[] = { GLX_RENDER_TYPE, GLX_RGBA_BIT, GLX_DRAWABLE_TYPE, GLX_WINDOW_BIT, GLX_DOUBLEBUFFER, True, GLX_STEREO, True,
                  GLX_RED_SIZE, 8, GLX_GREEN_SIZE, 8, GLX_BLUE_SIZE, 8, GLX_DEPTH_SIZE, 24, None };
    GLXFBConfig *c = glXChooseFBConfig(d, DefaultScreen(d), att, &n);
    if (!c || !n) { fprintf(stderr, "glx-covered: no stereo framebuffer configuration\n"); return 4; }
    XVisualInfo *vi = glXGetVisualFromFBConfig(d, c[0]);
    XSetWindowAttributes swa; memset(&swa, 0, sizeof swa);
    swa.colormap = XCreateColormap(d, RootWindow(d, vi->screen), vi->visual, AllocNone);
    swa.event_mask = StructureNotifyMask | ExposureMask;
    Window win = XCreateWindow(d, RootWindow(d, vi->screen), 100, 100, w, h, 0, vi->depth, InputOutput, vi->visual, CWColormap | CWEventMask, &swa);
    XStoreName(d, win, "glx-covered");
    XSetWindowAttributes cwa; memset(&cwa, 0, sizeof cwa);
    cwa.background_pixel = 0xff808080; cwa.colormap = swa.colormap; cwa.border_pixel = 0;
    Window cover = XCreateWindow(d, win, 30, h / 2, 60, 60, 0, vi->depth, InputOutput, vi->visual, CWBackPixel | CWColormap | CWBorderPixel, &cwa);
    if (cover_at == 0)
        XMapWindow(d, cover);
    XMapWindow(d, win);
    for (;;) { XEvent e; XNextEvent(d, &e); if (e.type == Expose) break; }
    GLXContext ctx = glXCreateNewContext(d, c[0], GLX_RGBA_TYPE, NULL, True);
    if (!ctx) { fprintf(stderr, "glx-covered: no context\n"); return 5; }
    glXMakeCurrent(d, win, ctx);
    GLboolean st = 0; glGetBooleanv(GL_STEREO, &st);
    printf("glx-covered: GL_STEREO %d renderer %s\n", st, glGetString(GL_RENDERER)); fflush(stdout);
    for (int i = 1; i <= frames; i++) {
        while (XPending(d)) { XEvent e; XNextEvent(d, &e); if (e.type == ConfigureNotify && !e.xconfigure.send_event) { w = e.xconfigure.width; h = e.xconfigure.height; } }
        if (i == cover_at) { XMapWindow(d, cover); XSync(d, False); printf("glx-covered: swap %d: covered\n", i); }
        if (i == uncover_at) { XUnmapWindow(d, cover); XSync(d, False); printf("glx-covered: swap %d: uncovered\n", i); }
        if (i == paint_at) { XSetWindowBackground(d, cover, 0xffc0c000); XClearWindow(d, cover); XSync(d, False); printf("glx-covered: swap %d: child painted\n", i); }
        if (still_at < 0 || i < still_at) {
            int x = (16 * i) % (w - 40);
            glViewport(0, 0, w, h);
            for (int eye = 0; eye < 2; eye++) {
                glDrawBuffer(eye ? GL_BACK_RIGHT : GL_BACK_LEFT);
                glDisable(GL_SCISSOR_TEST);
                glClearColor(eye ? 0 : 1, 0, eye ? 1 : 0, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
                glEnable(GL_SCISSOR_TEST);
                glScissor(w / 4, h / 4, w / 2, h / 2); glClearColor(0, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
                glScissor(x, h - 60, 40, 40); glClearColor(1, 1, 1, 1); glClear(GL_COLOR_BUFFER_BIT);
            }
            glXSwapBuffers(d, win);
        }
        if (listed(getenv("REPORT"), i)) { XSync(d, False); printf("glx-covered: swap %d: declared %ld\n", i, declared(d, win)); }
        fflush(stdout);
        usleep(period);
    }
    XSync(d, False);
    printf("glx-covered: end: declared %ld\n", declared(d, win)); fflush(stdout);
    if (getenv("READBACK")) {
        XWindowAttributes wa; XGetWindowAttributes(d, win, &wa);
        XImage *im = XGetImage(d, win, 0, wa.height / 8, wa.width, 1, AllPlanes, ZPixmap);
        XImage *mid = XGetImage(d, win, wa.width / 2, wa.height / 2, 1, 1, AllPlanes, ZPixmap);
        if (im && mid)
            printf("glx-covered: window %dx%d left=%06lx middle=%06lx right=%06lx\n", wa.width, wa.height,
                   XGetPixel(im, wa.width / 8, 0) & 0xffffff, XGetPixel(mid, 0, 0) & 0xffffff, XGetPixel(im, wa.width - wa.width / 8, 0) & 0xffffff);
        fflush(stdout);
    }
    sleep(num("HOLD_S", 0));
    return 0;
}
