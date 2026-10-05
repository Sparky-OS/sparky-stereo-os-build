/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * A 2D window with a 3D area inside it: the window's own surface is a plain
 * 2D buffer (blue, undeclared), and a subsurface holds a two-view EGL surface
 * (left eye red, right eye green), which Mesa declares as full side by side.
 * KWin should show the window in 3D: the blue 2D part the same in both eyes,
 * the subsurface's left view in the left eye and its right view in the right.
 */

#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include <wayland-egl.h>
#include "xdg-shell-client-protocol.h"

enum { WIN_W = 320, WIN_H = 200, SUB_X = 64, SUB_Y = 48, SUB_W = 128, SUB_H = 64 };

struct state {
   struct wl_compositor *compositor;
   struct wl_subcompositor *subcompositor;
   struct wl_shm *shm;
   struct xdg_wm_base *wm_base;
   bool configured;
};

static void wm_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial)
{
   (void)data;
   xdg_wm_base_pong(wm_base, serial);
}
static const struct xdg_wm_base_listener wm_listener = { .ping = wm_ping };

static void surface_configure(void *data, struct xdg_surface *surface, uint32_t serial)
{
   struct state *state = data;
   xdg_surface_ack_configure(surface, serial);
   state->configured = true;
}
static const struct xdg_surface_listener surface_listener = { .configure = surface_configure };

static void toplevel_configure(void *data, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *s)
{
   (void)data; (void)t; (void)w; (void)h; (void)s;
}
static void toplevel_close(void *data, struct xdg_toplevel *t)
{
   (void)data; (void)t;
}
static const struct xdg_toplevel_listener toplevel_listener = {
   .configure = toplevel_configure, .close = toplevel_close,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version)
{
   struct state *state = data;
   if (!strcmp(interface, wl_compositor_interface.name))
      state->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, version < 4 ? version : 4);
   else if (!strcmp(interface, wl_subcompositor_interface.name))
      state->subcompositor = wl_registry_bind(registry, name, &wl_subcompositor_interface, 1);
   else if (!strcmp(interface, wl_shm_interface.name))
      state->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
   else if (!strcmp(interface, xdg_wm_base_interface.name))
      state->wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, version < 3 ? version : 3);
}
static void registry_remove(void *data, struct wl_registry *r, uint32_t name)
{
   (void)data; (void)r; (void)name;
}
static const struct wl_registry_listener registry_listener = {
   .global = registry_global, .global_remove = registry_remove,
};

/* The window's own 2D picture: opaque blue. */
static struct wl_buffer *blue_buffer(struct wl_shm *shm)
{
   const int stride = WIN_W * 4, size = stride * WIN_H;
   int fd = memfd_create("blue", MFD_CLOEXEC);
   assert(fd >= 0 && ftruncate(fd, size) == 0);
   uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
   assert(pixels != MAP_FAILED);
   for (int i = 0; i < WIN_W * WIN_H; i++)
      pixels[i] = 0xff0000ff;
   munmap(pixels, size);
   struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
   struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, WIN_W, WIN_H, stride, WL_SHM_FORMAT_XRGB8888);
   wl_shm_pool_destroy(pool);
   close(fd);
   return buffer;
}

/* Each view carries the frame's number as 16 blocks, white for 1 and black for 0, most
 * significant first, so a capture can tell that both eyes show the same frame. */
enum { BITS = 16, BIT_W = 7, BIT_X = 8, BIT_Y = 8, BIT_H = 16 };

