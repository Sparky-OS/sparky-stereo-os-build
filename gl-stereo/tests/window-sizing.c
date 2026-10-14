/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static Display *display;
static Window window;
static int (*raw_attributes)(Display *, Window, XWindowAttributes *);
static Bool requested_size(Display *d,XEvent *event,XPointer argument)
{
    (void)d;
    if (getenv("TEST_PREDICATE_LOG") && event->type==ConfigureNotify)
        fprintf(stderr,"predicate width=%d expected=%d send_event=%d window=%lu expected_window=%lu serial=%lu\n",event->xconfigure.width,*(int *)argument,event->xconfigure.send_event,event->xconfigure.window,window,event->xconfigure.serial);
    return event->type==ConfigureNotify && event->xconfigure.window==window &&
           event->xconfigure.width==*(int *)argument;
}
static void check_predicates(int width,int height)
{
    XEvent event,result;
    memset(&event,0,sizeof(event));
    event.xconfigure.type=ConfigureNotify;event.xconfigure.display=display;
    event.xconfigure.window=window;event.xconfigure.serial=NextRequest(display);
    event.xconfigure.width=2*width;event.xconfigure.height=height;
    XPutBackEvent(display,&event);
    assert(XCheckIfEvent(display,&result,requested_size,(XPointer)&width));
    assert(result.xconfigure.width==width);
    XPutBackEvent(display,&event);
    XPeekIfEvent(display,&result,requested_size,(XPointer)&width);
    assert(result.xconfigure.width==width);
    XIfEvent(display,&result,requested_size,(XPointer)&width);
    assert(result.xconfigure.width==width);
}
static void settle(int width, int height)
{
    int last = 0;
    for (int i = 0; i < 100; ++i) {
        XSync(display, False);
        while (XPending(display)) {
            XEvent e; XNextEvent(display, &e);
            if (e.type == ConfigureNotify) last = e.xconfigure.width;
        }
        usleep(10000);
    }
    XWindowAttributes raw, app;
    assert(raw_attributes(display, window, &raw));
    assert(XGetWindowAttributes(display, window, &app));
    fprintf(stderr, "requested=%d raw=%d app=%d event=%d\n", width, raw.width, app.width, last);
    assert(raw.width == width * 2 && raw.height == height);
    assert(app.width == width && app.height == height);
    assert(last == width);
    check_predicates(width,height);
    unsigned glwidth = 0;
    glXQueryDrawable(display, window, GLX_WIDTH, &glwidth);
    fprintf(stderr, "GLX width=%u\n", glwidth);
    assert(glwidth == (unsigned)width);
    glXSwapBuffers(display, window);
    for (int frame = 0; frame < 3; ++frame) {
        glViewport(0, 0, width, height);
        glMatrixMode(GL_PROJECTION); glLoadIdentity(); glOrtho(-1,1,-1,1,-1,1);
        glMatrixMode(GL_MODELVIEW); glLoadIdentity();
        glClearColor(0,0,0,1); glClear(GL_COLOR_BUFFER_BIT);
        glBegin(GL_QUADS);
        glColor3f(1,0,0);
        glVertex2f(-.8,-.5); glVertex2f(-.2,-.5); glVertex2f(-.2,.5); glVertex2f(-.8,.5);
        glColor3f(0,0,1);
        glVertex2f(.2,-.5); glVertex2f(.8,-.5); glVertex2f(.8,.5); glVertex2f(.2,.5);
        glEnd();
        glFinish();
        if (frame == 2) for (int eye = 0; eye < 2; ++eye) {
            unsigned char pixel[3] = {99,99,99};
            glReadPixels(eye*width+width/4, height/2, 1, 1, GL_RGB, GL_UNSIGNED_BYTE, pixel);
            fprintf(stderr, "eye %d red sample %u %u %u\n", eye, pixel[0], pixel[1], pixel[2]);
            assert(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0);
            glReadPixels(eye*width+3*width/4, height/2, 1, 1, GL_RGB, GL_UNSIGNED_BYTE, pixel);
            assert(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 255);
        }
        glXSwapBuffers(display, window);
    }
}
int main(void)
{
    display = XOpenDisplay(NULL); assert(display);
    if (getenv("TEST_SUPPORT_VERSION")) {
        unsigned long version = strtoul(getenv("TEST_SUPPORT_VERSION"), NULL, 10);
        Atom supported = XInternAtom(display, "_KDE_NET_WM_STEREO_CONTENT_SUPPORTED", False);
        XChangeProperty(display, DefaultRootWindow(display), supported, XA_CARDINAL, 32,
                        PropModeReplace, (unsigned char *)&version, 1);
        XSync(display, False);
    }
    void *x11 = dlopen("libX11.so.6", RTLD_NOW); assert(x11);
    void *(*lookup)(void *, const char *) = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    assert(lookup);
    *(void **)(&raw_attributes) = lookup(x11, "XGetWindowAttributes"); assert(raw_attributes);
    int attrs[] = { GLX_RGBA, GLX_DOUBLEBUFFER, None, None };
    if (getenv("TEST_QUAD")) attrs[2] = GLX_STEREO;
    XVisualInfo *v = glXChooseVisual(display, DefaultScreen(display), attrs); assert(v);
    XSetWindowAttributes a = {0};
    a.colormap = XCreateColormap(display, DefaultRootWindow(display), v->visual, AllocNone);
    a.event_mask = StructureNotifyMask;
    window = XCreateWindow(display, DefaultRootWindow(display), 100,100,400,300,0,
                           v->depth,InputOutput,v->visual,CWColormap|CWEventMask,&a);
    XStoreName(display,window,"gl-stereo-sizing");
    if (!getenv("TEST_UNMAPPED")) XMapWindow(display,window);
    XSync(display,False);
    GLXContext c = glXCreateContext(display,v,NULL,True); assert(c);
    assert(glXMakeCurrent(display,window,c));
    if (getenv("TEST_UNMAPPED")) {
        XResizeWindow(display,window,420,310);XSync(display,False);
        int width=420;XEvent event;
        assert(XCheckIfEvent(display,&event,requested_size,(XPointer)&width));
        XWindowAttributes a;assert(XGetWindowAttributes(display,window,&a));assert(a.width==420);
        unsigned glwidth;glXQueryDrawable(display,window,GLX_WIDTH,&glwidth);assert(glwidth==420);
        puts("PASS: unmapped compositor-owned window reports its requested size");return 0;
    }
    settle(400,300);
    XResizeWindow(display,window,420,310); settle(420,310);
    XMoveResizeWindow(display,window,100,100,440,320); settle(440,320);
    XWindowChanges changes = {.width=400,.height=300};
    XConfigureWindow(display,window,CWWidth|CWHeight,&changes); settle(400,300);
    puts("PASS: initial size, resize, move-resize, configure, logical events and both eye buffers"); fflush(stdout);
    if (!getenv("TEST_SUPPORT_VERSION") || getenv("TEST_RIG")) sleep(8);
    return 0;
}
