/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include "saver-x11-frame.h"
#include <X11/Xutil.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static unsigned char component(unsigned long pixel, unsigned long mask)
{
    if (!mask) return 0;
    while (!(mask & 1)) { mask >>= 1; pixel >>= 1; }
    return (pixel & mask) * 255 / mask;
}
void saver_x11_frame(Display *display, Window window, unsigned width, unsigned height)
{
    static int fd = -2, pending;
    static uint32_t sequence;
    if (fd == -2) {
        const char *value = getenv("GL_STEREO_FRAME_FD");
        fd = value ? atoi(value) : -1;
        if (fd < 3) fd = -1;
    }
    if (fd < 0 || !width || !height || width > 8192 || height > 4096 || (uint64_t)width * height * 4 > 67108864) return;
    if (pending) {
        uint32_t ack;
        ssize_t n = recv(fd, &ack, sizeof(ack), MSG_DONTWAIT);
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
        if (n != sizeof(ack) || le32toh(ack) != sequence) { fd = -1; return; }
        pending = 0;
    }
    size_t bytes = (size_t)width * height * 4;
    int memory = memfd_create("gl-stereo-rocks", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (memory < 0) return;
    if (ftruncate(memory, bytes)) { close(memory); return; }
    unsigned char *pixels = mmap(NULL, bytes, PROT_WRITE | PROT_READ, MAP_SHARED, memory, 0);
    if (pixels == MAP_FAILED) { close(memory); return; }
    XImage *image = XGetImage(display, window, 0, 0, width, height, AllPlanes, ZPixmap);
    if (!image) { munmap(pixels, bytes); close(memory); return; }
    for (unsigned y = 0; y < height; ++y) for (unsigned x = 0; x < width; ++x) {
        unsigned long pixel = XGetPixel(image, x, y);
        unsigned char *p = pixels + ((height - 1 - y) * width + x) * 4;
        p[0] = component(pixel, image->red_mask); p[1] = component(pixel, image->green_mask);
        p[2] = component(pixel, image->blue_mask); p[3] = 255;
    }
    XDestroyImage(image); munmap(pixels, bytes);
    if (fcntl(memory, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) { close(memory); return; }
    uint32_t header[] = {htole32(0x46334453), htole32(1), htole32(width), htole32(height),
                         htole32(width * 4), htole32(++sequence), htole32(bytes), htole32(1)};
    struct iovec io = {header, sizeof(header)};
    union { struct cmsghdr align; char bytes[CMSG_SPACE(sizeof(int))]; } control = {0};
    struct msghdr msg = {0};
    msg.msg_iov = &io; msg.msg_iovlen = 1; msg.msg_control = control.bytes; msg.msg_controllen = sizeof(control.bytes);
    struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
    c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &memory, sizeof(memory));
    if (sendmsg(fd, &msg, MSG_DONTWAIT | MSG_NOSIGNAL) == sizeof(header)) pending = 1;
    else if (errno != EAGAIN && errno != EWOULDBLOCK) fd = -1;
    close(memory);
}
