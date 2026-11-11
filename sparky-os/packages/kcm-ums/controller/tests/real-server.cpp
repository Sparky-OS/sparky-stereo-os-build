// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "backend.h"
#include <QCoreApplication>
#include <QTextStream>
#include <QThread>
#include <QJsonDocument>
int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    try {
        Backend backend(QUrl(QStringLiteral("http://127.0.0.1:9001")));
        const auto renderers = backend.renderers();
        for (const auto &entry : renderers) {
            const auto renderer = entry.toObject();
            if (!renderer.value(QStringLiteral("name")).toString().contains(QLatin1String("Flat Headset"))) continue;
            backend.select(renderer);
            backend.sendFile(QUrl::fromLocalFile(QStringLiteral("/media/top-bottom.mkv")));
            if (backend.status != QLatin1String("Playing")) return 2;
            QThread::sleep(5);
            backend.transport(QStringLiteral("Pause"));
            if (backend.status != QLatin1String("Paused")) return 3;
            backend.setVolume(.42);
            if (backend.volume != .42) return 4;
            backend.seek(1000000);
            QTextStream(stdout) << "PASS real UMS selected-renderer library, Play/Pause/Seek/Volume\n";
            return 0;
        }
        QTextStream(stderr) << "No Flat Headset renderer in " << QJsonDocument(renderers).toJson() << '\n';
        return 5;
    } catch (const std::exception &error) {
        QTextStream(stderr) << error.what() << '\n';
        return 1;
    }
}