static void draw_eye(GLenum buffer, float red, float green, unsigned frame)
{
   glDrawBuffer(buffer);
   glClearColor(red, green, 0.0f, 1.0f);
   glClear(GL_COLOR_BUFFER_BIT);
   glEnable(GL_SCISSOR_TEST);
   for (int i = 0; i < BITS; i++) {
      const float bit = (frame >> (BITS - 1 - i)) & 1 ? 1.0f : 0.0f;
      glScissor(BIT_X + i * BIT_W, SUB_H - BIT_Y - BIT_H, BIT_W, BIT_H);
      glClearColor(bit, bit, bit, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
   }
   glDisable(GL_SCISSOR_TEST);
   assert(glGetError() == GL_NO_ERROR);
}

int main(void)
{
   struct state state = {0};
   struct wl_display *display = wl_display_connect(NULL);
   assert(display);
   struct wl_registry *registry = wl_display_get_registry(display);
   wl_registry_add_listener(registry, &registry_listener, &state);
   assert(wl_display_roundtrip(display) >= 0);
   assert(state.compositor && state.subcompositor && state.shm && state.wm_base);
   xdg_wm_base_add_listener(state.wm_base, &wm_listener, &state);

   struct wl_surface *surface = wl_compositor_create_surface(state.compositor);
   struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(state.wm_base, surface);
   struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);
   xdg_surface_add_listener(xdg_surface, &surface_listener, &state);
   xdg_toplevel_add_listener(toplevel, &toplevel_listener, &state);
   xdg_toplevel_set_title(toplevel, "2D window with a 3D subsurface");
   wl_surface_commit(surface);
   while (!state.configured)
      assert(wl_display_dispatch(display) >= 0);

   /* The 3D area: a subsurface with a two-view EGL surface. */
   struct wl_surface *child = wl_compositor_create_surface(state.compositor);
   struct wl_subsurface *subsurface = wl_subcompositor_get_subsurface(state.subcompositor, child, surface);
   wl_subsurface_set_position(subsurface, SUB_X, SUB_Y);
   wl_subsurface_set_desync(subsurface);

   struct wl_egl_window *window = wl_egl_window_create(child, SUB_W, SUB_H);
   EGLDisplay egl = eglGetPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, display, NULL);
   assert(egl != EGL_NO_DISPLAY && eglInitialize(egl, NULL, NULL) && eglBindAPI(EGL_OPENGL_API));
   const char *extensions = eglQueryString(egl, EGL_EXTENSIONS);
   assert(extensions && strstr(extensions, "EGL_EXT_multiview_window"));
   const EGLint config_attrs[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE,
   };
   EGLConfig config;
   EGLint count;
   assert(eglChooseConfig(egl, config_attrs, &config, 1, &count) && count == 1);
   /* NO_STEREO: the control, the same window with an ordinary one-view subsurface. */
   const bool stereo = getenv("NO_STEREO") == NULL;
   const EGLint surface_attrs[] = { EGL_MULTIVIEW_VIEW_COUNT_EXT, 2, EGL_NONE };
   EGLSurface egl_surface = eglCreateWindowSurface(egl, config, (EGLNativeWindowType)window, stereo ? surface_attrs : NULL);
   assert(egl_surface != EGL_NO_SURFACE);
   EGLContext context = eglCreateContext(egl, config, EGL_NO_CONTEXT, NULL);
   assert(context != EGL_NO_CONTEXT && eglMakeCurrent(egl, egl_surface, egl_surface, context));
   GLint gl_stereo = 0;
   glGetIntegerv(GL_STEREO, &gl_stereo);
   assert(!gl_stereo == !stereo);

   unsigned frame = 1;
   if (stereo) {
      draw_eye(GL_BACK_LEFT, 1.0f, 0.0f, frame);
      draw_eye(GL_BACK_RIGHT, 0.0f, 1.0f, frame);
   } else {
      draw_eye(GL_BACK, 1.0f, 0.0f, frame);
   }
   glFinish(); /* the known Mesa multiview flush issue, fixed separately */
   assert(eglSwapBuffers(egl, egl_surface));

   /* The window's own 2D part, committed after the 3D area is in place. */
   wl_surface_attach(surface, blue_buffer(state.shm), 0, 0);
   wl_surface_damage(surface, 0, 0, WIN_W, WIN_H);
   wl_surface_commit(surface);
   wl_display_roundtrip(display);
   printf("window=%dx%d subsurface=%dx%d at %d,%d gl_stereo=%d\n", WIN_W, WIN_H, SUB_W, SUB_H, SUB_X, SUB_Y, gl_stereo);
   fflush(stdout);

   /* A new frame number in both views on every swap, until the time is up. */
   const char *hold = getenv("HOLD_SECONDS");
   const time_t end = time(NULL) + (hold ? atoi(hold) : 8);
   while (time(NULL) < end) {
      frame++;
      if (stereo) {
         draw_eye(GL_BACK_LEFT, 1.0f, 0.0f, frame);
         draw_eye(GL_BACK_RIGHT, 0.0f, 1.0f, frame);
      } else {
         draw_eye(GL_BACK, 1.0f, 0.0f, frame);
      }
      glFinish();
      assert(eglSwapBuffers(egl, egl_surface));
      wl_display_dispatch_pending(display);
   }
   printf("frames=%u\n", frame);
   return 0;
}
