// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// sparky-stereo-throw: the command of the Throw daemon.
#include <KLocalizedString>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <QTimer>

namespace
{
QTextStream out(stdout);
QTextStream err(stderr);

int usage()
{
    err << i18nc("@info:usage the command's help; keep the words in angle brackets' meaning",
                 "Usage: sparky-stereo-throw list | throw <id> [--wait SECONDS] | stop <id> | info <id> | volume <id> <0..1|-> [mute|unmute] | status <id> | choose <id> <codec|-> [<mode>|-] | sound <id> <sound|->\n");
    return 2;
}
} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("sparky-stereo-throw");
    const QStringList args = app.arguments().mid(1);
    if (args.isEmpty()) {
        return usage();
    }
    QDBusInterface throwd(QStringLiteral("org.sparky.Throw"), QStringLiteral("/org/sparky/Throw"), QStringLiteral("org.sparky.Throw"),
                          QDBusConnection::sessionBus());
    if (!throwd.isValid()) {
        err << i18nc("@info the daemon is not on the session bus", "The Throw service is not running (org.sparky.Throw).") << '\n';
        return 1;
    }
    throwd.setTimeout(30000);
    const QString verb = args.at(0);
    if (verb == QLatin1String("list") && args.size() == 1) {
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("Devices"));
        if (!reply.isValid()) {
            err << reply.error().message() << '\n';
            return 1;
        }
        out << QJsonDocument::fromJson(reply.value().toUtf8()).toJson(QJsonDocument::Indented);
        return 0;
    }
    if (args.size() < 2) {
        return usage();
    }
    const QString id = args.at(1);
    if (verb == QLatin1String("throw")) {
        int wait = 0;
        if (args.size() == 4 && args.at(2) == QLatin1String("--wait")) {
            wait = args.at(3).toInt();
        } else if (args.size() != 2) {
            return usage();
        }
        int status = 1;
        QString last;
        if (wait > 0) {
            // the state the daemon reaches decides the exit: throwing 0, failed or stopped 1, no answer 3
            QDBusConnection::sessionBus().connect(QStringLiteral("org.sparky.Throw"), QStringLiteral("/org/sparky/Throw"), QStringLiteral("org.sparky.Throw"),
                                                  QStringLiteral("StateChanged"), &app, SLOT(quit()));
        }
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("Throw"), id);
        if (!reply.isValid() || !reply.value().isEmpty()) {
            err << (reply.isValid() ? reply.value() : reply.error().message()) << '\n';
            return 1;
        }
        if (wait <= 0) {
            return 0;
        }
        QTimer deadline;
        deadline.setSingleShot(true);
        QObject::connect(&deadline, &QTimer::timeout, &app, [&] {
            status = 3;
            app.quit();
        });
        deadline.start(wait * 1000);
        while (true) {
            app.exec();
            if (status == 3) {
                err << "no Throw state within " << wait << " s\n";
                return 3;
            }
            const QDBusReply<QString> devices = throwd.call(QStringLiteral("Devices"));
            for (const auto &value : QJsonDocument::fromJson(devices.value().toUtf8()).array()) {
                const QJsonObject d = value.toObject();
                if (d.value(QStringLiteral("id")).toString() == id) {
                    last = d.value(QStringLiteral("state")).toString();
                    if (last == QLatin1String("throwing")) {
                        out << "throwing\n";
                        return 0;
                    }
                    if (last == QLatin1String("failed") || last == QLatin1String("stopped")) {
                        out << last << ": " << d.value(QStringLiteral("detail")).toString() << '\n';
                        return 1;
                    }
                }
            }
        }
    }
    if (verb == QLatin1String("stop") && args.size() == 2) {
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("Stop"), id);
        if (!reply.isValid() || !reply.value().isEmpty()) {
            err << (reply.isValid() ? reply.value() : reply.error().message()) << '\n';
            return 1;
        }
        return 0;
    }
    if (verb == QLatin1String("status") && args.size() == 2) {
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("Status"), id);
        if (!reply.isValid()) {
            err << reply.error().message() << '\n';
            return 1;
        }
        out << QJsonDocument::fromJson(reply.value().toUtf8()).toJson(QJsonDocument::Compact) << '\n';
        return 0;
    }
    if (verb == QLatin1String("choose") && (args.size() == 3 || args.size() == 4)) {
        // "-" leaves the choice to the table: the codec it prefers, the codec's own default mode
        const QString codec = args.at(2) == QLatin1String("-") ? QString() : args.at(2);
        const QString mode = args.size() == 4 && args.at(3) != QLatin1String("-") ? args.at(3) : QString();
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("SetChoice"), id, codec, mode);
        if (!reply.isValid()) {
            err << reply.error().message() << '\n';
            return 1;
        }
        const QJsonObject answer = QJsonDocument::fromJson(reply.value().toUtf8()).object();
        out << QJsonDocument(answer).toJson(QJsonDocument::Indented);
        return answer.contains(QStringLiteral("error")) ? 1 : 0;
    }
    if (verb == QLatin1String("sound") && args.size() == 3) {
        // "-" leaves the sound to the table: the best stereo sound the stream carries that has not failed on this device
        const QString sound = args.at(2) == QLatin1String("-") ? QString() : args.at(2);
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("SetSound"), id, sound);
        if (!reply.isValid()) {
            err << reply.error().message() << '\n';
            return 1;
        }
        const QJsonObject answer = QJsonDocument::fromJson(reply.value().toUtf8()).object();
        out << QJsonDocument(answer).toJson(QJsonDocument::Indented);
        return answer.contains(QStringLiteral("error")) ? 1 : 0;
    }
    if (verb == QLatin1String("info") && args.size() == 2) {
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("DeviceInfo"), id);
        if (!reply.isValid()) {
            err << reply.error().message() << '\n';
            return 1;
        }
        out << QJsonDocument::fromJson(reply.value().toUtf8()).toJson(QJsonDocument::Indented);
        return QJsonDocument::fromJson(reply.value().toUtf8()).object().contains(QStringLiteral("error")) ? 1 : 0;
    }
    if (verb == QLatin1String("volume") && (args.size() == 3 || args.size() == 4)) {
        bool ok = true;
        const double level = args.at(2) == QLatin1String("-") ? -1.0 : args.at(2).toDouble(&ok);
        if (!ok || level > 1.0) {
            return usage();
        }
        int muted = -1;
        if (args.size() == 4) {
            if (args.at(3) == QLatin1String("mute")) {
                muted = 1;
            } else if (args.at(3) == QLatin1String("unmute")) {
                muted = 0;
            } else {
                return usage();
            }
        }
        const QDBusReply<QString> reply = throwd.call(QStringLiteral("SetVolume"), id, level, muted);
        if (!reply.isValid()) {
            err << reply.error().message() << '\n';
            return 1;
        }
        out << reply.value() << '\n';
        return QJsonDocument::fromJson(reply.value().toUtf8()).object().contains(QStringLiteral("error")) ? 1 : 0;
    }
    return usage();
}
