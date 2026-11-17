// SPDX-License-Identifier: GPL-2.0-or-later
#include <QCoreApplication>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusError>
#include <QDBusReply>
#include <iostream>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc < 2) return 2;
    QDBusInterface editor("org.sparky.ThemeEditor", "/ThemeEditor", "org.sparky.ThemeEditor1");
    const QString method = QString::fromLocal8Bit(argv[1]);
    QList<QVariant> args;
    if (argc > 2) {
        if (method == "setRenderWidth") args << QString::fromLocal8Bit(argv[2]).toInt();
        else if (method == "setModelDepth") args << QString::fromLocal8Bit(argv[2]).toDouble();
        else args << QString::fromLocal8Bit(argv[2]);
    }
    if (argc > 3) args << QString::fromLocal8Bit(argv[3]).toDouble();
    const auto reply = editor.callWithArgumentList(QDBus::Block, method, args);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        std::cerr << reply.errorMessage().toStdString() << '\n'; return 1;
    }
    for (const auto &arg : reply.arguments()) std::cout << arg.toString().toStdString() << '\n';
    return 0;
}
