/* SPDX-License-Identifier: GPL-2.0-or-later OR MIT */
/* Synthetic stereo test: nested translate, projection unchanged, distinct bands. */

#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "quads-xform: cannot open display\n"); return 1; }
    int screen = DefaultScreen(dpy);
    Window root = RootWindow(dpy, screen);
    int attribs[] = {GLX_RGBA, GLX_DOUBLEBUFFER, GLX_DEPTH_SIZE, 24, None};
    XVisualInfo *vi = glXChooseVisual(dpy, screen, attribs);
    if (!vi) return 2;
    XSetWindowAttributes swa = {0};
    swa.event_mask = ExposureMask;
    swa.colormap = XCreateColormap(dpy, root, vi->visual, AllocNone);
    Window w = XCreateWindow(dpy, root, 0, 0, 640, 360, 0,
                             vi->depth, InputOutput, vi->visual,
                             CWEventMask | CWColormap, &swa);
    XMapWindow(dpy, w);
    GLXContext ctx = glXCreateContext(dpy, vi, NULL, GL_TRUE);
    if (!ctx || !glXMakeCurrent(dpy, w, ctx)) return 3;
    XFree(vi);
    glXWaitX();

    glViewport(0, 0, 640, 360);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    double n = 1.0, f = 100.0, t = 0.5;
    double r = t * n, l = -r, b = -0.5, tp = 0.5;
    glFrustum(l, r, b, tp, n, f);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glColor3f(0, 1, 0);
    glBegin(GL_QUADS);
    glVertex3f(-0.2f,  0.1f, -n * 5.0f);
    glVertex3f( 0.2f,  0.1f, -n * 5.0f);
    glVertex3f( 0.2f, -0.3f, -n * 5.0f);
    glVertex3f(-0.2f, -0.3f, -n * 5.0f);
    glEnd();

    glPushMatrix();
    glTranslatef(0.0f, 0.0f, (float)(-n * 5.0));
    glPushMatrix();
    glTranslatef(0.0f, 0.0f, (float)(n * 5.0 / 2.0));
    glColor3f(1, 0, 0);
    glBegin(GL_QUADS);
    glVertex3f(-0.2f,  0.6f, 0.0f);
    glVertex3f( 0.2f,  0.6f, 0.0f);
    glVertex3f( 0.2f,  0.2f, 0.0f);
    glVertex3f(-0.2f,  0.2f, 0.0f);
    glEnd();
    glPopMatrix();
    glPopMatrix();

    glColor3f(0, 0, 1);
    glBegin(GL_QUADS);
    glVertex3f(-0.2f, -1.2f, -n * 5.0f * 2.0f);
    glVertex3f( 0.2f, -1.2f, -n * 5.0f * 2.0f);
    glVertex3f( 0.2f, -1.6f, -n * 5.0f * 2.0f);
    glVertex3f(-0.2f, -1.6f, -n * 5.0f * 2.0f);
    glEnd();

    GLenum error = glGetError();
    if (error) { fprintf(stderr, "GL error: %x\n", error); return 4; }
    glXSwapBuffers(dpy, w);
    glXWaitGL();

    glXMakeCurrent(dpy, None, NULL);
    glXDestroyContext(dpy, ctx);
    XDestroyWindow(dpy, w);
    XCloseDisplay(dpy);
    return 0;
}
