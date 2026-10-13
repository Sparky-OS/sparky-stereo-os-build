// SPDX-License-Identifier: GPL-2.0-or-later
#include "frameclient.h"
#include <QtEndian>
#include <QDebug>
#include <array>
#include <vector>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

FrameClient::FrameClient(QObject *parent) : QObject(parent)
{
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] { m_process.readAllStandardOutput(); });
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        qWarning().noquote() << m_process.readAllStandardError().left(1024);
    });
    auto closeChildDescriptors = [this] {
        if (m_childControl >= 0) close(m_childControl);
        if (m_childPixels >= 0) close(m_childPixels);
        m_childControl = m_childPixels = -1;
    };
    connect(&m_process, &QProcess::started, this, closeChildDescriptors);
    connect(&m_process, &QProcess::errorOccurred, this, [this, closeChildDescriptors] { closeChildDescriptors(); clear(); });
    m_cycle.setInterval(600000);
    connect(&m_cycle, &QTimer::timeout, this, [this] { sendControl("{\"event\":\"rotate\"}"); });
    m_deadline.setSingleShot(true);
    m_deadline.setInterval(6000);
    connect(&m_deadline, &QTimer::timeout, this, &FrameClient::clear);
    connect(&m_process, &QProcess::finished, this, &FrameClient::clear);
}

FrameClient::~FrameClient()
{
    sendControl("{\"event\":\"shutdown\"}");
    if (m_control >= 0) close(m_control);
    if (m_pixels >= 0) close(m_pixels);
    if (!m_process.waitForFinished(3500)) m_process.kill();
    if (m_childControl >= 0) close(m_childControl);
    if (m_childPixels >= 0) close(m_childPixels);
}

void FrameClient::clear()
{
    m_frame = {};
    Q_EMIT frameChanged();
}

void FrameClient::sendControl(const QByteArray &data)
{
    if (m_control >= 0 && send(m_control, data.constData(), data.size(), MSG_DONTWAIT | MSG_NOSIGNAL) != data.size()) {
        clear();
    }
}

void FrameClient::setCycleSeconds(int seconds)
{
    m_cycle.setInterval(qBound(60, seconds, 86400) * 1000);
}

void FrameClient::setRunning(bool running)
{
    if (m_running == running) return;
    m_running = running;
    if (running && m_process.state() == QProcess::NotRunning) {
        int control[2], pixels[2];
        if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, control) < 0) return;
        if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pixels) < 0) {
            close(control[0]); close(control[1]); return;
        }
        if (m_control >= 0) close(m_control);
        if (m_pixels >= 0) close(m_pixels);
        delete m_notifier;
        m_control = control[0]; m_pixels = pixels[0];
        const int childControl = fcntl(control[1], F_DUPFD_CLOEXEC, 64);
        const int childPixels = fcntl(pixels[1], F_DUPFD_CLOEXEC, 64);
        close(control[1]); close(pixels[1]);
        if (childControl < 0 || childPixels < 0) {
            if (childControl >= 0) close(childControl);
            if (childPixels >= 0) close(childPixels);
            return;
        }
        m_childControl = childControl; m_childPixels = childPixels;
        m_process.setChildProcessModifier([childControl, childPixels] {
            if (fcntl(childControl, F_SETFD, 0) < 0 || fcntl(childPixels, F_SETFD, 0) < 0) _exit(127);
        });
        m_process.start(QStringLiteral("/usr/bin/python3"), {QStringLiteral(SAVER_DIRECTORY "/controller.py"),
                        QStringLiteral(SAVER_CATALOGUE), QString::number(childControl), QString::number(childPixels)});
        m_sequence = 0;
        m_notifier = new QSocketNotifier(m_pixels, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated, this, &FrameClient::readFrame);
    }
    if (running) {
        sendControl("{\"locked\":true,\"display_on\":true,\"on_ac\":true}");
        m_cycle.start(); m_deadline.start();
    } else {
        sendControl("{\"locked\":false,\"display_on\":false,\"on_ac\":false}");
        m_cycle.stop(); m_deadline.stop(); clear();
    }
}

void FrameClient::readFrame()
{
    std::array<quint32, 8> header{};
    alignas(cmsghdr) std::array<char, CMSG_SPACE(16 * sizeof(int))> control{};
    iovec vector{header.data(), sizeof(header)};
    msghdr message{};
    message.msg_iov = &vector; message.msg_iovlen = 1;
    message.msg_control = control.data(); message.msg_controllen = control.size();
    const auto bytes = recvmsg(m_pixels, &message, MSG_DONTWAIT | MSG_CMSG_CLOEXEC);
    if (bytes < 0 && (errno == EAGAIN || errno == EINTR)) return;
    std::vector<int> descriptors;
    for (cmsghdr *item = CMSG_FIRSTHDR(&message); item; item = CMSG_NXTHDR(&message, item)) {
        if (item->cmsg_level == SOL_SOCKET && item->cmsg_type == SCM_RIGHTS) {
            const auto count = (item->cmsg_len - CMSG_LEN(0)) / sizeof(int);
            auto *fds = reinterpret_cast<int *>(CMSG_DATA(item));
            descriptors.insert(descriptors.end(), fds, fds + count);
        }
    }
    auto reject = [&] {
        qWarning() << "Stereo frame rejected" << bytes << message.msg_flags << descriptors.size();
        for (int fd : descriptors) close(fd);
        m_notifier->setEnabled(false);
        shutdown(m_pixels, SHUT_RDWR);
        clear();
    };
    if (bytes != sizeof(header) || (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) || descriptors.size() != 1) {
        reject(); return;
    }
    for (auto &word : header) word = qFromLittleEndian(word);
    const auto [magic, version, width, height, stride, sequence, size, format] = header;
    if (magic != 0x46334453 || version != 1 || format != 1 || width < 2 || width > 8192 || width % 2 ||
        height < 1 || height > 4096 || stride != width * 4 || size != stride * height || size > 67108864 || sequence <= m_sequence) {
        reject(); return;
    }
    struct stat info{};
    constexpr int seals = F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
    const int fd = descriptors[0];
    const int actualSeals = fcntl(fd, F_GET_SEALS);
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || info.st_size != size ||
        actualSeals < 0 || (actualSeals & seals) != seals) {
        reject(); return;
    }
    void *data = mmap(nullptr, size, PROT_READ, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) { reject(); return; }
    if (m_running) {
        m_frame = QImage(static_cast<const uchar *>(data), width, height, stride, QImage::Format_RGBA8888).flipped(Qt::Vertical);
    }
    munmap(data, size); close(fd);
    m_sequence = sequence;
    const quint32 ack = qToLittleEndian(sequence);
    if (send(m_pixels, &ack, sizeof(ack), MSG_DONTWAIT | MSG_NOSIGNAL) != sizeof(ack)) {
        m_notifier->setEnabled(false); clear(); return;
    }
    if (m_running) { m_deadline.start(); Q_EMIT frameChanged(); }
}
