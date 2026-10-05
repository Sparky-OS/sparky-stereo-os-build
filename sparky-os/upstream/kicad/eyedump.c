/* Test shim (never part of the KiCad patch): at glXSwapBuffers, read the left and right back buffers of a
 * stereo drawable and write them as PPM files, so the two eyes can be compared without any compositor.
 * EYEDUMP_DIR = output directory; EYEDUMP_FRAME = first swap (then every third; the last dump stays) of the largest drawable to dump (default 40).
 * EYEDUMP_FINISH=1 calls glFinish() before reading (Mesa packing note). */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <GL/gl.h>
#include <GL/glx.h>

__attribute__((constructor)) static void hello(void){ fprintf(stderr, "eyedump: loaded\n"); }
static void dump(const char* aName, GLenum aBuf, int w, int h, int aStereo)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s.ppm", getenv("EYEDUMP_DIR") ? getenv("EYEDUMP_DIR") : ".", aName);
    unsigned char* px = malloc((size_t) w * h * 3);
    GLint oldRead; glGetIntegerv(GL_READ_BUFFER, &oldRead);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadBuffer(aBuf);
    glReadPixels(0, 0, w, h, GL_RGB, GL_UNSIGNED_BYTE, px);
    GLenum err = glGetError();
    glReadBuffer(oldRead);
    FILE* f = fopen(path, "wb");
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for(int y = h - 1; y >= 0; --y) fwrite(px + (size_t) y * w * 3, 3, w, f);
    fclose(f); free(px);
    fprintf(stderr, "eyedump: %s %dx%d stereo=%d glerror=0x%x\n", path, w, h, aStereo, err);
}

void glXSwapBuffers(Display* dpy, GLXDrawable d)
{
    static void (*real)(Display*, GLXDrawable);
    static int frames; static unsigned best;
    if(!real) real = dlsym(RTLD_NEXT, "glXSwapBuffers");
    unsigned w = 0, h = 0;
    glXQueryDrawable(dpy, d, GLX_WIDTH, &w); glXQueryDrawable(dpy, d, GLX_HEIGHT, &h);
    if(getenv("EYEDUMP_TRACE")) fprintf(stderr, "eyedump: swap %ux%u\n", w, h);
    int target = getenv("EYEDUMP_FRAME") ? atoi(getenv("EYEDUMP_FRAME")) : 40;
    if(w * h > 300000)
    {
        best = w * h;
        if(++frames >= target && frames % 3 == 0)
        {
            GLboolean st = GL_FALSE; glGetBooleanv(GL_STEREO, &st);
            if(getenv("EYEDUMP_FINISH") && *getenv("EYEDUMP_FINISH")) glFinish();
            if(st) { dump("left", GL_BACK_LEFT, w, h, 1); dump("right", GL_BACK_RIGHT, w, h, 1); }
            else dump("mono", GL_BACK, w, h, 0);
        }
    }
    if(getenv("EYEDUMP_FINISH") && *getenv("EYEDUMP_FINISH")) glFinish();
    real(dpy, d);
}
