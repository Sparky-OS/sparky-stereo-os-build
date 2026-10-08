// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "adapter.h"

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <fcntl.h>
#include <linux/cec.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace
{

QString readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QString::fromLatin1(file.readAll()).trimmed() : QString();
}

struct Connector
{
    QString name;
    QString edid;
    uint card;
    uint id;
};

}

QList<AdapterConfig> discoverAdapters(const QString &deviceDirectory, const QString &drmDirectory, const QStringList &outputs, const QHash<QString, QString> &bindings)
{
    QList<Connector> connectors;
    const QRegularExpression connectorPattern(QStringLiteral("^card([0-9]+)-(HDMI-A-[0-9]+)$"));
    const QDir drm(drmDirectory);
    const auto entries = drm.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const auto &entry : entries) {
        const auto match = connectorPattern.match(entry);
        if (!match.hasMatch() || outputs.count(match.captured(2)) != 1 || readFile(drm.filePath(entry + QStringLiteral("/status"))) != QStringLiteral("connected")) {
            continue;
        }
        bool ok;
        const auto id = readFile(drm.filePath(entry + QStringLiteral("/connector_id"))).toUInt(&ok);
        if (ok) {
            connectors.append({match.captured(2), drm.filePath(entry + QStringLiteral("/edid")), match.captured(1).toUInt(), id});
        }
    }

    const QDir devices(deviceDirectory);
    const auto names = devices.entryList({QStringLiteral("cec*")}, QDir::System | QDir::Files, QDir::Name);
    QList<AdapterConfig> result;
    for (const auto &name : names) {
        if (!QRegularExpression(QStringLiteral("^cec[0-9]+$")).match(name).hasMatch()) {
            continue;
        }
        const auto path = devices.filePath(name);
        const int fd = open(QFile::encodeName(path).constData(), O_RDWR | O_CLOEXEC);
        if (fd < 0) {
            continue;
        }
        cec_caps caps = {};
        cec_connector_info info = {};
        const bool usable = ioctl(fd, CEC_ADAP_G_CAPS, &caps) == 0 && (caps.capabilities & CEC_CAP_TRANSMIT);
        const bool hasConnector = usable && (caps.capabilities & CEC_CAP_CONNECTOR_INFO) && ioctl(fd, CEC_ADAP_G_CONNECTOR_INFO, &info) == 0 && info.type == CEC_CONNECTOR_TYPE_DRM;
        close(fd);
        if (!usable) {
            continue;
        }
        QList<Connector> matches;
        for (const auto &connector : connectors) {
            if (hasConnector) {
                if (connector.card == info.drm.card_no && connector.id == info.drm.connector_id) {
                    matches.append(connector);
                }
            } else if (bindings.contains(name)) {
                if (connector.name == bindings.value(name)) {
                    matches.append(connector);
                }
            } else if (names.size() == 1 && connectors.size() == 1) {
                matches.append(connector);
            }
        }
        if (matches.size() == 1) {
            const auto &connector = matches.constFirst();
            result.append({path, connector.name, connector.edid, !hasConnector && bool(caps.capabilities & CEC_CAP_PHYS_ADDR)});
        }
    }
    return result;
}
