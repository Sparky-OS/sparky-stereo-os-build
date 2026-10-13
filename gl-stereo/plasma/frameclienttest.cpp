// SPDX-License-Identifier: GPL-2.0-or-later
#include "frameclient.h"
#include <QCoreApplication>
#include <QTimer>
#include <iostream>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    FrameClient client;
    int frames = 0;
    int events = 0;
    QTimer responsiveness;
    responsiveness.setInterval(5);
    QObject::connect(&responsiveness, &QTimer::timeout, &app, [&] { ++events; });
    responsiveness.start();
    QObject::connect(&client, &FrameClient::frameChanged, &app, [&] {
        if (client.frame().isNull()) return;
        const QImage image = client.frame();
        if (image.width() != 1280 || image.height() != 360) { app.exit(2); return; }
        std::cout << "received " << frames+1 << "\n" << std::flush;
        if (++frames != 5) return;
        if (events < 5) { app.exit(3); return; }
        client.setRunning(false);
        if (!client.frame().isNull()) { app.exit(4); return; }
        std::cout << "PASS: native receiver delivered five bounded frames, event loop progressed, inactive state cleared background\n";
        app.exit(0);
    });
    QTimer::singleShot(0, &client, [&] { client.setRunning(true); });
    QTimer::singleShot(10000, &app, [&] { std::cerr << "FAIL: no five native frames\n"; app.exit(1); });
    return app.exec();
}
