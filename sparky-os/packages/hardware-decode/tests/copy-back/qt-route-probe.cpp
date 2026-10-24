// Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later
// Plays a film for two seconds into a QVideoSink, as Dragon and Gwenview's
// players do through Qt Multimedia, and prints how many frames arrived.
// The decoder choice is read from qt.multimedia.ffmpeg.hwaccel's messages.
#include <QGuiApplication>
#include <QMediaPlayer>
#include <QTimer>
#include <QUrl>
#include <QVideoFrame>
#include <QVideoSink>
#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 2)
        return 2;
    QMediaPlayer player;
    QVideoSink sink;
    int frames = 0;
    QObject::connect(&sink, &QVideoSink::videoFrameChanged, [&](const QVideoFrame &frame) {
        if (frame.isValid())
            frames++;
    });
    player.setVideoSink(&sink);
    player.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    player.play();
    QTimer::singleShot(2500, &app, [&] {
        std::printf("frames=%d\n", frames);
        app.quit();
    });
    return app.exec() == 0 && frames > 0 ? 0 : 1;
}
