// SPDX-License-Identifier: GPL-2.0-or-later
// Test mutation: the old state never declares the greeter's pixel background.
int stereo_declare_wayland_format(void *surface, int content)
{
    (void)surface; (void)content;
    return 0;
}
