// Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later
#include <QGuiApplication>
#include <QMediaPlayer>
#include <QVideoSink>
#include <QVideoFrame>
#include <QTimer>
#include <QFile>
#include <QDebug>
#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 4 && argc != 5)
        return 2;
    QMediaPlayer player;
    QVideoSink sink;
    QFile pixels(QString::fromLocal8Bit(argv[2]));
    if (!pixels.open(QIODevice::WriteOnly))
        return 3;
    const int bits = atoi(argv[3]);
    int frames = 0;
    int failed = 0;
    QObject::connect(&sink, &QVideoSink::videoFrameChanged, [&](const QVideoFrame &input) {
        if (!input.isValid())
            return;
        QVideoFrame frame(input);
        if (!frame.map(QVideoFrame::ReadOnly)) {
            failed = 4;
            return;
        }
        const auto format = frame.pixelFormat();
        const bool words = format == QVideoFrameFormat::Format_P010
                           || format == QVideoFrameFormat::Format_P016
                           || format == QVideoFrameFormat::Format_YUV420P10
                           || format == QVideoFrameFormat::Format_YUV422P16
                           || format == QVideoFrameFormat::Format_YUV444P16;
        if (bits > 8 && !words)
            failed = 5;
        const int shift = words && format != QVideoFrameFormat::Format_YUV420P10 ? 16 - bits : 0;
        for (int y = 0; y < frame.height(); y++) {
            const auto *row = frame.bits(0) + y * frame.bytesPerLine(0);
            for (int x = 0; x < frame.width(); x++) {
                quint16 value = words ? reinterpret_cast<const quint16 *>(row)[x] >> shift : row[x];
                pixels.write(reinterpret_cast<const char *>(&value), sizeof(value));
            }
        }
        qInfo().noquote() << "FRAME" << frames++ << frame.startTime() << format
                          << frame.surfaceFormat().stereoMode() << frame.surfaceFormat().stereoFlags() << frame.size();
        frame.unmap();
    });
    QObject::connect(&player, &QMediaPlayer::mediaStatusChanged, [&](auto status) {
        if (status == QMediaPlayer::EndOfMedia)
            app.quit();
    });
    QObject::connect(&player, &QMediaPlayer::errorOccurred, [&](auto, auto error) {
        qCritical() << error;
        failed = 6;
        app.quit();
    });
    QTimer::singleShot(15000, [&] { failed = 7; app.quit(); });
    player.setVideoSink(&sink);
    player.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    player.play();
    app.exec();
    return failed ? failed : (frames == (argc == 5 ? atoi(argv[4]) : 48) ? 0 : 8);
}
