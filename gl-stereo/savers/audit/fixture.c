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
