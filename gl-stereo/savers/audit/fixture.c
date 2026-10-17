/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <EGL/egl.h>
#include <X11/Xlib.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static void *lookup_next(const char *name)
{
    void *(*lookup)(void *, const char *) = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    return lookup(RTLD_NEXT, name);
}

/* Test input only: keep the hack's seed and clock repeatable while leaving
 * Xlib, Mesa and the compositor on their normal clocks and process IDs. */
static int hack_caller(void *caller)
{
    if (getenv("AUDIT_REAL_TIME")) return 0;
    Dl_info info;
    return dladdr(caller, &info) && info.dli_fname &&
           strstr(info.dli_fname, "/xscreensaver/");
}
static unsigned ticks;
int gettimeofday(struct timeval *tv, void *tz)
{
    static int (*next)(struct timeval *, void *);
    if (!next) next = lookup_next("gettimeofday");
    if (!hack_caller(__builtin_return_address(0))) return next(tv, tz);
    unsigned tick = ticks++;
    tv->tv_sec = 1700000000 + tick / 60;
    tv->tv_usec = (tick % 60) * 16666;
    return 0;
}
time_t time(time_t *out)
{
    static time_t (*next)(time_t *);
    if (!next) next = lookup_next("time");
    if (!hack_caller(__builtin_return_address(0))) return next(out);
    time_t value = 1700000000 + ticks++ / 60;
    if (out) *out = value;
    return value;
}
pid_t getpid(void)
{
    static pid_t (*next)(void);
    if (!next) next = lookup_next("getpid");
    return hack_caller(__builtin_return_address(0)) ? 12345 : next();
}
static int capture(int width, int height)
{
    static unsigned frame;
    unsigned target = getenv("AUDIT_FRAME") ? atoi(getenv("AUDIT_FRAME")) : 120;
    int selected = ++frame == target;
    const char *path = getenv("AUDIT_CAPTURE");
    if (selected && path) {
        unsigned char *pixels = malloc((size_t)width * height * 3);
        GLboolean double_buffer;
        glGetBooleanv(GL_DOUBLEBUFFER, &double_buffer);
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadBuffer(double_buffer ? GL_BACK : GL_FRONT);
        glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels);
        FILE *out = fopen(path, "wb");
        if (!out) abort();
        fprintf(out, "P6\n%d %d\n255\n", width, height);
        for (int y = height - 1; y >= 0; --y)
            fwrite(pixels + (size_t)y*width*3, 3, width, out);
        fclose(out);
        free(pixels);
    }
    return selected;
}
static GLuint probe_renderbuffer;
static void prepare_state(int selected)
{
    if (!selected || !getenv("AUDIT_VALIDATE_STATE")) return;
    glGenRenderbuffers(1,&probe_renderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER,probe_renderbuffer);
    glReadBuffer(GL_FRONT);
    glEnable(GL_SCISSOR_TEST); glScissor(7,9,23,25);
    glEnable(GL_FRAMEBUFFER_SRGB);
}
static void stopped_frame(int selected)
{
    if (selected) {
        if (getenv("AUDIT_VALIDATE_STATE")) {
            GLint read,draw,renderbuffer,buffer,scissor[4];
            glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read);
            glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw);
            glGetIntegerv(GL_RENDERBUFFER_BINDING,&renderbuffer);
            glGetIntegerv(GL_READ_BUFFER,&buffer); glGetIntegerv(GL_SCISSOR_BOX,scissor);
            if (read || draw || renderbuffer!=(GLint)probe_renderbuffer || buffer!=GL_FRONT ||
                !glIsEnabled(GL_SCISSOR_TEST) || !glIsEnabled(GL_FRAMEBUFFER_SRGB) ||
                scissor[0]!=7 || scissor[1]!=9 || scissor[2]!=23 || scissor[3]!=25 || glGetError()) abort();
            fprintf(stderr,"PASS: readback restores framebuffer, renderbuffer, read buffer, scissor and sRGB state\n");
        }
        const char *ready = getenv("AUDIT_READY");
        GLint samples=0, double_buffer=0;
        glGetIntegerv(GL_SAMPLES,&samples); glGetIntegerv(GL_DOUBLEBUFFER,&double_buffer);
        if (ready) { FILE *out = fopen(ready, "w"); if (!out) abort(); fprintf(out,"{\"clock_queries\":%u,\"samples\":%d,\"double_buffer\":%d}\n",ticks,samples,double_buffer); fclose(out); }
        raise(SIGSTOP);
    }
}
void glXSwapBuffers(Display *display, GLXDrawable drawable)
{
    static void (*next)(Display *, GLXDrawable);
    if (!next) next = lookup_next("glXSwapBuffers");
    XWindowAttributes a;
    XGetWindowAttributes(display, drawable, &a);
    int selected = capture(a.width, a.height);
    prepare_state(selected);
    next(display, drawable);
    stopped_frame(selected);
}
EGLBoolean eglSwapBuffers(EGLDisplay display, EGLSurface surface)
{
    static EGLBoolean (*next)(EGLDisplay, EGLSurface);
    if (!next) next = lookup_next("eglSwapBuffers");
    EGLint width, height;
    eglQuerySurface(display, surface, EGL_WIDTH, &width);
    eglQuerySurface(display, surface, EGL_HEIGHT, &height);
    int selected = capture(width, height);
    prepare_state(selected);
    EGLBoolean result = next(display, surface);
    stopped_frame(selected);
    return result;
}
/* A stereo capture is of frames drawn after the compositor sized the window for both
 * views. With AUDIT_STEREO_WIDTH set (the window's width once the compositor has sized it),
 * the first make-current of each window waits, after the layer has declared the window, until
 * the X server reports that width. The saver draws nothing before, so its frame count and
 * clock start at the same point however late the compositor answers. */
