/* SPDX-License-Identifier: GPL-2.0-or-later OR MIT */
/* Synthetic stereo test: three quads at eye-space depths near, convergence, far.
 * Each quad is drawn in a distinct vertical band so depth test never occludes one.
 * Red = Z/2 (in front of screen), green = Z (screen plane), blue = 2Z (behind).
 */

#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "quads: cannot open display\n"); return 1; }
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

    for (int frame = 0; frame < (getenv("TEST_FRAMES") ? 40 : 1); ++frame) {
    glViewport(0, 0, 640, 360);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    double n = 1.0, f = 100.0, t = 0.5;
    double r = t * n, l = -r, b = -0.5, tp = 0.5;
    glFrustum(l, r, b, tp, n, f);

    if (getenv("TEST_MATRIX")) {
        GLdouble projection[16], stretch[16] = {2,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
        glGetDoublev(GL_PROJECTION_MATRIX, projection);
        projection[0] /= 2;
        glLoadMatrixd(projection);
        glMultMatrixd(stretch);
        glPushMatrix(); glLoadIdentity(); glPopMatrix();
    }
    if (getenv("TEST_ORTHO")) {
        glLoadIdentity(); glOrtho(-1, 1, -2, 2, 1, 100);
    }
    if (getenv("TEST_TEXTURE")) {
        unsigned char pixels[8*8*3];
        for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x)
            for (int c = 0; c < 3; ++c) pixels[(y*8+x)*3+c] = ((x+y)%2) ? 255 : 96;
        GLuint tex; glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 8, 8, 0, GL_RGB, GL_UNSIGNED_BYTE, pixels);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glEnable(GL_TEXTURE_2D);
    }
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    (void)n;

    glColor3f(1, 0, 0);
    glBegin(GL_QUADS);
    glTexCoord2f(0, 0);
    glVertex3f(-0.2f,  0.6f, -n * 5.0f / 2.0f);
    glTexCoord2f(1, 0);
    glVertex3f( 0.2f,  0.6f, -n * 5.0f / 2.0f);
    glTexCoord2f(1, 1);
    glVertex3f( 0.2f,  0.2f, -n * 5.0f / 2.0f);
    glTexCoord2f(0, 1);
    glVertex3f(-0.2f,  0.2f, -n * 5.0f / 2.0f);
    glEnd();

    glColor3f(0, 1, 0);
    glBegin(GL_QUADS);
    glTexCoord2f(0, 0);
    glVertex3f(-0.2f,  0.1f, -n * 5.0f);
    glTexCoord2f(1, 0);
    glVertex3f( 0.2f,  0.1f, -n * 5.0f);
    glTexCoord2f(1, 1);
    glVertex3f( 0.2f, -0.3f, -n * 5.0f);
    glTexCoord2f(0, 1);
    glVertex3f(-0.2f, -0.3f, -n * 5.0f);
    glEnd();

    glColor3f(0, 0, 1);
    glBegin(GL_QUADS);
    glTexCoord2f(0, 0);
    glVertex3f(-0.2f, -1.2f, -n * 5.0f * 2.0f);
    glTexCoord2f(1, 0);
    glVertex3f( 0.2f, -1.2f, -n * 5.0f * 2.0f);
    glTexCoord2f(1, 1);
    glVertex3f( 0.2f, -1.6f, -n * 5.0f * 2.0f);
    glTexCoord2f(0, 1);
    glVertex3f(-0.2f, -1.6f, -n * 5.0f * 2.0f);
    glEnd();

    GLenum error = glGetError();
    if (error) { fprintf(stderr, "GL error: %x\n", error); return 4; }
    if (argc > 1) {
        unsigned char pixels[640*360*3];
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadBuffer(GL_BACK);
        glReadPixels(0, 0, 640, 360, GL_RGB, GL_UNSIGNED_BYTE, pixels);
        FILE *fp = fopen(argv[1], "wb");
        if (!fp) return 5;
        fprintf(fp, "P6\n640 360\n255\n");
        for (int y = 359; y >= 0; --y) fwrite(pixels+y*640*3, 1, 640*3, fp);
        fclose(fp);
    }
    glXSwapBuffers(dpy, w);
    glXWaitGL();
    }

    glXMakeCurrent(dpy, None, NULL);
    glXDestroyContext(dpy, ctx);
    XDestroyWindow(dpy, w);
    XCloseDisplay(dpy);
    return 0;
}
