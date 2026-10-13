/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <stereo-declare.h>

int stereo_declare_x11_format(Display *display, Window window, enum stereo_layout layout)
{
    return stereo_declare_x11(display, window, layout, STEREO_CLASS_NONE, 0);
}
