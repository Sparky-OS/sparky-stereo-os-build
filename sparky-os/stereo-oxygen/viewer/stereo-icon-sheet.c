/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * stereo-icon-sheet: shows the Stereo Oxygen test icons in a two-view Wayland EGL window (one top-level
 * surface, EGL_MULTIVIEW_VIEW_COUNT_EXT 2, GL_BACK_LEFT / GL_BACK_RIGHT), which our Mesa packs and declares
 * and our KWin shows one view to each eye.
 *
 * The sheet is composed on the CPU once for each eye on a mid-grey background and drawn 1:1 (nearest, never
 * scaled): the left half of every stereo cell goes to the left view, the right half to the right view; the
 * plain Oxygen picture and everything else is identical in both views.
 *
 * Assets folder (default: "assets" next to the program): list.txt (one name per line, the row order),
 * <variant>/<size>/<name>.png with variant plain (N x N), A2 A4 A6 B2 B4 B6 (2N x N, left view first), and
 * <variant>/<size>/<name>.probe-front.png / .probe-back.png for page 4.
 *
 * Pages (keys 1 2 3 4, Tab cycles, arrows and Page Up/Down scroll, Esc or q quits):
 *   1: the 128 pixel icons, one row per icon: plain, A2 A4 A6, B2 B4 B6, C2 C4 C6
 *   2: the 32 and 48 pixel versions at their real size, the same columns
 *   3: the 256 pixel icons
 *   4: the front and back parts alone (measurement probes, for the proofs by script)
 *
 * Two ways to reach the compositor, chosen automatically (or with --path):
 *   multiview: our Mesa's EGL_EXT_multiview_window, a two-view window surface (GL_BACK_LEFT / GL_BACK_RIGHT); Mesa packs
 *              and declares it.
 *   declare:   any Mesa: an ordinary one-view EGL window surface whose buffer holds both views side by side (left view in
 *              the left half, right view in the right half, each at the sheet's size, so the buffer is twice as wide as
 *              the window); the window's size is one view (wp_viewporter destination), and the surface is declared full
 *              side by side, left eye first, through kde_stereo_content_manager_v1 (KWin).
 *
 * Plain C, EGL, Wayland, libpng.
 */

#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <png.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <libgen.h>
#include <limits.h>

#include <wayland-client.h>
#include <wayland-egl.h>
#include "xdg-shell-client-protocol.h"
#include "viewporter-client-protocol.h"
#include "kde-stereo-content-client-protocol.h"

#define BG 128
#define MARGIN 24
#define GAP 16
#define MAXROWS 32
#define NVARIANTS 10

static const char *variants[NVARIANTS] = { "plain", "A2", "A4", "A6", "B2", "B4", "B6", "C2", "C4", "C6" };
static const char *variant_labels[NVARIANTS] = { "PLAIN", "A 2%", "A 4%", "A 6%", "B 2%", "B 4%", "B 6%", "C 2%", "C 4%", "C 6%" };

/* ---- a 5x7 font for the column labels (identical in both eyes) ---- */
struct glyph { char c; uint8_t rows[7]; };
static const struct glyph font[] = {
   { ' ', { 0, 0, 0, 0, 0, 0, 0 } },
   { 'A', { 0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11 } },
   { 'B', { 0x1e, 0x11, 0x11, 0x1e, 0x11, 0x11, 0x1e } },
   { 'C', { 0x0e, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0e } },
   { 'I', { 0x0e, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0e } },
   { 'L', { 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1f } },
   { 'N', { 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11 } },
   { 'P', { 0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10 } },
   { 'F', { 0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x10 } },
   { 'R', { 0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11 } },
   { 'O', { 0x0e, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0e } },
   { 'T', { 0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04 } },
   { 'K', { 0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11 } },
   { 'X', { 0x11, 0x11, 0x0a, 0x04, 0x0a, 0x11, 0x11 } },
   { 'S', { 0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e } },
   { '%', { 0x19, 0x19, 0x02, 0x04, 0x08, 0x13, 0x13 } },
   { '0', { 0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e } },
   { '1', { 0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e } },
   { '2', { 0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f } },
   { '3', { 0x1f, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0e } },
   { '4', { 0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02 } },
   { '5', { 0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e } },
   { '6', { 0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e } },
   { '7', { 0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 } },
   { '8', { 0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e } },
   { '9', { 0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c } },
};

