/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Every OpenGL 4.6 drawing command reaches the view its draw buffer names
 * (sections 10.4 and 13.2.3): each command draws one square into the left back
 * buffer in red and into the right back buffer in blue, at its own place, and
 * both views are read back. */
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/glx.h>
#include <X11/Xatom.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { WIDTH = 320, HEIGHT = 200, CELL = 30, COMMANDS = 10 };
static const char *names[COMMANDS] = {
    "DrawArraysInstancedBaseInstance", "DrawElementsInstancedBaseInstance",
    "DrawElementsInstancedBaseVertexBaseInstance", "MultiDrawElementsBaseVertex",
    "MultiDrawArraysIndirectCount", "MultiDrawElementsIndirectCount",
    "DrawTransformFeedback", "DrawTransformFeedbackInstanced",
    "DrawTransformFeedbackStream", "DrawTransformFeedbackStreamInstanced"};

static GLuint shader(GLenum type, const char *source)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &source, NULL); glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok); assert(ok);
    return s;
}

/* Two triangles covering a CELL square at the cell of command i, in clip space. */
static void square(int i, float *v)
{
    float x0 = -1 + 2.0f * (10 + (i % 5) * 60) / WIDTH, y0 = -1 + 2.0f * (40 + (i / 5) * 80) / HEIGHT;
    float x1 = x0 + 2.0f * CELL / WIDTH, y1 = y0 + 2.0f * CELL / HEIGHT;
    float q[12] = {x0, y0, x1, y0, x1, y1, x0, y0, x1, y1, x0, y1};
    memcpy(v, q, sizeof(q));
}

