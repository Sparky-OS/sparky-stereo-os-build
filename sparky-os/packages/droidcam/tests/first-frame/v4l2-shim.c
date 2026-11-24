/* Created by Daniel Ramos (Capitain Jack) 2026/11/24 (count at every frame and SHIM_SIZE: 2026/11/24, after the main session's review copy)
 * Copyright 2026 under the GNU GPL3 License
 * Sparky Stereo OS: a stand-in for a v4l2loopback device, loaded with LD_PRELOAD into droidcam-cli whose -dev is /dev/null: it answers
 * the client's V4L2 questions (640x480 YU12 on "platform:v4l2loopback-000") and counts the frames the client writes
 * into the file named by SHIM_COUNT_FILE at every frame and when the client ends, so a running client can be read.
 * The device is /dev/null, or any /dev/video* node of the test container. SHIM_SIZE=WxH (default 640x480) is the size the device answers. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static volatile long frames;
static int dev_w = 640, dev_h = 480;
#define FRAME_BYTES (dev_w * dev_h * 3 / 2)

__attribute__((constructor)) static void init(void) {
    const char *size = getenv("SHIM_SIZE");
    int w, h;
    if (size && sscanf(size, "%dx%d", &w, &h) == 2) {
        dev_w = w;
        dev_h = h;
    }
}

static int is_null_device(int fd) {
    char link[64], target[64];
    snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(link, target, sizeof(target) - 1);
    if (n < 0) return 0;
    target[n] = 0;
    return strcmp(target, "/dev/null") == 0 || strncmp(target, "/dev/video", 10) == 0;
}

int ioctl(int fd, unsigned long req, ...) {
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    if (!is_null_device(fd)) {
        int (*real)(int, unsigned long, ...) = dlsym(RTLD_NEXT, "ioctl");
        return real(fd, req, arg);
    }
    req = (unsigned int) req; /* the client's xioctl takes an int, so the request arrives sign extended */
    if (req == VIDIOC_QUERYCAP) {
        struct v4l2_capability *cap = arg;
        memset(cap, 0, sizeof(*cap));
        strcpy((char *) cap->driver, "v4l2 loopback");
        strcpy((char *) cap->card, "Test camera");
        strcpy((char *) cap->bus_info, "platform:v4l2loopback-000");
        return 0;
    }
    if (req == VIDIOC_G_FMT || req == VIDIOC_S_FMT) {
        struct v4l2_format *f = arg;
        f->fmt.pix.width = dev_w;
        f->fmt.pix.height = dev_h;
        f->fmt.pix.pixelformat = V4L2_PIX_FMT_YUV420;
        f->fmt.pix.field = V4L2_FIELD_NONE;
        f->fmt.pix.bytesperline = dev_w;
        f->fmt.pix.sizeimage = FRAME_BYTES;
        return 0;
    }
    errno = EINVAL;
    return -1;
}

static void write_count(void) {
    const char *path = getenv("SHIM_COUNT_FILE");
    if (!path) return;
    char line[32];
    int n = snprintf(line, sizeof(line), "%ld\n", frames);
    int out = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out >= 0) {
        ssize_t (*real)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
        real(out, line, n);
        close(out);
    }
}

ssize_t write(int fd, const void *buf, size_t count) {
    ssize_t (*real)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    if (count == (size_t) FRAME_BYTES && is_null_device(fd)) {
        frames++;
        write_count();
    }
    return real(fd, buf, count);
}

__attribute__((destructor)) static void report(void) {
    write_count();
}