struct image { int w, h; uint8_t *rgba; };

struct cell { int page; char variant[16]; char name[96]; int size; int x, y, w, h; };

struct sheet {
   int w, h;
   uint8_t *eye[2];         /* RGBA, opaque */
   struct cell *cells;
   int ncells, capcells;
};

static const char *assets = NULL;
static char *names[MAXROWS];
static int nnames;
static int probe_size = 128;

static void die(const char *msg, const char *arg)
{
   fprintf(stderr, "stereo-icon-sheet: %s%s%s\n", msg, arg ? ": " : "", arg ? arg : "");
   exit(1);
}

static bool load_png(const char *path, struct image *im)
{
   png_image p;
   memset(&p, 0, sizeof p);
   p.version = PNG_IMAGE_VERSION;
   if (!png_image_begin_read_from_file(&p, path))
      return false;
   p.format = PNG_FORMAT_RGBA;
   im->w = p.width;
   im->h = p.height;
   im->rgba = malloc(PNG_IMAGE_SIZE(p));
   if (!im->rgba || !png_image_finish_read(&p, NULL, im->rgba, 0, NULL)) {
      png_image_free(&p);
      free(im->rgba);
      return false;
   }
   return true;
}

/* ---- composing ---- */
static void fill(struct sheet *s)
{
   for (int e = 0; e < 2; e++)
      for (size_t i = 0; i < (size_t)s->w * s->h; i++) {
         s->eye[e][i * 4 + 0] = s->eye[e][i * 4 + 1] = s->eye[e][i * 4 + 2] = BG;
         s->eye[e][i * 4 + 3] = 255;
      }
}

static void put_pixel(struct sheet *s, int e, int x, int y, const uint8_t *p)
{
   if (x < 0 || y < 0 || x >= s->w || y >= s->h)
      return;
   uint8_t *d = s->eye[e] + ((size_t)y * s->w + x) * 4;
   const int a = p[3];
   for (int c = 0; c < 3; c++)
      d[c] = (uint8_t)((p[c] * a + BG * (255 - a) + 127) / 255);
}

/* eye: 0 left, 1 right; half: which half of the picture's width starts at src_x */
static void blit(struct sheet *s, int e, const struct image *im, int src_x, int w, int dx, int dy)
{
   for (int y = 0; y < im->h; y++)
      for (int x = 0; x < w; x++)
         put_pixel(s, e, dx + x, dy + y, im->rgba + ((size_t)y * im->w + src_x + x) * 4);
}

static void text(struct sheet *s, int x, int y, const char *str, int scale)
{
   for (; *str; str++, x += 6 * scale) {
      for (size_t g = 0; g < sizeof font / sizeof font[0]; g++) {
         if (font[g].c != *str)
            continue;
         for (int r = 0; r < 7; r++)
            for (int c = 0; c < 5; c++)
               if (font[g].rows[r] & (0x10 >> c))
                  for (int e = 0; e < 2; e++)
                     for (int yy = 0; yy < scale; yy++)
                        for (int xx = 0; xx < scale; xx++) {
                           const uint8_t ink[4] = { 20, 20, 20, 255 };
                           put_pixel(s, e, x + c * scale + xx, y + r * scale + yy, ink);
                        }
      }
   }
}

