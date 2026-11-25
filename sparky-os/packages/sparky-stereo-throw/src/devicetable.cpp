// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "devicetable.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>

namespace Throw
{

QString Mode::text() const
{
    return QStringLiteral("%1x%2@%3").arg(size.width()).arg(size.height()).arg(hz);
}

Mode Mode::parse(const QString &text)
{
    static const QRegularExpression re(QStringLiteral("^(\\d+)x(\\d+)@(\\d+)$"));
    const auto match = re.match(text.trimmed());
    if (!match.hasMatch()) {
        return {};
    }
    return {QSize(match.captured(1).toInt(), match.captured(2).toInt()), match.captured(3).toInt()};
}

const CodecRow *ModelRow::codecRow(const QString &codec) const
{
    for (const auto &row : codecs) {
        if (row.codec == codec) {
            return &row;
        }
    }
    return nullptr;
}

namespace
{
ModelRow fromJson(const QJsonObject &o)
{
    ModelRow row;
    row.model = o.value(QStringLiteral("md")).toString();
    row.generation = o.value(QStringLiteral("generation")).toString();
    row.shortWords = o.value(QStringLiteral("short")).toString();
    row.video = o.value(QStringLiteral("video")).toBool(true);
    row.source = o.value(QStringLiteral("source")).toString();
    for (const auto &value : o.value(QStringLiteral("codecs")).toArray()) {
        const QJsonObject c = value.toObject();
        CodecRow codec;
        codec.codec = c.value(QStringLiteral("codec")).toString();
        codec.profile = c.value(QStringLiteral("profile")).toString();
        codec.level = c.value(QStringLiteral("level")).toString();
        for (const auto &mode : c.value(QStringLiteral("modes")).toArray()) {
            const Mode m = Mode::parse(mode.toString());
            if (m.isValid()) {
                codec.modes.append(m);
            }
        }
        codec.defaultMode = Mode::parse(c.value(QStringLiteral("default")).toString());
        if (!codec.defaultMode.isValid() && !codec.modes.isEmpty()) {
            codec.defaultMode = codec.modes.first();
        }
        if (!codec.codec.isEmpty() && codec.defaultMode.isValid()) {
            row.codecs.append(codec);
        }
    }
    return row;
}
} // namespace

DeviceTable::DeviceTable(const QString &path)
{
    // the first Chromecast's limits: H.264 High up to level 4.1, 1080p at 30 frames a second (Google's media page);
    // the decision of row 81's review for any model not in the table
    m_unknown.generation = QStringLiteral("not in the table: the first Chromecast's limits");
    m_unknown.shortWords = QStringLiteral("not in the table");
    m_unknown.codecs = {CodecRow{QStringLiteral("h264"),
                                 QStringLiteral("High"),
                                 QStringLiteral("4.1"),
                                 {Mode{QSize(1920, 1080), 30}, Mode{QSize(1280, 720), 60}},
                                 Mode{QSize(1920, 1080), 30}}};
    m_unknown.known = false;
    m_audio.codecs = {QStringLiteral("flac"), QStringLiteral("opus"), QStringLiteral("vorbis"), QStringLiteral("aac")};

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
    const QJsonObject audio = doc.object().value(QStringLiteral("audio")).toObject();
    if (!audio.isEmpty()) {
        m_audio.codecs.clear();
        for (const auto &c : audio.value(QStringLiteral("codecs")).toArray()) {
            m_audio.codecs.append(c.toString());
        }
        const QJsonObject flac = audio.value(QStringLiteral("flac")).toObject();
        m_audio.flacMaxRate = flac.value(QStringLiteral("maxRate")).toInt(96000);
        m_audio.flacBits = flac.value(QStringLiteral("bits")).toInt(24);
    }
    for (const auto &value : doc.object().value(QStringLiteral("models")).toArray()) {
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
