/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { WIDTH = 640, HEIGHT = 360, COUNT = 600 };
typedef struct { double x, y, z; } Star;
static Star stars[COUNT];
static uint32_t seed = 1;
static double random_unit(void)
{
    seed = seed * 1664525u + 1013904223u;
    return (seed >> 8) / 16777216.0;
}
static void spawn(Star *s, double z)
{
    double x, y;
    do { x = 2 * random_unit() - 1; y = 2 * random_unit() - 1; }
    while (fabs(x) < .4 && fabs(y) < .3);
    s->x = x * z * (WIDTH / (double)HEIGHT) * .5;
    s->y = y * z * .5;
    s->z = z;
}
static double brightness(double z)
{
    if (z <= 5) return 0;
    if (z >= 7) return 1;
    double t = (z - 5) / 2;
    return t * t * (3 - 2 * t);
}
int main(int argc, char **argv)
{
    int frames = 0, oracle = 0, reference = 0, fast = 0;
    const char *capture = NULL;
    double probe_depth = 6, oracle_x = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--oracle")) oracle = 1;
        else if (!strcmp(argv[i], "--fast")) fast = 1;
        else if (!strcmp(argv[i], "--frames") && ++i < argc) frames = atoi(argv[i]);
        else if (!strcmp(argv[i], "--seed") && ++i < argc) seed = strtoul(argv[i], NULL, 10);
        else if (!strcmp(argv[i], "--reference-left")) reference = -1;
        else if (!strcmp(argv[i], "--reference-right")) reference = 1;
        else if (!strcmp(argv[i], "--capture") && ++i < argc) capture = argv[i];
        else if (!strcmp(argv[i], "--oracle-x") && ++i < argc) oracle_x = atof(argv[i]);
        else if (!strcmp(argv[i], "--probe-depth") && ++i < argc) probe_depth = atof(argv[i]);
        else { fprintf(stderr, "invalid argument\n"); return 2; }
    }
    if (!isfinite(oracle_x) || fabs(oracle_x) > .8 || frames < 0 || frames > 100000 || !isfinite(probe_depth) || probe_depth < 5 || probe_depth > 80) return 2;
    Display *d = XOpenDisplay(NULL);
    if (!d) return 3;
    int attrs[] = {GLX_RGBA, GLX_DOUBLEBUFFER, GLX_DEPTH_SIZE, 24, GLX_STEREO, None};
    if (reference) attrs[4] = None;
    XVisualInfo *v = glXChooseVisual(d, DefaultScreen(d), attrs);
    if (!v) { fputs("starfield requires stereo GLX support\n", stderr); return 4; }
    XSetWindowAttributes a = {0};
    a.colormap = XCreateColormap(d, DefaultRootWindow(d), v->visual, AllocNone);
    Window w = XCreateWindow(d, DefaultRootWindow(d), 0, 0, WIDTH, HEIGHT,
                            0, v->depth, InputOutput, v->visual, CWColormap, &a);
    XStoreName(d, w, "Stereo starfield"); XMapWindow(d, w);
    GLXContext c = glXCreateContext(d, v, NULL, True);
    XFree(v);
    if (!c || !glXMakeCurrent(d, w, c)) return 5;
    glXWaitX();
    for (int i = 0; i < COUNT; ++i) spawn(&stars[i], 7 + random_unit() * 73);
    const double r = WIDTH / (double)HEIGHT * .5;
    const double convergence = 5, separation = 2 * .01 * convergence * r;
    unsigned updates = 0;
    for (int frame = 0; !frames || frame < frames; ++frame) {
        if (!oracle) {
            for (int i = 0; i < COUNT; ++i) {
                stars[i].z -= .1;
                if (stars[i].z <= 5) spawn(&stars[i], 80);
            }
            ++updates;
        }
        for (int eye = -1; eye <= 1; eye += 2) {
            if (reference && eye != reference) continue;
            glDrawBuffer(reference ? GL_BACK : eye < 0 ? GL_BACK_LEFT : GL_BACK_RIGHT);
            glViewport(0, 0, WIDTH, HEIGHT);
            glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glMatrixMode(GL_PROJECTION); glLoadIdentity();
            double shift = -eye * separation / (2 * convergence);
            glFrustum(-r + shift, r + shift, -.5, .5, 1, 100);
            glMatrixMode(GL_MODELVIEW); glLoadIdentity();
            glTranslated(-eye * separation / 2, 0, 0);
            glPointSize(oracle ? 7 : 2);
            glBegin(GL_POINTS);
            if (oracle) {
                const double depths[] = {probe_depth, 10, 20, 5};
                for (int i = 0; i < 4; ++i) {
                    double b = brightness(depths[i]);
                    glColor3d(i == 0 || i == 3 ? b : 0, i == 1 || i == 3 ? b : 0, i == 2 || i == 3 ? b : 0);
                    glVertex3d(oracle_x * r * depths[i], (.3 - .2 * i) * depths[i], -depths[i]);
                }
            } else {
                for (int i = 0; i < COUNT; ++i) {
                    double b = brightness(stars[i].z);
                    glColor3d(b, b, b);
                    glVertex3d(stars[i].x, stars[i].y, -stars[i].z);
                }
            }
            glEnd();
        }
        if (glGetError() != GL_NO_ERROR) return 6;
        if (capture && frame == frames - 1) {
            unsigned char *pixels = malloc(WIDTH * HEIGHT * 3);
            if (!pixels) return 7;
            glReadBuffer(reference ? GL_BACK : GL_BACK_LEFT);
            glPixelStorei(GL_PACK_ALIGNMENT, 1);
            glReadPixels(0, 0, WIDTH, HEIGHT, GL_RGB, GL_UNSIGNED_BYTE, pixels);
            FILE *file = fopen(capture, "wb");
            if (!file) return 7;
            fprintf(file, "P6\n%d %d\n255\n", WIDTH, HEIGHT);
            for (int y = HEIGHT - 1; y >= 0; --y) fwrite(pixels + y * WIDTH * 3, 1, WIDTH * 3, file);
            fclose(file); free(pixels);
        }
        glXSwapBuffers(d, w);
        if (!fast) { struct timespec delay = {0, 16666667}; nanosleep(&delay, NULL); }
    }
    printf("starfield: frames=%d world_updates=%u\n", frames, updates);
    glXMakeCurrent(d, None, NULL); glXDestroyContext(d, c);
    XDestroyWindow(d, w); XCloseDisplay(d);
    return 0;
}