static void add_cell(struct sheet *s, int page, const char *variant, const char *name, int size, int x, int y, int w, int h)
{
   if (s->ncells == s->capcells) {
      s->capcells = s->capcells ? 2 * s->capcells : 64;
      s->cells = realloc(s->cells, s->capcells * sizeof *s->cells);
   }
   struct cell *c = &s->cells[s->ncells++];
   c->page = page;
   snprintf(c->variant, sizeof c->variant, "%s", variant);
   snprintf(c->name, sizeof c->name, "%s", name);
   c->size = size; c->x = x; c->y = y; c->w = w; c->h = h;
}

/* One cell: the plain picture (same in both eyes) or a stereo picture (left half to the left view, right half to the right). */
static void place(struct sheet *s, int page, const char *variant, const char *name, int size, const char *suffix, int x, int y)
{
   char path[PATH_MAX];
   struct image im;
   snprintf(path, sizeof path, "%s/%s/%d/%s%s.png", assets, variant, size, name, suffix);
   if (!load_png(path, &im))
      die("cannot read", path);
   if (!strcmp(variant, "plain")) {
      /* Oxygen's own PNG is not always exactly N x N (48/printer.png is 48 x 46): shown at its own size, centred in the cell */
      if (im.w > size || im.h > size)
         die("plain picture is larger than its cell", path);
      blit(s, 0, &im, 0, im.w, x + (size - im.w) / 2, y + (size - im.h) / 2);
      blit(s, 1, &im, 0, im.w, x + (size - im.w) / 2, y + (size - im.h) / 2);
   } else {
      if (im.w != 2 * size || im.h != size)
         die("stereo picture is not 2N x N", path);
      blit(s, 0, &im, 0, size, x, y);
      blit(s, 1, &im, size, size, x, y);
   }
   add_cell(s, page, variant, name, size, x, y, size, size);
   free(im.rgba);
}

static struct sheet *build_page(int page)
{
   struct sheet *s = calloc(1, sizeof *s);
   const int hdr = 24;
   if (page == 1 || page == 3) {
      const int n = page == 1 ? 128 : 256;
      s->w = 2 * MARGIN + NVARIANTS * n + (NVARIANTS - 1) * GAP;
      s->h = 2 * MARGIN + hdr + nnames * n + (nnames - 1) * GAP;
   } else if (page == 2) {
      s->w = 2 * MARGIN + NVARIANTS * (32 + 48) + (2 * NVARIANTS - 2) * GAP + 3 * GAP;
      s->h = 2 * MARGIN + hdr + nnames * 48 + (nnames - 1) * GAP;
   } else {
      /* probes: a flow of cells, front then back, for every variant but plain, wrapping at 2048 */
      s->w = 2048;
      const int per = (s->w - 2 * MARGIN + GAP) / (probe_size + GAP);
      const int total = nnames * (NVARIANTS - 1) * 2;
      const int rows = (total + per - 1) / per;
      s->h = 2 * MARGIN + rows * probe_size + (rows - 1) * GAP;
   }
   for (int e = 0; e < 2; e++)
      s->eye[e] = malloc((size_t)s->w * s->h * 4);
   fill(s);

   if (page == 1 || page == 3) {
      const int n = page == 1 ? 128 : 256;
      for (int v = 0; v < NVARIANTS; v++)
         text(s, MARGIN + v * (n + GAP), MARGIN, variant_labels[v], 2);
      for (int r = 0; r < nnames; r++)
         for (int v = 0; v < NVARIANTS; v++)
            place(s, page, variants[v], names[r], n, "", MARGIN + v * (n + GAP), MARGIN + hdr + r * (n + GAP));
   } else if (page == 2) {
      for (int g = 0; g < 2; g++) {
         const int n = g ? 48 : 32;
         const int x0 = MARGIN + (g ? NVARIANTS * (32 + GAP) + 3 * GAP : 0);
         for (int v = 0; v < NVARIANTS; v++) {
            char label[32];
            snprintf(label, sizeof label, "%s", variant_labels[v]);
            text(s, x0 + v * (n + GAP), MARGIN, label, 1);
            for (int r = 0; r < nnames; r++)
               place(s, page, variants[v], names[r], n, "", x0 + v * (n + GAP), MARGIN + hdr + r * (48 + GAP) + (48 - n) / 2);
         }
         text(s, x0, MARGIN + 10, g ? "48" : "32", 1);
      }
   } else {
      const int per = (s->w - 2 * MARGIN + GAP) / (probe_size + GAP);
      int i = 0;
      for (int r = 0; r < nnames; r++)
         for (int v = 1; v < NVARIANTS; v++)
            for (int t = 0; t < 2; t++, i++)
               place(s, page, variants[v], names[r], probe_size, t ? ".probe-back" : ".probe-front",
                     MARGIN + (i % per) * (probe_size + GAP), MARGIN + (i / per) * (probe_size + GAP));
   }
   return s;
}

