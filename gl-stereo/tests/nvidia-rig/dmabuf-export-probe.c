/* SPDX-License-Identifier: MIT */
/* Exports a GL texture as a dma-buf the way GTK does (EGL_MESA_image_dma_buf_export) and says whether the fds are open. */
#define EGL_EGLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int
main (void)
{
  PFNEGLGETPLATFORMDISPLAYEXTPROC get_display = (void *) eglGetProcAddress ("eglGetPlatformDisplayEXT");
  PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC query = (void *) eglGetProcAddress ("eglExportDMABUFImageQueryMESA");
  PFNEGLEXPORTDMABUFIMAGEMESAPROC export_image = (void *) eglGetProcAddress ("eglExportDMABUFImageMESA");
  EGLDisplay dpy = get_display (EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
  EGLint major, minor;
  EGLConfig config;
  EGLint n;
  EGLint attribs[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_NONE };
  EGLint ctx_attribs[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
  GLuint tex;
  EGLImage image;
  int fourcc, planes;
  EGLuint64KHR modifiers[4];
  int fds[4] = { -1, -1, -1, -1 };
  EGLint strides[4], offsets[4];

  if (!eglInitialize (dpy, &major, &minor))
    return printf ("eglInitialize failed 0x%x\n", eglGetError ()), 1;
  printf ("EGL %d.%d vendor %s\n", major, minor, eglQueryString (dpy, EGL_VENDOR));
  printf ("export extension: %s\n", strstr (eglQueryString (dpy, EGL_EXTENSIONS), "EGL_MESA_image_dma_buf_export") ? "yes" : "no");
  eglBindAPI (EGL_OPENGL_ES_API);
  if (!eglChooseConfig (dpy, attribs, &config, 1, &n) || !n)
    return printf ("no config\n"), 1;
  EGLContext ctx = eglCreateContext (dpy, config, EGL_NO_CONTEXT, ctx_attribs);
  eglMakeCurrent (dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx);
  printf ("GL renderer: %s\n", glGetString (GL_RENDERER));
  glGenTextures (1, &tex);
  glBindTexture (GL_TEXTURE_2D, tex);
  glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA8, 256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
  image = eglCreateImage (dpy, ctx, EGL_GL_TEXTURE_2D, (EGLClientBuffer) (uintptr_t) tex, NULL);
  if (image == EGL_NO_IMAGE)
    return printf ("eglCreateImage failed 0x%x\n", eglGetError ()), 1;
  if (!query (dpy, image, &fourcc, &planes, modifiers))
    return printf ("query failed 0x%x\n", eglGetError ()), 1;
  printf ("fourcc %.4s planes %d modifier0 0x%llx\n", (char *) &fourcc, planes, (unsigned long long) modifiers[0]);
  if (!export_image (dpy, image, fds, strides, offsets))
    return printf ("export failed 0x%x\n", eglGetError ()), 1;
  for (int i = 0; i < planes; i++)
    printf ("plane %d fd %d (%s) stride %d offset %d\n", i, fds[i], fds[i] >= 0 && fcntl (fds[i], F_GETFD) >= 0 ? "open" : "NOT OPEN", strides[i], offsets[i]);
  return 0;
}
