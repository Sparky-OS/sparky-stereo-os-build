// SPDX-License-Identifier: GPL-3.0-or-later
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int mock_fd = -1;
static FILE *trace;

int open(const char *path, int flags, ...)
{
    int (*real_open)(const char *, int, ...) = dlsym(RTLD_NEXT, "open");
    if (strcmp(path, "/dev/uinput") != 0) {
        if (flags & O_CREAT) {
            va_list args;
            va_start(args, flags);
            int mode = va_arg(args, int);
            va_end(args);
            return real_open(path, flags, mode);
        }
        return real_open(path, flags);
    }
    trace = fopen(getenv("FT37_TRACE"), "w");
    if (!trace)
        abort();
    setvbuf(trace, NULL, _IOLBF, 0);
    fprintf(trace, "OPEN %s %d\n", path, flags & O_ACCMODE);
    mock_fd = real_open("/dev/null", flags);
    return mock_fd;
}

int ioctl(int fd, unsigned long request, ...)
{
    if (fd != mock_fd) {
        errno = ENOTTY;
        return -1;
    }
    va_list args;
    va_start(args, request);
    switch (request) {
    case UI_SET_EVBIT:
        fprintf(trace, "EVBIT %d\n", va_arg(args, int));
        break;
    case UI_SET_ABSBIT:
        fprintf(trace, "ABSBIT %d\n", va_arg(args, int));
        break;
    case UI_ABS_SETUP: {
        const struct uinput_abs_setup *axis = va_arg(args, void *);
        fprintf(trace, "ABSSETUP %u %d %d\n", axis->code,
                axis->absinfo.minimum, axis->absinfo.maximum);
        break;
    }
    case UI_SET_KEYBIT:
        fprintf(trace, "KEYBIT %d\n", va_arg(args, int));
        break;
    case UI_DEV_SETUP: {
        const struct uinput_setup *setup = va_arg(args, void *);
        fprintf(trace, "SETUP %u %u %u %u %s\n", setup->id.bustype,
                setup->id.vendor, setup->id.product, setup->id.version, setup->name);
        break;
    }
    case UI_DEV_CREATE:
        if (getenv("FT37_FAIL_CREATE")) {
            fprintf(trace, "CREATE FAILED\n");
            va_end(args);
            errno = EINVAL;
            return -1;
        }
        fprintf(trace, "CREATE\n");
        break;
    case UI_GET_SYSNAME(64):
        strcpy(va_arg(args, char *), "input37");
        fprintf(trace, "SYSNAME\n");
        break;
    case UI_DEV_DESTROY:
        fprintf(trace, "DESTROY\n");
        break;
    default:
        fprintf(trace, "UNEXPECTED %lu\n", request);
        va_end(args);
        errno = EINVAL;
        return -1;
    }
    va_end(args);
    return 0;
}

ssize_t write(int fd, const void *data, size_t size)
{
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    if (fd != mock_fd)
        return real_write(fd, data, size);
    if (size == 0 || size % sizeof(struct input_event) != 0) {
        errno = EINVAL;
        return -1;
    }
    const struct input_event *events = data;
    for (size_t i = 0; i < size / sizeof(*events); ++i)
        fprintf(trace, "EVENT %u %u %d\n", events[i].type, events[i].code, events[i].value);
    return (ssize_t)size;
}

int close(int fd)
{
    int (*real_close)(int) = dlsym(RTLD_NEXT, "close");
    if (fd == mock_fd) {
        fprintf(trace, "CLOSE\n");
        fclose(trace);
        mock_fd = -1;
    }
    return real_close(fd);
}