static void free_sheet(struct sheet *s)
{
   if (!s)
      return;
   free(s->eye[0]); free(s->eye[1]); free(s->cells); free(s);
}

static void write_layout(const char *file, const struct sheet *s)
{
   FILE *f = fopen(file, "w");
   if (!f)
      die("cannot write", file);
   fprintf(f, "sheet\t%d\t%d\n", s->w, s->h);
   for (int i = 0; i < s->ncells; i++) {
      const struct cell *c = &s->cells[i];
      fprintf(f, "cell\t%d\t%s\t%s\t%d\t%d\t%d\t%d\t%d\n", c->page, c->variant, c->name, c->size, c->x, c->y, c->w, c->h);
   }
   fclose(f);
}

static void read_list(void)
{
   char path[PATH_MAX], line[256];
   snprintf(path, sizeof path, "%s/list.txt", assets);
   FILE *f = fopen(path, "r");
   if (!f)
      die("cannot read", path);
   while (fgets(line, sizeof line, f) && nnames < MAXROWS) {
      line[strcspn(line, "\r\n")] = 0;
      if (line[0] && line[0] != '#')
         names[nnames++] = strdup(line);
   }
   fclose(f);
   if (!nnames)
      die("empty list", path);
}

/* ---- Wayland ---- */
struct state {
   struct wl_compositor *compositor;
   struct wl_seat *seat;
   struct xdg_wm_base *wm_base;
   struct wl_keyboard *keyboard;
   struct wp_viewporter *viewporter;
   struct kde_stereo_content_manager_v1 *stereo;
   bool configured, closed;
   int want_w, want_h;     /* size the compositor asked for, 0 if none */
   int key_page, key_dx, key_dy, key_quit;
};

static void wm_ping(void *d, struct xdg_wm_base *b, uint32_t serial) { (void)d; xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_listener = { .ping = wm_ping };

static void surface_configure(void *d, struct xdg_surface *s, uint32_t serial)
{
   struct state *st = d;
   xdg_surface_ack_configure(s, serial);
   st->configured = true;
}
static const struct xdg_surface_listener surface_listener = { .configure = surface_configure };

static void toplevel_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *states)
{
   struct state *st = d;
   (void)t; (void)states;
   st->want_w = w;
   st->want_h = h;
}
static void toplevel_close(void *d, struct xdg_toplevel *t) { struct state *st = d; (void)t; st->closed = true; }
static const struct xdg_toplevel_listener toplevel_listener = { .configure = toplevel_configure, .close = toplevel_close };

enum { K_ESC = 1, K_1 = 2, K_2 = 3, K_3 = 4, K_4 = 5, K_TAB = 15, K_Q = 16, K_HOME = 102, K_UP = 103,
       K_PGUP = 104, K_LEFT = 105, K_RIGHT = 106, K_DOWN = 108, K_PGDN = 109 };

