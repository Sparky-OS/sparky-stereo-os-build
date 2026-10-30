/* SPDX-License-Identifier: MIT */
/* Pixel control for ordinary EGL pbuffers, with no native display or stereo. */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void require(int ok, const char *operation)
{
    if (!ok) {
        fprintf(stderr, "%s: EGL error %#x, GL error %#x\n", operation,
                eglGetError(), glGetError());
        exit(1);
    }
}

int main(void)
{
    EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA,
                                               EGL_DEFAULT_DISPLAY, NULL);
    EGLint major, minor, count;
    EGLConfig config;
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE
    };
    require(display != EGL_NO_DISPLAY, "surfaceless display");
    require(eglInitialize(display, &major, &minor), "initialize");
    require(eglBindAPI(EGL_OPENGL_API), "OpenGL API");
    require(eglChooseConfig(display, attributes, &config, 1, &count) && count,
            "pbuffer config");
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, NULL);
    require(context != EGL_NO_CONTEXT, "context");
    printf("EGL %d.%d vendor=%s\n", major, minor,
           eglQueryString(display, EGL_VENDOR));
    for (int frame = 0; frame < 3; ++frame) {
        const int width = frame == 1 ? 32 : 64, height = frame == 1 ? 24 : 48;
        EGLint dimensions[] = {EGL_WIDTH, width, EGL_HEIGHT, height, EGL_NONE};
        EGLSurface surface = eglCreatePbufferSurface(display, config, dimensions);
        require(surface != EGL_NO_SURFACE, "pbuffer");
        require(eglMakeCurrent(display, surface, surface, context), "make current");
        GLboolean stereo = GL_TRUE, doublebuffer = GL_FALSE;
        glGetBooleanv(GL_STEREO, &stereo);
        glGetBooleanv(GL_DOUBLEBUFFER, &doublebuffer);
        require(!stereo, "ordinary mono context");
        glViewport(0, 0, width, height);
        glEnable(GL_SCISSOR_TEST);
        for (int quadrant = 0; quadrant < 4; ++quadrant) {
            glScissor((quadrant & 1) * width / 2, (quadrant >> 1) * height / 2,
                      width / 2, height / 2);
            glClearColor((quadrant == 0 || quadrant == 3),
                         (quadrant == 1 || quadrant == 3),
                         (quadrant == 2 || quadrant == 3), 1);
            glClear(GL_COLOR_BUFFER_BIT);
        }
        glDisable(GL_SCISSOR_TEST);
        glFinish();
        glReadBuffer(doublebuffer ? GL_BACK : GL_FRONT);
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        unsigned char pixels[64 * 48 * 3];
        glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels);
        require(glGetError() == GL_NO_ERROR, "read pixels");
        unsigned bad = 0;
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                int quadrant = (x >= width / 2) + 2 * (y >= height / 2);
                const unsigned char expected[] = {
                    (quadrant == 0 || quadrant == 3) ? 255 : 0,
                    (quadrant == 1 || quadrant == 3) ? 255 : 0,
                    (quadrant == 2 || quadrant == 3) ? 255 : 0
                };
                bad += memcmp(pixels + (y * width + x) * 3, expected, 3) != 0;
            }
        printf("FRAME %d size=%dx%d stereo=%d mismatches=%u renderer=%s\n",
               frame, width, height, stereo, bad, glGetString(GL_RENDERER));
        require(!bad, "all pixels");
        require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                               EGL_NO_CONTEXT), "unbind");
        require(eglDestroySurface(display, surface), "destroy pbuffer");
    }
    FILE *maps = fopen("/proc/self/maps", "r");
    char line[2048];
    require(maps != NULL, "mapped providers");
    while (fgets(line, sizeof(line), maps))
        if (strstr(line, "/")) printf("MAP %s", line);
    fclose(maps);
    require(eglDestroyContext(display, context), "destroy context");
    require(eglTerminate(display), "terminate");
    return 0;
}
