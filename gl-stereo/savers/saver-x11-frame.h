/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef SAVER_X11_FRAME_H
#define SAVER_X11_FRAME_H
#include <X11/Xlib.h>
void saver_x11_frame(Display *display, Window window, unsigned width, unsigned height);
#endif
