#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <time.h>
static double t0(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static double start;

__attribute__((constructor)) static void hello(void)
{
  start = t0();
  fprintf(stderr, "eyedump: loaded\n");
}

static int seq;
static void dump(const char *name0, GLenum buffer, int width, int height)
{
  char path[512], name[128];
  if (getenv("EYEDUMP_SEQ")) snprintf(name, sizeof name, "%s-%02d", name0, seq); else snprintf(name, sizeof name, "%s", name0);
  const char *directory = getenv("EYEDUMP_DIR");
  snprintf(path, sizeof path, "%s/%s.ppm", directory ? directory : ".", name);
  unsigned char *pixels = malloc((size_t) width * height * 3);
  GLint oldRead;
  glGetIntegerv(GL_READ_BUFFER, &oldRead);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadBuffer(buffer);
  glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels);
  GLenum error = glGetError();
  glReadBuffer(oldRead);
  FILE *file = fopen(path, "wb");
  fprintf(file, "P6\n%d %d\n255\n", width, height);
  for (int y = height - 1; y >= 0; --y)
    fwrite(pixels + (size_t) y * width * 3, 3, width, file);
  fclose(file);
  free(pixels);
  fprintf(stderr, "eyedump: %s %dx%d glerror=0x%x\n",
          path, width, height, error);
}

void glXSwapBuffers(Display *display, GLXDrawable drawable)
{
  static void (*real_swap)(Display *, GLXDrawable);
  static int frames;
  static unsigned best;
  if (!real_swap)
    real_swap = dlsym(RTLD_NEXT, "glXSwapBuffers");

  unsigned width = 0;
  unsigned height = 0;
  glXQueryDrawable(display, drawable, GLX_WIDTH, &width);
  glXQueryDrawable(display, drawable, GLX_HEIGHT, &height);
  if (getenv("EYEDUMP_TRACE"))
    fprintf(stderr, "eyedump: swap %ux%u at %.2f\n", width, height, t0() - start);

  int target = getenv("EYEDUMP_FRAME") ? atoi(getenv("EYEDUMP_FRAME")) : 1;
  double after = getenv("EYEDUMP_AFTER") ? atof(getenv("EYEDUMP_AFTER")) : 0;
  if (width * height > (getenv("EYEDUMP_MIN_AREA") ? atoi(getenv("EYEDUMP_MIN_AREA")) : 300000) && t0() - start >= after && t0() - start < (getenv("EYEDUMP_UNTIL") ? atof(getenv("EYEDUMP_UNTIL")) : 1e9))
    {
      best = width * height;
      if (++frames >= target && frames % target == 0)
        {
          GLboolean stereo = GL_FALSE;
          glGetBooleanv(GL_STEREO, &stereo);
          if (getenv("EYEDUMP_FINISH") && *getenv("EYEDUMP_FINISH"))
            glFinish();
          if (stereo && !getenv("EYEDUMP_MONO"))
            {
              dump("left", GL_BACK_LEFT, width, height);
              dump("right", GL_BACK_RIGHT, width, height);
              seq++;
            }
          else
            dump("mono", GL_BACK, width, height);
        }
    }
  if (getenv("EYEDUMP_FINISH") && *getenv("EYEDUMP_FINISH"))
    glFinish();
  real_swap(display, drawable);
}
