// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The device table: what each Cast model (its DNS-SD `md`) plays, as data (/usr/share/sparky-stereo-throw/devices.json).
#pragma once

#include <QList>
#include <QSize>
#include <QString>

namespace Throw
{

struct ModelRow {
    QString model; // the `md` the device announces, compared without case
    QString generation; // what the model name tells, in plain words
    bool video = true; // false: an audio-only device or a group, no screen to throw to
    QSize size; // the mode the network screen arrives in
    int refreshHz = 30;
    QString codec; // H264 in this milestone
    QString level; // the highest level the device decodes, as Google lists it
    QString source; // where the row comes from
    bool known = true; // false: the model is not in the table and the first Chromecast's limits are used
};

class DeviceTable
{
public:
    // reads the table; an unreadable table is said (error()) and the built-in first-generation row is used for every model
    explicit DeviceTable(const QString &path = QString());
    ModelRow row(const QString &model) const;
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
    QString m_error;
    QString m_path;
};

} // namespace Throw