static struct { EGLSurface surface; Window window; } surfaces[16];
static Window waited[16];
static void remember_surface(EGLSurface surface, Window window)
{
    for (unsigned i = 0; i < sizeof(surfaces)/sizeof(*surfaces); ++i)
        if (!surfaces[i].surface || surfaces[i].surface == surface) { surfaces[i].surface = surface; surfaces[i].window = window; return; }
}
static void wait_for_stereo_width(Window window)
{
    const char *target = getenv("AUDIT_STEREO_WIDTH");
    if (!target || !window) return;
    unsigned slot = 0;
    for (; slot < sizeof(waited)/sizeof(*waited) && waited[slot]; ++slot)
        if (waited[slot] == window) return;
    if (slot < sizeof(waited)/sizeof(*waited)) waited[slot] = window;
    /* the X server's own answer, not the layer's per-view size */
    static Display *display;
    static Status (*attributes)(Display *, Window, XWindowAttributes *);
    if (!display) {
        void *x11 = dlopen("libX11.so.6", RTLD_NOW);
        Display *(*open)(const char *) = x11 ? (Display *(*)(const char *))dlsym(x11, "XOpenDisplay") : NULL;
        attributes = x11 ? (Status (*)(Display *, Window, XWindowAttributes *))dlsym(x11, "XGetWindowAttributes") : NULL;
        display = open && attributes ? open(NULL) : NULL;
        if (!display) abort();
    }
    int width = atoi(target), seconds = getenv("AUDIT_STEREO_WAIT") ? atoi(getenv("AUDIT_STEREO_WAIT")) : 120;
    struct timespec start, now; clock_gettime(CLOCK_MONOTONIC, &start);
    XWindowAttributes a = {0};
    for (;;) {
        if (!attributes(display, window, &a)) return;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double elapsed = (now.tv_sec - start.tv_sec) + (now.tv_nsec - start.tv_nsec) / 1e9;
        if (a.width == width || elapsed > seconds) {
            fprintf(stderr, "fixture: window %lu %d wide after %.3f s (stereo width %d)\n", window, a.width, elapsed, width);
            return;
        }
        usleep(10000);
    }
}
EGLSurface eglCreateWindowSurface(EGLDisplay display, EGLConfig config, EGLNativeWindowType window, const EGLint *attributes)
{
    static EGLSurface (*next)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *);
    if (!next) next = lookup_next("eglCreateWindowSurface");
    EGLSurface surface = next(display, config, window, attributes);
    if (surface != EGL_NO_SURFACE) remember_surface(surface, (Window)window);
    return surface;
}
EGLSurface eglCreatePlatformWindowSurface(EGLDisplay display, EGLConfig config, void *window, const EGLAttrib *attributes)
{
    static EGLSurface (*next)(EGLDisplay, EGLConfig, void *, const EGLAttrib *);
    if (!next) next = lookup_next("eglCreatePlatformWindowSurface");
    EGLSurface surface = next(display, config, window, attributes);
    if (surface != EGL_NO_SURFACE && window) remember_surface(surface, *(Window *)window);
    return surface;
}
EGLSurface eglCreatePlatformWindowSurfaceEXT(EGLDisplay display, EGLConfig config, void *window, const EGLint *attributes)
{
    static EGLSurface (*next)(EGLDisplay, EGLConfig, void *, const EGLint *);
    if (!next) next = lookup_next("eglCreatePlatformWindowSurfaceEXT");
    EGLSurface surface = next(display, config, window, attributes);
    if (surface != EGL_NO_SURFACE && window) remember_surface(surface, *(Window *)window);
    return surface;
}
EGLBoolean eglMakeCurrent(EGLDisplay display, EGLSurface draw, EGLSurface read, EGLContext context)
{
    static EGLBoolean (*next)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
    if (!next) next = lookup_next("eglMakeCurrent");
    EGLBoolean result = next(display, draw, read, context);
    if (result && draw != EGL_NO_SURFACE)
        for (unsigned i = 0; i < sizeof(surfaces)/sizeof(*surfaces); ++i)
            if (surfaces[i].surface == draw) { wait_for_stereo_width(surfaces[i].window); break; }
    return result;
}
Bool glXMakeCurrent(Display *display, GLXDrawable drawable, GLXContext context)
{
    static Bool (*next)(Display *, GLXDrawable, GLXContext);
    if (!next) next = lookup_next("glXMakeCurrent");
    Bool result = next(display, drawable, context);
    if (result && drawable) wait_for_stereo_width(drawable);
    return result;
}
Bool glXMakeContextCurrent(Display *display, GLXDrawable draw, GLXDrawable read, GLXContext context)
{
    static Bool (*next)(Display *, GLXDrawable, GLXDrawable, GLXContext);
    if (!next) next = lookup_next("glXMakeContextCurrent");
    Bool result = next(display, draw, read, context);
    if (result && draw) wait_for_stereo_width(draw);
    return result;
}