int main(void)
{
    Display *d = XOpenDisplay(NULL); assert(d);
    unsigned long version = 1;
    Atom supported = XInternAtom(d, "_KDE_NET_WM_STEREO_CONTENT_SUPPORTED", False);
    XChangeProperty(d, DefaultRootWindow(d), supported, XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&version, 1);
    XSync(d, False);
    int count;
    int fbattrs[] = {GLX_RENDER_TYPE, GLX_RGBA_BIT, GLX_DRAWABLE_TYPE, GLX_WINDOW_BIT, GLX_DOUBLEBUFFER, True, GLX_STEREO, True, None};
    GLXFBConfig *configs = glXChooseFBConfig(d, DefaultScreen(d), fbattrs, &count);
    assert(configs && count);
    XVisualInfo *v = glXGetVisualFromFBConfig(d, configs[0]); assert(v);
    XSetWindowAttributes a = {0};
    a.colormap = XCreateColormap(d, DefaultRootWindow(d), v->visual, AllocNone);
    Window w = XCreateWindow(d, DefaultRootWindow(d), 0, 0, WIDTH, HEIGHT, 0, v->depth, InputOutput, v->visual, CWColormap, &a);
    XMapWindow(d, w);
    PFNGLXCREATECONTEXTATTRIBSARBPROC create =
        (PFNGLXCREATECONTEXTATTRIBSARBPROC)glXGetProcAddressARB((const GLubyte *)"glXCreateContextAttribsARB");
    int ctxattrs[] = {GLX_CONTEXT_MAJOR_VERSION_ARB, 4, GLX_CONTEXT_MINOR_VERSION_ARB, 5,
                      GLX_CONTEXT_PROFILE_MASK_ARB, GLX_CONTEXT_CORE_PROFILE_BIT_ARB, None};
    GLXContext c = create(d, configs[0], NULL, True, ctxattrs);
    assert(c && glXMakeCurrent(d, w, c));
    GLboolean stereo; glGetBooleanv(GL_STEREO, &stereo); assert(stereo);

    GLuint program = glCreateProgram();
    glAttachShader(program, shader(GL_VERTEX_SHADER,
        "#version 450\nin vec2 position; out vec2 captured;\n"
        "void main() { captured = position; gl_Position = vec4(position, 0, 1); }\n"));
    glAttachShader(program, shader(GL_FRAGMENT_SHADER,
        "#version 450\nuniform vec4 colour; out vec4 fragment;\nvoid main() { fragment = colour; }\n"));
    const char *varyings[] = {"captured"};
    glTransformFeedbackVaryings(program, 1, varyings, GL_INTERLEAVED_ATTRIBS);
    glBindAttribLocation(program, 0, "position");
    glLinkProgram(program);
    GLint ok; glGetProgramiv(program, GL_LINK_STATUS, &ok); assert(ok);
    glUseProgram(program);
    GLint colour = glGetUniformLocation(program, "colour");

    float vertices[COMMANDS][12];
    for (int i = 0; i < COMMANDS; ++i) square(i, vertices[i]);
    GLuint vao, vbo, ibo, indirect, parameter, xfb[4], xfb_buffer[4];
    glGenVertexArrays(1, &vao); glBindVertexArray(vao);
    glGenBuffers(1, &vbo); glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    const GLuint elements[6] = {0, 1, 2, 3, 4, 5};
    glGenBuffers(1, &ibo); glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(elements), elements, GL_STATIC_DRAW);
    /* Indirect commands for squares 4 (arrays: count, instances, first, base instance) and
     * 5 (elements: count, instances, first index, base vertex, base instance). */
    const GLuint commands[9] = {6, 1, 4 * 6, 0, 6, 1, 0, 5 * 6, 0};
    glGenBuffers(1, &indirect); glBindBuffer(GL_DRAW_INDIRECT_BUFFER, indirect);
    glBufferData(GL_DRAW_INDIRECT_BUFFER, sizeof(commands), commands, GL_STATIC_DRAW);
    const GLsizei one = 1;
    glGenBuffers(1, &parameter); glBindBuffer(GL_PARAMETER_BUFFER, parameter);
    glBufferData(GL_PARAMETER_BUFFER, sizeof(one), &one, GL_STATIC_DRAW);
    /* Squares 6 to 9 captured once into transform feedback objects, nothing rasterized. */
    glGenTransformFeedbacks(4, xfb); glGenBuffers(4, xfb_buffer);
    glDrawBuffer(GL_BACK_LEFT); /* one view: the capture is drawn once */
    glEnable(GL_RASTERIZER_DISCARD);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
    for (int i = 0; i < 4; ++i) {
        glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, xfb[i]);
        glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER, xfb_buffer[i]);
        glBufferData(GL_TRANSFORM_FEEDBACK_BUFFER, sizeof(vertices[0]), NULL, GL_STATIC_DRAW);
        glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, xfb_buffer[i]);
        glBeginTransformFeedback(GL_TRIANGLES);
        glDrawArrays(GL_TRIANGLES, (6 + i) * 6, 6);
        glEndTransformFeedback();
    }
    glDisable(GL_RASTERIZER_DISCARD);
    glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, 0);

    glViewport(0, 0, WIDTH, HEIGHT);
    for (int eye = 0; eye < 2; ++eye) {
        glDrawBuffer(eye ? GL_BACK_RIGHT : GL_BACK_LEFT);
        glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glUniform4f(colour, !eye, 0, eye, 1);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
        glDrawArraysInstancedBaseInstance(GL_TRIANGLES, 0 * 6, 6, 1, 0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, (void *)(1 * 6 * 2 * sizeof(float)));
        glDrawElementsInstancedBaseInstance(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0, 1, 0);
        glDrawElementsInstancedBaseVertexBaseInstance(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0, 1, 6, 0);
        const GLsizei counts[1] = {6};
        const void *offsets[1] = {0};
        const GLint bases[1] = {2 * 6};
        glMultiDrawElementsBaseVertex(GL_TRIANGLES, counts, GL_UNSIGNED_INT, offsets, 1, bases);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
        glMultiDrawArraysIndirectCount(GL_TRIANGLES, 0, 0, 1, 0);
        glMultiDrawElementsIndirectCount(GL_TRIANGLES, GL_UNSIGNED_INT, (void *)(4 * sizeof(GLuint)), 0, 1, 0);
        for (int i = 0; i < 4; ++i) {
            glBindBuffer(GL_ARRAY_BUFFER, xfb_buffer[i]);
            glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
            if (i == 0) glDrawTransformFeedback(GL_TRIANGLES, xfb[i]);
            if (i == 1) glDrawTransformFeedbackInstanced(GL_TRIANGLES, xfb[i], 1);
            if (i == 2) glDrawTransformFeedbackStream(GL_TRIANGLES, xfb[i], 0);
            if (i == 3) glDrawTransformFeedbackStreamInstanced(GL_TRIANGLES, xfb[i], 0, 1);
        }
    }
    assert(glGetError() == GL_NO_ERROR);
    int failures = 0;
    for (int eye = 0; eye < 2; ++eye) {
        glReadBuffer(eye ? GL_BACK_RIGHT : GL_BACK_LEFT);
        for (int i = 0; i < COMMANDS; ++i) {
            unsigned char pixel[4] = {0};
            glReadPixels(10 + (i % 5) * 60 + CELL / 2, 40 + (i / 5) * 80 + CELL / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            int good = pixel[0] == (eye ? 0 : 255) && pixel[1] == 0 && pixel[2] == (eye ? 255 : 0);
            if (!good) {
                printf("FAIL: %s, %s eye reads %d,%d,%d\n", names[i], eye ? "right" : "left", pixel[0], pixel[1], pixel[2]);
                ++failures;
            }
        }
    }
    glXSwapBuffers(d, w);
    glXMakeCurrent(d, None, NULL); glXDestroyContext(d, c);
    XDestroyWindow(d, w); XFree(v); XFree(configs); XCloseDisplay(d);
    if (failures) return 1;
    printf("PASS: all %d drawing commands drew into the view their draw buffer names\n", COMMANDS);
    return 0;
}
