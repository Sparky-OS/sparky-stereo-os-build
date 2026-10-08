// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "adapter.h"
#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QRegularExpression>
#include <fcntl.h>
#include <linux/cec.h>
#include <sys/ioctl.h>
#include <unistd.h>

static bool isVivid(const QString &path)
{
    const int fd = open(QFile::encodeName(path).constData(), O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        return false;
    }
    cec_caps caps = {};
    const bool valid = ioctl(fd, CEC_ADAP_G_CAPS, &caps) == 0 && QByteArray(caps.driver).startsWith("vivid");
    close(fd);
    return valid;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 3 || !isVivid(QString::fromLocal8Bit(argv[1])) || !isVivid(QString::fromLocal8Bit(argv[2]))) {
        qWarning() << "Pass vivid transmitter and receiver nodes only; physical adapters are rejected";
        return 2;
    }
    const QString transmitter = QString::fromLocal8Bit(argv[1]);
    CecAdapter adapter({transmitter, QStringLiteral("HDMI-A-1"), {}, false});
    QTimer poll;
    poll.setInterval(500);
    bool on = false;
    uint attempts = 0;
    QObject::connect(&adapter, &CecAdapter::failed, &app, [&app](const QString &message) {
        qWarning().noquote() << message;
        app.exit(1);
    });
    QObject::connect(&adapter, &CecAdapter::transmitted, &app, [&](bool requestedOn, bool acknowledged) {
        if (!acknowledged) {
            app.exit(1);
            return;
        }
        on = requestedOn;
        attempts = 0;
        poll.start();
    });
    QObject::connect(&poll, &QTimer::timeout, &app, [&] {
        QProcess query;
        query.setProcessChannelMode(QProcess::MergedChannels);
        query.start(QStringLiteral("/usr/bin/cec-ctl"), {QStringLiteral("--device=") + transmitter, QStringLiteral("--skip-info"), QStringLiteral("--to=0"), QStringLiteral("--give-device-power-status")});
        if (!query.waitForFinished(3000)) {
            query.kill();
            query.waitForFinished();
            app.exit(1);
            return;
        }
        const auto output = QString::fromLocal8Bit(query.readAll());
        const QString expected = on ? QStringLiteral("on") : QStringLiteral("standby");
        if (query.exitCode() == 0 && QRegularExpression(QStringLiteral("pwr-state: ") + expected + QStringLiteral("\\b")).match(output).hasMatch()) {
            qInfo().noquote() << "PASS vivid receiver power state:" << expected;
            poll.stop();
            if (on) {
                app.exit(0);
            } else {
                adapter.setScreenOn(true);
            }
        } else if (++attempts >= 20) {
            qWarning().noquote() << "Receiver did not reach" << expected << output;
            app.exit(1);
        }
    });
    QTimer::singleShot(0, &app, [&] {
        adapter.setScreenOn(false);
    });
    return app.exec();
}