/* Optional inspection of the application's camera texture before postprocessing. */
void glCopyTexImage2D(GLenum target,GLint level,GLenum format,GLint x,GLint y,GLsizei width,GLsizei height,GLint border)
{
    static void (*next)(GLenum,GLint,GLenum,GLint,GLint,GLsizei,GLsizei,GLint);
    static unsigned copies;
    if (!next) next=lookup_next("glCopyTexImage2D");
    next(target,level,format,x,y,width,height,border);
    const char *path=getenv("AUDIT_TEXTURE");
    unsigned frame=getenv("AUDIT_FRAME") ? atoi(getenv("AUDIT_FRAME")) : 120;
    if (++copies!=frame || !path || target!=GL_TEXTURE_2D) return;
    unsigned char *pixels=malloc((size_t)width*height*3);
    glPixelStorei(GL_PACK_ALIGNMENT,1);
    glGetTexImage(target,level,GL_RGB,GL_UNSIGNED_BYTE,pixels);
    FILE *out=fopen(path,"wb");if (!out) abort();
    fprintf(out,"P6\n%d %d\n255\n",width,height);
    for (int row=height-1;row>=0;row--) fwrite(pixels+(size_t)row*width*3,3,width,out);
    fclose(out);free(pixels);
}

/* Give asynchronous text savers identical bytes, available at the same point
 * in both runs. This is an explicit test input, never a shipped saver option. */
static FILE *text_input;
FILE *popen(const char *command,const char *mode)
{
    static FILE *(*real)(const char *,const char *);
    if (!real) real=lookup_next("popen");
    const char *path=getenv("AUDIT_TEXT");
    if (path && !text_input && !strcmp(mode,"r") && strstr(command,"xscreensaver-text")) {
        text_input=fopen(path,"r");
        if (!text_input) abort();
        return text_input;
    }
    return real(command,mode);
}
int pclose(FILE *stream)
{
    static int (*real)(FILE *);
    if (!real) real=lookup_next("pclose");
    if (stream==text_input) {text_input=NULL;return fclose(stream);}
    return real(stream);
}
