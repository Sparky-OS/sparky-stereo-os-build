/* glx-draw-buffers.c: what reaches each color buffer of a GLX window, read back with glReadPixels before the swap.
 * CASE=out|fragcolor|clear|fixed  a quad buffer window, left cleared red, right blue, then glDrawBuffer(GL_BACK) and a green rectangle
 *      left|right                 the same rectangle with GL_BACK_LEFT or GL_BACK_RIGHT (a shader's own output)
 *      mrtwin                     GL_BACK, a shader with two outputs (green at 0, magenta at 1)
 *      dualsrc                    GL_BACK, dual-source blending (index 0 and 1 at location 0)
 *      mrtfbo                     a framebuffer object with two attachments, glDrawBuffers, the window untouched
 *      mono                       a window without stereo, a shader's own output, GL_BACK
 *      es2|es3                    OpenGL ES contexts on a mono window (gl_FragColor, a declared output)
 * ANNOUNCE_STEREO=1 sets the root property a stereo compositor sets, for a test display without one.
 * TIME=N draws N frames with swaps and prints the mean frame time.  Exit 0 always when it ran: the caller compares the lines.
 * SPDX-License-Identifier: MIT */
#define GL_GLEXT_PROTOTYPES
#define GLX_GLXEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <GL/glext.h>
#include <GL/glxext.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#ifndef GLX_CONTEXT_ES2_PROFILE_BIT_EXT
#define GLX_CONTEXT_ES2_PROFILE_BIT_EXT 0x4
#endif
static int W = 400, H = 300;
static GLuint prog(const char *vs, const char *fs)
{
    GLuint v = glCreateShader(GL_VERTEX_SHADER), f = glCreateShader(GL_FRAGMENT_SHADER), p = glCreateProgram();
    GLint ok; char log[512];
    glShaderSource(v, 1, &vs, NULL); glCompileShader(v);
    glShaderSource(f, 1, &fs, NULL); glCompileShader(f);
    glGetShaderiv(f, GL_COMPILE_STATUS, &ok);
    if (!ok) { glGetShaderInfoLog(f, sizeof log, NULL, log); printf("COMPILE-FAILED %s\n", log); exit(3); }
    glAttachShader(p, v); glAttachShader(p, f); glBindAttribLocation(p, 0, "pos"); glLinkProgram(p);
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) { glGetProgramInfoLog(p, sizeof log, NULL, log); printf("LINK-FAILED %s\n", log); exit(3); }
    return p;
}
static void px(const char *what, int x, int y)
{
    unsigned char c[4] = {9, 9, 9, 9};
    glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, c);
    printf(" %s=%d,%d,%d", what, c[0], c[1], c[2]);
}
int main(void)
{
    const char *cs = getenv("CASE") ? getenv("CASE") : "out";
    int stereo = strcmp(cs, "mono") && strcmp(cs, "es2") && strcmp(cs, "es3");
    int es = !strcmp(cs, "es2") ? 2 : !strcmp(cs, "es3") ? 3 : 0;
    int compat = !strcmp(cs, "fragcolor") || !strcmp(cs, "clear") || !strcmp(cs, "fixed");
    int n = 0, frames = getenv("TIME") ? atoi(getenv("TIME")) : 3;
    Display *d = XOpenDisplay(NULL);
    if (!d) { printf("NO-DISPLAY\n"); return 2; }
    if (getenv("ANNOUNCE_STEREO")) {   /* a test display without a stereo compositor: announce it as the compositor does */
        unsigned long v = 10;
        XChangeProperty(d, DefaultRootWindow(d), XInternAtom(d, "_KDE_NET_WM_STEREO_CONTENT_SUPPORTED", False), XInternAtom(d, "CARDINAL", False), 32, PropModeReplace, (unsigned char *)&v, 1);
        XSync(d, False);
    }
    int att[] = { GLX_RENDER_TYPE, GLX_RGBA_BIT, GLX_DRAWABLE_TYPE, GLX_WINDOW_BIT, GLX_DOUBLEBUFFER, True, GLX_STEREO, stereo ? True : False,
                  GLX_RED_SIZE, 8, GLX_GREEN_SIZE, 8, GLX_BLUE_SIZE, 8, GLX_DEPTH_SIZE, 24, None };
    GLXFBConfig *c = glXChooseFBConfig(d, DefaultScreen(d), att, &n);
    if (!c || !n) { printf("case %s: NO-CONFIG (stereo %d)\n", cs, stereo); return 4; }
    XVisualInfo *vi = glXGetVisualFromFBConfig(d, c[0]);
    XSetWindowAttributes swa; memset(&swa, 0, sizeof swa);
    swa.colormap = XCreateColormap(d, RootWindow(d, vi->screen), vi->visual, AllocNone);
    swa.event_mask = StructureNotifyMask;
    Window win = XCreateWindow(d, RootWindow(d, vi->screen), 50, 50, W, H, 0, vi->depth, InputOutput, vi->visual, CWColormap | CWEventMask, &swa);
    XStoreName(d, win, "drawbuffers"); XMapWindow(d, win); XSync(d, False); usleep(700000);
    int cat[] = { GLX_CONTEXT_MAJOR_VERSION_ARB, es ? es : compat ? 2 : 3, GLX_CONTEXT_MINOR_VERSION_ARB, es ? 0 : compat ? 1 : 3,
                  GLX_CONTEXT_PROFILE_MASK_ARB, es ? GLX_CONTEXT_ES2_PROFILE_BIT_EXT : compat ? GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB : GLX_CONTEXT_CORE_PROFILE_BIT_ARB, None };
    GLXContext ctx = glXCreateContextAttribsARB(d, c[0], NULL, True, cat);
    if (!ctx) { printf("case %s: NO-CONTEXT\n", cs); return 5; }
    glXMakeCurrent(d, win, ctx);
    static const GLfloat q[] = { -0.5f, -0.5f, 0.5f, -0.5f, -0.5f, 0.5f, 0.5f, 0.5f };
    const char *v330 = "#version 330 core\nin vec2 pos;\nvoid main(){gl_Position=vec4(pos,0.0,1.0);}\n";
    GLuint p = 0, vao = 0, vbo = 0, fbo = 0, tex[2] = {0, 0};
    if (es == 2) p = prog("attribute vec2 pos;\nvoid main(){gl_Position=vec4(pos,0.0,1.0);}\n", "precision mediump float;\nvoid main(){gl_FragColor=vec4(0.0,1.0,0.0,1.0);}\n");
    else if (es == 3) p = prog("#version 300 es\nin vec2 pos;\nvoid main(){gl_Position=vec4(pos,0.0,1.0);}\n", "#version 300 es\nprecision mediump float;\nlayout(location=0) out vec4 colour;\nvoid main(){colour=vec4(0.0,1.0,0.0,1.0);}\n");
    else if (!strcmp(cs, "fragcolor")) p = prog("#version 120\nattribute vec2 pos;\nvoid main(){gl_Position=vec4(pos,0.0,1.0);}\n", "#version 120\nvoid main(){gl_FragColor=vec4(0.0,1.0,0.0,1.0);}\n");
    else if (!strcmp(cs, "mrtwin") || !strcmp(cs, "mrtfbo")) p = prog(v330, "#version 330 core\nlayout(location=0) out vec4 a;\nlayout(location=1) out vec4 b;\nvoid main(){a=vec4(0.0,1.0,0.0,1.0);b=vec4(1.0,0.0,1.0,1.0);}\n");
    else if (!strcmp(cs, "dualsrc")) p = prog(v330, "#version 330 core\nlayout(location=0,index=0) out vec4 a;\nlayout(location=0,index=1) out vec4 b;\nvoid main(){a=vec4(0.0,0.5,0.0,1.0);b=vec4(0.0,0.0,0.0,1.0);}\n");
    else if (!compat) p = prog(v330, "#version 330 core\nlayout(location=0) out vec4 colour;\nvoid main(){colour=vec4(0.0,1.0,0.0,1.0);}\n");
    if (p) {
        if (!compat && es != 2) { glGenVertexArrays(1, &vao); glBindVertexArray(vao); }
        glGenBuffers(1, &vbo); glBindBuffer(GL_ARRAY_BUFFER, vbo); glBufferData(GL_ARRAY_BUFFER, sizeof q, q, GL_STATIC_DRAW);
        glEnableVertexAttribArray(0); glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
    }
    if (!strcmp(cs, "mrtfbo")) {
        glGenFramebuffers(1, &fbo); glGenTextures(2, tex);
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        for (int i = 0; i < 2; i++) { glBindTexture(GL_TEXTURE_2D, tex[i]); glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, tex[i], 0); }
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    struct timespec t0, t1; clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < frames; i++) {
        glViewport(0, 0, W, H);
        if (stereo) {
            glDrawBuffer(GL_BACK_LEFT);  glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glDrawBuffer(GL_BACK_RIGHT); glClearColor(0, 0, 1, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glDrawBuffer(!strcmp(cs, "left") ? GL_BACK_LEFT : !strcmp(cs, "right") ? GL_BACK_RIGHT : GL_BACK);
        } else { glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT); }
        if (!strcmp(cs, "mrtfbo")) {
            GLenum bufs[2] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1 };
            glBindFramebuffer(GL_FRAMEBUFFER, fbo); glDrawBuffers(2, bufs); glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        }
        if (!strcmp(cs, "dualsrc")) { glEnable(GL_BLEND); glBlendFunc(GL_ONE, GL_SRC1_COLOR); }
        if (p) { glUseProgram(p); glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); }
        else if (!strcmp(cs, "clear")) { glEnable(GL_SCISSOR_TEST); glScissor(W / 4, H / 4, W / 2, H / 2); glClearColor(0, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT); glDisable(GL_SCISSOR_TEST); }
        else { glColor3f(0, 1, 0); glBegin(GL_TRIANGLE_STRIP); for (int k = 0; k < 4; k++) glVertex2f(q[2 * k], q[2 * k + 1]); glEnd(); }
        if (i == frames - 1 && !getenv("TIME")) {
            printf("case %s: error=0x%x", cs, glGetError());
            if (!strcmp(cs, "mrtfbo")) {
                glReadBuffer(GL_COLOR_ATTACHMENT0); px("att0", W / 2, H / 2); glReadBuffer(GL_COLOR_ATTACHMENT1); px("att1", W / 2, H / 2);
                glBindFramebuffer(GL_FRAMEBUFFER, 0);
            }
            if (stereo) { glReadBuffer(GL_BACK_LEFT); px("left-corner", 5, 5); px("left-middle", W / 2, H / 2); glReadBuffer(GL_BACK_RIGHT); px("right-corner", 5, 5); px("right-middle", W / 2, H / 2); }
            else { px("corner", 5, 5); px("middle", W / 2, H / 2); }
            printf(" | %s\n", glGetString(GL_RENDERER));
        }
        if (!strcmp(cs, "mrtfbo")) glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glDisable(GL_BLEND);
        glXSwapBuffers(d, win);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    if (getenv("TIME")) printf("case %s: %d frames, %.4f ms a frame | %s\n", cs, frames, ((t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6) / frames, glGetString(GL_RENDERER));
    return 0;
}
