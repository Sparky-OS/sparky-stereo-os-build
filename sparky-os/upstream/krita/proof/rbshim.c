/* LD_PRELOAD readback shim. On every swap it reads the default framebuffer's back buffer at its real depth
 * (glReadPixels GL_RGBA/GL_UNSIGNED_SHORT: a 10-bit buffer gives up to 1024 levels, an 8-bit one 256) into memory;
 * a thread writes the newest frame to $RB_OUT.raw/.txt when /tmp/rb.trigger appears. Only windows above 100000 pixels. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <EGL/egl.h>
#include <GL/gl.h>
#include <GL/glx.h>
typedef void (*pfnReadPixels)(int, int, int, int, unsigned, unsigned, void *);
typedef void (*pfnBind)(unsigned, unsigned);
typedef void (*pfnGetInt)(unsigned, int *);
typedef void (*pfnReadBuf)(unsigned);
static const char *trig = "/tmp/rb.trigger";
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
#define NS 8
static struct { void *key; unsigned short *buf; int w, h, bits[4]; const char *api; unsigned long frames; } slot[NS];
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void *writer(void *arg)
{
    (void)arg;
    for (;;) {
        usleep(100000);
        if (access(trig, F_OK) != 0) continue;
        pthread_mutex_lock(&mu);
        {
            const char *name = getenv("RB_OUT") ? getenv("RB_OUT") : "/tmp/rb";
            for (int i = 0; i < NS; i++) {
                if (!slot[i].buf) continue;
                char fn[400]; snprintf(fn, sizeof fn, "%s.%d.raw", name, i);
                FILE *f = fopen(fn, "wb"); if (f) { fwrite(slot[i].buf, 8, (size_t)slot[i].w * slot[i].h, f); fclose(f); }
                snprintf(fn, sizeof fn, "%s.%d.txt", name, i);
                f = fopen(fn, "w"); if (f) { fprintf(f, "api=%s w=%d h=%d red=%d green=%d blue=%d alpha=%d frames=%lu\n", slot[i].api, slot[i].w, slot[i].h, slot[i].bits[0], slot[i].bits[1], slot[i].bits[2], slot[i].bits[3], slot[i].frames); fclose(f); }
            }
            unlink(trig);
        }
        pthread_mutex_unlock(&mu);
    }
    return 0;
}
static void start(void) { pthread_t t; pthread_create(&t, 0, writer, 0); }
static void grab(void *key, int w, int h, const char *api)
{
    if (w * h < 100000) return;
    pthread_once(&once, start);
    void *(*gpa)(const char *) = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "eglGetProcAddress");
    #define L(n) ((void *)(gpa ? gpa(n) : 0))
    pfnReadPixels rp = (pfnReadPixels)L("glReadPixels");
    pfnBind bind = (pfnBind)L("glBindFramebuffer");
    pfnGetInt gi = (pfnGetInt)L("glGetIntegerv");
    pfnReadBuf rb = (pfnReadBuf)L("glReadBuffer");
    if (!rp || !bind || !gi) return;
    int oldRead = 0, oldRB = 0, bits[4];
    gi(0x8CAA, &oldRead); gi(0x0C02, &oldRB);
    bind(0x8CA8, 0);
    if (rb) rb(GL_BACK);
    bits[0] = bits[1] = bits[2] = bits[3] = -1;
    typedef void (*pfnGetFBA)(unsigned, unsigned, unsigned, int *);
    pfnGetFBA gf = (pfnGetFBA)L("glGetFramebufferAttachmentParameteriv");
    if (gf) { gf(0x8CA8, GL_BACK, 0x8212, &bits[0]); gf(0x8CA8, GL_BACK, 0x8213, &bits[1]); gf(0x8CA8, GL_BACK, 0x8214, &bits[2]); gf(0x8CA8, GL_BACK, 0x8215, &bits[3]); }
    pthread_mutex_lock(&mu);
    int i = 0; while (i < NS - 1 && slot[i].key && slot[i].key != key) i++;
    if (!slot[i].buf || slot[i].w != w || slot[i].h != h) { free(slot[i].buf); slot[i].buf = malloc((size_t)w * h * 8); slot[i].w = w; slot[i].h = h; }
    slot[i].key = key;
    rp(0, 0, w, h, GL_RGBA, 0x1403, slot[i].buf);
    memcpy(slot[i].bits, bits, sizeof bits); slot[i].api = api; slot[i].frames++;
    pthread_mutex_unlock(&mu);
    bind(0x8CA8, (unsigned)oldRead);
    if (rb) rb((unsigned)oldRB);
}
EGLBoolean eglSwapBuffers(EGLDisplay d, EGLSurface s)
{
    static EGLBoolean (*real)(EGLDisplay, EGLSurface);
    if (!real) real = dlsym(RTLD_NEXT, "eglSwapBuffers");
    EGLint w = 0, h = 0; eglQuerySurface(d, s, EGL_WIDTH, &w); eglQuerySurface(d, s, EGL_HEIGHT, &h);
    grab(s, w, h, "egl");
    return real(d, s);
}
void glXSwapBuffers(Display *dpy, GLXDrawable drw)
{
    static void (*real)(Display *, GLXDrawable);
    if (!real) real = dlsym(RTLD_NEXT, "glXSwapBuffers");
    unsigned w = 0, h = 0; glXQueryDrawable(dpy, drw, GLX_WIDTH, &w); glXQueryDrawable(dpy, drw, GLX_HEIGHT, &h);
    grab((void *)drw, (int)w, (int)h, "glx");
    real(dpy, drw);
}