static void kb_keymap(void *d, struct wl_keyboard *k, uint32_t f, int fd, uint32_t sz) { (void)d; (void)k; (void)f; (void)sz; close(fd); }
static void kb_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *su, struct wl_array *keys) { (void)d; (void)k; (void)s; (void)su; (void)keys; }
static void kb_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *su) { (void)d; (void)k; (void)s; (void)su; }
static void kb_mods(void *d, struct wl_keyboard *k, uint32_t s, uint32_t a, uint32_t b, uint32_t c, uint32_t g) { (void)d; (void)k; (void)s; (void)a; (void)b; (void)c; (void)g; }
static void kb_repeat(void *d, struct wl_keyboard *k, int32_t r, int32_t dl) { (void)d; (void)k; (void)r; (void)dl; }
static void kb_key(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t time, uint32_t key, uint32_t state)
{
   struct state *st = d;
   (void)k; (void)serial; (void)time;
   if (state != WL_KEYBOARD_KEY_STATE_PRESSED)
      return;
   switch (key) {
   case K_ESC: case K_Q: st->key_quit = 1; break;
   case K_1: st->key_page = 1; break;
   case K_2: st->key_page = 2; break;
   case K_3: st->key_page = 3; break;
   case K_4: st->key_page = 4; break;
   case K_TAB: st->key_page = -1; break;
   case K_UP: st->key_dy = -64; break;
   case K_DOWN: st->key_dy = 64; break;
   case K_PGUP: st->key_dy = -512; break;
   case K_PGDN: st->key_dy = 512; break;
   case K_LEFT: st->key_dx = -64; break;
   case K_RIGHT: st->key_dx = 64; break;
   case K_HOME: st->key_dx = st->key_dy = -100000; break;
   }
}
static const struct wl_keyboard_listener kb_listener = {
   .keymap = kb_keymap, .enter = kb_enter, .leave = kb_leave, .key = kb_key, .modifiers = kb_mods, .repeat_info = kb_repeat,
};

static void seat_caps(void *d, struct wl_seat *seat, uint32_t caps)
{
   struct state *st = d;
   if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !st->keyboard) {
      st->keyboard = wl_seat_get_keyboard(seat);
      wl_keyboard_add_listener(st->keyboard, &kb_listener, st);
   }
}
static void seat_name(void *d, struct wl_seat *s, const char *n) { (void)d; (void)s; (void)n; }
static const struct wl_seat_listener seat_listener = { .capabilities = seat_caps, .name = seat_name };

static void registry_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version)
{
   struct state *st = d;
   if (!strcmp(iface, wl_compositor_interface.name))
      st->compositor = wl_registry_bind(r, name, &wl_compositor_interface, version < 4 ? version : 4);
   else if (!strcmp(iface, xdg_wm_base_interface.name))
      st->wm_base = wl_registry_bind(r, name, &xdg_wm_base_interface, version < 3 ? version : 3);
   else if (!strcmp(iface, wp_viewporter_interface.name))
      st->viewporter = wl_registry_bind(r, name, &wp_viewporter_interface, 1);
   else if (!strcmp(iface, kde_stereo_content_manager_v1_interface.name))
      st->stereo = wl_registry_bind(r, name, &kde_stereo_content_manager_v1_interface, 1);
   else if (!strcmp(iface, wl_seat_interface.name) && !st->seat) {
      st->seat = wl_registry_bind(r, name, &wl_seat_interface, version < 5 ? version : 5);
      wl_seat_add_listener(st->seat, &seat_listener, st);
   }
}
static void registry_remove(void *d, struct wl_registry *r, uint32_t name) { (void)d; (void)r; (void)name; }
static const struct wl_registry_listener registry_listener = { .global = registry_global, .global_remove = registry_remove };

/* ---- drawing ---- */
static GLuint tex[2];

static void upload(const struct sheet *s)
{
   if (!tex[0])
      glGenTextures(2, tex);
   for (int e = 0; e < 2; e++) {
      glBindTexture(GL_TEXTURE_2D, tex[e]);
      glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, s->w, s->h, 0, GL_RGBA, GL_UNSIGNED_BYTE, s->eye[e]);
   }
}

