/* SPDX-License-Identifier: GPL-2.0-or-later OR MIT */
/* Synthetic stereo test: three quads at eye-space depths near, convergence, far.
 * Each quad is drawn in a distinct vertical band so depth test never occludes one.
 * Red = Z/2 (in front of screen), green = Z (screen plane), blue = 2Z (behind).
 */

#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "quads: cannot open display\n"); return 1; }
    int screen = DefaultScreen(dpy);
    Window root = RootWindow(dpy, screen);
    int attribs[] = {GLX_RGBA, GLX_DOUBLEBUFFER, GLX_DEPTH_SIZE, 24, None};
    XVisualInfo *vi = glXChooseVisual(dpy, screen, attribs);
    if (!vi) return 2;
    XSetWindowAttributes swa = {0};
    swa.event_mask = ExposureMask;
    swa.colormap = XCreateColormap(dpy, root, vi->visual, AllocNone);
    Window w = XCreateWindow(dpy, root, 0, 0, 640, 360, 0,
                             vi->depth, InputOutput, vi->visual,
                             CWEventMask | CWColormap, &swa);
    XMapWindow(dpy, w);
    GLXContext ctx = glXCreateContext(dpy, vi, NULL, GL_TRUE);
    if (!ctx || !glXMakeCurrent(dpy, w, ctx)) return 3;
    XFree(vi);
    glXWaitX();
#ifdef TEST_SHADER
    const char *vertex = "#version 120\nuniform mat4 camera; void main() { gl_Position=camera*gl_Vertex; gl_FrontColor=gl_Color; }";
    const char *fragment = "#version 120\nvoid main() { gl_FragColor=gl_Color; }";
    GLuint vs=glCreateShader(GL_VERTEX_SHADER), fs=glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(vs,1,&vertex,NULL); glCompileShader(vs);
    glShaderSource(fs,1,&fragment,NULL); glCompileShader(fs);
    GLuint program=glCreateProgram(); glAttachShader(program,vs); glAttachShader(program,fs); glLinkProgram(program);
    GLint linked; glGetProgramiv(program,GL_LINK_STATUS,&linked);
    if (!linked) return 6;
    char unchanged[256]; glGetShaderSource(vs,sizeof(unchanged),NULL,unchanged);
    if (strcmp(unchanged,vertex)) return 7;
    glUseProgram(program);
    GLint camera=glGetUniformLocation(program,"camera");
    GLfloat original[16];
