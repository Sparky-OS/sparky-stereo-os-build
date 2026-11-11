// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "umsprofile.h"
#include "window.h"
#include <KLocalizedString>
#include <QApplication>
#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QTimer>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("ums-renderer"));
    KLocalizedString::setApplicationDomain("kcm_ums");
    QCommandLineParser parser;
    parser.setApplicationDescription(i18n("Play shared media on a network device and control it from Plasma."));
    parser.addHelpOption();
    parser.addOption({QStringLiteral("target"), i18n("Device group: tv or headset"), QStringLiteral("group")});
    parser.addOption({QStringLiteral("server"), i18n("UMS web interface address"), QStringLiteral("url")});
    parser.addPositionalArgument(QStringLiteral("file"), i18n("One local file already shared by UMS"), QStringLiteral("[file]"));
    parser.process(app);
    const auto args = parser.positionalArguments();
    if (args.size() > 1
        || (!parser.value(QStringLiteral("target")).isEmpty() && parser.value(QStringLiteral("target")) != QLatin1String("tv")
            && parser.value(QStringLiteral("target")) != QLatin1String("headset")))
        parser.showHelp(2);
    const auto source = args.isEmpty() ? QUrl() : QUrl::fromUserInput(args.first(), QDir::currentPath(), QUrl::AssumeLocalFile);
    auto bus = QDBusConnection::sessionBus();
    const auto service = QStringLiteral("org.sparky.UMS.Controller");
    if (!bus.registerService(service)) {
        QDBusInterface remote(service, QStringLiteral("/Controller"), QStringLiteral("org.sparky.UMS.Controller"), bus);
        const auto reply = remote.call(QStringLiteral("Open"), parser.value(QStringLiteral("target")), source.toString());
        return reply.type() == QDBusMessage::ErrorMessage ? 1 : 0;
    }
    QString server = parser.value(QStringLiteral("server"));
    if (server.isEmpty()) {
        int port = 9001;
        QFile config(UmsProfile::defaultDirectory() + QStringLiteral("/UMS.conf"));
        if (config.open(QIODevice::ReadOnly)) {
            const auto match = QRegularExpression(QStringLiteral("(?m)^\\s*web_gui_port\\s*=\\s*(\\d+)\\s*$")).match(QString::fromUtf8(config.readAll()));
            if (match.hasMatch() && match.captured(1).toInt() > 0 && match.captured(1).toInt() < 65536)
                port = match.captured(1).toInt();
        }
        server = QStringLiteral("http://127.0.0.1:%1").arg(port);
    }
    Window window{QUrl(server)};
    if (!bus.registerObject(QStringLiteral("/Controller"), &window, QDBusConnection::ExportScriptableSlots))
        return 1;
    QTimer::singleShot(0, &window, [&] {
        window.Open(parser.value(QStringLiteral("target")), source.toString());
    });
    return app.exec();
}
