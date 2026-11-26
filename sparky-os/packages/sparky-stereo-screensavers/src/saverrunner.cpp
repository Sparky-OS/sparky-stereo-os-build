// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "saverrunner.h"

#include <QFileInfo>
#include <QtEndian>

#include <array>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

QString SaverRunner::helper()
{
    const QByteArray override = qgetenv("SPARKY_SAVER_PREVIEW");
    return override.isEmpty() ? QStringLiteral(SAVER_HELPER) : QString::fromLocal8Bit(override);
}

SaverRunner::SaverRunner(QObject *parent)
    : QObject(parent)
{
    m_deadline.setSingleShot(true);
    connect(&m_deadline, &QTimer::timeout, this, [this] {
        fail(NoPicture, QString());
    });
}

SaverRunner::~SaverRunner()
{
    stop();
}

void SaverRunner::closeSockets()
{
    delete m_notifier;
    m_notifier = nullptr;
    if (m_pixels >= 0) {
        close(m_pixels);
    }
    m_pixels = -1;
}

void SaverRunner::stop()
{
    m_running = false;
    m_deadline.stop();
    closeSockets();
    if (QProcess *process = m_process) {
        m_process = nullptr;
        process->disconnect(this);
        process->closeWriteChannel(); // the helper ends when its standard input closes
        if (process->state() != QProcess::NotRunning) {
            connect(process, &QProcess::finished, process, &QObject::deleteLater);
            QTimer::singleShot(2000, process, [process] {
                process->terminate();
            });
            QTimer::singleShot(5000, process, [process] {
                process->kill();
            });
        } else {
            process->deleteLater();
        }
    }
    m_frame = {};
}

void SaverRunner::fail(Failure failure, const QString &detail)
{
    if (!m_running) {
        return;
    }
    stop();
    Q_EMIT frameChanged();
    Q_EMIT failed(failure, detail);
}

void SaverRunner::start(const QString &saver, const QSize &view, double separation)
{
    stop();
    m_saver = saver;
    m_said.clear();
    m_sequence = 0;
    m_running = true;
    if (!QFileInfo(helper()).isExecutable()) {
        fail(NoHelper, helper());
        return;
    }
    int pixels[2];
    if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pixels) < 0) {
        fail(NoDisplay, QStringLiteral("socketpair"));
        return;
    }
    const int child = fcntl(pixels[1], F_DUPFD_CLOEXEC, 64);
    close(pixels[1]);
    if (child < 0) {
        close(pixels[0]);
        fail(NoDisplay, QStringLiteral("descriptor"));
        return;
    }
    m_pixels = pixels[0];
    m_process = new QProcess(this);
    QProcess *process = m_process;
    process->setChildProcessModifier([child] {
        if (fcntl(child, F_SETFD, 0) < 0) {
            _exit(127);
        }
    });
    connect(process, &QProcess::readyReadStandardError, this, [this, process] {
        m_said += process->readAllStandardError();
        m_said = m_said.right(2048);
    });
    connect(process, &QProcess::readyReadStandardOutput, process, [process] {
        process->readAllStandardOutput();
    });
    connect(process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            fail(NoHelper, helper());
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        m_said += process->readAllStandardError();
        // the helper's one line: "sparky-saver-preview: KIND: detail"
        QString detail;
        const QList<QByteArray> lines = m_said.trimmed().split('\n');
        const QByteArray last = lines.isEmpty() ? QByteArray() : lines.constLast();
        if (last.startsWith("sparky-saver-preview: ")) {
            detail = QString::fromUtf8(last.mid(22)).section(QStringLiteral(": "), 1);
        }
        if (status == QProcess::NormalExit && code >= NotOffered && code <= NoPicture) {
            fail(Failure(code), detail);
        } else {
            fail(Ended, status == QProcess::NormalExit ? QStringLiteral("status %1").arg(code) : QStringLiteral("crashed"));
        }
    });
    QStringList arguments{QStringLiteral("--size"), QStringLiteral("%1x%2").arg(view.width()).arg(view.height())};
    if (separation >= 0) {
        arguments << QStringLiteral("--separation") << QString::number(separation, 'g', 6);
    }
    arguments << saver << QString::number(child);
    process->start(helper(), arguments);
    close(child); // the helper has its own copy since the fork
    if (!m_running) {
        return;
    }
    m_notifier = new QSocketNotifier(m_pixels, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &SaverRunner::readFrame);
    bool ok = false;
    const int wait = qEnvironmentVariableIntValue("SPARKY_SAVER_WAIT", &ok);
    m_deadline.start((ok && wait > 0 ? wait : 20) * 1000 + 2000); // the saver's first picture, software drawn on a busy machine
}

void SaverRunner::readFrame()
{
    std::array<quint32, 8> header{};
    alignas(cmsghdr) std::array<char, CMSG_SPACE(16 * sizeof(int))> control{};
    iovec vector{header.data(), sizeof(header)};
    msghdr message{};
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    message.msg_control = control.data();
    message.msg_controllen = control.size();
    const auto bytes = recvmsg(m_pixels, &message, MSG_DONTWAIT | MSG_CMSG_CLOEXEC);
    if (bytes < 0 && (errno == EAGAIN || errno == EINTR)) {
        return;
    }
    std::vector<int> descriptors;
    for (cmsghdr *item = CMSG_FIRSTHDR(&message); item; item = CMSG_NXTHDR(&message, item)) {
        if (item->cmsg_level == SOL_SOCKET && item->cmsg_type == SCM_RIGHTS) {
            const auto count = (item->cmsg_len - CMSG_LEN(0)) / sizeof(int);
            auto *fds = reinterpret_cast<int *>(CMSG_DATA(item));
            descriptors.insert(descriptors.end(), fds, fds + count);
        }
    }
    if (bytes == 0) { // the saver closed its end; the helper's exit says why
        for (int fd : descriptors) {
            close(fd);
        }
        m_notifier->setEnabled(false);
        return;
    }
    auto reject = [&](const char *why) {
        for (int fd : descriptors) {
            close(fd);
        }
        fail(BadFrame, QString::fromLatin1(why));
    };
    if (bytes != sizeof(header) || (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) || descriptors.size() != 1) {
        reject("envelope");
        return;
    }
    for (auto &word : header) {
        word = qFromLittleEndian(word);
    }
    const auto [magic, version, width, height, stride, sequence, size, format] = header;
    if (magic != 0x46334453 || version != 1 || format != 1 || width < 2 || width > 8192 || width % 2 || height < 1 || height > 4096
        || stride != width * 4 || size != stride * height || size > 67108864 || sequence <= m_sequence) {
        reject("dimensions, format or sequence");
        return;
    }
    struct stat info {
    };
    constexpr int seals = F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
    const int fd = descriptors[0];
    const int actualSeals = fcntl(fd, F_GET_SEALS);
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || info.st_size != size || actualSeals < 0
        || (actualSeals & seals) != seals) {
        reject("storage");
        return;
    }
    void *data = mmap(nullptr, size, PROT_READ, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        reject("mapping");
        return;
    }
    m_frame = QImage(static_cast<const uchar *>(data), width, height, stride, QImage::Format_RGBA8888).flipped(Qt::Vertical);
    munmap(data, size);
    close(fd);
    m_sequence = sequence;
    const quint32 ack = qToLittleEndian(sequence);
    if (send(m_pixels, &ack, sizeof(ack), MSG_DONTWAIT | MSG_NOSIGNAL) != sizeof(ack)) {
        fail(Ended, QStringLiteral("acknowledgement"));
        return;
    }
    m_deadline.start(8000);
    Q_EMIT frameChanged();
}