/* buffer: GL_BACK_LEFT / GL_BACK_RIGHT (multiview) or GL_BACK; xoff: where this eye's half starts in the buffer */
static void draw_eye(GLenum buffer, int e, const struct sheet *s, int win_w, int win_h, int sx, int sy, int xoff)
{
   glDrawBuffer(buffer);
   glViewport(xoff, 0, win_w, win_h);
   glDisable(GL_DITHER);
   glDisable(GL_BLEND);
   glDisable(GL_LIGHTING);
   glEnable(GL_SCISSOR_TEST);
   glScissor(xoff, 0, win_w, win_h);
   glClearColor(BG / 255.0f, BG / 255.0f, BG / 255.0f, 1.0f);
   glClear(GL_COLOR_BUFFER_BIT);
   glMatrixMode(GL_PROJECTION);
   glLoadIdentity();
   glOrtho(0, win_w, win_h, 0, -1, 1);
   glMatrixMode(GL_MODELVIEW);
   glLoadIdentity();
   glEnable(GL_TEXTURE_2D);
   glBindTexture(GL_TEXTURE_2D, tex[e]);
   glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
   glColor4f(1, 1, 1, 1);
   const float x0 = (float)-sx, y0 = (float)-sy, x1 = x0 + s->w, y1 = y0 + s->h;
   glBegin(GL_QUADS);
   glTexCoord2f(0, 0); glVertex2f(x0, y0);
   glTexCoord2f(1, 0); glVertex2f(x1, y0);
   glTexCoord2f(1, 1); glVertex2f(x1, y1);
   glTexCoord2f(0, 1); glVertex2f(x0, y1);
   glEnd();
   glDisable(GL_TEXTURE_2D);
   glDisable(GL_SCISSOR_TEST);
}

static void usage(void)
{
   puts("usage: stereo-icon-sheet [--assets DIR] [--page 1|2|3|4] [--size WxH] [--probe-size N] [--layout FILE] [--hold SECONDS]\n"
        "                         [--path auto|multiview|declare]\n"
        "  1: icons at 128 px   2: 32 and 48 px at their real size   3: 256 px   4: front/back part probes (for proofs)\n"
        "  keys: 1 2 3 4 or Tab change page; arrows, Page Up/Down, Home scroll; Esc or q quits.\n"
        "  --path: multiview needs EGL_EXT_multiview_window (our Mesa); declare works on any Mesa under our KWin; default auto\n"
        "  columns: plain Oxygen, rules A, B and C at 2/4/6 %. Default window size: the sheet's size.");
}

