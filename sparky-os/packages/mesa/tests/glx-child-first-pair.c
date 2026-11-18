/* A plain top level with a quad buffer GLX child: the 3D area of a Qt, VTK or CloudCompare window.
   DELAY_MS waits between the map of both windows and the first swap, SWAPS and GAP_MS set the swaps after it. */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xlib-xcb.h>
#include <xcb/present.h>
#include <time.h>
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
int main(void)
{
    d = XOpenDisplay(NULL); if (!d) return 2;
    int attr[] = { GLX_RGBA, GLX_DOUBLEBUFFER, GLX_STEREO, GLX_RED_SIZE, 8, GLX_DEPTH_SIZE, 16, None };
    XVisualInfo *vi = glXChooseVisual(d, DefaultScreen(d), attr);
    if (!vi) { printf("no stereo visual\n"); return 3; }
    XSetWindowAttributes sa = { .colormap = XCreateColormap(d, RootWindow(d, vi->screen), vi->visual, AllocNone), .border_pixel = 0, .event_mask = ExposureMask | StructureNotifyMask };
    Window top = XCreateSimpleWindow(d, RootWindow(d, vi->screen), 0, 0, 800, 560, 0, 0, 0x808080);
    XStoreName(d, top, "glx-child");
    Window child = XCreateWindow(d, top, 40, 40, 640, 400, 0, vi->depth, InputOutput, vi->visual, CWColormap | CWBorderPixel | CWEventMask, &sa);
    GLXContext ctx = glXCreateContext(d, vi, NULL, True);
    glXMakeCurrent(d, child, ctx);
    XMapWindow(d, child); XMapWindow(d, top); XFlush(d);
    if (env("EARLY", 0)) { /* the declaration Mesa writes at the first swap, written now */
        unsigned long ver = 4, lay = 3;
        XChangeProperty(d, child, XInternAtom(d, "_KDE_NET_WM_STEREO_CONTENT_VERSION", False), XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&ver, 1);
        XChangeProperty(d, child, XInternAtom(d, "_KDE_NET_WM_STEREO_CONTENT", False), XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&lay, 1);
        XChangeProperty(d, top, XInternAtom(d, "_KDE_NET_WM_STEREO_CONTENT_CHILDREN", False), XA_WINDOW, 32, PropModeReplace, (unsigned char *)&child, 1);
        XFlush(d);
    }
    usleep(env("DELAY_MS", 0) * 1000);
    show("before first swap", child, "_KDE_NET_WM_STEREO_CONTENT");
    show("before first swap", top, "_KDE_NET_WM_STEREO_CONTENT_CHILDREN");
    xcb_connection_t *xc = XGetXCBConnection(d);
    xcb_special_event_t *trace = NULL;
    if (env("PRESENT_TRACE", 0)) {
        xcb_present_event_t eid = xcb_generate_id(xc);
        trace = xcb_register_for_special_xge(xc, &xcb_present_id, eid, NULL);
        xcb_present_select_input(xc, eid, child, XCB_PRESENT_EVENT_MASK_COMPLETE_NOTIFY);
        xcb_flush(xc);
    }
    long swaps = env("SWAPS", 1), gap = env("GAP_MS", 100);
    for (long i = 0; i < swaps; i++) {
        glViewport(0, 0, 640, 400);
        glDrawBuffer(GL_BACK_LEFT); glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glDrawBuffer(GL_BACK_RIGHT); glClearColor(0, 0, 1, 1); glClear(GL_COLOR_BUFFER_BIT);
        glXSwapBuffers(d, child);
        printf("swap %ld done\n", i + 1); fflush(stdout);
        if (i + 1 < swaps) usleep(gap * 1000);
    }
    if (trace) { /* the completions the server sent for the child's presents, in the order they came */
        for (int t = 0; t < 40; t++) {
            xcb_generic_event_t *ev;
            while ((ev = xcb_poll_for_special_event(xc, trace))) {
                xcb_present_generic_event_t *g = (xcb_present_generic_event_t *)ev;
                if (g->evtype == XCB_PRESENT_EVENT_COMPLETE_NOTIFY) {
                    xcb_present_complete_notify_event_t *c = (xcb_present_complete_notify_event_t *)ev;
                    printf("present complete: serial %u mode %u (0 copy 1 flip 2 skip 3 suboptimal copy)\n", c->serial, c->mode);
                }
                free(ev);
            }
            usleep(25000);
        }
        fflush(stdout);
    }
    show("after swaps", child, "_KDE_NET_WM_STEREO_CONTENT");
    show("after swaps", child, "_KDE_NET_WM_STEREO_DEPTH_LIMITS");
    usleep(2000000);
    show("2 s later", child, "_KDE_NET_WM_STEREO_CONTENT");
    show("2 s later", child, "_KDE_NET_WM_STEREO_DEPTH_LIMITS");
    usleep(env("HOLD_MS", 12000) * 1000);
    return 0;
}
