/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A program that draws only when the window system asks (Expose, ConfigureNotify), like a
 * still picture. Run under a compositor that sizes declared windows late: it must show both
 * eyes once the compositor has doubled its window, with no input. TEST_MAPPED names a file
 * written once the window is mapped; the program then waits for TEST_GO before it makes its
 * context current (where the layer declares the window). */
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void draw(Display *display, Window window, unsigned *count)
{
    XWindowAttributes a; XGetWindowAttributes(display, window, &a);
    glViewport(0, 0, a.width, a.height);
    glMatrixMode(GL_PROJECTION); glLoadIdentity(); glOrtho(-1, 1, -1, 1, -1, 1);
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    glBegin(GL_QUADS);
    glColor3f(1, 0, 0);
    glVertex2f(-.8, -.5); glVertex2f(-.2, -.5); glVertex2f(-.2, .5); glVertex2f(-.8, .5);
    glColor3f(0, 0, 1);
    glVertex2f(.2, -.5); glVertex2f(.8, -.5); glVertex2f(.8, .5); glVertex2f(.2, .5);
    glEnd();
    glXSwapBuffers(display, window);
    fprintf(stderr, "draw %u at %dx%d\n", ++*count, a.width, a.height);
}
int main(void)
{
    Display *display = XOpenDisplay(NULL); assert(display);
    int attributes[] = { GLX_RGBA, GLX_DOUBLEBUFFER, None };
    XVisualInfo *visual = glXChooseVisual(display, DefaultScreen(display), attributes); assert(visual);
    XSetWindowAttributes a = {0};
    a.colormap = XCreateColormap(display, DefaultRootWindow(display), visual->visual, AllocNone);
    a.event_mask = ExposureMask | StructureNotifyMask;
    Window window = XCreateWindow(display, DefaultRootWindow(display), 100, 100, 400, 300, 0, visual->depth,
                                  InputOutput, visual->visual, CWColormap | CWEventMask, &a);
    XStoreName(display, window, "gl-stereo-late-doubling");
    XMapWindow(display, window);
    XEvent event;
    do XNextEvent(display, &event); while (event.type != MapNotify);
    if (getenv("TEST_MAPPED")) { FILE *f = fopen(getenv("TEST_MAPPED"), "w"); assert(f); fclose(f); }
    if (getenv("TEST_GO")) while (access(getenv("TEST_GO"), F_OK)) usleep(2000);
    GLXContext context = glXCreateContext(display, visual, NULL, True); assert(context);
    assert(glXMakeCurrent(display, window, context));
    unsigned count = 0;
    draw(display, window, &count);
    for (;;) {
        XNextEvent(display, &event);
        if ((event.type == Expose && event.xexpose.count == 0) || event.type == ConfigureNotify) {
            if (event.type == ConfigureNotify) fprintf(stderr, "configure %dx%d\n", event.xconfigure.width, event.xconfigure.height);
            draw(display, window, &count);
        }
    }
}
