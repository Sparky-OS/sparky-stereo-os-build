// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "devicetable.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

namespace Throw
{

namespace
{
ModelRow fromJson(const QJsonObject &o)
{
    ModelRow row;
    row.model = o.value(QStringLiteral("md")).toString();
    row.generation = o.value(QStringLiteral("generation")).toString();
    row.video = o.value(QStringLiteral("video")).toBool(true);
    const QJsonObject mode = o.value(QStringLiteral("mode")).toObject();
    row.size = QSize(mode.value(QStringLiteral("width")).toInt(), mode.value(QStringLiteral("height")).toInt());
    row.refreshHz = mode.value(QStringLiteral("refresh")).toInt(30);
    row.codec = o.value(QStringLiteral("codec")).toString(QStringLiteral("H264"));
    row.level = o.value(QStringLiteral("level")).toString();
    row.source = o.value(QStringLiteral("source")).toString();
    return row;
}
} // namespace

DeviceTable::DeviceTable(const QString &path)
{
    // the first Chromecast's limits: H.264 High up to level 4.1, 1080p at 30 frames a second (Google's media page);
    // the decision of row 81's review for any model not in the table
    m_unknown.generation = QStringLiteral("unknown");
    m_unknown.size = QSize(1920, 1080);
    m_unknown.refreshHz = 30;
    m_unknown.codec = QStringLiteral("H264");
    m_unknown.level = QStringLiteral("4.1");
    m_unknown.known = false;

    m_path = path.isEmpty() ? QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("sparky-stereo-throw/devices.json")) : path;
    QFile file(m_path);
    if (m_path.isEmpty() || !file.open(QIODevice::ReadOnly)) {
        m_error = QStringLiteral("the device table %1 cannot be read").arg(m_path.isEmpty() ? QStringLiteral("devices.json") : m_path);
        return;
    }
    QJsonParseError parse;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parse);
    if (parse.error != QJsonParseError::NoError) {
        m_error = QStringLiteral("the device table %1 is not JSON: %2").arg(m_path, parse.errorString());
        return;
    }
    const QJsonObject unknown = doc.object().value(QStringLiteral("unknown")).toObject();
    if (!unknown.isEmpty()) {
        m_unknown = fromJson(unknown);
        m_unknown.known = false;
    }
    const QJsonArray models = doc.object().value(QStringLiteral("models")).toArray();
    for (const auto &value : models) {
        m_rows.append(fromJson(value.toObject()));
    }
}

ModelRow DeviceTable::row(const QString &model) const
{
    for (const auto &row : m_rows) {
        if (row.model.compare(model, Qt::CaseInsensitive) == 0) {
            return row;
        }
    }
    ModelRow unknown = m_unknown;
    unknown.model = model;
    return unknown;
}

} // namespace Throw
