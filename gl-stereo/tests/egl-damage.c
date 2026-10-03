/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void)
{
    Display *d = XOpenDisplay(NULL); assert(d);
    EGLDisplay display = eglGetDisplay((EGLNativeDisplayType)d);
    assert(eglInitialize(display,NULL,NULL)); assert(eglBindAPI(EGL_OPENGL_API));
    EGLint attrs[] = {EGL_SURFACE_TYPE,EGL_WINDOW_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_NONE};
    EGLConfig cfg; EGLint count;
    assert(eglChooseConfig(display,attrs,&cfg,1,&count) && count);
    EGLint visual; assert(eglGetConfigAttrib(display,cfg,EGL_NATIVE_VISUAL_ID,&visual));
    XVisualInfo request = {0}; request.visualid = visual;
    int n; XVisualInfo *vi = XGetVisualInfo(d,VisualIDMask,&request,&n); assert(vi);
    XSetWindowAttributes a = {0};
    a.colormap = XCreateColormap(d,DefaultRootWindow(d),vi->visual,AllocNone);
    Window w = XCreateWindow(d,DefaultRootWindow(d),0,0,160,100,0,vi->depth,InputOutput,vi->visual,CWColormap,&a);
    XMapWindow(d,w); XSync(d,False);
    EGLSurface surface = eglCreateWindowSurface(display,cfg,(EGLNativeWindowType)w,NULL);
    EGLContext context = eglCreateContext(display,cfg,EGL_NO_CONTEXT,NULL);
    assert(context && surface && eglMakeCurrent(display,surface,surface,context));
    EGLint width; assert(eglQuerySurface(display,surface,EGL_WIDTH,&width) && width == 160);
    const char *extensions = eglQueryString(display,EGL_EXTENSIONS);
    const char *names[] = {"eglSwapBuffersWithDamageKHR","eglSwapBuffersWithDamageEXT"};
    const char *extension_names[] = {"EGL_KHR_swap_buffers_with_damage","EGL_EXT_swap_buffers_with_damage"};
    for (int frame = 0; frame < 2; ++frame) {
        assert(strstr(extensions,extension_names[frame]));
        glViewport(0,0,160,100); glClearColor(0,0,0,1); glClear(GL_COLOR_BUFFER_BIT);
        glMatrixMode(GL_PROJECTION); glLoadIdentity(); glMatrixMode(GL_MODELVIEW); glLoadIdentity();
        glColor3f(1,0,0); glRectf(-.5,-.5,.5,.5);
        assert(glGetError() == GL_NO_ERROR);
        PFNEGLSWAPBUFFERSWITHDAMAGEKHRPROC swap = (PFNEGLSWAPBUFFERSWITHDAMAGEKHRPROC)eglGetProcAddress(names[frame]);
        EGLint damage[] = {0,0,160,100};
        assert(swap && swap(display,surface,damage,1));
    }
    eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
    eglDestroyContext(display,context); eglDestroySurface(display,surface); eglTerminate(display);
    XDestroyWindow(d,w); XFree(vi); XCloseDisplay(d);
    puts("PASS: EGL desktop GL, logical surface size, KHR/EXT damage swaps");
}
