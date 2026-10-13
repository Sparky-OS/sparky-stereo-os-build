// SPDX-License-Identifier: GPL-2.0-or-later
// capture OUT.png [OUTPUT]: one frame of KWin's ScreenShot2 interface (CaptureScreen for OUTPUT, else
// CaptureActiveScreen) at the output's native resolution, i.e. in DEVICE pixels, without the cursor,
// saved as PNG. Prints "size WxH format F". Adapted from the qt-stereo lane's qt-capture.cpp
// (qt-capture.orig.cpp here): the same D-Bus call and pipe read, the stereo checks left out.
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#include <QGuiApplication>
#include <QImage>
#include <QVariantMap>

#include <unistd.h>

#include <cstdio>
#include <vector>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc < 2) {
        fprintf(stderr, "usage: capture OUT.png [OUTPUT]\n");
        return 2;
    }
    int pipes[2];
    if (pipe(pipes) != 0)
        return 2;
    QDBusInterface iface(QStringLiteral("org.kde.KWin.ScreenShot2"), QStringLiteral("/org/kde/KWin/ScreenShot2"),
                         QStringLiteral("org.kde.KWin.ScreenShot2"), QDBusConnection::sessionBus());
    QVariantMap options;
    options.insert(QStringLiteral("include-cursor"), false);
    options.insert(QStringLiteral("native-resolution"), true);
    QDBusUnixFileDescriptor descriptor(pipes[1]);
    const QDBusMessage reply = argc > 2 && QByteArray(argv[2]) == "window"
        ? iface.call(QDBus::Block, QStringLiteral("CaptureActiveWindow"), options, QVariant::fromValue(descriptor))
        : argc > 2
        ? iface.call(QDBus::Block, QStringLiteral("CaptureScreen"), QString::fromLocal8Bit(argv[2]), options, QVariant::fromValue(descriptor))
        : iface.call(QDBus::Block, QStringLiteral("CaptureActiveScreen"), options, QVariant::fromValue(descriptor));
    close(pipes[1]);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        fprintf(stderr, "%s: %s\n", qPrintable(reply.errorName()), qPrintable(reply.errorMessage()));
        return 3;
    }
    const QVariantMap results = qdbus_cast<QVariantMap>(reply.arguments().constFirst());
    const int width = results.value(QStringLiteral("width")).toUInt();
    const int height = results.value(QStringLiteral("height")).toUInt();
    const int stride = results.value(QStringLiteral("stride")).toUInt();
    const int format = results.value(QStringLiteral("format")).toUInt();
    std::vector<unsigned char> image(size_t(stride) * size_t(height));
    size_t done = 0;
    while (done < image.size()) {
        const ssize_t count = read(pipes[0], image.data() + done, image.size() - done);
        if (count <= 0)
            break;
        done += size_t(count);
    }
    close(pipes[0]);
    if (done != image.size()) {
        fprintf(stderr, "short capture: %zu/%zu bytes\n", done, image.size());
        return 5;
    }
    QImage(image.data(), width, height, stride, QImage::Format(format)).save(QString::fromLocal8Bit(argv[1]));
    printf("size %dx%d format %d\n", width, height, format);
    return 0;
}
