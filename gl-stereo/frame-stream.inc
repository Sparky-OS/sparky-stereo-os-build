/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <endian.h>

static void stream_frame(WindowState *w)
{
    static _Thread_local int fd = -2, pending;
    static _Thread_local uint32_t sequence;
    if (fd == -2) {
        const char *value = getenv("GL_STEREO_FRAME_FD");
        char *end;
        long parsed = value ? strtol(value, &end, 10) : -1;
        fd = value && !*end && parsed >= 3 && parsed <= 1048576 ? (int)parsed : -1;
    }
    if (fd < 0 || !w->active) return;
    if (pending) {
        uint32_t ack;
        ssize_t n = recv(fd, &ack, sizeof(ack), MSG_DONTWAIT);
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
        if (n != sizeof(ack) || le32toh(ack) != sequence) { fd = -1; return; }
        pending = 0;
    }
    unsigned width = 2 * w->width, height = w->height;
    if (!width || !height || width > 8192 || height > 4096 || (uint64_t)width * height * 4 > 67108864) return;
    size_t bytes = (size_t)width * height * 4;
    int memory = memfd_create("gl-stereo-frame", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (memory < 0) return;
    if (ftruncate(memory, bytes)) { close(memory); return; }
    void *pixels = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, memory, 0);
    if (pixels == MAP_FAILED) { close(memory); return; }
    GLint read, pbo, framebuffer, pack[6];
    const GLenum names[] = {GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH, GL_PACK_SKIP_PIXELS,
                            GL_PACK_SKIP_ROWS, GL_PACK_SWAP_BYTES, GL_PACK_LSB_FIRST};
    r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &framebuffer);
    r_glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    r_glGetIntegerv(GL_READ_BUFFER, &read);
    r_glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pbo);
    r_glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    for (int i = 0; i < 6; ++i) { r_glGetIntegerv(names[i], &pack[i]); r_glPixelStorei(names[i], i ? 0 : 1); }
    GLboolean double_buffer;
    r_glGetBooleanv(GL_DOUBLEBUFFER, &double_buffer);
    r_glReadBuffer(double_buffer ? GL_BACK : GL_FRONT);
    read_window_color(width, height, GL_RGBA, pixels);
    r_glReadBuffer(read);
    r_glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
    for (int i = 0; i < 6; ++i) r_glPixelStorei(names[i], pack[i]);
    r_glBindBuffer(GL_PIXEL_PACK_BUFFER, pbo);
    munmap(pixels, bytes);
    if (fcntl(memory, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) { close(memory); return; }
    uint32_t header[] = {htole32(0x46334453), htole32(1), htole32(width), htole32(height),
                         htole32(width * 4), htole32(++sequence), htole32(bytes), htole32(1)};
    /* Format 1 is bottom-up RGBA8. One frame stays outstanding until ACK. */
    struct iovec io = {header, sizeof(header)};
    union { struct cmsghdr align; char bytes[CMSG_SPACE(sizeof(int))]; } control = {0};
    struct msghdr msg = {0};
    msg.msg_iov = &io; msg.msg_iovlen = 1;
    msg.msg_control = control.bytes; msg.msg_controllen = sizeof(control.bytes);
    struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
    c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &memory, sizeof(memory));
    ssize_t n = sendmsg(fd, &msg, MSG_DONTWAIT | MSG_NOSIGNAL);
    if (n == sizeof(header)) pending = 1;
    else if (errno != EAGAIN && errno != EWOULDBLOCK) fd = -1;
    close(memory);
}
