#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <execinfo.h>
#include <unistd.h>
static void desc(EGLDisplay d, EGLConfig c, const char *what)
{
    EGLint r = -1, a = -1, f = -1, id = -1;
    eglGetConfigAttrib(d, c, EGL_RED_SIZE, &r); eglGetConfigAttrib(d, c, EGL_ALPHA_SIZE, &a); eglGetConfigAttrib(d, c, EGL_CONFIG_ID, &id);
    eglGetConfigAttrib(d, c, EGL_COLOR_COMPONENT_TYPE_EXT, &f);
    fprintf(stderr, "eglspy2: %s config id %d: %d bits, alpha %d, float %d\n", what, id, r, a, f == EGL_COLOR_COMPONENT_TYPE_FLOAT_EXT);
}
EGLSurface eglCreateWindowSurface(EGLDisplay d, EGLConfig c, EGLNativeWindowType w, const EGLint *attr)
{
    static EGLSurface (*real)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *);
    if (!real) real = dlsym(RTLD_NEXT, "eglCreateWindowSurface");
    desc(d, c, "eglCreateWindowSurface"); return real(d, c, w, attr);
}
EGLContext eglCreateContext(EGLDisplay d, EGLConfig c, EGLContext s, const EGLint *attr)
{
    static EGLContext (*real)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
    if (!real) real = dlsym(RTLD_NEXT, "eglCreateContext");
    desc(d, c, "eglCreateContext"); { EGLint a=-1; eglGetConfigAttrib(d, c, EGL_ALPHA_SIZE, &a); if (a==0) { void *bt[40]; int n=backtrace(bt,40); backtrace_symbols_fd(bt,n,2); fprintf(stderr,"--- end bt\n"); } } return real(d, c, s, attr);
}
