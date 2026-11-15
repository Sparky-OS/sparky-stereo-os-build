// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "camerastore.h"

#include <QSettings>
#include <QStandardPaths>

using namespace Sparky::Camera;

namespace
{
QSettings settings()
{
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("sparky-stereo-camera"), QStringLiteral("cameras"));
}
}

QString Sparky::Camera::cameraKey(const QString &busInfo, const QString &card)
{
    QString key = busInfo + QLatin1Char('|') + card;
    key.replace(QLatin1Char('/'), QLatin1Char('_'));
    key.replace(QLatin1Char('\\'), QLatin1Char('_'));
    return key;
}

CameraChoice Sparky::Camera::loadChoice(const QString &key)
{
    QSettings s = settings();
    CameraChoice c;
    s.beginGroup(key);
    c.packing = s.value(QStringLiteral("packing")).toString();
    if (s.contains(QStringLiteral("format"))) {
        c.hasMode = true;
        c.mode.fourcc = s.value(QStringLiteral("format")).toString();
        c.mode.size = {s.value(QStringLiteral("width")).toInt(), s.value(QStringLiteral("height")).toInt()};
        c.mode.fps = s.value(QStringLiteral("fps")).toDouble();
    }
    s.beginGroup(QStringLiteral("controls"));
    for (const QString &k : s.childKeys()) {
        bool ok = false;
        const quint32 id = k.toUInt(&ok, 10);
        if (ok) {
            c.controls.insert(id, s.value(k).toLongLong());
        }
    }
    s.endGroup();
    s.beginGroup(QStringLiteral("names"));
    for (const QString &k : s.childKeys()) {
        c.controlNames.insert(k.toUInt(), s.value(k).toString());
    }
    s.endGroup();
    s.endGroup();
    return c;
}

void Sparky::Camera::saveChoice(const QString &key, const CameraChoice &c)
{
    QSettings s = settings();
    s.remove(key);
    s.beginGroup(key);
    if (!c.packing.isEmpty()) {
        s.setValue(QStringLiteral("packing"), c.packing);
    }
    if (c.hasMode) {
        s.setValue(QStringLiteral("format"), c.mode.fourcc);
        s.setValue(QStringLiteral("width"), c.mode.size.width);
        s.setValue(QStringLiteral("height"), c.mode.size.height);
        s.setValue(QStringLiteral("fps"), c.mode.fps);
    }
    for (auto it = c.controls.cbegin(); it != c.controls.cend(); ++it) {
        s.setValue(QStringLiteral("controls/%1").arg(it.key()), it.value());
        s.setValue(QStringLiteral("names/%1").arg(it.key()), c.controlNames.value(it.key()));
    }
    s.endGroup();
    s.sync();
}

void Sparky::Camera::forgetChoice(const QString &key)
{
    QSettings s = settings();
    s.remove(key);
    s.sync();
}