int main(int argc, char **argv)
{
   int page = 1, req_w = 0, req_h = 0, hold = 0;
   const char *layout = NULL, *path_opt = "auto";
   static char self[PATH_MAX], defassets[PATH_MAX];
   for (int i = 1; i < argc; i++) {
      if (!strcmp(argv[i], "--assets") && i + 1 < argc) assets = argv[++i];
      else if (!strcmp(argv[i], "--page") && i + 1 < argc) page = atoi(argv[++i]);
      else if (!strcmp(argv[i], "--size") && i + 1 < argc) { if (sscanf(argv[++i], "%dx%d", &req_w, &req_h) != 2) die("bad --size", argv[i]); }
      else if (!strcmp(argv[i], "--probe-size") && i + 1 < argc) probe_size = atoi(argv[++i]);
      else if (!strcmp(argv[i], "--layout") && i + 1 < argc) layout = argv[++i];
      else if (!strcmp(argv[i], "--path") && i + 1 < argc) path_opt = argv[++i];
      else if (!strcmp(argv[i], "--hold") && i + 1 < argc) hold = atoi(argv[++i]);
      else { usage(); return !strcmp(argv[i], "--help") ? 0 : 2; }
   }
   if (!assets) {
      ssize_t n = readlink("/proc/self/exe", self, sizeof self - 1);
      if (n > 0) { self[n] = 0; snprintf(defassets, sizeof defassets, "%s/assets", dirname(self)); assets = defassets; }
      else assets = "assets";
   }
   if (page < 1 || page > 4) die("page must be 1 to 4", NULL);
   read_list();

   struct sheet *sheet = build_page(page);
   if (layout) write_layout(layout, sheet);
   int win_w = req_w ? req_w : sheet->w, win_h = req_h ? req_h : sheet->h;

   struct state st = {0};
   struct wl_display *display = wl_display_connect(NULL);
   if (!display) die("no Wayland display", NULL);
   struct wl_registry *registry = wl_display_get_registry(display);
   wl_registry_add_listener(registry, &registry_listener, &st);
   wl_display_roundtrip(display);
   wl_display_roundtrip(display);
   if (!st.compositor || !st.wm_base) die("compositor lacks wl_compositor or xdg_wm_base", NULL);
   xdg_wm_base_add_listener(st.wm_base, &wm_listener, &st);

   struct wl_surface *surface = wl_compositor_create_surface(st.compositor);
   struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(st.wm_base, surface);
   struct xdg_toplevel *top = xdg_surface_get_toplevel(xs);
   xdg_surface_add_listener(xs, &surface_listener, &st);
   xdg_toplevel_add_listener(top, &toplevel_listener, &st);
   xdg_toplevel_set_title(top, "Stereo Oxygen icon sheet");
   xdg_toplevel_set_app_id(top, "stereo-icon-sheet");
   wl_surface_commit(surface);
   while (!st.configured)
      if (wl_display_dispatch(display) < 0) die("display error", NULL);
   if (!req_w && st.want_w > 0) win_w = st.want_w;
   if (!req_h && st.want_h > 0) win_h = st.want_h;

   EGLDisplay egl = eglGetPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, display, NULL);
   if (egl == EGL_NO_DISPLAY || !eglInitialize(egl, NULL, NULL) || !eglBindAPI(EGL_OPENGL_API))
      die("EGL initialisation failed", NULL);
   const char *ext = eglQueryString(egl, EGL_EXTENSIONS);
   const bool has_multiview = ext && strstr(ext, "EGL_EXT_multiview_window");
   bool multiview;
   if (!strcmp(path_opt, "auto")) multiview = has_multiview;
   else if (!strcmp(path_opt, "multiview")) multiview = true;
   else if (!strcmp(path_opt, "declare")) multiview = false;
   else die("--path must be auto, multiview or declare", path_opt);
   struct wp_viewport *viewport = NULL;
   struct kde_stereo_content_v1 *declaration = NULL;
   if (multiview) {
      if (!has_multiview)
         die("this EGL has no EGL_EXT_multiview_window; use --path declare (or auto)", NULL);
   } else {
      if (!st.viewporter || !st.stereo)
         die("the compositor lacks wp_viewporter or kde_stereo_content_manager_v1 (our KWin is needed)", NULL);
      viewport = wp_viewporter_get_viewport(st.viewporter, surface);
      wp_viewport_set_destination(viewport, win_w, win_h);
      declaration = kde_stereo_content_manager_v1_create(st.stereo, surface);
      kde_stereo_content_v1_set_content(declaration, KDE_STEREO_CONTENT_V1_CONTENT_SIDE_BY_SIDE_FULL);
   }
   struct wl_egl_window *window = wl_egl_window_create(surface, multiview ? win_w : 2 * win_w, win_h);
   const EGLint cfg_attrs[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
                                EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE };
   EGLConfig config;
   EGLint count;
   if (!eglChooseConfig(egl, cfg_attrs, &config, 1, &count) || count != 1)
      die("no EGL config", NULL);
   const EGLint surf_attrs[] = { EGL_MULTIVIEW_VIEW_COUNT_EXT, 2, EGL_NONE };
   EGLSurface esurf = eglCreateWindowSurface(egl, config, (EGLNativeWindowType)window, multiview ? surf_attrs : NULL);
   if (esurf == EGL_NO_SURFACE)
      die("cannot create the window surface", NULL);
   EGLContext ctx = eglCreateContext(egl, config, EGL_NO_CONTEXT, NULL);
   if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(egl, esurf, esurf, ctx))
      die("cannot make the GL context current", NULL);
   GLint gl_stereo = 0;
   glGetIntegerv(GL_STEREO, &gl_stereo);
   if (multiview && !gl_stereo)
      die("the surface is not a two-view surface (GL_STEREO is 0)", NULL);
   eglSwapInterval(egl, 0);

   int sx = 0, sy = 0;
   bool dirty = true;
   upload(sheet);
   printf("window=%dx%d sheet=%dx%d page=%d cells=%d path=%s gl_stereo=%d buffer=%dx%d\n", win_w, win_h, sheet->w, sheet->h, page, sheet->ncells,
          multiview ? "multiview" : "declare", gl_stereo, multiview ? win_w : 2 * win_w, win_h);
   fflush(stdout);
   const time_t end = hold ? time(NULL) + hold : 0;
   while (!st.closed && !st.key_quit && (!end || time(NULL) < end)) {
      if (dirty) {
         if (multiview) {
            draw_eye(GL_BACK_LEFT, 0, sheet, win_w, win_h, sx, sy, 0);
            draw_eye(GL_BACK_RIGHT, 1, sheet, win_w, win_h, sx, sy, 0);
         } else {
            glDrawBuffer(GL_BACK);
            glDisable(GL_SCISSOR_TEST);
            glClearColor(BG / 255.0f, BG / 255.0f, BG / 255.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            draw_eye(GL_BACK, 0, sheet, win_w, win_h, sx, sy, 0);
            draw_eye(GL_BACK, 1, sheet, win_w, win_h, sx, sy, win_w);
         }
         glFinish(); /* Mesa's multiview swap packs before the draw is flushed */
         if (!eglSwapBuffers(egl, esurf))
            die("eglSwapBuffers failed", NULL);
         dirty = false;
      }
      /* wait for events, but wake once a second so --hold ends and a lost frame is redrawn */
      while (wl_display_prepare_read(display) != 0)
         wl_display_dispatch_pending(display);
      wl_display_flush(display);
      struct { int fd; } pf = { wl_display_get_fd(display) };
      fd_set rs;
      FD_ZERO(&rs);
      FD_SET(pf.fd, &rs);
      struct timeval tv = { 1, 0 };
      if (select(pf.fd + 1, &rs, NULL, NULL, &tv) > 0)
         wl_display_read_events(display);
      else
         wl_display_cancel_read(display);
      wl_display_dispatch_pending(display);

      if (st.want_w > 0 && st.want_h > 0 && (st.want_w != win_w || st.want_h != win_h) && !req_w) {
         win_w = st.want_w; win_h = st.want_h;
         wl_egl_window_resize(window, multiview ? win_w : 2 * win_w, win_h, 0, 0);
         if (viewport) wp_viewport_set_destination(viewport, win_w, win_h);
         dirty = true;
      }
      if (st.key_page) {
         int np = st.key_page < 0 ? page % 4 + 1 : st.key_page;
         st.key_page = 0;
         if (np != page) {
            struct sheet *ns = build_page(np);
            free_sheet(sheet);
            sheet = ns;
            page = np;
            sx = sy = 0;
            upload(sheet);
            dirty = true;
         }
      }
      if (st.key_dx || st.key_dy) {
         sx += st.key_dx; sy += st.key_dy;
         st.key_dx = st.key_dy = 0;
         int mx = sheet->w - win_w, my = sheet->h - win_h;
         if (mx < 0) mx = 0;
         if (my < 0) my = 0;
         if (sx < 0) sx = 0;
         if (sy < 0) sy = 0;
         if (sx > mx) sx = mx;
         if (sy > my) sy = my;
         dirty = true;
      }
      /* the compositor may ask for a new frame by showing the window again; a cheap periodic redraw keeps it alive */
      static time_t last;
      if (time(NULL) != last) { last = time(NULL); dirty = true; }
   }
   return 0;
}