#endif

    for (int frame = 0; frame < (getenv("TEST_FRAMES") ? 40 : 1); ++frame) {
    glViewport(0, 0, 640, 360);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    double n = 1.0, f = 100.0, t = 0.5;
    double r = t * n, l = -r, b = -0.5, tp = 0.5;
    glFrustum(l, r, b, tp, n, f);

    if (getenv("TEST_PROJECTION_VIEW") || getenv("TEST_PROJECTION_ROTATE")) glTranslated(0,0,-20);
    if (getenv("TEST_PROJECTION_ROTATE")) glRotated(35,0,1,0);
    if (getenv("TEST_MATRIX")) {
        GLdouble projection[16], stretch[16] = {2,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
        glGetDoublev(GL_PROJECTION_MATRIX, projection);
        projection[0] /= 2;
        glLoadMatrixd(projection);
        glMultMatrixd(stretch);
        glPushMatrix(); glLoadIdentity(); glPopMatrix();
    }
    if (getenv("TEST_ORTHO")) {
        glLoadIdentity(); glOrtho(-1, 1, -2, 2, 1, 100);
    }
#ifdef TEST_SHADER
    glGetFloatv(GL_PROJECTION_MATRIX,original);
    glUniformMatrix4fv(camera,1,GL_FALSE,original);
    glLoadIdentity();
#endif
    if (getenv("TEST_TEXTURE")) {
        unsigned char pixels[8*8*3];
        for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x)
            for (int c = 0; c < 3; ++c) pixels[(y*8+x)*3+c] = ((x+y)%2) ? 255 : 96;
        GLuint tex; glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 8, 8, 0, GL_RGB, GL_UNSIGNED_BYTE, pixels);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glEnable(GL_TEXTURE_2D);
    }
    GLdouble model_camera[16];
    glGetDoublev(GL_PROJECTION_MATRIX,model_camera);
    if (getenv("TEST_MODELVIEW_CAMERA")) glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    if (getenv("TEST_MODELVIEW_CAMERA")) glLoadMatrixd(model_camera);
    if (getenv("TEST_PROJECTION_ROTATE")) glRotated(-35,0,1,0);
    if (getenv("TEST_PROJECTION_VIEW") || getenv("TEST_PROJECTION_ROTATE")) glTranslated(0,0,20);
    (void)n;

    glColor3f(1, 0, 0);
    glBegin(GL_QUADS);
    glTexCoord2f(0, 0);
    glVertex3f(-0.2f,  0.6f, -n * 5.0f / 2.0f);
    glTexCoord2f(1, 0);
    glVertex3f( 0.2f,  0.6f, -n * 5.0f / 2.0f);
    glTexCoord2f(1, 1);
    glVertex3f( 0.2f,  0.2f, -n * 5.0f / 2.0f);
    glTexCoord2f(0, 1);
    glVertex3f(-0.2f,  0.2f, -n * 5.0f / 2.0f);
    glEnd();

    glColor3f(0, 1, 0);
    glBegin(GL_QUADS);
    glTexCoord2f(0, 0);
    glVertex3f(-0.2f,  0.1f, -n * 5.0f);
    glTexCoord2f(1, 0);
    glVertex3f( 0.2f,  0.1f, -n * 5.0f);
    glTexCoord2f(1, 1);
    glVertex3f( 0.2f, -0.3f, -n * 5.0f);
    glTexCoord2f(0, 1);
    glVertex3f(-0.2f, -0.3f, -n * 5.0f);
    glEnd();

    glColor3f(0, 0, 1);
    glBegin(GL_QUADS);
    glTexCoord2f(0, 0);
    glVertex3f(-0.2f, -1.2f, -n * 5.0f * 2.0f);
    glTexCoord2f(1, 0);
    glVertex3f( 0.2f, -1.2f, -n * 5.0f * 2.0f);
    glTexCoord2f(1, 1);
    glVertex3f( 0.2f, -1.6f, -n * 5.0f * 2.0f);
    glTexCoord2f(0, 1);
    glVertex3f(-0.2f, -1.6f, -n * 5.0f * 2.0f);
    glEnd();

    if (getenv("TEST_CAMERA_TEXTURE")) {
        GLuint texture; glGenTextures(1,&texture); glBindTexture(GL_TEXTURE_2D,texture);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
        glCopyTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,0,0,640,360,0);
        glCopyTexSubImage2D(GL_TEXTURE_2D,0,0,0,0,0,320,360);
        glTexParameterf(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
        glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
        glMatrixMode(GL_PROJECTION);glLoadIdentity();
        glMatrixMode(GL_MODELVIEW);glLoadIdentity();
        glEnable(GL_TEXTURE_2D);glColor3f(1,1,1);
        glBegin(GL_QUADS);
        glTexCoord2f(0,0);glVertex2f(-1,-1);
        glTexCoord2f(1,0);glVertex2f(1,-1);
        glTexCoord2f(1,1);glVertex2f(1,1);
        glTexCoord2f(0,1);glVertex2f(-1,1);
        glEnd();
        GLint binding;glGetIntegerv(GL_TEXTURE_BINDING_2D,&binding);
        if (binding!=(GLint)texture) return 11;
        glDisable(GL_TEXTURE_2D);glDeleteTextures(1,&texture);
    }

#ifdef TEST_SHADER
    GLfloat restored[16]; glGetUniformfv(program,camera,restored);
    if (memcmp(original,restored,sizeof(original))) return 8;
#endif
    GLenum error = glGetError();
    if (error) { fprintf(stderr, "GL error: %x\n", error); return 4; }
    if (argc > 1) {
        unsigned char pixels[640*360*3];
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadBuffer(GL_BACK);
        glReadPixels(0, 0, 640, 360, GL_RGB, GL_UNSIGNED_BYTE, pixels);
        FILE *fp = fopen(argv[1], "wb");
        if (!fp) return 5;
        fprintf(fp, "P6\n640 360\n255\n");
        for (int y = 359; y >= 0; --y) fwrite(pixels+y*640*3, 1, 640*3, fp);
        fclose(fp);
    }
    glXSwapBuffers(dpy, w);
    glXWaitGL();
    }

    glXMakeCurrent(dpy, None, NULL);
    glXDestroyContext(dpy, ctx);
    XDestroyWindow(dpy, w);
    XCloseDisplay(dpy);
    return 0;
}
