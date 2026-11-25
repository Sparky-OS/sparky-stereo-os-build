// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The device table: what each Cast model (its DNS-SD `md`) plays, as data (/usr/share/sparky-stereo-throw/devices.json).
// Every video codec Google's "Supported Media for Google Cast" lists for a model, with its profile, level and the modes
// it allows, in the order the daemon prefers them.
#pragma once

#include <QList>
#include <QSize>
#include <QString>
#include <QStringList>

namespace Throw
{

struct Mode {
    QSize size;
    int hz = 0;
    bool isValid() const
    {
        return size.isValid() && !size.isEmpty() && hz > 0;
    }
    QString text() const; // 1920x1080@30
    static Mode parse(const QString &text);
    bool operator==(const Mode &other) const
    {
        return size == other.size && hz == other.hz;
    }
};

struct CodecRow {
    QString codec; // h264, hevc, vp9, vp8, av1
    QString profile;
    QString level;
    QList<Mode> modes;
    Mode defaultMode;
    bool allows(const Mode &mode) const
    {
        return modes.contains(mode);
    }
};

struct ModelRow {
    QString model; // the `md` the device announces, compared without case
    QString generation; // what the model name tells, in plain words (the device's page)
    QString shortWords; // the same, short (the list's row)
    bool video = true; // false: a speaker or a group, sound only
    QList<CodecRow> codecs; // preferred first
    QString source; // where the row comes from
    bool known = true; // false: the model is not in the table and the first Chromecast's limits are used
    const CodecRow *codecRow(const QString &codec) const;
};

struct AudioLimits {
    QStringList codecs;
    int flacMaxRate = 96000;
    int flacBits = 24;
};

class DeviceTable
{
public:
    // reads the table; an unreadable table is said (error()) and the built-in first-generation row is used for every model
    explicit DeviceTable(const QString &path = QString());
    ModelRow row(const QString &model) const;
    AudioLimits audio() const
    {
        return m_audio;
    }
    QString error() const
    {
        return m_error;
    }
    QString path() const
    {
        return m_path;
    }

private:
    QList<ModelRow> m_rows;
    ModelRow m_unknown;
    AudioLimits m_audio;
    QString m_error;
    QString m_path;
};

} // namespace Throw
