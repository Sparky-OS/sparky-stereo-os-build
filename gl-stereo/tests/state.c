/* SPDX-License-Identifier: GPL-2.0-or-later */
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
typedef struct { Display *d; Window w; GLXContext c; int index; } View;
static void *exercise(void *arg)
{
    View *v = arg;
    assert(glXMakeCurrent(v->d,v->w,v->c));
    glViewport(10,20,30,40);
    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    glFrustum(-1,1,-1,1,1+v->index,100);
    double expected[16]; glGetDoublev(GL_PROJECTION_MATRIX,expected);
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    for (int frame = 0; frame < 20; ++frame) {
        glDisable(GL_SCISSOR_TEST);
        glClearColor(1,0,0,1); glClear(GL_COLOR_BUFFER_BIT);
        glScissor(5,7,11,13); glEnable(GL_SCISSOR_TEST);
        glClearColor(0,0,1,1); glClear(GL_COLOR_BUFFER_BIT);
        GLint box[4], vp[4];
        glGetIntegerv(GL_VIEWPORT,vp); glGetIntegerv(GL_SCISSOR_BOX,box);
        assert(vp[0] == 10 && vp[1] == 20 && vp[2] == 30 && vp[3] == 40);
        assert(box[0] == 5 && box[1] == 7 && box[2] == 11 && box[3] == 13);
        assert(glIsEnabled(GL_SCISSOR_TEST));
        double actual[16]; glGetDoublev(GL_PROJECTION_MATRIX,actual);
        assert(!memcmp(actual,expected,sizeof(actual)));
    }
    unsigned char pixels[320*100*3];
    glReadBuffer(GL_BACK); glPixelStorei(GL_PACK_ALIGNMENT,1);
    glReadPixels(0,0,320,100,GL_RGB,GL_UNSIGNED_BYTE,pixels);
    for (int y = 0; y < 100; ++y) for (int x = 0; x < 320; ++x) {
        int logical = x % 160;
        int blue = logical >= 5 && logical < 16 && y >= 7 && y < 20;
        unsigned char *p = pixels+(y*320+x)*3;
        assert(p[0] == (blue ? 0 : 255) && p[1] == 0 && p[2] == (blue ? 255 : 0));
    }
    glDisable(GL_SCISSOR_TEST);
    GLuint fbo, tex;
    glGenFramebuffers(1,&fbo); glBindFramebuffer(GL_FRAMEBUFFER,fbo);
    glGenTextures(1,&tex); glBindTexture(GL_TEXTURE_2D,tex);
    glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,16,16,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
    glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);
    assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    glViewport(0,0,16,16); glClearColor(0,0,0,0); glClear(GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION); glLoadIdentity(); glMatrixMode(GL_MODELVIEW);
    glEnable(GL_BLEND); glBlendFunc(GL_ONE,GL_ONE); glColor4f(.25,.25,.25,1);
    const GLfloat vertices[] = {-1,-1, 1,-1, 1,1, -1,1};
    glEnableClientState(GL_VERTEX_ARRAY); glVertexPointer(2,GL_FLOAT,0,vertices);
    glDrawArrays(GL_QUADS,0,4);
    unsigned char pixel[4]; glReadPixels(8,8,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
    assert(pixel[0] >= 63 && pixel[0] <= 65);
    glBindFramebuffer(GL_FRAMEBUFFER,0);
    glDeleteFramebuffers(1,&fbo); glDeleteTextures(1,&tex);
    assert(glGetError() == GL_NO_ERROR);
    assert(glXMakeCurrent(v->d,None,NULL));
    return NULL;
}
int main(void)
{
    assert(XInitThreads());
    Display *d = XOpenDisplay(NULL); assert(d);
    int attrs[] = {GLX_RGBA,GLX_DOUBLEBUFFER,GLX_DEPTH_SIZE,24,None};
    XVisualInfo *visual = glXChooseVisual(d,DefaultScreen(d),attrs); assert(visual);
    XSetWindowAttributes a = {0};
    a.colormap = XCreateColormap(d,DefaultRootWindow(d),visual->visual,AllocNone);
    View views[2]; pthread_t threads[2];
    for (int i = 0; i < 2; ++i) {
        views[i].d = d; views[i].index = i;
        views[i].w = XCreateWindow(d,DefaultRootWindow(d),0,i*120,160,100,0,visual->depth,InputOutput,visual->visual,CWColormap,&a);
        XMapWindow(d,views[i].w);
        views[i].c = glXCreateContext(d,visual,NULL,True); assert(views[i].c);
    }
    XSync(d,False);
    for (int i = 0; i < 2; ++i) assert(!pthread_create(&threads[i],NULL,exercise,&views[i]));
    for (int i = 0; i < 2; ++i) {
        assert(!pthread_join(threads[i],NULL));
        glXDestroyContext(d,views[i].c); XDestroyWindow(d,views[i].w);
    }
    XFree(visual); XCloseDisplay(d);
    puts("PASS: two contexts/threads, subviewport/scissor restoration, FBO draws run once");
}
