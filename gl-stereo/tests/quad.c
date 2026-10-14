/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xatom.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void property(Display *d, Window w, const char *name, unsigned long a, unsigned long b, unsigned long length)
{
    Atom type; int format; unsigned long count, remaining; unsigned char *data = NULL;
    assert(XGetWindowProperty(d,w,XInternAtom(d,name,False),0,2,False,XA_CARDINAL,&type,&format,&count,&remaining,&data) == Success);
    assert(type == XA_CARDINAL && format == 32 && count == length && !remaining);
    assert(((unsigned long *)data)[0] == a);
    if (length == 2) assert(((unsigned long *)data)[1] == b);
    XFree(data);
}
int main(int argc, char **argv)
{
    Display *d = XOpenDisplay(NULL); assert(d);
    int screen = DefaultScreen(d);
    unsigned long version = 1;
    if (getenv("TEST_SUPPORT_VERSION")) version = strtoul(getenv("TEST_SUPPORT_VERSION"),NULL,10);
    Atom supported = XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT_SUPPORTED",False);
    int absent = argc > 1 && !strcmp(argv[1],"unsupported");
    int automatic = argc > 1 && !strcmp(argv[1],"auto");
    int preset_class = getenv("TEST_PRESET_CLASS") != NULL;
    if (absent) XDeleteProperty(d,DefaultRootWindow(d),supported);
    else XChangeProperty(d,DefaultRootWindow(d),supported,XA_CARDINAL,32,PropModeReplace,(unsigned char *)&version,1);
    XSync(d,False);
    int attrs[] = {GLX_RGBA,GLX_DOUBLEBUFFER,GLX_DEPTH_SIZE,24,GLX_STEREO,None};
    if (argc > 1 && !strcmp(argv[1],"minimum-depth")) attrs[3] = 1;
    if (automatic) attrs[4] = None;
    XVisualInfo *v = glXChooseVisual(d,screen,attrs);
    if (absent) { assert(!v); puts("PASS: no stereo visual without compositor support"); return 0; }
    assert(v);
    int stereo = 0; assert(!glXGetConfig(d,v,GLX_STEREO,&stereo) && stereo == !automatic);
    GLXFBConfig *configs = NULL;
    if (argc > 1 && !strcmp(argv[1],"fbconfig")) {
        XFree(v);
        int count;
        int fbattrs[] = {GLX_RENDER_TYPE,GLX_RGBA_BIT,GLX_DRAWABLE_TYPE,GLX_WINDOW_BIT,GLX_DOUBLEBUFFER,True,GLX_DEPTH_SIZE,24,GLX_STEREO,True,None};
        configs = glXChooseFBConfig(d,screen,fbattrs,&count);
        assert(configs && count);
        assert(!glXGetFBConfigAttrib(d,configs[0],GLX_STEREO,&stereo) && stereo);
        v = glXGetVisualFromFBConfig(d,configs[0]); assert(v);
        int all_count; GLXFBConfig *all = glXGetFBConfigs(d,screen,&all_count);
        int stereo_count = 0, mono_count = 0;
        for (int i = 0; i < all_count; ++i) {
            assert(!glXGetFBConfigAttrib(d,all[i],GLX_STEREO,&stereo));
            if (stereo) ++stereo_count; else ++mono_count;
        }
        assert(stereo_count && mono_count); XFree(all);
    }
    XSetWindowAttributes a = {0};
    a.colormap = XCreateColormap(d,DefaultRootWindow(d),v->visual,AllocNone);
    Window w = XCreateWindow(d,DefaultRootWindow(d),0,0,320,200,0,v->depth,InputOutput,v->visual,CWColormap,&a);
    Atom class_atom = XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT_CLASS",False);
    if (preset_class) {
        unsigned long kind[] = {4,2};
        XChangeProperty(d,w,class_atom,XA_CARDINAL,32,PropModeReplace,(unsigned char *)kind,2);
    }
    XMapWindow(d,w);
    XSelectInput(d,w,PropertyChangeMask);
    GLXContext c = configs ? glXCreateNewContext(d,configs[0],GLX_RGBA_TYPE,NULL,True) : glXCreateContext(d,v,NULL,True);
    assert(c && glXMakeCurrent(d,w,c));
    GLint depth_bits; glGetIntegerv(GL_DEPTH_BITS,&depth_bits); assert(depth_bits >= attrs[3]);
    GLboolean double_buffer; glGetBooleanv(GL_DOUBLEBUFFER,&double_buffer); assert(double_buffer);
    XFree(v); if (configs) XFree(configs);
    GLboolean enabled; glGetBooleanv(GL_STEREO,&enabled); assert(enabled == !automatic);
    int expected_width = 320, expected_height = 200;
    const char *size = getenv("GL_STEREO_RENDER_RESOLUTION");
    if (size) assert(sscanf(size,"%dx%d",&expected_width,&expected_height) == 2);
    XWindowAttributes geometry;
    Display *observer = XOpenDisplay(NULL); assert(observer);
    XGetWindowAttributes(observer,w,&geometry); assert(geometry.width == 2*expected_width && geometry.height == expected_height);
    property(observer,w,"_KDE_NET_WM_STEREO_CONTENT",3,0,1);
    if (preset_class) property(observer,w,"_KDE_NET_WM_STEREO_CONTENT_CLASS",4,2,2);
    else {
        Atom type; int format; unsigned long count, remaining; unsigned char *data = NULL;
        assert(XGetWindowProperty(observer,w,class_atom,0,2,False,AnyPropertyType,
                                  &type,&format,&count,&remaining,&data) == Success);
        assert(type == None && count == 0);
        if (data) XFree(data);
    }
    assert(glXMakeCurrent(d,w,c));
    XSync(d,False);
    XEvent event; unsigned declarations = 0;
    Atom layout_atom = XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT",False);
    while (XCheckWindowEvent(d,w,PropertyChangeMask,&event)) {
        assert(event.xproperty.atom != class_atom);
        if (event.xproperty.atom == layout_atom) ++declarations;
    }
    assert(declarations == 1);
    Window menu = XCreateSimpleWindow(d,DefaultRootWindow(d),0,0,64,48,0,0,0);
    XSync(d,False); XGetWindowAttributes(observer,menu,&geometry);
    assert(geometry.width == 64 && geometry.height == 48);
    XDestroyWindow(d,menu);
    glViewport(0,0,320,200);
    if (automatic) {
        glClearColor(0,0,0,1); glClear(GL_COLOR_BUFFER_BIT);
    }
    for (int eye = 0; !automatic && eye < 2; ++eye) {
        glDrawBuffer(eye ? GL_BACK_RIGHT : GL_BACK_LEFT);
        GLint buffer; glGetIntegerv(GL_DRAW_BUFFER,&buffer); assert(buffer == (eye ? GL_BACK_RIGHT : GL_BACK_LEFT));
        glClearColor(!eye,eye,eye,1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glEnable(GL_SCISSOR_TEST); glScissor(120,70,80,60);
        glClearColor(eye,eye,!eye,1); glClear(GL_COLOR_BUFFER_BIT);
        glDisable(GL_SCISSOR_TEST);
    }
    for (int eye = 0; !automatic && eye < 2; ++eye) {
        glReadBuffer(eye ? GL_BACK_RIGHT : GL_BACK_LEFT);
        unsigned char pixel[4] = {0};
        glReadPixels(10,10,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
        assert(pixel[0] == (eye ? 0 : 255));
        assert(pixel[1] == (eye ? 255 : 0));
        assert(pixel[2] == (eye ? 255 : 0));
    }
    assert(glGetError() == GL_NO_ERROR);
    glXSwapBuffers(d,w);
    glXMakeCurrent(d,None,NULL); glXDestroyContext(d,c);
    XDestroyWindow(d,w); XCloseDisplay(observer); XCloseDisplay(d);
    printf("PASS: %s selection, queries, geometry and full-SBS-only declaration%s\n",
           automatic ? "automatic" : "native stereo",
           automatic ? "" : ", independent buffers");
    return 0;
}
