/* glx-back-both-eyes.c: a GLX quad buffer window. Left eye cleared red, right eye blue, then glDrawBuffer(GL_BACK) and one more
 * drawing that OpenGL 4.6 core 17.4.1 sends to both back buffers:
 *   MODE=out        a core profile shader with a user-defined output at location 0 draws a green rectangle
 *   MODE=fragcolor  a compatibility shader writing gl_FragColor draws it
 *   MODE=clear      a scissored glClear draws it
 *   MODE=fixed      fixed-function glBegin/glEnd draws it
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
#include <unistd.h>

static GLuint prog(const char *vs, const char *fs)
{
    GLuint v = glCreateShader(GL_VERTEX_SHADER), f = glCreateShader(GL_FRAGMENT_SHADER), p = glCreateProgram();
    GLint ok; char log[512];
    glShaderSource(v, 1, &vs, NULL); glCompileShader(v);
    glShaderSource(f, 1, &fs, NULL); glCompileShader(f);
    glAttachShader(p, v); glAttachShader(p, f); glBindAttribLocation(p, 0, "pos"); glLinkProgram(p);
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) { glGetProgramInfoLog(p, sizeof log, NULL, log); fprintf(stderr, "link: %s\n", log); exit(3); }
    return p;
}

int main(void)
{
    const char *mode = getenv("MODE") ? getenv("MODE") : "out";
    int core = !strcmp(mode, "out");
    int w = 800, h = 600, n = 0, frames = getenv("FRAMES") ? atoi(getenv("FRAMES")) : 600;
    Display *d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "no display\n"); return 2; }
    int att[] = { GLX_RENDER_TYPE, GLX_RGBA_BIT, GLX_DRAWABLE_TYPE, GLX_WINDOW_BIT, GLX_DOUBLEBUFFER, True, GLX_STEREO, True,
                  GLX_RED_SIZE, 8, GLX_GREEN_SIZE, 8, GLX_BLUE_SIZE, 8, GLX_DEPTH_SIZE, 24, None };
    GLXFBConfig *c = glXChooseFBConfig(d, DefaultScreen(d), att, &n);
    if (!c || !n) { fprintf(stderr, "glback: no stereo framebuffer configuration\n"); return 4; }
    XVisualInfo *vi = glXGetVisualFromFBConfig(d, c[0]);
    XSetWindowAttributes swa; memset(&swa, 0, sizeof swa);
    swa.colormap = XCreateColormap(d, RootWindow(d, vi->screen), vi->visual, AllocNone);
    swa.event_mask = StructureNotifyMask | ExposureMask;
    Window win = XCreateWindow(d, RootWindow(d, vi->screen), 100, 100, w, h, 0, vi->depth, InputOutput, vi->visual,
                               CWColormap | CWEventMask, &swa);
    XStoreName(d, win, "glback"); XMapWindow(d, win);
    int cat[] = { GLX_CONTEXT_MAJOR_VERSION_ARB, core ? 3 : 2, GLX_CONTEXT_MINOR_VERSION_ARB, core ? 3 : 1,
                  GLX_CONTEXT_PROFILE_MASK_ARB, core ? GLX_CONTEXT_CORE_PROFILE_BIT_ARB : GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB, None };
    GLXContext ctx = glXCreateContextAttribsARB(d, c[0], NULL, True, cat);
    if (!ctx) { fprintf(stderr, "glback: no context\n"); return 5; }
    glXMakeCurrent(d, win, ctx);
    GLboolean st = 0; glGetBooleanv(GL_STEREO, &st);
    printf("glback: mode %s GL_STEREO %d renderer %s\n", mode, st, glGetString(GL_RENDERER)); fflush(stdout);
    GLuint p = 0, vao = 0, vbo = 0;
    static const GLfloat q[] = { -0.5f, -0.5f, 0.5f, -0.5f, -0.5f, 0.5f, 0.5f, 0.5f };
    if (!strcmp(mode, "out")) {
        p = prog("#version 330 core\nin vec2 pos;\nvoid main(){gl_Position=vec4(pos,0.0,1.0);}\n",
                 "#version 330 core\nlayout(location=0) out vec4 colour;\nvoid main(){colour=vec4(0.0,1.0,0.0,1.0);}\n");
        glGenVertexArrays(1, &vao); glBindVertexArray(vao);
    } else if (!strcmp(mode, "fragcolor")) {
        p = prog("#version 120\nattribute vec2 pos;\nvoid main(){gl_Position=vec4(pos,0.0,1.0);}\n",
                 "#version 120\nvoid main(){gl_FragColor=vec4(0.0,1.0,0.0,1.0);}\n");
    }
    if (p) {
        glGenBuffers(1, &vbo); glBindBuffer(GL_ARRAY_BUFFER, vbo); glBufferData(GL_ARRAY_BUFFER, sizeof q, q, GL_STATIC_DRAW);
        glEnableVertexAttribArray(0); glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
    }
    for (int i = 0; i < frames; i++) {
        while (XPending(d)) { XEvent e; XNextEvent(d, &e); if (e.type == ConfigureNotify && !e.xconfigure.send_event) { w = e.xconfigure.width; h = e.xconfigure.height; } }
        GLint db = 0;
        glViewport(0, 0, w, h);
        glDrawBuffer(GL_BACK_LEFT);  glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glDrawBuffer(GL_BACK_RIGHT); glClearColor(0, 0, 1, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glDrawBuffer(getenv("NOBACK") ? GL_BACK_LEFT : GL_BACK);
        glGetIntegerv(GL_DRAW_BUFFER, &db);
        if (i == 0) { printf("glback: GL_DRAW_BUFFER 0x%x error 0x%x\n", db, glGetError()); fflush(stdout); }
        if (p) { glUseProgram(p); glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); }
        else if (!strcmp(mode, "clear")) { glEnable(GL_SCISSOR_TEST); glScissor(w / 4, h / 4, w / 2, h / 2); glClearColor(0, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT); glDisable(GL_SCISSOR_TEST); }
        else { glColor3f(0, 1, 0); glBegin(GL_TRIANGLE_STRIP); for (int k = 0; k < 4; k++) glVertex2f(q[2 * k], q[2 * k + 1]); glEnd(); }
        glXSwapBuffers(d, win);
        usleep(50000);
    }
    return 0;
}
