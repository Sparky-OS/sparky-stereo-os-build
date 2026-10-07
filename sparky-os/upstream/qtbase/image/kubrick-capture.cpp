// Test aid: KWin ScreenShot2 capture of the active screen (or window) to a PNG; prints the "stereo" result key.
#include <QGuiApplication>
#include <QImage>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusArgument>
#include <QDBusUnixFileDescriptor>
#include <QVariantMap>
#include <unistd.h>
#include <cstdio>
#include <vector>
int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: capture screen|window out.png\n"); return 2; }
    int pipes[2];
    if (pipe(pipes) != 0) return 2;
    QDBusInterface iface("org.kde.KWin.ScreenShot2", "/org/kde/KWin/ScreenShot2", "org.kde.KWin.ScreenShot2", QDBusConnection::sessionBus());
    QVariantMap options;
    options.insert("include-decoration", false); options.insert("include-cursor", false); options.insert("hide-caller-windows", false);
    QDBusUnixFileDescriptor fd(pipes[1]);
    QDBusMessage reply = iface.call(QDBus::Block, QString(argv[1]) == "screen" ? "CaptureActiveScreen" : "CaptureActiveWindow", options, QVariant::fromValue(fd));
    close(pipes[1]);
    if (reply.type() == QDBusMessage::ErrorMessage) { fprintf(stderr, "%s: %s\n", qPrintable(reply.errorName()), qPrintable(reply.errorMessage())); return 3; }
    const QVariant first = reply.arguments().constFirst();
    QVariantMap r = first.canConvert<QVariantMap>() ? first.toMap() : qdbus_cast<QVariantMap>(first.value<QDBusArgument>());
    int w = r["width"].toUInt(), h = r["height"].toUInt(), stride = r["stride"].toUInt();
    std::vector<unsigned char> img(size_t(stride) * h); size_t done = 0;
    while (done < img.size()) { ssize_t c = read(pipes[0], img.data() + done, img.size() - done); if (c <= 0) break; done += c; }
    if (done != img.size()) { fprintf(stderr, "short capture %zu/%zu\n", done, img.size()); return 5; }
    QImage(img.data(), w, h, stride, QImage::Format_ARGB32).save(argv[2]);
    printf("width=%d height=%d stereo=%s\n", w, h, qPrintable(r["stereo"].toString()));
    return 0;
}
