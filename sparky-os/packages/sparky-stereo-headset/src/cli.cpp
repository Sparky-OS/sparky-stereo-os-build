// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// sparky-stereo-headset status [--json] | apply | watch
//   status  what is connected and what it reports, in words or as JSON
//   apply   send the saved choices of every connected headset to it, now
//   watch   what the user service runs: the saved choices go to a headset when it appears, and the person is told when its battery is low

#include "headsetengine.h"
#include "headsetstore.h"

#include <KLocalizedString>
#include <KNotification>

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QTextStream>
#include <QTimer>

using namespace Sparky::Headset;

static QTextStream out(stdout);
static QTextStream err(stderr);

// Send the saved choices; returns the number refused
static int applySaved(const Headset &h)
{
    int refused = 0;
    const QVariantMap saved = savedChoices(h.id);
    for (auto it = saved.cbegin(); it != saved.cend(); ++it) {
        const QString error = apply(h, it.key(), it.value());
        if (error.isEmpty()) {
            out << h.id << ' ' << it.key() << " = " << it.value().toString() << '\n';
        } else {
            ++refused;
            err << h.id << ' ' << it.key() << ": " << error << '\n';
            KNotification::event(QStringLiteral("applyFailed"), i18n("The headset kept its setting"), error, QStringLiteral("audio-headset"), KNotification::CloseOnTimeout,
                                 QStringLiteral("sparkystereoheadset"));
        }
    }
    return refused;
}

static int status(bool json)
{
    QList<Headset> list;
    QString error;
    if (!query(list, error)) {
        if (json) {
            out << QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("headsets"), QJsonArray()}, {QStringLiteral("message"), error}}).toJson(QJsonDocument::Compact)) << '\n';
        } else {
            out << error << '\n';
        }
        return 1;
    }
    if (json) {
        QJsonArray array;
        for (const Headset &h : list) {
            array << QJsonObject::fromVariantMap(describe(h, savedChoices(h.id)));
        }
        out << QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("headsets"), array}}).toJson(QJsonDocument::Indented));
        return 0;
    }
    for (const Headset &h : list) {
        out << h.name << " (" << h.id << ")\n";
        const QString battery = batteryText(h);
        if (!battery.isEmpty()) {
            out << "  " << battery << '\n';
        }
        for (const QVariant &s : describe(h, savedChoices(h.id)).value(QStringLiteral("settings")).toList()) {
            const QVariantMap m = s.toMap();
            out << "  " << m.value(QStringLiteral("key")).toString() << (m.value(QStringLiteral("saved")).toBool() ? " (kept)" : "") << '\n';
        }
    }
    return 0;
}

static int watch(QCoreApplication &app)
{
    static QSet<QString> seen;
    static QSet<QString> lowTold;
    auto poll = [] {
        QList<Headset> list;
        QString error;
        if (!query(list, error)) {
            seen.clear(); // unplugged: its choices go to it again when it comes back
            return;
        }
        for (const Headset &h : std::as_const(list)) {
            if (!seen.contains(h.id)) {
                seen.insert(h.id);
                applySaved(h);
            }
            if (!h.batteryKnown() || h.charging()) {
                lowTold.remove(h.id);
                continue;
            }
            const int low = peripheralLowLevel();
            if (h.battery <= low && !lowTold.contains(h.id)) {
                lowTold.insert(h.id);
                KNotification::event(QStringLiteral("lowBattery"), i18n("Headset battery low"), i18n("%1: the battery is at %2%. Charge it soon.", h.name, h.battery),
                                     QStringLiteral("audio-headset"), KNotification::CloseOnTimeout, QStringLiteral("sparkystereoheadset"));
            } else if (h.battery > low + 5) {
                lowTold.remove(h.id);
            }
        }
    };
    QTimer timer;
    timer.setInterval(20000);
    QObject::connect(&timer, &QTimer::timeout, &app, poll);
    timer.start();
    poll();
    return app.exec();
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("sparky-stereo-headset"));
    KLocalizedString::setApplicationDomain("kcm_sparkystereo_headset");
    const QStringList args = app.arguments().mid(1);
    const QString command = args.value(0);
    if (command == QLatin1String("status")) {
        return status(args.contains(QLatin1String("--json")));
    }
    if (command == QLatin1String("apply")) {
        QList<Headset> list;
        QString error;
        if (!query(list, error)) {
            err << error << '\n';
            return 1;
        }
        int refused = 0;
        for (const Headset &h : std::as_const(list)) {
            refused += applySaved(h);
        }
        return refused ? 1 : 0;
    }
    if (command == QLatin1String("watch")) {
        return watch(app);
    }
    err << "Usage: sparky-stereo-headset status [--json] | apply | watch\n";
    return 2;
}
